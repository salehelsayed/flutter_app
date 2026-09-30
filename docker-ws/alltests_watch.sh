#!/bin/bash
# Read-only progress for a launched checkpoint: alive?, launch log tail, wrapper log tail, newest files.
run=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run; label="$1"; n="${2:-15}"
date
pid=$(cat "$run/$label.launch.pid" 2>/dev/null); if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then echo "ALIVE pid=$pid"; else echo "EXITED pid=$pid"; fi
echo "== launch.log =="; tail -n 20 "$run/$label.launch.log" 2>/dev/null | cut -c1-400
echo "== wrapper.log =="; tail -n "$n" "$run/$label.wrapper.log" 2>/dev/null | cut -c1-400
echo "== newest files =="; find "$run/$label" -type f -mmin -30 2>/dev/null | xargs ls -lt 2>/dev/null | head -8 | awk "{print \$5, \$6, \$7, \$8, \$9}"
