#!/bin/bash
# Commit the staged O10 docs on the Mac (the container commit hung on a virtiofs read).
cd /Volumes/CrucialX9/flutter_app || exit 1
git diff --cached --numstat
git commit -q -F - <<'MSG'
docs(testing): O10 iPhone re-check passes after the GE-009 fix

Pixel admin, iPhone 13 brand-new invitee, both on this branch. The message
sent before accept reaches the invitee once, from the relay inbox, after
accept. Before accept the iPhone shows only the invite card and a passive
"Open the app to view updates." card. Closes gaps 2 and 3 of the GE-009
handover.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
MSG
echo "rc=$?"; git log -1 --format='%h %s'
