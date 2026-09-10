#!/bin/sh
set -eu

readonly DEFAULT_OPTS="nodatacache,nomdatacache,nobrowse"

_usage() {
  _usage_prog="$1"
  printf 'Usage: %s [-o extra_opts] <//user@server/share> <mount_point>\n' "$_usage_prog"
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

_validate_positional_args() {
  _validate_positional_args_prog="$1"
  shift
  if [ $# -ne 2 ] || [ -z "$1" ] || [ -z "$2" ]; then
    _exit_usage "$_validate_positional_args_prog" 1
  fi
}

_strip_trailing_slashes() {
  _strip_trailing_slashes_input="$1"
  while :; do
    case "$_strip_trailing_slashes_input" in
      */*/) _strip_trailing_slashes_input="${_strip_trailing_slashes_input%/}" ;;
      *) break ;;
    esac
  done
  printf '%s\n' "$_strip_trailing_slashes_input"
}

_format_smb_url() {
  _format_smb_url_input="$1"
  case "$_format_smb_url_input" in
    smb://*)
      printf '//%s\n' "${_format_smb_url_input#smb://}"
      ;;
    //*)
      printf '%s\n' "$_format_smb_url_input"
      ;;
    *)
      printf '//%s\n' "$_format_smb_url_input"
      ;;
  esac
}

_normalize_url() {
  _normalize_url_trimmed="$(_strip_trailing_slashes "$1")"
  _format_smb_url "$_normalize_url_trimmed"
}

_validate_url() {
  _validate_url_prog="$1"
  _validate_url_raw="$2"
  _validate_url_normalized="$3"
  case "${_validate_url_normalized#//}" in
    */*) ;;
    *)
      printf '%s: error: URL must include server and share: %s\n' "$_validate_url_prog" "$_validate_url_raw" >&2
      exit 1
      ;;
  esac
}

_build_mount_options() {
  _build_mount_options_extra="$1"
  if [ -n "$_build_mount_options_extra" ]; then
    printf '%s,%s\n' "$DEFAULT_OPTS" "$_build_mount_options_extra"
  else
    printf '%s\n' "$DEFAULT_OPTS"
  fi
}

_ensure_mount_point() {
  _ensure_mount_point_dir="$1"
  if [ ! -d "$_ensure_mount_point_dir" ]; then
    mkdir -p "$_ensure_mount_point_dir"
  fi
}

_mount_smb() {
  _mount_smb_opts="$1"
  _mount_smb_url="$2"
  _mount_smb_point="$3"
  mount -t smbfs -o "$_mount_smb_opts" "$_mount_smb_url" "$_mount_smb_point"
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
        _main_extra_opts="$2"
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

  _validate_positional_args "$_main_prog" "$@"
  _check_platform "$_main_prog"

  _main_raw_url="$1"
  _main_mount_point="$2"

  _main_url="$(_normalize_url "$_main_raw_url")"
  _validate_url "$_main_prog" "$_main_raw_url" "$_main_url"

  _main_opts="$(_build_mount_options "$_main_extra_opts")"

  _ensure_mount_point "$_main_mount_point"
  _mount_smb "$_main_opts" "$_main_url" "$_main_mount_point"
  _disable_indexing "$_main_mount_point"
}

main "$@"
