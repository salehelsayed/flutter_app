# VC-014 read-only: production relay call/APNs VoIP counters from /metrics (no sudo, no journal, no config).
#   RELAY_SSH_HOST=<prod> python3 docker-ws/relay_ssh.py < docker-ws/vc014/aws_metrics.sh
date -u +%FT%TZ
curl -s -m 5 localhost:2112/metrics | grep -E '^relay_(apns_voip|call_wake|call_store|call_mailbox|call_)[a-z_]*(\{[^}]*\})? ' | grep -vE '_bucket|_sum |_count ' | head -40
