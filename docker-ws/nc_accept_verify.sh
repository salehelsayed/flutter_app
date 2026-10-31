#!/bin/bash
# Accept the pending request on the viewer, go Back to Orbit, then time when the new contact shows in Orbit and in all-chats (no restart).
#   nc_accept_verify.sh <serial> <name> <evidence dir>
S="$1"; N="$2"; E="$3"; D="$(dirname "$0")"; A="python3 $D/apa.py $S"
ts() { date -u +%H:%M:%S.%3NZ; }
log() { echo "$N $1 $(ts)" | tee -a "$E/steps.txt"; }
timeout 60 $A tap 'Accept' >/dev/null && log accept_tap
sleep 3; timeout 30 $A src "(?i)$N|Write something" | head -3
timeout 30 $A back >/dev/null; log back_to_orbit
seen=""
for i in $(seq 1 40); do
  if timeout 20 $A src "Open chat with $N" 2>/dev/null | grep -q "$N"; then seen=1; log orbit_seen; break; fi
  sleep 1
done
[ -z "$seen" ] && log orbit_NOT_seen_after_poll
timeout 60 $A shot "$E/a_orbit_after_$N.png" >/dev/null
timeout 30 $A tap 'Show all chats' >/dev/null; log allchats_open
seen=""
for i in $(seq 1 30); do
  if timeout 20 $A src "(?i)$N" 2>/dev/null | grep -q "$N"; then seen=1; log allchats_seen; break; fi
  sleep 1
done
[ -z "$seen" ] && log allchats_NOT_seen_after_poll
timeout 60 $A shot "$E/a_allchats_after_$N.png" >/dev/null
timeout 30 $A src '(?i)^All ' | head -2
timeout 30 $A tapxy 94 204 >/dev/null; log orbit_toggle_from_allchats
sleep 2; timeout 30 $A pkg; timeout 30 $A src '(?i)open settings|Show all chats' | head -2
