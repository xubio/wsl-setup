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

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
cd $SCRIPT_DIR

# Update system
echo "=== Updating system ==="
sudo apt update
sudo apt upgrade -y

# Install packages from pkglist.txt
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

# Restore Apache configuration
if [ -d apache2 ]; then
    echo "=== Restoring Apache configuration ==="
    sudo cp -r apache2 /etc/
    sudo a2dissite 000-default.conf
    sudo systemctl restart apache2 || true
else
    echo "No apache2 directory found, skipping Apache restore."
fi

# Decrypt and extract config archive
if [ -f config.asc ]; then
    echo "=== Decrypting and extracting config.tgz ==="
    gpg --batch --yes --passphrase "$PASSWORD" -d -o config.tgz config.asc
    tar xzf config.tgz -C ~
    rm -f config.tgz
else
    echo "No config.asc found, skipping config restore."
fi

#Install firefox
sudo install -d -m 0755 /etc/apt/keyrings
wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O-  | sudo tee /etc/apt/keyrings/packages.mozilla.org.asc > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" | sudo tee -a /etc/apt/sources.list.d/mozilla.list > /dev/null
echo ' Package: * Pin: origin packages.mozilla.org Pin-Priority: 1000 ' | sudo tee /etc/apt/preferences.d/mozilla
sudo apt-get update && sudo apt-get install firefox

pushd ~/
# Install gecko driver
wget https://github.com/mozilla/geckodriver/releases/download/v0.36.0/geckodriver-v0.36.0-linux64.tar.gz
tar -xzvf geckodriver-v0.36.0-linux64.tar.gz
sudo mv geckodriver /usr/local/bin

# Get ledger repo:
gh repo clone oohomes_ledger
pip3 install -r oohomes_ledger/requirements.txt --break-system-packages
sudo ln -s $HOME/oohomes_ledger /var/www/oohomes
popd

# apache will need access to html files
chmod a+rx $HOME
chmod a+rx $HOME/oohomes_ledger
chmod a+rx $HOME/oohomes_ledger/html
touch $HOME/oohomes_ledger/html/.sessions.json
chmod a+w $HOME/oohomes_ledger/html/.sessions.json

ln -s /mnt/c/Users/bjoos/Documents/NextCloud/Real\ Estate/Invoices $HOME/oohomes_ledger/invoices
ln -s /mnt/c/Users/bjoos/Documents/NextCloud/Real\ Estate/Leases $HOME/oohomes_ledger/leases
echo "=== Environment rebuild complete ==="
echo "You may need to log out and back in for changes to dotfiles and shell configs to take effect."

