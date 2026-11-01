#!/bin/bash
# Part 2 run lever on C (emulator-5558, Appium session open): tap <target>, poll page source until <done-regex>, sample PSS/RSS meanwhile.
#   p2_run.sh <label> <tap-desc-substring|xy:X,Y> <done-regex | !gone-regex> [timeout-secs]
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
cd "$(dirname "$0")" || exit 2
C=emulator-5558; L="$1"; T="$2"; RE="$3"; TO="${4:-240}"; O=/workspace/.codex-test-logs/translate-mem6-20261101/runs; mkdir -p $O
ma() { adb -s $C shell cat /proc/meminfo | awk '/MemAvailable/{print $2}'; }
pid0=$(adb -s $C shell pidof com.mknoon.app | tr -d '\r'); MA0=$(ma)
bash mem_sampler.sh $C $O/$L.mem 600 & SP=$!
sleep 1; { case "$T" in xy:*) X=${T#xy:}; python3 apa.py $C tapxy ${X%,*} ${X#*,} >/dev/null;; *) python3 apa.py $C tap "$T" >/dev/null;; esac; } || { touch $O/$L.mem.stop; wait $SP; echo "$L TAP_FAILED"; exit 3; }
t0=$(date +%s.%N); start=$(date -u +%T); res=TIMEOUT
while python3 -c "import sys,time;sys.exit(0 if time.time()-$t0<$TO else 1)"; do
  S=$(python3 apa.py $C src 2>&1); echo "$S" > $O/$L.src
  echo "$(date -u +%T.%2N) $(echo "$S" | grep -E 'Voice message|ranslat|ranscri' | tr '\n' '~' | cut -c1-600)" >> $O/$L.polls
  case "$RE" in !*) echo "$S" | grep -qE "${RE#!}|ranscribing|reparing" || { res=DONE; break; };; *) echo "$S" | grep -qE "$RE" && { res=DONE; break; };; esac
  echo "$S" | grep -qiE "couldn|failed|try again|not available" && { res=ERROR; break; }
done
dur=$(python3 -c "import time;print(round(time.time()-$t0,1))")
sleep 2; touch $O/$L.mem.stop; wait $SP; MA1=$(ma); pid1=$(adb -s $C shell pidof com.mknoon.app | tr -d '\r')
pk=$(awk '{for(i=1;i<=NF;i++){if($i=="PSS:")p=($(i+1)>p?$(i+1):p); if($i=="RSS:")r=($(i+1)>r?$(i+1):r)}} END{print p" "r}' $O/$L.mem)
echo "$L start=$start result=$res dur_s=$dur peak_pss_kB=${pk% *} peak_rss_kB=${pk#* } samples=$(wc -l < $O/$L.mem) memavail_before_kB=$MA0 memavail_after_kB=$MA1 pid_same=$([ "$pid0" = "$pid1" ] && echo yes || echo "NO($pid0->$pid1)")" | tee -a $O/summary.txt
