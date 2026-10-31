#!/bin/bash
# List file names (depth 2) under a directory, read-only.
#   host-run bash docker-ws/list_dir_names.sh <dir>
find "${1:?dir}" -maxdepth 2 -type f 2>/dev/null | head -40
