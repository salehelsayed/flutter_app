# Read-only: print the Hetzner relay's APNs VoIP push counters and recent [PUSH] journal lines.
#   python3 docker-ws/hetzner_ssh.py < docker-ws/calls28_relay_apns.sh
date -u +%T
curl -s -m 3 localhost:2112/metrics | grep -E '^relay_apns_voip_push_attempts_total\{outcome="(sent|invalid_token|sent_cross_environment|network|provider_error)"\}'
journalctl -u relay-server.service --since "-15 min" --no-pager | grep -E '\[PUSH\]|apns|APNS' | tail -8 | cut -c1-200
