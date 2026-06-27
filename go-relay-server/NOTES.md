⏺ 1. Install node_exporter (host metrics on :9100)

  SSH into your EC2 instance, then:

  # Download
  cd /tmp
  wget https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz
  tar xzf node_exporter-1.8.2.linux-amd64.tar.gz
  sudo cp node_exporter-1.8.2.linux-amd64/node_exporter /usr/local/bin/
  rm -rf node_exporter-1.8.2.linux-amd64*

  # Create systemd service
  sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<'EOF'
  [Unit]
  Description=Node Exporter
  After=network.target

  [Service]
  ExecStart=/usr/local/bin/node_exporter
  Restart=on-failure
  RestartSec=5

  [Install]
  WantedBy=multi-user.target
  EOF

  # Start it
  sudo systemctl daemon-reload
  sudo systemctl enable node_exporter
  sudo systemctl start node_exporter

  # Verify — should return a wall of metrics
  curl -s localhost:9100/metrics | head -20

  ---
  2. Install Prometheus (scraper on :9090)

  # Download
  cd /tmp
  wget https://github.com/prometheus/prometheus/releases/download/v2.54.1/prometheus-2.54.1.linux-amd64.tar.gz
  tar xzf prometheus-2.54.1.linux-amd64.tar.gz
  sudo cp prometheus-2.54.1.linux-amd64/prometheus /usr/local/bin/
  sudo cp prometheus-2.54.1.linux-amd64/promtool /usr/local/bin/
  rm -rf prometheus-2.54.1.linux-amd64*

  # Create config directory and scrape config
  sudo mkdir -p /etc/prometheus /var/lib/prometheus

  sudo tee /etc/prometheus/prometheus.yml > /dev/null <<'EOF'
  global:
    scrape_interval: 15s

  scrape_configs:
    - job_name: "relay-server"
      static_configs:
        - targets: ["localhost:2112"]

    - job_name: "node"
      static_configs:
        - targets: ["localhost:9100"]
  EOF

  # Create systemd service
  sudo tee /etc/systemd/system/prometheus.service > /dev/null <<'EOF'
  [Unit]
  Description=Prometheus
  After=network.target

  [Service]
  ExecStart=/usr/local/bin/prometheus \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/var/lib/prometheus \
    --storage.tsdb.retention.time=30d
  Restart=on-failure
  RestartSec=5

  [Install]
  WantedBy=multi-user.target
  EOF

  # Start it
  sudo systemctl daemon-reload
  sudo systemctl enable prometheus
  sudo systemctl start prometheus

  # Verify — should show Prometheus's own metrics page
  curl -s localhost:9090/-/healthy
  # Should print: Prometheus Server is Healthy.

  ---
  3. View from your Mac

  ssh -L 9090:localhost:9090 ec2-user@mknoun.xyz

  Then open http://localhost:9090 in your browser.

  Try these queries to verify both targets are scraped:

  ┌────────────────────────────────┬──────────────────────────────────┐
  │             Query              │          What it shows           │
  ├────────────────────────────────┼──────────────────────────────────┤
  │ up                             │ Both targets should show value 1 │
  ├────────────────────────────────┼──────────────────────────────────┤
  │ relay_connections_active       │ Your app metric                  │
  ├────────────────────────────────┼──────────────────────────────────┤
  │ node_memory_MemAvailable_bytes │ Host metric from node_exporter   │
  ├────────────────────────────────┼──────────────────────────────────┤
  │ go_goroutines                  │ Built-in Go runtime metric       │
  └────────────────────────────────┴──────────────────────────────────┘

  If up{job="relay-server"} shows 0 or is missing, your relay-server isn't running yet with the new metrics build — deploy it first.

  ---
  Appendix: additive inbox dispatch actions (FDC-08 / FDC-09)

  The inbox stream handler (`HandleInboxStream`, `inbox.go`) dispatches on
  `req.Action`. All actions below are ADDITIVE: an old relay answers
  `{"status":"ERROR","error":"Unknown action: <action>"}`, which new clients map
  to a graceful skip (NET-REL-07 back-compat). Presence is a HINT, never
  load-bearing — the inbox + push remain the delivery guarantee.

  - `presence_get`  (FDC-08, READ): coarse "online-ish, TTL-lagged" presence for a
    peer (no circuit dial). Reply `{presence: reachable|unreachable|unknown, ageMs}`.
  - `presence_set`  (FDC-09, WRITE): a peer SELF-PUBLISHES its foreground/background
    state (`metadata: {state, ttlMs}`). Subject = the AUTHENTICATED stream peer
    (anti-spoof). Records the self-state + seeds last-seen so a stale state degrades
    to `unknown` (≈180 s TTL, clamp 10 min).
  - `register_wake_tokens` (FDC-09 §12): a recipient registers the opaque wake-token
    SET it minted for its contacts (`wakeTokens: [...]`). The store-path push gate
    then wakes ONLY a sender presenting a member token (`store` carries `wakeToken`);
    a non-member wake is suppressed (metric `push_sent_total{result="unauthorized_wake"}`)
    but the message is still stored. FAIL-OPEN until a recipient registers a set, so
    existing push delivery is unchanged. Cleared on `unregister_token`.
    NOTE: enforcement ships OFF (`wakeTokenGateEnforced=false`) — a registered set is
    RECORDED but never suppresses — until the SEND-SIDE token presentation lands
    (the store request attaching the recipient-issued token). Strict ship-order;
    flip on only once both halves are live, else all of a registered recipient's
    1:1 pushes hard-silence (every sender presents an empty token).

  Presence + wake-token stores are in-memory (a relay bounce loses them and fails
  OPEN back to existing push); durability is FDC-10's gap.