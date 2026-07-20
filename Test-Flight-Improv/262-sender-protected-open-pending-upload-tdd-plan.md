# 262 - Sender One-More-Look Independent Of Relay Upload Finalization  (Bug + Modification)

Status: reviewed-ready (v4 — 2026-07-20 `$tdd-review`; source-grounded counterexamples were
applied for shared runtime/lock ownership, pre-prep persistence, terminal deletion, durable outbox
custody, commit-boundary/idempotency, causal RED waves, and the real device exit path.)
Type: bug + modification
Closure tier: PROD-CRITICAL device proof when a policy-eligible target pair is available
Boundary triggers: on-device Android controller/viewer + SQLCipher persistence; no relay,
bridge, native-handler, or wire-format production change
Spec: free-text intent (no formal spec) — user-selected product decision from the 2026-07-19
debug session: "the sender's one-more-look shouldn't depend on the relay upload at all — the
plaintext durable copy exists locally. Teach the outgoing lane of `_verifiedOpenableLocalPath`
to also accept the pending-upload canonical path for `upload_pending` outgoing rows."
Grounding: verify→refute workflow `wf_319c8f2a-c19` (2 ground + 6 verify + up-to-6 refute agents;
C2 and C6 survived as stated, C1's field conclusion REFUTED, C3/C4/C5 corrected — see Root Cause).

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-19 | Evidence Collector (debug session + wf_319c8f2a-c19) | conversation_screen.dart, conversation_wired.dart, direct_private_media_viewer_controller.dart, direct_private_media_lifecycle.dart, private_media_lifecycle_engine.dart, messages_db_helpers.dart, upload_media_use_case.dart, retry_incomplete_uploads_use_case.dart, private_media_action_eligibility.dart, + full test inventory | Two-leg root cause confirmed (finalize path-shape defect + pending-shape authority rejection); C6 race latent-on-HEAD, opened by this fix | Planner |
| 2026-07-19 | Planner | tier-matrix, gate scripts, device journey harness | Plan emitted (this file) | Reviewer |
| 2026-07-19 | Reviewer (sufficiency) | plan + current source + gates + device harness | `not-ready`; E6 convergence, bypass inventory, custody, causal device proof, tests, repair, and gates required revision | Revise plan |
| 2026-07-20 | Revision | current source, exact callers, live device matrix, gate scripts | v3 deltas applied; no implementation and no review rerun | Rerun `$tdd-review` in a later turn |
| 2026-07-20 | Reviewer 2 (`$tdd-review`) | plan v3 + current composition/writers/cleanup/retrier/harness/gates + three independent counterexample passes | `plan-fixes-required`; v4 applies only verified execution-safety and causality deltas | Execute v4 RED-first |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (git status --short) | | | scope confirmed | |
| | RED tests added | | (cmd proving they FAIL) | RED for expected reason | |
| | implementation | | | scoped files only | |
| | direct GREEN | | (exact cmd) | reds now green | |
| | preservation GREEN | | (exact cmd) | sentinels green | |
| | named gates | | (exact cmd + selected paths + exit) | gate green | |
| | QA (independent) | | (re-run cmds) | blocking: none/list | verdict |

## Source Of Truth
- Spec / intent: inline above (free-text product decision)
- Gate definitions: scripts/run_test_gates.sh + scripts/run_host_test_gates.sh (script wins over prose)
- Discovery/registration: scripts/check_reliability_simulation_discovery.sh
- Numbering / index: Test-Flight-Improv/00-INDEX.md

## Session Classification
implementation-ready (reviewed; execute RED-first under the literal wave contract)

## Exact Problem Statement
User-a sends a "protected view" photo to user-b. User-b receives it (LAN leg or relay) and opens
it fine. On user-a's phone, tapping "Open private media" shows "Couldn't open this photo" with the
generic body and no Try Again — persistently, including after a fully successful relay upload.
The sender's one-more-look (plan 260 S4 lane) is effectively dead in the field for real sends.

What must improve:
1. The sender's one-more-look must be grantable from the local plaintext durable copy without
   depending on relay upload finalization (`upload_pending` rows open from the pending-upload copy).
2. The finalized ("done") sender row must actually carry the canonical relative path in the REAL
   pipeline (today a fallback persists a dangling absolute `pending_uploads/` path).
3. The sender bubble must show the one-more-look affordance during the pending window and after
   restart, and show truthful failure copy when bytes are genuinely gone.

What must stay unchanged (→ preserved-green sentinels):
- Incoming lanes: incoming View-Once still requires done+canonical for its lease; incoming
  protected/disappearing still open lease-free from canonical done rows.
- Zero egress widening: save/share/forward/export/PiP remain denied for private rows.
- Exact-identity CAS contract (Session-03): no path/status wildcards in lease CAS.
- Pending-copy custody rule: source survives until a durable copy exists.
- Queued-lane sweep exclusions (260 S3): `upload_pending` is never reaped to failed.

## Root Cause (verify → refute confirmed)
Two independent legs produce the reported symptom (workflow `wf_319c8f2a-c19`):

**Leg A — finalize persists a dangling non-canonical path (persistent, post-success).**
`conversation_wired.dart` uploads FROM the pending durable copy with `deleteSourceWhenDone: true`
(:3287). Real `uploadMedia` copies it to the canonical owned path and then unlinks the pending
source — the skip condition `durableCopyAbsolutePath != localFilePath`
(upload_media_use_case.dart:754) always fires because canonical ≠ pending; the call-site comment
(conversation_wired.dart:3283-3286) claiming the unlink is skipped is stale/wrong. Unlink is
pinned by `upload_media_use_case_test.dart` ("transient source file deleted after durable copy
and successful upload when deleteSourceWhenDone", :721-744). By the time
`_finalizeUploadedAttachmentFromPlan` runs, the pending file is gone, so
`_buildLocalSuccessAttachmentFromPlan` takes its missing-source fallback (:688-695) and persists
`local_path` = ABSOLUTE dangling `pending_uploads/…` path with `download_status='done'`,
discarding the canonical relative path `uploadMedia` returned. The adapter's convention check
(`direct_private_media_lifecycle.dart:132-143`) rejects that stored shape → prepare fails
`localAuthorityMissing` forever; no repair path exists for 'done' rows. The Open button still
renders because the UI's `resolveExistingMediaPathForDisplay`
(lib/shared/widgets/media/media_display_helpers.dart:19-38) falls back to the canonical file by
attachment identity — enabled button + always-failing tap = the field report. Every wired test
stubs `uploadMediaFn` without deleting the source, which is why the suite never sees this.

**Leg B — the whole authority chain rejects the `upload_pending` shape (pending window).**
For an outgoing protected row with `download_status='upload_pending'` at
`pending_uploads/<msg>/<blob>.jpg`, prepare fails `localAuthorityMissing` with `canRetry=false`
(repro test, second case). Three INDEPENDENT gates reject it: (a) adapter mapping
`isDownloadComplete = downloadStatus=='done'` (direct_private_media_lifecycle.dart:90-91) plus
`_verifiedOpenableLocalPath` status gate (:121) and canonical-path convention (:132-143);
(b) the SQL lease-identity predicate `download_status = 'done'` inside EXISTS
(lib/core/database/helpers/messages_db_helpers.dart:1105) consumed by claim/markViewing/rollback/
consumeExact CAS, plus a SEPARATE inline copy in the quarantine CAS (:1245); (c) controller
`_requalifyRetry` raw-row status checks (direct_private_media_viewer_controller.dart:794/:799).
Engine `openOneShot` (:254-259/:269-278) and `_openableTargetPath` (:885-889) are DERIVATIVE —
they consume the adapter booleans and pass automatically once (a) is fixed; do NOT edit them.
During this window the sender bubble shows NO button at all (not a failing one): the in-memory
optimistic/displayMedia stamps carry `ownerLane == null`, and eligibility hard-denies
`openInApp` on `wrongOwner` (private_media_action_eligibility.dart:210-211); after failure
settlement every path rehydrates from DB and `localMediaAvailable` requires 'done'
(conversation_screen.dart:1013).

**Leg C — race OPENED by this fix (C6, survived refute).** A lease whose `storedLocalPath` is a
pending path is unreachable on HEAD, but becomes reachable the moment Leg B lands. Then: the
background retrier (status-only selection, retry_incomplete_uploads_use_case.dart:107-108/:215;
pre-save guard checks only downloadStatus :309-342) rewrites the row to canonical+done via plain
`saveAttachment` (:382) mid-lease → `_matchesLease` path equality breaks (engine :607-608),
markViewing/rollback CAS match 0 rows (SQL :1105-1106), the message strands at
`private_media_state='opening'` (the fail-closed corrector is incoming-only,
messages_db_helpers.dart:1389), and `deletePendingUploadDir` (:517-521) deletes the file being
rendered. The incoming guarded save cannot be reused: its predicate requires `is_incoming=1`
AND state 'available' (:1344/:1348). NOTE: the PLAIN consume CAS with null identity args skips
the EXISTS entirely (:1269→1082-1084), so crash-recovery reconcile (engine :459-461) can already
terminalize a stranded outgoing 'opening' row — recovery is a guard row, not a fix site.

Refuted / do-NOT-re-introduce:
- REFUTED (C1): "sender open works once the relay upload finalizes" — false in the field; the
  repro's canonical+done state is synthetic (real finalize persists the Leg-A dangling path).
  Do not close this plan on the canonical-state test alone.
- REFUTED (C3 original): "Open button is enabled from in-memory optimistic 'done' stamps" —
  wrong; `ownerLane == null` → `wrongOwner` denies it. The field's enabled-button shape comes
  from Leg-A 'done' rows + display-helper canonical fallback. Do not "fix" the button by
  trusting lane-less in-memory attachments.
- REFUTED (debug session): encrypted-vs-plaintext size mismatch; `toConversationMessage`
  clobbering private state; missing native protection handlers — all investigated, all wrong.
- CORRECTED (C4): engine `openOneShot` / `_openableTargetPath` are NOT fix sites (derivative).
- CORRECTED (C5): "pending copy exists exactly while upload_pending" is false on the success
  lane — the unlink lands while the row is still `upload_pending`; the fix must fail closed on
  missing pending bytes (transient window until Leg-A finalize commits canonical+done).

## Real Scope
In scope:
- E1 (Leg A): `_finalizeUploadedAttachmentFromPlan` treats the successful upload result as the
  source of truth and persists its canonical RELATIVE `localPath`, complete encryption metadata,
  and `done` status; `_buildLocalSuccessAttachmentFromPlan` must never synthesize an absolute
  pending path after the source disappears (conversation_wired.dart:669-739). Durable preparation
  already requires both repository and `MediaFileManager` (:624-630, :3153-3162), so the
  unreachable `mediaFileManager == null` fallback is not a causal obligation; delete it or make it
  fail closed rather than persisting an absolute path. Delete the stale :3283-3286 comment.
- E2 (Leg B, adapter/path authority): `direct_private_media_lifecycle.dart` maps outgoing
  protected/View-Once `upload_pending` as locally complete for one-more-look only.
  `_verifiedOpenableLocalPath` accepts either the canonical convention or the EXACT stored
  relative path returned by
  `MediaFilePathConvention.relativePathForPendingUpload(messageId, attachmentId, mime)`.
  Add `MediaFileManager.trustedPendingUploadRootPath()` constructed independently from the app
  documents directory, analogous to `trustedMediaRootPath()` (:176-185); never derive authority
  from `resolveStoredPath`, the stored row, or `dirname(dirname(candidate))`. Resolve the expected
  convention path beneath that trusted root, authorize every component without following
  symlinks, and require safe identifiers, an existing regular file, and exact recorded size.
  Return a typed probe outcome so only an exact otherwise-authorized expected path with a missing
  leaf becomes `senderLocalBytesMissing`; wrong convention/root/identity/symlink/type/size remains
  generic `localAuthorityMissing` and must not be mislabeled to the user.
- E3 (Leg B, SQL): shared predicate `_directPrivateMediaLeaseIdentityPredicate`
  (messages_db_helpers.dart:1099-1107) direction-aware status set: outgoing
  `IN ('done','upload_pending')`, incoming stays `= 'done'`; same for the inline quarantine
  EXISTS (:1241-1246). Exact `local_path = ?` equality is retained everywhere.
- E4 (Leg B, controller): `_requalifyRetry` treats the outgoing `upload_pending` shape like the
  done shape for post-rollback retry (direct_private_media_viewer_controller.dart:794-807).
- E5 (Leg B, UI): `conversation_screen.dart:1013` accepts outgoing `upload_pending` as a candidate
  for the Open action. Before durable preparation, lane-less optimistic attachments remain
  ineligible. The persisted boundary must match: for a private send, do not let
  `_persistOptimisticAttachments` write the picker/source-path row before durable preparation
  (`conversation_wired.dart:3120-3125/:5261-5281` currently stamps it direct in the repository).
  Persist the parent and keep the optimistic attachment in memory only; the first persisted private
  attachment is the convention-relative `upload_pending` row written after the pending copy exists.
  After `_prepareDurableMediaUploads` commits that row/copy, display the exact message-owned
  attachment stamped `ownerLane: direct`; do NOT rewrite the display-only object to absolute-path +
  `done` as current :3164-3170 does. The failure launcher passes `localMediaMissing` only for the
  typed `senderLocalBytesMissing` outcome, so genuinely missing bytes use
  `private_media_sender_local_missing_body` and unrelated failures retain generic copy.
- E6 (Leg C mutation authority — replaces bounded writer retries and v2's file-only repair): add
  a bounded `OutgoingDirectPrivateMutationCoordinator` plus repository/DB outcomes
  `committed | deferredActiveLease | transportOnlyTerminalCustody | refused`. Own exactly ONE
  coordinator per app database/repository runtime—not per adapter, controller, or caller, and not
  as an unscoped process-global.
  Expose it through an outgoing-private repository capability shared by the startup lifecycle,
  every `ConversationWired` lifecycle, private deletion cleanup, and foreground/background/manual/
  send-result writers. Completion qualification, DB commit or token publication, and token removal
  are linearized under that repository's exact `MediaAttachmentLifecycleLock`; never release the
  lock between observing `opening|viewing` and publishing the token. Every DB mutation requalifies,
  in the SAME transaction as the write, an exact direct attachment and a visible, terminal-null
  parent with `is_incoming=0`, policy version 1, mode `protected|view_once`. A first upload-success
  commit additionally requires the exact existing row to remain `upload_pending` at the expected
  convention-relative pending path. An already-canonical `done` row accepts only an identical full
  completion as idempotent, compared with an explicit persisted-field fingerprint (identity,
  canonical path, status, MIME/size, hashes, key, nonce, and scheme)—never `MediaAttachment.==`,
  which compares only `id`; stale/conflicting results refuse. An exact replay returns `committed`
  without a second secure-key write. While `available`, commit the COMPLETE
  uploaded attachment (canonical relative path, `done`, new hash/key/nonce/scheme). While
  `opening|viewing`, record one token-owned process-local deferred completion keyed by exact
  message/attachment/pending-path identity and mutate neither row nor secure key. Capacity is one
  slot per live exact attachment lease, with no timeout, eviction, or retry loop; settlement/cleanup
  owns removal. Missing/hidden/deleted/wrong-policy/wrong-identity parents refuse. A `consumed`
  parent is a permanent local-mutation no-op, but while its transport status is still
  `sending|failed`, its exact pending outbox attachment set remains, and `wire_envelope IS NULL`,
  upload success may return `transportOnlyTerminalCustody`: it writes no attachment/key/token and
  authorizes only the E8 envelope-handoff path. Other terminal shapes refuse; identical duplicate
  completions are idempotent and conflicting key/nonce/hash completions fail
  closed. Secure-key commits reuse `_withCompensatedEncryptionKeyWrite` (:400-415).
  Non-completion mutations (failure projection, cancellation, rearm, row/bulk deletion) apply
  only under the same positive `available` authority. An active-lease result is explicit
  `notAppliedActiveLease`, not reported as a successful cancellation/failure transition; terminal
  results are permanent local-mutation no-ops (E8's typed transport-only custody is not a mutation).
  Route every reachable writer: foreground finalize/failure/cancel,
  incomplete-retrier finalize/fallback/deletion, manual-retry rearm/success/failure/pending-dir
  deletion, `_persistOutgoingMedia` saves plus stale-set bulk deletion, message
  `updateWireEnvelope`, `_saveOutgoingMessageWithMedia`/send-result status writes, and classify
  `dbMarkUploadPendingAttachmentsFailedForMessage` plus failed-media deletion as guarded or prove
  them unreachable for an active private lease. Also classify the real destructive parents:
  private Delete-for-Me stays on terminal lifecycle cleanup; private Delete-for-Everyone must use
  terminal lifecycle cleanup after its durable tombstone rather than generic attachment cleanup;
  contact deletion must either terminalize/clean each private parent or fail the whole operation
  before its first file/row/contact side effect when a live private lease prevents that. Terminal-
  authorized lifecycle cleanup discards the token and is distinct from available-only transport
  failure/cancel/stale-row deletion. Pass authoritative parent policy explicitly; encryption
  metadata is not a private-parent discriminator and private callers fail closed when the
  capability is absent. Ordinary-media save/delete behavior remains generic.
- E7 (settlement-owned completion + legacy repair): extend the direct-private adapter/repository
  rollback seam, not the shared engine. `PrivateMediaLifecycleEngine` already calls
  `DirectPrivateMediaLifecycle.rollbackOpening` while holding the exact attachment lock. When an
  exact outgoing pre-frame lease has a matching deferred completion, authorize the canonical
  file/convention/size while that lock excludes every app-owned cleanup/relocation, then replace
  ordinary rollback with ONE cross-table DB transaction that (1) exact-CASes parent
  `opening -> available`, (2) rechecks the pending DB row identity, and (3) writes the complete
  uploaded canonical+`done` row. Write the new secure key immediately before that transaction with
  compensation on false/throw. The compensated callback contains ONLY the cross-table
  `dbWriteTransaction`: once that transaction returns committed, repository refresh and
  authorization/event publication run outside compensation, and a post-commit notification error
  cannot restore the old key or downgrade the committed outcome. A crash before commit leaves
  durable `opening`, which startup reconciliation terminalizes; a commit leaves parent and complete
  attachment finalized—there is no `available`+lost-key gap and no writer retry loop. Terminal settlement/cleanup discards the
  deferred token before custody-qualified deletion of row/key/files; late local callbacks remain
  refused. If upload success arrives after rollback, its positive-`available` path commits directly.
  A combined-transaction false/throw produces the engine's fail-closed lost-race disposition;
  after the engine releases
  its lock, a shared controller settlement-result helper immediately schedules lifecycle
  reconciliation to terminalize and perform E8 custody-qualified cleanup of the still-`opening`
  row. Both published-grant `_settleGrant` and prepare-time `_settleUnpublishedLease` must use that
  helper; startup reconciliation is the crash fallback, not the only owner.
  Qualification-time legacy repair is deliberately narrower: for already-deployed outgoing
  protected/View-Once rows that are `done` at a noncanonical/dangling pending path, exact
  canonical file authority may CAS only `local_path` to the canonical relative path while
  preserving every other row/key/bookmark/playback field. A bare `upload_pending` row plus
  canonical bytes is NEVER enough to fabricate `done`; the complete deferred upload result is
  required.
- E8 (upload/cleanup + durable outbox custody): foreground, incomplete-retry, and manual-retry
  private upload lanes claim `directPrivateMediaTransferRegistry` under the attachment lifecycle
  lock before the first plaintext read, then RELEASE the lifecycle lock before any file/crypto/
  network I/O; only the
  registry token spans the transfer. Retain that token through upload, durable-copy creation,
  completion registration/commit, and durable message/envelope transport handoff. A completion
  that is `deferredActiveLease` or `transportOnlyTerminalCustody` locally must still be carried as
  the complete in-memory upload result through envelope persistence; do not make transport custody
  wait for the attachment row to become canonical `done`. Use the existing durable contract, not a
  new schema marker: while claiming transfer custody under the lifecycle lock, clear any old
  `wire_envelope` through an exact, private-state-preserving column update before a private
  re-upload that rotates media keys; abort the upload if that invalidation fails. Build the new
  envelope from committed results plus exact coordinator-owned deferred or transport-only
  fingerprints, and treat only the successful non-null `wire_envelope` write as durable custody for
  that attempt. Envelope/final transport-status persistence must use column updates or a fresh
  reread/merge that cannot overwrite `opening|viewing|consumed`, hidden/deleted/tombstone, or the
  exact attachment set; the transport-only path never calls a generic parent/attachment full-save.
  Update `_lateSendAbortReason`/attachment assembly so an exact owned deferred result
  satisfies completion without weakening attachment-set identity; a raw pending row does not. For
  prepared outgoing protected/View-Once foreground uploads pass `deleteSourceWhenDone: false`;
  ordinary uploads retain today's unlink behavior. Pending-source and directory deletion becomes
  lifecycle-owned after committed promotion or custody-qualified terminal cleanup, with
  requalification and deletion under the same lock. Release the transfer token in `finally`, then
  explicitly invoke exact lifecycle cleanup for either
  (a) an available+committed promotion whose pending source can now be removed or (b) a terminal/
  hidden parent whose full cleanup was deferred. Release alone does not retry either cleanup.
  Registry acquisition failure is fail-closed. Process-local registry/token state is not durable:
  startup may terminalize an interrupted viewer lease, but automatic cleanup of an outgoing
  `consumed` parent must retain the exact outbox attachment/pending source until the attempt's
  non-null `wire_envelope` is observable. A restart before that boundary retries from the
  retained pending row/file; after the boundary it may clean. Explicit user hidden/deleted/
  tombstoned intent remains terminal-authorized and may clean immediately. This custody predicate
  is lifecycle-owned and must not re-enable Open on the terminal parent. Retention is minimal:
  after transfer release it may remove an uncommitted canonical/key residue, but not the exact
  pending row/source needed to retry; canonical bytes alone never authorize promotion. After the
  rebuilt envelope is durable and local media is cleaned, the existing failed/unacked retry lanes
  must replay that exact envelope without rebuilding media or requiring the deleted attachment.
- E9 (proof-only boundary): extend the existing device-local journey with a physical-sender p262
  slice and bump `directPrivateMediaDeviceLocalJourneyVersion` from 2 to 3. The p262 fixture uses a
  valid decodable PNG and the real `MediaFileManager.copyToDurableStorage` application-documents
  pending root. Seed the outgoing row through a fixture-only direct SQL/preserving-save path—not
  the current incoming-only `dbSaveDirectPrivateMediaAttachmentGuarded`—then assert its exact SQL
  path/status/size before the tap and seed only the repository mirror. The automation must prove a
  first frame, tap the real viewer Back control, await the conversation route, and only then assert
  SQL `consumed` plus cleanup. Update exact-key, v1+v2 legacy-version, and v4 future-version
  evaluator fixtures; no production protocol version changes.
Out of scope (owning session named):
- Group / announcement private-media lanes (238 / 242 own their one-more-look parity).
- Offline media outbox presentation/queued-lane behavior (260 S3 owns; already landed).
- Any relay/bridge/native change; any new `download_status` vocabulary.
- View-once INCOMING contract and protection coordinator semantics (234 S3/S5 own).

## Files To Inspect Next
Production: lib/main.dart (startup lifecycle composition),
lib/features/conversation/presentation/screens/conversation_wired.dart (:618-739,
:3040-3420, :2536-2599), lib/features/conversation/presentation/screens/conversation_screen.dart
(:988-1037, :1601-1663), lib/features/conversation/application/direct_private_media_lifecycle.dart,
lib/features/conversation/application/direct_private_media_viewer_controller.dart,
lib/core/database/helpers/messages_db_helpers.dart (:1070-1300),
lib/core/database/helpers/media_attachments_db_helpers.dart (guarded save + preservation policy),
lib/features/conversation/application/retry_incomplete_uploads_use_case.dart,
lib/features/conversation/application/retry_failed_messages_use_case.dart,
lib/features/conversation/application/retry_unacked_messages_use_case.dart,
lib/features/conversation/application/send_chat_message_use_case.dart (:2115-2205),
lib/features/conversation/application/delete_message_use_case.dart,
lib/features/contacts/application/delete_contact_use_case.dart,
lib/features/conversation/domain/repositories/media_attachment_repository.dart +
media_attachment_repository_impl.dart, lib/core/media/direct_private_media_transfer_registry.dart,
lib/core/media/media_upload_in_flight_tracker.dart, lib/core/media/media_file_manager.dart,
lib/core/media/media_file_path_convention.dart, lib/core/media/direct_private_media_path_guard.dart.
Direct tests + integration tests: see Existing Tests + RED Catalog below.
Dependency-only context: lib/core/media/private_media_lifecycle_engine.dart (derivative gates —
read, do not edit), lib/shared/widgets/media/media_display_helpers.dart.
Proof-only: integration_test/direct_private_media_device_local_journey_harness.dart,
integration_test/scripts/direct_private_media_device_local_journey_criteria.dart,
integration_test/scripts/run_direct_private_media_device_local_journey.dart, and the criteria host
test. Include production-composition and fixture tests that prove startup, `ConversationWired`, and
private deletion resolve the same repository-scoped coordinator/lock. Gate-only:
scripts/run_test_gates.sh, scripts/run_host_test_gates.sh, and
scripts/check_reliability_simulation_discovery.sh.

## Existing Tests Covering This Area
- test/features/conversation/application/sender_protected_open_repro_test.dart — THE repro
  (uncommitted, added during the debug session). Test 1: canonical done state grants. Test 2:
  pending shape fails `localAuthorityMissing`, canRetry=false (asserts the BUG — flipped by this
  plan). Auto-glob only; in NO curated array.
- direct_private_media_viewer_test.dart (26) — controller prepare/settle/retry, sender widgets.
  1to1-curated + 1to1-host.
- private_media_lifecycle_cas_test.dart (5) — direction-aware CAS lease lane. core-host auto
  only; NOT in 1to1 arrays (gap).
- messages_db_helpers_private_media_lifecycle_test.dart (14) — SQL lane. 1to1-curated + host.
- private_media_cleanup_race_test.dart (15) — terminal cleanup incl. pending family. 1to1.
- consume_private_media_use_case_test.dart (13) — View-Once engine lane. 1to1.
- private_media_restart_replay_test.dart (2) — restart/recovery, incoming-only (gap: no
  outgoing restart case). 1to1.
- retry_incomplete_uploads_use_case_test.dart (~37) — retrier lanes (no private-state awareness).
- upload_media_use_case_test.dart — pins the deleteSourceWhenDone unlink + source custody.
- media_outbox_queued_lane_test.dart (2) — upload_pending never swept (260 S3 landmine guard).
- private_media_action_eligibility_test.dart (8) + direct_private_media_boundary_test.dart (8)
  — egress-denial sentinels.
- direct_private_media_device_local_journey_criteria_test.dart + harness — device journey with
  outgoing fixture `p260-production-outgoing`; registered in
  check_reliability_simulation_discovery.sh:229-230, runner :365.
Missing coverage gaps: outgoing-pending open (only the repro's bug-asserting test), outgoing
restart/recovery, mid-lease finalize race (unreachable on HEAD), real-shaped uploadMediaFn in
wired tests (all stubs skip the unlink → Leg A invisible), sender-pending device journey.
Already in curated family arrays?: as listed per file above (ONE_TO_ONE_TESTS
scripts/run_test_gates.sh:21; ONE_TO_ONE_HOST_TESTS scripts/run_host_test_gates.sh:18).

## RED Test Catalog  (three causal RED waves — each production/proof seam stays RED-first)
1. test/features/conversation/presentation/screens/conversation_wired_sender_finalize_canonical_path_test.dart::"finalize persists canonical relative path when real upload unlinked the pending source"
   - Tier: widget/host (wired send flow)
   - Shape/setup: pump ConversationWired with a REAL-SHAPED fake `uploadMediaFn` that (like
     production uploadMedia) copies source→canonical owned path, UNLINKS the source
     (deleteSourceWhenDone contract), and returns the canonical RELATIVE localPath; send one
     protected photo; read the persisted attachment row.
   - RED on HEAD because: `_buildLocalSuccessAttachmentFromPlan` missing-source fallback
     (conversation_wired.dart:688-695) persists `local_path` = absolute pending path; assertion
     `local_path == media/<peer>/<blob>.jpg` fails.
   - GREEN after fix asserts: row `local_path` == canonical relative, `download_status`='done',
     canonical file exists, and the upload result's hash/key/nonce/scheme survive persistence;
     follow-up `prepareResult` on that row is GRANTED. No test obligation is attached to the
     unreachable `mediaFileManager == null` branch.
   - Mutation that re-reds: revert the E1 fallback edit → row carries the pending absolute path.
2. test/features/conversation/application/direct_private_media_sender_pending_open_test.dart::"outgoing upload_pending row grants one-more-look from the pending copy (protected AND view_once)"
   (rename+flip of sender_protected_open_repro_test.dart test 2; keep test 1 as sentinel)
   - Tier: application host, production-schema SQLite/FFI fixture (MediaRepositoryRealDbFixture)
     + real adapter/engine/controller + fake protection coordinator.
   - Shape/setup: PARAMETERIZED over mode in {protected, view_once}: outgoing available parent;
     attachment row `upload_pending` at `pending_uploads/<msg>/<blob>.jpg` (lane direct); real
     pending file with matching size.
   - RED on HEAD because: prepare fails `localAuthorityMissing` (adapter gates) — assertion
     `result.isGranted` fails (exact current behavior proven by the repro).
   - GREEN after fix uses fresh fixtures for the two mutually exclusive outcomes: grant with
     `localPath` == resolved pending absolute and pre-frame rollback returns `available`; a
     separate fresh lease records first frame and terminalizes to `consumed`.
   - Mutation that re-reds: revert ANY of E2 adapter mapping / E2 path acceptance / E3 SQL
     predicate — each independently re-reds (three sub-assertions pin all three gates: adapter
     target probe `isDownloadComplete`, `_verifiedOpenableLocalPath` non-null via grant, and a
     direct `dbClaimDirectPrivateMediaOpening` CAS probe).
3. same file::"pending-path authority negatives fail closed"
   - Tier: application host (same fixture) — GUARD rows for the NEW E2 branch (green on HEAD,
     mutation-verified against the new code)
   - Shape/setup: compact negative matrix against the pending arm: missing exact leaf with NO
     canonical replacement; missing trusted root or message directory; wrong messageId/attachmentId;
     sibling pending file; wrong extension; absolute pending stored path; outside-root path; unsafe
     identifiers; symlinked root/ancestor/leaf; directory/non-file; size mismatch. The pending authority root is independently constructed
     from app documents + `pending_uploads/`, never from the candidate/stored row.
   - RED on HEAD because: guard rows — green on HEAD; documented as such.
   - GREEN after fix asserts: every negative is refused with zero state mutation; only the exact
     missing-leaf case reports typed `senderLocalBytesMissing`, while a missing root/ancestor and all
     authority/identity/symlink/type/size violations remain generic `localAuthorityMissing`. A bare pending row plus
     canonical bytes but no matching deferred completion remains pending and fabricates no key.
   - Mutation that re-reds: delete the existence/size check (or any path-guard call) inside the
     E2 pending branch → the corresponding negative flips red.
4. test/core/database/helpers/private_media_lifecycle_cas_test.dart::"outgoing pending identity claims, views, rolls back, consumes and quarantines exactly once (protected AND view_once)"
   - Tier: integration/repo-host (production-schema SQLite/FFI via fixture — NOT SQLCipher;
     the fixture builds through the shared production migration registry)
   - Shape/setup: parameterized outgoing parent mode {protected, view_once} + direct attachment
     row `upload_pending` at the pending relative path. Use isolated fixtures for claim,
     mark-viewing, rollback, consume, and the separately inlined quarantine predicate; all use
     exact `storedLocalPath` = pending path.
   - RED on HEAD because: every exact CAS returns 0 rows (SQL `download_status = 'done'` at
     :1105 and inline :1245).
   - GREEN after fix asserts: each CAS updates exactly 1 row for the exact pending identity; a
     WRONG path or wrong attachmentId still updates 0 (exact-identity contract retained).
   - Mutation that re-reds: revert the shared E3 predicate → shared cases return 0; separately
     revert only the inline quarantine predicate → quarantine returns 0.
5. same file::"incoming lease identity still requires done and canonical path"
   - Tier: integration/repo-host (sentinel — green on HEAD, guards over-widening)
   - Shape/setup: incoming view_once parent + `upload_pending` attachment → both the shared
     claim/mark/rollback/consume predicate and the separately inlined quarantine predicate return
     0 before AND after the fix.
   - RED on HEAD because: N/A (sentinel); goes RED if E3 widens the incoming direction.
   - GREEN asserts: 0 rows for incoming pending identity.
   - Mutation that re-reds: widen either incoming shared arm or incoming inline quarantine arm →
     its isolated sentinel flips red.
6. test/features/conversation/presentation/screens/direct_private_media_sender_pending_button_test.dart::"sender bubble offers one-more-look during the upload_pending window"
   - Tier: widget
   - Shape/setup: parameterize protected + view_once ConversationScreen parents whose single
     attachment is lane-direct, message-owned, `upload_pending`, pending-relative, with an
     existing file (DB-hydrated/restart shape).
   - RED on HEAD because: `localMediaAvailable` requires 'done' (conversation_screen.dart:1013)
     → `find.byKey(ValueKey('private-media-open'))` finds nothing.
   - GREEN after fix asserts: Open button present + enabled; tap invokes the launcher with the
     exact identity.
   - Mutation that re-reds: revert the E5 `localMediaAvailable` status-set edit.
7. same file::"in-session send stamps direct lane so the pending bubble gates truthfully"
   - Tier: widget (wired)
   - Shape/setup: ConversationWired send of a protected photo with a barrier around durable
     preparation and an uploadMediaFn that never completes. Assert from a fresh DB/reload at the
     pre-preparation barrier that the parent may exist but no private attachment/source-path row is
     durable and no Open can be reconstructed; after the real pending-copy/row transaction, the displayed object is exactly
     message-owned, direct-lane, `upload_pending`, pending-relative, and Open is enabled.
   - RED on HEAD because: optimistic/displayMedia attachments carry `ownerLane == null` →
     eligibility `wrongOwner` → no button (empirically proven in wf C3 probe).
   - GREEN after fix asserts: in-session pending bubble shows the same enabled Open button
     without the current display-only absolute-path + `done` lie.
   - Mutation that re-reds: restore `_persistOptimisticAttachments` for the private picker row or
     revert the E5 ownerLane stamping.
8. same file::"genuinely missing sender bytes show the sender-local-missing body"
   - Tier: widget
   - Shape/setup: outgoing pending row WITH the file present at render; a real-controller launcher
     wrapper deletes the exact authorized file immediately before qualification, then the test
     taps Open. Add a wrong-path/symlink authority control where bytes remain.
   - RED on HEAD because: conversation_screen failure call site (:988-1008) never passes
     `localMediaMissing` → generic `private_media_notification_body` shown.
   - GREEN after fix asserts: missing bytes produce typed `senderLocalBytesMissing`, sender-local-
     missing copy, and no retry; the authority control retains generic copy so the UI cannot label
     every outgoing authority failure as locally missing.
   - Mutation that re-reds: revert the E5 localMediaMissing pass-through.
9. test/features/conversation/application/retry_incomplete_uploads_pending_open_race_test.dart::"shared-runtime completion races atomically with PRE-FRAME rollback"
   - Tier: application host, production-schema SQLite/FFI fixture + fake secure store
   - Shape/setup: build startup and `ConversationWired` lifecycle adapters plus foreground,
     incomplete-retry, and send-result writers over the same app DB/repository runtime; assert they
     resolve one coordinator and the exact same `MediaAttachmentLifecycleLock`. Open a pending row
     through one adapter, barrier a writer on a complete canonical result containing a newly rotated
     key/nonce/hash, and settle through the other. Exercise both serialized orders: registration
     wins before settlement, and settlement wins before registration. Do NOT mark first frame.
   - RED on HEAD because: the plain save rewrites path/status/key during the lease and exact
     revalidation/rollback fails.
   - GREEN after fix asserts: outcome `deferredActiveLease`; exact DB row and live secure key stay
     byte-identical while open; revalidation succeeds; rollback+completion produces one atomic
     result—parent `available`, row canonical+`done`, complete new hash/key/nonce/scheme persisted,
     deferred token empty—and a subsequent canonical open grants. When settlement wins first, the
     writer observes positive `available` authority and commits directly; neither order strands a
     token. No `markFirstFrame` assertion belongs in this rollback case.
   - Mutation that re-reds: construct an adapter-local coordinator, release the shared lock before
     token publication, bypass E6, omit the token, split rollback/save, or remove key compensation.
10. same file::"deferred completion is discarded by FIRST-FRAME terminal settlement and late writers cannot reinsert"
    - Tier: application host
    - Shape/setup: as #9 through deferred outcome, keep the viewer open while the upload caller
      persists the complete result into the durable media envelope, then mark first frame and settle
      terminally; release transfer custody and invoke the same completion plus a fallback writer
      again after cleanup.
    - RED on HEAD because: the plain save rewrites mid-lease or reinserts row/key after consume.
    - GREEN after fix asserts: transport does not wait for local canonical-row commit; after durable
      handoff the consumed state discards the token, cleanup removes row/key/files, and every late
      completion returns permanent refusal without resurrection.
    - Mutation that re-reds: replace positive authority with `not opening/viewing`, or omit
      terminal token discard.
11. same file::"pending deletion is lifecycle-locked and never races a pending-path lease"
    - Tier: application host
    - Shape/setup: interleave exact requalification, a lease claim, and each pending-dir deletion
      caller behind barriers; include foreground, incomplete-retry, and manual-retry cleanup.
    - RED on HEAD because: callers delete independently of the attachment lifecycle lock.
    - GREEN after fix asserts: no check/delete TOCTOU; file survives opening/viewing, deletion runs
      only after committed promotion or terminal cleanup, and unrelated directories are untouched.
    - Mutation that re-reds: move deletion outside the lock or bypass one named caller.
12. same file::"every attachment/message writer and destructive parent uses typed private authority"
    - Tier: application host; one isolated barrier case per raw writer
    - Shape/setup: exercise upload-failure projection (connectivity/bounded/exhausted/terminal),
      retrier fallback, cancellation, manual rearm/failure, `_persistOutgoingMedia` stale-set bulk
      deletion, `dbMarkUploadPendingAttachmentsFailedForMessage`, and failed-media deletion—or
      provide a source-enforced nonprivate proof for either bulk helper. Exercise foreground,
      incomplete-retry, manual-retry, and send-result upload-success callers separately because
      every insertion-capable success must produce the same exact deferred-completion behavior.
      Barrier `updateWireEnvelope`, `_saveOutgoingMessageWithMedia`, and final status persistence
      against opening/viewing/consumed transitions and assert no stale full save overwrites private
      state, deletion intent, or attachment identity.
      Separately race a live lease against private Delete-for-Me, delivered/inboxed private
      Delete-for-Everyone, and contact deletion: the first two use terminal lifecycle cleanup after
      their durable user-intent mutation; contact deletion either terminalizes/cleans every affected
      private parent or returns before its first file/row/contact side effect.
    - RED on HEAD because: at least one raw writer mutates status/path/rows under the lease.
    - GREEN after fix asserts: failure/cancel/rearm/delete paths return `notAppliedActiveLease`,
      preserve attachment row, parent transport/private state, key, and lease, and are not reported
      to callers as successful transitions; terminal parents permanently no-op for local mutation,
      with only E8's exact transport-only custody exception. Each success caller defers/carries the
      full completion and follows #9/#10/#13. Ordinary-media callers retain their existing
      save/delete behavior. Terminal-authorized user deletion is not misclassified as an
      available-only transport failure/cancel/stale-row mutation.
    - Mutation that re-reds: bypass any named writer, infer privacy from encryption metadata, or
      let a private caller fall back to generic save when the guarded capability is absent, or
      route any named destructive parent through generic attachment cleanup.
13. same file::"real private upload lanes preserve transfer and durable outbox custody"
    - Tier: application host; parameterized foreground, incomplete-retry, and manual-retry callers
    - Shape/setup: drive each REAL caller behind a barrier before its first byte read; do not seed
      a registry token manually. While the upload is blocked, open the pending copy. For the
      incomplete retrier, keep the viewer long-lived through upload success and prove the complete
      in-memory result reaches durable envelope persistence despite local `deferredActiveLease`;
      after terminal settlement/restart, the same exact custody shape produces
      `transportOnlyTerminalCustody`, never a local row/key write.
      Start with a stale non-null envelope and prove a state-preserving update clears it while the
      registry is claimed, before the key-rotating re-upload; invalidation failure aborts before the
      first read. A barrier after upload but before the new envelope therefore remains non-custodial. Exercise
      release both before and after first-frame terminal settlement. Add an ordinary-upload control.
    - RED on HEAD because: no upload caller acquires `directPrivateMediaTransferRegistry`,
      foreground passes `deleteSourceWhenDone: true`, and `_lateSendAbortReason` rejects the locally
      deferred pending row; upload/cleanup can delete the live source before durable handoff.
    - GREEN after fix asserts: each private caller owns the transfer token through completion
      registration/durable envelope handoff; no lifecycle lock is held while the blocked upload
      performs file/crypto/network I/O; foreground never requests source unlink; terminal cleanup
      retains bytes while transfer/viewer custody is active. `finally` releases and explicitly
      triggers the appropriate cleanup: pending-source-only cleanup after an available+committed
      promotion, or full cleanup after terminal state plus durable transport custody. The ordinary
      control still unlinks as today. Exact deferred/transport-only fingerprints may satisfy
      late-send assembly and its envelope/status writes preserve terminal viewer state;
      an unowned pending row, missing attachment, or conflicting result still aborts. After the
      rebuilt envelope is persisted and local row/files are cleaned, restart-shaped `failed` and
      `sent` cases replay the byte-identical envelope through real `retryFailedMessages` and
      `retryUnackedMessages` without media reconstruction.
    - Mutation that re-reds: omit any lane's claim, restore private foreground unlink, release
      before envelope persistence, hold the lifecycle lock across I/O, omit post-release
      reconciliation, or make a post-cleanup retry require the deleted attachment.
14. test/features/conversation/application/direct_private_media_sender_pending_open_test.dart::"legacy done row with dangling absolute pending path is repaired at open qualification"
    - Tier: application host (persisted-row test)
    - Shape/setup: parameterize protected + view_once over the EXACT deployed broken shape:
      `done` with ABSOLUTE dangling `pending_uploads/…` path, pending file absent, canonical owned
      file present with exact size; call prepareResult. Snapshot all non-path fields plus secure
      key/bookmark/playback. Add canonical-missing, wrong-size, symlink/non-file, competing-row
      change, and a second idempotent execution.
    - RED on HEAD because: prepare fails `localAuthorityMissing` (convention check) and no
      repair path exists for 'done' rows — assertion `isGranted` fails.
    - GREEN after fix asserts: E7 changes only `local_path`, then the SAME call chain grants;
      every other row/key/local-viewer field is identical, negatives refuse, and the second run is
      an idempotent no-op.
    - Mutation that re-reds: revert the E7 qualification-time repair.
15. same file::"post-rollback retry requalifies the pending shape"
    - Tier: application host (E4 causal row)
    - Shape/setup: pending row + valid pending bytes but deliberately NO canonical file and NO
      deferred completion; grant, settle pre-frame to `rolledBackAvailable`, then call the typed
      retry API. Add missing/wrong pending path and terminal-state negatives.
    - RED on HEAD because: `_requalifyRetry` hard-fails the pending shape
      (direct_private_media_viewer_controller.dart:794/:799) → canRetry false.
    - GREEN after fix asserts: reread remains `upload_pending`; canRetry true only for the exact
      rolled-back pending shape and false for missing/wrong-path or terminal shapes. This prevents
      E7/canonical `done` behavior from masking an omitted E4 edit.
    - Mutation that re-reds: revert the E4 `_requalifyRetry` arm.
16. test/features/conversation/integration/private_media_restart_replay_test.dart::"restart terminalizes viewer state without destroying unhanded-off outbox custody"
    - Tier: integration (real on-disk DB, fixture restart)
    - Shape/setup: seed outgoing protected parents stranded at `private_media_state='opening'`
      with exact pending attachment/files. Restart once while `wire_envelope IS NULL` and once after
      the exact rebuilt envelope has been persisted non-null; then run `reconcileLocalLifecycle`. In the no-handoff
      branch, run the real incomplete retrier after restart through envelope persistence and release.
    - RED on HEAD because: recovery terminalizes and unconditionally cleans the pending family, so
      the no-handoff branch loses the only retryable outbound source.
    - GREEN asserts: both parents become terminal (`consumed`) and cannot reopen. Before durable
      handoff, the exact outbox row/pending file remains retryable (without exposing viewer access),
      restart retry receives `transportOnlyTerminalCustody`, completes transport from the retained
      source, and post-release cleanup removes it. With pre-existing
      durable handoff, startup immediately removes row/key/files. Explicit hidden/deleted intent
      also cleans immediately.
    - Mutation that re-reds: make consumed cleanup unconditional, treat terminal parent as openable,
      or retain artifacts after durable handoff/explicit deletion.
17. same restart file + race file::"failed atomic rollback/finalize leaves opening and restart fails closed"
    - Tier: application/integration, real on-disk DB + fake secure store
    - Shape/setup: defer a complete upload result; inject DB `false` and throw separately inside
      the combined rollback/finalize transaction, then destroy all process-local coordinator state
      and reopen the database. In a third branch let the transaction commit and inject a throw from
      the subsequent repository refresh/event. Replay the exact already-committed completion, then
      vary each fingerprint field (path, size, hash, key, nonce, scheme) one at a time.
    - RED on HEAD because: no combined transaction/token exists; a split implementation can leave
      `available` with old/lost key metadata.
    - GREEN after fix asserts: pre-commit false/throw compensation restores the old key and parent never commits
      `available`; one branch proves controller-owned post-lock reconciliation terminalizes and
      immediately applies E8's custody-qualified cleanup, while a crash-injection branch destroys
      process state first and proves startup reconciliation does the same. A post-commit refresh/event throw does NOT
      compensate or downgrade: new key + canonical row + `available` parent remain committed, the
      token is consumed, and settlement reports `rolledBackAvailable`. No late callback resurrects
      terminal state. A bare pending row plus canonical file but no live token never promotes. An
      exact full-fingerprint replay returns `committed` without a second key write; every differing
      persisted field refuses with zero side effects.
    - Mutation that re-reds: split parent/attachment commits, persist the new key without
      compensation, include refresh/events inside the compensated callback, compare duplicates by
      model `==`, or reconstruct pending success from canonical bytes alone.
18. integration_test/direct_private_media_device_local_journey_harness.dart + integration_test/scripts/direct_private_media_device_local_journey_criteria.dart::"sender pending one-more-look criterion (p262 fixture) — CAUSAL tap-through"
    - Tier: device-proof (existing registered journey — PROD-CRITICAL closure leg)
    - Shape/setup: add a `p262-sender-pending` fixture. The p262 slice MUST be causal, not
      visibility-only: the existing harness wires `onOpenPrivateMedia: (_) async {}` (no-op,
      harness :224), measures action visibility rather than tapping (:340), and holds
      UI attachments only in projection maps. The recipient proof's current
      `seedDurableAttachment` already writes SQL; do not claim the whole harness is memory-only.
      For the physical-sender p262 slice: create a valid decodable PNG through real
      `MediaFileManager.copyToDurableStorage` under the application-documents root; seed an outgoing
      protected parent + exact direct `upload_pending` attachment in the on-device production
      SQLCipher DB through a fixture-only outgoing raw/preserving save (the current guarded seed is
      incoming-only), assert exact path/status/size SQL before the tap, and only then seed the
      repository mirror. Wire `onOpenPrivateMediaResult` through a real
      `DirectPrivateMediaViewerController` AND the real `DirectPrivateMediaViewer` route/first-frame
      callback, TAP the scoped Open action, and derive evidence from SQL reads: exactly one tap and
      available→opening→viewing. After proving the first frame, tap the real viewer Back control,
      await the conversation route, and observe →consumed plus attachment/file cleanup. Directly
      calling mark/settle in a fake callback is insufficient. Put these observations under the
      sender role only. Existing p260 observation meanings remain untouched. Bump proof artifact
      version 2→3 and update exact-key, valid, legacy-v1, legacy-v2, and future-v4 fixtures.
      Extend the evaluator (and its host test
      test/integration/direct_private_media_device_local_journey_criteria_test.dart) to REQUIRE
      the derived sequence (reject missing/wrong sequence and boolean-only evidence).
    - RED on HEAD because: evaluator host test demanding the p262 criterion fails until the
      evaluator knows it; on-device the tap-through fails while the authority rejects pending.
    - GREEN after fix asserts: complete artifact accepted only with the derived p262 criterion.
    - Mutation that re-reds: revert any Leg-B edit → device journey tap-through + criterion fail.

## Test Coverage Matrix  (ZERO empty cells in tier / mutation / gate / registration)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-262-01 finalize canonical path (Leg A) | UI-wired persistence | widget/host | conversation_wired_sender_finalize_canonical_path_test.dart::catalog #1 | fallback persists dangling absolute pending path | revert E1 | flutter test test/features/conversation/presentation/screens/conversation_wired_sender_finalize_canonical_path_test.dart | AUTO (glob) + add to ONE_TO_ONE_TESTS |
| TC-262-02 pending grant, protected+view_once (Leg B core) | repo+DB+controller | application host (production-schema SQLite/FFI) | direct_private_media_sender_pending_open_test.dart::catalog #2 | prepare fails localAuthorityMissing | revert E2 or E3 (each pinned) | flutter test test/features/conversation/application/direct_private_media_sender_pending_open_test.dart | AUTO (glob) + add to ONE_TO_ONE_TESTS + ONE_TO_ONE_HOST_TESTS |
| TC-262-03 canonical grant sentinel | repo+DB+controller | application host | same file::"finalized canonical state grants" (repro test 1) | n/a — sentinel (green on HEAD) | revert E2 over-broadly (breaks canonical lane) | same cmd | same registration |
| TC-262-04 pending-authority negative matrix | exact path/filesystem authority guards | application host | same file::catalog #3 | guard rows (green on HEAD; documented) | remove any E2 convention/identifier/containment/symlink/type/size check | same cmd | same registration |
| TC-262-05 CAS pending identity, protected+view_once | DB CAS (production-schema SQLite/FFI) | repo-host | private_media_lifecycle_cas_test.dart::catalog #4 | exact CAS returns 0 for pending identity | revert E3 | flutter test test/core/database/helpers/private_media_lifecycle_cas_test.dart | AUTO (core glob) + add file to ONE_TO_ONE_TESTS |
| TC-262-06 incoming stays strict | DB CAS sentinel | repo-host | same file::catalog #5 | sentinel (green on HEAD) | widen incoming predicate arm | same cmd | same registration |
| TC-262-07 pending button (hydrated/restart) | UI gate | widget | direct_private_media_sender_pending_button_test.dart::catalog #6 | localMediaAvailable requires 'done' | revert E5 status set | flutter test test/features/conversation/presentation/screens/direct_private_media_sender_pending_button_test.dart | AUTO (glob) |
| TC-262-08 durable-prep-only in-session button | persistence/UI phase truthfulness | widget (wired + DB reload) | same file::catalog #7 | picker-path row persists before prep; display later becomes absolute+done | restore optimistic private-row save or display lie | same cmd | AUTO (glob) |
| TC-262-09 truthful missing-bytes copy + generic sibling | UI/controller result discrimination | widget | same file::catalog #8 | localMediaMissing never passed | revert E5 result mapping or hardcode missing for all failures | same cmd | AUTO (glob) |
| TC-262-10 shared-runtime completion + atomic pre-frame rollback/finalize (Leg C) | composition + both race orders + cross-table CAS/key compensation | application host (production-schema SQLite/FFI) | retry_incomplete_uploads_pending_open_race_test.dart::catalog #9 | adapters are separate and plain save rewrites row/key mid-lease | use adapter-local coordinator, unlock before publish, omit token, or split commit | flutter test test/features/conversation/application/retry_incomplete_uploads_pending_open_race_test.dart | AUTO (glob) + add to ONE_TO_ONE_TESTS |
| TC-262-11 lifecycle-locked pending deletion (Leg C) | destructive-action timing/TOCTOU | application host | same file::catalog #11 | raw callers delete outside lock | move deletion outside authority or bypass a caller | same cmd | same registration |
| TC-262-12 restart terminalizes viewer but preserves unhanded-off outbox | lifecycle + transport durability | integration (real on-disk DB) | private_media_restart_replay_test.dart::catalog #16 | unconditional cleanup destroys retryable pending source | make consumed cleanup unconditional or retain after handoff | flutter test test/features/conversation/integration/private_media_restart_replay_test.dart | AUTO (glob); already in ONE_TO_ONE_TESTS + ONE_TO_ONE_HOST_TESTS |
| TC-262-13 egress stays denied | security sentinel | application host | private_media_action_eligibility_test.dart + direct_private_media_boundary_test.dart (existing, unchanged) | sentinel (green on HEAD) | widen eligibility beyond openInApp | ./scripts/run_test_gates.sh 1to1 | already in ONE_TO_ONE_TESTS |
| TC-262-14 physical-sender causal device journey + proof version 3 | Android UI/controller/SQLCipher/filesystem boundary | device-proof | journey harness + criteria::catalog #18 | evaluator lacks v3 sequence; production pending tap fails | replace valid durable PNG/outgoing SQL seed/real route/back exit/SQL observation, or revert Leg B | criteria host test + literal pinned runner in Device Profile | criteria host test already in ONE_TO_ONE_TESTS; harness/runner already registered |
| TC-262-15 first-frame consume discards token; late writer never reinserts | concurrency + terminal custody | application host | same race file::catalog #10 | plain save rewrites/reinserts | weaken positive authority or omit token discard | same cmd as TC-262-10 | same registration |
| TC-262-16 all attachment/message writers and destructive parents use typed authority | caller/bypass + user-deletion coverage | application host | same race file::catalog #12 | raw/full-save callers mutate active identity/state or use generic cleanup | bypass a writer, state-preserving merge, policy route, or named deletion parent | same cmd as TC-262-10 | same registration |
| TC-262-17 real upload lanes retain transfer + durable replay custody | destructive action + transfer/envelope/retry ownership | application host | same race file::catalog #13 | no registry claim; foreground unlinks; deferred retrier cannot hand off | omit lane claim, hold lock over I/O, wait on local commit, release early, omit reconciliation, or require cleaned media for envelope replay | same cmd as TC-262-10 | same registration |
| TC-262-18 legacy dangling-done row repaired at open | persistence repair | application host (persisted-row) | direct_private_media_sender_pending_open_test.dart::catalog #14 | 'done'+dangling path fails with no repair path | revert E7 qualification repair | same cmd as TC-262-02 | same registration as TC-262-02 |
| TC-262-19 post-rollback retry requalification (E4 causal) | controller retry lane | application host | same file::catalog #15 | _requalifyRetry hard-fails pending shape | revert E4 arm | same cmd as TC-262-02 | same registration as TC-262-02 |
| TC-262-20 rollback/finalize boundary and duplicates are crash-safe | atomicity + restart + compensation boundary + full fingerprint | integration (real on-disk DB) | restart/race files::catalog #17 | no atomic seam; refresh can trigger wrong compensation; equality is id-only | split commit, compensate after commit, use model ==, or infer success | flutter test test/features/conversation/integration/private_media_restart_replay_test.dart test/features/conversation/application/retry_incomplete_uploads_pending_open_race_test.dart | existing restart registration + race registration |

Registration-enforcement note: array additions are unenforced. Acceptance uses one exact-line
assertion per `ONE_TO_ONE_TESTS` entry plus fail-closed `--list --only <exact path>` selectors for
the host/family manifests; a combined OR grep is not evidence.

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** TC-262-07 (restart-hydrated pending row reconstructs
  the button) + TC-262-08 (no picker-path attachment survives a pre-prep crash) + TC-262-12
  (restart terminalizes viewer state while preserving unhanded-off outbox custody) + TC-262-18
  (legacy path-only repair) + TC-262-20 (failed combined rollback/finalize remains
  crash-terminalizable; canonical bytes alone never fabricate missing upload metadata).
- **Sibling-surface consistency:** TC-262-06 (incoming lanes stay strict — deliberate asymmetry
  test-locked) + TC-262-13 (save/share/forward/export unchanged for pending-backed rows) +
  TC-262-16 (ALL reachable mid-lease writers under one gate, not just the retrier).
- **Destructive-action side-effects:** TC-262-11 (pending-dir deferral) + TC-262-12
  custody-qualified restart cleanup + TC-262-15 (post-terminal writers cannot resurrect row/key) +
  TC-262-16 (Delete-for-Me/Everyone/contact use terminal authority) + TC-262-17 (cleanup defers
  while transfer/viewer custody is live and while outbound handoff is absent).
- **Invariant re-verification under new transitions:** TC-262-10 (one repository-scoped
  coordinator/lock serializes both race orders and a deferred completion leaves identity/key
  untouched) + TC-262-15 (consume discards local completion authority while E8 independently
  preserves any unhanded-off outbox custody) + TC-262-20
  (pre-commit false/throw, post-commit notification throw, restart, and full-fingerprint replay).
- **Boundary causality:** TC-262-14 requires a real physical-sender tap, production controller +
  viewer route, SQLCipher-observed state sequence, cleanup, and proof-version-3 evaluator—not a
  visibility check or self-assigned flag.

## Invariants (locked by tests)
- INV-262-1: sender one-more-look never depends on relay reachability → TC-262-02, TC-262-14.
- INV-262-2: incoming lease/open contracts unchanged → TC-262-06 + existing 1to1 sentinels.
- INV-262-3: zero egress widening for private rows → TC-262-13.
- INV-262-4: exact-identity CAS retained (wrong path/id still 0 rows) → TC-262-05.
- INV-262-5: a complete upload result is either committed under positive `available` authority or
  token-deferred without changing row/key; pre-frame settlement atomically rolls back+finalizes,
  while exact consumed/no-envelope custody permits transport-only handoff without local mutation;
  never via writer retry loops → TC-262-10/12/15/20.
- INV-262-6: fail-closed on missing pending bytes and every pending-path negative → TC-262-04.
- INV-262-7: nothing reinserts row/key after terminal; cleanup defers while upload custody is
  claimed and reruns after release; automatic consumed cleanup retains outbound custody until a
  durable envelope/handoff exists → TC-262-12/15/17.
- INV-262-8: complete deferred results converge atomically on pre-frame rollback; deployed
  `done`+dangling rows receive path-only repair; pending rows never infer missing crypto metadata
  from canonical bytes → TC-262-10/18/20.
- INV-262-9: before durable prep no sender Open is exposed; after prep the UI object remains
  truthful `upload_pending`/direct/message-owned, and no picker-path attachment row survives the
  pre-prep boundary → TC-262-08.
- INV-262-10: every runtime participant for one app DB/repository shares one coordinator and the
  exact lifecycle lock; no transfer I/O holds that lock → TC-262-10/17.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. Snapshot the dirty tree (`git status --short` into Execution Progress); never revert unrelated
   work. Rename the repro to `direct_private_media_sender_pending_open_test.dart`, replace prints
   with assertions, and keep canonical TC-262-03 as a sentinel.
2. **RED wave A (currently reachable):** add/run catalog #1-#8 and #14, including the SQL halves
   of #4/#5. Do not add E4 catalog #15 or proof catalog #18 yet. Record each true RED and each
   explicitly HEAD-green mutation sentinel.
3. Implement E1-E3 + E5 and the narrow path-only legacy repair: persist the successful upload
   result; add the independently trusted pending root and outgoing protected/View-Once adapter/SQL
   arms; keep incoming strict; make the persisted durable-prep boundary and UI state truthful.
   Deliberately leave E4 `_requalifyRetry` unchanged so its later RED is causal. Run Wave-A GREEN.
4. **RED wave B (newly reachable after E2/E3):** add/run catalog #9-#13 and #15-#17. Use barriers to
   prove each failure is now the planned writer/custody/atomicity defect—not the former inability
   to open pending media. Record HEAD-green preservation rows separately.
5. Implement E4, then E6's exact outgoing-private coordinator + typed outcomes, positive same-transaction
   parent qualification, token ownership/conflict rules, secure-key compensation, explicit parent
   policy routing, full persisted-field duplicate fingerprint, shared runtime composition, and every
   named success/non-completion/bulk/deletion caller. Private capability absence fails closed;
   ordinary callers remain on generic persistence.
6. Implement E7 without editing the shared engine: extend the adapter/repository rollback seam to
   combine exact `opening -> available` rollback and full deferred-completion persistence in one
   DB transaction under the engine-held attachment lock. Discard tokens in terminal cleanup; add
   the narrowly path-only deployed-row repair before outgoing target qualification. Stop-if the
   combined transaction cannot preserve parent+attachment DB atomicity plus fail-closed compensated
   key/restart semantics—replan rather than use a post-settlement retry or canonical-file inference.
   Keep refresh/events outside the compensated transaction callback. On combined failure, schedule direct
   lifecycle reconciliation only after the engine-held lock is released; retain startup recovery
   as the crash fallback.
7. Implement E8 across foreground, incomplete-retry, and manual-retry upload callers: registry
   claim before read, private foreground `deleteSourceWhenDone:false`, hold through completion and
   durable envelope handoff even when local completion defers, release in `finally`, then invoke
   custody-qualified cleanup/reconciliation. Preserve restart-retryable outbox custody until that
   handoff, without reopening a consumed viewer. Move every pending deletion under the exact
   lifecycle lock/authority, but hold no lifecycle lock across transfer I/O.
8. Run Wave-B GREEN and its focused preservation sentinels. Verify each E4/E6-E8 mutation target
   before moving to the boundary proof.
9. **Boundary RED wave C:** add/run proof catalog #18 immediately before E9. Then implement E9
   proof-only changes: artifact version 3, valid PNG in the real documents root, fixture-only
   outgoing SQLCipher seed, real controller + viewer route/back exit, SQL-derived transition/
   cleanup evidence, and strict evaluator mutations. Run criteria host proof and the literal pinned
   Android journey.
10. Rerun every direct command, preservation sentinel, 1to1 gate, exact registration/selector,
    justified core/feature family sweep, and hygiene command in Acceptance Gates. Record exact
    outcomes/artifacts and hand the implementation to independent QA; do not claim closure from
    implementation evidence alone.

## Risks And Edge Cases
- Security: pending plaintext lives outside the canonical media tree → exact convention,
  independently trusted pending root, identifier checks, symlink-safe authorization, regular-file
  and size checks are all mutation-pinned by TC-262-04.
- Over-widening the SQL predicate to incoming → TC-262-06.
- Key rotation: every successful retry returns a new hash/key/nonce/scheme; the process token must
  retain the COMPLETE result and combined rollback/finalize must compensate secure-key writes.
  Its compensation boundary ends with the DB transaction, and duplicate identity uses a full
  persisted-field fingerprint rather than id-only model equality. Canonical bytes alone cannot
  reconstruct upload success → TC-262-10/20.
- Post-terminal reinsertion: any writer landing after consume must not resurrect row or
  secure-store key → E6 positive authority, TC-262-15.
- Sender view sabotaging relay delivery: terminal cleanup can delete the only plaintext either
  during a live upload or after a process restart but before durable transport handoff. E8 covers
  all three upload lanes, carries a deferred result through envelope persistence, disables private
  foreground unlink, retains unhanded-off outbox custody, and reruns cleanup after release/handoff
  → TC-262-12/17.
- Crash semantics: a process-local completion is safe only because rollback+finalize is one DB
  transaction and outbound custody is independently durable. Before commit, restart terminalizes
  viewer access but retains a retryable pending source until transport handoff; after commit,
  parent+attachment+key are complete. Post-commit refresh failure cannot roll back the key
  → TC-262-12/20.
- Caller truthfulness: failure/cancel/rearm/delete attempts during an active lease return explicit
  not-applied outcomes; callers must not display success or mutate parent/attachment inconsistently
  → TC-262-16.
- Sweeper landmine: no new status values introduced; `upload_pending` semantics unchanged →
  media_outbox_queued_lane_test.dart stays green.

## Device Proof Profile
Requires device journey for closure (PROD-CRITICAL: TC-262-14 — host tests cannot prove the
sender-device end-to-end affordance→grant→view→settle chain; do NOT treat host coverage as
sufficient on its own).
Closure scenario: extend the registered `direct_private_media_device_local_journey`, keep all
setup/navigation/tap/assertions automated, and run one pinned USB physical Android sender plus one
Android emulator recipient. Live 2026-07-20 matrix: `21071FDF600CSC` + default `emulator-5554`
(`emulator-5556` also available). Rediscover at execution and substitute the exact available IDs.
No iPhone/manual-tap leg is required. If no policy-eligible pair exists at execution, record
`N/A (target unavailable by project policy)`—never `environment_blocker`, `evidence_gap`, or a
failed gate. This is an app-layer/SQLCipher proof; relay production work remains out of scope.

## Acceptance Gates  (literal — copy/paste; record baselines on HEAD before RED)
```bash
# Baseline capture (HEAD, before any edit) — record exit 0, selected paths, and any failures
./scripts/run_test_gates.sh 1to1
./scripts/run_host_test_gates.sh 1to1

# RED wave A (before E1-E3/E5/path-repair production edits)
flutter test test/features/conversation/application/direct_private_media_sender_pending_open_test.dart
flutter test test/features/conversation/presentation/screens/conversation_wired_sender_finalize_canonical_path_test.dart
flutter test test/core/database/helpers/private_media_lifecycle_cas_test.dart --plain-name 'outgoing pending identity'
flutter test test/features/conversation/presentation/screens/direct_private_media_sender_pending_button_test.dart

# After Wave-A GREEN, RED wave B (add E4 row now; failures must be E4/E6-E8-specific)
flutter test test/features/conversation/application/direct_private_media_sender_pending_open_test.dart
flutter test test/features/conversation/application/retry_incomplete_uploads_pending_open_race_test.dart
flutter test test/features/conversation/integration/private_media_restart_replay_test.dart

# Boundary RED wave C, immediately before E9
flutter test test/integration/direct_private_media_device_local_journey_criteria_test.dart

# Direct GREEN after E9 — rerun every Wave-A/B/C command above: exit 0, zero failures

# Preservation sentinels (must select the expected files and finish with zero failures)
./scripts/run_test_gates.sh 1to1
./scripts/run_host_test_gates.sh 1to1
flutter test test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart test/features/conversation/application/retry_failed_messages_use_case_test.dart test/features/conversation/application/retry_unacked_messages_use_case_test.dart test/features/conversation/application/media_outbox_queued_lane_test.dart test/features/conversation/application/upload_media_use_case_test.dart test/features/conversation/application/consume_private_media_use_case_test.dart test/features/conversation/integration/private_media_restart_replay_test.dart test/features/conversation/application/private_media_cleanup_race_test.dart

# Exact curated-array assertions (combined OR grep is insufficient)
[ "$(grep -Fxc '  "test/features/conversation/application/direct_private_media_sender_pending_open_test.dart"' scripts/run_test_gates.sh)" -eq 1 ]
[ "$(grep -Fxc '  "test/features/conversation/application/retry_incomplete_uploads_pending_open_race_test.dart"' scripts/run_test_gates.sh)" -eq 1 ]
[ "$(grep -Fxc '  "test/core/database/helpers/private_media_lifecycle_cas_test.dart"' scripts/run_test_gates.sh)" -eq 1 ]
[ "$(grep -Fxc '  "test/features/conversation/presentation/screens/conversation_wired_sender_finalize_canonical_path_test.dart"' scripts/run_test_gates.sh)" -eq 1 ]
[ "$(grep -Fxc '  "test/features/conversation/application/direct_private_media_sender_pending_open_test.dart"' scripts/run_host_test_gates.sh)" -eq 1 ]

# Fail-closed host/family discovery for every new file
./scripts/run_host_test_gates.sh 1to1 --list --only test/features/conversation/application/direct_private_media_sender_pending_open_test.dart
./scripts/run_host_test_gates.sh feature-host-all --list --only test/features/conversation/application/direct_private_media_sender_pending_open_test.dart
./scripts/run_host_test_gates.sh feature-host-all --list --only test/features/conversation/application/retry_incomplete_uploads_pending_open_race_test.dart
./scripts/run_host_test_gates.sh feature-host-all --list --only test/features/conversation/presentation/screens/conversation_wired_sender_finalize_canonical_path_test.dart
./scripts/run_host_test_gates.sh feature-host-all --list --only test/features/conversation/presentation/screens/direct_private_media_sender_pending_button_test.dart
./scripts/run_host_test_gates.sh core-host-all --list --only test/core/database/helpers/private_media_lifecycle_cas_test.dart

# Final pre-close sweeps (both lib/core and lib/features change) — batch-parallel form ONLY
./scripts/run_host_test_gates.sh feature-host-all --batch-flutter --concurrency 4 --reporter failures-only
./scripts/run_host_test_gates.sh core-host-all --batch-flutter --concurrency 4 --reporter failures-only

# Device journey (rediscover, pin exact available Android IDs, automate all interactions)
flutter devices --machine
adb devices -l
./scripts/check_reliability_simulation_discovery.sh
flutter test test/integration/direct_private_media_device_local_journey_criteria_test.dart
p262_artifact_dir="$(mktemp -d /tmp/p262-direct-private-media.XXXXXX)"
dart run integration_test/scripts/run_direct_private_media_device_local_journey.dart \
  --sender 21071FDF600CSC \
  --recipient emulator-5554 \
  --artifact-dir "$p262_artifact_dir"
test -s "$p262_artifact_dir/plan234-direct-private-media-device-local-journey.json"

# Hygiene
flutter analyze                                       # 0 new issues
git diff --check
```

Do NOT run full `host-all` for this individual plan. Full `host-all` is owned once by the
Plan-260-S4/Plan-262 sender-one-more-look dependency wave and again by final private-media
rollout/release closure.

## Known-Failure Interpretation
- Expected RED: Wave-A commands fail only at E1-E3/E5/path-repair assertions. After those seams
  turn green, Wave-B fails only at the newly added E4/E6-E8/atomicity/custody assertions; a failure
  caused merely by pending-open rejection is off-target. Wave C fails only because the v3 p262
  evaluator/causal proof contract is absent before E9.
- Pre-existing dirty: large uncommitted working tree (259/260 execution + this session's repro
  test + memory/docs edits) — snapshot first; never revert unrelated files.
- Toolchain: `/claude-host-bin/flutter` is absent on 2026-07-20. PATH resolves to
  `/Users/I560101/development/flutter/bin/flutter` 3.41.4; literal commands use plain `flutter`.
- Device availability: the current eligible pair is physical `21071FDF600CSC` + emulator
  `emulator-5554` (5556 also available). Rediscover at execution. If an eligible pair is absent,
  record `N/A (target unavailable by project policy)` rather than an environment blocker/gap.
- Scope drift (BLOCKING): any group/announcement-lane, relay/bridge, or incoming-contract diff.

## Done Criteria
- [ ] All three causal RED waves recorded before their corresponding production/proof seams; each true RED
      failed for its documented reason and every HEAD-green sentinel is labeled honestly.
- [ ] Mutation-verified (every E1-E9 edit and every named raw caller has a re-red mutation).
- [ ] Direct GREEN + preservation sentinels + 1to1 gates exit 0 with expected selected paths and
      zero failures; no count-delta substitute for registration evidence.
- [ ] No schema migration: E3/new CAS use existing columns, coordinator state is process-local,
      and E9's version bump is proof-artifact-only; confirm no schema diff.
- [ ] `feature-host-all` and `core-host-all` pass; full `host-all` remains wave/final-owned.
- [ ] TC-262-14 proven on an available pinned Android pair with version-3 causal artifact, or
      recorded `N/A (target unavailable by project policy)` if no eligible pair exists.
- [ ] Exact-line curated registrations and exact host/family selectors pass.
- [ ] flutter analyze 0 new; git diff --check clean; no Scope Guard violations.

## Scope Guard (hard "Do not")
- Do not touch group (238) / announcement (242) private-media lanes.
- Do not introduce new `download_status` values ('sending'-sweeper landmine).
- Do not modify engine `openOneShot`/`_openableTargetPath`/`_matchesLease` gates (derivative).
- Do not widen the incoming direction of any CAS predicate.
- Do not widen eligibility beyond `openInApp` for the pending shape (no egress).
- Do not trust lane-less in-memory attachments for authority decisions (C3 lesson).
- Do not weaken exact lease identity or change path/status/key while a completion is deferred.
- Do not infer a successful pending upload from canonical-file existence; key/nonce/hash are not
  reconstructible. Only a complete exact deferred token may participate in atomic rollback/finalize.
- Do not use bounded writer retries, an in-memory callback without atomic settlement, or a
  negative-only `not opening/viewing` predicate.
- Do not let private parents fall back to generic save/delete when the guarded capability/policy
  context is unavailable.
- Do not construct a coordinator per adapter/caller or publish/remove a token outside the exact
  repository runtime's lifecycle lock; do not hold that lock across file/crypto/network I/O.
- Do not delete/relocate the pending copy before committed promotion or custody-qualified terminal
  cleanup, and do not release transfer custody before durable envelope/transport handoff.
- Do not let automatic consumed cleanup destroy an outgoing source before durable transport
  custody, or let retained outbox custody re-enable viewer access on a terminal parent.
- Do not change artifact proof version outside the proof-only harness/criteria contract.

## Accepted Differences / Intentionally Out Of Scope
- Process death while an outgoing one-more-look lease is still `opening|viewing` preserves the
  fail-closed viewer contract: restart terminalizes and never resurrects the process-local
  completion. Cleanup is transport-custody-aware: it retains only the exact retryable outbox
  row/source until durable handoff, then removes it.
- A transport cancel/failure/rearm/stale-row deletion that races an active lease is explicitly not
  applied and must not be reported as successful. The truthful pending state remains and may be
  retried after settlement. Durable queues for these non-completion intents are out of scope.
  Explicit Delete-for-Me/Delete-for-Everyone/contact deletion is terminal user intent and follows
  the E6 lifecycle-cleanup contract instead of this available-only rule.
- Group-lane one-more-look parity: 238-series owns it; the SQL predicate change here is
  direct-lane only.
- Retrier connectivity gating (memory landmine: none exists) — 260 S3 follow-ups own it.

## Dependency Impact
- Builds directly on 260 S4 (sender one-more-look CAS lane) and 259 copy keys
  (`private_media_sender_local_missing_body`); 260 S3's queued-lane sweep exclusions are a
  hard prerequisite sentinel (upload_pending must never be reaped mid-window).
- The debug-session memory note `sender-protected-open-authority-divergence` should be updated
  at execution close (its "happy finalized state opens fine" clause is field-refuted by Leg A).

## Reviewer Findings
Review 1 (2026-07-19, external): verdict not-ready; blockers (1) E6 bounded re-attempt cannot
guarantee post-lease convergence (stranding counterexample: viewer outlives every retry; sent
parent leaves the retrier's sending|failed set; pending file already unlinked) and TC-262-10
was internally contradictory (first frame ⇒ terminal, no reopen); (2) guard missed reachable
writers (failure projection, cancellation, manual retry, `_persistOutgoingMedia` bulk delete)
and the upload↔cleanup custody split (uploads claim mediaUploadInFlightTracker, cleanup checks
directPrivateMediaTransferRegistry) enables consume-mid-upload plaintext deletion; (3)
TC-262-14 was visibility-only (harness no-op `onOpenPrivateMedia` :225 and visibility assertions);
(4) E4 untested, E2 lacked negatives, TC-262-09 setup contradictory, pre-durable lane stamping
unsafe, protected-only parameterization; (5) legacy broken rows unrepaired; (6) command/gate
corrections.

Review 2 (2026-07-20, `$tdd-review`): initial verdict `plan-fixes-required`; core pending-open
direction confirmed, but v3 was unsafe to execute as written. Confirmed counterexamples: (1)
startup, `ConversationWired`, and deletion construct separate lifecycle adapters, so an
adapter-local completion coordinator cannot serialize writers/settlement; the state read and token
publication also require the exact shared lifecycle lock; (2) `_persistOptimisticAttachments`
durably exposes the picker/source row before pending-copy preparation, and generic
Delete-for-Everyone/contact cleanup plus unpublished settlement were not test-pinned; (3) Wave A
included E4 before E2/E3 made it reachable and included the proof evaluator before E9, permitting
wrong-cause REDs/impossible GREEN; (4) the device fixture used an incoming-only guarded save and
non-decodable bytes, and omitted the real viewer exit; (5) most critically, first-frame/restart
cleanup could destroy the only outbound source before `wire_envelope` persistence, making an
offline private send permanently unretryable; (6) post-commit refresh inside key compensation could
restore an old key after the DB commit, and id-only model equality could accept a conflicting
completion replay.

## Revision Disposition
- Review-1 deltas remain: exact positive mutation authority, full deferred result, atomic
  rollback/finalize, exhaustive writer inventory, three-lane transfer custody, path-only legacy
  repair, causal device proof, literal gates, and wave/final `host-all` ownership.
- Review-2 findings are applied in v4 through one repository-runtime coordinator/lock, a crash-
  observable pre-prep test, terminal deletion/settlement coverage, corrected A/B/C RED order,
  production-shaped outgoing device setup/exit, and full-fingerprint duplicate semantics.
- E8 now uses the existing crash contract explicitly: old envelope cleared before key rotation;
  exact deferred/transport-only results may build the new envelope; automatic consumed cleanup
  retains the exact pending outbox source while `wire_envelope IS NULL`, without restoring viewer
  authority. E7 ends compensation at the DB transaction and treats post-commit observer failure as
  committed.
- The five review lenses and triggered B2/B4/B5/B6 blind spots were rerun against v4; no required
  plan delta or user-owned decision remains.

## Final Execution Verdict
ready — disposition: execute
