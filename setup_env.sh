#!/usr/bin/env bash
#
# setup_env.sh - Rebuild WSL2 environment from captured backup
# Usage: ./setup_env.sh password
# Run this inside a fresh WSL2 distro from the git repo directory containing the backup files.

set -e


# Password: $SETUP_PASSWORD takes precedence (wsl-install.ps1 passes it through
# the WSL environment, which keeps it off the command line); the positional
# argument is the documented interface and the fallback.
PASSWORD="${SETUP_PASSWORD:-${1:-}}"
if [ -z "$PASSWORD" ]; then
    echo "Usage: $0 password   (or set SETUP_PASSWORD)" >&2
    exit 1
fi

# Most of this script runs as root.  wsl-install.ps1 grants this user
# passwordless sudo, so this normally succeeds without prompting; when sudo does
# need a password and there is no terminal to type it on (the installer runs
# this through a pipe), stop here with a clear reason instead of failing later
# inside apt.
if ! sudo -n true 2> /dev/null; then
    if [ -t 0 ]; then
        echo "Note: sudo will prompt for your password."
    else
        echo "error: sudo requires a password and no terminal is available to enter it." >&2
        echo "       Grant passwordless sudo to this user (see wsl-install.ps1) and re-run." >&2
        exit 1
    fi
fi

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
cd "$SCRIPT_DIR"

# Say which revision is running.  wsl-install.ps1 clones this repo from GitHub,
# so a local edit that was never pushed is invisible to a fresh install -- and
# that is exactly the kind of thing it is worth being able to see in the log
# instead of guessing at from line numbers after the fact.
REVISION=$(git rev-parse --short HEAD 2> /dev/null || echo unknown)
echo "=== Rebuilding from wsl-setup@$REVISION ==="

# Third-party repositories that could not be installed or verified.  Collected
# here and reported at the end, so a degraded rebuild is never silent.
SKIPPED_REPOS=""

note_skipped() {
    SKIPPED_REPOS="${SKIPPED_REPOS:+$SKIPPED_REPOS, }$1"
}

# Update system
echo "=== Updating system ==="
# Tolerant on purpose.  On a machine whose third-party keyrings have gone stale
# this update fails, and under `set -e` it used to kill the whole rebuild at the
# first line -- before the key refresh below could repair the machine.  A
# repository problem degrades the rebuild; it must not abort it.
if ! sudo apt update; then
    echo "warning: 'apt update' reported errors (see above); continuing" >&2
fi
sudo apt upgrade -y || echo "warning: 'apt upgrade' failed; continuing" >&2

# The key fetches below need these; on a minimal image they are not yet present.
sudo apt install -y ca-certificates wget gnupg curl \
    || echo "warning: could not install ca-certificates/wget/gnupg/curl; third-party repos may be skipped" >&2

# ---------------------------------------------------------------------------
# Third-party apt repositories.
# These MUST be configured before pkglist.txt is installed: that list contains
# `firefox` (available only from the Mozilla repo) and `nodejs` (nodesource;
# Debian ships an older release under the same name).
#
# Two rules learned from rebuilds that died here:
#
#   1. Refresh the signing keys every run.  apt verifies keys against a
#      time-based crypto policy, so a keyring captured months ago can stop
#      being accepted (`... SHA1 is not considered secure since ...`) and the
#      repository is then rejected as unsigned.  Re-fetching is what makes a
#      stale machine repairable.
#   2. A key is only trusted once it has been fetched, parsed and installed as a
#      binary keyring.  A failed download piped straight into the keyring file
#      leaves it empty, and apt then reports the unhelpful
#      "Missing key <fingerprint>".  Binary, not armored: sqv, gpgv and the
#      _apt sandbox user can all read a binary keyring; an armored .asc is not
#      universally accepted.
# ---------------------------------------------------------------------------
echo "=== Adding third-party apt repositories ==="

# Fetch a signing key, verify that it really is a usable key, then install it.
install_repo_key() {
    local url="$1" keyring="$2" name="$3"
    local tmp bin fpr

    if ! command -v wget > /dev/null || ! command -v gpg > /dev/null; then
        echo "warning: wget and gpg are required to install the $name signing key" >&2
        return 1
    fi

    tmp=$(mktemp)
    bin=$(mktemp)
    if ! wget -q -O "$tmp" "$url"; then
        echo "warning: could not download the $name signing key from $url" >&2
        rm -f "$tmp" "$bin"
        return 1
    fi
    if [ ! -s "$tmp" ]; then
        echo "warning: the $name signing key downloaded from $url is empty" >&2
        rm -f "$tmp" "$bin"
        return 1
    fi

    # Accept either an armored or an already-binary key.
    if ! gpg --dearmor < "$tmp" > "$bin" 2> /dev/null || [ ! -s "$bin" ]; then
        cp "$tmp" "$bin"
    fi
    if ! gpg --show-keys "$bin" > /dev/null 2>&1; then
        echo "warning: the $name signing key from $url is not a readable key" >&2
        rm -f "$tmp" "$bin"
        return 1
    fi

    # Replace, never append: a stale keyring is what breaks the repository.
    sudo rm -f "$keyring"
    sudo install -m 0644 "$bin" "$keyring"

    fpr=$(gpg --show-keys --with-colons "$bin" 2> /dev/null | awk -F: '/^fpr:/{print $10; exit}') || true
    echo "  $name signing key installed${fpr:+ ($fpr)}"
    rm -f "$tmp" "$bin"
    return 0
}

sudo install -d -m 0755 /etc/apt/keyrings \
    || echo "warning: could not create /etc/apt/keyrings; third-party repos will be skipped" >&2

# Mozilla (firefox)
if install_repo_key https://packages.mozilla.org/apt/repo-signing-key.gpg \
        /etc/apt/keyrings/packages.mozilla.org.gpg "Mozilla"; then
    sudo rm -f /etc/apt/keyrings/packages.mozilla.org.asc   # superseded armored copy
    echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.gpg] https://packages.mozilla.org/apt mozilla main" \
        | sudo tee /etc/apt/sources.list.d/mozilla.list > /dev/null
    printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' \
        | sudo tee /etc/apt/preferences.d/mozilla > /dev/null
else
    # Never leave behind a source list apt cannot verify.
    sudo rm -f /etc/apt/sources.list.d/mozilla.list
    note_skipped Mozilla
fi

# NodeSource (nodejs 22.x)
if install_repo_key https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        /etc/apt/keyrings/nodesource.gpg "NodeSource"; then
    sudo rm -f /usr/share/keyrings/nodesource.gpg            # superseded location
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
        | sudo tee /etc/apt/sources.list.d/nodesource.list > /dev/null
    printf 'Package: nodejs\nPin: origin deb.nodesource.com\nPin-Priority: 600\n' \
        | sudo tee /etc/apt/preferences.d/nodejs > /dev/null
else
    sudo rm -f /etc/apt/sources.list.d/nodesource.list
    note_skipped NodeSource
fi

# Refresh the lists now that the keys are current.  Tolerant for the same
# reason as the update above; the pkglist install below reports what is missing.
if ! sudo apt update; then
    echo "warning: 'apt update' still reports errors after the key refresh" >&2
fi

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
sudo apt install -y python3-pip || echo "warning: could not install python3-pip" >&2

# Python packages pip-installed into the user site by capture_env.sh.
# if [ -f requirements.txt ]; then
#     echo "=== Installing Python packages ==="
#     pip3 install --user --break-system-packages -r requirements.txt \
#         || echo "warning: some pip packages failed to install" >&2
# else
#     echo "Warning: requirements.txt not found, skipping Python packages." >&2
# fi

# Decrypt and extract config archive
if [ -f config.asc ]; then
    echo "=== Decrypting and extracting home config ==="
    # gpg's own failure text is unhelpful; name the likely cause here.
    if ! gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 \
            -d -o config.tgz config.asc 3< <(printf '%s\n' "$PASSWORD"); then
        rm -f config.tgz
        echo "error: could not decrypt config.asc -- wrong password?" >&2
        exit 1
    fi
    if ! tar xzf config.tgz -C ~; then
        rm -f config.tgz
        echo "error: could not extract config.tgz into $HOME" >&2
        exit 1
    fi
    rm -f config.tgz
else
    echo "No config.asc found, skipping config restore."
fi

pushd ~/
# Install gecko driver
wget https://github.com/mozilla/geckodriver/releases/download/v0.36.0/geckodriver-v0.36.0-linux64.tar.gz \
    || echo "warning: could not download geckodriver" >&2
if [ -f geckodriver-v0.36.0-linux64.tar.gz ]; then
    if tar -xzvf geckodriver-v0.36.0-linux64.tar.gz && [ -f geckodriver ]; then
        sudo mv geckodriver /usr/local/bin \
            || echo "warning: could not install geckodriver into /usr/local/bin" >&2
    else
        echo "warning: could not unpack geckodriver-v0.36.0-linux64.tar.gz" >&2
    fi
    rm -f geckodriver-v0.36.0-linux64.tar.gz
fi

# Get ledger repo (already present on a re-run, which must not abort the script)
if [ ! -d oohomes_ledger ]; then
    gh repo clone oohomes_ledger || echo "warning: could not clone oohomes_ledger" >&2
fi
if [ -f oohomes_ledger/requirements.txt ]; then
    pip3 install -r oohomes_ledger/requirements.txt --break-system-packages \
        || echo "warning: some ledger pip packages failed to install" >&2
fi
popd

# Symlink the invoice and lease trees into the ledger checkout.  Only meaningful
# once that checkout exists, and a link that cannot be made must not abort an
# otherwise complete rebuild.
if [ -d "$HOME/oohomes_ledger" ]; then
    ln -sfn "/mnt/c/Users/bjoos/Documents/NextCloud/Real Estate/Invoices" "$HOME/oohomes_ledger/invoices" \
        || echo "warning: could not link invoices into ~/oohomes_ledger" >&2
    ln -sfn "/mnt/c/Users/bjoos/Documents/NextCloud/Real Estate/Leases" "$HOME/oohomes_ledger/leases" \
        || echo "warning: could not link leases into ~/oohomes_ledger" >&2
else
    echo "warning: ~/oohomes_ledger is missing; invoices/leases links not created" >&2
fi
if [ -n "$SKIPPED_REPOS" ]; then
    echo "warning: these third-party repositories were not configured: $SKIPPED_REPOS" >&2
    echo "warning: packages that come only from them are missing or older than usual" >&2
fi
echo "=== Environment rebuild complete ==="
echo "You may need to log out and back in for changes to dotfiles and shell configs to take effect."
