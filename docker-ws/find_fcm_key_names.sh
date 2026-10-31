#!/bin/bash
# Read-only: list FILE NAMES that look like a Firebase service-account key. Never opens any file.
for d in "$HOME/Downloads" "$HOME/Documents" "$HOME/.config" "$HOME/Desktop" "$HOME/keys" "$HOME/.secrets" /Volumes/CrucialX9/flutter_app /Volumes/CrucialX9/secrets; do
  [ -d "$d" ] || continue
  find "$d" -maxdepth 4 -type f \( -iname '*firebase-adminsdk*.json' -o -iname '*service*account*.json' -o -iname '*serviceAccount*.json' -o -iname '*fcm*credential*.json' \) \
    -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/build/*' 2>/dev/null
done
