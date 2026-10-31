#!/bin/bash
# Read-only: print afcclient usage (options for app container access).
/opt/homebrew/bin/afcclient --help 2>&1 | head -40
