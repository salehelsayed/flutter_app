#!/bin/bash
# Read-only: list xcodebuild WebDriverAgent processes for the T011 simulator (pid ppid).
ps -axo pid=,ppid=,args= | grep "[x]codebuild" | grep WebDriverAgent | grep F83C694C | awk "{print \$1, \$2}"
