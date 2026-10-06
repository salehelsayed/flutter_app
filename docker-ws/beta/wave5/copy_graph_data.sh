#!/bin/bash
# Copy the git-ignored graph data (not caches) from the main checkout into the wave3-next worktree.
M=/Volumes/CrucialX9/flutter_app; W=$M/.claude/worktrees/wave3-next
for f in graphify-arch/graphify-out/graph.json graphify-arch/graphify-out/manifest.json graphify-arch/graphify-out/graph.html graphify-arch/tdd-overlay.json graphify-out/graph.json graphify-out/manifest.json graphify-out/GRAPH_REPORT.md; do
  [ -f "$M/$f" ] && { mkdir -p "$W/$(dirname "$f")"; cp -p "$M/$f" "$W/$f" && echo "copied $f"; }
done
cd "$W" && git status --short | wc -l
ls -d "$HOME/.claude-docker-home/.claude/projects/-workspace/memory" && ls "$HOME/.claude-docker-home/.claude/projects/-workspace/memory" | wc -l
