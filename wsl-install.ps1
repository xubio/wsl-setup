# ==============================
# WSL2 Auto-Setup Script
# ==============================

param(
    [string]$DistroName = "oohomes-debian"
)
$pass = Read-Host "Enter password to use for setup_env.sh"

# --- Ensure WSL is enabled
$wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
$vmFeature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform

if ($wslFeature.State -ne "Enabled") {
    Write-Host "Enabling WSL..."
    dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
}

if ($vmFeature.State -ne "Enabled") {
    Write-Host "Enabling Virtual Machine Platform..."
    dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
}

# --- Check if distro exists
$existing = wsl --list --quiet
if ($existing -contains $DistroName) {
    Write-Error "ERROR: A WSL distro named '$DistroName' already exists. Use 'wsl --unregister $DistroName' first."
    exit 1
}

# --- Install Ubuntu 22.04
Write-Host "Installing Ubuntu 24.04 as '$DistroName'..."
Write-Host "cmd: wsl --install -d Debian --name $DistroName --no-launch"
wsl --install -d Ubuntu-24.04 --name $DistroName --no-launch

# --- Create non-password user
Write-Host "Creating user 'oohomes'..."
wsl -d $DistroName -- bash -c "adduser --disabled-password --gecos '' oohomes; usermod -aG sudo oohomes"

# --- Configure passwordless sudo for oohomes
Write-Host "Configuring passwordless sudo for 'oohomes'..."
wsl -d $DistroName -- bash -c "echo 'oohomes ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/oohomes && sudo chmod 440 /etc/sudoers.d/oohomes"

# --- Set default user
Write-Host "Setting 'oohomes' as default user..."
$wslConf = "[user]`ndefault=oohomes"
wsl -d $DistroName -- bash -c "echo '$wslConf' > /etc/wsl.conf"

# --- Run startup commands directly
Write-Host "Running startup script in \$HOME..."
wsl -d $DistroName -u oohomes -- bash -lc "cd; git clone https://github.com/xubio/wsl-setup.git"
wsl -d $DistroName -u oohomes -- bash -lc "cd; ~/wsl-setup/setup_env.sh $pass"

Write-Host ""
Write-Host "Default user: oohomes (no password)"
Write-Host "Run with: wsl -d $DistroName"
