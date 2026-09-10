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

## Development

Run the test suite and repository consistency checks:

```sh
./bin/check.sh
```

`bin/check.sh` validates script executability, lints with ShellCheck (or `sh -n`), checks markdown formatting, and runs the unit test suite (`tests/run.sh`).
