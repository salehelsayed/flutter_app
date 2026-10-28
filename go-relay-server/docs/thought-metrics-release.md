# Relay v1.11.3: Thought aggregate counter release preparation

Status: PREPARATION ONLY. No relay login, upload, deployment, tag creation, or
production configuration change was performed for this work. Kayan routes code
review; a separate explicit owner approval is required at release time.

**Build 129 only.** Kayan's owner decision `m-1d69c2f5` (2026-10-27) adds a
separate in-app “Thoughts metrics” withdrawal switch. Do not activate the counter
for build 128. The relay opt-out admission change is implemented below; the
hardening commit alone does not include it. Kayan's partial resume in the reply
to `m-9a79d135` permits implementation and guarded focused Go tests. Full relay
validation and frozen builds remain on hold until the AWS device lanes finish
and Kayan explicitly releases that hold; the earlier artifact is superseded.

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
Unset, false or unrecognized values leave it OFF: no collector or Thought
series is registered. Every OFF startup deletes only the counter snapshot,
then syncs its parent directory; absent files are a successful no-op. Deletion
failures are reported and must be repaired before claiming the retention rule
was met. Initialization failure leaves analytics unavailable while the relay
continues serving messages. A missing series means unavailable, never zero.

When ON, `MKNOON_RELAY_THOUGHT_METRICS_KEY` is required: a nonblank, independently
random secret of at least 32 bytes, securely provided by the release operator.
No real key is created/read/provisioned by this preparation. Never put the key
in chat, logs, command arguments, a git file or a public unit dump. Use the
existing protected service environment file (0600), with approved provisioning.
Sender IDs are domain-separated HMAC-SHA256 inputs before HLL insertion; the
key is kept in process memory, never in the snapshot. A snapshot-only holder
without the strong key cannot reproduce the sender hashing. This is not a
claim against someone who also obtains the key or controls the relay.

Snapshot version 2 stores only a domain-separated key verifier plus the bounded
weekly sketches. A legacy unkeyed snapshot or different key verifier is wiped
before starting a fresh empty epoch. Key rotation therefore resets all history;
never combine different-key weeks or rotate keys weekly while claiming pilot
week 3/4 returning counts. Keep the key stable across the retained pilot window.
Thought IDs still use the existing unkeyed HLL input; do not claim every possible
known-item membership inference is prevented.

The enabled counter reads only already-routed outer `post_create` metadata after
accepted inbox storage, excluding opted-out or malformed-flag envelopes before
hashing. It retains dense p14 HLL registers for eligible distinct posts
and senders in at most eight authored Monday-UTC ISO weeks. Fanout/retries use
the same logical ID; direct-only deliveries remain unseen. Weekly senders are
relay-observed sender IDs, not verified people or all app activity.

Returning posters = senders in week N intersect the union of **all earlier
retained** weeks, estimated by inclusion-exclusion, clamped to valid bounds.
It covers pilot weeks 3/4 if the earlier pilot weeks are within retention and
were observed while enabled. It is not an all-time returning-person measure.
Record the pilot's starting UTC ISO week; do not infer pilot week 3 from the
calendar week number. Historical weeks before enablement cannot be backfilled.
No sender identifiers, per-input hashes, event logs or content are retained by
the counter; snapshot version 2 adds only a non-secret key verifier. Dense sketches are not a
differential privacy guarantee. Small-cohort errors are measured by the
synthetic `TestThoughtMetricsReturningSmallCohortAccuracy` cases, rather than
claiming that the HLL single-cardinality error is the intersection error.

Verified hardened 129 race results: 18 top-level cases and 18 subcases (nine
admission and nine accuracy), zero failures/skips. Each accuracy pattern has 128 trials and two measured pilot weeks
(256 estimates per table row). Results below take the worst pattern for each
weekly sender count; all-returning uses a fixed cohort, while all-new/rotating
also stress larger prior unions. This is not a guarantee for arbitrary IDs or
weeks, and all-new cohorts can produce false positive returning estimates.

| Weekly senders | Worst pattern p95 absolute error | Observed maximum error |
| --- | --- | --- |
| 20 | 0 senders | 2 senders |
| 50 | 1 sender | 3 senders |
| 100 | 1 sender | 4 senders |

Raw JSON and every keyed pattern's mean/p95/max are retained under
`.codex-test-logs/relay-thought-hardening-20261027/` and the opt-out receipts under
`.codex-test-logs/relay-thought-optout-20261028/`. The latter preserves the first
run's incorrect retry-delivery test assertion and its correction: InboxStore
retains both accepted retry copies while the HLL counts one logical eligible
Thought. The fresh corrected run passes under the unchanged resource guard.
The earlier unkeyed
run does not certify this hardened candidate. Dense p14 is preserved;
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

   Engineering description only: the counter stores bounded weekly sketches
   and a key verifier, not lists of sender/Thought/recipient IDs or content.
   Sender hashing uses a separate secret key. Global relay-counter OFF startup deletes the aggregate
   snapshot; operations complete and verify that restart within seven days of
   switch-off. This description is superseded as user-facing copy by Mizan's
   version, per Kayan `m-2421a59d`; do not publish this draft instead.

The later owner decision in `m-1d69c2f5` supersedes the earlier without-consent
wording from `m-895504c2`: the basis is existing beta consent, with a separate
“Thoughts metrics” withdrawal switch in 129. Obtain the owner's lawyer check
before including any users outside that beta group. Mizan owns the privacy
copy. Operations must restart with the counter OFF **within seven days of
switch-off** and verify the snapshot is absent; repair deletion failures within
that deadline. Prometheus history and backup copies need their own retention
rules; deleting this file alone does not erase those copies.

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
  environment `/etc/mknoon/relay-server.env`; metrics reachable locally on port 2112.
  The old source binds all interfaces; AWS access controls were not probed.
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
mkdir -p ../.codex-test-logs/relay-thought-hardening-20261027/build
env GOTOOLCHAIN=go1.27.1 CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
  go build -trimpath -ldflags "-X main.callDiagnosticBuild=$CANDIDATE" \
  -o ../.codex-test-logs/relay-thought-hardening-20261027/build/relay-server.v1.11.3 .
shasum -a 256 ../.codex-test-logs/relay-thought-hardening-20261027/build/relay-server.v1.11.3
go version -m ../.codex-test-logs/relay-thought-hardening-20261027/build/relay-server.v1.11.3
go tool nm ../.codex-test-logs/relay-thought-hardening-20261027/build/relay-server.v1.11.3 \
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
   `Environment=MKNOON_RELAY_THOUGHT_METRICS_ENABLED=true` and
   `Environment=MKNOON_RELAY_METRICS_BIND_IP=127.0.0.1`, after recording whether
   that exact file already exists and retaining a private backup if so. Securely
   provision the required random `MKNOON_RELAY_THOUGHT_METRICS_KEY` in the existing
   protected service env file; never print/read back its value. Verify
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
Do not restore the older v1.11.1 backup by accident or reset Redis/inbox data.
Rollback also ends this collection epoch: complete and verify snapshot-only
deletion within seven days of switch-off. Prefer a clean counter-OFF restart
of the candidate before restoring v1.11.2. If that is not possible, the approved
release operator must remove only the resolved `thoughts-metrics.json` regular
file, sync its parent directory and verify absence; v1.11.2 has no OFF-startup
cleanup and must not be assumed to perform it. Preserve identity, media and all
custody data. Record the failed attempt, deletion evidence and rollback outcome.

To stop collection while retaining v1.11.3, set the dedicated enable flag to
`false`, daemon-reload and cleanly restart **within seven days of switch-off**.
The snapshot is deleted on the first restart with the counter OFF; check it is
absent and that no deletion failure was reported. The same behavior applies to
an unset/unrecognized enable flag. Normal ON startup with a missing/invalid key
refuses the collector without claiming deletion succeeded. Series become absent,
not zero; there is no historical backfill for time disabled. Root/operators
must separately apply approved retention for backups and Prometheus history.
Wiping a file is logical deletion, not a promise of forensic secure erasure.

## Prometheus readout

**Behavior change for ALL relay metrics:** `MKNOON_RELAY_METRICS_BIND_IP` defaults
to `127.0.0.1`; the port remains 2112. An explicit IP override (for example
`0.0.0.0` or `::1`) is possible; invalid input leaves the metrics listener off
with a diagnostic while relay message service continues. The endpoint itself
has no authentication, so retain approved network access controls.

Before activation, account for every existing Prometheus consumer and confirm
it reaches the loopback endpoint using a local scrape or an existing approved
SSH tunnel. A direct remote Prometheus scrape must be adapted before release;
do not silently break all existing relay monitoring. Example approved tunnel:

```sh
ssh -i <approved-key-path> -N -L 12112:127.0.0.1:2112 ubuntu@51.21.194.144
# In another terminal, without opening port 2112 publicly:
curl -fsS http://127.0.0.1:12112/metrics
```

The normal SSH helper can also execute a local-only
`curl -fsS http://127.0.0.1:2112/metrics` on the host after approval. Do not print
service environment/key values. The week label is calendar ISO week; substitute
the recorded pilot weeks.

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

## Build 129 relay opt-out contract

Agreed with Claude-UI in `m-d467a3cf` after `m-1d69c2f5`: a top-level JSON boolean
`thoughts_metrics_opt_out: true` in the existing outer `post_create` routing
metadata, next to `post_id`, `sender_peer_id` and `created_at`, outside encrypted
content. App-owned seam: `PostCreateEnvelope.buildEncryptedEnvelope`.

The relay checks this flag after accepted inbox storage, before
hashing or updating either sketch. True skips both post/sender contributions;
false/absent preserves existing eligibility; the app omits the key while ON.
Any nonboolean (including JSON null) skips counting while message delivery remains
unchanged. No opted-out-person list,
new stored identifiers or opt-out metric labels are introduced.

Claude-UI owns the planned app DB v125 `metrics_opt_out` post-row field,
default 0. Creation captures the switch; switching OFF also marks the user's
own posts with undelivered recipients. The bit is one-way per Thought: switching
back ON never clears an older true value. Every recipient/retry rebuilds from
that durable row, so newly built copies cannot become eligible after an
opted-out decision. A copy already serialized/submitted while ON can still
arrive after OFF, including after a newer opted-out copy. A row update cannot
recall in-flight bytes, and the stateless relay admission rule cannot establish
an acceptance-time cutoff. Already submitted requests may complete/count;
previously counted contributions remain. This engineering nuance was sent to
Claude-UI and Kayan in `m-8a45642a`; keep the withdrawal wording precise rather
than adding a cancellation/barrier mechanism for this counter.

A previously counted Thought cannot be subtracted from an HLL; the relay will
not retain individual history to undo it. The seven-day global OFF deletion
rule does not mean each user's app switch erases their historical contribution.
The present collector reads only `post_create`: chat replies/quotedMessageId,
reactions, views and `post_pass` are ignored and have no engagement metric in
this task. Do not add opt-out fields to those unrelated types for this counter.

Kayan authorized implementation and guarded focused testing in the partial
resume reply to `m-9a79d135`. Actual inbox tests cover absent/false eligibility,
true/null/other-type exclusion, unchanged fanout/retry delivery and the delayed
eligible-copy boundary. Full relay validation and frozen builds remain held.
The hardening source review remains scoped to its fixed commit; the opt-out
delta needs its own scoped review rather than reopening settled findings.
