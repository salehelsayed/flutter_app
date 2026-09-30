#!/bin/bash
f=$(ls -t ~/.npm-cache/_logs/*debug-0.log | head -1)
grep -iE "error|EACCES|EPERM|syscall" "$f" | tail -20
ls -ld ~/.local ~/.local/lib ~/.local/lib/node_modules ~/.local/bin ~/.npm-cache 2>&1
