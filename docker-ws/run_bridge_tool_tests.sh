#!/bin/bash
# Run the host bridge and host build-job diagnostic unit tests with the Mac's system Python.
#   host-run bash docker-ws/run_bridge_tool_tests.sh [log-file-in-repo]
set -uo pipefail
cd "$(dirname "$0")/.."
[ -n "${1:-}" ] && exec > "$1" 2>&1
if [ -n "${2:-}" ]; then
  # Debug one test id with a stack dump if it is still running after 20 seconds.
  cd scripts/test && /usr/bin/python3 -c 'import faulthandler, sys, unittest
faulthandler.dump_traceback_later(20, exit=True)
unittest.main(module=None, argv=["x", "-v", sys.argv[1]])' "$2"
  exit $?
fi
/usr/bin/python3 --version
cd /tmp && /usr/bin/python3 -I -m unittest discover -s "$OLDPWD/scripts/test" -p 'claude_host_tool_bridge_run_test.py' -v
a=$?
/usr/bin/python3 -I -m unittest discover -s "$OLDPWD/scripts/test" -p 'diagnose_host_build_jobs_test.py'
b=$?
echo "bridge_tests_exit=$a diagnostic_tests_exit=$b"
[ "$a" = 0 ] && [ "$b" = 0 ]
