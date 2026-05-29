# Closure Reference: Reliable Group Discussions

**Purpose:** define what "reliable enough" means for current group discussion text/media/voice messaging in this repo without pretending group chat has identical transport semantics to 1:1 chat.

---

## Architecture Note

Group discussions are **not** 1:1 chat with more recipients.

Current group reliability is built on:

- pre-persisted local sender state,
- concurrent publish + inbox fallback,
- resume-oriented recovery,
- receipt-less publish semantics,
- and local one-thread send serialization.

This closure reference is therefore a **sender-trust closure**, not a promise of per-recipient ACK proof.

---

## Closure Statement

The current group discussion system should be treated as **reliably closed for core messaging** when all of these remain true:

1. outgoing text/media/voice messages persist enough local state before publish/upload risk,
2. interruption and resume recovery can rejoin, drain, recover, and retry without losing sender work, including closing interrupted pending rows exactly once,
3. the current reachable text send surfaces share one interruption-safe sender entry contract,
4. ordinary media remains durable across send-then-lock and publish-failure retry paths,
5. one conversation screen does not run overlapping local send pipelines,
6. user-visible statuses stay honest for a receipt-less group transport model.

This is the closure bar for current group discussions.

---

## What Current Closure Already Includes

### 1. Durable sender-side text path

- `send_group_message_use_case.dart` pre-persists the outgoing row before bridge publish work.
- Live-peer and legacy-success publish paths no longer overstate durable closure as `sent` while offline inbox custody or retry-owned inbox storage is still unresolved.
- The send path carries enough local state for later retry/recovery through `wireEnvelope`, `inboxStored`, and `inboxRetryPayload`.
- `pending` can now honestly mean "live publish accepted, inbox custody is still open" while the zero-peer or already-inbox-backed path can still close `sent` when custody is durably closed.

### 2. Caller-surface text parity

- `group_conversation_wired.dart`, `feed_wired.dart`, and `share_batch_delivery_coordinator.dart` now route the current reachable group or announcement text sends through the same interruption-safe sender entry contract.
- Feed inline reply and share-to-group now own the same explicit `bg:begin/bg:end` background-task wrapping already used by the main group conversation surface.

### 3. Durable ordinary-media path

- `group_conversation_wired.dart` now persists the parent `GroupMessage` row before ordinary-media upload starts.
- `retry_incomplete_group_uploads_use_case.dart` and `retry_failed_group_messages_use_case.dart` now give ordinary media the intended retry/recovery shape.
- This closes the earlier ordinary-media parent-row and publish-failure retry gaps.

### 4. Strong resume-oriented recovery

The current group flow already has meaningful recovery on resume:

- topic rejoin
- group inbox drain
- stuck-send recovery
- incomplete-upload retry
- failed-send retry
- failed-inbox-store retry via `retryFailedGroupInboxStores(...)`

That is enough for the current group closure bar when combined with durable local persistence.

- Repeated pause/resume now closes the same mixed live/offline pending sender row exactly once without a second publish.

### 5. Explicit one-thread send serialization

- `group_conversation_wired.dart` owns a shared local send guard
- `group_conversation_screen.dart` threads `isSending` into `ComposeArea`

This means one group conversation screen now intentionally prevents overlapping local send pipelines instead of relying on luck.

### 6. Honest group status semantics

Current closure treats these as the meaningful outgoing statuses:

- `sending`
- `sent`
- `pending`
- `failed`

That is the correct level of honesty for a publish + inbox-backed, receipt-less group system.

### 7. Settled media budget and foreground upload protection

- Ordinary group attachments now use the settled `5 GB` general-media budget
  across the live composer entry points that matter in this repo, including the
  hydrated attachment paths that reuse the same pending-media state.
- The in-app voice recorder keeps its separate `100 MB` sanity limit; that
  remains a recorder-specific safeguard, not the ordinary attachment budget.
- The current group conversation surfaces now show honest foreground upload
  protection for active relay uploads:
  - aggregate byte progress
  - the warning copy `Keep the app open until the upload completes`
  - leave confirmation while an upload is active
  - a ref-counted wake lock that stays held until the last active relay upload
    finishes, fails, or is cancelled
- Active relay-backed group uploads now also expose a user-controlled cancel
  path in the live conversation surface, but the promise stays honest:
  - cancel does not interrupt in-flight member uploads mid-stream
  - the current parallel upload batch is allowed to resolve, then the composer
    snapshot is restored, the optimistic row is terminalized to `failed`, and
    durable pending attachments are marked `upload_failed`
- Failed outgoing group media rows now expose message-scoped retry/delete
  controls:
  - retry acts on the same failed row instead of creating a duplicate
    optimistic row
  - delete removes only the targeted failed row and only app-owned durable
    pending-upload files
- Announcement admins inherit this shared group failed-media recovery surface,
  while read-only announcement members still do not gain the write-path
  controls.
- This closure is still intentionally foreground-only. The repo does **not**
  promise true background upload execution or download-side wake-lock behavior.

### 8. Discussion new-member onboarding proof

- `test/features/groups/integration/group_new_member_onboarding_test.dart`
  now proves a newly-added discussion member receives only post-join text,
  image, video, and voice messages through the bridge-backed group send path.
- The same test preserves the no-backfill contract for a pre-join message and
  asserts the receiver persists image/video/audio descriptors and starts
  media-download work for each incoming media attachment.
- The suite also covers post-join side context for a newly-added member:
  Charlie's reaction to a post-join message fans out to Bob through the
  listener/reaction repository path, and a post-join quoted reply to a
  pre-join parent keeps the parent absent while the group conversation UI
  renders `Message unavailable`.
- Multi-member onboarding now has host-side epoch evidence: Bob and Charlie
  converge on the same latest fake-network epoch and receive the same post-add
  message with that `keyGeneration`.
- The add/send boundary is pinned for the fake network: a staged but
  unsubscribed Bob does not receive the racing message, then receives the first
  post-subscription message exactly once while member lists converge.
- Re-add/current-state evidence remains covered by
  `group_membership_smoke_test.dart`, which verifies the re-added member uses
  the current fake epoch and does not receive removed-period traffic.
- `integration_test/group_real_crypto_onboarding_test.dart` now adds the
  real-bridge app-boundary crypto proof for first-add and re-add: Bob accepts
  production encrypted group invites through `handleIncomingGroupInvite`,
  decrypts current-epoch `group.encrypt` ciphertexts with the accepted keys,
  and retained old key material fails against the re-add ciphertext.
- The new crypto suite is device-backed Nightly / Release Pool evidence. It
  does not replace the separate live GossipSub/two-node real-network simulator
  closure bars tracked by Report 85.
- The Report 85 crypto/security boundary is now explicit: replay convergence
  is the Flutter `messageId`/content dedupe contract, not nonce-cache
  rejection, and Go group-topic validation rejects forged signed
  `members_added` envelopes before decoded membership events reach Flutter.
- GMAR-002 tightened `test/features/groups/integration/group_media_fanout_test.dart`
  on `2026-05-02`: existing Bob and Charlie now each independently complete
  Alice's image, video, and voice downloads with matching incoming message ids,
  attachment metadata, `done` status, local paths, and exact per-recipient
  download calls. The suite also proves one recipient's forced download failure
  remains visible as failed/non-done while the other recipient succeeds.
- GMAR-002 also tightened the lower relay/blob proof in
  `go-mknoon/integration/media_test.go`: two authorized non-sender members now
  independently download the same group blob byte-for-byte while an outsider is
  rejected. This is existing-member app-layer/blob authorization evidence;
  GMAR-003 and GMAR-004 carry the later membership-boundary app-layer parity and
  configured visible/recovery proof.
- GMAR-003 tightened the host/app-layer membership-boundary media proofs on
  `2026-05-02`: `group_new_member_onboarding_test.dart` now proves newly-added
  Bob and Charlie independently download Alice's same post-join image, video,
  and voice while pre-join text/media remains excluded. `group_media_fanout_test.dart`
  now proves newly-added Bob's media reaches Alice and Charlie, and existing
  non-creator Charlie's media reaches Alice and Bob, with completed downloads,
  sender identity, sender message ids, key epoch, attachment metadata, and exact
  per-recipient download calls. The full media fan-out suite stayed green, so
  MD-011 removed-member future-media exclusion remains protected.
- GMAR-004 accepted the remaining Report 90 configured visible-media/recovery
  layer on `2026-05-02`: the simulator proof on
  `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` now passes after fixture metadata was
  made truthful under group media integrity policy, host screen/wired tests prove
  video/voice/failed media rows, reopen hydration, retry visibility, and no
  duplicate rows/attachments, and the full drain offline inbox suite passes after
  legacy fake replay fixtures were signed at the test fake bridge boundary. No
  GMAR-004 production group media or replay logic change was required.
- GMAR-005 closed the final Report 90 gate-confidence layer on `2026-05-03`:
  after fix-authorized recovery for failing media-message journey metadata,
  stable-ID/all-gate, broad host-suite, and two-simulator smoke orchestration
  evidence, the final rerun passed every required direct GMAR suite, configured
  simulator media proof, two-simulator routing/group and foreground group push
  smoke command with relay addresses, device-pinned `run_test_gates.sh all`,
  `completeness-check`, broad `flutter test`, `cd go-mknoon && go test ./...`,
  and `git diff --check`.
- GMAR-001 tightened the text-only fan-out proof on `2026-05-02`:
  `group_messaging_smoke_test.dart` now proves Admin, Bob, Charlie, and Diana
  each receive the other three active members' text messages exactly once with
  matching sender peer IDs and usernames. The focused four-user text proof and
  the `groups` gate both passed.
- That GMAR-001 evidence alone closes only the text complaint shape where a member
  sees creator-authored text but misses other active members' text. It does
  **not** close Report 90 all-recipient media parity by itself: that media proof
  is now carried by GMAR-002, GMAR-003, and GMAR-004, with final gate/full-suite
  reconciliation closed by GMAR-005.
- Report 89 extends that same suite to the newly-added sender path: after
  bootstrap and latest-key persistence, Bob sends image, video, and voice, his
  outgoing rows retain the attachments, and Alice/Charlie each receive exactly
  one row with Bob's sender message ids plus image/video/audio metadata intact.
- Report 89 also adds a conversation-surface regression in
  `group_conversation_screen_test.dart`: a visible group row can contain text
  plus a video duration/play affordance, voice/audio affordance, and failed
  media state instead of silently dropping media. This is host widget evidence;
  process-kill restart persistence and broader real-stack/device-lab playback
  remain explicit residuals.
- Report 89 now adds Android emulator and iPhone 17 simulator proof in
  `integration_test/group_new_member_media_simulator_proof_test.dart`: a
  newly-added member's incoming and outgoing text-plus-video/voice rows render,
  voice reaches play/pause, video opens in the full-screen viewer, and the same
  rows survive a conversation-surface reopen on `emulator-5554` and iPhone 17
  simulator `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`. The companion Android
  emulator and iPhone 17 simulator runs for `media_message_journey_e2e_test.dart`,
  `media_stable_id_smoke_test.dart`, and `foreground_group_push_drain_test.dart`
  also passed on `2026-04-29`. True process-kill restart persistence, broader
  paired-simulator real-stack coverage, and real-device/TestFlight playback
  remain explicit residuals.
- `integration_test/foreground_group_push_drain_test.dart` now proves a
  representative foreground group push drains a targeted image inbox item once,
  preserves the media descriptor, triggers the media download path, and shows
  the expected notification text. This is direct foreground-router/inbox
  evidence, not OS background/terminated push or paired-simulator delivery.
- `test/features/groups/application/group_message_listener_test.dart` and
  `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`
  now pin the host-side removed-user notification boundary: self-removal
  deletes local group access, later group traffic creates no local
  notification, and a stale removed-group notification route resolves missing.
  Paired-simulator route-exit and OS stale-tap UI proof remain Report 85
  residuals.
- `integration_test/scripts/run_routing_smoke_e2e.dart` now consumes strict
  G2/G4/G5/G7/G8 group-smoke criteria from
  `integration_test/scripts/routing_smoke_group_criteria.dart`, with
  `test/integration/routing_smoke_group_criteria_test.dart` covering
  partial/pending failure cases. This prevents sender-only or pending receiver
  evidence from closing simulator rows.
- A paired simulator run attempted on `2026-04-29` reached Alice ready and
  launched Bob, then failed before S1 because Alice's child harness timed out
  waiting for `bob_identity.json` while Bob was still finishing startup. The
  Alice-side identity wait in `routing_smoke_alice_harness.dart` and
  `group_smoke_alice_harness.dart` now matches the orchestrator startup window.
- Report 85 GON-012 revalidated the host-side retry/media recovery surface:
  incomplete group uploads retry, failed group messages retry, and failed
  outgoing media rows with retry/delete controls all passed their focused
  suites on `2026-04-29`. The full simulator media matrix and simulator-visible
  recovery journeys remain residual Report 85 rows.
- Report 85 GON-013 revalidated local relay/recovery prerequisites: Go
  multi-relay fallback paths, fake-network partition/heal cursor ordering,
  duplicate live+inbox dedupe, and same-account host convergence all passed on
  `2026-04-29`. `multi_relay_failover_test.dart` now has a strict
  `MKNOON_REQUIRE_MULTI_RELAY=true` mode so fixture-backed closure runs fail
  clearly when relay addresses are absent. Live relay outage replay and
  same-account two-device simulator execution remain device-lab residuals.
- Report 85 GON-014 tightened the fake-network partition/heal recovery proof:
  `group_resume_recovery_test.dart` now stages three missed split-window
  messages across cursor-ordered durable inbox pages, drains them exactly once,
  and then proves post-heal live delivery resumes. Real bridge/GossipSub
  partition recovery remains a simulator residual rather than a local closure
  claim.
- Report 85 GON-015 added the recurring fixture-backed command
  `./scripts/run_test_gates.sh group-real-network-nightly`. It requires
  `FLUTTER_DEVICE_ID`, forwards `MKNOON_RELAY_ADDRESSES`, and forces
  `MKNOON_REQUIRE_MULTI_RELAY=true`, so missing relay config fails clearly
  instead of becoming skipped evidence.

### 9. Direct epoch-key monotonicity proof

- GEK-001 closed the direct key-update listener and Go active-key boundary on
  `2026-05-09`: delayed older direct key updates no longer promote active key
  state after a newer accepted generation, conflicting same-generation key
  material no longer replaces the first accepted material, and duplicate
  same-generation material is idempotent.
- The accepted contract is intentionally split: Dart may retain
  non-conflicting historical older key material for replay, while Go keeps the
  latest active key and previous-key grace state monotonic.
- Evidence passed: focused GEK-001 listener red/green tests, the full
  `group_key_update_listener_test.dart` suite, the focused Go
  `TestUpdateGroupKey_*` monotonic command, `./scripts/run_test_gates.sh groups`,
  and `git diff --check`.
- This closes only the GEK-001 direct host/Go-boundary slice. GEK-003 and
  GEK-004 are recorded separately below, and GEK-005 final reconciliation is
  recorded in section 13 as `residual_only`.

### 10. Live decrypt durable repair proof

- GEK-002 is covered after its `2026-05-09` host proof plus GEK-005 recovery
  closure of the receipt-fixture follow-up. The host app-layer journey is where
  a live `group:decryption_failed` diagnostic creates a
  safe pending state, durable replay later arrives for the same missing message,
  the synthetic no-envelope live placeholder is superseded, and key arrival
  repairs the durable replay into exactly one visible plaintext row.
- `group_pending_key_repair_service.dart` now keeps the durable replay
  `messageId` canonical and emits `GROUP_LIVE_DECRYPTION_REPAIR_SUPERSEDED`
  when it removes a matching synthetic live placeholder.
- Evidence passed: the focused GEK-002 red/green regression, focused
  prerequisite selectors 2 through 6, the full `group_message_listener_test.dart`
  suite, `./scripts/run_test_gates.sh groups`, and `git diff --check`.
- Closed follow-up: the older `PREREQ-GROUP-SYNC-RECEIPTS` fixed-date receipt
  fixtures now use deterministic retention clock control. Full
  `drain_group_offline_inbox_use_case_test.dart` and broad
  `flutter test --no-pub test/features/groups` reruns pass.
- That GEK-002 closure did not itself close later sessions. GEK-003 and GEK-004
  are recorded separately below, and GEK-005 final reconciliation is recorded in
  section 13 as `residual_only`.

### 11. Partial key-update rotation race proof

- GEK-003 closed the deterministic host app-layer partial key-update rotation
  race on `2026-05-09`: Alice can rotate to epoch 2, Bob can receive and
  commit the key while Charlie remains on epoch 1, Bob can send immediately on
  epoch 2, and Charlie does not silently lose that message.
- `group_pending_key_repair_service.dart` now derives durable replay repair
  identity from the signed replay envelope account sender and transport
  identity before falling back to relay `from`, so a relay device sender can
  still converge with the live diagnostic account sender.
- The accepted proof shows Alice/current-key replay succeeds, Charlie's live
  decrypt failure creates a pending-key state, durable replay becomes canonical
  under Bob's real message id, later Charlie key arrival repairs one delivered
  plaintext row, and duplicate replay/retry stays exactly once.
- Evidence passed: the focused GEK-003 regression in
  `drain_group_offline_inbox_use_case_test.dart`, focused key-update/send and
  GEK-002 repair-convergence safety selectors, the `groups` gate (`103`
  tests), QA review, and `git diff --check`.
- This closes only the GEK-003 host app-layer rotation/send/repair slice. GEK-004
  is recorded separately below; this GEK-003 entry does not close final
  simulator/relay reconciliation. The old GEK-002 `PREREQ-GROUP-SYNC-RECEIPTS`
  fixed-date fixture follow-up is now closed by GEK-005 recovery.

### 12. Delayed membership/config durable replay proof

- GEK-004 closed the deterministic host app-layer delayed membership/config
  replay-ordering gap on `2026-05-09`: a signed durable message from a newly
  accepted sender can arrive before the recipient has the delayed membership
  config, defer safely, and recover after config catch-up.
- `drain_group_offline_inbox_use_case.dart` now defers signed durable group
  message replays rejected as `unknown_sender` within the page, then retries
  them before cursor commit after membership/config/system replay has run.
- The accepted proof shows the pre-catch-up replay creates no ghost row and does
  not advance the cursor, the delayed `member_added` config makes the sender and
  device locally known, the same durable message is delivered once with the
  expected sender/device/message identity, and duplicate replay stays exactly
  once.
- Unresolved unknown senders still reject before cursor advancement, and live
  unknown senders remain fail-closed. GEK-004 did not change invite eligibility
  semantics, per-recipient ACKs, Go/native behavior, or relay/simulator behavior.
- Evidence passed: the focused GEK-004 red/green regression in
  `drain_group_offline_inbox_use_case_test.dart`, all required GEK-001/GEK-002/
  GEK-003 safety selectors, membership/config and invite-truth selectors, QA
  reruns of the GEK-002 and GEK-003 drain selectors, the `groups` gate, and
  `git diff --check`. `completeness-check` was skipped because no
  `_test.dart` file was added, removed, or renamed.
- This closes only the GEK-004 host app-layer membership/config replay slice.
  GEK-005 final reconciliation is recorded in section 13 as `residual_only`, and
  the GEK-002 `PREREQ-GROUP-SYNC-RECEIPTS` fixed-date fixture follow-up is closed.

### 13. Final epoch-key reconciliation

- GEK-005 ran the final Report 94 acceptance-only evidence sweep and recovery
  rerun on `2026-05-10` and wrote the final program verdict `residual_only`.
- Green evidence: all 17 GEK-focused Dart selectors passed, full
  `group_key_update_listener_test.dart`, `group_message_listener_test.dart`,
  `drain_group_offline_inbox_use_case_test.dart`, and broad
  `flutter test --no-pub test/features/groups` passed, the focused and broad Go
  commands passed, the `groups` gate passed,
  `./scripts/run_test_gates.sh completeness-check` passed with `730/730` test
  files classified, and `git diff --check` passed.
- Closed follow-up: the exact old `PREREQ-GROUP-SYNC-RECEIPTS` fixed-date receipt
  fixtures now pass under deterministic retention clock control.
- Former broad-host blocker resolved: direct `drain_followup_invariants_test.dart`
  reruns prove local-delivered receipt re-derivation on dedup and
  `GROUP_MESSAGE_LISTENER_EMPTY_DROP` flow-event logging for malformed drained
  envelopes.
- Device/relay evidence: the configured iOS simulators
  `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` and
  `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` were booted and used with the supplied
  relay addresses. The single-device nightly passed as self-contained smoke
  because no CLI peer fixture was present; the paired iOS relay script passed
  its MD-004 primary/sibling proof. These are supporting evidence, not a claim
  of full live three-party GEK split-delivery closure.
- `Test-Flight-Improv/test-gate-definitions.md` was inspected through
  `completeness-check` and was not changed by GEK-005.

### 14. Four-user admin-permission checklist proof

- Report 96 is covered by the four-session GAPR rollout for
  `regression_group_admin_permissions_and_message_reliability_four_users`.
  The final program verdict is `accepted_with_explicit_follow_up` on
  `2026-05-29`.
- GAPR-001 stabilized the four-user baseline after fixing duplicate same-hash
  metadata/avatar recovery in the group message listener. Its targeted simulator
  evidence passed as run id `1780055021026`.
- GAPR-002 expanded the scenario and criteria to prove independent forbidden
  admin-action rejection for non-admin, demoted-admin, non-friend invite, and
  removed-member states. Its targeted simulator evidence passed as run id
  `1780057317153`.
- GAPR-003 added system-event visibility and richer convergence proof for
  promotion, demotion, removal, watermarks, pending-invite state, removed-member
  representation, latest event identity, avatar bytes/hash, state hash, and key
  epoch. Its final post-fix targeted simulator evidence passed as run id
  `1780060893842`, with proof accepted for Alice, Bob, Charlie, and Dana.
- Final GAPR-004 checks passed on `2026-05-29`: the criteria suite passed with
  537 tests, scenario listing/discovery still exposed the target scenario, the
  reliability-sims group list still mapped it as check `#87`, and scoped
  `git diff --check` passed.
- The explicit follow-up is not a Report 96 checklist gap: the full
  `./scripts/run_test_gates.sh groups` gate remains red only on the known
  non-target `UP-001 create add remove and re-add keep DB and bridge groupConfig
  snapshots aligned` stale-membership residual at
  `lib/features/groups/application/add_group_member_use_case.dart:281`.
  Do not reopen Report 96 unless the four-user admin-permission scenario, its
  action-specific rejection proof, its system-event proof, or its convergence
  proof regresses.

### 15. Group details recovery-save feedback proof

- Report 97 is closed on `2026-05-29` after the GDR rollout.
- GDR-001 added the group-details editor recovery-save waiting contract:
  localized non-jargon wait copy, elapsed waiting timer, Save disabled only
  while `groupRecoveryGate` is active or the name is invalid, draft
  name/description/photo preservation, raw recovery-error mapping, and avatar
  commit/delete atomicity when recovery starts during a save.
- GDR-001 host evidence passed:
  `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart`,
  `flutter test --no-pub test/features/groups/application/update_group_metadata_use_case_test.dart`,
  `flutter test --no-pub test/l10n/l10n_integrity_test.dart`, and
  `./scripts/run_test_gates.sh groups`.
- GDR-002 added promoted-admin A/B/C acceptance coverage for the reported shape:
  A/B and B/C are connected, A/C are not direct contacts, B and then C become
  admins, C's recovery-window details/photo save is rejected without local-only
  metadata/avatar persistence, and C's post-recovery save converges to A, B, and
  C.
- GDR-002 host evidence passed the targeted promoted-admin recovery-save
  selector, full `group_admin_metadata_convergence_test.dart`, and
  `./scripts/run_test_gates.sh groups`.
- No gate-definition changes were required; the existing groups gate remains the
  release-facing host proof for this regression.

---

## Accepted Architectural Differences From 1:1

These differences are real and do **not** automatically mean group discussions are unreliable:

1. group publish is receipt-less; it does not prove end-user receipt the way 1:1 ACK/inbox logic is stronger,
2. `sent` in groups means the current sender pipeline is durably closed, not "every member definitely received it",
3. `pending` in groups can honestly mean either no-live-peer inbox fallback or live publish accepted while inbox custody is still unresolved; it is not a failure,
4. local ordering is intentionally serialized per conversation screen, but distributed total ordering is not guaranteed,
5. group cancel remains batch-bounded: the current parallel upload batch is
   allowed to resolve before the optimistic row is terminalized, rather than
   pretending member uploads are interruptible mid-stream.

Future work may strengthen those areas, but they are not required to keep the current group system trustworthy.

---

## Current Residual Caveat

There are still narrow residuals worth remembering:

- voice publish-failure retry is weaker than ordinary-media retry because the producer-side completed-attachment seam is still narrower in the current tree
- Report 90 all-recipient media parity is now closed by GMAR-001 through
  GMAR-005. The accepted evidence includes existing-member app-layer
  image/video/voice download parity, two-authorized-non-sender blob
  authorization proof, newly-added/non-creator host app-layer media parity,
  configured visible render/playback/reopen/retry/offline/duplicate proof, and
  the GMAR-005 final gate/full-suite reconciliation.
- Report 94 epoch-key reliability final program verdict is `residual_only` after
  GEK-005. GEK-001 through GEK-004 stay closed, including the old GEK-002
  receipt-fixture follow-up. The remaining limitation is exact live three-party
  GEK stale-key/decrypt-repair split-delivery proof scope, not a focused GEK-001
  through GEK-004 regression. Do not reopen GEK-001 unless
  direct stale-older or same-generation conflict behavior regresses, do not
  reopen GEK-002 unless the live diagnostic plus durable replay plus key-arrival
  convergence regresses, do not reopen GEK-003 unless the partial key-update
  delivery plus immediate post-rotation send repair path regresses, and do not
  reopen GEK-004 unless delayed membership/config catch-up plus durable
  unknown-sender replay recovery regresses.
- Report 96 group admin-permission checklist coverage is accepted with explicit
  follow-up after GAPR-004. The remaining follow-up is the known non-target
  `UP-001` stale-membership groups-gate residual, not a reason to reopen the
  Report 96 four-user admin-permission checklist unless that exact scenario or
  its criteria proof regresses.

These are **not** reasons to reopen the whole group reliability program. Reopen only if they become real escaped bugs or clearly justified trust gaps.

---

## What Is Not Required For Group Reliability Closure

These are intentionally **not** part of the current closure bar:

- group ACK / per-recipient delivery proof
- read receipts
- total ordering across devices
- heavy outbox/job architecture
- broad status-model redesign
- true background upload architecture
- announcement authorization proof
- search, scheduling, analytics, or other product-scope features

Those may be future product or protocol work, but they are not prerequisites for trusting the current group send path.

---

## When To Reopen Group Reliability

Reopen this area only if one of these happens:

1. a current send surface bypasses the durable pre-persist contract or the shared interruption-safe sender entry contract,
2. ordinary media loses parent-row or publish-failure retry parity,
3. the settled `5 GB` ordinary-attachment budget regresses across live or
   hydrated group entry paths, or in-app voice recordings stop honoring the
   separate `100 MB` sanity cap,
4. active relay upload protection regresses in the group conversation surface
   (aggregate progress, leave guard, wake-lock lifetime, batch-bounded cancel,
   targeted failed-media retry/delete, or bounded owned-file cleanup), or the
   repo starts overclaiming true background upload behavior,
5. resume recovery stops restoring sender work safely, including exact-once closure of interrupted pending rows or the `retryFailedGroupInboxStores(...)` recovery step,
6. the one-thread send guard regresses,
7. voice publish-failure retry becomes a real escaped bug or clearly justified trust gap,
8. a direct regression or named gate proves an escaped bug in shared group send/retry/recovery behavior.

Do **not** reopen group reliability just because someone notices that group semantics are weaker than 1:1 in the abstract.

---

## Required Regression Contract

When touching shared group discussion reliability code:

1. add the direct regression first for the exact seam,
2. run the exact direct suite for the changed files,
3. run `./scripts/run_test_gates.sh groups`,
4. run `./scripts/run_test_gates.sh feed` when caller-surface parity, feed inline group reply, or share-to-group wiring changes,
5. run `./scripts/run_test_gates.sh baseline` when Flutter production code changes,
6. run `./scripts/run_test_gates.sh transport` when lifecycle, startup, resume, reconnect, or device-backed media recovery wiring changes, including exact-once pending-row closure and `retryFailedGroupInboxStores(...)` ordering,
7. run `./scripts/run_test_gates.sh 1to1` as well if shared 1:1 retry/transport infrastructure is touched.

For the cancelable-upload seams, direct proof should keep covering:

- batch-bounded cancel restoring the composer snapshot while terminalizing the
  same group row to `failed` plus attachment `upload_failed`
- targeted failed-media retry/delete on the same group row
- announcement admins inheriting the shared controls while read-only
  announcement members do not
- delete cleanup staying bounded to the targeted row and app-owned
  pending-upload files instead of unrelated stored source paths

Use `Test-Flight-Improv/test-gate-definitions.md` as the execution source of truth and `Test-Flight-Improv/14-regression-test-strategy.md` as the policy/rationale reference.

---

## Bottom Line

The current repo already supports **trustworthy group discussion messaging for text/media/voice** under the current architecture, with one narrow residual around voice publish-failure retry.

Future changes should preserve:

- durable local sender state,
- one interruption-safe text-send entry contract across the currently reachable group surfaces,
- inbox-backed recovery,
- resume-oriented repair,
- exact-once closure of interrupted pending rows,
- one-thread send determinism,
- honest receipt-less status semantics,
- the settled general-media size contract,
- and honest foreground-only upload protection plus batch-bounded failed-media
  recovery while relay uploads are active.

Anything beyond that should be treated as new product/protocol scope unless a real regression proves otherwise.
