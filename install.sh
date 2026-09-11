#!/bin/sh
# Aizen Desktop installer for Linux and macOS.
#
#   curl -fsSL https://raw.githubusercontent.com/talmetis-labs/aizen-desktop-plugin/main/install.sh | sh
#
# Downloading is open; using is not. This script fetches the latest build and puts it next to
# `aizen`. The app then checks, when it opens, that the Aizen account you sign in with owns the
# Aizen Desktop plugin — the licence is issued to that account and to this machine, signed by the
# server, and the window does not work without it. Nothing is checked here because nothing here
# could be trusted: a check on the user's own machine is friction, not a wall. The wall is the
# server that refuses to issue a licence to an account that has not paid.
#
# This is a front-end for the `aizen` CLI. Install that first:
#   curl -fsSL https://raw.githubusercontent.com/talmetis-labs/aizen/main/install.sh | sh
set -eu

repo="talmetis-labs/aizen-desktop-plugin"

os="$(uname -s)"
arch="$(uname -m)"
case "$os" in
  Linux)  plat="linux-x86_64.AppImage" ;;
  Darwin)
    case "$arch" in
      arm64 | aarch64) plat="macos-aarch64.app.tar.gz" ;;
      *) echo "aizen-desktop: Apple Silicon (arm64) only; got $arch" >&2; exit 1 ;;
    esac ;;
  *) echo "aizen-desktop: unsupported OS: $os (use install.ps1 on Windows)" >&2; exit 1 ;;
esac

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
  echo "          curl -fsSL https://raw.githubusercontent.com/talmetis-labs/aizen/main/install.sh | sh" >&2
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

# --- resolve the download URL: AIZEN_DESKTOP_DOWNLOAD (a mirror, a staging build) wins; else the
#     newest release asset from the public repo --------------------------------------------------
download="${AIZEN_DESKTOP_DOWNLOAD:-}"
if [ -z "$download" ]; then
  api="https://api.github.com/repos/$repo/releases/latest"
  download="$(curl -fsSL "$api" | grep -o "https://github.com/[^\"]*aizen-desktop-[^\"]*${plat}" | head -1)"
  if [ -z "$download" ]; then
    echo "aizen-desktop: no release asset for '$plat' yet (still building?) -- see $api" >&2
    exit 1
  fi
fi

echo "Downloading $(basename "$download") ..."

if [ "$os" = "Linux" ]; then
  dest="$dir/aizen-desktop"
  curl -fsSL "$download" -o "$dest"
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
  curl -fsSL "$download" -o "$tmpd/aizen.app.tar.gz"
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
echo "On first run, sign in with the Aizen account that owns the Aizen Desktop plugin."
