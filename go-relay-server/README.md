  1. Build the binary on the server:

  cd go-relay-server
  make build
  sudo cp relay-server /usr/local/bin/relay-server

  2. Create the service file:

  sudo nano /etc/systemd/system/relay-server.service

  [Unit]
  Description=mknoon relay server
  After=network.target

  [Service]
  Type=simple
  ExecStart=/usr/local/bin/relay-server
  WorkingDirectory=/usr/local/bin
  Restart=on-failure
  RestartSec=5
  Environment=FIREBASE_SERVICE_ACCOUNT=/etc/mknoon/firebase-service-account.json

  [Install]
  WantedBy=multi-user.target

  3. Enable and start:

  sudo mkdir -p /data/media
  sudo systemctl daemon-reload
  sudo systemctl enable relay-server
  sudo systemctl start relay-server

  Common commands:

  sudo systemctl status relay-server    # check status
  sudo journalctl -u relay-server -f    # tail logs
  sudo systemctl restart relay-server   # restart after rebuild

  Adjust the FIREBASE_SERVICE_ACCOUNT path to wherever your service account JSON lives on the EC2 instance.