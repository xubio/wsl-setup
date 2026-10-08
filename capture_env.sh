#!/usr/bin/env bash
#
# capture_env.sh - Capture a reproducible snapshot of the current WSL2 environment.
# Run this inside your WSL2 instance from the root of this git repo.
# pkglist.txt, apt-installed.txt, requirements.txt, system-info.txt and the
# encrypted config.asc are (re)written in the current directory; commit them
# afterwards so setup_env.sh can rebuild a fresh distro from them.
#
# Usage: ./capture_env.sh <password>
#
# The password is used only to encrypt config.asc. It is never written to disk,
# is not left in the tar archive, and is not passed on the command line of any
# child process.

set -euo pipefail

password=${1:-}
if [ -z "$password" ]; then
    echo "empty password, you must supply one to encrypt sensitive info" >&2
    exit 1
fi

# Extra directories (relative to $HOME) whose contents are worth preserving
# inside the encrypted archive. Add your own here.
DATA_DIRS=(
    bin
    ai
    mcp
)

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
thisdir=$(pwd)

echo "=== Capturing environment as of $TIMESTAMP ==="

# 1. APT packages
echo "--- Capturing installed APT packages ---"
# Manually installed set: this is what setup_env.sh feeds back to apt.
apt-mark showmanual | sort > pkglist.txt
# Full installed set, machine readable (kept for the record / auditing drift).
dpkg-query -W -f='${Package}\t${Version}\n' | sort > apt-installed.txt

# 2. Python packages installed by pip into the user site.
#    Debian-packaged python3-* modules live in /usr/lib/python3/dist-packages and
#    are already covered by pkglist.txt, so only the pip-installed user site is
#    recorded here -- that is exactly the set that needs --break-system-packages.
echo "--- Capturing Python packages ---"
if command -v pip3 >/dev/null 2>&1; then
    if ! pip3 freeze --user > requirements.txt; then
        echo "warning: pip3 freeze --user failed, dropping requirements.txt" >&2
        rm -f requirements.txt
    fi
fi

# 3. Machine identity (regenerated every run so it cannot go stale)
echo "--- Capturing system info ---"
{
    echo "Hostname: $(hostname)"
    # shellcheck disable=SC1091
    echo "Distro: $(. /etc/os-release && echo "$PRETTY_NAME")"
    echo "WSL distro: ${WSL_DISTRO_NAME:-unknown}"
    uname -a
    echo "Captured: $TIMESTAMP"
} > system-info.txt

# 4. Archive the home-directory config. This contains secrets (git credentials,
#    ssh keys, gh tokens), so the tar stream is piped straight into gpg -- no
#    plaintext intermediate archive is ever written to disk.
echo "--- Collecting files for encrypted archive ---"
tlist=$(mktemp)
tmpasc=$(mktemp "$thisdir/.config.asc.XXXXXX")
trap 'rm -f "$tlist" "$tmpasc"' EXIT

pushd ~/ >/dev/null

# Whole-directory captures, skipped if absent.
for d in .config "${DATA_DIRS[@]}"; do
    if [ -e "$d" ]; then
        printf '%s\n' "$d" >> "$tlist"
    fi
done
# Dotfiles in the home directory.
find . -maxdepth 1 -type f -name ".*" ! -name ".bash_history" -print >> "$tlist"
# SSH material (keys, config, known_hosts).
if [ -d .ssh ]; then
    find .ssh -print >> "$tlist"
fi

cat "$tlist"
echo "--- Encrypting to config.asc ---"
tar -czf - -T "$tlist" | gpg --batch --yes --pinentry-mode loopback \
    --passphrase-fd 3 --symmetric --cipher-algo AES256 --armor \
    -o "$tmpasc" 3< <(printf '%s\n' "$password")

popd >/dev/null

# Only replace the committed archive once encryption has fully succeeded.
mv -f "$tmpasc" "$thisdir/config.asc"

echo
echo "Environment snapshot complete."
echo "Files saved in current directory:"
echo "  pkglist.txt apt-installed.txt requirements.txt system-info.txt config.asc"
echo "You can now commit these files to your git repository."
