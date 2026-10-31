#!/bin/bash
# Read-only: direct and second-level children of a pid.
for c in $(pgrep -P "$1"); do ps -o pid=,etime=,pcpu=,args= -p $c | cut -c1-220; for g in $(pgrep -P $c); do ps -o pid=,etime=,pcpu=,args= -p $g | cut -c1-220; done; done
