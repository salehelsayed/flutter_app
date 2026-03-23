 From your Mac, run:

  ssh -i se.pem -L 3000:localhost:3000 ubuntu@13.60.15.36

  Then open in your browser:
  - http://localhost:3000 — Grafana home (login: admin / admin)
  - http://localhost:3000/d/ec2-host-metrics — EC2 Host Metrics
   dashboard
  - http://localhost:3000/d/relay-server-overview — Relay
  Server Overview dashboard