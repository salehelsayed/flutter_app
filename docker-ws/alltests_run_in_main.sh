#!/bin/bash
# Run a command in the main checkout with the 3.47.2 SDK first on PATH.
cd /Volumes/CrucialX9/flutter_app || exit 4
export PATH="$HOME/development/flutter-3.47.2/bin:$PATH"
"$@"
