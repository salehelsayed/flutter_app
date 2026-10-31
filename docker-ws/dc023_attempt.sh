#!/bin/bash
# DC-023 recheck, one attempt on the Pixel receiver. A = peer whose chat stays mounted, B = peer whose card is tapped.
#   dc023_attempt.sh <label> <A-name> <A-serial> <B-name> <B-serial> <out-dir>
# Steps: open A from the list, Home, B sends, tap B card, in-app Back to A, A sends, poll records 25 s, Back to list.
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
L="$1"; AN="$2"; AS="$3"; BN="$4"; BS="$5"; O="$6"; D="$(dirname "$0")"; P=21071FDF600CSC
mkdir -p "$O"; exec > >(tee -a "$O/$L.txt") 2>&1
ts() { date -u +%T.%3N; }
hdr() { bash "$D/setA_ui.sh" texts $P | grep -o 'View contact profile&#10;[^&]*' | head -1; }
echo "== $L start $(ts)"
bash "$D/setA_ui.sh" tap $P "content-desc=\"$AN&#10;" || exit 3; sleep 5
echo "header after list open: $(hdr)"
adb -s $P shell input keyevent 3; echo "Home $(ts)"; sleep 3
echo "B send: $(bash "$D/setA_ui.sh" send $BS ${L}_B)"
for i in $(seq 1 20); do bash "$D/dc023_records.sh" $P | grep -q "${L}_B" && break; sleep 2; done
echo "B card: $(bash "$D/dc023_records.sh" $P | grep "${L}_B")"
bash "$D/setA_notif_tap.sh" $P "${L}_B"; sleep 2
echo "header after tap: $(hdr)"
bash "$D/setA_ui.sh" tap $P 'content-desc="Back"'; echo "in-app Back $(ts)"; sleep 5
echo "header after Back: $(hdr)"
echo "records before A send:"; bash "$D/dc023_records.sh" $P
echo "A send: $(bash "$D/setA_ui.sh" send $AS ${L}_A)"
for i in $(seq 1 13); do sleep 2; R=$(bash "$D/dc023_records.sh" $P | grep "${L}_A"); [ -n "$R" ] && { echo "A CARD at $(ts): $R"; break; }; done
[ -z "$R" ] && echo "no A card after 26 s ($(ts))"
echo "records after A send:"; bash "$D/dc023_records.sh" $P
echo "screen still A: $(hdr) | msg visible: $(bash "$D/setA_ui.sh" texts $P | grep -c "${L}_A")"
bash "$D/setA_ui.sh" tap $P 'content-desc="Back"'; sleep 5
echo "list rows after Back: $(bash "$D/setA_ui.sh" texts $P | grep -E "content-desc=\"($AN|$BN)&#10;")"
echo "== $L end $(ts)"
