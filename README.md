# SnapMac

SnapMac evaluates your current macOS system and generates a `restore.sh` script that rebuilds your exact software environment on a fresh Mac — from Homebrew packages and App Store apps to npm globals, Python tools, Rust crates, and more.

## How it works

Running `snapshot.sh` scans your system and produces two files in `snapshots/<timestamp>/`:

- **`restore.sh`** — a self-contained script that installs everything on a new Mac
- **`Brewfile`** — used by `restore.sh` to install Homebrew packages, casks, App Store apps, and VS Code extensions

`restore.sh` handles everything from scratch: Xcode Command Line Tools, Homebrew, and all package managers. The only requirement to *run* it is a fresh macOS installation.

**Package managers scanned:** Homebrew, npm, pip3, pipx, uv, pnpm, yarn, Deno, Bun, mise, Go, Cargo, Ruby gems, Composer

Binaries in `$PATH` and GUI apps in `/Applications` that aren't managed by any known package manager are listed in `restore.sh` as manual review items.

## Requirements

- macOS with [Homebrew](https://brew.sh) installed
- `mas` and `pipx` are installed automatically if missing

## Quick start

```bash
# Clone the tool
git clone https://github.com/dlasley/snapmac.git
cd snapmac

# Take a snapshot of your current system
bash scripts/snapshot.sh
```

The generated `restore.sh` path is printed at the end of the run.

### Pin exact versions

By default `restore.sh` installs the latest version of each package. To pin to the versions currently installed:

```bash
bash scripts/snapshot.sh --version=exact
```

## Restoring on a new Mac

Copy or download your `restore.sh` and its accompanying `Brewfile` to the same directory on the new machine, then:

```bash
bash restore.sh
```

That's it. Xcode CLT and Homebrew are installed automatically if missing. Each package manager is invoked in sequence; failures are counted and reported at the end without stopping the rest of the install.

## Storing snapshots in a private repo

Snapshots contain your full list of installed software, so you'll want to store them in a **private** repository separate from this tool.

1. Create a private repo (e.g. `github.com/<you>/my-snapshots`)
2. Copy `.env.example` to `.env` and set `SNAPMAC_REMOTE_REPO`:

```bash
cp .env.example .env
# Edit .env and set SNAPMAC_REMOTE_REPO=https://github.com/<you>/my-snapshots.git
```

3. Push a snapshot:

```bash
bash scripts/push-snapshot.sh
```

On first run, `push-snapshot.sh` reads `SNAPMAC_REMOTE_REPO` from `.env` and configures the git remote automatically. Subsequent pushes commit and push the latest snapshot directory.

## Automated snapshots

To run snapshots on a schedule:

```bash
# Interactive cron setup
bash scripts/setup-cron.sh
```

This registers `auto-snapshot.sh` in your crontab. `auto-snapshot.sh` runs `snapshot.sh` followed by `push-snapshot.sh` and logs output to `snapshots/auto-snapshot.log`.

To trigger it manually:

```bash
bash scripts/auto-snapshot.sh
```
