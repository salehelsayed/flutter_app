Privacy-Safe Business Metrics — Implementation Plan

  Overview

  Add aggregate-only business metrics to the relay server using HyperLogLog for unique user estimation. Zero individual tracking, no stored peer IDs, no behavioral profiles.

  Peer connects → peer ID hashed into HLL → original ID discarded
                                             (not recoverable)

  Memory cost: ~36KB total (3 HLL registers). Accuracy: ~2% error margin.

  ---
  New Metrics

  ┌───────────────────────────────┬─────────────────────────┬─────────────────────────────────────────────┐
  │            Metric             │          Type           │              What It Tells You              │
  ├───────────────────────────────┼─────────────────────────┼─────────────────────────────────────────────┤
  │ relay_estimated_dau           │ Gauge                   │ Estimated daily active unique peers (HLL)   │
  ├───────────────────────────────┼─────────────────────────┼─────────────────────────────────────────────┤
  │ relay_estimated_wau           │ Gauge                   │ Estimated weekly active unique peers (HLL)  │
  ├───────────────────────────────┼─────────────────────────┼─────────────────────────────────────────────┤
  │ relay_estimated_mau           │ Gauge                   │ Estimated monthly active unique peers (HLL) │
  ├───────────────────────────────┼─────────────────────────┼─────────────────────────────────────────────┤
  │ relay_new_signups_total       │ Counter                 │ First-time profile uploads (new users)      │
  ├───────────────────────────────┼─────────────────────────┼─────────────────────────────────────────────┤
  │ relay_push_tokens_by_platform │ Gauge (label: platform) │ iOS vs Android split                        │
  ├───────────────────────────────┼─────────────────────────┼─────────────────────────────────────────────┤
  │ relay_messages_daily          │ Gauge                   │ Messages stored today (resets midnight UTC) │
  ├───────────────────────────────┼─────────────────────────┼─────────────────────────────────────────────┤
  │ relay_media_uploads_daily     │ Gauge                   │ Media uploads today (resets midnight UTC)   │
  └───────────────────────────────┴─────────────────────────┴─────────────────────────────────────────────┘

  ---
  File Changes

  ┌─────────────────────────────────┬────────┬────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │              File               │ Change │                                            Description                                             │
  ├─────────────────────────────────┼────────┼────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ go.mod / go.sum                 │ modify │ Add github.com/axiomhq/hyperloglog dependency                                                      │
  ├─────────────────────────────────┼────────┼────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ business_metrics.go             │ new    │ HLL registers (day/week/month), daily counters, midnight reset logic                               │
  ├─────────────────────────────────┼────────┼────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ metrics.go                      │ modify │ Add 7 new Prometheus metric declarations                                                           │
  ├─────────────────────────────────┼────────┼────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ inbox_store.go                  │ modify │ Add PlatformCounts() to PushTokenBackend interface                                                 │
  ├─────────────────────────────────┼────────┼────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ push_token_store.go             │ modify │ Implement PlatformCounts() for memory backend                                                      │
  ├─────────────────────────────────┼────────┼────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ backend_redis.go                │ modify │ Implement PlatformCounts() for Redis backend                                                       │
  ├─────────────────────────────────┼────────┼────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ profile.go                      │ modify │ os.Stat check before write — detect new vs update                                                  │
  ├─────────────────────────────────┼────────┼────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ inbox.go                        │ modify │ Add PushService.PlatformCounts() wrapper; call biz.RecordMessageStored()                           │
  ├─────────────────────────────────┼────────┼────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ media.go                        │ modify │ Call biz.RecordMediaUploaded() after upload                                                        │
  ├─────────────────────────────────┼────────┼────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ main.go                         │ modify │ Create biz singleton, wire HLL into connection handler, update stats ticker, bump version to 1.2.0 │
  ├─────────────────────────────────┼────────┼────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ grafana-business-dashboard.json │ new    │ Grafana dashboard with 10 panels                                                                   │
  └─────────────────────────────────┴────────┴────────────────────────────────────────────────────────────────────────────────────────────────────┘

  ---
  Step-by-Step

  Step 1: Add HyperLogLog dependency

  cd go-relay-server && go get github.com/axiomhq/hyperloglog

  Step 2: Create business_metrics.go (new file)

  Contains the HLL state and daily counter logic:

  - hllRegister — wraps hyperloglog.Sketch with a mutex, provides Insert(), Estimate(), Reset()
  - businessMetrics — holds 3 HLL registers (daily/weekly/monthly), 2 atomic daily counters, midnight reset logic
  - RecordPeerSeen(peerID string) — feeds peer ID into all 3 HLLs (hash only, original discarded)
  - RecordMessageStored() / RecordMediaUploaded() — increment daily atomics
  - CheckAndResetPeriods() — compares current YearDay()/ISOWeek()/Month() vs stored boundary, resets on crossing
  - Package-level var biz *businessMetrics so inbox/media can call it with nil-guard

  Step 3: Add Prometheus declarations to metrics.go

  Append 7 new vars after existing declarations:
  - estimatedDAU, estimatedWAU, estimatedMAU — gauges
  - newSignupsCounter — counter
  - pushTokensByPlatform — gauge vec with platform label
  - messagesDailyGauge, mediaUploadsDailyGauge — gauges

  Step 4: Add PlatformCounts() to push token backends

  - Add to PushTokenBackend interface in inbox_store.go
  - Implement in memoryPushTokenStore — iterate s.tokens, count by entry.Platform
  - Implement in redisPushTokenBackend — scan keys, unmarshal entries, count by platform
  - Add PushService.PlatformCounts() wrapper method in inbox.go

  Step 5: Detect new signups in profile.go

  In handleProfileUpload, before writing the file:
  isNewProfile := false
  if _, err := os.Stat(path); os.IsNotExist(err) {
      isNewProfile = true
  }
  After successful upload: if isNewProfile { newSignupsCounter.Inc() }

  Idempotent after restarts — existing profiles on disk won't re-trigger.

  Step 6: Wire daily counters in inbox.go and media.go

  - In InboxStore.Store(), after inboxStoredCounter.Inc(): if biz != nil { biz.RecordMessageStored() }
  - In handleMediaUpload(), after mediaUploadedCounter.Inc(): if biz != nil { biz.RecordMediaUploaded() }

  Step 7: Wire HLL and stats ticker in main.go

  - Create singleton after subsystem init: biz = newBusinessMetrics()
  - In connection event handler, network.Connected branch: biz.RecordPeerSeen(e.Peer.String())
  - In stats ticker (every 60s):
    a. Call biz.CheckAndResetPeriods() (resets at midnight UTC)
    b. Set gauges: estimatedDAU.Set(float64(biz.dailyHLL.Estimate())) (same for WAU/MAU)
    c. Set daily gauges: messagesDailyGauge.Set(float64(biz.messagesDailyCount.Load()))
    d. Update platform counts: iterate push.PlatformCounts(), set gauge vec
  - Bump version from "1.1.0" to "1.2.0"

  Step 8: Create Grafana Business Overview dashboard

  New file: grafana-business-dashboard.json

  ┌──────────────────────────┬────────────────────────────────────────────┬───────────────────┐
  │          Panel           │                   PromQL                   │       Type        │
  ├──────────────────────────┼────────────────────────────────────────────┼───────────────────┤
  │ Estimated DAU            │ relay_estimated_dau                        │ Stat (big number) │
  ├──────────────────────────┼────────────────────────────────────────────┼───────────────────┤
  │ Estimated WAU            │ relay_estimated_wau                        │ Stat              │
  ├──────────────────────────┼────────────────────────────────────────────┼───────────────────┤
  │ Estimated MAU            │ relay_estimated_mau                        │ Stat              │
  ├──────────────────────────┼────────────────────────────────────────────┼───────────────────┤
  │ Total Users              │ relay_profile_count                        │ Stat              │
  ├──────────────────────────┼────────────────────────────────────────────┼───────────────────┤
  │ Messages per Active User │ relay_messages_daily / relay_estimated_dau │ Stat              │
  ├──────────────────────────┼────────────────────────────────────────────┼───────────────────┤
  │ Platform Split           │ relay_push_tokens_by_platform              │ Bar gauge         │
  ├──────────────────────────┼────────────────────────────────────────────┼───────────────────┤
  │ New Signups              │ increase(relay_new_signups_total[1d])      │ Time series       │
  ├──────────────────────────┼────────────────────────────────────────────┼───────────────────┤
  │ Daily Message Volume     │ relay_messages_daily                       │ Time series       │
  ├──────────────────────────┼────────────────────────────────────────────┼───────────────────┤
  │ Daily Media Uploads      │ relay_media_uploads_daily                  │ Time series       │
  ├──────────────────────────┼────────────────────────────────────────────┼───────────────────┤
  │ Activity Trend           │ rate(relay_connections_total[1d])          │ Time series       │
  └──────────────────────────┴────────────────────────────────────────────┴───────────────────┘

  Step 9: Build and deploy

  # Build
  cd go-relay-server
  go mod tidy
  GOOS=linux GOARCH=amd64 go build -o relay-server .

  # Deploy binary
  scp -i se.pem relay-server ubuntu@13.60.15.36:/tmp/relay-server
  ssh -i se.pem ubuntu@13.60.15.36 'sudo systemctl stop relay-server && sudo mv /tmp/relay-server /usr/local/bin/ && sudo systemctl start relay-server'

  # Deploy dashboard (transform + upload)
  # Same sed/python3 transform as the other dashboards

  Step 10: Verify

  # Check new metrics exist
  curl -s localhost:2112/metrics | grep relay_estimated
  curl -s localhost:2112/metrics | grep relay_new_signups
  curl -s localhost:2112/metrics | grep relay_push_tokens_by_platform

  # Check Grafana dashboard loaded
  curl -s -u admin:admin localhost:3000/api/search | grep business

  ---
  Privacy Audit

  ┌───────────────────────────────┬─────────────────────────────────────────┐
  │             Check             │                 Status                  │
  ├───────────────────────────────┼─────────────────────────────────────────┤
  │ Peer IDs in Prometheus labels │ None                                    │
  ├───────────────────────────────┼─────────────────────────────────────────┤
  │ Peer IDs stored in memory     │ Only hashed in HLL (not recoverable)    │
  ├───────────────────────────────┼─────────────────────────────────────────┤
  │ Per-user counters             │ None — all aggregate                    │
  ├───────────────────────────────┼─────────────────────────────────────────┤
  │ Daily resets                  │ Midnight UTC via CheckAndResetPeriods() │
  ├───────────────────────────────┼─────────────────────────────────────────┤
  │ HLL memory                    │ ~36KB total (3 registers)               │
  ├───────────────────────────────┼─────────────────────────────────────────┤
  │ Labels cardinality            │ platform in {ios, android} — fixed set  │
  └───────────────────────────────┴─────────────────────────────────────────┘
