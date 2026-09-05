# Aizen Desktop installer for Windows (PowerShell 5+).
#
#   irm https://raw.githubusercontent.com/talmetis-labs/aizen-desktop-plugin/main/install.ps1 | iex
#
# The pack is licensed. This installer will NOT download it until the account it is run under is
# confirmed, by the licence server, to hold a paid entitlement - the same device-code flow the app
# itself uses. On success it writes ~/.aizen/desktop/license.json, so the app you just installed is
# already activated on this machine.
#
# Honest note on what this gate is worth: a check that runs on the user's own machine is friction,
# not a wall. Real enforcement is that the app is useless without a paid, server-issued gateway key.
# For a HARD download gate, host the pack behind the server and set AIZEN_DESKTOP_DOWNLOAD to a URL
# that itself checks the entitlement before streaming the file - this script prefers that URL when
# the licence response carries one.
#
# One file. No toolchain, no Node, no Rust. This is a front-end for the `aizen` CLI - install
# that first: irm https://raw.githubusercontent.com/aizen-stack/aizen/main/install.ps1 | iex

$ErrorActionPreference = 'Stop'

# --- configuration -------------------------------------------------------------------------
$Repo   = 'talmetis-labs/aizen-desktop-plugin'
$Suffix = 'windows-x86_64.exe'
$Dir    = if ($env:AIZEN_INSTALL) { $env:AIZEN_INSTALL } else { Join-Path $env:LOCALAPPDATA 'Aizen' }

# Where the licence server lives, and where a person buys/manages a plan. Overridable so pointing at
# staging is an env var, not an edit. These default to the values compiled into the app; set
# AIZEN_LICENSE_API to your production licence host if it differs.
$LicenseApi  = if ($env:AIZEN_LICENSE_API) { $env:AIZEN_LICENSE_API.TrimEnd('/') } else { 'https://api.aizen.sh' }
$AccountSite = if ($env:AIZEN_ACCOUNT_URL) { $env:AIZEN_ACCOUNT_URL.TrimEnd('/') } else { 'https://aizen.sh' }

# ~/.aizen, the config home the app and core share. AIZEN_HOME overrides it, same as the app.
$AizenHome  = if ($env:AIZEN_HOME) { $env:AIZEN_HOME } else { Join-Path $env:USERPROFILE '.aizen' }
$LicenseDir = Join-Path $AizenHome 'desktop'
$LicensePath = Join-Path $LicenseDir 'license.json'

Write-Host "Aizen Desktop installer" -ForegroundColor Cyan

# --- helpers -------------------------------------------------------------------------------

function New-DeviceId {
    # 16 random bytes as hex - random, not a hardware fingerprint, exactly as the app makes it. The
    # server counts seats by this id; reusing the app's stored id keeps this install on one seat.
    $bytes = New-Object 'System.Byte[]' 16
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    -join ($bytes | ForEach-Object { $_.ToString('x2') })
}

function Get-Store {
    if (Test-Path $LicensePath) {
        try { return Get-Content $LicensePath -Raw | ConvertFrom-Json } catch { }
    }
    return $null
}

function Save-Store($store) {
    New-Item -ItemType Directory -Force $LicenseDir | Out-Null
    $tmp = "$LicensePath.tmp"
    ($store | ConvertTo-Json -Depth 8) | Set-Content -Path $tmp -Encoding utf8
    Move-Item -Force $tmp $LicensePath
}

function Get-TokenIat($token) {
    # `iat` out of the JWS payload, for the clock-rollback high-water mark. No verification here -
    # the app re-verifies against its compiled-in key on first launch; this is only a hint.
    try {
        $p = $token.Split('.')[1].Replace('-', '+').Replace('_', '/')
        switch ($p.Length % 4) { 2 { $p += '==' } 3 { $p += '=' } }
        $json = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p)) | ConvertFrom-Json
        if ($json.iat) { return [uint64]$json.iat }
    } catch { }
    return [uint64]0
}

function Invoke-License($route, $body) {
    # Returns @{ code = <int>; json = <obj|$null> }. A non-2xx is data here, not a thrown error, so
    # 428 "still pending" reads as a state rather than a crash.
    $uri = "$LicenseApi$route"
    try {
        $res = Invoke-WebRequest -Uri $uri -Method Post -ContentType 'application/json' `
            -Body ($body | ConvertTo-Json -Compress) -UseBasicParsing
        $code = [int]$res.StatusCode
    } catch [System.Net.WebException] {
        $resp = $_.Exception.Response
        if (-not $resp) { throw "Could not reach the licence server ($LicenseApi): $($_.Exception.Message)" }
        $code = [int]$resp.StatusCode
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $text = $reader.ReadToEnd()
        $json = $null; if ($text) { try { $json = $text | ConvertFrom-Json } catch { } }
        return @{ code = $code; json = $json }
    }
    $json = $null
    if ($res.Content) { try { $json = $res.Content | ConvertFrom-Json } catch { } }
    return @{ code = $code; json = $json }
}

# --- the gate: prove a paid entitlement before anything is downloaded ----------------------

$store = Get-Store
if (-not $store) { $store = [pscustomobject]@{ device = New-DeviceId; name = $env:COMPUTERNAME; refresh = ''; token = ''; seen = 0 } }
if (-not $store.device) { $store | Add-Member -Force NoteProperty device (New-DeviceId) }
if (-not $store.name)   { $store | Add-Member -Force NoteProperty name $env:COMPUTERNAME }

$entitlement = $null   # the paid entitlement, once we have one
$download    = $null   # a server-gated download URL, if the licence response carries one

# 1) Already activated on this machine? Ask the server if the entitlement still stands.
if ($store.refresh) {
    Write-Host "  checking your licence..."
    $r = Invoke-License '/v1/entitlement/refresh' @{ refresh = $store.refresh; device = $store.device }
    if ($r.code -ge 200 -and $r.code -lt 300 -and $r.json.entitlement) {
        $entitlement = $r.json.entitlement
        if ($r.json.refresh) { $store.refresh = $r.json.refresh }
        if ($r.json.download) { $download = $r.json.download.windows }
        Write-Host "  licence OK" -ForegroundColor Green
    } else {
        Write-Host "  stored licence is no longer valid - re-activating" -ForegroundColor Yellow
    }
}

# 2) Not activated (or lapsed): run the device-code flow. The server only issues an entitlement to a
#    paid account, so reaching a token here IS the purchase check.
if (-not $entitlement) {
    $r = Invoke-License '/v1/device/code' @{
        device = $store.device; name = $store.name; platform = 'windows'; version = 'installer'
    }
    if ($r.code -ge 400 -or -not $r.json.deviceCode) {
        $msg = if ($r.json.message) { $r.json.message } else { "licence server refused the request ($($r.code))" }
        throw "Could not start activation: $msg"
    }
    $deviceCode = $r.json.deviceCode
    $userCode   = $r.json.userCode
    $verifyUrl  = $r.json.verifyUrl
    $interval   = if ($r.json.interval)  { [int]$r.json.interval }  else { 5 }
    $expiresIn  = if ($r.json.expiresIn) { [int]$r.json.expiresIn } else { 900 }

    Write-Host ""
    Write-Host "  To download Aizen Desktop, confirm your purchase:" -ForegroundColor Cyan
    Write-Host "    1. Open:  $verifyUrl"
    Write-Host "    2. Enter code:  $userCode" -ForegroundColor White
    Write-Host "    (no account yet? buy a plan at $AccountSite)" -ForegroundColor DarkGray
    Write-Host ""
    try { Start-Process $verifyUrl | Out-Null } catch { }

    $deadline = (Get-Date).AddSeconds($expiresIn)
    Write-Host -NoNewline "  waiting for approval"
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds $interval
        Write-Host -NoNewline "."
        $p = Invoke-License '/v1/device/token' @{ deviceCode = $deviceCode; device = $store.device }
        if ($p.code -eq 428) { continue }                       # not yet
        if ($p.code -eq 429) {                                   # slow down
            if ($p.json.interval) { $interval = [int]$p.json.interval }
            continue
        }
        if ($p.code -ge 200 -and $p.code -lt 300 -and $p.json.entitlement) {
            $entitlement = $p.json.entitlement
            if ($p.json.refresh)  { $store.refresh = $p.json.refresh }
            if ($p.json.download) { $download = $p.json.download.windows }
            Write-Host ""
            break
        }
        # Anything else is denied/expired.
        Write-Host ""
        $why = if ($p.json.message) { $p.json.message } elseif ($p.json.error) { $p.json.error } else { "code $($p.code)" }
        throw "Activation denied ($why). This account has no plan - buy at $AccountSite, then re-run."
    }
    if (-not $entitlement) { throw "Timed out waiting for approval. Re-run the installer to try again." }
}

# Persist the licence so the app opens already activated.
$store.token = $entitlement
$store.seen  = [Math]::Max([uint64]$store.seen, (Get-TokenIat $entitlement))
try { Save-Store $store; Write-Host "  activated -> $LicensePath" -ForegroundColor Green }
catch { Write-Host "  (could not write $LicensePath : $($_.Exception.Message))" -ForegroundColor Yellow }

Write-Host ""
Write-Host "Licence confirmed. Installing..." -ForegroundColor Cyan

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
    Write-Host "             irm https://raw.githubusercontent.com/aizen-stack/aizen/main/install.ps1 | iex" -ForegroundColor Yellow
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
# A server-gated URL (from the licence response, or AIZEN_DESKTOP_DOWNLOAD) wins: that is the path
# that makes the gate real. Otherwise fall back to the public release asset.
if ($env:AIZEN_DESKTOP_DOWNLOAD) { $download = $env:AIZEN_DESKTOP_DOWNLOAD }

New-Item -ItemType Directory -Force $Dir | Out-Null
$dest = Join-Path $Dir 'aizen-desktop.exe'
$ProgressPreference = 'SilentlyContinue'

if ($download) {
    Write-Host "  downloading (licensed)..."
    # Carry the entitlement so a server-side gate can authorise the stream.
    Invoke-WebRequest $download -OutFile $dest -Headers @{ Authorization = "Bearer $entitlement" }
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
