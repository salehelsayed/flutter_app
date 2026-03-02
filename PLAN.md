# Relay Server Prometheus Metrics — Implementation Plan

## Overview

Add Prometheus instrumentation to `go-relay-server/` so you can observe app-level and host-level metrics from your Mac via SSH tunnel + Prometheus UI.

---

## Architecture

```
┌─── EC2 ─────────────────────────────────────────┐
│                                                  │
│  relay-server (:4000/4002/4005)  ← libp2p        │
│  relay-server (:2112 /metrics)   ← app metrics   │
│                                                  │
│  node_exporter (:9100 /metrics)  ← host metrics  │
│  prometheus    (:9090)           ← scrapes both   │
│                                                  │
└──────────────────────────────────────────────────┘
        │
        │  ssh -L 9090:localhost:9090 ec2-user@mknoun.xyz
        ▼
   Your Mac → browser → localhost:9090 (Prometheus UI)
                       → or Grafana (optional, later)
```

- **:2112** — app metrics (relay-server exposes `/metrics` here)
- **:9100** — reserved for `node_exporter` (host CPU/RAM/disk/network)
- **:9090** — Prometheus server scrapes both endpoints

---

## Step 1: Add Prometheus dependency

**File:** `go-relay-server/go.mod`

```bash
cd go-relay-server && go get github.com/prometheus/client_golang/prometheus github.com/prometheus/client_golang/prometheus/promhttp
```

This adds `prometheus/client_golang`. The library automatically registers built-in collectors:
- `go_*` — goroutines, GC, heap, threads (replaces custom `runtime.ReadMemStats`)
- `process_*` — process CPU, RSS, open FDs, start time

No need to manually register gauges for goroutines or heap — they come free.

---

## Step 2: Create `metrics.go` — central metric definitions

**New file:** `go-relay-server/metrics.go`

All metric variables defined in one place. Registered via `init()`.

### Gauges (current state — names never end in `_total`)

| Variable | Name | Help | Labels |
|---|---|---|---|
| `connectionsActive` | `relay_connections_active` | Current connected peers | — |
| `inboxMessagesPending` | `relay_inbox_messages_pending` | Messages waiting in inbox | — |
| `inboxPeersPending` | `relay_inbox_peers_pending` | Peers with pending messages | — |
| `inboxPushTokens` | `relay_inbox_push_tokens` | Registered FCM tokens | — |
| `mediaBlobsPending` | `relay_media_blobs_pending` | Blob files on disk | — |
| `mediaDiskBytes` | `relay_media_disk_bytes` | Media folder size in bytes | — |
| `profileCount` | `relay_profile_count` | Profile files on disk | — |
| `profileDiskBytes` | `relay_profile_disk_bytes` | Profile folder size in bytes | — |
| `rendezvousNamespaces` | `relay_rendezvous_namespaces` | Active namespaces | — |
| `rendezvousPeers` | `relay_rendezvous_peers` | Registered rendezvous peers | — |
| `activeStreams` | `relay_active_streams` | Concurrent protocol handlers | `proto` |

**Labels for `activeStreams`:** `proto` in {`inbox`, `media`, `rendezvous`} — low cardinality.

### Counters (lifetime totals — `_total` suffix per convention)

| Variable | Name | Help | Labels |
|---|---|---|---|
| `inboxStored` | `relay_inbox_stored_total` | Messages accepted into inbox | — |
| `inboxRetrieved` | `relay_inbox_retrieved_total` | Messages sent to retrieving peer | — |
| `inboxExpired` | `relay_inbox_expired_total` | Messages pruned by TTL | — |
| `inboxCapped` | `relay_inbox_capped_total` | Messages dropped by 100-cap overflow | — |
| `mediaUploaded` | `relay_media_uploaded_total` | Blobs uploaded | — |
| `mediaUploadedBytes` | `relay_media_uploaded_bytes_total` | Bytes uploaded | — |
| `mediaDownloaded` | `relay_media_downloaded_total` | Blobs downloaded | — |
| `mediaDownloadedBytes` | `relay_media_downloaded_bytes_total` | Bytes downloaded | — |
| `mediaDeleted` | `relay_media_deleted_total` | Blobs deleted | `reason` |
| `mediaDeletedBytes` | `relay_media_deleted_bytes_total` | Bytes deleted | `reason` |
| `mediaExpired` | `relay_media_expired_total` | Blobs removed by TTL cleanup | — |
| `profileUploaded` | `relay_profile_uploaded_total` | Profiles uploaded | — |
| `profileDownloaded` | `relay_profile_downloaded_total` | Profiles downloaded | — |
| `profileDeleted` | `relay_profile_deleted_total` | Profiles explicitly deleted | — |
| `pushSent` | `relay_push_sent_total` | Push notifications attempted | `result` |
| `rendezvousRegistered` | `relay_rendezvous_registered_total` | Registrations | — |
| `rendezvousDiscovered` | `relay_rendezvous_discovered_total` | Discover requests served | — |
| `rendezvousExpired` | `relay_rendezvous_expired_total` | Registrations expired | — |
| `connectionsTotal` | `relay_connections_total` | Lifetime peer connections | — |
| `disconnectionsTotal` | `relay_disconnections_total` | Lifetime peer disconnections | — |
| `streamErrors` | `relay_stream_errors_total` | Stream-level errors | `proto`, `kind` |

**Label values (all low-cardinality, fixed sets):**
- `reason` in {`auto_download`, `explicit`, `ttl_cleanup`, `peer_cap`}
- `result` in {`success`, `failed`, `invalid_token`}
- `kind` in {`read`, `decode`, `write`}
- `proto` in {`inbox`, `media`, `rendezvous`}

No peer IDs, message IDs, or blob IDs in labels — ever.

### Histogram (latency)

| Variable | Name | Help | Labels |
|---|---|---|---|
| `streamDuration` | `relay_stream_duration_seconds` | End-to-end stream handler time | `proto`, `result` |

**Labels:**
- `proto` in {`inbox`, `media`, `rendezvous`}
- `result` in {`ok`, `error`}

**Buckets:** `{0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30}`

Chosen based on expected SLOs:
- Rendezvous/inbox ops: <100ms typical
- Media uploads/downloads: 1-30s depending on blob size

### What NOT to register as custom metrics

Do NOT create custom gauges for:
- Goroutines — use built-in `go_goroutines`
- Heap memory — use built-in `go_memstats_heap_alloc_bytes`
- Process CPU — use built-in `process_cpu_seconds_total`
- Process RSS — use built-in `process_resident_memory_bytes`
- Open FDs — use built-in `process_open_fds`

These are automatically registered by `prometheus/client_golang`.

---

## Step 3: Start HTTP metrics server in `main.go`

Add to `main()`, after libp2p host creation but before the select loop:

```go
go func() {
    mux := http.NewServeMux()
    mux.Handle("/metrics", promhttp.Handler())
    log.Println("[METRICS] Serving Prometheus metrics on :2112/metrics")
    if err := http.ListenAndServe(":2112", mux); err != nil {
        log.Printf("[METRICS] HTTP server error: %v", err)
    }
}()
```

Port **2112** — leaves :9100 free for `node_exporter`.

---

## Step 4: Instrument `main.go`

### 4a. Connection tracking (lines ~119-123)

Replace `totalConnected` atomic with Prometheus gauge + counters:

```go
case network.Connected:
    connectionsActive.Inc()
    connectionsTotal.Inc()
    logPeerConnected(...)

case network.NotConnected:
    connectionsActive.Dec()
    disconnectionsTotal.Inc()
```

### 4b. Stats ticker (lines ~177-201)

Keep the 60-second ticker. Change it to update Prometheus gauges using the existing `Stats()` methods:

```go
func updatePrometheusGauges(h host.Host, inbox *InboxStore, rz *RendezvousStore, media *MediaStore, profile *ProfileStore) {
    rzNs, rzPeers := rz.Stats()
    rendezvousNamespaces.Set(float64(rzNs))
    rendezvousPeers.Set(float64(rzPeers))

    iPeers, iMsgs := inbox.Stats()
    inboxPeersPending.Set(float64(iPeers))
    inboxMessagesPending.Set(float64(iMsgs))
    inboxPushTokens.Set(float64(inbox.push.TokenCount()))

    mBlobs, mDiskMB := media.Stats()
    mediaBlobsPending.Set(float64(mBlobs))
    mediaDiskBytes.Set(float64(mDiskMB * 1024 * 1024))

    pCount, pDiskMB := profile.Stats()
    profileCount.Set(float64(pCount))
    profileDiskBytes.Set(float64(pDiskMB * 1024 * 1024))
}
```

Keep the existing `log.Printf("[STATS] ...")` line — useful for `journalctl`. Remove `heap_mb` and `goroutines` from the log if desired (they're in built-in metrics now), or keep for human convenience.

---

## Step 5: Instrument `inbox.go`

### 5a. Store() method (~line 200)

After successful store:
```go
inboxStored.Inc()
```

### 5b. pruneExpired() (~line 253)

Track how many messages were pruned by TTL:
```go
pruned := len(before) - len(after)
if pruned > 0 {
    inboxExpired.Add(float64(pruned))
}
```

### 5c. Store() cap overflow (~line 196)

When messages are dropped by the 100-message cap:
```go
overflow := len(messages) - maxMessagesPerPeer
if overflow > 0 {
    inboxCapped.Add(float64(overflow))
}
```

### 5d. Retrieve() method (~line 229)

After deletion from memory:
```go
inboxRetrieved.Add(float64(len(retrieved)))
```

### 5e. HandleInboxStream (~lines 319-398)

Replace `activeInboxStreams` atomic with Prometheus gauge:
```go
activeStreams.WithLabelValues("inbox").Inc()
defer func() {
    result := "ok"
    if handlerErr { result = "error" }
    streamDuration.WithLabelValues("inbox", result).Observe(time.Since(start).Seconds())
    activeStreams.WithLabelValues("inbox").Dec()
}()
```

On errors:
```go
streamErrors.WithLabelValues("inbox", "read").Inc()    // read error ~line 333
streamErrors.WithLabelValues("inbox", "decode").Inc()   // JSON decode ~line 339
streamErrors.WithLabelValues("inbox", "write").Inc()    // write error ~line 407
```

### 5f. SendNotification (~lines 85-133)

```go
pushSent.WithLabelValues("success").Inc()        // ~line 132
pushSent.WithLabelValues("failed").Inc()         // ~line 124
pushSent.WithLabelValues("invalid_token").Inc()  // ~line 128
```

---

## Step 6: Instrument `media.go`

### 6a. handleMediaUpload (~lines 282-336)

After successful upload:
```go
mediaUploaded.Inc()
mediaUploadedBytes.Add(float64(written))
```

### 6b. handleMediaDownload (~lines 338-382)

After successful download:
```go
mediaDownloaded.Inc()
mediaDownloadedBytes.Add(float64(meta.Size))
```

After auto-delete on download (~line 381):
```go
mediaDeleted.WithLabelValues("auto_download").Inc()
mediaDeletedBytes.WithLabelValues("auto_download").Add(float64(meta.Size))
```

### 6c. handleMediaDelete (~lines 384-404)

```go
mediaDeleted.WithLabelValues("explicit").Inc()
mediaDeletedBytes.WithLabelValues("explicit").Add(float64(meta.Size))
```

### 6d. cleanupExpired (~lines 86-104)

For each expired blob removed:
```go
mediaExpired.Inc()
mediaDeleted.WithLabelValues("ttl_cleanup").Inc()
mediaDeletedBytes.WithLabelValues("ttl_cleanup").Add(float64(meta.Size))
```

### 6e. store() — peer cap pruning (~lines 133-148)

When blobs are pruned because a peer exceeds the 50-blob cap:
```go
mediaDeleted.WithLabelValues("peer_cap").Inc()
mediaDeletedBytes.WithLabelValues("peer_cap").Add(float64(meta.Size))
```

### 6f. HandleMediaStream (~lines 233-280)

Same pattern as inbox:
```go
activeStreams.WithLabelValues("media").Inc()
defer func() {
    streamDuration.WithLabelValues("media", result).Observe(...)
    activeStreams.WithLabelValues("media").Dec()
}()
```

Error counters: `streamErrors.WithLabelValues("media", "read"|"decode"|"write").Inc()`

---

## Step 7: Instrument `profile.go`

### 7a. handleProfileUpload (~line 141)
```go
profileUploaded.Inc()
```

### 7b. handleProfileDownload (~line 178)
```go
profileDownloaded.Inc()
```

### 7c. handleProfileDelete (~line 184)
```go
profileDeleted.Inc()
```

Profile streams go through `HandleMediaStream`, so `activeStreams` and `streamDuration` for `proto="media"` already cover them. No separate proto label needed.

---

## Step 8: Instrument `rendezvous.go`

### 8a. HandleRendezvousStream (~lines 148-195)

```go
activeStreams.WithLabelValues("rendezvous").Inc()
defer func() {
    streamDuration.WithLabelValues("rendezvous", result).Observe(...)
    activeStreams.WithLabelValues("rendezvous").Dec()
}()
```

Error counters: `streamErrors.WithLabelValues("rendezvous", "read"|"decode"|"write").Inc()`

### 8b. handleRegister (~line 219)
```go
rendezvousRegistered.Inc()
```

### 8c. handleDiscover (~line 279)
```go
rendezvousDiscovered.Inc()
```

### 8d. cleanupExpired (~line 77)

For each expired registration removed:
```go
rendezvousExpired.Inc()
```

---

## Step 9: EC2 deployment — node_exporter + Prometheus

### 9a. Install node_exporter on EC2

```bash
wget https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz
tar xzf node_exporter-1.8.2.linux-amd64.tar.gz
sudo cp node_exporter-1.8.2.linux-amd64/node_exporter /usr/local/bin/
```

Systemd unit `/etc/systemd/system/node_exporter.service`:
```ini
[Unit]
Description=Node Exporter
After=network.target

[Service]
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

This gives full host metrics on **:9100**: CPU, memory, disk I/O, filesystem usage, network bytes/packets, load average.

### 9b. Install Prometheus on EC2

```bash
wget https://github.com/prometheus/prometheus/releases/download/v2.54.1/prometheus-2.54.1.linux-amd64.tar.gz
tar xzf prometheus-2.54.1.linux-amd64.tar.gz
sudo cp prometheus-2.54.1.linux-amd64/prometheus /usr/local/bin/
sudo mkdir -p /etc/prometheus /var/lib/prometheus
```

Config `/etc/prometheus/prometheus.yml`:
```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: "relay-server"
    static_configs:
      - targets: ["localhost:2112"]

  - job_name: "node"
    static_configs:
      - targets: ["localhost:9100"]
```

Systemd unit `/etc/systemd/system/prometheus.service`:
```ini
[Unit]
Description=Prometheus
After=network.target

[Service]
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --storage.tsdb.retention.time=30d
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

### 9c. Rebuild and deploy relay-server

```bash
cd go-relay-server && make build
scp relay-server ec2-user@mknoun.xyz:/usr/local/bin/
ssh ec2-user@mknoun.xyz 'sudo systemctl restart relay-server'
```

---

## Step 10: View from your Mac

```bash
ssh -L 9090:localhost:9090 ec2-user@mknoun.xyz
```

Open `http://localhost:9090` in browser. Example queries:

| What | PromQL |
|---|---|
| Active connections | `relay_connections_active` |
| Messages stored/min | `rate(relay_inbox_stored_total[5m]) * 60` |
| Messages deleted vs retrieved | `rate(relay_inbox_retrieved_total[5m])` vs `rate(relay_inbox_expired_total[5m])` |
| Media disk usage MB | `relay_media_disk_bytes / 1024 / 1024` |
| Bytes deleted by reason | `sum by (reason)(rate(relay_media_deleted_bytes_total[5m]))` |
| Blobs deleted by reason | `sum by (reason)(rate(relay_media_deleted_total[5m]))` |
| P95 stream latency | `histogram_quantile(0.95, sum by (le, proto)(rate(relay_stream_duration_seconds_bucket[5m])))` |
| Stream errors by type | `sum by (proto, kind)(rate(relay_stream_errors_total[5m]))` |
| Push success rate | `rate(relay_push_sent_total{result="success"}[5m]) / rate(relay_push_sent_total[5m])` |
| Host CPU usage | `100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)` |
| Host memory used | `node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes` |
| Host disk free | `node_filesystem_avail_bytes{mountpoint="/"}` |
| Network rx bytes/s | `rate(node_network_receive_bytes_total{device="eth0"}[5m])` |
| Go heap | `go_memstats_heap_alloc_bytes` |
| Goroutines | `go_goroutines` |

---

## File Change Summary

| File | Change type | Description |
|---|---|---|
| `go.mod` / `go.sum` | modify | Add `prometheus/client_golang` dependency |
| `metrics.go` | **new** | All metric definitions (gauges, counters, histogram) + `init()` registration |
| `main.go` | modify | Start HTTP :2112, call `updatePrometheusGauges` in ticker, instrument connections |
| `inbox.go` | modify | Increment counters on store/retrieve/expire/cap/push, stream metrics |
| `media.go` | modify | Increment counters on upload/download/delete/expire/cap, stream metrics |
| `profile.go` | modify | Increment counters on upload/download/delete |
| `rendezvous.go` | modify | Increment counters on register/discover/expire, stream metrics |

---

## Design Rules

1. **Gauge names never end in `_total`** — that suffix is reserved for counters
2. **Downloaded and deleted are separate counters** — a blob is downloaded, then separately deleted (with a reason label)
3. **Retrieved and expired are separate counters** — retrieve = peer-initiated, expired = TTL-pruned
4. **All labels are low-cardinality** — only fixed enum sets (`proto`, `reason`, `result`, `kind`)
5. **No peer IDs, message IDs, or blob IDs in labels** — unbounded cardinality kills Prometheus
6. **Built-in collectors for Go runtime** — `go_*` and `process_*` handle goroutines, heap, CPU, FDs
7. **App metrics on :2112, host metrics on :9100** — separate concerns, standard ports
8. **Histogram buckets chosen from SLOs** — not arbitrary; 10ms-30s covers both fast ops and media transfers
