# relay-hz-86b786747 read-only: Hetzner relay call/APNs VoIP counters from /metrics.
#   python3 docker-ws/hetzner_ssh.py < docker-ws/rhz86_metrics.sh
date -u +%FT%TZ
curl -s -m 5 localhost:2112/metrics | grep -E '^relay_(apns_voip|call_wake|call_store|call_mailbox|call_)[a-z_]*(\{[^}]*\})? ' | grep -vE '_bucket|_sum |_count ' | head -60
