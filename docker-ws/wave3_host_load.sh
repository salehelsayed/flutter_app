#!/bin/bash
# Mac load and the top CPU consumers.
uptime; sysctl -n hw.ncpu; ps -axo pcpu,pid,etime,comm -r | head -12 | cut -c1-150
