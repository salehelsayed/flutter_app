#!/bin/bash
# A caller's explicit selection wins; a local file must select IPHONE_UDIDS.
mknoon_load_iphone_targets() {
  local repo="$1" kind="${2:-physical}" supplied="${IPHONE_UDIDS+x}" selected="${IPHONE_UDIDS-}"
  if [ -f "$repo/docker-ws/local_devices.env" ]; then
    . "$repo/docker-ws/local_devices.env" || return 2
  fi
  [ "$supplied" = x ] || selected="${IPHONE_UDIDS-}"
  IPHONE_UDIDS=$(
    set -f
    set -- $selected
    [ "$#" -gt 0 ] || { echo 'explicit IPHONE_UDIDS required' >&2; exit 2; }
    if [ "$kind" = sim ]; then
      [ "$#" -eq 1 ] && [[ "$1" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]] || { echo 'one explicit simulator identifier required' >&2; exit 2; }
    else
      for target in "$@"; do
        [[ "$target" =~ ^[[:xdigit:]]{40}$ || "$target" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{16}$ ]] || { echo 'invalid iPhone target' >&2; exit 2; }
      done
    fi
    printf '%s\n' "$@"
  ) || return 2
  export IPHONE_UDIDS
}
