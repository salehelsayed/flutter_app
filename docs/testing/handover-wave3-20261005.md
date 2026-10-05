# Handover: Wave 3 production catalog journeys (2026-10-05)

Branch `wave3-baseline-20260930` (local only, never pushed).

**Status: Wave 3 device work is complete (2026-10-05).** All 107 original
multi-device catalog cases are accounted for: 51 have a production
replacement proven on devices (run PASS, negative probe FAIL at the intended
step) and 56 are recorded as not portable. The last four, the iOS simulator
journeys, finished on 2026-10-05. Results and the census: crosswalk section
"2026-10-04 Wave 3 batches 10 to 13, the fourth role and iOS simulators" in
`docs/testing/production-bootstrap-migration-crosswalk.md`.

## Where the code is

- **Main checkout** `/workspace` (= `/Volumes/CrucialX9/flutter_app`) has all
  Wave 3 commits.
- **Worktree** `.claude/worktrees/wave3-next` (branch `wave3-next`) is where
  edits and device runs happen. `wt_next.sh sync` copies its commits to the
  main branch and rebases it. Container git cannot resolve its gitdir; use
  `wt_next.sh git ...`.
- Another session (notification-lock work) keeps uncommitted edits in the main
  checkout (`lib/core/notifications/*`, `ios/*`, new untracked files). Do not
  commit or touch them. Device runs use the worktree for this reason.

## Done on 2026-10-04 (Android, device-proven)

| Case | Devices | Probe result |
|---|---|---|
| GE-024 quoted reply (`ge024`) | 3 Android | FAIL at `alice-renders-replies` |
| L-01 media reaction (`private_media_reaction_roundtrip`) | 3 Android | FAIL at `bob receives the image message` |
| gm002 | 4 Android | FAIL at `dana pending invitation` |
| ML-002 (`private_online_add`) | 4 Android | FAIL at the oracle |
| gm003 | 4 Android | FAIL at the oracle |
| ML-003 (`private_offline_add`) | 4 Android | FAIL at the oracle |
| UP-012 (`private_removed_notification_privacy`) | 3 Android | FAIL at `alice-back-to-chat` |

## Done on 2026-10-05 (three DeviceHub iOS 26.5 simulators)

| Case | Probe result |
|---|---|
| NW-006 `private_peer_disconnect_not_removal` | FAIL at the oracle (`bobDisconnected`) |
| ML-020 `private_admin_role_transfer_delivery` | FAIL at `charlie receives aliceRemovedWindowAfterDemotion` |
| NW-003 `private_partition_readd_heal` | FAIL at the oracle (partition fields) |
| NW-010 + OB-011 `private_background_resume_group_delivery` | FAIL at the oracle (`bobBackgroundedDuringAliceActivity`) |

Simulators: iPhone Air 6597ECAD, iPhone 17 8E31AD68, iPhone 16e DBE8C32E
(config `.codex-test-logs/production-bootstrap-migration-20260930/wave3-device-config-ios.json`
in the worktree). Label stays `ios_26_2_core_simulator` (user decision).

## Product findings from the iOS runs

File: `Test-Flight-Improv/Production-Flow-Audits/findings/group-key-rotation-authority-2026-10-05.md`.

- **001 (open, needs a product decision):** after an admin handover nobody
  may rotate the group key (rotation needs the rotateKeys role AND being the
  creator), so a removed member keeps the current key. Proposed fix: one
  deterministic rotation leader per group, invisible to users. The user wants
  rotation handled without hurting usability.
- **002 (fixed, 55de94641):** Group Info kept showing a removed member until
  the new key reached every member; it now reloads when the removal is
  broadcast.
- **NW-010 drain fix (0268dfe79):** the inbox drain dropped the replay
  envelope's key epoch (reported 0), so an offline member rejected a signed
  removal on return and kept the removed member. A diagnostic (5650cb6b0)
  logs per-field state-hash parts on such a rejection.

## Remaining

1. Wave-end host-all ran in the worktree on 2026-10-05 (`docker-ws/beta/r92_wt_host_all.sh`,
   log `docker-ws/beta/r92_host_all.out`): Flutter 18,914 passed, 1 failed:
   `test/integration/relay_down_degradation_integration_test.dart` case 4
   failed only in the concurrency-4 batch and passes alone (5/5), so it is
   parallel interference. The 8 Go commands the lane skips after a red were
   run separately: all pass.
2. Finding 001 needs a product decision before code.
3. Nothing is pushed. Pushing, merging and relay changes need explicit approval.

## How to run (tools)

All Mac-side scripts are in `docker-ws/beta/` and run through `host-run`.

- `wt_next.sh setup|git|flutter|sync|rebase`; `wt_check.sh [tests]`;
  `wt_commit.sh` / `wt_commit_paths.sh` (message in `wt_commit_msg.txt`).
- `wt_campaign.sh <checks> [config]`: a device campaign in the worktree.
- `docker-ws/beta/wave3/queue.sh` (`run:<k...>:<sc...>`, `probe:<k>:<sc>:<spec>`;
  `QCONFIG=`, `QAVDS=none` for iOS), `probe_apply.py`, `probes/*.json`.
- `docker-ws/beta/wave3/watchdog.sh <queue log> [sims]`: run it beside every
  queue. It exits on done, a stall, a lost simulator or a queue that never
  starts, and clears orphaned `flutter build ios` helpers.
- `r79_progress.sh` (live progress), `r89_sim_flow_log.sh` and
  `r90_sim_log_raw.sh` (a simulator's app log), `r88_sim_kill_probe.sh`.

## Landmines

- Never edit the worktree while a queue run or probe is active: the run's
  source digest changes and the build can mix sources. Hold fixes in the
  scratchpad and apply them between runs.
- Stopping a queue mid-probe leaves the probe edit applied; the queue refuses
  to start while "NEGATIVE PROBE" is in the tree (`probe_apply.py restore`).
- iOS simulator journeys: the build must be signed (App Group); Maestro's iOS
  driver needs the build-guard allowance; `simctl spawn` needs `/bin/kill`;
  the iOS app opens on the circle view.
- `flutter build ios` leaves orphaned `dartvm` helpers that hold SIMS's pipe;
  the watchdog clears them.
- host-run calls die with the tool-call timeout: long Mac jobs self-detach.
- The simulators are wiped after each run; keep evidence in the watch
  snapshot (proof folder), not on the device.
- Container `git` can hang on virtiofs; commit on the Mac.
