#!/bin/sh
set -eu

readonly DEFAULT_OPTS="nodatacache,nomdatacache,nobrowse"

_usage() {
  _usage_prog="$1"
  printf 'Usage: %s [-o extra_opts] <//user@server/share> <mount_point>\n' "$_usage_prog"
}

_normalize_url() {
  _normalize_url_input="$1"
  while :; do
    case "$_normalize_url_input" in
      */*/) _normalize_url_input="${_normalize_url_input%/}" ;;
      *) break ;;
    esac
  done
  case "$_normalize_url_input" in
    smb://*)
      printf '//%s\n' "${_normalize_url_input#smb://}"
      ;;
    //*)
      printf '%s\n' "$_normalize_url_input"
      ;;
    *)
      printf '//%s\n' "$_normalize_url_input"
      ;;
  esac
}

main() {
  _main_prog="$(basename "$0")"
  _main_extra_opts=""

  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help)
        _usage "$_main_prog"
        exit 0
        ;;
      -o)
        if [ $# -lt 2 ] || [ -z "$2" ]; then
          _usage "$_main_prog" >&2
          exit 1
        fi
        _main_extra_opts="$2"
        shift 2
        ;;
      --)
        shift
        break
        ;;
      -*)
        _usage "$_main_prog" >&2
        exit 1
        ;;
      *)
        break
        ;;
    esac
  done

  if [ $# -ne 2 ] || [ -z "$1" ] || [ -z "$2" ]; then
    _usage "$_main_prog" >&2
    exit 1
  fi

  if [ "$(uname -s)" != "Darwin" ]; then
    printf '%s: error: macOS (Darwin) required\n' "$_main_prog" >&2
    exit 1
  fi

  _main_raw_url="$1"
  _main_mount_point="$2"

  _main_url="$(_normalize_url "$_main_raw_url")"
  case "${_main_url#//}" in
    */*) ;;
    *)
      printf '%s: error: URL must include server and share: %s\n' "$_main_prog" "$_main_raw_url" >&2
      exit 1
      ;;
  esac

  _main_opts="$DEFAULT_OPTS"
  if [ -n "$_main_extra_opts" ]; then
    _main_opts="${_main_opts},${_main_extra_opts}"
  fi

  if [ ! -d "$_main_mount_point" ]; then
    mkdir -p "$_main_mount_point"
  fi

  mount -t smbfs -o "$_main_opts" "$_main_url" "$_main_mount_point"
  mdutil -i off "$_main_mount_point" >/dev/null 2>&1 || true
}

main "$@"
