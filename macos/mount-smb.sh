#!/bin/sh
set -eu

_usage() {
  _usage_prog="$1"
  printf 'Usage: %s [-o extra_opts] <//user@server/share> <mount_point>\n' "$_usage_prog" >&2
  exit 1
}

_normalize_url() {
  _normalize_url_input="$1"
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
  _main_prog="$0"
  _main_extra_opts=""

  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help)
        _usage "$_main_prog"
        ;;
      -o)
        [ $# -ge 2 ] || _usage "$_main_prog"
        _main_extra_opts="$2"
        shift 2
        ;;
      --)
        shift
        break
        ;;
      -*)
        _usage "$_main_prog"
        ;;
      *)
        break
        ;;
    esac
  done

  [ $# -eq 2 ] || _usage "$_main_prog"
  _main_raw_url="$1"
  _main_mount_point="$2"

  _main_url="$(_normalize_url "$_main_raw_url")"
  _main_opts="nodatacache,nomdatacache,nobrowse"
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
