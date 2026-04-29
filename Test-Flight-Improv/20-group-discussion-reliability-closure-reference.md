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
- `test/features/groups/integration/group_media_fanout_test.dart` now proves
  existing discussion members receive image, video, and voice messages through
  the bridge-backed group send path with descriptors intact. This is
  fake-network/app-layer media evidence; live GossipSub/simulator media
  delivery remains owned by later Report 85 sessions.
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

There is still one narrow residual worth remembering:

- voice publish-failure retry is weaker than ordinary-media retry because the producer-side completed-attachment seam is still narrower in the current tree

This is **not** a reason to reopen the whole group reliability program. It is the one specific residual to reopen only if it becomes a real escaped bug or clearly justified trust gap.

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
