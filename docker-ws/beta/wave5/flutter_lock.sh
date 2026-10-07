#!/bin/bash
# Read-only: processes holding the Flutter 3.47.2 SDK startup lockfile, with age, parent and cwd.
L=$HOME/development/flutter-3.47.2/bin/cache/lockfile
for p in $(lsof -t "$L" 2>/dev/null); do
  echo "$(ps -o pid=,ppid=,etime=,pcpu= -p $p) cwd=$(lsof -a -p $p -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | cut -c1-70) cmd=$(ps -o command= -p $p | grep -oE 'flutter_tools.snapshot [a-z]+ [a-z-]+[^/]{0,60}' | head -1)"
done
