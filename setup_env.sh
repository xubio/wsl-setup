#!/usr/bin/env bash
#
# setup_env.sh - Rebuild WSL2 environment from captured backup
# Usage: ./setup_env.sh password
# Run this inside a fresh WSL2 distro from the git repo directory containing the backup files.

set -e


PASSWORD="${1:-}"
if [ -z "$PASSWORD" ]; then
    echo "Usage: $0 password"
    exit 1
fi
echo "some portions of this script must run as root.  Need your sudo password"
sudo echo "sudo access available, proceeding"

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
cd "$SCRIPT_DIR"

# Update system
echo "=== Updating system ==="
sudo apt update
sudo apt upgrade -y

# ---------------------------------------------------------------------------
# Third-party apt repositories.
# These MUST be configured before pkglist.txt is installed: that list contains
# `firefox` (available only from the Mozilla repo) and `nodejs` (nodesource;
# Debian ships an older release under the same name). On a fresh distro apt
# would fail as a whole and, under `set -e`, abort the entire rebuild.
# ---------------------------------------------------------------------------
echo "=== Adding third-party apt repositories ==="

# Mozilla (firefox)
sudo install -d -m 0755 /etc/apt/keyrings
wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O- | sudo tee /etc/apt/keyrings/packages.mozilla.org.asc > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" | sudo tee /etc/apt/sources.list.d/mozilla.list > /dev/null
echo ' Package: * Pin: origin packages.mozilla.org Pin-Priority: 1000 ' | sudo tee /etc/apt/preferences.d/mozilla > /dev/null

# NodeSource (nodejs 22.x)
wget -qO- https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/nodesource.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list > /dev/null
printf 'Package: nodejs\nPin: origin deb.nodesource.com\nPin-Priority: 600\n' | sudo tee /etc/apt/preferences.d/nodejs > /dev/null

sudo apt update

# Install packages from pkglist.txt
if [ -f pkglist.txt ] ; then
    echo "=== Installing APT packages ==="
    # One unavailable name should not abort the whole rebuild (the config
    # restore below is more important than any single package).
    sudo apt install -y $(cat pkglist.txt) || {
        echo "warning: batch install failed, retrying package by package" >&2
        while read -r pkg; do
            [ -n "$pkg" ] || continue
            sudo apt install -y "$pkg" || echo "warning: could not install $pkg" >&2
        done < pkglist.txt
    }
else
    echo "Warning: pkglist.txt not found, skipping APT packages."
fi
sudo apt install -y python3-pip

# Python packages pip-installed into the user site by capture_env.sh.
if [ -f requirements.txt ]; then
    echo "=== Installing Python packages ==="
    pip3 install --user --break-system-packages -r requirements.txt \
        || echo "warning: some pip packages failed to install" >&2
fi

# Decrypt and extract config archive
if [ -f config.asc ]; then
    echo "=== Decrypting and extracting home config ==="
    gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 \
        -d -o config.tgz config.asc 3< <(printf '%s\n' "$PASSWORD")
    tar xzf config.tgz -C ~
    rm -f config.tgz
else
    echo "No config.asc found, skipping config restore."
fi

pushd ~/
# Install gecko driver
wget https://github.com/mozilla/geckodriver/releases/download/v0.36.0/geckodriver-v0.36.0-linux64.tar.gz
tar -xzvf geckodriver-v0.36.0-linux64.tar.gz
sudo mv geckodriver /usr/local/bin
rm -f geckodriver-v0.36.0-linux64.tar.gz

# Get ledger repo:
gh repo clone oohomes_ledger
pip3 install -r oohomes_ledger/requirements.txt --break-system-packages
popd

ln -s /mnt/c/Users/bjoos/Documents/NextCloud/Real\ Estate/Invoices $HOME/oohomes_ledger/invoices
ln -s /mnt/c/Users/bjoos/Documents/NextCloud/Real\ Estate/Leases $HOME/oohomes_ledger/leases
echo "=== Environment rebuild complete ==="
echo "You may need to log out and back in for changes to dotfiles and shell configs to take effect."

