#!/bin/bash
# Check that the Mac's OpenSSH can reach the Hetzner TEST relay non-interactively with the Hetzner key (path only, never read).
#   host-run bash docker-ws/hetzner_mac_ssh_probe.sh
K="$HOME/.ssh/hetzner_relay_ed25519"
[ -f "$K" ] && echo "key present, mode $(stat -f %Lp "$K")" || { echo "key missing"; exit 2; }
ssh-keygen -F 2.29.62.121 >/dev/null 2>&1 && echo "known_hosts has host" || echo "known_hosts lacks host"
ssh -o BatchMode=yes -o ConnectTimeout=15 -i "$K" root@2.29.62.121 'systemctl is-active relay-server; /usr/local/bin/relay-server version | head -1' 2>&1 | tail -3
echo "ssh exit=$?"
