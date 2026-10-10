#!/bin/bash
# Read-only: how fast does this Mac reach the relay right now?
H=mknoun.xyz
echo "=== resolve ==="; dscacheutil -q host -a name $H | awk '/ip_address/ {print $2}'
echo "=== ping ==="; ping -c 5 -t 8 $H 2>&1 | tail -2
echo "=== wss :4001 (tcp connect / tls done / first byte, seconds) ==="
for i in 1 2 3 4 5; do
  curl -s -o /dev/null --max-time 10 -w "connect=%{time_connect} tls=%{time_appconnect} ttfb=%{time_starttransfer} code=%{http_code}\n" https://$H:4001/
done
echo "=== raw tcp ports (connect time) ==="
for p in 4005 4000 443 3478; do
  s=$(python3 -c "import socket,time;t=time.time();s=socket.socket();s.settimeout(5)
try:
  s.connect(('$H',$p));print('open %.3fs'%(time.time()-t))
except Exception as e:print('FAIL',type(e).__name__)")
  echo "tcp $p: $s"
done
echo "=== active network ==="; route -n get default 2>/dev/null | awk '/interface/ {print $2}'; networksetup -getairportnetwork en0 2>/dev/null
echo "=== mac load ==="; sysctl -n vm.loadavg
