# VC-014 read-only: does the relay journal hold per-request APNs lines? No sudo; counts and redacted shape only.
id -nG
journalctl -u relay-server.service --since "-75 min" --no-pager 2>&1 | grep -ciE 'apns|voip|\[PUSH\]'
journalctl -u relay-server.service --since "-75 min" --no-pager 2>&1 | grep -iE 'apns|voip|\[PUSH\]' | tail -5 | sed -E 's/[0-9a-f]{32,}/<hex>/g; s/12D3Koo[A-Za-z0-9]+/<peer>/g' | cut -c1-200
