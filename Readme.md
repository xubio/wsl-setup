## Oohomes rental property financials environment ## 

This repo contains all code to set up the oohomes WSL environment

## Usage: ##
1. Download wsl-install.ps1 on windows machine from:
    https://raw.githubusercontent.com/xubio/wsl-setup/refs/heads/main/wsl-install.ps1
2. Open an Adminstrator powershell
3. Navigate to dir containing downloaded wsl-install.ps1
4. Run wsl-install.ps1

You should end up with a oohomes-debian WSL distribution.  If an existing distro named oohomes-debian is found, the script will abort.  If you intend to replace an exiting repo, remove it first manually by 
>    wsl --unregister oohomes-debian

## Capturing and rebuilding the environment ##

The distro is disposable; this repo is the source of truth.

* `capture_env.sh <password>` (run in WSL, from this directory) refreshes the
  snapshot files and re-encrypts the home-directory config:

  - `pkglist.txt` - apt packages to reinstall (from `apt-mark showmanual`)
  - `requirements.txt` - pip packages installed in the user site
  - `apt-installed.txt` - full installed set with versions, for the record
  - `system-info.txt` - distro/kernel identity, with a capture timestamp
  - `config.asc` - AES256-encrypted tar of `~/.*`, `~/.config`, `~/.ssh`,
    `~/bin`, `~/ai`, `~/mcp`

  It contains git and gh credentials, so the password matters and `config.asc`
  is the only file there that should ever be committed.  Commit the refreshed
  snapshot after a meaningful environment change, otherwise a rebuild from this
  repo will produce a different (stale) machine.

* `setup_env.sh <password>` rebuilds a fresh distro from those files.  It is
  invoked automatically by `wsl-install.ps1`.  Third-party apt repositories
  (Mozilla for `firefox`, NodeSource for `nodejs`) are configured before
  `pkglist.txt` is installed, because those two packages are not in Debian.

## Running the ledger ##

The ledger web app is served by Flask, not Apache:

* In WSL: `~/oohomes_ledger/html/start_server.sh` (bound to 127.0.0.1:8080)
* From Windows: run `start_oohomes.cmd` in the same directory, then open
  http://localhost:8080

The Flask process runs as the `oohomes` user, so it reads the ledger files
directly.  No `/var/www` symlink, no `www-data` access and no world-readable
home directory are involved.
