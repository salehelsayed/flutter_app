#!/bin/bash
# Read-only: count processes by state and list the commands of running or uninterruptible ones.
ps -axo stat=,comm= | awk '{print substr($1,1,1)}' | sort | uniq -c
ps -axo stat=,pid=,ppid=,comm= | awk 'substr($1,1,1)=="R"||substr($1,1,1)=="U"' | awk '{n=split($4,a,"/"); print $1,$2,$3,a[n]}' | sort -k4 | uniq -c -f3 | sort -rn | head -15
