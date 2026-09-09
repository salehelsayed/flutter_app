# App diagnostic collector and operator

This collector is separate from call diagnostics, message custody and media authority. It accepts authenticated endpoint reports through the existing encrypted InboxProtocol. The authenticated stream identity selects a private owner partition; the request cannot choose an owner. The collector does not download or inspect attachments. Client `source=relay` is rejected. `receivedAtMs` is relay-observed; feature stage, outcome, client time, OS report interval and build fields are endpoint-reported.

## Wire and bridge

Dart calls `GoBridgeClient.send` with `{"cmd":"app_diagnostics_v1","payload":{...}}`. Native dispatch invokes exported Go `AppDiagnosticsV1` with the payload JSON. Go sends `action=app_diagnostics_v1` to configured relays.

Payload operations:

- `configure`: `op`, `enabled` boolean, `consentEpoch` positive safe integer.
- `upload`: `op`, `consentEpoch`, `events` array, at most 64.
- `clear`: `op`, `consentEpoch`.
- `capabilities`: `op` only.

Response: `{"status":"OK","version":1,"data":{"supported":true,"enabled":true,"consentEpoch":123,"acceptedEventIds":[],"rejectedEventIds":[]}}`. ACK lists occur on uploads. A fixed `reason` may accompany partial ACKs. Accepted IDs are durable or already durably stored. Rejected IDs are permanently invalid or discarded by a full attempt bucket. Sink failure, stale/disabled consent and global/owner pressure leave IDs unacknowledged for retry. Repeated discarded IDs do not inflate distinct-loss counts; a saturated bounded discard ledger reports a lower bound. Metrics count upload outcomes including retries, not unique events.

The native bridge wraps `data` in its existing `ok` result. Exact unsupported action on an old relay returns `supported=false`. Configure/clear fan out to currently configured relays; any transport, protocol or collector error prevents success being reported for that fanout. A diagnostic request cannot invoke a call or message operation. Diagnostics remain asynchronous and must never gate app authority.

The canonical event schema is `tool/app_diagnostics/schema_v1.json`. Its generated copies must match byte-for-byte. Unknown fields, duplicate JSON keys, non-v4 UUIDs, arbitrary reason strings, arbitrary values, malformed hashes, unsafe integers and spoofed relay events are rejected. `fingerprint` is reserved for the app's sanitized stack-frame hash; it is not a content, attachment, identifier or credential hash.

## Consent, bounds and durability

The app uses its own app-wide collection preference; server storage remains off for an owner until authenticated configure. Call consent is independent. Higher epochs supersede older commands, equal conflicting enables are rejected, and repeated same-epoch clear is idempotent. Disable/clear persists a pending-erasure marker before deleting that owner's files. Restart completes interrupted erase before accepting new uploads. Upload and erasure ordering share one store mutex. No raw authority identity is stored: private owner digests and epoch state are excluded from operator output.

Server limits are independent of call quotas: 14 days from record creation, 128 MiB global, 8 MiB per authenticated owner, 512 routine records / 128 KiB per owner/run/attempt bucket, 32 bounded final slots, 192 KiB absolute record bound. Final records are reserved separately from routine events; if needed they evict routine records while recording loss. First final per feature/source/attempt is immutable; distinct OS crash/hang report IDs keep separate slots. Runtime records without attempts use run/trace grouping. Each record is written atomically with mode 0600 and fsynced; its directory is 0700. An hourly sweep and upload-time sweep expire records. Consent high-water metadata expires after 14 days without refresh. Old epoch protection therefore has this explicit retention horizon.

Dart owns the 7-day 4 MiB app queue and 1 MiB native queue, with 100 attempts and 256 events / 64 KiB per local attempt. Server aggregation allows the endpoint reports to coexist. Failed preflight records can upload without any message/call being created. `traceId` links a diagnostic story; `attemptId` separates retries. Optional `reportingRunId` links imported native reports to the copied Dart support code while preserving their original collector run/time/build. A MetricKit interval-end timestamp is marked by `reportTimeIsIntervalEnd`; it is not an exact crash time.

## Review and deployment

Run `bash -n docker-ws/app_diagnostics_install.sh` and the focused Go/Python gates before review. On the reviewed relay host, the installer prepares the protected data directory, atomically installs the operator/schema pair, and writes a dedicated systemd environment drop-in. It performs daemon-reload but **does not deploy the relay binary or restart services**. Root coordinates binary backup, candidate replacement and restart separately. No existing call diagnostic path, quota or files are modified.

Environment:

```
APP_DIAGNOSTICS_DIR=/var/lib/mknoon/app-diagnostics
APP_DIAGNOSTICS_MAX_BYTES=134217728
```

An absent directory setting disables this collector; invalid config or unreadable storage leaves `relay_app_diagnostics_storage_ready=0` and a fixed startup status. No environment values or disk errors are printed. Readiness is `relay_app_diagnostics_storage_ready`; request/ACK outcomes are `relay_app_diagnostics_requests_total` and `relay_app_diagnostics_events_total`. Response-write errors have their own `relay_app_diagnostics_reply_write_failures_total` counter.

## Operator commands

```
sudo python3 /usr/local/bin/app_diagnostics.py --hours 24 --limit 100
sudo python3 /usr/local/bin/app_diagnostics.py --support-code UUID --hours 336 --limit 2000
sudo python3 /usr/local/bin/app_diagnostics.py --trace UUID --hours 336 --limit 2000
sudo python3 /usr/local/bin/app_diagnostics.py --run UUID --hours 336 --limit 2000
sudo python3 /usr/local/bin/app_diagnostics.py --hours 24 --format html > app-diagnostics.html
```

`--support-code` matches trace, original run or reporting run. `--run` matches either run. Lookup shows only strict validated events and anonymous per-export endpoint aliases. `--trace` never proves the endpoints are authorized participants: a client can report a shared diagnostic UUID without acquiring message authority. Runtime snapshots without a start/final are event reports, not invented attempts.

Aggregates separate retries by owner/feature/attempt across reporting runs (owner/run/feature/trace fallback without attemptId), join restart recovery without inventing a cross-run duration, show missing start/final, and group by feature/build/platform. Known technical failure rates use success/ok plus failed/rejected/timeout as the denominator. Canceled, blocked and expired outcomes are excluded; interrupted/unknown outcomes remain explicit and are not counted as proven technical failure. Alerts are local output only: failure/missing-final rate at 20% with at least 5 samples; a new retained-baseline error signature after 3 reports; any observed telemetry loss or invalid record. New-error evidence is scoped to the retained baseline and counts reports, not unique incidents. No email, push, Slack or external notification is sent.

The HTML dashboard is a static sanitized artifact generated on demand. It does not start an unauthenticated web server. Private collector files and consent maps must never be copied into reports. Preserve output scope: missing, disabled, offline, expired, legacy and separately routed relay evidence cannot be reconstructed by the operator. Remote erasure applies to configured reachable relays, and rolling back to a relay without this protocol cannot acknowledge deletion; erase before rollback or allow the protected retention horizon to expire.

## Automatic private monitor

The reviewed installer now enables `mknoon-app-diagnostics-monitor.timer` and runs its oneshot service once. Every five minutes it writes mode-0600 `snapshot.json`, `dashboard.html`, `alerts.json` and transition state beneath `/var/lib/mknoon/app-diagnostics-monitor` (mode 0700). The service runs as the relay service user with a read-only view of collector storage and write access only to its monitor directory. There is no HTTP listener or outbound notification provider.

Snapshots contain aggregates rather than trace, event, run or owner identifiers. Each section and active-alert set is capped at 200 entries, every output file at 512 KiB, and no append-only monitor archive is created. Truncation is visible. JSON/HTML files are atomically replaced; state is committed last so a failed snapshot cannot suppress future alert publication. A process crash may repeat a local notice. Corrupt monitor state cannot inject free text into the journal. An unreadable collector replaces the prior dashboard with an explicit unavailable state instead of silently retaining a healthy snapshot.

The local journal records only fixed opened/cleared alert kinds and integer counts. An unchanged active alert is not announced again; a one-line snapshot health receipt appears each tick. Technical rates and new retained-baseline signatures use the operator thresholds. Missing-start, missing-final and interrupted-unknown coverage rates also require at least five observed attempts and a five-minute age grace; unknown is kept separate from proven technical failure. Projection truncation, collector unavailability and telemetry loss are explicit. Client-reported drop totals come from the latest retained Flutter health snapshot per owner and are shown separately from relay discard counts. Offline/disabled clients cannot report their current loss until they return.

```
sudo systemctl status mknoon-app-diagnostics-monitor.timer
sudo systemctl start mknoon-app-diagnostics-monitor.service
sudo journalctl -u mknoon-app-diagnostics-monitor.service --since '30 minutes ago' --no-pager
sudo cat /var/lib/mknoon/app-diagnostics-monitor/alerts.json
```

The timer may first report unavailable while the installer is preparing paths before the new relay binary starts; after deployment, run the monitor service again and verify readiness plus a readable snapshot. It does not restart the relay.

## Deploy bundle and rollback

`build/app-diagnostics/deploy-bundle/` contains the reviewed Linux `relay-server`, source/binary hash manifest, strict operator/schema, monitor, installer and this runbook. Copy that bundle to a protected staging directory on the relay. Root must first back up the currently running relay binary and verify its hash; binary replacement, relay restart and health validation remain root-coordinated deployment steps. Run the bundle installer with `sudo bash app_diagnostics_install.sh`; it prints an installer backup directory beneath `/var/backups/mknoon-app-diagnostics/<UTC>`. That backup contains only the prior app-owned wrapper, units, drop-in and operator-link target, not client records or authority maps.

For rollback, stop and disable the new timer:

```
sudo systemctl disable --now mknoon-app-diagnostics-monitor.timer
sudo systemctl stop mknoon-app-diagnostics-monitor.service
```

Restore the relay binary from root's verified pre-deployment binary backup and restart it using the same deployment procedure. Restore these app-owned files from the printed installer backup, or remove only these new files if no previous copy existed:

- `/usr/local/bin/app_diagnostics.py`
- `/etc/systemd/system/relay-server.service.d/app-diagnostics.conf`
- `/etc/systemd/system/mknoon-app-diagnostics-monitor.service`
- `/etc/systemd/system/mknoon-app-diagnostics-monitor.timer`

If `previous-operator-target.txt` is nonempty, atomically repoint `/usr/local/lib/mknoon-app-diagnostics/current` to that prior versioned directory. Then run `sudo systemctl daemon-reload`; restore the timer's enabled/active state according to the two `previous-timer-*.txt` files. Verify the restored relay hash and services. Existing call diagnostics files/configuration are outside this rollback.

Keep collector records protected; do not copy them into deployment evidence. Before rolling back to a binary without the app protocol, complete any pending client disable/erase requests while the collector is still available. If collection is disabled long term, remove the aggregate monitor snapshots after review so they are not kept indefinitely with the timer stopped. The protocol cannot promise erasure acknowledgment from a downgraded server that no longer implements it.
