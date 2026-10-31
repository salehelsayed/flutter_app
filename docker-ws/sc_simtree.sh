#!/bin/bash
# Read-only: list Mknoon sim app data files (size, path) excluding caches and tmp, for staging baselines.
D=$(xcrun simctl get_app_container F83C694C-90FE-45B7-8C01-AF14B865DC71 com.mknoon.app data) || exit 1
cd "$D" && GRAPH_OK=1 find . -type f -not -path "./Library/Caches/*" -not -path "./tmp/*" -exec stat -f "%z %N" {} \; | sort -k2
