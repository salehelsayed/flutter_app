#!/bin/bash
# DC-023 recheck: one line per com.mknoon.app notification record (channel, flags, title, text) from dumpsys only.
#   dc023_records.sh <serial>
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
adb -s "$1" shell dumpsys notification --noredact | awk '
  /NotificationRecord\(/ { if (p) print rec; p=($0 ~ /pkg=com.mknoon.app/); rec="";
    if (p) { match($0, /channel=[^ ]+/); rec=substr($0,RSTART,RLENGTH); match($0, /flags=[^ ]+/); rec=rec " " substr($0,RSTART,RLENGTH) } }
  p && /android\.title=String/ { sub(/^ */,""); rec=rec " | " $0 }
  p && /android\.text=String/ { sub(/^ */,""); rec=rec " | " $0 }
  END { if (p) print rec }'
