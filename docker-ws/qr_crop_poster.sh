#!/bin/bash
# Run qr_crop_poster.py with the first python3 on the Mac that has PIL.
for p in /opt/homebrew/bin/python3 /usr/local/bin/python3 /opt/homebrew/opt/python@3.13/bin/python3 /opt/homebrew/opt/python@3.12/bin/python3 /usr/bin/python3; do
  [ -x "$p" ] && "$p" -c 'import PIL' 2>/dev/null && exec "$p" "$(dirname "$0")/qr_crop_poster.py" "$@"
done
echo "no python with PIL"; exit 3
