#!/bin/bash
echo "HOME=$HOME user=$(id -un)"; ls -d "$HOME/.ssh" 2>&1; ls "$HOME/.ssh" 2>/dev/null | grep -c hetzner
