#!/bin/bash
# Read-only: Mac swap-in/out rate over 10 s and the emulator process resident size.
a=$(vm_stat | awk '/Swapins/ {gsub("\\.","",$2); print $2} /Swapouts/ {gsub("\\.","",$2); print $2}' | tr '\n' ' ')
p=$(vm_stat | awk '/Pageins/ {gsub("\\.","",$2); print $2}')
sleep 10
b=$(vm_stat | awk '/Swapins/ {gsub("\\.","",$2); print $2} /Swapouts/ {gsub("\\.","",$2); print $2}' | tr '\n' ' ')
q=$(vm_stat | awk '/Pageins/ {gsub("\\.","",$2); print $2}')
set -- $a $b
echo "per 10 s: swapins=$(( $3 - $1 )) swapouts=$(( $4 - $2 )) pageins=$(( q - p ))  (pages of 16 KB)"
echo "swap: $(sysctl -n vm.swapusage)"
ps -axo pid,rss,pcpu,command | awk '/qemu-system-aarch64 .*Pixel_7a/ && !/awk/ {printf "emulator-5556 qemu pid %s rss %d MB cpu %s%%\n",$1,$2/1024,$3}'
echo "load: $(sysctl -n vm.loadavg)"
