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