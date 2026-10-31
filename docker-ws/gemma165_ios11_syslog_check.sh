#!/bin/bash
# Read-only: list any idevicesyslog reader still attached to the iPhone 11.
ps -axo pid,lstart,command | grep '[i]devicesyslog -u 00008030-001A6D2801BB802E' || echo "no iPhone 11 idevicesyslog running"
