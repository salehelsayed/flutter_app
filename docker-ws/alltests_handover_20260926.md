

## Continuation 2026-09-25/26 (Claude Code session) — STOPPED on user request

User instruction for this session: finish remaining tests with fix-as-you-go, keep the user posted, use Jev triage
when debugging, then stop. NO final clean sweep was run. Stop requested 2026-09-26 ~16:10 local.

### How this session ran things (read before resuming)
- Checks launched only from the clean worktree via `docker-ws/alltests_launch.sh <ids> <label> [device-config] [nodeps]`
  (main checkout `/Volumes/CrucialX9/flutter_app/docker-ws/`). It sources `run-env-after-source039.sh` with NO
  positional args (run-env-next.sh ends in `exec "$@"`; sourcing it with args execs the check id → exit 127).
  Wrapper = `docker-ws/alltests_checkpoint.py` (copy of restart-checkpoint.py with device-config arg; updates
  repair-progress.json like the original).
- Focused diagnostics (NOT check results): `docker-ws/alltests_sims_focused.py` (one SIMS capability via
  `sims.dart major --only <cap>` + streamed Pixel logcat into `<label>/pixel-logcat.txt`),
  `alltests_seq_focused.sh` (several in sequence), `alltests_gmp_focused.py` (group multi-party scenarios on the 4 sims),
  `alltests_friends_focused.py` (one friends smoke scenario).
- IMPORTANT host issue: `flutter build ios` leaves orphaned flutter_tools dartvm forks (ppid 1) that keep the
  parent's stdout/stderr pipes open → any harness that waits for stream close hangs forever. Reaper:
  `docker-ws/alltests_reap_orphans.sh` (only kills worktree-cwd orphans when no live build). Both capture scripts now
  drain output for at most 30 s after exit (fixed, see below).
- `full-legacy` cannot run alone (BLOCKED "Schedule dependency cycle or unavailable dependency") and in the combined
  run its routes are HELD (`device_cleanup_review_required`) whenever any full-sims-major device check fails.

### Check results this session (real check runs)
PASS: full.xctest…testnotificationtap (source070), …testcoldnotificationtap (source078),
…testautomatelocalnetworkpermission (source080; needs user to approve iOS "enable UI automation" once per boot),
…testtapexistingnotification (source084), full.group-reaction.ios_announcement_reaction_recipient (source087),
full.group-reaction.ios_chat_group_message_and_reaction_recipient (source096), full-notification-recovery
(source081, and again source102 after the contract-#1 revert).
FAIL: full-sims (source092: 66/67 routes PASS; friends scenario 8 "offline intro relay heals" failed — C accepted
but A/B never got it; passed when rerun alone (source093) → likely intermittent).
FAIL: full-sims-major (source097, before most fixes: 31/38 PASS; FAIL sims.contracts #1 [my change, since reverted],
android.keepalive_drop_skip_direct, notifications.android_payload_campaign, notifications.ios_payload_fast_path,
groups.multi_party_release [37/109], groups.media_send_reliability_ios; intro.accept N/A reserved emulator).
BLOCKED: full-legacy (source097: 5 steps PASS, 75 routes held by the failed major device checks).
BLOCKED (fixtures, user chose to leave): 3 VC205 XCTests (need real caller QR `MKNOON_VC205_CONTACT_QR` + live call;
no repo driver), testreactionnotificationtap (Plan 256 staged tap config), android_message_unread_lifecycle /
android_physical_recipient / ios_physical_recipient / head_provenance (staging+capture manifests).

### Fixes applied this session (all mirrored main ↔ worktree, analyzer/format clean, host tests listed PASS)
1. lib/core/debug/private_media_outbox_e2e.dart — curly-brace lint (analyzer.flutter).
2. test/…/background_storage_liveness_journal_test.dart — overlap test joins publication (maxCallerImpact 1 min) (11/11).
3. scripts/test/host_test_gate_batch_contract_test.sh — `unset MKNOON_HOST_FLUTTER_WORKERS` (wrapper leaked workers=2).
4. tool/testing/selection.json — LocalNetwork adapter `-configuration Profile` + `ENABLE_TESTABILITY=YES`
   (Debug Flutter app launched by XCUITest never starts Dart on iOS 14+ → prompt never appears). Prep script
   `docker-ws/alltests_prepare_localnetwork.py` (Profile config-only). Validated metadata.
5. PRODUCT: lib/core/services/p2p_impl/p2p_inbox_coordinator.dart — recovery-only `_verifyFullDrainOutcome` ignores a
   delivery_receipt parked `typed_handler_unavailable` for the foreground (it blocked headless recovery forever;
   chat content still blocks). Regression test in test/core/services/p2p_service_recovery_only_test.dart (RED→GREEN);
   1421 core services/notifications/bootstrap tests PASS.
6. integration_test/scripts/capture_1to1_reaction_head_provenance.dart — timeout-path evidence (runtime log, snapshots,
   force audit, jobscheduler dump); forcing logic back to the TC-393-12-pinned original (contract #1 PASS);
   recipient relaunch waits for its own push registration before the authenticated unregister (race re-created the
   route); bounded 30 s post-exit output drain in _runStreaming.
7. integration_test/scripts/capture_group_reaction_notification_device.dart — same bounded drain; Plan 397 path grants
   POST_NOTIFICATIONS to the reinstalled Android sender (OS dialog covered the fixture UI).
8. scripts/run_ios_notification_tap_ui_smoke.sh — 120 s readiness bound starts at XCTest case start (compilation has
   its own 30 min budget); legacy hash pin updated.
9. integration_test/background_reconnect_test.dart — repeats the relay-down proof window (max 3) only when automatic
   relay recovery returned before the send proof; hash pin updated.
10. integration_test/group_multi_device_real_harness.dart — GroupRepositoryImpl wired like production (removed-shell
    authority + membership watermark). Focused: ge002, private_abc_create, ge016 PASS. Re-add family (ge015,
    private_*readd*, private_history_retention) still FAIL by design: after self-removal the product only allows
    re-entry via accepted invite ("Ordinary group creation cannot cross a retained self-removal floor"); fixtures must be
    reworked to real invite re-entry (user chose: record, separate plan). A delete-shell helper was tried and reverted.
11. integration_test/scripts/android_keepalive_drop_campaign.dart — keep latest [CONN] callback across the 4000-line
    polls + record observed callbacks. Focused keepalive PASS (source101); disconnect callback arrives ~15.4–16.0 s vs
    16 s deadline → still near the edge (user decision if it flakes).
12. PRODUCT (Go, user approved vs 359f6fca7): go-mknoon/node — after ACK read timeout on a RELAYED (limited) conn,
    probe it once (2 s) and if unresponsive close it and resend once within the remaining budget; direct conns
    unchanged. `[SEND] ack_read_failed …` and `stale_relay_circuit_closed resending_once …` log lines.
    Tests: go-mknoon/node/stale_relay_resend_test.go (RED without fix, GREEN with); node Send/Ack/Relay/Deadline suites PASS.
    Device: B13 passed once with a real resend (source105); later run (source112) failed B13 with ack timeouts where
    the probe was INCONCLUSIVE (no resend) and once conn_closed=true after 227 ms → further B13 failure modes remain.
13. integration_test/scripts/notification_android_payload_campaign.dart — failure message keeps app step errorType;
    warm leg arms the post-tap observer before the SSH relay-journal check (cached-apps freezer froze the receiver);
    permission-denied leg uses `_sendSpacedProviderMarker` (live send suppresses the provider). 184 tests PASS.
14. integration_test/scripts/ios_notification_payload_xcui_driver.dart — stage Documents/auto_setup.json after
    install (fresh installs had no account → no node → no permission/handoff); finalization failure keeps the first
    failure; handoff mismatch names fields. 21 tests PASS.
15. iOS group media harness — keeps fixed StateError detail, saves fixture stderr stage + xcodebuild-test.log
    (group_media_reliability_runner_contract.dart, group_media_ios_background_recovery.dart); fixture driver accepts a
    slow first frame (`Status: timeout` + exact component + live pid); GroupMediaBackgroundRecoveryUITests.swift
    background wait = SpringBoard-foreground then app.state (compiled on device, run).

### Open items for the next session
- iOS payload (notifications.ios_payload_fast_path): now reaches the handoff; fails `mismatched: peerDeviceId` because the
  private staging manifest/provider request (Sep 21, `.codex-test-logs/all-tests-y227gs8x/ios-fixtures-metric-deployed/`)
  are bound to the OLD receiver libp2p peer id, lost when cleanup uninstalled the app. Needs fresh fixture generation
  for the current receiver identity (do not hand-edit). Also: prepare XCTest hard-codes `permission_automated=true`
  (NotificationTapUITests.swift:225) — make it report the real result (separate change).
- iOS group media: reaches phase-A ready; after `XCUIDevice.press(.home)` the app stays `runningForeground` (state 4)
  (source112). Needs device-level look (screen recording lost because xcodebuild is SIGKILLed at 8 min; consider
  stopping xcodebuild promptly after the XCTest ends so the xcresult completes).
- Android payload B13: resend path only fires on a conclusively unresponsive relayed conn; source112 shows inconclusive
  probes and a closed conn. Pixel logcat per run is in `<label>/pixel-logcat.txt`.
- Group multi-party re-add family (≈20/109) needs invite re-entry fixtures (separate plan).
- Possible product gap (unverified): production_canonical_inbox_projection_composition.dart:1400 builds
  GroupRepositoryImpl without removed-shell functions, and its headless GroupMessageListener would fail a self-removal.
- Owning full-sims-major + full-legacy rerun with all fixes NOT done (≈10 h; legacy stays held while any major device
  check fails).
- Owned TURN container `mknoon-all-tests-foreground-turn-4a6a560b` still running (needed for foreground audio);
  remove it only at true final stop.
- repair-progress.json was updated only by real check launches (alltests_checkpoint.py), not by focused diagnostics.
- Helper scripts live untracked in `/Volumes/CrucialX9/flutter_app/docker-ws/alltests_*` (+ `.run_handover_copy/`,
  git-excluded). None were committed. No commits were made.
