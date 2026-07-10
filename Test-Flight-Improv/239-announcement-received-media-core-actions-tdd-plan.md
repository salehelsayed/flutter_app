# 239 - Announcement Received-Media Core Actions

Status: implemented (host-green 2026-07-10)
Type: Feature Improvement
Spec: free-text intent — local received image/video parity for announcement recipients (Save, Share, Delete for me, and Info) without granting announcement publish permission
Classification: implementation-ready
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector / Planner | group conversation UI/wiring; announcement authorization; plans 227/228/230/235 | Announcement readers need local received-media actions without gaining write permission. | Reuse the shared media foundation and keep transport unchanged. |
| 2026-07-10 | Planner refresh | owner-lane persistence and the proposed group delete/reconcile seams | Announcements are group-owned media and must not introduce a third owner lane. | Require group-owner qualification and reuse the group deletion contract. |
| 2026-07-10 | Independent review revision | `group_received_media_action_policy.dart`; group screen/wired tests; DB v98 deletion journal; existing Info sheet; analyzer baseline | Plans 227/228/230/235 are already implemented in current source. The old coordinator/viewer/delete/reconciler proposal is stale; the live gap is the chat-only capability guard, announcement-admin Reply leakage from `canWrite`, and missing MIME/dimensions/duration Info fields. | Reduce Plan 239 to policy/presentation metadata changes plus preservation sentinels. |

## Problem And Evidence

- Behavior to improve: a recipient opening an incoming announcement image/video should receive the local media actions Save, Share, Info, and Delete for me from both the attachment overlay and typed viewer. These actions must not grant Reply or publishing ability.
- Impact: announcement media is viewable but the already-implemented group received-media actions are deliberately unreachable for this group type.
- Confirmed current gap: `GroupReceivedMediaActionPolicy.capabilitiesFor` at `lib/features/groups/application/group_received_media_action_policy.dart:28-52` returns an empty set for every non-chat group at line 34. This is the remaining action-availability blocker.
- Confirmed admin counterexample: `GroupConversationWired._canWriteForGroup` at `lib/features/groups/presentation/screens/group_conversation_wired.dart:4948-4965` makes an announcement admin writable, while `GroupConversationScreen._showMessageContextOverlay` at `lib/features/groups/presentation/screens/group_conversation_screen.dart:1026` derives Reply directly from `canWrite`. Enabling announcement media capabilities without tightening the media-target branch would therefore leak Reply to admins.
- Confirmed implemented stack: the attachment overlay already routes Save, Share, Info, and Delete at `group_conversation_screen.dart:1029-1085`; the typed viewer and all action callbacks already exist at `group_conversation_wired.dart:4644-4817`; Save/Share and Delete coordinators are wired at `:4844-4910` and `:5744-5752`.
- Confirmed deletion authority: current DB version is 98 at `lib/core/database/app_database_version.dart:10`. Migration 098 creates the explicit, self-contained `group_media_deletion_journal`; its contract states that orphan shape is never deletion authority at `lib/core/database/migrations/098_group_media_deletion_journal.dart:7-19`.
- Confirmed Info baseline and gap: `GroupMediaInfoSheet` already renders display identity, sent time, size, state, and caption while excluding storage/crypto/transport secrets at `lib/features/groups/presentation/widgets/group_media_info_sheet.dart:8-14` and `:59-107`. It does not render the persisted MIME, image dimensions, or video duration even though `MediaAttachment` and the typed viewer already carry them.
- Existing coverage: GMA-01 locks discussion policy; GMA-04 revalidates exact group-owned media before egress; GMA-07/GMA-08 and IR-020 lock atomic deletion, restart convergence, and replay suppression; GMA-11 locks UI-to-coordinator routing; GMA-12 locks Info redaction; current GMA-13 deliberately excludes both announcements and Q&A.
- Missing coverage: no member/admin announcement case requires the exact received-media capability set, no test catches admin Reply leakage, and no group Info test requires MIME plus conditional dimensions/duration.
- Refuted findings: the viewer, four callbacks, action coordinator, Info sheet, deletion coordinator, restart reconciler, and group-owner persistence are not missing. Creating announcement-specific replacements would duplicate the Plan-235 stack and is prohibited.
- Unresolved findings: N/A — this is a host-only capability and metadata delta over accepted native, owner-lane, viewer, and deletion boundaries.
- Affected production/test files: `lib/features/groups/application/group_received_media_action_policy.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/groups/presentation/widgets/group_media_info_sheet.dart`, and their existing policy/screen/wired tests. `group_conversation_wired.dart` is a reuse seam, not a planned production edit.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `0c960e7158dcc386`; current at review time.
- Query / profile: `python3 graphify-arch/tdd_context.py query "Plan 239 announcement received media group_received_media_action_policy GMA-13 group_media_deletion_journal GroupMediaInfoSheet group_conversation_wired" --profile review --budget 900`.
- Anchors: `GroupMediaInfoSheet` -> `lib/features/groups/presentation/widgets/group_media_info_sheet.dart`; `group_media_deletion_journal` -> `lib/core/database/migrations/098_group_media_deletion_journal.dart`.
- Surfaced proof/gate files: group conversation screen/wired, typed viewer, migration 098, GMA policy/presentation/deletion tests, and `scripts/run_test_gates.sh`.
- Graph gaps requiring source search: the compact result did not surface the policy test or GMA-13 directly; current source and exact test-name search supplied those facts.
- Reuse rule: these anchors may guide execution, but current source/tests remain authoritative.

## Scope Contract And Guard

In scope:
- Extend `GroupReceivedMediaActionPolicy` so an incoming image/video owned by `MediaOwnerLane.group` in `GroupType.announcement` receives Info/Delete for me, plus Save/Share only while `GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia` is true.
- Keep Reply exclusive to writable `GroupType.chat`. For a media-target overlay, derive Reply from the policy capability set rather than raw `canWrite`; a verified announcement admin and member must receive the same four received-media capabilities and never Reply.
- Reuse the existing `GroupReceivedMediaActionsController`, typed viewer, wired callbacks, confirmation flow, and `GroupMediaDeleteForMeCoordinator`. Confirmation from an announcement must dispatch exactly one existing delete operation; cancel dispatches zero.
- Extend the existing privacy-minimized Info sheet with the persisted MIME and conditional image dimensions or video duration. Reuse existing localized media-info labels/format conventions; do not expose raw peer IDs or add a new Info architecture.

Must preserve:
- Discussion policy, including Reply only when writable -> `test/features/groups/application/group_received_media_action_policy_test.dart::GMA-01 discussion incoming media capabilities vary safely by action and state`.
- Discussion bubble/viewer coordinator routing -> `test/features/groups/presentation/group_conversation_wired_test.dart::GMA-11 wired media actions reach only injected coordinators`.
- Q&A remains empty; outgoing, non-visual, direct-owned, and unresolved rows remain ineligible -> TC-239-01/02.
- Save/Share still re-load and revalidate the exact group parent/attachment immediately before egress -> GMA-04.
- Info/Delete remain available for eligible incoming group visual rows even when Save/Share are unavailable; this preserves Plan-235 policy rather than requiring verified bytes for local metadata/deletion.
- Existing reaction/copy behavior remains outside the received-media capability set. “Exactly four” means Save/Share/Info/Delete among media actions, not removal of the message overlay's reaction/copy controls.
- DB v98 journal authority, atomic deletion, restart cleanup, replay suppression, and same-ID isolation remain unchanged -> GMA-07, GMA-08, and IR-020.
- Announcement members remain compose/send read-only, and Go still rejects unauthorized announcement publication -> existing read-only and Go sentinels.

Hard `Do not`:
- Do not add an announcement action coordinator, viewer, delete use case, deletion journal, reconciler, owner lane, migration, or Go/libp2p change.
- Do not infer deletion intent from orphan attachments or change `group_media_deletion_journal`.
- Do not make `canWrite` true for announcement members or enable Reply for announcement media, including admins.
- Do not change normal non-media message overlay behavior, discussion Reply, Q&A behavior, reactions, copy, or compose authorization.
- Do not weaken group-owner, direction, visual-type, current integrity, canonical-path, or action-time revalidation gates.
- Do not render raw peer IDs, paths, hashes, keys, nonces, schemes, relay diagnostics, or export history in Info.
- Do not add Report, Forward, private Reply, Delete for everyone, or attachment-only deletion.

Deferred / accepted difference:
- Protected/view-once/disappearing policy remains owned by plan 242.
- Reporting is owned by plan 246; cross-lane private Reply is owned by plan 247.
- MIME/dimensions/duration improve the shared group Info sheet for discussion media too; this is an accepted consistency improvement, guarded by existing GMA-12 redaction coverage.

Dependencies:
- Current source already contains the accepted Plan-227 egress service, Plan-228 `MediaOwnerLane.group`, Plan-230 typed viewer, and Plan-235 group action/delete stack.
- Execution preflight verifies those source/test anchors and DB v98 directly; it does not infer readiness from stale status prose in dependency plan headers.
- No schema, SQLCipher, native, device, relay, or transport boundary is changed by Plan 239.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-239-01 | Policy gives verified incoming group-owned announcement media exactly Save/Share/Info/Delete for both member (`canWrite=false`) and admin (`canWrite=true`); unverified keeps Info/Delete; Q&A and all existing direction/type/lane negatives remain empty. | `test/features/groups/application/group_received_media_action_policy_test.dart::GMA-13 announcement member and admin get core media capabilities without reply while qa stays empty` plus GMA-01 | host unit / table-driven `MediaAttachment` fixtures | HEAD returns empty for announcements -> exact member/admin sets pass without Reply and the discussion sentinel remains green | restore the chat-only early return, add Reply when announcement admin `canWrite`, or allow Q&A -> TC-239-01 red | `flutter test test/features/groups/application/group_received_media_action_policy_test.dart --plain-name 'GMA-13 announcement member and admin get core media capabilities without reply while qa stays empty'`; existing `GROUP_TESTS` entry |
| TC-239-02 | Bubble and typed viewer expose the same announcement media actions for member/admin, never Reply, keep Q&A excluded, route Save/Share to the existing controller, open existing Info, and make cancel zero-op/confirm exactly one delete-coordinator call without any send/publish call. | `test/features/groups/presentation/group_conversation_wired_test.dart::GMA-13 announcement member and admin expose core media actions without reply while qa stays excluded` | host wired widget / real screen policy with recording action/delete coordinators and throwing egress/delivery seams | HEAD GMA-13 expects announcements empty -> announcement surfaces expose exact media keys and dispatch only the existing injected seams | derive media Reply from raw `canWrite`, omit one viewer capability, bypass an injected coordinator, or treat Q&A like announcement -> TC-239-02 red | `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'GMA-13 announcement member and admin expose core media actions without reply while qa stays excluded'`; existing `GROUP_TESTS` entry |
| TC-239-03 | Existing Info renders MIME and `width × height` for images or formatted duration for videos while retaining display identity/time/size/state/caption and secret/raw-peer redaction. | `test/features/groups/presentation/group_conversation_screen_test.dart::GMA-12M group media info includes MIME and conditional dimensions or duration` plus existing GMA-12 | host widget / image and video fixtures with sentinel peer/path/hash/key/nonce data | HEAD sheet lacks MIME/dimensions/duration -> both conditional shapes render and every existing redaction remains green | omit MIME, swap dimensions/duration branches, bind `toMap()`, or render sender peer ID -> TC-239-03 red | `flutter test test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'GMA-12M group media info includes MIME and conditional dimensions or duration'`; existing `GROUP_TESTS` entry |
| TC-239-04 | Save/Share remain current-row, exact-parent, group-owner, integrity/path-qualified egress operations; announcement policy does not create a bypass. | `test/features/groups/application/group_received_media_actions_test.dart::GMA-04 egress reloads exact group owner and delegates only currently eligible media` | GREEN sentinel / application host, real temp path and collision fakes | GREEN on HEAD -> remains GREEN | pass viewer path/MIME directly, skip parent/group/lane reload, or accept failed integrity -> sentinel red | `flutter test test/features/groups/application/group_received_media_actions_test.dart --plain-name 'GMA-04 egress reloads exact group owner and delegates only currently eligible media'`; existing `GROUP_TESTS` entry |
| TC-239-05 | Announcement Delete reuses the v98 atomic journal saga and replay protection; no orphan inference, new cleanup path, or migration is introduced. | `test/features/groups/application/delete_group_media_for_me_use_case_test.dart::GMA-07 delete prepare is exact group scoped atomic and reaction safe`; `test/features/groups/integration/group_received_media_delete_replay_test.dart::GMA-08 self contained journal saga converges per item across every restart boundary`; `test/features/groups/domain/repositories/group_message_repository_impl_test.dart::IR-020 tombstone prevents replay save and unread resurrection` | GREEN sentinels / production DB helpers, temp files, restart and replay fixtures | GREEN on DB v98 -> remains GREEN while TC-239-02 proves announcement confirmation reaches this coordinator exactly once | infer cleanup from orphan shape, split delete preparation, skip journal finalize ordering, or bypass tombstone -> sentinel red | run the three exact tests; all paths already occur once in `GROUP_TESTS` |
| TC-239-06 | Announcement member compose/reactions and native publisher authorization remain unchanged. | `test/features/groups/presentation/group_conversation_wired_test.dart::announcement readers stay read-only for compose but still keep reaction entry`; `go-mknoon/node/pubsub_test.go::TestIsAllowedWriter_AnnouncementMemberBlocked`; `::TestGroupTopicValidator_AnnouncementNonAdminRejected` | GREEN sentinels / host widget and Go node validator | GREEN on HEAD -> remains GREEN; no Go production diff | expose compose/send callbacks or allow a non-admin writer in Go -> sentinel red | exact Flutter selector plus `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestIsAllowedWriter_AnnouncementMemberBlocked|TestGroupTopicValidator_AnnouncementNonAdminRejected' -count=1)` |

### Test Notes

- TC-239-01's “exact” set is the `GroupReceivedMediaAction` capability set. Save/Share require current verified media; Info/Delete preserve the accepted Plan-235 behavior for an otherwise eligible incoming visual group row.
- TC-239-02 must exercise member and admin separately. The admin case is causal for the overlay change because raw `canWrite` would expose Reply. Assert both overlay and viewer action keys, exact `(groupId, messageId, attachmentId)` controller calls, zero delivery/bridge calls, zero delete calls after cancel, and one after confirm.
- TC-239-03 may reuse the established direct/viewer formatting conventions and existing localization keys. Use display identity in positive assertions and a distinct raw peer-ID sentinel in negative assertions.
- TC-239-05 is preservation-only. The explicit v98 journal is the sole deletion authority; do not add announcement-specific persistence fixtures merely to repeat Plan 235.

## Implementation Steps

1. Snapshot `git status --short`; verify DB v98, the policy/action/delete classes, existing GMA tests, and their single `GROUP_TESTS` registrations.
2. Add TC-239-01, rename/rework current GMA-13 for TC-239-02, and add TC-239-03 before production edits. Run the first causal RED after the named policy test exists.
3. Replace the policy's chat-only guard with an explicit chat/announcement contract: Q&A fails closed; common incoming/visual/group-owner gates remain; Save/Share stay verified-only; Reply is added only for writable chat.
4. In the existing media-target overlay path, require the Reply capability as well as `canWrite`; leave normal non-media overlay and discussion Reply behavior unchanged. Stop-if: the change needs a new action model or affects compose authorization.
5. Extend `GroupMediaInfoSheet` with MIME plus conditional dimensions/duration using existing metadata and formatting/localization conventions. Preserve the current approved-field allowlist and raw-peer/secret redaction.
6. Run focused tests, representative mutation re-reds, exact preservation sentinels, the curated groups gate, scoped analyzer, and diff hygiene.

## Risks And Blind Spots

- Enabling announcements wholesale could also enable Q&A or admin Reply -> TC-239-01/02 assert type- and action-specific capability sets.
- A viewer-only fix could leave the bubble unavailable, or vice versa -> TC-239-02 exercises both surfaces through the real wired policy.
- Existing action callbacks could be bypassed by announcement-specific wiring -> TC-239-02 requires only the injected Plan-235 coordinators and zero delivery/bridge calls.
- Info expansion could leak raw identity/storage/crypto data -> TC-239-03 extends, rather than replaces, GMA-12's sentinel redaction.
- Lifecycle / derived-state durability: N/A for new logic; capability is recomputed from current message/attachment/group state, while deletion durability remains covered by GMA-07/GMA-08/IR-020.
- Sibling-surface consistency: TC-239-01/02 plus GMA-01/GMA-11 preserve discussion and Q&A behavior.
- Destructive-action side effects: no destructive implementation changes; TC-239-02 and TC-239-05 prove UI dispatch and preserve the existing saga.
- Invariant re-verification under new transitions: GMA-04 remains the action-time authority for Save/Share; the policy does not replace it.

## Gate Cadence

- Per-plan closure: run the focused Plan-239 policy/wired/Info selectors, exact GMA-01/GMA-04/GMA-07/GMA-08/GMA-11/GMA-12/IR-020/read-only/Go sentinels, and the curated `groups` lane gate.
- Do not run `core-host-all`, `feature-host-all`, or full `host-all` for Plan 239; this plan changes no migration, lifecycle, shared native, or transport surface.
- Full `host-all` runs once after the complete announcement core-actions wave (`231` and `239`, with the shared Plan-235 foundation already closed) and once at final received-media rollout/release closure.
- Shared tests outside feature/core globs: Go authorization is run directly; no simulator/device test is required.

## Acceptance Gates

```bash
# Source-backed preflight and dirty-tree snapshot
git status --short
test "$(rg -o 'currentIdentityDatabaseVersion[[:space:]]*=[[:space:]]*[0-9]+' lib/core/database/app_database_version.dart | rg -o '[0-9]+$')" -eq 98
test -f lib/features/groups/application/group_received_media_action_policy.dart
test -f lib/features/groups/application/group_received_media_actions.dart
test -f lib/features/groups/application/group_media_delete_for_me_coordinator.dart
test -f lib/core/database/migrations/098_group_media_deletion_journal.dart
for f in \
  test/features/groups/application/group_received_media_action_policy_test.dart \
  test/features/groups/application/group_received_media_actions_test.dart \
  test/features/groups/application/delete_group_media_for_me_use_case_test.dart \
  test/features/groups/integration/group_received_media_delete_replay_test.dart \
  test/features/groups/presentation/group_conversation_screen_test.dart \
  test/features/groups/presentation/group_conversation_wired_test.dart; do
  test "$(rg -F -c "\"$f\"" scripts/run_test_gates.sh)" -eq 1
done

# First causal RED after adding the named test; expect non-zero because announcements are excluded wholesale
flutter test test/features/groups/application/group_received_media_action_policy_test.dart --plain-name 'GMA-13 announcement member and admin get core media capabilities without reply while qa stays empty'

# Focused GREEN; expect exit 0 and zero failed tests
flutter test test/features/groups/application/group_received_media_action_policy_test.dart
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'GMA-13 announcement member and admin expose core media actions without reply while qa stays excluded'
flutter test test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'GMA-12M group media info includes MIME and conditional dimensions or duration'

# Exact preservation sentinels; expect exit 0
flutter test test/features/groups/application/group_received_media_actions_test.dart --plain-name 'GMA-04 egress reloads exact group owner and delegates only currently eligible media'
flutter test test/features/groups/application/delete_group_media_for_me_use_case_test.dart --plain-name 'GMA-07 delete prepare is exact group scoped atomic and reaction safe'
flutter test test/features/groups/integration/group_received_media_delete_replay_test.dart --plain-name 'GMA-08 self contained journal saga converges per item across every restart boundary'
flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart --plain-name 'IR-020 tombstone prevents replay save and unread resurrection'
flutter test test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'GMA-12 media info redacts storage crypto and transport secrets'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'GMA-11 wired media actions reach only injected coordinators'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'announcement readers stay read-only for compose but still keep reaction entry'

# Curated affected-lane and Go preservation gates
./scripts/run_test_gates.sh groups
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestIsAllowedWriter_AnnouncementMemberBlocked|TestGroupTopicValidator_AnnouncementNonAdminRejected' -count=1)

# Scoped analyzer avoids the accepted repository-wide baseline; expect no issues in Plan-239-owned files
flutter analyze --no-pub \
  lib/features/groups/application/group_received_media_action_policy.dart \
  lib/features/groups/presentation/screens/group_conversation_screen.dart \
  lib/features/groups/presentation/widgets/group_media_info_sheet.dart \
  test/features/groups/application/group_received_media_action_policy_test.dart \
  test/features/groups/presentation/group_conversation_screen_test.dart \
  test/features/groups/presentation/group_conversation_wired_test.dart
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-239-01 fails because the current policy returns no announcement capabilities; TC-239-02 fails under the old GMA-13 exclusion contract; TC-239-03 fails because the Info sheet lacks MIME/dimensions/duration.
- Green sentinels: GMA-01/GMA-04/GMA-07/GMA-08/GMA-11/GMA-12/IR-020/read-only/Go tests remain green and are not relabeled as causal work.
- Pre-existing dirty tree / known failure: preserve unrelated work. Repository-wide `flutter analyze` has an accepted non-zero baseline (Plan 227 recorded 1,624 findings); only the scoped Plan-239 analyzer is a closure gate.
- Environment blocker: none. Existing Plan-227 device proof owns native Save/Share; Plan 239 changes only host-side capability and presentation logic.
- Scope drift: any new coordinator/viewer/delete/reconciler/migration, raw peer-ID display, Q&A action, announcement Reply, Go/libp2p diff, or send/publish call blocks completion.

- [x] TC-239-01 through TC-239-06 have recorded causal/preservation outcomes.
- [x] Member and admin announcement media expose the exact eligible media actions on bubble and viewer; neither exposes Reply.
- [x] Q&A, outgoing, non-visual, direct-owned, and unresolved rows remain excluded.
- [x] Cancel performs zero deletes; confirm reaches the existing delete coordinator exactly once; Save/Share reach only the existing egress controller.
- [x] MIME and conditional dimensions/duration render while all GMA-12 secrets and raw peer IDs remain absent.
- [x] Existing test paths remain registered exactly once in `GROUP_TESTS`; no new harness/device registration is needed.
- [x] Focused tests, sentinels, `groups`, scoped analyzer, and `git diff --check` pass.
- [x] Scope Contract And Guard is respected.

## Handoff

- First causal RED command: `flutter test test/features/groups/application/group_received_media_action_policy_test.dart --plain-name 'GMA-13 announcement member and admin get core media capabilities without reply while qa stays empty'` after adding the test.
- Preservation command: `flutter test test/features/groups/application/group_received_media_actions_test.dart --plain-name 'GMA-04 egress reloads exact group owner and delegates only currently eligible media'`.
- Manual registration: none; all modified test files already occur exactly once in `GROUP_TESTS`, and preflight asserts that contract.
- Migration: none; current DB v98 journal and Plan-235 deletion saga remain unchanged.
- Boundary closure: host-only. No paired device, SQLCipher, relay, or native proof is required.
- Aggregate cadence: no Plan-239 full `host-all`; the announcement core-actions wave and final rollout own aggregate runs.
- Unresolved evidence: none.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-10 | preflight | app_database_version.dart; policy/actions/delete classes; `GROUP_TESTS` | all preflight asserts pass at DB v98; each test file registered exactly once | dirty tree preserved (other live sessions); pathspec-only commit planned | none | causal tests |
| 2026-07-10 | RED | policy test | TC-239-01 `GMA-13` failed: announcement returned `Set:[]` | causal RED confirmed against chat-only guard | none | production edits |
| 2026-07-10 | GREEN | policy, screen overlay, info sheet + 3 test files | TC-239-01/02/03 pass; info-sheet Column overflowed the sheet max height when rows were added → wrapped in `SingleChildScrollView` | member+admin get exactly Save/Share/Info/Delete, no Reply; Q&A empty; MIME/dimensions/duration render | none | mutations + sentinels |
| 2026-07-10 | mutation re-reds | same | chat-only guard restore → TC-239-01 red; raw-`canWrite` media Reply → TC-239-02 red; MIME row omitted → TC-239-03 red; all restored | each causal test kills its mutation | none | sentinels + gates |
| 2026-07-10 | closure | — | GMA-01/04/07/08/11/12 + IR-020 + read-only compose + both Go tests green; `run_test_gates.sh groups` 1311 tests pass; scoped analyzer: 6 findings, all pre-existing baseline (4 `withOpacity` deprecations, 1 duplicate import, 1 null-aware lint — none introduced by this diff); `git diff --check` clean | host-green | none | commit |
