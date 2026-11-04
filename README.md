# workstation-scripts

POSIX shell utilities for workstation administration and configuration.

## Scripts

### macos/mount-smb.sh

Mounts an SMB share on macOS with safe defaults.

```sh
macos/mount-smb.sh [-h|--help] [-o extra_opts] [--] <//user@server/share> <mount_point>
```

Arguments:
- `<//user@server/share>`: SMB share URL or UNC path (e.g. `//user@server/share` or `smb://server/share`).
- `<mount_point>`: Local directory where the share will be mounted.

Options:
- `-o extra_opts`: Additional comma-delimited options passed to `mount -t smbfs`. May be specified multiple times.
- `-h`, `--help`: Show usage.
- `--`: Treat subsequent arguments as positional arguments.

Behavior:
- Runs as the unprivileged user so the mounted share is owned by and accessible to that user account;
  rejects running as root.
- Prompts for sudo only if needed to create or chown the mount point (e.g. when mounting under
  `/Volumes`).
- Applies default mount options: `nodatacache`, `nomdatacache`, and `nobrowse`.
- Normalizes share URLs by stripping leading `smb:`, reducing leading slashes to `//`, and removing trailing slashes.
- Rejects URLs with a password embedded before the `@` (e.g. `smb://user:pass@server/share`); it
  leaks into `ps` output and shell history. Omit the password and let macOS prompt or use Keychain.
- Creates the mount point directory if it does not already exist, and removes it again if the
  mount fails, but only if this run created it.
- Disables Spotlight indexing on the mount point via `mdutil -i off`.
- Requires macOS (Darwin).

Examples:

```sh
# Basic mount in home directory
macos/mount-smb.sh //user@nas.local/share ~/mnt/share

# Mount under /Volumes (prompts for sudo only to prepare /Volumes/nas)
macos/mount-smb.sh //user@nas.local/share /Volumes/nas

# Full SMB URI with extra mount options
macos/mount-smb.sh -o ro,nostreams smb://nas.local/data ~/mnt/data
```

### macos/keep-awake.sh

Prevents macOS from sleeping when idle or when the laptop lid is closed.

```sh
macos/keep-awake.sh [-h|--help] [--] [command [args...]]
```

Arguments:
- `command [args...]`: Optional command to run. When specified, executes the command under `caffeinate` while sleep is disabled, restores original sleep settings on completion, and exits with the command's exit code. When omitted, keeps the system awake interactively until interrupted with `Ctrl-C`.

Options:
- `-h`, `--help`: Show usage.
- `--`: Treat subsequent arguments as a command.

Behavior:
- Disables sleep via `pmset -a disablesleep 1` and runs `caffeinate`.
- If a command is specified, executes that command under `caffeinate` and exits with the command's exit code.
- If no command is specified, keeps the system awake until interrupted with `Ctrl-C`.
- Maintains a background `sudo` keep-alive loop so authentication does not expire during long executions.
- Restores original sleep settings on exit or signal (`SIGINT`, `SIGTERM`, `SIGHUP`).
- Requires macOS (Darwin) and sudo access for `pmset`.

Examples:

```sh
# Keep awake interactively until Ctrl-C
macos/keep-awake.sh

# Keep awake while running a long task
macos/keep-awake.sh claude
```

### macos/prune-caches.sh

Prunes regenerable caches while keeping data that is still in use.

```sh
macos/prune-caches.sh [-h|--help] [-n|--dry-run] [--install-agent]
```

Options:
- `-n`, `--dry-run`: Print each action as `would remove <path>` or `would run <command>` and change nothing.
- `--install-agent`: Write `~/Library/LaunchAgents/local.workstation-scripts.prune-caches.plist` and load it with
  `launchctl bootout` then `launchctl bootstrap`, replacing a loaded agent. The agent runs this script Sundays at
  10:00, logs to `~/Library/Logs/prune-caches.log`, and gets a `PATH` that includes `/opt/homebrew/bin`, `~/.local/bin` and the default fnm Node. The plist is
  checked with `plutil -lint`. With `--dry-run`, prints what would be written and run.
- `-h`, `--help`: Show usage.

Behavior:
- Runs `brew cleanup`, `uv cache prune`, `npm cache verify`, `docker image prune -f`, and `docker builder prune -f`.
  Stopped containers and Docker volumes are left alone.
- Removes Terraform plugin cache versions that no `.terraform.lock.hcl` under the source directories pins, plus every
  symlink in the cache. The cache is `$TF_PLUGIN_CACHE_DIR` (default `~/.terraform.d/plugin-cache`); the source
  directories are the colon-separated `$PRUNE_SRC_DIRS` (default `~/src`). Skipped if a source directory is missing or holds no lock files.
- Removes Claude session directories and loose files under `$PRUNE_CLAUDE_TMP_DIR` (default `/private/tmp/claude-<uid>`)
  that contain nothing modified in the last 7 days. `bash-edit-diff` and `plugin-tool-staging` are kept, and symlinks
  are never followed.
- Reports a missing tool or an unreachable Docker daemon on stderr and skips it.
- Requires macOS (Darwin).

Examples:

```sh
# Preview what would be removed
macos/prune-caches.sh --dry-run

# Prune
macos/prune-caches.sh

# Install the weekly LaunchAgent
macos/prune-caches.sh --install-agent
```

## Development

Run the test suite and repository consistency checks:

```sh
./bin/check.sh
```

`bin/check.sh` validates script executability, lints with ShellCheck (or `sh -n`), checks markdown formatting, and runs the unit test suite (`tests/run.sh`).
