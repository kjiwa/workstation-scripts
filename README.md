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

### bin/ensure-agent-settings.sh

Monitors and ensures symlinks and generated build artifacts from `agent-settings` are intact.

```sh
bin/ensure-agent-settings.sh [-h|--help] [-c|--check] [-r|--repair] [-m|--mode notify|auto-restore] [--set-mode notify|auto-restore] [-n|--notify|--no-notify] [-i|--install-service] [-u|--uninstall-service] [-s|--status] [-d|--dir dir] [-q|--quiet]
```

Options:
- `-c`, `--check`: Check symlinks and build artifacts without modifying anything. Exits 0 if intact, 1 if broken.
- `-r`, `--repair`: Inspect and repair missing build artifacts or broken symlinks via `install.sh`.
- `-m`, `--mode <notify|auto-restore>`: Set execution mode for this run.
- `--set-mode <notify|auto-restore>`: Persist default mode to configuration file.
- `-n`, `--notify`: Enable desktop notifications (`osascript` on macOS, `notify-send` on Linux).
- `--no-notify`: Suppress desktop notifications.
- `-i`, `--install-service`: Install and activate background event-driven service (macOS `launchd` or Linux `systemd` user `.path`).
- `-u`, `--uninstall-service`: Disable and remove background event-driven service.
- `-s`, `--status`: Display service status, configuration, and link health.
- `-d`, `--dir <dir>`: Path to `agent-settings` repository (default: `~/src/github/kjiwa/agent-settings`).
- `-q`, `--quiet`: Suppress non-error output.
- `-h`, `--help`: Show usage.

Behavior:
- Operates portably across macOS and Linux.
- In `notify` mode (default), broken items trigger a desktop notification with remediation instructions and exit 1.
- In `auto-restore` mode, broken items trigger `install.sh` in `agent-settings` to restore build artifacts and symlinks, then notify on completion.
- Background services use OS-native file monitoring (macOS `launchd` `WatchPaths`, Linux `systemd` `.path` units) to detect changes immediately with zero idle polling or battery drain.
- Configuration is loaded from `${XDG_CONFIG_HOME:-~/.config}/workstation-scripts/ensure-agent-settings.conf`.

Examples:

```sh
# Health check
bin/ensure-agent-settings.sh --check

# Manual repair
bin/ensure-agent-settings.sh --repair

# Set default mode to auto-restore
bin/ensure-agent-settings.sh --set-mode auto-restore

# Install background service
bin/ensure-agent-settings.sh --install-service

# Check service and link status
bin/ensure-agent-settings.sh --status
```

## Development

Run the test suite and repository consistency checks:

```sh
./bin/check.sh
```

`bin/check.sh` validates script executability, lints with ShellCheck (or `sh -n`), checks markdown formatting, and runs the unit test suite (`tests/run.sh`).
