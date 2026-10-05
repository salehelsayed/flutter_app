# Handover: Wave 4 production measurements (2026-10-05)

Branch `wave3-baseline-20260930` (also `main`, see "Git state"). Results and
classification: crosswalk sections "2026-10-05 Wave 4 batch 1" and
"2026-10-05 Wave 4 device results" in
`docs/testing/production-bootstrap-migration-crosswalk.md`.

## Status: Wave 4 device work complete

All 26 Wave 4 harnesses have a disposition:
- 3 already covered by `production.startup_resume_performance` (B, M, BR);
- 6 new or extended production measurements, each device-proven (run PASS,
  negative probe FAIL at the intended step):
  `production.startup_resume_performance` + C-Sim-2,
  `production.transport_census`, `production.message_latency` (A, R, GP),
  `production.notification_tap_latency` (N);
- 15 retained as component evidence (6 reclassified from the baseline, with
  source reasons), 2 dispatchers retained;
- the shared-XCTest adapter has a real caller, `production.shared_xctest`,
  PASS on the iPhone 11.

## Open items for the user

1. **Notification regression on main.** `329ff3140` ("commit the remaining
   working-tree changes") carried another session's unfinished
   notification-lock work. With it, `production.notification_open` fails:
   the push reaches the backgrounded receiver, the background handler logs
   `PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED (exact_sql_authority_unavailable)`
   and Alice's message never reaches Bob's database. With the five
   notification-lock files at `9d253a273` the journey passes (A/B run on the
   run tree only). main still has the regression; fixing or reverting it is
   the user's call.
2. **Original A and R benchmarks** send without the recipient ML-KEM key and
   stop at `encryption_required` before any transport. Fixing the original
   harnesses needs approval.
3. The iPhone 11's Appium WebDriverAgent (another session's) was stopped for
   the XCTest batch at the user's choice; that session must restart it.
4. Not done: a forced-relay census condition (the relay-only profile is
   reserved to the startup/resume scenario); R-Sim-6 and R-Sim-8 recorded as
   not reproduced.

## How to run

- Device runs use the worktree `.claude/worktrees/wave3-next`; code is
  edited and committed in the main checkout (host git only: container git
  hangs on the shared disk), then `wt_next.sh rebase`.
- Queue: `docker-ws/beta/wave3/queue.sh` with `QPREFIX=production-`,
  `QPROOF=production.`, `QCONFIG=<worktree>/.codex-test-logs/production-bootstrap-migration-20260930/wave4-device-config.json`
  (Pixel 6 + emulator-5554) or `wave4-device-config-ios.json` (iPhone 11),
  `QAVDS=7` (or `none`). Quiet wait is 1 minute.
- Always run `docker-ws/beta/wave3/watchdog.sh <queue log> 0` beside a queue
  (`STALL_S=1800` for a first iOS device build).
- New capabilities: `docker-ws/beta/wave4/register_capability.py <spec>`
  (specs in `docker-ws/beta/wave4/specs/`).
- The iOS device build needs the signing attestation
  (`docker-ws/beta/wave4/mint_signing_attestation.sh <udid> <out>`; output in
  the git-ignored `docker-ws/beta/wave4/private/`), exported by
  `docker-ws/beta/wt_campaign.sh`.
- `docker-ws/beta/main_check.sh <files...>` formats, analyzes and tests only
  the named files (other sessions edit the main checkout).

## Landmines met

- Measurements run alone on the Mac: no builds or test runs beside them.
- A relay can drop and recover within one host poll: watch the production
  state stream, not snapshots, for short outages.
- SIMS rejects evidence whose validator IDs differ from the manifest's single
  `artifactValidator`.
- A test-only xcodebuild inside SIMS must set `SIMS_CHILD_BUILDS_FORBIDDEN=1`.
- Stopping a queue mid-probe leaves the probe edit: restore it with
  `probe_apply.py restore` and compare with the `.orig` file.
- A same-peer notification tap emits no tap-to-message timing (the screen is
  already open).
