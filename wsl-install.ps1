# ==============================
# WSL2 Auto-Setup Script
# Run from an Administrator PowerShell:
#   .\wsl-install.ps1
# ==============================

param(
    [string]$DistroName = "oohomes-debian"
)

$ErrorActionPreference = "Stop"

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "ERROR: run this script from an Administrator PowerShell (enabling WSL and writing sudoers both need it)."
    exit 1
}

$pass = Read-Host "Enter password to use for setup_env.sh"
if ([string]::IsNullOrEmpty($pass)) {
    Write-Error "ERROR: no password given. It decrypts config.asc, so the rebuild cannot proceed without it."
    exit 1
}

# --- Ensure WSL is enabled
$wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
$vmFeature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform

$rebootNeeded = $false
if ($wslFeature.State -ne "Enabled") {
    Write-Host "Enabling WSL..."
    dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
    $rebootNeeded = $true
}

if ($vmFeature.State -ne "Enabled") {
    Write-Host "Enabling Virtual Machine Platform..."
    dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
    $rebootNeeded = $true
}

if ($rebootNeeded) {
    Write-Host ""
    Write-Host "WSL features were just enabled; Windows must be restarted before anything else works."
    Write-Host "Reboot, then run this script again."
    exit 1
}

# --- Check if distro exists
# wsl.exe emits UTF-16 text; strip NULs and stray whitespace so the comparison
# cannot silently miss an existing distro.
$existing = @( (wsl --list --quiet 2>$null) -replace "`0", "" |
    ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" } )
if ($existing -contains $DistroName) {
    Write-Error "ERROR: A WSL distro named '$DistroName' already exists. Use 'wsl --unregister $DistroName' first."
    exit 1
}

# --- Install Debian
Write-Host "Installing Debian as '$DistroName'..."
Write-Host "cmd: wsl --install -d Debian --name $DistroName --no-launch"
wsl --install -d Debian --name $DistroName --no-launch
if ($LASTEXITCODE -ne 0) {
    Write-Error "ERROR: 'wsl --install -d Debian --name $DistroName' failed (exit $LASTEXITCODE)."
    exit 1
}

# --- Create non-password user
Write-Host "Creating user 'oohomes'..."
wsl -d $DistroName -- bash -c "adduser --disabled-password --gecos '' oohomes; usermod -aG sudo oohomes"

# --- Configure passwordless sudo for oohomes
# Everything below depends on this: without it apt installs run as oohomes
# without the rights to install anything.
Write-Host "Configuring passwordless sudo for 'oohomes'..."
wsl -d $DistroName -- bash -c "echo 'oohomes ALL=(ALL) NOPASSWD:ALL' | tee /etc/sudoers.d/oohomes && chmod 440 /etc/sudoers.d/oohomes"
if ($LASTEXITCODE -ne 0) {
    Write-Error "ERROR: could not write /etc/sudoers.d/oohomes; the rest of the setup would fail."
    exit 1
}

# --- Set default user
Write-Host "Setting 'oohomes' as default user..."
wsl -d $DistroName -- bash -c "printf '[user]\ndefault=oohomes\n' > /etc/wsl.conf"
# /etc/wsl.conf is only read when the distro instance starts, so restart it
# here: otherwise a plain `wsl -d $DistroName` would land as root.  Every later
# command names its user explicitly, so it does not matter to them.
wsl --terminate $DistroName

# --- Run startup commands directly
Write-Host "Running startup script in \$HOME..."
wsl -d $DistroName -u oohomes -- bash -lc "sudo apt update && sudo apt install -y git"
if ($LASTEXITCODE -ne 0) {
    Write-Error "ERROR: could not install git in '$DistroName' (no network?)."
    exit 1
}
wsl -d $DistroName -u oohomes -- bash -lc "cd; git clone https://github.com/xubio/wsl-setup.git"
if ($LASTEXITCODE -ne 0) {
    Write-Error "ERROR: could not clone https://github.com/xubio/wsl-setup.git (no network, or the command itself failed)."
    exit 1
}

# --- Rebuild the environment
# The password is passed in the WSL environment (WSLENV) so the shell cannot
# word-split it: as an unquoted argument it was silently dropped, and setup_env.sh
# then printed usage and exited before restoring anything.  A quoted argument is
# passed as well, for the case where WSLENV sharing does not reach bash.
#
# `set -o pipefail` matters here: without it the exit status of
# `setup_env.sh ... | tee log` is tee's, so every setup failure looked like a
# success and the distro was left half-built.
$env:SETUP_PASSWORD = $pass
if ([string]::IsNullOrEmpty($env:WSLENV)) {
    $env:WSLENV = "SETUP_PASSWORD"
} elseif ($env:WSLENV -notmatch '(^|:)SETUP_PASSWORD(/|$)') {
    $env:WSLENV = "SETUP_PASSWORD:$env:WSLENV"
}
$passForShell = "'" + $pass.Replace("'", "'\''") + "'"

Write-Host "Configuring the environment (this takes a while; log: ~/wsl-setup.log)..."
wsl -d $DistroName -u oohomes -- bash -lc "set -o pipefail; cd; ./wsl-setup/setup_env.sh $passForShell 2>&1 | tee ~/wsl-setup.log"
$setupExit = $LASTEXITCODE
Remove-Item Env:SETUP_PASSWORD -ErrorAction SilentlyContinue

if ($setupExit -ne 0) {
    Write-Host ""
    Write-Host "--- last 40 lines of ~/wsl-setup.log ---"
    wsl -d $DistroName -u oohomes -- bash -lc "tail -n 40 ~/wsl-setup.log"
    Write-Host ""
    Write-Error "ERROR: setup_env.sh failed (exit $setupExit). '$DistroName' is only partly set up. Fix the cause above, then re-run it with: wsl -d $DistroName -u oohomes -- bash -lc 'cd; ./wsl-setup/setup_env.sh <password>'"
    exit 1
}

# A successful exit can still hide a degraded rebuild (a third-party repository
# that could not be configured, a package that would not install).
# wsl.exe returns UTF-16 text, so the NULs must go before the count is tested --
# otherwise "1" never matches the pattern and the warnings are swallowed.
$warnText = ((wsl -d $DistroName -u oohomes -- bash -lc "grep -c '^warning:' ~/wsl-setup.log 2>/dev/null") -replace "`0", "").Trim()
if ($warnText -match '^\d+$' -and [int]$warnText -gt 0) {
    Write-Host ""
    Write-Warning "setup_env.sh reported $warnText warning(s); the rebuild may be missing something:"
    wsl -d $DistroName -u oohomes -- bash -lc "grep '^warning:' ~/wsl-setup.log"
}

Write-Host ""
Write-Host "Default user: oohomes (no password)"
Write-Host "Run with: wsl -d $DistroName"
