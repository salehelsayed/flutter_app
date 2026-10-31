#!/bin/bash
# Read-only: 3 samples of disk throughput for all disks.
iostat -d -w 2 -c 3 2>&1 | tail -4
