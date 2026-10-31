#!/bin/bash
# VC-023 read-only (Hetzner test relay, via `python3 docker-ws/hetzner_ssh.py < this`): for call-diagnostic files changed in the
# last MIN minutes, print mtime, file size, and counts of the privacy-safe selected-route fields (transport,
# pairRelayInvolvement, mediaFlowVerified). Prints no ids, peer ids or addresses.
MIN=${MIN:-30}
D=/var/lib/mknoon/call-diagnostics
find "$D" -maxdepth 1 -type f -name '*.json' -mmin -"$MIN" ! -name private.json -printf '%TY-%Tm-%TdT%TH:%TM:%TSZ %s %p\n' 2>/dev/null | sort | while read -r ts sz f; do
  r=$(grep -oE '"(transport|pairRelayInvolvement)": ?"[a-z_]+"|"mediaFlowVerified": ?(true|false)' "$f" | tr -d ' ' | sort | uniq -c | tr '\n' ' ')
  [ -n "$r" ] && echo "${ts%.*} size=$sz kind=$(basename "$f" | cut -c1-7 | sed 's/[0-9a-f-]\{7\}/trace/') :: $r"
done
echo "now $(date -u +%FT%TZ)"
