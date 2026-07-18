#!/usr/bin/env bash
set -uo pipefail
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"

echo "=== before ==="
graphify --version 2>&1 | head -1

echo "=== uv tool upgrade graphifyy ==="
uv tool upgrade graphifyy 2>&1 | tail -10

echo "=== after ==="
graphify --version 2>&1 | head -1

echo "=== LLM backend keys visible to host bridge env (masked) ==="
env | grep -iE "^(ANTHROPIC|GEMINI|GOOGLE|OPENAI|DEEPSEEK|KIMI|MOONSHOT)[A-Z_]*=" | sed 's/=.*/=<set>/' || echo "none in env"
for f in "$HOME/.graphify/config" "$HOME/.graphify/config.json" "$HOME/.config/graphify/config.json"; do
  [ -f "$f" ] && echo "config file present: $f"
done
ls "$HOME/.graphify" 2>/dev/null | head -10
