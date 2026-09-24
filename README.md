# workstation-scripts

POSIX shell utilities for workstation administration and configuration.

## Scripts

### macos/mount-smb.sh

Mounts an SMB share on macOS with safe defaults.

```sh
macos/mount-smb.sh [-o extra_opts] <//user@server/share> <mount_point>
```

Options:
- `-o extra_opts`: Additional comma-delimited options passed to `mount -t smbfs`. May be specified multiple times.
- `-h`, `--help`: Show usage.

Behavior:
- Applies default mount options: `nodatacache`, `nomdatacache`, and `nobrowse`.
- Normalizes share URLs by stripping leading `smb:`, reducing leading slashes to `//`, and removing trailing slashes.
- Creates the mount point directory if it does not already exist.
- Disables Spotlight indexing on the mount point via `mdutil -i off`.
- Requires macOS (Darwin).

Examples:

```sh
# Basic mount
macos/mount-smb.sh //user@nas.local/share ~/mnt/share

# Full SMB URI with extra mount options
macos/mount-smb.sh -o ro,nostreams smb://nas.local/data ~/mnt/data
```

### macos/keep-awake.sh

Prevents macOS from sleeping when idle or when the laptop lid is closed.

```sh
macos/keep-awake.sh [-h|--help] [--] [command [args...]]
```

Options:
- `-h`, `--help`: Show usage.
- `--`: Treat subsequent arguments as a command.

Behavior:
- Disables sleep via `pmset -a disablesleep 1` and runs `caffeinate`.
- If a command is specified, executes that command under `caffeinate` and exits with the command's exit code.
- If no command is specified, keeps the system awake until interrupted with `Ctrl-C`.
- Maintains a background `sudo` keep-alive loop so authentication does not expire during long executions.
- Restores original sleep settings on exit or signal (`SIGINT`, `SIGTERM`, `SIGHUP`).
- Requires macOS (Darwin) and root privileges for `pmset`.

Examples:

```sh
# Keep awake interactively until Ctrl-C
macos/keep-awake.sh

# Keep awake while running a long task
macos/keep-awake.sh claude
```

## Development

Run the test suite and repository consistency checks:

```sh
./bin/check.sh
```

`bin/check.sh` validates script executability, lints with ShellCheck (or `sh -n`), checks markdown formatting, and runs the unit test suite (`tests/run.sh`).
