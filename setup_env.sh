#!/usr/bin/env bash
#
# setup_from_env.sh - Rebuild WSL2 environment from captured backup
# Usage: ./setup_from_env.sh password
# Run this inside a fresh WSL2 distro from the git repo directory containing the backup files.

set -e

PASSWORD="$1"
if [ -z "$PASSWORD" ]; then
    echo "Usage: $0 password"
    exit 1
fi
echo "some portions of this script must run as root.  Need your sudo password"
sudo echo "sudo access available, proceeding"

# 1. Update system
echo "=== Updating system ==="
sudo apt update
sudo apt upgrade -y

# 2. Install packages from pkglist.txt
if [ -f pkglist.txt ]; then
    pkgs=`cat pkglist.txt`
    for pkg in $pkgs ; do
        echo "=== APT: Installing $pkg ==="
        sudo apt install -y $pkg
    done
else
    echo "Warning: pkglist.txt not found, skipping APT packages."
fi
sudo apt install -y python3-pip

# 4. Restore Apache configuration
if [ -d apache2 ]; then
    echo "=== Restoring Apache configuration ==="
    sudo cp -r apache2 /etc/
    sudo systemctl restart apache2 || true
else
    echo "No apache2 directory found, skipping Apache restore."
fi

# 5. Decrypt and extract config archive
if [ -f config.asc ]; then
    echo "=== Decrypting and extracting config.tgz ==="
    gpg --batch --yes --passphrase "$PASSWORD" -d -o config.tgz config.asc
    tar xzf config.tgz -C ~
    rm -f config.tgz
else
    echo "No config.asc found, skipping config restore."
fi

# 6. Restore system info note (optional)
if [ -f system-info.txt ]; then
    echo "=== System info snapshot available ==="
    cat system-info.txt
fi

# Get ledger repo:
gh repo clone oohomes_ledger
pip3 install -r oohomes_ledger/requirements.txt --break-system-packages
sudo ln -s $HOME/oohomes_ledger /var/www/oohomes

sudo apachectl start 
echo "=== Environment rebuild complete ==="
echo "You may need to log out and back in for changes to dotfiles and shell configs to take effect."
