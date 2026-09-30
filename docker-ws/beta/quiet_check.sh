#!/bin/bash
# Read-only one-liner: may the beta run start? QUIET = the iOS build is not running,
# 1-min load < 40, 5-min load < 50, and this Mac's system cache (used by the iOS
# simulator) and every resolver it uses answer mknoun.xyz with the new relay address.
# Each resolver answer is printed as address/remaining-TTL.
NEW=51.21.194.144
read -r _ l1 l5 l15 _ < <(sysctl -n vm.loadavg)
b=idle; pgrep -f build_ios_inplace.sh >/dev/null && b=running
sys=$(dscacheutil -q host -a name mknoun.xyz | awk '/ip_address/ {print $2}' | sort -u | tr '\n' ',')
dns_ok=1; [ "$sys" = "$NEW," ] || dns_ok=0
res=""
for r in $(scutil --dns | awk '/nameserver\[[0-9]+\]/ {print $3}' | sort -u); do
  a=$(dig +time=3 +tries=1 +noall +answer A mknoun.xyz @"$r" | awk '{printf "%s/%s ", $5, $2}')
  res="$res $r=${a:-none}"
  case "$a" in "$NEW/"*) ;; *) dns_ok=0 ;; esac
done
state=LOADED
if [ "$b" = idle ] && [ "${l1%.*}" -lt 40 ] && [ "${l5%.*}" -lt 50 ] && [ $dns_ok = 1 ]; then state=QUIET; fi
echo "$state $(date '+%H:%M:%S') load1=$l1 load5=$l5 build=$b sys=$sys$res"
