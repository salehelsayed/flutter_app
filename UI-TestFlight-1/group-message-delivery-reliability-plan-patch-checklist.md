# Patch Checklist for `group-message-delivery-reliability-tdd-plan.md`

**Date:** 2026-03-24
**Source plan:** `UI-TestFlight-1/group-message-delivery-reliability-tdd-plan.md`
**Goal:** Make the draft sufficient to implement against the current repo, not perfect.

This is a patch checklist for the plan document, not a replacement plan. Keep the original structure, but patch the headings below so they match the current Flutter + Go codebase.

## Global patch rules

- Treat universal persist-before-publish as a prerequisite, not an assumption. Today only `GroupConversationWired` pre-persists a `'sending'` row; `FeedWired` does not.
- Preserve the current concurrent start of publish + inbox store unless a section explicitly says otherwise. The sufficient fix is a single concurrent inbox-store future, not a second sequential inbox call.
- Do not promise retry for media or voice unless the plan also persists durable retry inputs for those paths.
- Any proof that claims UI, lifecycle, background-task, or retry behavior must go through the real UI/lifecycle surfaces, not only the use case.
- Recompute the appendix and test counts after section edits. Several affected-file lists are incomplete.

## Section 0: Plan Overview

### Core Bug

- Patch bullet 2 to say group retry infra is missing, but also note the use case does not own optimistic persistence for all callers today.
- Patch bullet 4 to say `_safeInboxStore` is concurrently started and swallows failures. Do not imply the sufficient fix is a second inbox call after publish.
- Patch bullet 5 to say only `group_conversation_wired.dart` pre-persists a `'sending'` row. `feed_wired.dart` currently calls `sendGroupMessage()` without pre-persisting a group row.
- Patch bullet 6 and later media sections to note that voice has separate reliability gaps, not just the image/video loop.
- Add one bullet that open group surfaces currently listen to inbound events only; local retry/recovery DB mutations are not pushed back into the UI.

### Scope

- Add an explicit scope decision for early recovery phases:
  either `text-only until durable media retry payloads land`,
  or `Sections 4 and 5 are prerequisites for any failed-message retry coverage`.
- Add an explicit note that `PendingMessageRetrier` group retry is only in scope if the plan also defines topic-ready ordering or a safe precondition.

### Dependencies Between Sections

- Move `DB Schema Changes` and `Wire Envelope Persistence Design` into the dependency chain for Sections 1, 2, 4, 5, 6, and 11.
- Show that Section 4 and Section 8 must be patched together because inbox-store semantics and `topicPeers` now define one send contract.
- Show that Section 3 depends on the final send-path contract from Sections 4/5/6 because `bg:end` must happen after the full protected pipeline.

### Recommended Implementation Order

- Patch Phase 1 so it starts with schema plus send-flow persistence, not only retry/recovery.
- Put Section 4 and Section 8 in the same phase and note they should be patched together.
- Move Section 11 to the end of implementation but make it clear the harness changes should be built incrementally from existing fakes, not from scratch.

### Can Each Section Ship Independently?

- Change Section 1 from `Yes` to `Qualified` unless the section is amended to include use-case-owned persist-before-publish.
- Change Section 2 from `After Section 1` to `After Section 1 and after the plan chooses text-only vs media-capable recovery`.
- Change Section 5 from `After Section 1` to `After Section 1 plus durable pending-upload storage semantics`.
- Change Section 6 from `After Section 5` to `After Section 5 and after the voice path is explicitly covered by Section 3 if bg-task protection remains in scope`.
- Change Section 10 from `After Sections 1 + 7` to `After Sections 3, 7, and 8` as well, because the proofs depend on bg-task behavior and `successNoPeers` / `pending`.

### Key Differences from 1:1 Plan

- Add that groups currently have no use-case-owned outgoing-row persistence for all callers.
- Add that groups currently have no local outgoing-mutation stream comparable to what the UI would need for retry/recovery updates.
- Add that group retry must account for key-epoch drift and current-vs-pending key semantics if Section 7 delays Go activation.

### Estimated ~115 Tests Total

- Add a note to recalculate totals after patching scope. Current counts understate Section 10 and overstate some simplified unit tests that are not repo-accurate.

## Database Schema Changes

### New Migration: `041_group_message_reliability_columns.dart`

- Add an `inbox_retry_payload TEXT` column. It should persist the exact `group:inboxStore` request inputs needed for retry: message payload, `recipientPeerIds`, `pushTitle`, `pushBody`, and any other required request fields.
- Keep `wire_envelope TEXT` only if the plan clearly says it stores plaintext publish retry parameters, not an encrypted v3 envelope.
- Patch the migration narrative to include `main.dart` database-version wiring, because the current affected-file lists omit that dependency.
- Add a note that media retry also depends on durable attachment-path semantics, even if those paths live in attachment tables rather than `group_messages`.

### GroupMessage Model Changes

- Add `inboxRetryPayload` to the model if the migration adds `inbox_retry_payload`.
- Add a note in the model section that Section 8 introduces a `pending` status that must be treated as a first-class outgoing status in Dart and in UI rendering.
- If `wireEnvelope` stays as the field name, add a warning that it is publish retry input JSON, not the Go-produced encrypted wire envelope.

### New DB Helper Functions

- Add helpers for loading messages with failed inbox store using the new retry payload.
- Add helpers for updating and clearing `inbox_retry_payload`.
- Add batch-limit notes where the plan later assumes unbounded loads.

### DB Schema TDD Tests

- Add migration tests for `inbox_retry_payload`.
- Add model round-trip tests for `pending` status handling if the model docs mention it.
- Add idempotency and null/backward-compat tests for all new reliability columns.

## Section 1: Stuck-Sending Recovery for Group Messages

### 1.1 Problem Statement

- Patch the statement that groups need an "identical pipeline." The repo needs an analogous pipeline, but only after retryable rows exist for all production callers.
- Add that `FeedWired` does not currently create a retryable outgoing row before publish.
- Add that visible UI recovery is incomplete unless the plan also patches local outgoing status propagation to the screen.

### 1.2 Design

#### 1.2.1 New Repository Methods

- Add any repo/query surface the section assumes for later steps:
  `transitionSendingToFailed()`,
  `getFailedOutgoingMessages({limit})`,
  and any local change-stream contract if the plan wants UI-visible retry state.

#### 1.2.2 New Use Case: `recoverStuckSendingGroupMessages`

- Clarify that pause-time transition and age-based stuck recovery are separate concerns.
- If Section 2 keeps the immediate pause sweep, say this use case is for crash/kill/orphan recovery, not the only way group sends leave `'sending'`.

#### 1.2.3 New Use Case: `retryFailedGroupMessages`

- Patch the logic to state a prerequisite:
  either Section 4 persist-before-publish plus retry payload storage is already landed,
  or this use case is text-only and must skip media-bearing rows with a flow event.
- Do not promise in-place replacement with the original `messageId` unless the product behavior is explicitly changed to stable-id retry. Current widget retry behavior is "failed original row plus new retry row."
- Add an authorization guard note for announcement groups so retry/resume never bypasses admin-only send rules.

#### 1.2.4 Wiring into `handleAppResumed`

- Keep group retry inside the existing group-recovery gate.
- State that group recovery must happen after `rejoinGroupTopics` and after group inbox drain, not only after rejoin.
- Add ordering tests, not only "called once" tests.

#### 1.2.5 Wiring into `PendingMessageRetrier`

- Either add a topic-ready precondition for group retry here, or explicitly defer group retry out of `PendingMessageRetrier` for the first sufficient pass.
- Do not imply the existing reconnect retrier is already group-safe.

### 1.3 Affected Files

- Add `lib/features/groups/application/send_group_message_use_case.dart`.
- Add `lib/features/groups/presentation/screens/group_conversation_wired.dart`.
- Add `lib/features/feed/presentation/screens/feed_wired.dart`.
- Add any new local-mutation-stream file or repository change source if you keep the UI-propagation requirement.

### 1.4 TDD Tests

- Add a test that feed-inline send is recoverable after the plan's persist-before-publish patch.
- Add a test that media-bearing failed rows are either skipped with telemetry or retried correctly, depending on the scope decision.
- Add a widget test that a visible outgoing group row updates from retry/recovery without requiring a manual reload.

### 1.5 Acceptance Proof

- Do not rely only on FLOW logs. Add a visible UI proof for `sending -> failed/sent` updates in an open group screen.

## Section 2: Lifecycle Pause Handler for Groups

### 2.1 Problem Statement

- Add that the current pause handler returns early when there are no 1:1 sending messages, which can skip group-only work if the section is not patched carefully.

### 2.2 Design

#### Pause Handler Changes

- Explicitly handle the `group-only pending sends` case; do not let a 1:1 early return short-circuit group transitions.
- Add a note about `hidden` / `paused` double-fire semantics and the current lifecycle wiring in `main.dart`.
- Clarify that media-backed group rows are only safe to mark-and-retry if the plan already made them durable.

#### Resume Handler Changes

- Keep Steps 3d and 3e after `rejoinGroupTopics` and after inbox drain.
- Add a note that mounted group UI still needs a local mutation stream if the proof expects onscreen state to update.

### 2.3 Affected Files

- Add any repository or helper files created in Section 1 if this section depends on them.
- Add `lib/main.dart` explicitly for lifecycle-flag and callback wiring.

### 2.4 TDD Tests

- Add a group-only case where there are zero 1:1 sends and one group send, and assert the group row is still transitioned.
- Add a feature-flag and repeated-lifecycle-event test so the section documents intended semantics.

### 2.5 Acceptance Proof

- If media retry is not yet durable, do not promise that all failed paused sends are recoverable. Limit the proof to the supported scope.

## Section 3: iOS Background Task Protection for Group Sends

### 3.1 Problem Statement

- Expand the problem statement to include the voice send path. `_onRecordStop` is currently outside background-task protection too.
- Decide whether `FeedWired` group inline send is in scope here. If yes, say so explicitly. If not, state the exclusion.

### 3.2 Design

- Patch the design so `bg:end` happens after the entire protected pipeline, including inbox-store completion, not only publish.
- Add the voice path explicitly if the section is supposed to cover all group send surfaces.
- Note that current tests cannot stub `sendGroupMessage` directly from `GroupConversationWired`; they need a bridge/order-recording seam similar to the 1:1 bg-task tests.

### 3.3 Affected Files

- Add `lib/features/feed/presentation/screens/feed_wired.dart` if group inline send is included.
- Add any native logging file only if the plan insists on an Xcode-console `bg:end` acceptance proof. Otherwise, rewrite the proof to use bridge call ordering instead of a native log that does not exist today.

### 3.4 TDD Tests

- Replace the current simplified fake-bridge assumptions with an order-recording bridge that can prove:
  `bg:begin -> upload -> publish -> inbox store -> bg:end`.
- Add a voice-path test.
- Add a test for OS refusal that still verifies no `bg:end` is called without a task ID.

### 3.5 Acceptance Proof

- Do not require a native `bg:end` console log unless the section also patches the native layer to emit one.

## Section 4: Inbox Store as Required Fallback

### 4.1 Problem Statement

- Add that the retry path is underdefined unless the exact inbox-store request is durably persisted.

### 4.2 Design

#### Replace `_safeInboxStore` with `_tryInboxStore`

- Keep this change, but make it clear `_tryInboxStore` must not swallow the only in-flight failure signal if Section 8 escalates the same inbox-store future.

#### Updated Send Flow

- Replace any wording that suggests "publish first, then run a second required inbox store."
- Use this repo-aware contract instead:
  start exactly one inbox-store future once, before awaiting publish;
  do not issue a second `group:inboxStore` call;
  capture its completion/error without swallowing;
  if `topicPeers > 0`, keep inbox best-effort/log-only;
  if `topicPeers == 0`, await that same future and propagate failure;
  preserve concurrent start.

#### New Use Case: `retryFailedGroupInboxStores`

- Change the retry design so it rebuilds the inbox request from `inbox_retry_payload`, not by guessing from the message row.
- Add an explicit batch limit and telemetry requirement for rows missing retry payload.

#### Wire into Resume Handler

- Add a decision: also wire into `PendingMessageRetrier`, or explicitly defer reconnect-time inbox retry for the first sufficient pass.

### 4.3 Affected Files

- Add `lib/features/groups/domain/repositories/group_message_repository_impl.dart`.
- Add `test/shared/fakes/in_memory_group_message_repository.dart`.
- Add `lib/main.dart`.

### 4.4 TDD Tests

- Add a test that no duplicate inbox-store call happens in the `topicPeers == 0` path.
- Add a test that the first inbox-store failure is not lost when zero-peer escalation occurs.
- Add a retry test that uses persisted `inbox_retry_payload`, not reconstructed best guesses.

### 4.5 Acceptance Proof

- Replace "no silent swallowing" with a stronger statement:
  there is exactly one inbox-store attempt per send call, its result is preserved, and zero-peer escalation uses that same attempt.

## Section 5: Parallel Media Upload + Group Media Retry

### 5.1 Problem Statement

- Add that durable pending-upload storage and retry-time path resolution are missing from the current draft.
- Add that voice reuse of this machinery is a required dependency for Section 6.

### 5.2 Design

#### 5.A — Parallel Media Upload

- Keep fail-all semantics, but add that already-uploaded results should not be committed into final message state unless the overall send succeeds.

#### 5.A.1 — Parallel DB Reads

- Keep the parallel-read optimization.

#### 5.B — Pre-Upload Persistence

- Patch this subsection to require:
  copying inputs into durable `pending_uploads/...` storage before first upload,
  persisting relative `pending_uploads/...` paths in DB,
  preserving a stable `blobId`,
  and never leaving the original temp path in persisted state.

#### 5.C — New Use Case: `retryIncompleteGroupUploads()`

- Patch the retry contract to group attachments by `messageId`.
- Say it must preserve already-`done` attachments, re-upload only `upload_pending`, and call `sendGroupMessage()` once per message with the full attachment set.
- Say retry must resolve stored relative paths back to absolute paths and pass `mediaFileManager:` during re-upload.

#### 5.D — Wire into Resume Handler

- Add a decision for reconnect-time retry:
  either wire group incomplete-upload retry into both `handleAppResumed` and `PendingMessageRetrier`,
  or explicitly defer reconnect-time upload retry.

### 5.3 Affected Files

- Add any media helper/file-manager surface that the durable pending path design changes.
- Add repository impl/fake files if retry queries need new attachment lookups.

### 5.4 TDD Tests

- Add tests for durable `pending_uploads/...` storage and retry-time path resolution.
- Add a test that `done` attachments are preserved while only `upload_pending` attachments are retried.
- Add a cleanup-timing test proving the pending directory is deleted only after final send success.

## Section 6: Voice Message Reliability for Groups

### 6.1 Problem Statement

- Keep the dual-ID orphan point, but add that the voice path is also outside Section 3 background-task protection unless Section 3 is patched.

### 6.2 Design

- Patch the design to use the same durable pending-path semantics as Section 5.
- Explicitly say the persisted path in DB is the relative pending path, while immediate upload/playback may resolve it to an absolute path.
- Explicitly integrate voice with `retry_incomplete_group_uploads_use_case.dart`.

### 6.3 Affected Files

- Add any attachment repository/helper/file-manager files touched by the durable pending-path contract.

### 6.4 TDD Tests

- Replace "Only 1 saveAttachment call" with the repo-accurate expectation:
  one save for `upload_pending`, one save to overwrite the same row as `done` on success.
- Add a test that upload failure leaves the attachment row `upload_pending` with the same `blobId`, duration, waveform, and retry count.
- Add a test that the temp recorder path never survives in persisted state.

## Section 7: Key Rotation Safety Window

### 7.1 Problem Statement

- Keep the core race description, but add that the current rotate API already mutates Go state immediately, so the draft reordering is not implementable yet.

### 7.2 Design

#### Dual-Epoch Grace Period (Go)

- Patch the design so grace-period fallback applies to decryption in `handleGroupSubscription`, not only validator signature checks.
- Choose one canonical grace-state model. Do not keep both `PrevKey/PrevKeyEpoch/GraceDeadline` and a separate `groupKeyRotatedAt[groupId]` concept unless the plan says exactly how they coexist.
- Add precise `UpdateGroupKey` rules:
  on `incomingEpoch > currentEpoch`, shift current into previous and stamp grace timing;
  on `incomingEpoch <= currentEpoch`, no-op;
  initial join/create starts with no previous key.

#### Reorder Rotation (Dart)

- Replace the current step order with a two-step bridge contract:
  first a non-mutating "generate next key" call that returns `{groupKey, keyEpoch}`,
  then distribution,
  then `group:updateKey` for the admin after completion or timeout.
- Patch the Dart side to define active-vs-pending key semantics so `sendGroupMessage` does not stamp or publish with the wrong epoch while Go activation is delayed.
- Add explicit concurrency/timeout language for per-member distribution. The current sequential `for` loop means one hung recipient blocks later recipients.

#### Epoch Mismatch Event (Go)

- Either mark this event diagnostic-only for the first sufficient pass, or add Dart routing for it.
- If kept, add a note that `go_bridge_client.dart` currently drops it unless new handling is added.

### 7.3 Affected Files

- Add `go-mknoon/bridge/bridge.go`.
- Add `lib/core/bridge/bridge_group_helpers.dart`.
- Add `lib/features/groups/application/group_key_update_listener.dart`.
- Add `lib/features/groups/application/send_group_message_use_case.dart`.
- Add `lib/features/groups/domain/models/group_key_info.dart`.
- Add `lib/features/groups/domain/repositories/group_repository.dart`.
- Add `lib/core/bridge/go_bridge_client.dart` if `group:epoch_rejected` remains in scope.

### 7.4 TDD Tests

- Add a Go test proving an old-epoch envelope is both validated and decrypted successfully during grace.
- Add a Dart test proving one hung recipient does not block distribution attempts to others before timeout.
- If delayed Go activation is kept, add a Dart test for active-vs-pending key usage on send.

### 7.5 Acceptance Proof

- Replace "zero message loss during rotation" with a staged proof:
  accept old epoch during grace,
  accept new epoch after update,
  reject old epoch after grace,
  and prove the sender's first post-rotation message uses the promoted epoch.

## Section 8: 0-Peer Publish Detection and Compensation

### 8.1 Problem Statement

- Keep the problem statement.

### 8.2 Design

#### Go: Return Peer Count in Publish Response

- Keep the additive `topicPeers` response.
- Add one line that async `group:publish_debug` remains observability-only and must not drive correctness.

#### Dart: Conditional Inbox Store Escalation

- Replace the current "required inbox store after publish" wording with the single-concurrent-future contract from Section 4.
- Add `SendGroupMessageResult.successNoPeers` handling requirements for all current send callers.
- Add an explicit UI contract for outgoing `status: 'pending'`.

### 8.3 Affected Files

- Add `lib/features/groups/presentation/screens/group_conversation_wired.dart`.
- Add `lib/features/feed/presentation/screens/feed_wired.dart`.
- Add `lib/features/conversation/presentation/widgets/letter_card.dart`.
- Add `lib/features/groups/domain/models/group_message.dart`.
- Add `go-mknoon/cmd/testpeer/commands.go`.

### 8.4 TDD Tests

- Update the zero-peer tests so they expect `successNoPeers` plus `pending`, not `success` plus `sent`.
- Add widget coverage proving `pending` renders differently from `sent` and `failed`.
- Add tests for text send, voice send, and feed composer treating `successNoPeers` as success, not failure.

## Section 9: Member Config Sync Atomicity

### 9.1 Problem Statement

- Add that listener-side DB state may already be stale when an out-of-order or dropped config-bearing message arrives.

### 9.2 Design

#### Rollback-on-failure for use cases

- Patch this subsection to choose the bridge-sync ownership boundary for batch add-member flows.
- Either add a parameter like `syncBridgeConfig: true|false` to `addGroupMember`,
  or move add-member bridge sync responsibility entirely to higher-level batch callers.

#### Retry with full-state resync for listener

- Replace "read all members from DB, rebuild config, retry once" with a versioned snapshot contract:
  every config-changing system message must carry `membershipRevision` plus a full `groupConfig` snapshot;
  persist `lastAppliedMembershipRevision` per group;
  reconcile DB membership rows from the incoming snapshot under that revision;
  discard stale revisions;
  retry Go sync with that same desired snapshot;
  if a gap or second failure remains, mark the group config dirty and schedule authoritative recovery.

#### Sequential config update queue

- Patch the queue requirement so it serializes the entire config-mutation pipeline per group, not only `callGroupUpdateConfig`.
- Add an explicit terminal failure emission contract, not only "emit CONFIG_SYNC_FAILED" informally.

### 9.3 Affected Files

- Add model/persistence files needed for `membershipRevision` and dirty-config state.
- Add higher-level batch caller files if they own add-member bridge sync after the patch.
- Add any config-dirty recovery file if introduced.

### 9.4 TDD Tests

- Add coverage for `_handleMembersAdded`, not only single-member add/remove.
- Add a stale-revision and out-of-order delivery test.
- Add a test for terminal dirty-state emission when both sync attempts fail.

## Section 10: Announcement-Specific Acceptance Proofs

### 10.1 Why Needed

- Keep the rationale, but add that retry/resume and optimistic UI persistence are part of the auth surface too.

### 10.2 Acceptance Proofs (6 scenarios)

#### Proof 10-A: Admin Text + Lock Phone -> Delivered via Inbox

- Rewrite to say this must run through `GroupConversationWired` plus lifecycle helpers, not only the use case.
- Specify expected result for connectivity:
  `success` when `topicPeers > 0`,
  `successNoPeers` plus `pending` when `topicPeers == 0`.
- Require `bg:begin` before upload/publish and `bg:end` after completion if Section 3 remains in scope.

#### Proof 10-B: Admin Media + Lock Phone -> Delivered

- Add that the harness must carry real media metadata, `messageId`, and `keyGeneration` or else declare the proof widget/integration-only.

#### Proof 10-C: Admin Voice + Lock Phone -> Delivered

- Same patch as 10-B, plus tie the proof to the Section 6 voice durability contract.

#### Proof 10-D: Non-Admin Rejection (Dart AND Go)

- Expand into three proofs:
  UI proof on `GroupConversationWired` showing a read-only reader surface with no send affordances;
  retry/resume proof showing a reader's failed/sending row is not republished or inbox-stored;
  Go crafted-envelope rejection proof.

#### Proof 10-E: Reader Backgrounded -> Receives on Resume

- Patch this so the same reader/device gets the live pubsub copy and later drains the same `messageId` from inbox after resume, proving dedupe on one device.

#### Proof 10-F: Key Rotation -> Admin's Next Message Uses New Key

- Split into staged assertions:
  old epoch accepted during grace,
  old epoch rejected after grace with the epoch-specific rejection signal if kept,
  first post-rotation admin send persists the new epoch and is decryptable after Go update.

## Section 11: Test Infrastructure

### 11.1 Current Assessment

- Keep the "solid foundation" wording, but add that existing infrastructure already contains reusable pieces:
  `_SlowPublishBridge`,
  `_InboxStoreFailBridge`,
  `_CursorInboxBridge`,
  and the lifecycle helper / `LifecycleBridge` pattern.

### 11.2 Required Extensions

#### FakeGroupPubSubNetwork

- Remove `inboxStoreFails` from this subsection. Inbox store is a bridge concern, not a fake-pubsub-network concern.
- Keep zero-peer and partial-delivery concepts only if they model live pubsub, not relay inbox behavior.

#### FakeBridge Extensions

- Add that bridge fakes must cover `bg:begin` / `bg:end` grant, refusal, delay, and ordering if Section 3 remains in scope.
- Reuse and generalize the existing inbox-store-failing and slow-publish bridges instead of inventing unrelated fakes.

#### GroupTestUser Extensions

- Add a bridge-backed group send path that actually calls `sendGroupMessage(...)`. Several Section 11 scenarios currently cannot hit the real reliability logic without this.
- If lifecycle coverage stays in scope, tie pause/resume to the existing lifecycle helper pattern rather than an internal `_isPaused` flag alone.

#### InMemoryGroupMessageRepository Extension

- Add any convenience query needed for retry state, but note that widget-level optimistic status changes still do not exist in the application use case by default.

### 11.3 New Test Helpers

#### `GroupReliabilityTestHarness`

- Add APIs for inbox-page seeding and per-command counts:
  `seedInboxPage(peerId, groupId, cursor, messages, nextCursor)`,
  `commandCount(peerId, cmd)`.
- Add a bridge-backed send helper, not only direct fake-pubsub fan-out.

#### `MessageStatusTracker`

- Patch the expected retry sequence to match actual product behavior unless the plan explicitly changes it.
- Today the safe expectation is `failed original row + new retry row`, not `['sending', 'failed', 'sending', 'sent']` on one message ID.

### 11.4 Integration Test Scenarios

- Rewrite scenarios 1, 2, 3, and 6 so they use the bridge-backed send path.
- Rewrite scenario 6 to match the chosen retry identity model.
- Add lifecycle-helper integration where the scenario claims pause/resume/bg-task behavior.

## Go-Side Changes

### 10.1 Peer Count in Publish Response (supports Section 8)

- Add `go-mknoon/cmd/testpeer/commands.go` to the plan text and appendix so direct callers are updated for the new return shape.
- Keep `GroupPublishReaction` additive changes only if there is a consumer; otherwise mark them optional for the first sufficient pass.

### 10.2 Key Rotation Grace Period (supports Section 7)

- Unify this appendix with Section 7's final grace-state model. Do not keep a second timestamp-only model if Section 7 uses previous-key fields.
- Add that decryption fallback must exist alongside validator fallback.

### 10.3 Decryption Failure Event Emission (new)

- Keep this as observability-only unless the plan also adds Dart consumers.
- Distinguish it from `group:epoch_rejected` so the document does not imply a synchronous send-time guarantee.

### 10.4 Validator Pre-Check for Own Messages (new)

- Either scope this out of the first sufficient pass, or explicitly tie it to the shared validation logic from Section 7 so it does not drift from the runtime validator.

### Go Implementation Order

- Patch the order if 10.4 is deferred. A sufficient first pass can be:
  peer count,
  decryption events,
  grace-period machinery,
  optional pre-check later.

### Bridge API Summary

- Add the new or clarified contracts:
  `topicPeers`,
  any diagnostic-only events,
  and the final rotate/generate-next-key response shape if Section 7 adopts a non-mutating generation step.

## Wire Envelope Persistence Design

### Problem

- Add that inbox retry needs a second persisted payload; publish retry input alone is not enough.

### Recommendation: Option B (Persist Plaintext Parameters)

- Keep Option B, but patch it so the document explicitly says:
  publish retry input lives in `wire_envelope` or a renamed publish-retry field,
  inbox retry input lives separately in `inbox_retry_payload`,
  and neither implies cached encrypted envelope replay.

### `retryPayload` Design

- Add the exact fields needed for media retry if the plan keeps media in scope.
- Add a second JSON design for `inbox_retry_payload`.

### Lifecycle

- Add `status: 'pending'` for the zero-peer plus inbox-success case.
- Clarify when `wire_envelope` and `inbox_retry_payload` are cleared vs retained.

### Send Flow Change

- Patch the send flow so the use case owns pre-persist for all production callers.
- Add `FeedWired` to the discussion because it currently bypasses optimistic row creation.
- Keep concurrent start of publish and inbox store, but make it the single-future model from Sections 4 and 8.

## Appendix A: Affected Files Summary

- Recompute the appendix after all patches. It currently misses at least:
  `lib/features/feed/presentation/screens/feed_wired.dart`
  `lib/features/conversation/presentation/widgets/letter_card.dart`
  `lib/core/bridge/bridge_group_helpers.dart`
  `lib/core/bridge/go_bridge_client.dart` if epoch events remain
  `go-mknoon/cmd/testpeer/commands.go`
  `lib/features/groups/application/group_key_update_listener.dart`
  `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
  `test/shared/fakes/in_memory_group_message_repository.dart`
  any new local-mutation-stream or config-revision persistence files

## Minimum sufficiency bar before implementation starts

- The patched plan must clearly choose text-only vs full media retry scope for early recovery sections.
- The patched plan must define one coherent send contract covering:
  pre-persist,
  exactly one concurrent inbox-store future,
  `topicPeers`,
  `successNoPeers`,
  `pending`,
  and retry payload persistence.
- The patched plan must define one coherent retry identity model:
  stable-id retry-in-place,
  or failed original row plus new retry row.
- The patched plan must define one coherent key-rotation activation model:
  immediate Go mutation,
  or generate-next-key then delayed activation.
- The patched plan must update the test infrastructure to hit the real bridge-backed send path for reliability scenarios.
