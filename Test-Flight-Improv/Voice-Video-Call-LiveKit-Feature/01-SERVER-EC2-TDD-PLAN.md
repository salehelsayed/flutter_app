# LiveKit Server — EC2 Deployment TDD Plan

> A dedicated EC2 instance handling voice/video calls for mknoon via LiveKit.

---

## Architecture Overview

```
┌──────────────┐         ┌──────────────────────────┐
│  mknoon app  │◄──wss──►│     EC2 (LiveKit SFU)    │
│  (Flutter)   │  media   │                          │
│              │◄──UDP───►│  Caddy (:443) ──► LK     │
└──────────────┘          │  Redis  TURN  Webhooks   │
                          └──────────────────────────┘
                                     ▲
                                     │ call signal
                          ┌──────────┴──────────┐
                          │  mknoon relay server │
                          │  (existing libp2p)   │
                          └─────────────────────┘
```

**Flow:**
1. Caller sends a `call_signal` message via existing libp2p P2P messaging (invite with room name)
2. Both peers generate LiveKit JWT tokens via a Go token-generation endpoint on this server
3. Both peers connect to the LiveKit room via WebSocket + WebRTC
4. LiveKit SFU handles all media routing, TURN, ICE, and quality adaptation
5. Call ends → room auto-closes after `empty_timeout`

---

## Phase 0: Infrastructure Prerequisites

### 0.1 EC2 Instance Selection

| Requirement | Choice | Rationale |
|-------------|--------|-----------|
| Instance type | `c5.xlarge` (4 vCPU, 8 GB) | Compute-optimized; estimated capacity must be validated via load test |
| OS | Ubuntu 22.04 LTS | Docker + LK docs target Ubuntu |
| Storage | 20 GB gp3 | Minimal — LK is stateless, logs rotate |
| Region | Same as relay server | Minimize latency to existing infra |

### 0.2 DNS Records

| Record | Type | Value |
|--------|------|-------|
| `lk.mknoon.xyz` | A | EC2 public IP |
| `turn.mknoon.xyz` | A | EC2 public IP |

### 0.3 Security Group / Firewall

| Port | Protocol | Direction | Purpose |
|------|----------|-----------|---------|
| 22 | TCP | Inbound (restricted to admin CIDRs only) | SSH admin — restrict to known IPs/VPN, never `0.0.0.0/0` |
| 80 | TCP | Inbound | Let's Encrypt ACME challenge (Caddy auto-renewal) |
| 443 | TCP + UDP | Inbound | HTTPS (Caddy) + TURN/TLS via L4 proxy |
| 7881 | TCP | Inbound | WebRTC ICE over TCP fallback (must NOT be behind TLS/LB) |
| 50000–60000 | UDP | Inbound | WebRTC media (ICE/UDP) — must match `rtc.port_range_start/end` in livekit.yaml |
| 3478 | UDP | Inbound | STUN + TURN/UDP |

> **Security notes:**
> - Port `6789` (Prometheus) must NOT be in the security group. Bind to `127.0.0.1` only and scrape via SSH tunnel or VPC-internal host.
> - Port `8080` (token service) must NOT be in the security group. All external traffic enters via Caddy on 443 and is reverse-proxied internally.
> - SSH (port 22) must be restricted to known admin CIDR ranges, not open to `0.0.0.0/0`. Ensure `PasswordAuthentication no` and `PermitRootLogin no` in sshd_config.

---

## Phase 1: Server Installation — TDD Steps

### Test 1.1: Docker & Docker Compose are installed

```bash
# TEST: verify docker is running
docker --version   # expect: Docker version 24+
docker compose version  # expect: v2+

# IMPLEMENT:
sudo apt update && sudo apt install -y docker.io docker-compose-plugin
sudo systemctl enable docker && sudo systemctl start docker
sudo usermod -aG docker ubuntu
```

**Red:** `docker --version` fails.
**Green:** Docker daemon running, user can run `docker ps`.

---

### Test 1.2: LiveKit config generated

```bash
# TEST: config files exist
ls /opt/livekit/livekit.yaml
ls /opt/livekit/caddy.yaml
ls /opt/livekit/docker-compose.yaml
ls /opt/livekit/redis.conf

# IMPLEMENT:
sudo mkdir -p /opt/livekit
docker run --rm -v /opt/livekit:/output livekit/generate \
  --local  # then customize below
```

**Red:** Files don't exist.
**Green:** All four config files present at `/opt/livekit/`.

---

### Test 1.3: LiveKit config is correct

```yaml
# /opt/livekit/livekit.yaml
# TEST: validate these fields are set correctly

port: 7880

keys:
  # Generate a secure random key pair
  # TEST: key and secret are at least 16 chars
  MKNOON_LK_KEY: <generate-32-char-secret>

rtc:
  port_range_start: 50000
  port_range_end: 60000
  tcp_port: 7881
  use_external_ip: true      # CRITICAL for EC2

redis:
  address: localhost:6379
  password: ${REDIS_PASSWORD}      # REQUIRED — never run Redis without auth

room:
  empty_timeout: 300          # 5 min — auto-cleanup idle rooms
  departure_timeout: 20
  max_participants: 20        # support group calls up to 20

turn:
  enabled: true
  udp_port: 3478
  tls_port: 5349
  domain: turn.mknoon.xyz
  external_tls: true          # Caddy L4 terminates TLS — LiveKit receives unencrypted TURN on 5349

prometheus_port: 6789         # Bind to 127.0.0.1 only — NEVER expose to internet

logging:
  level: info
  pion_level: error
  json: true
```

**Red:** Config has placeholder values or missing `use_external_ip`.
**Green:** Config validated, all critical fields set.

**Test script:**
```bash
# Validate config parses correctly
docker run --rm \
  -v /opt/livekit/livekit.yaml:/livekit.yaml \
  livekit/livekit-server \
  --config /livekit.yaml \
  --help  # exits 0 if config is parseable
```

---

### Test 1.4: Caddy reverse proxy config

> **Important:** `livekit/caddyl4` is a Caddy build with Layer 4 support. The LiveKit API/WebSocket
> endpoint uses standard L7 HTTP reverse proxy. The TURN/TLS endpoint requires **L4 TLS passthrough**
> (not HTTP reverse proxy), because TURN operates at L4 (TCP/UDP), not L7.

```yaml
# /opt/livekit/caddy.yaml
# TEST: correct domains, L7 for API, L4 for TURN

# L7 — HTTP/WebSocket reverse proxy for LiveKit API
{
  email: admin@mknoon.xyz
}

lk.mknoon.xyz {
  reverse_proxy localhost:7880
}

# L4 — TLS termination + TCP proxy for TURN
# This uses Caddy L4 module syntax (caddyl4 image required)
# TURN traffic is NOT HTTP — it is raw TCP/UDP and must use L4 proxy
{
  layer4 {
    turn.mknoon.xyz:443 {
      tls
      proxy localhost:5349
    }
  }
}
```

> **Note:** The exact L4 syntax depends on caddyl4 version. Refer to LiveKit's official
> `docker-compose` generator output for the canonical Caddy config. The key requirement is that
> TURN port 5349 receives TLS-terminated traffic via L4 proxy, matching `external_tls: true` in livekit.yaml.

**Red:** Caddy config points to wrong domains or uses HTTP reverse_proxy for TURN.
**Green:** Caddy serves TLS for API (L7) and TURN (L4), proxies correctly to LiveKit.

---

### Test 1.5: Docker Compose stack starts

```yaml
# /opt/livekit/docker-compose.yaml
# NOTE: 'version' key is deprecated in Compose Specification v2+ and is omitted
services:
  caddy:
    image: livekit/caddyl4:latest  # Pin to specific tag in production
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"       # QUIC
      - "5349:5349"         # TURN/TLS (L4 proxy)
    volumes:
      - ./caddy.yaml:/etc/caddy.yaml
      - caddy_data:/data
    command: run --config /etc/caddy.yaml
    restart: unless-stopped
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "3"

  livekit:
    image: livekit/livekit-server:v1.10.1  # PINNED — never use :latest in production
    ports:
      - "7880:7880"         # API/WebSocket (internal, proxied via Caddy)
      - "7881:7881"         # ICE/TCP fallback (must be direct, not behind TLS)
      - "3478:3478/udp"     # STUN + TURN/UDP
      - "50000-60000:50000-60000/udp"  # WebRTC media
    volumes:
      - ./livekit.yaml:/etc/livekit.yaml
    command: --config /etc/livekit.yaml
    restart: unless-stopped
    depends_on:
      - redis
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "3"

  redis:
    image: redis:7-alpine
    command: redis-server --requirepass ${REDIS_PASSWORD} --appendonly yes --save 60 1
    volumes:
      - redis_data:/data
    restart: unless-stopped
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "3"

  token-service:
    build: ./token-service
    # Port 8080 is NOT published to host — only accessible via Docker network + Caddy proxy
    expose:
      - "8080"
    environment:
      - LK_API_KEY=${LK_API_KEY}
      - LK_API_SECRET=${LK_API_SECRET}
      - APP_SECRET=${APP_SECRET}
    restart: unless-stopped
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "3"

volumes:
  caddy_data:
  redis_data:
```

> **Key changes from initial draft:**
> - LiveKit pinned to `v1.10.1` — never use `:latest` in production
> - Redis has `--requirepass`, `--appendonly yes`, and `--save 60 1` for persistence
> - Token service uses `expose` (not `ports`) — only reachable via internal Docker network, proxied through Caddy
> - All services have log rotation (50 MB, 3 files)
> - `version` key removed (deprecated in modern Compose)

```bash
# TEST: all containers running
cd /opt/livekit && docker compose up -d
docker compose ps  # expect: 3 services running (caddy, livekit, redis)

# TEST: LiveKit responding
curl -s https://lk.mknoon.xyz  # expect: HTTP response (not timeout)
```

**Red:** Containers crash or don't start.
**Green:** All 3 containers healthy, HTTPS endpoint responding.

---

### Test 1.6: systemd service for auto-start

```bash
# /etc/systemd/system/livekit-docker.service
[Unit]
Description=LiveKit Docker Compose
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/livekit
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down

[Install]
WantedBy=multi-user.target
```

```bash
# TEST: service starts on boot
sudo systemctl enable livekit-docker
sudo systemctl start livekit-docker
sudo systemctl status livekit-docker  # expect: active

# TEST: survives reboot
sudo reboot
# After reboot:
docker compose -f /opt/livekit/docker-compose.yaml ps  # expect: 3 running
```

**Red:** Services don't auto-start after reboot.
**Green:** All containers running after reboot.

---

## Phase 2: Token Generation Service — TDD Steps

> A lightweight Go HTTP service running on the same EC2 that generates LiveKit JWT tokens.
> The mknoon app calls this endpoint to get a token before joining a room.

### Test 2.1: Go token generation module

```go
// File: /opt/livekit/token-service/token_test.go
package main

import (
    "testing"
    "time"

    "github.com/livekit/protocol/auth"
    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/require"
)

func TestGenerateToken_ValidJWT(t *testing.T) {
    apiKey := "testkey"
    apiSecret := "testsecretatleast16chars"

    token, err := generateToken(apiKey, apiSecret, "room-123", "user-alice", 10*time.Minute)
    require.NoError(t, err)
    assert.NotEmpty(t, token)

    // Verify the token is valid JWT that can be parsed
    verifier, err := auth.ParseAPIToken(token)
    require.NoError(t, err)
    assert.Equal(t, apiKey, verifier.APIKey())

    // Verify claims
    claims, err := verifier.Verify(apiSecret)
    require.NoError(t, err)
    assert.Equal(t, "user-alice", claims.Identity)
    assert.True(t, claims.Video.RoomJoin)
    assert.Equal(t, "room-123", claims.Video.Room)
}

func TestGenerateToken_DifferentRooms(t *testing.T) {
    apiKey := "testkey"
    apiSecret := "testsecretatleast16chars"

    t1, _ := generateToken(apiKey, apiSecret, "room-a", "alice", time.Hour)
    t2, _ := generateToken(apiKey, apiSecret, "room-b", "alice", time.Hour)
    assert.NotEqual(t, t1, t2) // Different rooms produce different tokens
}

func TestGenerateToken_CanPublishAudioVideo(t *testing.T) {
    apiKey := "testkey"
    apiSecret := "testsecretatleast16chars"

    token, _ := generateToken(apiKey, apiSecret, "room-1", "alice", time.Hour)
    verifier, _ := auth.ParseAPIToken(token)
    claims, _ := verifier.Verify(apiSecret)

    // Must be able to publish audio and video
    assert.Nil(t, claims.Video.CanPublish) // nil = default true
    assert.Nil(t, claims.Video.CanSubscribe)
}
```

```go
// File: /opt/livekit/token-service/token.go
package main

import (
    "time"
    "github.com/livekit/protocol/auth"
)

func generateToken(apiKey, apiSecret, room, identity string, ttl time.Duration) (string, error) {
    at := auth.NewAccessToken(apiKey, apiSecret)
    grant := &auth.VideoGrant{
        RoomJoin: true,
        Room:     room,
    }
    at.SetVideoGrant(grant).
        SetIdentity(identity).
        SetValidFor(ttl)
    return at.ToJWT()
}
```

**Red:** Test fails — function doesn't exist.
**Green:** Token generated, JWT valid, claims correct.

---

### Test 2.2: HTTP endpoint for token generation

```go
// File: /opt/livekit/token-service/server_test.go
package main

import (
    "encoding/json"
    "net/http"
    "net/http/httptest"
    "testing"

    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/require"
)

func TestTokenEndpoint_Success(t *testing.T) {
    srv := newTokenServer("testkey", "testsecretatleast16chars")

    req := httptest.NewRequest("GET", "/token?room=call-123&identity=alice", nil)
    req.Header.Set("Authorization", "Bearer <app-shared-secret>")
    w := httptest.NewRecorder()

    srv.ServeHTTP(w, req)

    assert.Equal(t, http.StatusOK, w.Code)

    var resp map[string]string
    err := json.Unmarshal(w.Body.Bytes(), &resp)
    require.NoError(t, err)
    assert.NotEmpty(t, resp["token"])
}

func TestTokenEndpoint_MissingRoom(t *testing.T) {
    srv := newTokenServer("testkey", "testsecretatleast16chars")

    req := httptest.NewRequest("GET", "/token?identity=alice", nil)
    req.Header.Set("Authorization", "Bearer <app-shared-secret>")
    w := httptest.NewRecorder()

    srv.ServeHTTP(w, req)

    assert.Equal(t, http.StatusBadRequest, w.Code)
}

func TestTokenEndpoint_MissingIdentity(t *testing.T) {
    srv := newTokenServer("testkey", "testsecretatleast16chars")

    req := httptest.NewRequest("GET", "/token?room=call-123", nil)
    req.Header.Set("Authorization", "Bearer <app-shared-secret>")
    w := httptest.NewRecorder()

    srv.ServeHTTP(w, req)

    assert.Equal(t, http.StatusBadRequest, w.Code)
}

func TestTokenEndpoint_Unauthorized(t *testing.T) {
    srv := newTokenServer("testkey", "testsecretatleast16chars")

    req := httptest.NewRequest("GET", "/token?room=call-123&identity=alice", nil)
    // No auth header
    w := httptest.NewRecorder()

    srv.ServeHTTP(w, req)

    assert.Equal(t, http.StatusUnauthorized, w.Code)
}
```

```go
// File: /opt/livekit/token-service/server.go
package main

import (
    "encoding/json"
    "net/http"
    "time"
)

type tokenServer struct {
    apiKey    string
    apiSecret string
    appSecret string // shared secret for mknoon app auth
    mux       *http.ServeMux
}

func newTokenServer(apiKey, apiSecret string) *tokenServer {
    s := &tokenServer{apiKey: apiKey, apiSecret: apiSecret}
    s.mux = http.NewServeMux()
    s.mux.HandleFunc("/token", s.handleToken)
    s.mux.HandleFunc("/health", s.handleHealth)
    return s
}

func (s *tokenServer) ServeHTTP(w http.ResponseWriter, r *http.Request) {
    s.mux.ServeHTTP(w, r)
}

func (s *tokenServer) handleToken(w http.ResponseWriter, r *http.Request) {
    // Auth check — validate shared secret
    authHeader := r.Header.Get("Authorization")
    if authHeader == "" || authHeader != "Bearer "+s.appSecret {
        http.Error(w, "unauthorized", http.StatusUnauthorized)
        return
    }

    // Rate limiting — per-IP, using X-Forwarded-For if behind Caddy
    ip := extractClientIP(r) // uses X-Forwarded-For → RemoteAddr fallback
    if s.rateLimiter.IsLimited(ip) {
        http.Error(w, "rate limit exceeded", http.StatusTooManyRequests)
        return
    }

    room := r.URL.Query().Get("room")
    identity := r.URL.Query().Get("identity")
    if room == "" || identity == "" {
        http.Error(w, "room and identity required", http.StatusBadRequest)
        return
    }

    // Room name validation — allowlist pattern only
    if !isValidRoomName(room) {
        http.Error(w, "invalid room name", http.StatusBadRequest)
        return
    }

    // Short TTL (10 min) — clients must refresh if call exceeds this
    token, err := generateToken(s.apiKey, s.apiSecret, room, identity, 10*time.Minute)
    if err != nil {
        http.Error(w, "token generation failed", http.StatusInternalServerError)
        return
    }

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(map[string]string{"token": token})
}

// extractClientIP returns the client IP, checking X-Forwarded-For first (Caddy sets this)
func extractClientIP(r *http.Request) string {
    if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
        // Take first IP in chain (original client)
        if idx := strings.Index(xff, ","); idx > 0 {
            return strings.TrimSpace(xff[:idx])
        }
        return strings.TrimSpace(xff)
    }
    host, _, _ := net.SplitHostPort(r.RemoteAddr)
    return host
}

// isValidRoomName enforces allowlist: call-<peerId>-<peerId> or group-<groupId>
// Max 128 chars, alphanumeric + hyphens only
var validRoomNameRegex = regexp.MustCompile(`^(call|group)-[a-zA-Z0-9-]{1,120}$`)

func isValidRoomName(name string) bool {
    return validRoomNameRegex.MatchString(name)
}

func (s *tokenServer) handleHealth(w http.ResponseWriter, r *http.Request) {
    w.WriteHeader(http.StatusOK)
    w.Write([]byte("ok"))
}
```

**Red:** Tests fail — server doesn't exist.
**Green:** All 4 endpoint tests pass.

---

### Test 2.3: Token service runs as Docker container alongside LiveKit

```dockerfile
# /opt/livekit/token-service/Dockerfile
FROM golang:1.24-alpine AS build
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
RUN CGO_ENABLED=0 go build -o token-service .

FROM alpine:3.19
COPY --from=build /app/token-service /token-service
EXPOSE 8080
CMD ["/token-service"]
```

> Token service is already included in the docker-compose.yaml above (Phase 1.5).
> It uses `expose: ["8080"]` (not `ports`) — accessible only via Docker network + Caddy reverse proxy.
> External access is via `https://lk.mknoon.xyz/token` (Caddy proxies to token-service:8080).

Caddy config addition for token service proxy:
```yaml
# Add to lk.mknoon.xyz block in caddy.yaml:
lk.mknoon.xyz {
  # Token service
  handle /token* {
    reverse_proxy token-service:8080
  }
  handle /health* {
    reverse_proxy token-service:8080
  }
  handle /webhook* {
    reverse_proxy token-service:8080
  }
  # LiveKit API/WebSocket (default)
  handle {
    reverse_proxy livekit:7880
  }
}
```

```bash
# TEST: token service responds via Caddy (HTTPS)
curl -s -H "Authorization: Bearer $APP_SECRET" \
  "https://lk.mknoon.xyz/token?room=call-test&identity=test-user"
# expect: {"token": "eyJ..."}

# TEST: token service NOT directly reachable on port 8080
curl -s --connect-timeout 3 "http://<EC2-PUBLIC-IP>:8080/health"
# expect: connection refused
```

**Red:** Endpoint unreachable or returns error.
**Green:** Returns valid JWT token.

---

## Phase 3: Webhook Handler — TDD Steps

> Receives LiveKit webhook events (room started/finished, participant joined/left)
> for logging, analytics, and optional push notification triggers.

### Test 3.1: Webhook signature verification

> **Important:** LiveKit webhooks use HMAC-SHA256 of the request body, NOT plain JWT.
> Use `webhook.ReceiveWebhookEvent()` with `auth.NewSimpleKeyProvider()` — this validates
> both the JWT signature AND the body integrity hash in the claims.

```go
// File: /opt/livekit/token-service/webhook_test.go
package main

import (
    "bytes"
    "net/http"
    "net/http/httptest"
    "testing"

    "github.com/livekit/protocol/auth"
    "github.com/livekit/protocol/livekit"
    "github.com/livekit/protocol/webhook"
    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/require"
    "google.golang.org/protobuf/encoding/protojson"
)

func TestWebhook_ValidSignature(t *testing.T) {
    apiKey := "testkey"
    apiSecret := "testsecretatleast16chars"
    srv := newTokenServer(apiKey, apiSecret)

    // Create a webhook event
    event := &livekit.WebhookEvent{
        Event: "room_started",
        Room:  &livekit.Room{Name: "call-123"},
    }
    body, _ := protojson.Marshal(event)

    // Sign the webhook using the CORRECT method: webhook.NewURLNotifier
    // which produces the same HMAC-SHA256 signature LiveKit server uses
    notifier := webhook.NewURLNotifier(webhook.URLNotifierParams{
        APIKey:    apiKey,
        APISecret: apiSecret,
        URLs:      []string{"http://localhost/webhook"},
    })
    // Alternatively, manually create a signed token with body hash:
    at := auth.NewAccessToken(apiKey, apiSecret)
    // The hash of the body must be in the claims for ReceiveWebhookEvent to verify
    at.SetSha256(string(body))
    at.SetValidFor(time.Minute)
    token, _ := at.ToJWT()

    req := httptest.NewRequest("POST", "/webhook", bytes.NewReader(body))
    req.Header.Set("Authorization", token)
    w := httptest.NewRecorder()

    srv.ServeHTTP(w, req)
    assert.Equal(t, http.StatusOK, w.Code)
}

func TestWebhook_InvalidSignature(t *testing.T) {
    srv := newTokenServer("testkey", "testsecretatleast16chars")

    req := httptest.NewRequest("POST", "/webhook", bytes.NewReader([]byte("{}")))
    req.Header.Set("Authorization", "invalid-token")
    w := httptest.NewRecorder()

    srv.ServeHTTP(w, req)
    assert.Equal(t, http.StatusUnauthorized, w.Code)
}

func TestWebhook_TamperedBody(t *testing.T) {
    apiKey := "testkey"
    apiSecret := "testsecretatleast16chars"
    srv := newTokenServer(apiKey, apiSecret)

    originalBody := []byte(`{"event":"room_started"}`)
    tamperedBody := []byte(`{"event":"room_finished"}`)

    // Sign with original body
    at := auth.NewAccessToken(apiKey, apiSecret)
    at.SetSha256(string(originalBody))
    at.SetValidFor(time.Minute)
    token, _ := at.ToJWT()

    // Send tampered body with original signature — must be rejected
    req := httptest.NewRequest("POST", "/webhook", bytes.NewReader(tamperedBody))
    req.Header.Set("Authorization", token)
    w := httptest.NewRecorder()

    srv.ServeHTTP(w, req)
    assert.Equal(t, http.StatusUnauthorized, w.Code)
}
```

**Webhook handler implementation must use `webhook.ReceiveWebhookEvent()`:**
```go
func (s *tokenServer) handleWebhook(w http.ResponseWriter, r *http.Request) {
    authProvider := auth.NewSimpleKeyProvider(s.apiKey, s.apiSecret)
    event, err := webhook.ReceiveWebhookEvent(r, authProvider)
    if err != nil {
        http.Error(w, "unauthorized", http.StatusUnauthorized)
        return
    }
    // event is verified — process it
    log.Printf("webhook: %s room=%s", event.Event, event.Room.GetName())
    w.WriteHeader(http.StatusOK)
}
```

**Red:** Webhook handler doesn't exist.
**Green:** Valid signatures accepted, tampered bodies rejected, invalid signatures rejected.

---

### Test 3.2: Webhook event routing

```go
func TestWebhook_RoomFinished_LogsEvent(t *testing.T) {
    // Test that room_finished events are logged
    // This enables future analytics and missed-call detection
}

func TestWebhook_ParticipantJoined_LogsEvent(t *testing.T) {
    // Test that participant_joined is logged with room + identity
}
```

LiveKit config addition:
```yaml
webhook:
  api_key: MKNOON_LK_KEY
  urls:
    - http://localhost:8080/webhook
```

**Red:** Events not logged.
**Green:** Events received, verified, and logged.

---

## Phase 4: Monitoring & Operations — TDD Steps

### Test 4.1: Prometheus metrics exposed (internal only)

```bash
# TEST: metrics endpoint responds on localhost only
curl -s http://localhost:6789/metrics | grep livekit
# expect: livekit_room_count, livekit_participant_count, etc.

# TEST: metrics NOT reachable from external IP
curl -s --connect-timeout 3 http://<EC2-PUBLIC-IP>:6789/metrics
# expect: connection refused (port not in security group)
```

LiveKit config (already set in livekit.yaml above):
```yaml
prometheus_port: 6789  # Bound to 127.0.0.1 — NOT exposed in security group
```

> **Alerting:** Prometheus metrics alone are not sufficient for operations. Add at minimum:
> - Disk usage alert (>80%) via CloudWatch or a cron script
> - CPU sustained >80% for 5 min
> - Health check failure (token service `/health` endpoint)
> - Certificate expiry monitoring (Caddy certs valid for 90 days, auto-renew at 30 days)
> Consider deploying Alertmanager or using AWS SNS for notifications.

**Red:** No metrics.
**Green:** Prometheus metrics available on localhost only, not reachable externally.

---

### Test 4.2: Log rotation configured

```bash
# TEST: Docker logging has size limits
docker inspect livekit-livekit-1 --format '{{.HostConfig.LogConfig}}'
# expect: max-size set

# IMPLEMENT: in docker-compose.yaml, add to each service:
logging:
  driver: json-file
  options:
    max-size: "50m"
    max-file: "3"
```

**Red:** Logs grow unbounded.
**Green:** Logs rotate at 50 MB, max 3 files.

---

### Test 4.3: Health check endpoint

```bash
# TEST: health check returns 200
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health
# expect: 200
```

**Red:** No health endpoint.
**Green:** Returns 200.

---

## Phase 5: Security Hardening — TDD Steps

### Test 5.1: Token service only accessible via HTTPS

```bash
# TEST: HTTP redirects to HTTPS
curl -s -o /dev/null -w "%{http_code}" http://lk.mknoon.xyz/token
# expect: 301 redirect to https

# TEST: HTTPS works
curl -s -o /dev/null -w "%{http_code}" https://lk.mknoon.xyz/health
# expect: 200
```

---

### Test 5.2: App authentication on token endpoint

```bash
# TEST: request without auth is rejected
curl -s -o /dev/null -w "%{http_code}" \
  "https://lk.mknoon.xyz/token?room=test&identity=test"
# expect: 401

# TEST: request with valid auth succeeds
curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $APP_SECRET" \
  "https://lk.mknoon.xyz/token?room=test&identity=test"
# expect: 200
```

**Implementation:** The token service validates a shared secret (stored in env var `APP_SECRET`). The mknoon app stores this secret and sends it with token requests. This prevents unauthorized room creation.

---

### Test 5.3: Room name validation

```go
func TestTokenEndpoint_RejectsInvalidRoomName(t *testing.T) {
    srv := newTokenServer("testkey", "testsecretatleast16chars")

    // Room names must match pattern: call-<peerId1>-<peerId2> or group-<groupId>
    req := httptest.NewRequest("GET", "/token?room=../../../etc/passwd&identity=alice", nil)
    req.Header.Set("Authorization", "Bearer <secret>")
    w := httptest.NewRecorder()

    srv.ServeHTTP(w, req)
    assert.Equal(t, http.StatusBadRequest, w.Code)
}

func TestTokenEndpoint_AcceptsValidRoomName(t *testing.T) {
    srv := newTokenServer("testkey", "testsecretatleast16chars")

    req := httptest.NewRequest("GET",
        "/token?room=call-12D3KooW-12D3KooX&identity=12D3KooW", nil)
    req.Header.Set("Authorization", "Bearer <secret>")
    w := httptest.NewRecorder()

    srv.ServeHTTP(w, req)
    assert.Equal(t, http.StatusOK, w.Code)
}
```

---

### Test 5.4: Per-IP Rate limiting

```go
func TestTokenEndpoint_RateLimited_SameIP(t *testing.T) {
    srv := newTokenServer("testkey", "testsecretatleast16chars")
    srv.appSecret = "test-secret"

    // 20 rapid requests from same IP
    for i := 0; i < 20; i++ {
        req := httptest.NewRequest("GET", "/token?room=call-abc&identity=alice", nil)
        req.RemoteAddr = "192.168.1.100:12345"  // Same client IP
        req.Header.Set("Authorization", "Bearer test-secret")
        w := httptest.NewRecorder()
        srv.ServeHTTP(w, req)
    }

    // 21st from same IP should be rate limited
    req := httptest.NewRequest("GET", "/token?room=call-abc&identity=alice", nil)
    req.RemoteAddr = "192.168.1.100:12345"
    req.Header.Set("Authorization", "Bearer test-secret")
    w := httptest.NewRecorder()
    srv.ServeHTTP(w, req)
    assert.Equal(t, http.StatusTooManyRequests, w.Code)
}

func TestTokenEndpoint_RateLimit_DifferentIPs_NotLimited(t *testing.T) {
    srv := newTokenServer("testkey", "testsecretatleast16chars")
    srv.appSecret = "test-secret"

    // 20 requests from different IPs — should all succeed
    for i := 0; i < 20; i++ {
        req := httptest.NewRequest("GET", "/token?room=call-abc&identity=alice", nil)
        req.RemoteAddr = fmt.Sprintf("192.168.1.%d:12345", i+1)
        req.Header.Set("Authorization", "Bearer test-secret")
        w := httptest.NewRecorder()
        srv.ServeHTTP(w, req)
        assert.Equal(t, http.StatusOK, w.Code)
    }
}

func TestTokenEndpoint_RateLimit_XForwardedFor(t *testing.T) {
    srv := newTokenServer("testkey", "testsecretatleast16chars")
    srv.appSecret = "test-secret"

    // Rate limiting uses X-Forwarded-For (from Caddy) when present
    for i := 0; i < 20; i++ {
        req := httptest.NewRequest("GET", "/token?room=call-abc&identity=alice", nil)
        req.RemoteAddr = "10.0.0.1:12345"  // Caddy's internal IP
        req.Header.Set("X-Forwarded-For", "203.0.113.50")  // Real client IP
        req.Header.Set("Authorization", "Bearer test-secret")
        w := httptest.NewRecorder()
        srv.ServeHTTP(w, req)
    }

    // 21st from same forwarded IP should be limited
    req := httptest.NewRequest("GET", "/token?room=call-abc&identity=alice", nil)
    req.RemoteAddr = "10.0.0.1:12345"
    req.Header.Set("X-Forwarded-For", "203.0.113.50")
    req.Header.Set("Authorization", "Bearer test-secret")
    w := httptest.NewRecorder()
    srv.ServeHTTP(w, req)
    assert.Equal(t, http.StatusTooManyRequests, w.Code)
}
```

---

## Phase 6: Integration Testing — End-to-End

### Test 6.1: Full call flow with CLI

```bash
# Start local LiveKit
livekit-server --dev &

# Generate tokens for two users
TOKEN_A=$(lk token create --api-key devkey --api-secret secret \
  --join --room test-call --identity alice --valid-for 1h)
TOKEN_B=$(lk token create --api-key devkey --api-secret secret \
  --join --room test-call --identity bob --valid-for 1h)

# User A joins and publishes demo audio
lk room join --url ws://localhost:7880 \
  --api-key devkey --api-secret secret \
  --publish-demo --identity alice test-call &

# User B joins — should see Alice as participant
lk room join --url ws://localhost:7880 \
  --api-key devkey --api-secret secret \
  --identity bob test-call &

# Verify room has 2 participants
sleep 3
lk room list --url ws://localhost:7880 \
  --api-key devkey --api-secret secret
# expect: test-call with num_participants: 2
```

**Red:** Participants can't connect or see each other.
**Green:** Both participants in room, audio flowing.

---

### Test 6.2: Load test

```bash
# TEST: server handles 50 concurrent 1:1 rooms (100 participants)
lk load-test \
  --url wss://lk.mknoon.xyz \
  --api-key $LK_API_KEY --api-secret $LK_API_SECRET \
  --room load-test \
  --audio-publishers 100 \
  --subscribers 100 \
  --duration 60s

# expect: no errors, CPU < 80%
```

---

## Deployment Checklist

### Infrastructure
- [ ] EC2 instance launched (c5.xlarge, Ubuntu 22.04)
- [ ] Security group configured (ports: 80, 443, 3478/udp, 7881, 50000-60000/udp)
- [ ] SSH restricted to admin CIDRs only (NOT `0.0.0.0/0`)
- [ ] Port 6789 (Prometheus) NOT in security group
- [ ] Port 8080 (token service) NOT in security group
- [ ] DNS records created: `lk.mknoon.xyz`, `turn.mknoon.xyz`
- [ ] sshd hardened: `PasswordAuthentication no`, `PermitRootLogin no`

### Stack
- [ ] Docker + Docker Compose installed
- [ ] LiveKit config generated and customized (pinned to `v1.10.1`)
- [ ] `use_external_ip: true` set in LiveKit config
- [ ] `rtc.port_range_start/end` matches security group (50000-60000)
- [ ] Caddy config with L7 for API + L4 for TURN
- [ ] Redis configured with `requirepass` and `appendonly yes`
- [ ] Docker Compose stack starts successfully (4 services: caddy, livekit, redis, token-service)
- [ ] TLS certificates auto-provisioned (Caddy + Let's Encrypt)
- [ ] ACME renewal verified (port 80 reachable by Caddy)

### Token Service
- [ ] Token service built, deployed, accessible only via Caddy
- [ ] Auth check implemented (Bearer token validation)
- [ ] Room name validation (allowlist regex)
- [ ] Per-IP rate limiting
- [ ] Token TTL set to 10 minutes (with client-side refresh)
- [ ] Health check endpoint responding

### Webhooks & Monitoring
- [ ] Webhook handler receiving and verifying events (`webhook.ReceiveWebhookEvent()`)
- [ ] systemd service enabled for auto-start
- [ ] Log rotation configured (50 MB, 3 files per service)
- [ ] Prometheus metrics available on localhost:6789 only
- [ ] Alerting configured (disk >80%, CPU >80% sustained, health check failure)
- [ ] Certificate expiry monitoring

### Secrets
- [ ] All secrets generated (`openssl rand -base64 32`)
- [ ] `.env` file has `chmod 600` permissions
- [ ] App shared secret stored in SecureKeyStore on client side

### Validation
- [ ] Full call flow tested with CLI tools
- [ ] Load test passed (verify c5.xlarge capacity before claiming 100+ concurrent calls)
- [ ] TURN connectivity verified (test from behind symmetric NAT)

---

## Environment Variables

```bash
# /opt/livekit/.env
LK_API_KEY=MKNOON_LK_KEY          # LiveKit API key
LK_API_SECRET=<generate-32-char>   # LiveKit API secret
APP_SECRET=<generate-32-char>      # Shared secret for mknoon app → token service auth
REDIS_PASSWORD=<generate-32-char>  # Redis requirepass — used by both LiveKit and Redis container
```

Generate secrets:
```bash
openssl rand -base64 32  # Run once per secret
```

> **Security:** The `.env` file must have `chmod 600` permissions. Never commit it to git.
> Consider using AWS Secrets Manager or SSM Parameter Store for production secrets.
