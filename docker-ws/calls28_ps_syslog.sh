#!/bin/bash
# Read-only: list idevicesyslog processes on the Mac.
ps -axo pid,lstart,command | grep idevicesyslo[g]
