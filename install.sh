#!/bin/sh
# Aizen Desktop installer for Linux and macOS.
#
#   curl -fsSL https://raw.githubusercontent.com/talmetis-labs/aizen-desktop-plugin/main/install.sh | sh
#
# The pack is licensed. This installer will NOT download it until the licence server confirms the
# account it is run under holds a paid entitlement — the same device-code flow the app itself uses.
# On success it writes ~/.aizen/desktop/license.json, so the app is already activated on this machine.
#
# Honest note: a check on the user's own machine is friction, not a wall. Real enforcement is that
# the app is useless without a paid, server-issued gateway key. For a HARD download gate, host the
# pack behind the server and set AIZEN_DESKTOP_DOWNLOAD to a URL that checks the entitlement before
# streaming — this script prefers that URL and sends the entitlement as a bearer token.
#
# This is a front-end for the `aizen` CLI. Install that first:
#   curl -fsSL https://raw.githubusercontent.com/aizen-stack/aizen/main/install.sh | sh
set -eu

repo="talmetis-labs/aizen-desktop-plugin"
license_api="${AIZEN_LICENSE_API:-https://api.aizen.sh}"; license_api="${license_api%/}"
account_site="${AIZEN_ACCOUNT_URL:-https://aizen.sh}"; account_site="${account_site%/}"
aizen_home="${AIZEN_HOME:-$HOME/.aizen}"
license_dir="$aizen_home/desktop"
license_path="$license_dir/license.json"

os="$(uname -s)"
arch="$(uname -m)"
case "$os" in
  Linux)  plat_os="linux"; plat="linux-x86_64.AppImage" ;;
  Darwin)
    plat_os="macos"
    case "$arch" in
      arm64 | aarch64) plat="macos-aarch64.app.tar.gz" ;;
      *) echo "aizen-desktop: Apple Silicon (arm64) only; got $arch" >&2; exit 1 ;;
    esac ;;
  *) echo "aizen-desktop: unsupported OS: $os (use install.ps1 on Windows)" >&2; exit 1 ;;
esac

# --- tiny JSON readers for flat responses (top-level "key":"str" / "key":num) ---------------
jstr() { sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1; }
jnum() { sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -1; }

new_device() { head -c 16 /dev/urandom 2>/dev/null | od -An -tx1 | tr -d ' \n'; }

# post_json ROUTE BODY -> sets HTTP_CODE and HTTP_BODY
post_json() {
  _tmp="$(mktemp)"
  HTTP_CODE="$(curl -s -o "$_tmp" -w '%{http_code}' -H 'Content-Type: application/json' \
    -X POST --data "$2" "$license_api$1" 2>/dev/null || echo 000)"
  HTTP_BODY="$(cat "$_tmp")"; rm -f "$_tmp"
}

# --- the gate: prove a paid entitlement before anything is downloaded -----------------------
device=""; refresh=""
if [ -f "$license_path" ]; then
  device="$(jstr device < "$license_path" || true)"
  refresh="$(jstr refresh < "$license_path" || true)"
fi
[ -n "$device" ] || device="$(new_device)"
name="$(hostname 2>/dev/null || echo aizen)"

entitlement=""
download="${AIZEN_DESKTOP_DOWNLOAD:-}"

# 1) Already activated? Ask the server whether the entitlement still stands.
if [ -n "$refresh" ]; then
  echo "  checking your licence..."
  post_json /v1/entitlement/refresh "{\"refresh\":\"$refresh\",\"device\":\"$device\"}"
  if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
    entitlement="$(printf '%s' "$HTTP_BODY" | jstr entitlement)"
    nr="$(printf '%s' "$HTTP_BODY" | jstr refresh)"; [ -n "$nr" ] && refresh="$nr"
  fi
  if [ -n "$entitlement" ]; then echo "  licence OK"; else echo "  stored licence invalid — re-activating"; fi
fi

# 2) Not activated (or lapsed): device-code flow. Reaching a token here IS the purchase check.
if [ -z "$entitlement" ]; then
  post_json /v1/device/code "{\"device\":\"$device\",\"name\":\"$name\",\"platform\":\"$plat_os\",\"version\":\"installer\"}"
  device_code="$(printf '%s' "$HTTP_BODY" | jstr deviceCode)"
  if [ "$HTTP_CODE" -ge 400 ] || [ -z "$device_code" ]; then
    msg="$(printf '%s' "$HTTP_BODY" | jstr message)"; [ -n "$msg" ] || msg="HTTP $HTTP_CODE"
    echo "aizen-desktop: could not start activation: $msg" >&2; exit 1
  fi
  user_code="$(printf '%s' "$HTTP_BODY" | jstr userCode)"
  verify_url="$(printf '%s' "$HTTP_BODY" | jstr verifyUrl)"
  interval="$(printf '%s' "$HTTP_BODY" | jnum interval)"; [ -n "$interval" ] || interval=5
  expires="$(printf '%s' "$HTTP_BODY" | jnum expiresIn)"; [ -n "$expires" ] || expires=900

  echo ""
  echo "  To download Aizen Desktop, confirm your purchase:"
  echo "    1. Open:  $verify_url"
  echo "    2. Enter code:  $user_code"
  echo "    (no account yet? buy a plan at $account_site)"
  echo ""
  if command -v open >/dev/null 2>&1; then open "$verify_url" >/dev/null 2>&1 || true
  elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$verify_url" >/dev/null 2>&1 || true; fi

  waited=0
  printf "  waiting for approval"
  while [ "$waited" -lt "$expires" ]; do
    sleep "$interval"; waited=$((waited + interval)); printf "."
    post_json /v1/device/token "{\"deviceCode\":\"$device_code\",\"device\":\"$device\"}"
    if [ "$HTTP_CODE" = "428" ]; then continue; fi
    if [ "$HTTP_CODE" = "429" ]; then
      ni="$(printf '%s' "$HTTP_BODY" | jnum interval)"; [ -n "$ni" ] && interval="$ni"; continue
    fi
    if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
      entitlement="$(printf '%s' "$HTTP_BODY" | jstr entitlement)"
      nr="$(printf '%s' "$HTTP_BODY" | jstr refresh)"; [ -n "$nr" ] && refresh="$nr"
      if [ -n "$entitlement" ]; then echo ""; break; fi
    fi
    echo ""
    why="$(printf '%s' "$HTTP_BODY" | jstr message)"; [ -n "$why" ] || why="HTTP $HTTP_CODE"
    echo "aizen-desktop: activation denied ($why). This account has no plan — buy at $account_site, then re-run." >&2
    exit 1
  done
  [ -n "$entitlement" ] || { echo ""; echo "aizen-desktop: timed out waiting for approval." >&2; exit 1; }
fi

# Persist the licence so the app opens already activated.
mkdir -p "$license_dir"
old_seen=0
[ -f "$license_path" ] && old_seen="$(jnum seen < "$license_path" || echo 0)"
[ -n "$old_seen" ] || old_seen=0
umask 077
tmp="$license_path.tmp"
printf '{\n  "device": "%s",\n  "name": "%s",\n  "refresh": "%s",\n  "token": "%s",\n  "seen": %s\n}\n' \
  "$device" "$name" "$refresh" "$entitlement" "$old_seen" > "$tmp" && mv -f "$tmp" "$license_path"
echo "  activated -> $license_path"

echo ""
echo "Licence confirmed. Installing..."

dir="${AIZEN_INSTALL:-$HOME/.aizen}/bin"
mkdir -p "$dir"

# --- the engine has to exist; this app only drives it ---------------------------------------
if [ -x "$dir/aizen" ]; then
  echo "core:     $("$dir/aizen" --version 2>/dev/null | head -1)"
elif command -v aizen >/dev/null 2>&1; then
  echo "core:     $(aizen --version 2>/dev/null | head -1)"
else
  echo "core:     not found" >&2
  echo "          Aizen Desktop drives the aizen CLI; install it first:" >&2
  echo "          curl -fsSL https://raw.githubusercontent.com/aizen-stack/aizen/main/install.sh | sh" >&2
fi

# --- Linux needs a webkit runtime; say so instead of failing at launch -----------------------
if [ "$os" = "Linux" ]; then
  if ! ldconfig -p 2>/dev/null | grep -q 'libwebkit2gtk-4\.1'; then
    echo "runtime:  libwebkit2gtk-4.1 not found" >&2
    echo "          Debian/Ubuntu: sudo apt install libwebkit2gtk-4.1-0" >&2
    echo "          Fedora:        sudo dnf install webkit2gtk4.1" >&2
    echo "          Arch:          sudo pacman -S webkit2gtk-4.1" >&2
  fi
fi

# --- resolve the download URL: a server-gated URL wins; else the public release asset --------
gated=1
if [ -z "$download" ]; then
  gated=0
  api="https://api.github.com/repos/$repo/releases/latest"
  download="$(curl -fsSL "$api" | grep -o "https://github.com/[^\"]*aizen-desktop-[^\"]*${plat}" | head -1)"
  if [ -z "$download" ]; then
    echo "aizen-desktop: no release asset for '$plat' yet (still building?) -- see $api" >&2
    exit 1
  fi
fi

# dl DEST URL — sends the entitlement as a bearer token only for a server-gated URL, so a
# server-side gate can authorise the stream. The public release needs no header.
dl() {
  if [ "$gated" = "1" ]; then
    curl -fsSL -H "Authorization: Bearer $entitlement" "$2" -o "$1"
  else
    curl -fsSL "$2" -o "$1"
  fi
}

echo "Downloading $(basename "$download") ..."

if [ "$os" = "Linux" ]; then
  dest="$dir/aizen-desktop"
  dl "$dest" "$download"
  chmod +x "$dest"

  apps="$HOME/.local/share/applications"
  mkdir -p "$apps"
  cat > "$apps/aizen-desktop.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Aizen
Comment=Desktop front-end for the Aizen coding agent
Exec=$dest
Terminal=false
Categories=Development;IDE;
StartupWMClass=Aizen
EOF
  update-desktop-database "$apps" >/dev/null 2>&1 || true
  echo "aizen-desktop installed -> $dest"
else
  appdir="$HOME/Applications"
  mkdir -p "$appdir"
  tmpd="$(mktemp -d)"
  dl "$tmpd/aizen.app.tar.gz" "$download"
  rm -rf "$appdir/Aizen.app"
  tar -xzf "$tmpd/aizen.app.tar.gz" -C "$appdir"
  rm -rf "$tmpd"
  # The bundle is unsigned, so clear the quarantine flag the download added.
  xattr -dr com.apple.quarantine "$appdir/Aizen.app" 2>/dev/null || true

  dest="$dir/aizen-desktop"
  printf '#!/bin/sh\nexec open -a "%s/Aizen.app" "$@"\n' "$appdir" > "$dest"
  chmod +x "$dest"
  echo "aizen-desktop installed -> $appdir/Aizen.app"
fi

# PATH hint (don't edit the user's profile silently).
case ":$PATH:" in
  *":$dir:"*) : ;;
  *)
    echo ""
    echo "Add it to your PATH (append to ~/.bashrc or ~/.zshrc):"
    echo "    export PATH=\"$dir:\$PATH\""
    ;;
esac
echo "Then run:  aizen-desktop"
