#!/bin/bash
# List plan399 coturn fixture containers; with --stop <id>, stop exactly that container if its name is a plan399 coturn fixture.
set -u
docker ps --format '{{.ID}} {{.Names}} {{.RunningFor}}' | grep 'mknoon-plan399-coturn' || echo "no plan399 coturn container"
if [ "${1:-}" = "--stop" ] && [ -n "${2:-}" ]; then
  n=$(docker inspect --format '{{.Name}}' "$2" 2>/dev/null)
  case "$n" in /mknoon-plan399-coturn-*) docker stop "$2" >/dev/null && echo "stopped $2";; *) echo "refused $2 ($n)"; exit 2;; esac
fi
