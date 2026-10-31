#!/bin/bash
# Temporary Mac-side SSH key for the Hetzner TEST relay campaigns (owner-approved 10-25). Never prints the private key.
#   host-run bash docker-ws/hetzner_tmp_key.sh create   -> prints the PUBLIC key only
#   host-run bash docker-ws/hetzner_tmp_key.sh hostkey  -> adds the Hetzner host key to known_hosts, prints its fingerprint
#   host-run bash docker-ws/hetzner_tmp_key.sh test     -> non-interactive ssh check
#   host-run bash docker-ws/hetzner_tmp_key.sh destroy  -> deletes the key dir and the known_hosts entry
set -u
D="$HOME/.mknoon-hetzner-tmp"; K="$D/id_ed25519"; H=2.29.62.121
case "${1:-}" in
  create) [ -f "$K" ] || { mkdir -m 700 -p "$D"; ssh-keygen -q -t ed25519 -N '' -C mknoon-harness-tmp-20261025 -f "$K"; }
          chmod 600 "$K"; echo "mode $(stat -f %Lp "$K")"; cat "$K.pub" ;;
  hostkey) ssh-keyscan -t ed25519 "$H" 2>/dev/null > "$D/scan"; ssh-keygen -lf "$D/scan"
           ssh-keygen -F "$H" >/dev/null || cat "$D/scan" >> "$HOME/.ssh/known_hosts"; rm -f "$D/scan"; echo added ;;
  test) ssh -o BatchMode=yes -o ConnectTimeout=15 -i "$K" root@$H 'systemctl is-active relay-server'; echo "exit=$?" ;;
  destroy) rm -rf "$D"; ssh-keygen -R "$H" >/dev/null 2>&1; [ -d "$D" ] && echo "still there" || echo "key dir deleted, known_hosts entry removed" ;;
  path) echo "$K" ;;
  *) echo usage; exit 2 ;;
esac
