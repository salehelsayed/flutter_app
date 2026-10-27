# Relay v1.11.3: Thought aggregate counter release preparation

Status: PREPARATION ONLY. No relay login, upload, deployment, tag creation, or
production configuration change was performed for this work. Kayan routes code
review; a separate explicit owner approval is required at release time.

## Candidate and behavior

Proposed component tag: `relay-v1.11.3` (not created or pushed).
`main.go` embeds `1.11.3` as a const: do not try to override it with `-X`.
The final commit, source tree, binary hashes and validation receipts belong in
the release evidence. Freeze that commit before building the release binary.

The original counter is the chain ending in `fbdfb0a44` (including
`495b9fdd4`); this branch imports it on the current `c72ef4904` app baseline.
The additional code is in `thought_metrics.go`, gated startup in `main.go`,
and `thought_metrics_test.go`. It is not yet a deployed or reviewed release.

`MKNOON_RELAY_THOUGHT_METRICS_ENABLED=true` explicitly enables the collector.
Unset, false or unrecognized values leave it OFF: no counter snapshot is read
or written and no Thought metric series is registered. Initialization failure
also leaves analytics unavailable while the relay continues serving messages.
A missing series means unavailable, never zero.

The enabled counter reads only already-routed outer `post_create` metadata after
accepted inbox storage. It retains dense p14 HLL registers for distinct posts
and senders in at most eight authored Monday-UTC ISO weeks. Fanout/retries use
the same logical ID; direct-only deliveries remain unseen. Weekly senders are
relay-observed sender IDs, not verified people or all app activity.

Returning posters = senders in week N intersect the union of **all earlier
retained** weeks, estimated by inclusion-exclusion, clamped to valid bounds.
It covers pilot weeks 3/4 if the earlier pilot weeks are within retention and
were observed while enabled. It is not an all-time returning-person measure.
Record the pilot's starting UTC ISO week; do not infer pilot week 3 from the
calendar week number. Historical weeks before enablement cannot be backfilled.
No new identifiers, per-input hashes, event logs or content are retained by the
counter; its existing snapshot schema is unchanged. Dense sketches are not a
differential privacy guarantee. Small-cohort errors are measured by the
synthetic `TestThoughtMetricsReturningSmallCohortAccuracy` cases, rather than
claiming that the HLL single-cardinality error is the intersection error.

Verified focused race results: 11 top-level cases and nine accuracy subcases,
zero failures/skips. Each pattern has 128 trials and two measured pilot weeks
(256 estimates per table row). Results below take the worst pattern for each
weekly sender count; all-returning uses a fixed cohort, while all-new/rotating
also stress larger prior unions. This is not a guarantee for arbitrary IDs or
weeks, and all-new cohorts can produce false positive returning estimates.

| Weekly senders | Worst pattern p95 absolute error | Observed maximum error |
| --- | --- | --- |
| 20 | 1 sender | 2 senders |
| 50 | 1 sender | 2 senders |
| 100 | 2 senders | 3 senders |

Raw JSON and every pattern's mean/p95/max are retained under
`.codex-test-logs/relay-thought-returners-20261027/`. Dense p14 is preserved;
no sparse per-input representation or exact production sender set is introduced.

The private file is `<resolved RELAY_DATA_DIR>/thoughts-metrics.json` (normally
`/data/thoughts-metrics.json`), mode 0600, atomic rename plus directory sync.
Minute/shutdown flushes persist bounded sketches; the last unflushed tail can
be lost on abrupt termination. `snapshot_healthy=1` means the last write
succeeded, not that every accepted update has reached disk. Restart tests cover
persisted counts and returning intersections. Never use `kill -9` for release.

## Approval and privacy prerequisites

1. Kayan's code review passes and the final affected/release checks have evidence.
   Focused counter results do not certify the other manifest-selected checks.
2. Mizan, via Hermes, updates the user-facing privacy text **before enabling or
   deploying this release** and Kayan records the approved copy. Suggested copy
   for that review:

   > Our relay can collect approximate weekly totals of Thoughts and their
   > senders, including senders seen in an earlier week within an eight-week
   > window. This counter uses routing metadata already needed for delivery;
   > it does not open encrypted Thought content. It retains bounded aggregate
   > sketches for up to eight weeks, with no additional stored sender IDs,
   > Thought IDs, recipients or content. Direct-only activity is not counted.

3. Obtain explicit owner release approval. First test the same candidate on
   Hetzner `2.29.62.121`, **after coordinating with Codex-UI**: its current
   UI-Update relay changes must be preserved. Compare both source baselines;
   reconcile needed changes before freezing/building, rather than overwriting
   a teammate's binary. A changed candidate requires affected validation again.
4. Verify the non-secret live baseline below at approved release time. Stop if
   it differs; obtain a fresh reviewed baseline and rollback artifact.

## AWS metadata supplied by Kayan, not freshly probed

- DNS **mknoun.xyz** (not mknoon.xyz), `51.21.194.144`, EC2 eu-north-1,
  x86_64 / Linux amd64. SSH user ubuntu with sudo.
- Unit `relay-server`; binary `/usr/local/bin/relay-server`;
  environment `/etc/mknoon/relay-server.env`; metrics `localhost:2112/metrics`.
- Expected previous version `1.11.2`, source `6bae23448`, installed
  2026-10-26 12:26 UTC; SHA-256
  `e0b6e8e4ba655ee97b4238278f467c7d5d6786324518d161517336526dba1484`.
- Older v1.11.1 backup:
  `/usr/local/bin/relay-server.pre-1.11.2-20261026T122550Z`.
  The rollback for this release must be a newly verified copy of live v1.11.2.
- Source of metadata: Kayan mailbox `m-6fb90386`, 2026-10-27 18:38 UTC;
  existing ignored `docker-ws/deploy_relay_v1.11.2_aws.sh` and `_result.txt`.
  Those scripts are operational context, not tracked release artifacts here.

## Local release build (safe to prepare; no publication)

From `go-relay-server` in the final clean candidate checkout:

```sh
CANDIDATE=$(git rev-parse HEAD)
test -z "$(git status --porcelain)"
mkdir -p ../.codex-test-logs/relay-thought-returners-20261027/build
env GOTOOLCHAIN=go1.27.1 CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
  go build -trimpath -ldflags "-X main.callDiagnosticBuild=$CANDIDATE" \
  -o ../.codex-test-logs/relay-thought-returners-20261027/build/relay-server.v1.11.3 .
shasum -a 256 ../.codex-test-logs/relay-thought-returners-20261027/build/relay-server.v1.11.3
go version -m ../.codex-test-logs/relay-thought-returners-20261027/build/relay-server.v1.11.3
go tool nm ../.codex-test-logs/relay-thought-returners-20261027/build/relay-server.v1.11.3 \
  | rg 'main.thoughtReturningDesc|main.\(\*thoughtMetrics\).Collect'
```

Retain the full hash, candidate commit/tree, Go version/build settings and symbol
probe in the evidence. The banner alone cannot identify the artifact. The
constant version is checked by a local host build's `version` command; execute
the Linux binary's `version` command only on the approved Linux staging host.

## Approved release procedure (DO NOT RUN during preparation)

Use the existing, already-authorized SSH/SFTP helpers by key **path** only; never
read or print a key, environment file, process environment or service credentials.
Always supply `RELAY_SSH_HOST=51.21.194.144` explicitly: helper defaults point
elsewhere. The ignored helpers are available in the primary checkout.

```sh
# Only AFTER approval and the coordinated Hetzner trial:
RELAY_SSH_HOST=51.21.194.144 python3 docker-ws/relay_sftp_put.py \
  /absolute/path/to/frozen/relay-server.v1.11.3 /tmp/relay-server.v1.11.3
# Run a separately reviewed remote script with:
RELAY_SSH_HOST=51.21.194.144 python3 docker-ws/relay_ssh.py < approved-release.sh
```

The reviewed remote script must use `set -euo pipefail` and perform these steps:

1. Check `uname -m` is x86_64, current executable SHA equals the expected v1.11.2
   baseline, unit is active, and `relay_backend_durable 1`. Record only allowlisted
   unit properties/PID/start time/restart count, not full unit/env dumps. Establish
   a real client baseline and owned custody test rows using the existing protocol
   probe. Preserve their logical IDs and assertions across restart.
2. Check uploaded full SHA matches the frozen local artifact; run its `version`
   command (`/tmp` may be non-executable: install a private staging copy with
   mode 0755 in `/usr/local/bin`, then invoke `version`). Do not start another
   relay process or generate a new relay identity.
3. Copy the current binary with `sudo -n cp -p` to
   `/usr/local/bin/relay-server.pre-1.11.3-<UTC-stamp>`; verify its full SHA matches
   the live baseline. Record this exact rollback path. Preserve existing env,
   keys, Redis, inbox, media, profiles, ports and all existing systemd drop-ins.
4. Add only a dedicated `/etc/systemd/system/relay-server.service.d/70-thought-metrics.conf`
   containing `[Service]` and
   `Environment=MKNOON_RELAY_THOUGHT_METRICS_ENABLED=true`, after recording whether
   that exact file already exists and retaining a private backup if so. Verify
   the existing `DIRECT_INBOX_ACK_CUSTODY_ADMISSION_ENABLED` remains true without
   printing other environment values. Resolve the persistent storage root and
   ensure the service account can write it; never fall back to an ephemeral path.
5. `sudo -n install -m0755 /tmp/relay-server.v1.11.3 /usr/local/bin/relay-server`;
   verify the installed hash; `sudo -n systemctl daemon-reload` then
   `sudo -n systemctl restart relay-server`. Do not restart Redis/nginx/coturn.
6. Wait up to 60 seconds for this PID's readiness: expected peer identity and
   `backend=redis durable=true` summary. Check `Starting relay-server v1.11.3`,
   on-disk and `/proc/<MainPID>/exe` SHA, active state, and `relay_backend_durable 1`.
   Check `NRestarts` stays stable at t+12, t+52 and t+92 seconds; a banner or
   active state alone is insufficient. Preserve failed-attempt evidence.
7. Run the real client dial and existing authenticated store/retrieve/ACK and
   owned-row retention probes. Collect local metrics below. After the periodic
   flush, confirm private snapshot persistence; prove clean restart continuity
   on Hetzner first. Do not inject content/tester IDs into metric labels or logs.
8. On success, update the primary checkout's existing
   `docker-ws/group-reaction-staging-manifest-315.json` fields
   `candidateRelayRevision` and `candidateRelaySha256` to the frozen candidate.
   Keep deployment evidence separate from source-only validation. Never change
   unrelated manifest fields or infer that a store build itself was redeployed.

## Rollback / disabling

If readiness, durability, identity, custody probes or restart stability fail,
retain diagnostics, restore the exact verified v1.11.2 backup with `install -m0755`,
verify its SHA, restore only the release-owned drop-in to its prior state, run
`daemon-reload`, restart only `relay-server`, and repeat durability/client checks.
Do not restore the older v1.11.1 backup by accident, delete the HLL snapshot or
reset Redis/inbox data. Record the failed attempt and rollback outcome.

To stop collection while retaining v1.11.3, set the dedicated flag explicitly to
`false`, daemon-reload and cleanly restart. Series become absent, not zero;
keep existing snapshots private. Persisted records expire to eight weeks on the
next enabled rotation, so disabling does not itself erase the inactive file.
The counter has no historical backfill for time disabled.

## Prometheus readout

Use the existing private scrape path / local SSH command; do not open port 2112.
The week label is calendar ISO week; substitute the recorded pilot weeks.

```promql
relay_backend_durable
relay_thoughts_snapshot_healthy
relay_thoughts_weekly_estimated{week="2026-W46"}
relay_thought_posters_weekly_estimated{week="2026-W46"}
relay_thought_returning_posters_weekly_estimated{week="2026-W46"}
absent(relay_thoughts_snapshot_healthy)
```

These are gauges, not counters: do not apply `rate`/`increase`, sum across weeks
to infer distinct people, or sum mirrored relays (senders/posts may overlap).
A restart resets ordinary Prometheus process counters, but the private HLL
snapshot is reloaded. Only the unflushed tail can be lost. A healthy empty
collector can legitimately report zero; absent series are unavailable. Returning
counts are approximate observed-sender intersections, with the tested cohort
error and the retention/coverage limits above, not engagement percentages.
