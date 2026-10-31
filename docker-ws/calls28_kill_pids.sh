#!/bin/bash
# Stop my own Mac processes by exact PID (args).
for p in "$@"; do kill "$p" && echo "killed $p"; done
