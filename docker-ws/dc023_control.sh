#!/bin/bash
# DC-023 recheck control and preservation legs on the Pixel receiver.
#   dc023_control.sh fresh <A-name> <A-serial> <out-dir>   open A from the list, A sends, poll records 26 s, Back
#   dc023_control.sh keep  <A-name> <A-serial> <out-dir>   Pixel on the list, A sends (expect card), open A from list, check card cleared
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
M="$1"; AN="$2"; AS="$3"; O="$4"; D="$(dirname "$0")"; P=21071FDF600CSC; L="ctl_$M"
exec > >(tee -a "$O/$L.txt") 2>&1
ts() { date -u +%T.%3N; }
hdr() { bash "$D/setA_ui.sh" texts $P | grep -o 'View contact profile&#10;[^&]*' | head -1; }
poll() { for i in $(seq 1 13); do sleep 2; R=$(bash "$D/dc023_records.sh" $P | grep "${L}_A"); [ -n "$R" ] && { echo "A CARD at $(ts): $R"; return; }; done; echo "no A card after 26 s ($(ts))"; }
row() { bash "$D/setA_ui.sh" texts $P | grep -E "content-desc=\"$AN&#10;"; }
echo "== $L start $(ts)"
if [ "$M" = fresh ]; then
  bash "$D/setA_ui.sh" tap $P "content-desc=\"$AN&#10;" || exit 3; sleep 5; echo "header: $(hdr)"
  echo "A send: $(bash "$D/setA_ui.sh" send $AS ${L}_A)"; poll
  echo "screen still A: $(hdr) | msg visible: $(bash "$D/setA_ui.sh" texts $P | grep -c "${L}_A")"
  bash "$D/setA_ui.sh" tap $P 'content-desc="Back"'; sleep 5; echo "row after Back: $(row)"
else
  echo "row before: $(row)"
  echo "A send: $(bash "$D/setA_ui.sh" send $AS ${L}_A)"; poll
  sleep 3; echo "row with Pixel on list: $(row)"
  bash "$D/setA_ui.sh" tap $P "content-desc=\"$AN&#10;" || exit 3; sleep 6; echo "header: $(hdr)"
  echo "records after open:"; bash "$D/dc023_records.sh" $P
  bash "$D/setA_ui.sh" tap $P 'content-desc="Back"'; sleep 5; echo "row after Back: $(row)"
fi
echo "== $L end $(ts)"
