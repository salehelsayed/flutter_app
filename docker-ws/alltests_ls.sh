#!/bin/bash
# Read-only: ls -la of given absolute paths on the Mac.
for p in "$@"; do ls -la "$p" 2>&1 | head -12; done
