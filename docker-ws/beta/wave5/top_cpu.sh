#!/bin/bash
# Read-only: top CPU processes on the Mac.
ps -axo pid,ppid,pcpu,etime,command -r | head -16 | cut -c1-170
