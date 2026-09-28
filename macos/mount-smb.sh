#!/bin/sh
set -eu

readonly DEFAULT_OPTS="nodatacache,nomdatacache,nobrowse"

_usage() {
  _usage_prog="$1"
  cat <<EOF
Usage: $_usage_prog [-h|--help] [-o extra_opts] <//user@server/share> <mount_point>

Mount an SMB share on macOS with safe defaults.

Arguments:
  <//user@server/share>  SMB share URL or UNC path (e.g. //user@server/share
                         or smb://server/share).
  <mount_point>          Local directory where the share will be mounted.

Options:
  -o extra_opts          Additional comma-delimited options passed to
                         mount -t smbfs. May be specified multiple times.
  -h, --help             Show this help message and exit.
  --                     Treat all following arguments as positional arguments.

Behavior:
  - Applies default mount options: nodatacache, nomdatacache, nobrowse.
  - Normalizes share URLs by stripping leading smb:, reducing leading
    slashes to //, and removing trailing slashes.
  - Rejects a password embedded in the URL (e.g. user:pass@server); omit the
    password and let macOS prompt or use Keychain.
  - Creates the mount point directory if it does not already exist, and
    removes it again if the mount fails, but only if this run created it.
  - Disables Spotlight indexing on the mount point via mdutil -i off.
  - Requires macOS.

Examples:
  $_usage_prog //user@nas.local/share ~/mnt/share
  $_usage_prog -o ro,nostreams smb://nas.local/data ~/mnt/data
EOF
}

_exit_usage() {
  _exit_usage_prog="$1"
  _exit_usage_code="$2"
  if [ "$_exit_usage_code" -eq 0 ]; then
    _usage "$_exit_usage_prog"
  else
    _usage "$_exit_usage_prog" >&2
  fi
  exit "$_exit_usage_code"
}

_check_platform() {
  _check_platform_prog="$1"
  if [ "$(uname -s)" != "Darwin" ]; then
    printf '%s: error: macOS (Darwin) required\n' "$_check_platform_prog" >&2
    exit 1
  fi
}

_normalize_url() {
  _normalize_url_prog="$1"
  _normalize_url_raw="$2"

  _normalize_url_path="${_normalize_url_raw#smb:}"
  while :; do
    case "$_normalize_url_path" in
      /*) _normalize_url_path="${_normalize_url_path#/}" ;;
      *) break ;;
    esac
  done
  while :; do
    case "$_normalize_url_path" in
      */) _normalize_url_path="${_normalize_url_path%/}" ;;
      *) break ;;
    esac
  done

  _normalize_url_server="${_normalize_url_path%%/*}"
  _normalize_url_share="${_normalize_url_path#*/}"

  if [ -z "$_normalize_url_path" ] || [ "$_normalize_url_server" = "$_normalize_url_path" ] || [ -z "$_normalize_url_server" ] || [ -z "$_normalize_url_share" ]; then
    printf '%s: error: URL must include server and share: %s\n' "$_normalize_url_prog" "$_normalize_url_raw" >&2
    exit 1
  fi

  case "$_normalize_url_server" in
    *@*)
      _normalize_url_userinfo="${_normalize_url_server%@*}"
      case "$_normalize_url_userinfo" in
        *:*)
          printf '%s: error: URL must not contain a password (it leaks via ps and shell history); omit the password from the URL and let macOS prompt or use Keychain: %s\n' "$_normalize_url_prog" "$_normalize_url_raw" >&2
          exit 1
          ;;
      esac
      ;;
  esac

  case "$_normalize_url_path" in
    *//* )
      printf '%s: error: URL must include server and share: %s\n' "$_normalize_url_prog" "$_normalize_url_raw" >&2
      exit 1
      ;;
  esac

  printf '//%s\n' "$_normalize_url_path"
}

_disable_indexing() {
  _disable_indexing_point="$1"
  mdutil -i off "$_disable_indexing_point" >/dev/null 2>&1 || true
}

main() {
  _main_prog="$(basename "$0")"
  _main_extra_opts=""

  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help)
        _exit_usage "$_main_prog" 0
        ;;
      -o)
        if [ $# -lt 2 ] || [ -z "$2" ]; then
          _exit_usage "$_main_prog" 1
        fi
        if [ -n "$_main_extra_opts" ]; then
          _main_extra_opts="${_main_extra_opts},$2"
        else
          _main_extra_opts="$2"
        fi
        shift 2
        ;;
      --)
        shift
        break
        ;;
      -*)
        _exit_usage "$_main_prog" 1
        ;;
      *)
        break
        ;;
    esac
  done

  if [ $# -ne 2 ] || [ -z "$1" ] || [ -z "$2" ]; then
    _exit_usage "$_main_prog" 1
  fi

  _check_platform "$_main_prog"

  _main_raw_url="$1"
  _main_mount_point="$2"

  _main_url="$(_normalize_url "$_main_prog" "$_main_raw_url")"
  _main_opts="$DEFAULT_OPTS${_main_extra_opts:+,$_main_extra_opts}"

  _main_mount_point_created=0
  if [ ! -d "$_main_mount_point" ]; then
    _main_mount_point_created=1
  fi
  mkdir -p "$_main_mount_point"

  set +e
  mount -t smbfs -o "$_main_opts" "$_main_url" "$_main_mount_point"
  _main_mount_status=$?
  set -e
  if [ "$_main_mount_status" -ne 0 ]; then
    if [ "$_main_mount_point_created" -eq 1 ]; then
      rmdir "$_main_mount_point" 2>/dev/null || true
    fi
    exit "$_main_mount_status"
  fi

  _disable_indexing "$_main_mount_point"
}

main "$@"
