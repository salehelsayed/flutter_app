# Plan 247 Session 02 — Minimum Request, Eligibility, And Dispatch-Time Revalidation

Status: accepted

## Planning Progress

- 2026-07-11 — Evidence Collector completed. Files inspected: current group/message/contact/identity/media models and repository contracts, production repository wiring, received-media/forward policies, in-memory fakes, `GROUP_TESTS`, and the canonical group-gate definition. Decision: current reads support exact group/message/sender/member/contact/group-owner-media checks, but base `getLocalDeletionGroupId` conflates a clear result with unsupported capability; Session 02 must make tombstone authority explicit and deny unknown capability. No simulator/device boundary is owned because this session renders and navigates nothing. Next: draft the narrow RED/GREEN request, policy, resolver, and boundary contract.
- 2026-07-11 — Planner started. Files used: accepted D-247-01..04 contract plus the verified repository/model seams. Decision: constrain production edits to two new group application files plus one narrow domain capability and its truthful production implementation; return only an eligible current contact or one privacy-minimized unavailable result. Next: complete exact tests, mutation proofs, scope guard, and closure commands.
- 2026-07-11 — Planner completed / Reviewer started. Draft contains the complete scope, closure bar, source hierarchy, causal tests, mutation contract, literal gates, known-failure rules, done criteria, scope guard, accepted differences, and dependency handoff. Planner correction: the tombstone seam is now a typed domain capability implemented by the real DB-backed repository, and group archiving is not an eligibility denial. Next: run one anchored counterexample review against callers/bypass risks and arbitrate findings once.
- 2026-07-11 — Reviewer completed / Arbiter started. Graphify review was anchored on `GroupMessageRepositoryImpl` and `getLocalDeletionGroupId`; source counterexamples were checked against the accepted artifact. Reviewer verdict: sufficient with adjustments. Fixed findings: removed unsupported archived-group denial, named the real production three-state tombstone capability path, scoped boundary checks around the pre-existing DB-backed implementation, and added untracked-file scope accounting. No UI, simulator, serialization, or delivery dependency is missing from this session. Next: classify findings and apply the stop rule.
- 2026-07-11 — Arbiter completed. Structural blockers remaining: none. The four reviewer corrections are incorporated, incremental naming/fixture details are bounded by tests and the allowlist, and accepted Session-03 differences remain deferred. Stop rule applied after one review/arbiter pass; this doc is execution-ready for Session 02 only.

## Real Scope

Session 02 adds an unrendered, group-owned application boundary for Plan 247:

- an immutable local `AnnouncementPrivateReplyRequest` containing exactly `sourceMessageId` and `senderPeerId`;
- a pure `AnnouncementPrivateReplyPolicy` for the accepted D-247 eligibility matrix;
- a repository-backed `AnnouncementPrivateReplyResolver` that performs fresh dispatch-time reads and returns either the current eligible `ContactModel` or one privacy-minimized unavailable result;
- a narrow `GroupMessageLocalDeletionAuthority` capability whose result distinguishes `knownClear`, `deleted`, and `unknown`, implemented truthfully by `GroupMessageRepositoryImpl`; and
- three RED-first host tests registered in `GROUP_TESTS`.

This session deliberately does **not** render an action, navigate, dismiss a transient surface, show copy, localize strings, invoke an opener, or change a viewer/bubble. It creates no direct/group send, upload, Forward, payload, serializer, persistence, migration, Bridge, Go, relay, native, or device behavior.

## Closure Bar

The session is complete only when an unrendered caller can submit the two-field request and receive an eligible current contact **only** after the resolver freshly proves all of the following:

1. a complete opener is currently available as an explicit input;
2. the current identity exists and has a non-empty peer ID;
3. the reloaded message exists, exactly matches `sourceMessageId`, has a non-empty `groupId`, exactly matches `senderPeerId`, is incoming, is not self-authored, and is not a `sys-` row;
4. local-deletion authority is known and reports the source clear; `deleted`, a tombstone for any group, and `unknown` all deny;
5. the reloaded group exists under the message's current `groupId`, exactly matches that ID, is `GroupType.announcement`, and is not dissolved;
6. `GroupRepository.getMember(groupId, currentPeerId)` returns the exact current local member; `GroupModel.myRole` alone is never membership authority;
7. an exact current image/video relationship exists for that message under `MediaOwnerLane.group`, with the row's `messageId` and owner rechecked; direct-owner, unresolved-owner, audio/file, missing, and wrong-parent rows deny;
8. `ContactRepository.getContact(senderPeerId)` returns that exact peer and the contact is neither archived nor blocked; and
9. every missing, contradictory, malformed, unsupported, or throwing read fails closed to the same externally safe unavailable result.

The request and the two new application files have no serialization or delivery surface. Repeated resolution re-reads authority rather than caching it. A pending/failed/not-yet-downloaded local attachment may still prove the **visual relationship**; Session 02 must not download it, copy it, require `localPath`, or infer egress eligibility. Existing viewer protection/availability gating remains untouched for Session 03.

## Source Of Truth

Product/privacy authority, in descending order for semantics:

- `Test-Flight-Improv/247-private-reply-decision.md` — accepted D-247-01..04, exact two-field request, fail-closed matrix, and no-cross-lane/no-auto-send boundary;
- `Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-breakdown.md` — Session 02 ownership and Session 03 exclusion;
- `Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan.md` — TC-247-01, TC-247-04, and TC-247-07;
- current code and tests — exact model fields and repository methods; current source wins if stale prose names a method differently;
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` — named-gate and registration source of truth.

Verified current seams:

- `IdentityRepository.loadIdentity()` in `lib/features/identity/domain/repositories/identity_repository.dart`;
- `GroupRepository.getGroup(...)` and `getMember(...)` in `lib/features/groups/domain/repositories/group_repository.dart`;
- `GroupMessageRepository.getMessage(...)` and the ambiguous default `getLocalDeletionGroupId(...)` in `lib/features/groups/domain/repositories/group_message_repository.dart`;
- production tombstone loader wiring in `lib/main.dart` and `GroupMessageRepositoryImpl`;
- `MediaAttachmentRepository.getAttachmentsForMessage(..., owner: MediaOwnerLane.group)`;
- `ContactRepository.getContact(...)` and `ContactModel.isArchived` / `isBlocked`;
- `GroupMessage.groupId`, `senderPeerId`, `isIncoming`, and the established `sys-` system-row convention; and
- `GroupModel.type` and `isDissolved`, plus exact `GroupMember.groupId` / `peerId`.

## Session Classification

`accepted`

Session 01's decision artifact is accepted. Current repositories provide every required read. The only ambiguous read is the optional tombstone default. This plan adds one narrow capability to the existing group-message repository domain contract and implements it in `GroupMessageRepositoryImpl`: a missing DB loader reports `unknown`, a supported loader returning no row reports `knownClear`, and a supported loader returning a row reports `deleted`. The resolver accepts only `knownClear`; it never promotes the legacy default-null method to authority.

No reliability-simulator or device proof is required in Session 02: it changes no rendered flow, navigation, transport, replay, notification, OS callback, or multi-instance behavior. Session 03 and Session 04 own presentation and aggregate host acceptance. This is not permission to claim the user-visible feature complete after Session 02.

## Exact Problem Statement

Plan 247 currently has an accepted product/privacy contract but no typed request or central stale-state security boundary. If presentation work were added now, a bubble or viewer could route using captured sender/message state, confuse absent tombstone support with a clear source, trust `myRole` after membership removal, accept a same-ID attachment from the wrong owner lane, or accidentally gain a serializer/send dependency.

Session 02 must establish one fail-closed, fresh-read resolver before any action is exposed. It must improve only authorization and local target resolution. Announcement read-only behavior, reactions, received-media Save/Share/Info/Delete, normal group Reply, direct conversation delivery, and every visible surface must remain unchanged.

## Files And Repositories To Inspect Next

Executor production allowlist:

- add `lib/features/groups/application/announcement_private_reply_request.dart`;
- add `lib/features/groups/application/announcement_private_reply_policy.dart`;
- narrowly edit `lib/features/groups/domain/repositories/group_message_repository.dart` to declare the typed three-state local-deletion capability; and
- narrowly edit `lib/features/groups/domain/repositories/group_message_repository_impl.dart` so the production implementation reports `unknown` when `dbLoadGroupMessageLocalDeletionFn` is absent, otherwise `knownClear` or `deleted` from that DB-backed closure.

Executor test/registration allowlist:

- add `test/features/groups/application/announcement_private_reply_request_test.dart`;
- add `test/features/groups/application/announcement_private_reply_policy_test.dart`;
- add `test/features/groups/application/announcement_private_reply_transport_boundary_test.dart`;
- edit only the `GROUP_TESTS` array in `scripts/run_test_gates.sh` to register those exact files.

Read-only comparison/preservation inputs:

- `lib/features/groups/domain/models/group_message.dart`;
- `lib/features/groups/domain/models/group_model.dart`;
- `lib/features/groups/domain/models/group_member.dart`;
- `lib/features/groups/domain/repositories/group_repository.dart`;
- `lib/features/identity/domain/repositories/identity_repository.dart`;
- `lib/features/contacts/domain/models/contact_model.dart`;
- `lib/features/contacts/domain/repositories/contact_repository.dart`;
- `lib/features/conversation/domain/models/media_attachment.dart`;
- `lib/features/conversation/domain/repositories/media_attachment_repository.dart`;
- `lib/features/groups/application/group_received_media_action_policy.dart`;
- `test/features/groups/application/group_received_media_action_policy_test.dart`;
- `test/features/groups/application/group_received_media_actions_test.dart`.

No `main.dart` edit is needed: its production `GroupMessageRepositoryImpl` factory already supplies `dbLoadGroupMessageLocalDeletionFn`. A `GroupMessageRepository`-typed caller obtains truthful authority by runtime-checking the new narrow capability implemented by that concrete object. If the object lacks the capability, or the implementation lacks the DB loader, the resolver receives `unknown` and denies. Session 03 must pass the same abstract repository to this resolver; it must not wrap `getLocalDeletionGroupId(...) == null` as `knownClear`.

If implementation evidence requires any existing production file beyond the two repository files named above, stop and reopen this plan. Do not silently grow the allowlist.

## Existing Tests Covering This Area

- `test/features/groups/application/group_received_media_action_policy_test.dart` proves group-lane image/video capability rules and keeps announcement Reply absent. It does not prove Message sender or stale contact/membership qualification.
- `test/features/groups/application/group_received_media_actions_test.dart` proves a locally tombstoned surviving parent blocks existing media egress. It does not distinguish unsupported tombstone authority for Plan 247.
- `test/features/groups/domain/repositories/group_message_repository_impl_test.dart` proves local deletion blocks same-ID replay. It is read-only preservation evidence; the new policy suite will instantiate the real implementation with and without its optional DB loader to pin the new three-state production capability without editing this already-dirty shared test file.
- `test/features/groups/presentation/group_conversation_wired_test.dart` preserves announcement reader read-only/reaction behavior, but Session 02 does not edit or execute the presentation path.
- Current group application tests use `MediaOwnerLane.group` and current repository fakes, but no current test combines identity, live membership, exact parent/sender, tombstone authority, visual relationship, contact state, and opener availability.

The three planned headline files do not yet exist. Their initial RED is expected and must be recorded after the tests are created, not confused with the pre-test file-not-found state.

## Regression / Tests To Add First

Add tests before either production file.

### 1. `announcement_private_reply_request_test.dart`

Named test:

- `private route request is minimum local and non-serializable`

Required proof:

- construct the request from sentinel `sourceMessageId` and `senderPeerId`;
- assert those are its only instance data fields/source-declared payload fields;
- assert no group ID/title, attachment ID/path/bytes, caption/text, sender display data, quote, key/nonce, initial text, Forward marker, or diagnostic seed is retained;
- source-check that the request declares no `toJson`, `fromJson`, `toMap`, `fromMap`, `jsonEncode`, `jsonDecode`, payload adapter, or persistence adapter; and
- prove equality/hash behavior, if supplied, depends on exactly the two accepted fields.

Initial causal RED: the imported request type/file is absent.

### 2. `announcement_private_reply_policy_test.dart`

Named tests:

- `accepted private-reply matrix is exact and fail closed`;
- `resolver re-reads every authority and returns one privacy-minimized result`;
- `unknown tombstone authority and repository errors deny without side effects`;
- `visual relationship does not require a downloaded local copy`.

The exact table must include one fully eligible row and independent denials for:

- empty request IDs;
- missing identity or empty current peer ID;
- missing opener;
- missing message, wrong returned message ID, sender drift, empty sender, wrong/outgoing/self sender, `sys-` row, and wrong/empty group ID;
- deletion state `deleted`, a non-null tombstone naming another group, and `unknown`/unsupported authority;
- missing group, wrong returned group ID, chat/QA type, and dissolved group;
- missing member and a mismatched returned member (proving `getMember`, not `myRole`, is authoritative);
- no attachment, direct/unresolved owner, wrong attachment parent, audio/file, and image/video parity under `MediaOwnerLane.group`;
- missing contact, mismatched contact peer ID, archived contact, and blocked contact; and
- an exception from each read seam collapsing to the same unavailable result.

The eligible table must include pending, failed, and no-local-path image/video variants to prove that Message sender does not initiate or depend on download. The mutable-repository case must resolve eligible once, then mutate one authority (sender drift, membership removal, tombstone, block, group dissolution, and opener loss in representative subcases) and prove a second resolve denies using new reads. The test fixture must record writes/send/upload calls and assert zero.

The same file must instantiate the real `GroupMessageRepositoryImpl` twice with minimal read/write stubs: without `dbLoadGroupMessageLocalDeletionFn` it reports `unknown`; with the closure it maps `null` to `knownClear` and a row to `deleted`. This is the causal production-wiring proof. It must not edit or depend on the shared `group_message_repository_impl_test.dart` fixture.

Initial causal RED: policy/resolver/result/deletion-state types are absent.

### 3. `announcement_private_reply_transport_boundary_test.dart`

Named test:

- `private route adapter is callback-only`.

Required proof over the two new application files plus the narrow repository capability/implementation hunks:

- the two new application files import only the models/repositories needed for read-only qualification;
- the two new application files contain no Flutter presentation/navigation import, `BuildContext`, `Navigator`, route callback invocation, or localization;
- the two new application files contain no `dart:convert`, serializer/map codec, message/payload encoder, DB helper, migration, file/IO, native/platform, Bridge/P2P, Go/relay, send, upload, Forward coordinator, or egress dependency;
- the domain interface hunk adds only the three-state read capability, and the implementation hunk reads only the already-injected `dbLoadGroupMessageLocalDeletionFn`; it adds no DB-helper import, write, fallback, or second source of deletion truth;
- the resolver exposes a result only and invokes no opener; `hasCompleteOpener` is qualification input, not a callback; and
- the request source contains exactly the two accepted identity fields.

Initial causal RED: the boundary cannot find the required production types/files.

### Mutation Re-RED Contract

After GREEN, temporarily apply and revert each representative mutation, recording the named test that turns RED:

1. accept `GroupType.chat` or remove the incoming/system-row guard;
2. skip the reloaded message `groupId` or `senderPeerId` equality check;
3. treat deletion state `unknown` as clear or accept any non-null tombstone;
4. use `group.myRole` instead of an exact current `getMember` result;
5. accept direct/unresolved owner or non-visual attachment;
6. accept archived/blocked/mismatched contact or missing opener;
7. add a third request field or serializer; and
8. add a send/payload/Bridge/Forward/navigation import or call.

No mutation may remain in the worktree.

## Accepted-Decision Coverage Ledger

| Accepted requirement | Session 02 proof | Status after execution |
|---|---|---|
| D-247-01 uses **Message sender**, not Reply | No UI/copy is added; transport-boundary test forbids a presentation action. Exact label remains Session 03. | Intentionally deferred to Session 03 |
| D-247-02 existing active/unblocked current contact only | Policy table + resolver fresh contact lookup, peer equality, archive/block denial | Must be covered |
| D-247-03 two-field local request and blank/no copied context | Request source-shape test + transport boundary; no route is opened in this session | Request portion must be covered; blank composer deferred to Session 03 |
| D-247-04 stale/missing/deleted/member/group/opener states fail closed | Full matrix, unknown-tombstone case, throwing-read cases, and mutation-after-first-resolution case | Must be covered |
| Visual current group-owned image/video relationship | Owner/type/parent table including collisions and image/video parity | Must be covered |
| Existing protection/availability stays fail closed | No viewer/capability edits; local download state is not copied or initiated | Preservation by scope; Session 03 rechecks viewer gating |
| Zero automatic send/upload/Forward/payload | Throwing write spies + source-contract boundary + Go/relay no-diff | Must be covered |
| No durable/cached authorization | No DB/migration/codec and second resolve re-reads mutated repositories | Must be covered |

## Step-By-Step Implementation Plan

1. Record `git status --short` and targeted diffs for every allowlisted existing file before edits. Do not clean, reset, reformat, or absorb unrelated Plan 234/other-agent work.
2. Create the three tests with the exact names and table above. Run each focused file and record causal RED caused by missing request/policy/resolver types.
3. Add `announcement_private_reply_request.dart` with one immutable local request containing exactly two non-serialized strings. Do not accept a raw `GroupMessage`, attachment, map, or context object.
4. In `group_message_repository.dart`, add the narrow three-state `GroupMessageLocalDeletionAuthority` contract. In `GroupMessageRepositoryImpl`, implement it from `dbLoadGroupMessageLocalDeletionFn`: absent closure -> `unknown`; supported closure + null row -> `knownClear`; supported closure + any row -> `deleted`. Preserve the existing nullable method for existing callers; do not reinterpret it.
5. In `announcement_private_reply_policy.dart`, require that capability on the injected abstract `GroupMessageRepository`. A repository that does not implement it, returns `unknown`, or throws must deny. Never add a callback whose implementation can turn the base method's ambiguous null into known-clear.
6. Add a pure policy that checks the fully hydrated current row set. It must use exact ID equality, reject `sys-`, require an announcement group that is not dissolved and an exact local member, require current group-owned image/video relationship, require exact active/unblocked contact, and require opener availability. Do not treat local group archiving as a denial; D-247 only names archived contacts and current membership remains the group authority.
7. Add a resolver using only the six read boundaries: identity, message/deletion capability, group/member, group-owner attachments, and contact. Re-run them on every invocation; catch missing/contradictory/throwing state and return one externally safe unavailable result. Return the current `ContactModel` only on complete eligibility. Do not log peer/source/reason details.
8. Keep download state out of qualification: never call download, never require `localPath`/`downloadStatus == done`, and never invoke integrity/file checks. The shared viewer's current action gating is unchanged and will be composed in Session 03.
9. Make the request, policy, and transport-boundary suites GREEN. Run and record every mutation re-red, reverting immediately after each check.
10. Register the three exact test paths in `GROUP_TESTS` without reordering or formatting unrelated entries. Run completeness-check, exact preservation sentinels, the curated groups gate, pinned Go authorization, analyzer, formatter check, no-diff boundaries, and diff hygiene.
11. Stop at the unrendered eligible-contact result. Do not create an action enum/key/callback, edit a viewer/bubble/wired screen, invoke navigation, add localization, or begin Session 03.

Stop early and re-open planning if the new narrow capability cannot give the abstract repository a truthful production `unknown` / `knownClear` / `deleted` result without a DB helper/schema change, or if eligibility requires any send/route/persistence dependency.

## Risks And Edge Cases

- **Ambiguous tombstone null:** current default `null` cannot prove known-clear. The typed production capability and its absent-loader/clear/deleted tests are mandatory; the resolver must never call the legacy method as authority.
- **Same-ID or stale-row drift:** `getMessage` is by ID only, so returned `id`, `groupId`, and `senderPeerId` must be rechecked before using the derived group/contact.
- **Membership drift:** `GroupModel.myRole` survives some stale shells; exact `getMember(groupId, currentPeerId)` is the authority.
- **Owner-lane collision:** the group-scoped repository call is necessary but not sufficient for a malicious fake; recheck `row.ownerLane` and `row.messageId`.
- **System rows with attachment corruption:** deny any `sys-` parent even if a visual row is present.
- **Download-state coupling:** Message sender is navigation intent, not media egress. Pending/failed/evicted local state must neither trigger download nor seed the route.
- **Privacy leakage through denial detail:** all ineligible/read-error states return the same externally safe unavailable result; detailed source/contact/block facts must not escape in UI-facing text or logs.
- **TOCTOU remains between resolution and navigation:** Session 02 minimizes it with dispatch-time fresh reads but cannot close the final callback boundary. Session 03 must call the resolver immediately before route dispatch, dismiss transient UI first, and coalesce taps.
- **Dirty shared tree:** `scripts/run_test_gates.sh` and some group tests may already contain unrelated work. Patch only the exact registration hunk and compare normal plus whitespace-ignored targeted diffs.

## Exact Tests And Gates To Run

Run in this order from the Flutter repository root.

```bash
# 0. Preserve the shared dirty-tree baseline
git status --short
git diff -- scripts/run_test_gates.sh

# 1. Causal RED after creating tests; each must fail for missing Session-02 types/behavior
flutter test test/features/groups/application/announcement_private_reply_request_test.dart --plain-name 'private route request is minimum local and non-serializable'
flutter test test/features/groups/application/announcement_private_reply_policy_test.dart --plain-name 'accepted private-reply matrix is exact and fail closed'
flutter test test/features/groups/application/announcement_private_reply_transport_boundary_test.dart --plain-name 'private route adapter is callback-only'

# 2. Focused GREEN
flutter test test/features/groups/application/announcement_private_reply_request_test.dart
flutter test test/features/groups/application/announcement_private_reply_policy_test.dart
flutter test test/features/groups/application/announcement_private_reply_transport_boundary_test.dart

# 3. Existing exact preservation sentinels
flutter test test/features/groups/application/group_received_media_action_policy_test.dart --plain-name 'GMA-13 announcement member and admin get core media capabilities without reply while qa stays empty'
flutter test test/features/groups/application/group_received_media_actions_test.dart --plain-name 'GMA-04 locally tombstoned parent refuses single Save and Share even when its row survives'
flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart --plain-name 'local delete still blocks same-id replay'

# 4. Registration and affected curated lane
rg -n 'announcement_private_reply_(request|policy|transport_boundary)_test.dart' scripts/run_test_gates.sh
./scripts/run_test_gates.sh completeness-check
./scripts/run_test_gates.sh groups

# 5. Announcement publication and transport no-change sentinels
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestIsAllowedWriter_AnnouncementMemberBlocked|TestGroupTopicValidator_AnnouncementNonAdminRejected' -count=1)
git diff --exit-code -- go-mknoon go-relay-server

# 6. Scoped static/format/hygiene checks
dart format --output=none --set-exit-if-changed \
  lib/features/groups/application/announcement_private_reply_request.dart \
  lib/features/groups/application/announcement_private_reply_policy.dart \
  lib/features/groups/domain/repositories/group_message_repository.dart \
  lib/features/groups/domain/repositories/group_message_repository_impl.dart \
  test/features/groups/application/announcement_private_reply_request_test.dart \
  test/features/groups/application/announcement_private_reply_policy_test.dart \
  test/features/groups/application/announcement_private_reply_transport_boundary_test.dart
flutter analyze \
  lib/features/groups/application/announcement_private_reply_request.dart \
  lib/features/groups/application/announcement_private_reply_policy.dart \
  lib/features/groups/domain/repositories/group_message_repository.dart \
  lib/features/groups/domain/repositories/group_message_repository_impl.dart \
  test/features/groups/application/announcement_private_reply_request_test.dart \
  test/features/groups/application/announcement_private_reply_policy_test.dart \
  test/features/groups/application/announcement_private_reply_transport_boundary_test.dart
git diff --check

# 7. Scope audit: inspect both forms because formatter churn can hide in -w output
git status --short -- \
  lib/features/groups/application/announcement_private_reply_request.dart \
  lib/features/groups/application/announcement_private_reply_policy.dart \
  lib/features/groups/domain/repositories/group_message_repository.dart \
  lib/features/groups/domain/repositories/group_message_repository_impl.dart \
  test/features/groups/application/announcement_private_reply_request_test.dart \
  test/features/groups/application/announcement_private_reply_policy_test.dart \
  test/features/groups/application/announcement_private_reply_transport_boundary_test.dart \
  scripts/run_test_gates.sh
git diff --stat -- \
  lib/features/groups/application/announcement_private_reply_request.dart \
  lib/features/groups/application/announcement_private_reply_policy.dart \
  lib/features/groups/domain/repositories/group_message_repository.dart \
  lib/features/groups/domain/repositories/group_message_repository_impl.dart \
  test/features/groups/application/announcement_private_reply_request_test.dart \
  test/features/groups/application/announcement_private_reply_policy_test.dart \
  test/features/groups/application/announcement_private_reply_transport_boundary_test.dart \
  scripts/run_test_gates.sh
git diff -w --stat -- \
  lib/features/groups/application/announcement_private_reply_request.dart \
  lib/features/groups/application/announcement_private_reply_policy.dart \
  lib/features/groups/domain/repositories/group_message_repository.dart \
  lib/features/groups/domain/repositories/group_message_repository_impl.dart \
  test/features/groups/application/announcement_private_reply_request_test.dart \
  test/features/groups/application/announcement_private_reply_policy_test.dart \
  test/features/groups/application/announcement_private_reply_transport_boundary_test.dart \
  scripts/run_test_gates.sh
```

Mutation commands are intentionally not prescribed as a bulk script: apply one minimal mutation, run its named focused test, record RED, and revert only that mutation with `apply_patch`. Never use `git checkout`, `git reset`, or a destructive cleanup in this dirty tree.

Per project cadence, do **not** run full `host-all` in Session 02. Do not run `feature-host-all`, the 1:1 gate, or reliability-sim here: no UI/direct route exists yet, and Session 04 owns aggregate Plan-247 host closure. The affected curated `groups` gate remains required.

## Known-Failure Interpretation

- Capture the exact pre-edit dirty-tree inventory and do not attribute unrelated Plan 234, Plan 254, Graphify, localization, database, or group-send changes to Session 02.
- A test-file-not-found before the test is created is intake evidence only; causal RED begins after the test exists and imports/asserts the missing Session-02 contract.
- If a focused new test fails after implementation, it is a Session-02 blocker.
- If an existing sentinel or the groups gate fails, rerun the exact failing file/test. Classify it as pre-existing only when it reproduces without Session-02 files/registration influencing the command and current baseline evidence identifies the same failure. Do not edit unrelated production to make the gate green.
- A groups-gate failure in a concurrently edited dirty file is not automatically pre-existing. Record command, test name, first failure, and targeted diff ownership; coordinate rather than overwriting another agent.
- Any Go authorization failure, Go/relay diff, analyzer error in an allowlisted file, registration omission, or formatter/diff-hygiene failure blocks acceptance.
- Unavailable simulator/device targets are irrelevant rather than blockers because no device leg is required for this unrendered host-only session.

## Done Criteria

- [x] `AnnouncementPrivateReplyRequest` contains exactly `sourceMessageId` and `senderPeerId` and has no codec/payload/persistence form.
- [x] The typed deletion-authority capability distinguishes `knownClear`, `deleted`, and `unknown`; the real `GroupMessageRepositoryImpl` reports loader absence as unknown, and only known-clear can qualify.
- [x] Pure policy and resolver cover every closure-bar fact, use exact current IDs, and return only current eligible contact or one privacy-minimized unavailable result.
- [x] Resolver invocation re-reads identity, parent, deletion authority, group, exact local member, group-owner visual relationship, and contact; repository errors fail closed.
- [x] Pending/failed/no-local-path visual rows prove no download requirement or side effect, while direct/unresolved/non-visual/wrong-parent rows deny.
- [x] All three causal suites pass and every listed representative mutation re-reds.
- [x] Existing announcement no-Reply, tombstone egress, and repository replay sentinels pass.
- [x] The three test files are present in `GROUP_TESTS`; completeness-check and `./scripts/run_test_gates.sh groups` pass.
- [x] Pinned Go authorization passes and Go/relay remain unchanged.
- [x] Scoped analyzer, formatter, `git diff --check`, and normal/`-w` scope audits pass under the recorded five-info analyzer interpretation.
- [x] `git status --short` accounts for the three new untracked tests and two new untracked application files in addition to tracked hunks; no untracked out-of-scope file is misclassified as an empty diff.
- [x] No presentation/viewer/localization/navigation/send/upload/Forward/serializer/DB helper/schema/migration/native/relay file is changed by this session; repository edits are limited to the typed capability and its truthful implementation.
- [x] Plan 247 remains implementation-in-progress and the user-visible action remains absent. Session 02's dependency is closed; Session 03 remains serialization-blocked on Plan-234 shared capability/viewer work.

## Scope Guard

Allowed production behavior is only local read qualification and an unrendered eligible-contact result.

Forbidden in Session 02:

- `GroupConversationScreen`, `GroupConversationWired`, context overlay, typed viewer, viewer item/action enum, Feed/Orbit/group-entry surfaces, or `main.dart` wiring edits;
- action keys, labels, icons, tooltips, feedback, localization ARB/generated output, semantics, layout, or RTL work;
- `Navigator`, route construction, transient-surface dismissal, opener callback invocation, double-tap/coalescing UI state, or direct `ConversationWired` construction;
- `sendChatMessage`, `sendGroupMessage`, upload, retry, Forward, egress, download, file hashing, payload/envelope, Bridge/P2P, Go/relay, notification, or native/platform calls;
- database version/schema/migration/helper/model persistence or durable draft/cache;
- changing existing Reply, reaction, announcement publication, Save/Share/Info/Delete, shared viewer protection, or lifecycle behavior; and
- editing any repository surface beyond the named narrow domain capability and its `GroupMessageRepositoryImpl` implementation, or editing shared fakes to make unknown deletion state look clear.

Overengineering includes a generic cross-lane router, serialized provenance, a new service locator/DI framework, new cache, generalized contact-introduction flow, reason-rich telemetry, or any production file beyond the four-file allowlist without new evidence. If one becomes necessary, stop and re-plan.

## Accepted Differences / Intentionally Out Of Scope

- Exact **Message sender** copy, localization, semantics, bubble/viewer placement, current-page dispatch, overlay dismissal, route error feedback, and double-tap coalescing belong to Session 03.
- Opening the fully wired blank 1:1 composer and proving route return state belong to Session 03; Session 02 invokes no opener.
- A route can still become stale in the final instructions between resolution and navigation. Session 03 minimizes that final interval by resolving immediately before dispatch; no durable lock is introduced.
- Shared viewer availability/protection can suppress its action even though the resolver's visual-relationship check does not require a downloaded file. This is intentional composition, not an eligibility contradiction.
- Session 02 does not add lifecycle schema/policy for announcement media; Plans 238/242 and the shared viewer remain authoritative for those later capabilities.
- 1:1 transport delivery, reporting, internal Forward, and private-media lifecycle are separate plans and are not approximated here.

## Dependency Impact

- Depends on accepted Session 01 decision artifact; changing D-247-01..04 reopens this plan.
- Successful closure satisfies Plan 247 Session 03's logical dependency on this resolver. Session 03 must call it immediately before navigation and must not duplicate or weaken its matrix; execution remains serialization-blocked on Plan-234 shared capability/viewer ownership.
- Session 03 obtains tombstone authority by passing its existing abstract `GroupMessageRepository` to the resolver. Production's object is `GroupMessageRepositoryImpl`, which implements the typed capability from the already-wired DB loader. Non-capable and loader-less repositories remain unavailable. Session 03 is explicitly forbidden from wrapping the ambiguous legacy nullable method as known-clear.
- Session 03 must refresh against landed Plan 234 viewer/protection changes before editing shared viewer files. Session 02 avoids that conflict entirely.
- Session 04 owns feature-host-all/1:1 preservation and closure-document synchronization after the UI slice lands.
- No migration number, native contract, wire contract, Go/relay contract, or device topology is reserved by this session.

## Reviewer Pass

Verdict: **sufficient with adjustments**, with all required adjustments incorporated.

- Missing files/tests/gates: none after adding the typed repository-capability files, real implementation proof inside the policy suite, all three headline registrations, the groups gate, and the pinned Go/no-diff sentinels.
- Stale/incorrect assumption fixed: the accepted artifact does not make `GroupModel.isArchived` a denial. Current membership plus announcement type, existence, and non-dissolution are the group checks.
- Critical bypass fixed: the legacy default-null tombstone method is not authority. Production truth comes from the typed capability on `GroupMessageRepositoryImpl`; loader absence/non-capable repositories return unknown and deny.
- Boundary-test false positive fixed: strict no-DB/no-IO scanning applies to the new application files, while the repository implementation hunk may read only its pre-existing injected tombstone loader.
- Dirty-tree gap fixed: scope audit now includes `git status` so untracked new files cannot disappear from `git diff --stat` evidence.
- Overengineering check: four production files are the minimum coherent set once truthful production tombstone capability is required. No generic router, DI layer, cache, serializer, UI abstraction, or repository-wide redesign is planned.
- Decomposition check: Session 02 stops at an unrendered eligible-contact result; every presentation/navigation concern remains in Session 03.
- Simulator check: no simulator gate is required because this session has no rendered route, transport, notification, replay, OS, or multi-instance behavior. Host proof is causal for these pure/repository-backed reads.

## Arbiter Decision

### Structural Blockers Remaining

None.

The review's structural findings were patched once: accepted group eligibility now matches D-247 exactly, deletion authority has a truthful production path, the source-contract boundary is executable, and dirty untracked files are auditable. A final arbiter pass found no new structural blocker, so the stop rule applies.

### Incremental Details Intentionally Deferred

- Exact private helper names and fixture construction style may vary if the public two-field request, three-state capability, resolver result, and test names remain exact.
- Test data builders may be local to the three new files; shared fake cleanup or generalization is not justified.
- Additional denial-reason telemetry is intentionally omitted, not postponed for this session.

### Accepted Differences Intentionally Left Unchanged

- Session 02 proves authorization and target resolution, not the visible **Message sender** action or blank-composer route.
- Local download completion is not a prerequisite for this cross-lane navigation resolver; viewer protection/availability remains an independent Session-03 gate.
- Final route-time coalescing and the last navigation TOCTOU interval remain Session-03 responsibilities.
- Full `host-all` remains a wave/final closure gate, not a Session-02 gate.

## Execution Handoff

- Start with the three RED tests exactly as named above; do not begin with production files.
- Preserve and compare the current dirty-tree baseline, especially the existing `scripts/run_test_gates.sh` and shared repository-test changes.
- Stop after the unrendered resolver passes focused, mutation, preservation, groups, Go/no-diff, analyzer, format, and scope gates.
- On acceptance, update only Session 02's plan/breakdown/source progress, record Session 03's logical dependency as satisfied, preserve its Plan-234 serialization block, and do not claim Plan 247 or the user-visible feature complete.

## Execution Result — 2026-07-11

Executor verdict before independent review: **implementation complete**. The
initial QA blockers, bounded fix pass, and final accepted verdict are recorded
below; this never claims the user-visible Plan-247 action is complete.

### Dirty-tree preservation and implemented scope

- The pre-edit tree already contained concurrent Plan-234 production/tests,
  `scripts/run_test_gates.sh` one-to-one registrations, group-send tests, plan
  docs, Graphify outputs, and unrelated local files. Nothing was cleaned,
  reset, checked out, or attributed to Session 02.
- Added only the two allowed application files:
  `announcement_private_reply_request.dart` and
  `announcement_private_reply_policy.dart`.
- Narrowly added `GroupMessageLocalDeletionState` plus
  `GroupMessageLocalDeletionAuthority` to
  `group_message_repository.dart`, and implemented that capability from the
  already-injected `dbLoadGroupMessageLocalDeletionFn` in
  `GroupMessageRepositoryImpl`.
- Added only the three allowed tests and their exact `GROUP_TESTS`
  registrations. The existing Plan-234 `ONE_TO_ONE_TESTS` hunk in the same
  script was preserved unchanged.
- No presentation, viewer, navigation, localization, `main.dart`, send,
  upload, Forward, payload, database helper/schema/migration, Bridge, native,
  Go, or relay production file was edited by this session.

### RED-first and focused GREEN evidence

- `announcement_private_reply_request_test.dart` first failed because the
  request file/type did not exist.
- `announcement_private_reply_policy_test.dart` first failed because the
  policy/resolver/result/deletion-authority types did not exist.
- `announcement_private_reply_transport_boundary_test.dart` first failed with
  a file-not-found error for the required application boundary after its own
  matcher-shape intake error was corrected; that file-not-found run is the
  recorded causal RED.
- Post-implementation combined focused run: **6/6 passed** — one request test,
  four policy/resolver tests, and one strengthened transport-boundary test.
- The boundary test now rejects repository mutation-call patterns for
  `save*`, `update*`, `delete*`, `remove*`, `addContact`, `archive*`,
  `unarchive*`, `mark*`, `send*`, `upload*`, and `forward*`, in addition to
  presentation/navigation/serialization/transport dependencies. This closes
  the swallowed-write-exception counterexample in denial paths.

### Mutation re-RED evidence

Each mutation was applied alone, turned the named focused test RED, and was
immediately reverted with `apply_patch`:

1. Accepting `GroupType.chat` failed `accepted private-reply matrix is exact and fail closed` at the chat-group row.
2. Removing exact `senderPeerId` equality failed the same matrix at sender drift.
3. Treating `unknown` deletion authority as clear failed the same matrix at unknown authority.
4. Removing exact member group/peer checks failed the same matrix at the mismatched-member row.
5. Removing the group-owner check failed the same matrix at the direct-owner collision row.
6. Accepting archived contacts failed the same matrix at the archived-contact row.
7. Adding a third request field failed `private route request is minimum local and non-serializable`.
8. Adding a group-send dependency failed `private route adapter is callback-only` at the import allowlist.

The final post-mutation focused run returned to **6/6 passed**.

### Preservation, registration, and curated gate evidence

- Existing announcement no-Reply sentinel passed:
  `GMA-13 announcement member and admin get core media capabilities without reply while qa stays empty`.
- Existing tombstoned-parent egress sentinel passed:
  `GMA-04 locally tombstoned parent refuses single Save and Share even when its row survives`.
- Existing repository replay sentinel passed:
  `local delete still blocks same-id replay`.
- All three new files are present in `GROUP_TESTS` at the exact registered
  paths.
- `./scripts/run_test_gates.sh completeness-check` passed **1160/1160**.
- The first two canonical groups attempts each exposed the same aggregate-only
  pre-existing flaky timing expectation in the already-dirty
  `group_conversation_wired_test.dart`: line 9879,
  `expect(uploadCompleted, hasLength(2))`, observed `Actual: []` in
  `cancel on the active upload banner restores composer state and terminalizes durable pending rows`.
  The exact named test passed immediately in isolation. No out-of-scope test or
  production change was made.
- The required final canonical retry passed **1932/1932** in 1m21s. Its bundled
  group-forwarding Go bridge sentinels also passed for `go-mknoon/bridge` and
  `go-mknoon/node`.
- The separately pinned announcement authorization command passed:
  `go test ./node -run 'TestIsAllowedWriter_AnnouncementMemberBlocked|TestGroupTopicValidator_AnnouncementNonAdminRejected' -count=1`.
- `git diff --exit-code -- go-mknoon go-relay-server` passed.

### Static, format, scope, and architecture evidence

- `dart format --output=none --set-exit-if-changed` passed for all seven Dart
  files with zero changes.
- The default scoped `flutter analyze` command exits 1 solely because five
  existing `prefer_initializing_formals` info lints remain in untouched
  constructor lines of `group_message_repository.dart`. The same exact scope
  with `--no-fatal-infos` exits 0 with no errors or warnings; the three new
  test/application files have no analyzer issues.
- `bash -n scripts/run_test_gates.sh`, `git diff --check`, normal targeted diff
  stat, and whitespace-ignored targeted diff stat all passed.
- Scope accounting shows exactly two modified repository files, two new
  application files, three new test files, and the exact shared-script
  registration hunk. The normal and `-w` tracked stats are identical: 39
  inserted tracked lines across the two repositories and shared script, of
  which 32 are Session-02-owned and seven are the preserved pre-edit Plan-234
  script hunk. The five intended new untracked files are explicitly present in
  `git status`.
- Graphify affected-context review was run for the four production files, then
  `./graphify-arch/refresh_arch_graph.sh --incremental` completed once:
  47,118 nodes, 73,261 edges, and refreshed TDD overlay.

### Remaining boundary

Session 02 stops at the unrendered eligible-contact result. No device or
simulator leg is applicable. Session 03 remains responsible for the visible
**Message sender** action, localization, transient-surface dismissal,
coalescing, and opening a blank direct composer immediately after this fresh
resolver. Plan 247 remains implementation-in-progress until those later
sessions and independent closure complete.

### Independent QA fix pass 1 — 2026-07-11

Status after bounded fix pass: **implementation corrected; independent QA rerun
accepted**. No Session-03 implementation was entered.

QA's three blocking counterexamples and one evidence correction were addressed
within the existing production/test allowlist:

- Success result construction is now library-private through
  `AnnouncementPrivateReplyResolution._available`; the public surface exposes
  only the single unavailable value and read-only result data. The boundary
  suite enumerates every result constructor, requires `_available` and
  `_unavailable`, requires every constructor name to be private, and forbids a
  public static `available`/`success` minter.
- Both request-shape suites now enumerate all two-space instance `final`
  declarations independently of field type, reject multi-field declarations,
  require length two, and require exactly `sourceMessageId` plus
  `senderPeerId`.
- Request sender, reloaded message sender, and current identity peer IDs now
  pass through `groupMemberPeerIdRejectReason` before authorization-derived
  reads. Edge whitespace and embedded control/DEL variants deny. Source-message
  and group IDs additionally use a conservative local canonical-ID check that
  rejects empty, edge-whitespace, control, and DEL values before they can seed
  repository qualification.
- Analyzer evidence is recorded truthfully: default scoped analyze exits 1 on
  exactly five pre-existing info lints; the identical command with
  `--no-fatal-infos` exits 0 and reports no errors or warnings.

Fix-pass RED/counterexample evidence:

1. The new boundary proof failed RED against the prior public
   `AnnouncementPrivateReplyResolution.available` constructor.
2. Adding a third `final int qaBypass` field turned both request-shape suites
   RED with three fields found; the mutation was reverted.
3. Replacing peer-ID canonical qualification with trim-only emptiness checks
   turned the exact matrix RED at `request sender with edge whitespace`; the
   mutation was reverted.
4. Replacing local source/group canonical qualification with trim-only
   emptiness turned the exact matrix RED at `source id with edge whitespace`;
   the mutation was reverted.
5. Re-exposing the success constructor publicly turned the transport boundary
   RED; the mutation was reverted.

Final fix-pass evidence:

- Combined focused request/policy/transport run: **6/6 passed**.
- `./scripts/run_test_gates.sh completeness-check`: **1163/1163 passed**; the
  inventory increased by three concurrent Plan-234 tests without losing the
  three Plan-247 registrations.
- The first final-code groups attempt encountered a concurrent Plan-234
  half-edit: missing
  `DirectPrivateMediaCleanupRepository.deleteDirectPrivateMediaEncryptionKeyWithinLock`
  caused one compile failure and one secondary compiler-exited load failure
  (**1930 passed / 2 failed**). No Plan-234 file was touched here. Once its
  owner restored interface/implementation/call coherence, the exact focused
  `media_eviction_redownload_test.dart` compiled and passed **2/2**.
- The unchanged final-code `./scripts/run_test_gates.sh groups` retry passed
  **1932/1932** in 1m17s, including the bundled `go-mknoon/bridge` and
  `go-mknoon/node` forwarding sentinels.
- Default scoped analyze: exit 1, exactly five pre-existing info lints and zero
  errors/warnings. Scoped `--no-fatal-infos`: exit 0 with the same five infos.
- Formatter check changed zero files; `bash -n`, `git diff --check`, Go/relay
  no-diff, normal scope stat, and whitespace-ignored scope stat all passed.
- Final Graphify affected-context review and one incremental refresh completed:
  **47,168 nodes, 73,348 edges**, 1,256 test files, 12,254 named tests, and 950
  production targets in the refreshed TDD overlay.

## Final Accepted Verdict — 2026-07-11

Verdict: **accepted** with zero independent-QA blockers after fix pass 1.

Independent post-fix QA verified all three corrected counterexamples, reran the
three focused files at **6/6**, confirmed formatter cleanliness, and confirmed
that scoped analysis has no errors or warnings (the default command remains
non-zero only for the five recorded pre-existing info lints). QA also passed
the current completeness inventory at **1164/1164** and accepted the persisted
final groups evidence at **1932/1932**.

What is closed in Session 02:

- the exact two-field, local-only, non-serializable request;
- the private success-result mint and single privacy-minimized unavailable
  result;
- canonical identifier, current identity, parent, sender, tombstone, group,
  membership, group-owned visual relationship, contact, and opener
  qualification;
- fresh resolver reads, exception denial, zero write/send/upload/Forward side
  effects, and truthful production tombstone authority; and
- focused, mutation, preservation, registration, groups, Go/no-diff, analyzer,
  formatter, and scope evidence for this unrendered boundary.

Accepted differences and still-open work:

- Session 02 intentionally renders and navigates nothing. Exact **Message
  sender** UI, localization, blank direct-route opening, current-viewer-item
  dispatch, overlay dismissal, coalescing, and route feedback remain Session
  03 scope.
- Plan 247 therefore remains implementation-in-progress. Session 03's logical
  dependency on Session 02 is satisfied, but its execution remains explicitly
  serialization-blocked until Plan 234 releases the shared capability/viewer
  files and its protection sentinels can be refreshed without concurrent edit
  overlap. Session 04 remains blocked on Session 03.

Maintenance/reopen rule: reopen Session 02 only for a real regression in the
minimum request shape, canonical/fresh eligibility matrix, tombstone authority,
privacy-minimized result boundary, no-side-effect contract, or its registered
focused/groups proof. Presentation or route work does not reopen Session 02;
it proceeds through Sessions 03–04 after the serialization guard clears.
