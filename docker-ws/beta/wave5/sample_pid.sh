#!/bin/bash
# Read-only: 2-second stack sample of a pid; print the heaviest frames.
sample "$1" 2 -mayDie 2>/dev/null | sed -n '/Call graph:/,/Total number in stack/p' | grep -vE "^\s*$" | head -40 | cut -c1-170
