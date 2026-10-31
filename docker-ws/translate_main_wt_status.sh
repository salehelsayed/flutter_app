#!/bin/bash
# Read-only: git status of build/wt-translate-main.
cd /Volumes/CrucialX9/flutter_app/build/wt-translate-main && git status --porcelain | head -20 && git rev-parse --short HEAD
