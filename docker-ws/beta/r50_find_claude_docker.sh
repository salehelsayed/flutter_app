#!/bin/bash
# Find where the claude-docker command is defined on the Mac (read profiles as text; never start zsh -i).
for f in "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.zshenv" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" "$HOME/.oh-my-zsh/custom"/*.zsh; do
  [ -f "$f" ] && grep -n 'claude-docker' "$f" /dev/null
done
for d in "$HOME/bin" "$HOME/.local/bin" /usr/local/bin /opt/homebrew/bin; do
  [ -e "$d/claude-docker" ] && { ls -la "$d/claude-docker"; file "$d/claude-docker"; head -20 "$d/claude-docker"; }
done
echo "R50 DONE"
