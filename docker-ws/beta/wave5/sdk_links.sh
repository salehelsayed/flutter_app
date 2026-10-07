#!/bin/bash
S=$HOME/development/flutter-3.47.2
ls -ld "$HOME/development" "$S" "$S/bin" "$S/bin/cache" 2>&1 | cut -c1-200
readlink -f "$S/bin/cache" 2>/dev/null
ls -la "$S/bin/cache" 2>&1 | head -20 | cut -c1-150
