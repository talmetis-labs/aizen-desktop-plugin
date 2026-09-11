# Aizen Desktop installer for Windows (PowerShell 5+).
#
#   irm https://raw.githubusercontent.com/talmetis-labs/aizen-desktop-plugin/main/install.ps1 | iex
#
# Downloading is open; using is not. This script fetches the latest build and puts it next to
# `aizen`. The app then checks, when it opens, that the Aizen account you sign in with owns the
# Aizen Desktop plugin - the licence is issued to that account and to this machine, signed by the
# server, and the window does not work without it. Nothing is checked here because nothing here
# could be trusted: a check that runs on the user's own machine is friction, not a wall. The wall
# is the server that refuses to issue a licence to an account that has not paid.
#
# One file. No toolchain, no Node, no Rust. This is a front-end for the `aizen` CLI - install
# that first: irm https://raw.githubusercontent.com/talmetis-labs/aizen/main/install.ps1 | iex

$ErrorActionPreference = 'Stop'

# --- configuration -------------------------------------------------------------------------
$Repo   = 'talmetis-labs/aizen-desktop-plugin'
$Suffix = 'windows-x86_64.exe'
$Dir    = if ($env:AIZEN_INSTALL) { $env:AIZEN_INSTALL } else { Join-Path $env:LOCALAPPDATA 'Aizen' }

Write-Host "Aizen Desktop installer" -ForegroundColor Cyan

# --- the engine has to exist; this app only drives it -------------------------------------
$core = Join-Path $Dir 'aizen.exe'
if (-not (Test-Path $core)) {
    $onPath = Get-Command aizen -ErrorAction SilentlyContinue
    if ($onPath) { $core = $onPath.Source } else { $core = $null }
}
if ($core) {
    Write-Host ("  core:      {0}" -f (& $core --version 2>$null | Select-Object -First 1))
} else {
    Write-Host "  core:      not found" -ForegroundColor Yellow
    Write-Host "             Aizen Desktop drives the aizen CLI; install it first:" -ForegroundColor Yellow
    Write-Host "             irm https://raw.githubusercontent.com/talmetis-labs/aizen/main/install.ps1 | iex" -ForegroundColor Yellow
}

# --- WebView2: present on Windows 11 and any machine with Edge, but check rather than crash --
$wv2Keys = @(
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
    'HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
    'HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
)
$wv2 = $wv2Keys | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($wv2) {
    Write-Host ("  webview2:  {0}" -f (Get-ItemProperty $wv2).pv)
} else {
    Write-Host "  webview2:  not found" -ForegroundColor Yellow
    Write-Host "             Install the Evergreen Runtime once:" -ForegroundColor Yellow
    Write-Host "             https://developer.microsoft.com/microsoft-edge/webview2/" -ForegroundColor Yellow
}

# --- fetch ---------------------------------------------------------------------------------
# AIZEN_DESKTOP_DOWNLOAD points a build at a file of your own (a mirror, a staging build);
# otherwise the newest release asset is taken from the public repo.
New-Item -ItemType Directory -Force $Dir | Out-Null
$dest = Join-Path $Dir 'aizen-desktop.exe'
$ProgressPreference = 'SilentlyContinue'

if ($env:AIZEN_DESKTOP_DOWNLOAD) {
    Write-Host "  downloading from AIZEN_DESKTOP_DOWNLOAD..."
    Invoke-WebRequest $env:AIZEN_DESKTOP_DOWNLOAD -OutFile $dest
} else {
    $rel = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest" -Headers @{ 'User-Agent' = 'aizen-desktop-installer' }
    $asset = $rel.assets | Where-Object { $_.name -like "*$Suffix" } | Select-Object -First 1
    if (-not $asset) { throw "No Windows asset (*$Suffix) found in release $($rel.tag_name)." }
    Write-Host ("  {0}  {1}  ({2:N1} MB)" -f $rel.tag_name, $asset.name, ($asset.size / 1MB))
    Invoke-WebRequest $asset.browser_download_url -OutFile $dest
}

# --- PATH (idempotent; usually already done by the core installer) --------------------------
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (($userPath -split ';') -notcontains $Dir) {
    [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ';' + $Dir), 'User')
    Write-Host "  added $Dir to your PATH"
}
if (($env:Path -split ';') -notcontains $Dir) { $env:Path = "$env:Path;$Dir" }

# --- Start Menu shortcut, so it is findable without a terminal ------------------------------
try {
    $programs = [Environment]::GetFolderPath('Programs')
    $lnk = Join-Path $programs 'Aizen.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $sc = $shell.CreateShortcut($lnk)
    $sc.TargetPath = $dest
    $sc.WorkingDirectory = $Dir
    $sc.Description = 'Aizen Desktop'
    $sc.Save()
    Write-Host "  Start Menu shortcut: $lnk"
} catch {
    Write-Host "  (could not create the Start Menu shortcut: $($_.Exception.Message))" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Aizen Desktop installed -> $dest" -ForegroundColor Green
Write-Host "Launch it from the Start Menu, or run:  aizen-desktop" -ForegroundColor Yellow
Write-Host "On first run, sign in with the Aizen account that owns the Aizen Desktop plugin." -ForegroundColor DarkGray
