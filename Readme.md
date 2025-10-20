## Oohomes rental property financials environment ## repo contains all code to set up a WSL environment for oohomes property financials

-------------------------------------------------------------------------------

# Usage: #

1. Download wsl-install.ps1 on windows machine from:
    https://raw.githubusercontent.com/xubio/wsl-setup/refs/heads/main/wsl-install.ps1
2. Open an Adminstrator powershell
3. Navigate to dir containing downloaded wsl-install.ps1
4. Run wsl-install.ps1

You should end up with a oohomes-ubuntu WSL distribution.  If an existing distro named oohomes-ubuntu is found, the script will abort.  If you intend to replace an exiting repo, remove it first manually by 
>    wsl --unregister oohomes-ubuntu
