# IPv6 Infrastructure & Ops Checklist

## Current Infrastructure

| Component | Value |
|-----------|-------|
| **Cloud provider** | AWS EC2 |
| **Public IPv4** | `13.60.15.36` |
| **Domain** | `mknoun.xyz` |
| **SSH** | `ssh ec2-user@mknoun.xyz` |
| **Reverse proxy** | nginx (TLS termination: WSS:4001 → WS:4000) |
| **Systemd service** | `/etc/systemd/system/relay-server.service` |
| **Binary path** | `/usr/local/bin/relay-server` |
| **Monitoring** | Prometheus `:9090`, node_exporter `:9100`, relay metrics `:2112` |

### Current Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 4000 | TCP/WS | WebSocket (local only — nginx proxies from 4001) |
| 4001 | TCP/WSS | WebSocket Secure (nginx TLS termination) |
| 4002 | UDP/QUIC | QUIC-v1 (direct, no proxy) |
| 4005 | TCP | Raw TCP |

---

## Step 1: Assign IPv6 Address to EC2 Instance

### 1a. Enable IPv6 on VPC

If the VPC doesn't already have an IPv6 CIDR block:

```
AWS Console → VPC → Your VPC → Actions → Edit CIDRs → Add IPv6 CIDR
  → Select "Amazon-provided IPv6 CIDR block"
```

### 1b. Enable IPv6 on Subnet

```
AWS Console → VPC → Subnets → Your Subnet → Actions → Edit IPv6 CIDRs
  → Assign an IPv6 CIDR from the VPC's block
```

### 1c. Update Route Table

Add a route for IPv6 traffic to the Internet Gateway:

```
AWS Console → VPC → Route Tables → Your Route Table → Edit Routes
  → Add: Destination `::/0`, Target: igw-xxxxx (same Internet Gateway as IPv4)
```

### 1d. Assign IPv6 to EC2 Instance

```
AWS Console → EC2 → Instances → Your Instance → Actions → Networking
  → Manage IP Addresses → Assign new IPv6 address (auto-assign)
```

Or via CLI:

```bash
# Find the ENI (network interface) ID
aws ec2 describe-instances --instance-ids i-XXXXX \
  --query 'Reservations[0].Instances[0].NetworkInterfaces[0].NetworkInterfaceId' \
  --output text

# Assign IPv6
aws ec2 assign-ipv6-addresses --network-interface-id eni-XXXXX --ipv6-address-count 1
```

### 1e. Verify on the Instance

```bash
ssh ec2-user@mknoun.xyz

# Should show an IPv6 address (2a05:... or 2600:... depending on region)
ip -6 addr show eth0

# Test IPv6 connectivity
ping6 -c 3 google.com
```

**Record the IPv6 address** — you'll need it for DNS and security group steps.

---

## Step 2: Security Group — Allow IPv6 Traffic

The existing security group allows IPv4 traffic on ports 4001, 4002, 4005. Add equivalent IPv6 rules:

```
AWS Console → EC2 → Security Groups → Your SG → Inbound Rules → Edit

Add these rules:
  Type: Custom TCP    Port: 4001   Source: ::/0   (WSS)
  Type: Custom TCP    Port: 4005   Source: ::/0   (TCP)
  Type: Custom UDP    Port: 4002   Source: ::/0   (QUIC)
```

Or via CLI:

```bash
SG_ID=sg-XXXXX

aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --ip-permissions \
    IpProtocol=tcp,FromPort=4001,ToPort=4001,Ipv6Ranges='[{CidrIpv6=::/0}]' \
    IpProtocol=tcp,FromPort=4005,ToPort=4005,Ipv6Ranges='[{CidrIpv6=::/0}]' \
    IpProtocol=udp,FromPort=4002,ToPort=4002,Ipv6Ranges='[{CidrIpv6=::/0}]'
```

---

## Step 3: DNS — Add AAAA Record

Add an IPv6 DNS record for `mknoun.xyz`:

```
DNS Provider (Route53 / Cloudflare / etc.)
  → Add record:
    Type: AAAA
    Name: mknoun.xyz
    Value: <IPv6 address from Step 1e>
    TTL: 300 (5 min, lower while testing)
```

### Verify DNS Resolution

```bash
# Should return the IPv6 address
dig AAAA mknoun.xyz

# Should return both A and AAAA
dig mknoun.xyz ANY

# Test from another machine
host mknoun.xyz
```

**Important**: Once the AAAA record is live and client code uses `/dns/` (from the IPv6 code plan), clients will start attempting IPv6 connections to the relay. The relay server must be listening on IPv6 (Step 5) before this goes live.

### Rollout Order

To avoid a window where clients try IPv6 but the server isn't ready:

1. Deploy relay server code with IPv6 listen addresses (Step 5) **first**
2. Add AAAA record **second**

Or: keep using `/dns4/` in client code until the server is fully ready, then flip both the AAAA record and the client `dns4` → `dns` change together.

---

## Step 4: nginx — Listen on IPv6

nginx currently handles TLS termination for WSS. Update it to also listen on IPv6.

```bash
ssh ec2-user@mknoun.xyz
sudo vi /etc/nginx/conf.d/relay.conf  # or wherever the config lives
```

Current (IPv4 only):
```nginx
server {
    listen 4001 ssl;
    # ...
}
```

Updated (dual-stack):
```nginx
server {
    listen 4001 ssl;
    listen [::]:4001 ssl;   # ← ADD THIS
    # ... rest unchanged ...
}
```

```bash
# Test config
sudo nginx -t

# Reload
sudo systemctl reload nginx
```

### Verify

```bash
# Should show both IPv4 and IPv6 listeners
sudo ss -tlnp | grep 4001
# Expected:
#   tcp  LISTEN  0  128  0.0.0.0:4001  ...  nginx
#   tcp  LISTEN  0  128     [::]:4001  ...  nginx
```

---

## Step 5: Relay Server Code — Add IPv6 Listen Addresses

**This is the only code change in `go-relay-server/`.** It's minimal and optional — the server works fine without it, but adding IPv6 listen addresses allows IPv6-capable clients to connect directly to the relay over IPv6.

### 5a. Update listen addresses in `main.go`

```go
// main.go — listen on both IPv4 and IPv6
libp2p.ListenAddrStrings(
    // IPv4
    fmt.Sprintf("/ip4/0.0.0.0/tcp/%d/ws", wsPort),
    fmt.Sprintf("/ip4/0.0.0.0/tcp/%d", tcpPort),
    fmt.Sprintf("/ip4/0.0.0.0/udp/%d/quic-v1", quicPort),
    // IPv6
    fmt.Sprintf("/ip6/::/tcp/%d/ws", wsPort),
    fmt.Sprintf("/ip6/::/tcp/%d", tcpPort),
    fmt.Sprintf("/ip6/::/udp/%d/quic-v1", quicPort),
),
```

### 5b. Update announce addresses in `main.go`

Add IPv6 announce addresses so peers know they can reach the relay via IPv6:

```go
// Add a serverIP6 constant (or read from env)
const serverIP6 = "2a05:xxxx:xxxx::xxxx"  // ← your IPv6 from Step 1e

announceAddrs := []ma.Multiaddr{
    // IPv4 (existing)
    ma.StringCast(fmt.Sprintf("/dns4/%s/tcp/%d/wss", serverDNS, wssPort)),
    ma.StringCast(fmt.Sprintf("/ip4/%s/tcp/%d", serverIP4, tcpPort)),
    ma.StringCast(fmt.Sprintf("/dns4/%s/udp/%d/quic-v1", serverDNS, quicPort)),
    // IPv6 (new)
    ma.StringCast(fmt.Sprintf("/dns6/%s/tcp/%d/wss", serverDNS, wssPort)),
    ma.StringCast(fmt.Sprintf("/ip6/%s/tcp/%d", serverIP6, tcpPort)),
    ma.StringCast(fmt.Sprintf("/dns6/%s/udp/%d/quic-v1", serverDNS, quicPort)),
}
```

**Alternative (simpler)**: Use `/dns/` instead of separate `/dns4/` + `/dns6/`:

```go
announceAddrs := []ma.Multiaddr{
    ma.StringCast(fmt.Sprintf("/dns/%s/tcp/%d/wss", serverDNS, wssPort)),
    ma.StringCast(fmt.Sprintf("/ip4/%s/tcp/%d", serverIP4, tcpPort)),
    ma.StringCast(fmt.Sprintf("/ip6/%s/tcp/%d", serverIP6, tcpPort)),
    ma.StringCast(fmt.Sprintf("/dns/%s/udp/%d/quic-v1", serverDNS, quicPort)),
}
```

### 5c. Build and deploy

```bash
ssh ec2-user@mknoun.xyz
cd ~/go-relay-server   # or wherever the source lives
make build
sudo cp relay-server /usr/local/bin/relay-server
sudo systemctl restart relay-server
```

---

## Step 6: Verify End-to-End

### 6a. Verify relay server listens on IPv6

```bash
ssh ec2-user@mknoun.xyz

# Check TCP listeners
sudo ss -tlnp | grep -E '4000|4001|4005'
# Should show [::] entries alongside 0.0.0.0

# Check UDP listeners (QUIC)
sudo ss -ulnp | grep 4002
# Should show [::] entry

# Check relay-server logs
sudo journalctl -u relay-server -f
# Should log IPv6 listen addresses
```

### 6b. Test IPv6 connectivity from outside

```bash
# From a machine with IPv6 (or use an IPv6 proxy/VPS)

# TCP test
nc -6 -zv mknoun.xyz 4005

# QUIC test (if you have a QUIC client)
# Or just verify DNS resolves both:
dig AAAA mknoun.xyz
dig A mknoun.xyz
```

### 6c. Test with a mobile client

1. Connect phone to an IPv6-capable network (e.g., T-Mobile)
2. Start the app
3. Check logs for listen addresses — should include `/ip6/` entries
4. Verify relay connection succeeds
5. Check connection transport — may show IPv6 if both client and relay support it

---

## Step 7: Monitoring

### 7a. Prometheus — no changes needed

The relay server exposes metrics on `:2112/metrics`. These are protocol-agnostic — connection counts, relay reservation counts, etc. They already capture IPv6 connections.

### 7b. Optional: Track IPv6 vs IPv4 connections

If you want to distinguish IPv6 vs IPv4 connections in metrics, add a Prometheus label in the connection event handler. This is optional and low-priority.

---

## Rollout Checklist

Execute in this order to avoid any window where clients try IPv6 but the server isn't ready:

| # | Task | Where | Reversible? |
|---|------|-------|-------------|
| 1 | Enable IPv6 on VPC/Subnet | AWS Console | Yes |
| 2 | Assign IPv6 to EC2 instance | AWS Console | Yes |
| 3 | Add IPv6 security group rules | AWS Console | Yes (remove rules) |
| 4 | Verify IPv6 connectivity on instance (`ping6 google.com`) | SSH | N/A |
| 5 | Update nginx to listen on `[::]:4001` | SSH + nginx config | Yes (remove line) |
| 6 | Update relay server code: add IPv6 listen + announce | Code + deploy | Yes (revert + redeploy) |
| 7 | Verify relay listens on IPv6 (`ss -tlnp`) | SSH | N/A |
| 8 | Add AAAA DNS record for `mknoun.xyz` | DNS provider | Yes (delete record) |
| 9 | Verify DNS resolves both A + AAAA | `dig` | N/A |
| 10 | Deploy client code: `dns4` → `dns` in relay constants | Client release | Yes (revert) |
| 11 | Verify mobile client connects via IPv6 | Device testing | N/A |

**Rollback**: If anything goes wrong, remove the AAAA record (Step 8) and clients immediately fall back to IPv4. All other steps can be reverted independently.

---

## Cost / Risk Summary

| Item | Impact |
|------|--------|
| **AWS cost** | IPv6 on EC2 is free (no additional charge for IPv6 addresses) |
| **Downtime** | Zero — all changes are additive (IPv4 continues to work throughout) |
| **Rollback time** | ~1 minute (delete AAAA record → clients use IPv4) |
| **nginx restart** | `reload` (graceful, no dropped connections) |
| **relay-server restart** | ~2 seconds (systemd restart, clients auto-reconnect) |
