#!/bin/bash
export PATH="/opt/homebrew/bin:$PATH"; cd /Volumes/CrucialX9/flutter_app || exit 1
gh variable list 2>&1 | head; echo "--- runners"; gh api repos/salehelsayed/flutter_app/actions/runners --jq '.runners[] | .name+" "+.status+" "+([.labels[].name]|join(","))' 2>&1 | head -5
