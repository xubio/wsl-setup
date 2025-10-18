#!/usr/bin/env bash
#
# capture_env.sh - Capture a reproducible snapshot of the current WSL2 environment.
# Run this inside your WSL2 instance from a git repo directory.
# All files will be created in the current directory.

set -e

password=$1
if [ "$password" == "" ] ; then
    echo "empty password, you must supply one to encrypt sensitive info"
fi

DATA_DIRS=(
    # Add any custom paths you want to preserve:
    # Example: ~/web /var/www/html ~/scripts
)

TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo "=== Capturing environment as of $TIMESTAMP ==="

# 1. APT package list
echo "--- Capturing installed APT packages ---"
apt-mark showmanual | sort > pkglist.txt
apt list --installed > apt-installed.txt 2>/dev/null || true
git add pkglist.txt apt-installed.txt

# 2. Python packages (system and virtualenvs)
echo "--- Capturing Python packages ---"
if command -v pip3 >/dev/null 2>&1; then
    pip3 freeze > requirements.txt || true
    git add requirements.txt
fi

# 3. Apache configuration (if present)
if [ -d /etc/apache2 ]; then
    echo "--- Archiving Apache configuration ---"
    cp -r /etc/apache2 .
    git add apache2
fi

# 4. System info (for debugging/rebuild context)
echo "--- Capturing system info ---"
{
    echo "Hostname: $(hostname)"
    echo "Distro: $(lsb_release -ds 2>/dev/null || cat /etc/os-release | head -n 1)"
    uname -a
} > system-info.txt
git add system-info.txt

#5. tar up the config files.  These include secrets for git and such, so encrypt the data with supplied password
thisdir=`pwd`
pushd ~/
echo "./.config/gh" > tlist
find . -maxdepth 1 -type f -name ".*" ! -name ".bash_history" -print >> tlist
tar -czf $thisdir/config.tgz -T tlist
rm -f tlist
popd
gpg --batch --yes --passphrase $password --symmetric --cipher-algo AES256 --armor -o config.asc config.tgz
git add config.asc

echo
echo "Environment snapshot complete."
echo "Files saved in current directory:"
echo "You can now commit these files to your git repository."

