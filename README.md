<div align="center">

# Aizen Desktop

**The desktop layer for [aizen](https://github.com/talmetis-labs/aizen) — Tauri v2 · Svelte 5 · no Electron.**

[Install](#install) · [Requirements](#requirements) · [Licence](#licence) · [Releases](https://github.com/talmetis-labs/aizen-desktop-plugin/releases)

</div>

---

Aizen Desktop is the graphical window for the `aizen` coding agent: file tree, editor, hunk-level
diffs, memory brain, personas, MCP servers, and parallel work across several agents. It **does not
bundle the engine** — the app finds the `aizen` binary you already have installed and drives that.

> This is the **distribution** repository. It holds the installers and the
> [Releases](https://github.com/talmetis-labs/aizen-desktop-plugin/releases) only; the source code
> is not here.

## Install

Downloading is open; using is not. The installer only downloads. On first launch the app asks you
to sign in with an Aizen account that **owns the Aizen Desktop plugin** — buy it at
[aizen.talmetis.com](https://aizen.talmetis.com).

```powershell
# Windows (PowerShell 5+)
irm https://raw.githubusercontent.com/talmetis-labs/aizen-desktop-plugin/main/install.ps1 | iex
```

```bash
# Linux / macOS
curl -fsSL https://raw.githubusercontent.com/talmetis-labs/aizen-desktop-plugin/main/install.sh | sh
```

The installer fetches **one file**, places it next to `aizen`, and creates a shortcut. No
toolchain, no Node, no Rust.

| | Install location | Override |
|---|---|---|
| Windows | `%LOCALAPPDATA%\Aizen\aizen-desktop.exe` | `AIZEN_INSTALL` |
| Linux | `~/.aizen/bin/aizen-desktop` (AppImage) | `AIZEN_INSTALL` |
| macOS | `~/Applications/Aizen.app` | `AIZEN_INSTALL` |

`AIZEN_DESKTOP_DOWNLOAD` points either script at a build of your own (a mirror, a staging build)
instead of the latest release.

### Manual download

Every release ships the same set of files; pick one from the
[Releases](https://github.com/talmetis-labs/aizen-desktop-plugin/releases) page.

| Platform | Portable | Installer |
|---|---|---|
| Windows x86_64 | `aizen-desktop-<tag>-windows-x86_64.exe` | `…-windows-x86_64-setup.exe` (NSIS) |
| Linux x86_64 | `aizen-desktop-<tag>-linux-x86_64.AppImage` | `…-linux-x86_64.deb` |
| macOS arm64 | `aizen-desktop-<tag>-macos-aarch64.app.tar.gz` | `…-macos-aarch64.dmg` |

Each platform has a `SHA256SUMS-<platform>.txt` beside its files. Verify before you run:

```bash
shasum -a 256 -c SHA256SUMS-linux-x86_64.txt
```

Builds are not yet code-signed. Windows SmartScreen and macOS Gatekeeper may ask you to confirm
the first launch (on macOS: right-click the app → Open).

## Requirements

- **`aizen` CLI** — the engine this app controls. Install it first:
  `irm https://raw.githubusercontent.com/talmetis-labs/aizen/main/install.ps1 | iex` (Windows) or
  `curl -fsSL https://raw.githubusercontent.com/talmetis-labs/aizen/main/install.sh | sh`
  (Linux / macOS).
- **Windows 10/11:** WebView2 Evergreen Runtime (already present on Windows 11 and on any machine
  with Edge).
- **Linux:** `libwebkit2gtk-4.1` (Ubuntu 22.04 or newer, or equivalent).
- **macOS:** Apple Silicon (arm64). Intel Macs are not supported.

## Licence

The app is sold as a plugin on your Aizen account. There is no key to type:

1. Sign in from the **Account** step of first-run setup (or Settings → Licence). Sign-in opens
   your browser; a password form is available for machines without one.
2. The app asks the server for a licence for **this machine**. It is issued only to an account that
   owns the Aizen Desktop plugin, signed by the server, and bound to this device.
3. The licence is valid for **7 days offline** and renews itself in the background every 12 hours
   while you are online. Signing out returns it.

The number of machines per account is set by your plan; if you hit the limit, remove an old
device at [aizen.talmetis.com](https://aizen.talmetis.com) and try again. The licence lives in
`~/.aizen/desktop/license.json` and is useless on any other machine.

## Update & uninstall

The app checks this repository's Releases for a newer version and tells you when there is one; rerun
the install one-liner to upgrade in place.

To uninstall, delete the binary and its shortcut:

| | Remove |
|---|---|
| Windows | `%LOCALAPPDATA%\Aizen\aizen-desktop.exe` and the Start Menu shortcut (or use *Add or remove programs* if you used the setup installer) |
| Linux | `~/.aizen/bin/aizen-desktop` and `~/.local/share/applications/aizen-desktop.desktop` |
| macOS | `~/Applications/Aizen.app` and the `~/.aizen/bin/aizen-desktop` launcher |

Your settings, sessions, and licence stay in `~/.aizen/`; remove that directory too if you want a
clean slate. The `aizen` CLI is a separate install and is not touched.

## Copyright

See [LICENSE](LICENSE). Aizen Desktop is proprietary software of Talmetis Labs; the right to run it is
tied to the account that bought it. Manage your plan at
[aizen.talmetis.com](https://aizen.talmetis.com).
