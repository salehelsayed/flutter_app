# Plan 247 — Announcement Media Private Reply Routing Session Breakdown

Status: accepted

## Decomposition Progress

- 2026-07-11 — Evidence Collector intake: inspected `Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan.md`, the current dirty-worktree inventory, and the intended adjacent breakdown path. At intake the source was evidence-gated and the decision artifact was absent; the Session-01 row below supersedes that state.
- 2026-07-11 — Evidence Collector: an anchored Graphify TDD query identified `GroupConversationScreen`, `GroupConversationWired`, `GROUP_TESTS`, the shared typed viewer, and the Feed/Orbit/group-entry callers. Current source confirms callback-only viewer dispatch, current contact/group/message reload seams, five `GroupConversationWired` construction sites, and no private-route action or typed opener.
- 2026-07-11 — Closure Mapper: Wave-1 authority resolves D-247-01..04 conservatively: the action is **Message sender**, uses an existing active/unblocked contact only, opens a blank existing 1:1 composer, copies no source context, and fails closed for stale/ineligible state. No database, wire, Bridge, Go, relay, or device boundary is owned.
- 2026-07-11 — Session Splitter: split accepted decision persistence, pure eligibility/revalidation, presentation/entry-surface wiring, and aggregate acceptance/closure. This keeps the unrendered policy slice independently safe and isolates shared-viewer conflict handling from the application contract.
- 2026-07-11 — Reviewer / Arbiter: four sessions are the minimum safe set. No structural blocker remains. The in-flight Plan 234 overlap is explicit and must be refreshed before Session 03; it is an execution-order/conflict guard, not a product blocker.
- 2026-07-11 — Session 01 accepted: created `247-private-reply-decision.md` with literal D-247-01..04 answers, exact EN/DE/AR copy, allow/deny and revalidation rules, and the blank-composer/no-auto-send boundary. Synchronized the source plan without changing code or tests. At that closure point Session 02 became execution-ready; Sessions 03–04 remained dependency-blocked.
- 2026-07-11 — Session 02 accepted after one bounded QA fix pass: minimum request, fail-closed resolver/policy, truthful three-state tombstone authority, canonical identifier checks, and callback/transport boundary landed with post-fix independent QA at zero blockers. Focused proof is 6/6, completeness is 1164/1164, and the persisted groups verdict is 1932/1932. Session 02 is closed; Session 03's logical dependency is satisfied but execution remains serialization-blocked on Plan-234 shared capability/viewer ownership.
- 2026-07-12 — Session 03 accepted after one proof-only QA fix pass and zero behavior-fix passes. The callback-only bubble/viewer/app-owner route, exact-current revalidation, blank real direct route, five-site opener census, localization, protection preservation, proportional family gates, exact scope manifest, accepted QA, exactly one post-QA incremental Graphify refresh, and separate closure review are closed. Session 04 alone is execution-ready.
- 2026-07-12 — A Session-04 formatter check concretely reopened Session 03 for four compatibility fixtures. The bounded formatting-only repair changed no tokens, assertions, behavior, symbols, names, or registrations; exact affected proof passed 34/34 and independent repair QA accepted at separate `post_closure_fix_passes=1` / behavior-fix count 0. Historical Session-03 `fix_passes=1` remains unchanged and no new Graphify refresh was required.
- 2026-07-12 — Session 04 accepted after fresh focused/preservation evidence, groups 1,951 plus inherited Go, current 1to1 1,977, current feature-host inventory 754 by supported segmented completion plus a 282-test current delta, completeness 1,185, host inventory 89, static/scope proof, independent QA, exact immutable equality, and separate closure review. Plan 247 is accepted/closed; final Wave-1 owns full host-all, availability-bounded device proof, and the final Graphify refresh.

## Recommended Plan Count

Create **4** doc-scoped session plans.

## Decomposition Artifact

- Artifact: `Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-breakdown.md`
- Source: `Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan.md`
- Downstream rule: plan, execute/QA, and close one session at a time. Before planning or executing a later session, refresh its exact files/tests against landed earlier sessions and the then-current Plan 234 shared-viewer work.

## Overall Closure Bar

An announcement recipient can deliberately choose **Message sender** from an eligible incoming announcement media message and reach the sender's already-supported, fully wired 1:1 conversation with an empty composer. Merely choosing the action sends, uploads, forwards, copies, or serializes nothing; it does not alter the announcement or either conversation history.

The action is absent unless the current source row is an incoming, non-deleted announcement media message, the source sender is not self, the current contact row exists and is active (`!isArchived`) and unblocked, the local user still has the source announcement, and a complete app-owner opener is available. Invocation re-loads the group, message, identity, contact, local-deletion authority, and media relationship and fails closed if any fact changed. Unknown, archived, blocked, self/outgoing, deleted/stale, dissolved/left/deleted/unavailable-group, missing-opener, and route-failure cases never auto-add, introduce, unblock, send, upload, forward, or copy context.

Announcement read-only publishing and reactions stay unchanged. The implementation adds no migration, durable draft, message/payload field, Bridge/P2P call, Go/relay behavior, or device-only contract.

## Accepted Decision Contract For Session 01

Session 01 acceptance required `Test-Flight-Improv/247-private-reply-decision.md` with the literal line `Status: accepted` and explicit accepted rows for every decision. That artifact now exists and contains:

| Decision | Accepted Wave-1 answer |
|---|---|
| D-247-01 — label and expectation | The user-facing action is **Message sender**. It is not named Reply or Reply privately and must not imply a same-thread or quoted relationship. Localized semantics: English `Message sender`; German `Absender anschreiben`; Arabic `مراسلة المرسل`. |
| D-247-02 — sender eligibility | Only a current existing `ContactModel` for the reloaded `senderPeerId` qualifies, and only when `isArchived == false`, `isBlocked == false`, the sender is not the current identity, the source message is incoming, and the complete opener is available. Never auto-add, start an introduction/contact request, unarchive, or unblock. |
| D-247-03 — context crossing | Open the existing fully wired direct conversation with a blank composer: no `initialText`, caption, media, attachment id/path/bytes, quote id, group id/title, source label, sender display metadata, key/nonce, or hidden diagnostic seed crosses into the direct draft/payload. The local typed request carries only the minimum stale-check identity selected by the source plan (`sourceMessageId` and `senderPeerId`) and has no JSON/wire serializer. |
| D-247-04 — exceptional states | Fail closed for self/outgoing, a missing/changed/deleted/tombstoned source, a non-announcement or unavailable/dissolved/deleted/left group, a missing local membership, unknown/archived/blocked contact, missing opener, or opener/route failure. Before render these states hide the action. If state becomes stale after the menu opens, dismiss the transient surface, open no route, and show privacy-minimized localized unavailable feedback; route failure shows localized open-failure feedback. |

Additional accepted invariants:

- Eligibility requires a current visual media relationship for the source message under `MediaOwnerLane.group`; a text-only row cannot gain the action.
- Local download state is not used as an excuse to transfer media or seed the direct route. Existing shared-viewer protection/availability gates remain fail-closed and are not weakened by Plan 247.
- Navigation is terminal for this action. It never invokes `sendChatMessage`, `sendGroupMessage`, an upload, Forward coordinator, Bridge command, or payload encoder.
- No `quotedMessageId`, forwarded marker, source message id, or group context is written into direct history.
- Session 01 recorded the accepted answers in the source plan and reclassified Session 02 as executable; Sessions 03–04 retain their actual dependency blocks.

## Source Of Truth

Product and closure intent:

- `Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan.md`
- This Wave-1 accepted decision contract
- `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`
- `Test-Flight-Improv/13-announcement-use-case-audit.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`

Current production seams:

- `lib/features/groups/application/group_received_media_action_policy.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/conversation/presentation/widgets/message_context_overlay.dart`
- `lib/shared/widgets/media/media_viewer_item.dart`
- `lib/shared/widgets/media/full_screen_typed_media_viewer.dart`
- `lib/features/contacts/domain/models/contact_model.dart`
- `lib/features/contacts/domain/repositories/contact_repository.dart`
- `lib/features/identity/domain/repositories/identity_repository.dart`
- `lib/features/groups/domain/repositories/group_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `lib/features/groups/presentation/screens/group_list_wired.dart`
- `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
- `lib/main.dart`
- `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`, `lib/l10n/app_ar.arb` and generated localization outputs

Current preservation evidence and gate ownership:

- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/conversation/presentation/widgets/message_context_overlay_test.dart`
- `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart`
- `test/shared/widgets/media/media_viewer_boundary_test.dart`
- `test/l10n/l10n_integrity_test.dart`
- `scripts/run_test_gates.sh` (`GROUP_TESTS`, conditional `ONE_TO_ONE_TESTS`)
- `scripts/run_host_test_gates.sh` (`feature-host-all`)

## Session Ledger

| Session | Title | Classification | Intended plan file | Depends on | Current status |
|---|---|---|---|---|---|
| 01 | Accept the private-route product/privacy contract | evidence-gated | `Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-01-plan.md` | none | accepted |
| 02 | Add minimum request, eligibility, and dispatch-time revalidation | implementation-complete | `Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-02-plan.md` | 01 | accepted |
| 03 | Wire Message sender through bubble, viewer, and app-owner routes | implementation-complete | `Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-03-plan.md` | 02 accepted; Plan 234 shared capability/viewer work closed | accepted |
| 04 | Run host acceptance and synchronize closure records | acceptance-only | `Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-04-plan.md` | 03 accepted | accepted |

## Ordered Session Breakdown

### Session 01 — Accept the private-route product/privacy contract

- Session id: `01`
- Classification: `evidence-complete`
- Execution status: `accepted` on 2026-07-11; the action remains absent from production.
- Intended plan file: `Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-01-plan.md`
- Completed scope:
  - Created `Test-Flight-Improv/247-private-reply-decision.md` with `Status: accepted` and the complete D-247-01..04 table above.
  - Recorded exact EN/DE/AR action and failure copy semantics, the allow/deny matrix, the blank-composer/minimum-request contract, revalidation timing, and the no-auto-send/no-cross-lane-data boundary.
  - Updated Plan 247's former decision-blocker section, test notes, implementation steps, handoff, status/classification, and execution progress so no decision placeholder remains.
  - Edited no production code or tests in this session.
- Why its own session: downstream tests and UI copy would be vacuous or misleading without a persisted, reviewable cross-lane privacy contract.
- Likely code-entry files: none.
- Direct tests/proof:
  - `test -s Test-Flight-Improv/247-private-reply-decision.md`
  - `rg -x 'Status: accepted' Test-Flight-Improv/247-private-reply-decision.md`
  - exact presence checks for all four accepted decision identifiers.
  - accepted-artifact hygiene checks for stale decision-placeholder vocabulary.
- Named gates: none; documentation evidence only.
- Matrix/closure docs: source Plan 247 and the new decision doc.
- Dependency: none.
- Meaningful verified end state: all behavior is testable from one accepted artifact while the action remains absent from production.

### Session 02 — Add minimum request, eligibility, and dispatch-time revalidation

- Session id: `02`
- Classification: `implementation-complete`
- Execution status: `accepted` on 2026-07-11 after one bounded QA fix pass and an independent post-fix QA verdict with zero blockers.
- Intended plan file: `Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-02-plan.md`
- Completed scope: exact two-field non-serializable request; private success-result mint; fail-closed policy/resolver with canonical identifier, identity, parent/sender, tombstone, announcement, membership, group-owned visual relationship, active-contact, and opener checks; truthful `unknown`/`knownClear`/`deleted` production tombstone capability; zero write/navigation/transport side effects; and three `GROUP_TESTS` registrations.
- Accepted evidence: focused 6/6; all recorded mutations re-RED and reverted; preservation/Go/no-diff/static/scope checks green; independent QA completeness 1164/1164; persisted final groups gate 1932/1932.
- Exact scope:
  - Add a group-owned `AnnouncementPrivateReplyRequest`/equivalent with only `sourceMessageId` and `senderPeerId`; deliberately provide no `toJson`, payload, message, Bridge, or persistence representation.
  - Add one pure eligibility policy plus a repository-backed resolver/coordinator that re-loads current identity, group, local membership, message, deletion authority, group-owned visual attachment relationship, and contact immediately before returning an eligible direct-route target.
  - Deny every D-247-04 row, sender drift, message/group mismatch, self, outgoing, text-only, archived/blocked/unknown contact, and unavailable opener state.
  - Return an eligible current contact or a privacy-minimized denial reason; perform no navigation and import no send/upload/forward/transport seam.
  - Add request/policy/transport-boundary RED-first tests and mutation re-red checks.
- Why its own session: this is the causal security boundary. It can land unrendered, provides an independently verified fail-closed state, and prevents presentation code from reimplementing stale-state checks.
- Likely code-entry files:
  - new `lib/features/groups/application/announcement_private_reply_request.dart` (or one equivalently narrow typed file)
  - new `lib/features/groups/application/announcement_private_reply_policy.dart`
  - existing repository interfaces only if a conservative read default is genuinely missing; no database implementation change
- Likely direct tests/regressions:
  - `test/features/groups/application/announcement_private_reply_policy_test.dart`
  - `test/features/groups/application/announcement_private_reply_request_test.dart`
  - `test/features/groups/application/announcement_private_reply_transport_boundary_test.dart`
  - table rows for current/non-current message, sender drift, deletion tombstone, missing source/group/member/contact, self/outgoing, archived/blocked, visual-media ownership collision, and missing opener.
- Likely named gates:
  - exact focused tests first
  - register the three group-owned headline files in `GROUP_TESTS`
  - no broad gate until the UI slice is present unless the planner identifies an actual shared production edit.
- Matrix/closure docs: Session 02 is accepted in this breakdown, its session plan, and Plan 247's execution ledger; final Plan-247 status still waits for Session 04.
- Dependency: Session 01 accepted artifact.
- Meaningful verified end state: a reusable fail-closed resolver exists, but no action is rendered and therefore no half-live route is exposed.

### Session 03 — Wire Message sender through bubble, viewer, and app-owner routes

- Session id: `03`
- Classification: `implementation-complete`
- Execution status: `accepted` on 2026-07-12 after fresh post-fix QA and a separate closure review with zero blockers. QA `fix_passes=1`; behavior-fix count `0`.
- Accepted evidence: Session-03 causal `10/10`; Session-02 preservation `6/6`; groups `1,951/1,951`; 1to1 `1,963/1,963`; feature-host-all `751/751`; completeness `1,179/1,179`; exact forbidden manifest; exactly one post-QA incremental Graphify refresh.
- Intended plan file: `Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-03-plan.md`
- Exact scope:
  - Add a typed, callback-only app-owner opener to `GroupConversationWired`; null means unavailable and keeps the action absent.
  - Extend the media bubble context menu with a distinct `Message sender` entry/key/callback. Do not reuse `Reply`, `onQuoteReply`, or `quotedMessageId`.
  - Add a distinct shared-viewer action such as `MediaViewerAction.messageSender`, with localized icon tooltip and exact current-item dispatch. Do not reinterpret `MediaViewerAction.reply`.
  - Build capability only for the accepted announcement-media/request row and invoke Session 02 revalidation again immediately before navigation.
  - Close the overlay/viewer before calling the opener, coalesce double taps, route exactly once to the current visible message's sender, pass no `initialText`, attachments, caption, quote, Forward provenance, group/source context, or payload field, and report stale/route failures without mutation.
  - Reuse existing complete `ConversationWired` builders owned by `lib/main.dart`, Feed, and Orbit. Thread the callback through reachable group-entry flows. Enumerate all five current `GroupConversationWired` construction sites; a site that truly lacks complete direct dependencies must explicitly pass/retain null and prove the action absent rather than constructing a partial direct screen.
  - Add EN/DE/AR strings and regenerate localization outputs using the repo's normal l10n process.
  - Preserve announcement reader read-only compose and reactions, and preserve normal discussion-group Reply behavior.
  - Add routing, entry-surface, zero-auto-send, localization/RTL/small-viewport, stale-menu, current-viewer-page, double-tap, and route-failure tests.
- Why its own session: it changes shared UI enums/widgets, async navigation, localization, and five constructor sites, with a different regression family and a known concurrent-file conflict from the pure application policy.
- Likely code-entry files:
  - `lib/features/groups/presentation/screens/group_conversation_screen.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/conversation/presentation/widgets/message_context_overlay.dart`
  - `lib/shared/widgets/media/media_viewer_item.dart`
  - `lib/shared/widgets/media/full_screen_typed_media_viewer.dart`
  - `lib/main.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/orbit/presentation/screens/orbit_wired.dart`
  - `lib/features/groups/presentation/screens/group_list_wired.dart`
  - `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
  - `lib/l10n/app_en.arb`, `app_de.arb`, `app_ar.arb` and generated outputs
- Likely direct tests/regressions:
  - `test/features/groups/presentation/announcement_private_reply_routing_test.dart`
  - `test/features/groups/presentation/announcement_private_reply_entry_surface_test.dart`
  - `test/features/groups/integration/announcement_private_reply_no_auto_send_test.dart`
  - `test/features/groups/presentation/group_conversation_wired_test.dart` exact announcement read-only/reaction sentinel plus return-state assertion
  - `test/features/conversation/presentation/widgets/message_context_overlay_test.dart`
  - `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart`
  - `test/shared/widgets/media/media_viewer_boundary_test.dart`
  - `test/l10n/l10n_integrity_test.dart`
- Likely named gates:
  - all focused files above
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh 1to1` because the shared viewer/context action enum is a direct-conversation preservation seam, even though Plan 247 creates no direct send behavior
  - `./scripts/run_host_test_gates.sh feature-host-all` only after focused/shared tests are green, justified by the multi-entry feature wiring
- Matrix/closure docs: execution evidence to Plan 247; final synchronization in Session 04.
- Dependency: Sessions 01–02 and Plan 234's shared capability/viewer work are accepted. Session 03 is closed; Session 04 is released.
- Meaningful verified end state: the action is reachable on every deliberately supported production entry path, opens a blank real direct conversation exactly once, and has host evidence of zero send/upload/Forward/source mutation.

#### Plan 234 overlap guard for Session 03

Plan 234 may concurrently edit:

- `lib/shared/widgets/media/media_viewer_item.dart`
- `lib/shared/widgets/media/full_screen_typed_media_viewer.dart`
- `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart`
- owner/protection capability construction in direct or shared viewer callers.

Session 03 must not overwrite Plan 234 lifecycle/protection state, `MediaViewerProtection`, `isActionEligible`, ordinary/private capability denial, or its tests. Its shared-viewer change is additive only: a distinct callback action, icon/tooltip/order, and exhaustive-switch handling. Refresh/rebase the session against landed Plan 234 code; if Plan 234 is still actively editing the same files, serialize those edits rather than merging simultaneously. Run Plan 234's then-current focused viewer/protection sentinels in addition to Plan 247 focused tests. No migration ownership exists in Plan 247.

### Session 04 — Run host acceptance and synchronize closure records

- Session id: `04`
- Classification: `acceptance-only`
- Execution status: `accepted` on 2026-07-12 after independent behavior/privacy QA and a separate closure review, both with zero blockers; Session-04 executable `fix_passes=0`.
- Accepted evidence: groups `1,951/1,951` plus inherited Go sentinels; current 1to1 `1,977/1,977`; feature-host `754/754` by honest supported segmented resume plus current delta `282/282`; completeness `1,185/1,185`; host inventory `89`; repair fixtures `34/34`; formatter `32/0`; analyzer zero warning/error; immutable equality; documentation gates and closure review accepted.
- Intended plan file: `Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-04-plan.md`
- Exact scope:
  - Independently inspect the landed diff for the accepted eligibility matrix, blank composer, exact current-item routing, callback-only boundary, route failure, and every production constructor.
  - Run all focused Plan 247 tests, shared viewer/context/l10n sentinels, announcement read-only/reaction sentinel, groups gate, 1:1 preservation gate, justified feature family gate, analyzer, diff hygiene, and completeness-check if gate arrays changed.
  - Prove from host spies/source contracts that opening/cancelling creates zero direct/group send, upload, Forward, Bridge, payload, persistence, or source-file mutation.
  - Update Plan 247 with exact commands/results and a final accepted or exact-blocker verdict.
  - Update `Test-Flight-Improv/00-INDEX.md`, `13-announcement-use-case-audit.md`, and `21-announcement-reliability-closure-reference.md` narrowly to record the new callback-only cross-lane UX without changing the announcement reliability/write model.
- Why its own session: it validates multiple earlier seams and owns final documentation truth; folding it into UI implementation would remove independent acceptance value.
- Likely code-entry files: none except fixes causally required by failed acceptance.
- Direct tests/gates:
  - all Session 02/03 focused suites
  - exact existing announcement read-only/reaction sentinel
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_host_test_gates.sh feature-host-all`
  - `./scripts/run_test_gates.sh completeness-check` if curated arrays changed
  - `flutter analyze`
  - `git diff --check`
- Matrix/closure docs: Plan 247, `00-INDEX.md`, announcement audit, and closure reference are synchronized; the decision artifact remains immutable and accepted.
- Dependency: Sessions 01–03 accepted and closed.
- Meaningful verified end state: a persisted accepted verdict with host-only causal evidence and synchronized maintenance documentation.

## Why This Is Not Fewer Sessions

- The product/privacy decision must be persisted before code and exact copy/tests exist; merging it into implementation would erase the evidence gate.
- The pure resolver/revalidation seam can land safely with no rendered action and has table-driven security tests distinct from widget/navigation tests.
- Presentation touches a shared viewer enum/widget, localization, navigation, and five constructor sites. Combining it with the policy would make counterexamples and Plan 234 conflict handling harder to isolate.
- Final acceptance spans both implementation slices and stable closure docs, so it needs an independent pass.

Three sessions would force either decision+code authoring in one pass or policy+multi-surface UI into one oversized diff. Both weaken the fail-closed and independent-QA contracts.

## Why This Is Not More Sessions

- Bubble and viewer actions express the same `Message sender` capability, use the same resolver/opener, and need the same group/l10n gates; separate UI sessions would create a misleading inconsistent interval.
- Feed, Orbit, app-shell, group-list, and create-picker work is constructor plumbing for one opener contract, not five independent product features.
- Localization is inseparable from the one user-visible action and failure states.
- There is no migration, persistence, direct delivery, Bridge, Go, relay, or native/device implementation to justify more sessions.

## Regression And Gate Contract

Follow `Test-Flight-Improv/14-regression-test-strategy.md` and use `Test-Flight-Improv/test-gate-definitions.md` plus the current scripts as execution authority:

1. Capture dirty-worktree baseline before every session and do not absorb unrelated Plan 234/reporting/forwarding work.
2. Write the exact causal test first in each implementation session and record real RED output; compile RED is acceptable only for the first missing typed contract/action.
3. Re-run representative guard-removal mutations: incoming guard, announcement type, current contact, archive/block, self, source reload/tombstone, group/member availability, opener availability, current viewer item, double-dispatch, and no-context seed.
4. Register new group headline files in `GROUP_TESTS`. Add the no-auto-send test to `ONE_TO_ONE_TESTS` only if it executes the real direct route fixture; otherwise keep 1:1 as a preservation gate, not false ownership.
5. Run exact shared tests because `test/shared/**` and `test/l10n/**` are not fully represented by `feature-host-all` discovery.
6. Run `groups`, `1to1`, and the justified `feature-host-all` family sweep after Session 03/04. Do not run full `host-all` as a per-plan gate; it remains wave/final-rollout work under repo cadence.
7. No device target is required. No Bridge, Go, relay, payload, or native code is modified or tested. Host fakes/spies and source-contract checks are the causal proof boundary.

### Device / Relay Proof Profile

- Classification: `host-only / N/A`
- Device matrix: `N/A` — navigation and zero-send behavior are fully injectable Flutter host boundaries.
- Relay/Go: `N/A` — no serialized operation or transport authority is introduced.
- Native/platform: `N/A` — no OS API or platform-specific route behavior is claimed.
- A request to add a device, relay, Go, migration, or payload leg is scope drift unless a landed implementation unexpectedly crosses that boundary; in that event stop and re-plan rather than silently expanding Plan 247.

## Matrix Update Contract

Session 04 owns the stable record updates:

- `Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan.md`: exact execution evidence and final verdict.
- `Test-Flight-Improv/247-private-reply-decision.md`: remains the accepted immutable product/privacy contract.
- `Test-Flight-Improv/00-INDEX.md`: replace evidence-gated Plan 247 wording/status with the actual closure verdict.
- `Test-Flight-Improv/13-announcement-use-case-audit.md`: record Message sender as an explicit navigation-only reader feature, not an announcement send capability.
- `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`: record preservation of reader read-only/reaction semantics and zero change to transport closure.

Do not create a new announcement matrix. These existing stable docs already own feature inventory and announcement closure.

## Downstream Execution Path

For each session, in order:

1. Create/refresh its intended doc-scoped plan with `$implementation-plan-orchestrator`.
2. Execute and independently QA it with `$implementation-execution-qa-orchestrator`.
3. Close its plan/evidence/docs with `$implementation-closure-audit-orchestrator`.
4. Refresh this ledger and the next session against landed code before advancing.

Session 03 must also perform the explicit Plan 234 overlap refresh before its planner and executor start.

## Reviewer Answers

- Recommended count: sufficient; neither too coarse nor fragmented.
- Sessions to merge: none.
- Sessions that must split: none after separating policy from presentation.
- Missing tests/gates: none structurally; exact no-auto-send fixture ownership determines whether its file is pinned in both curated arrays.
- Meaningful end states: yes — accepted contract; unrendered fail-closed resolver; complete user-visible route; independent accepted closure.
- Matrix responsibility: Session 04 explicitly owns it.
- Minimum safe set: four sessions.

## Structural Blockers Remaining

None. Wave-1 authority supplied the formerly missing D-247 decisions.

The former shared-viewer coordination constraint with Plan 234 was resolved before Session 03 execution. No Plan-247 structural or execution blocker remains.

## Accepted Differences Intentionally Left Unchanged

- This action is **Message sender**, not same-thread Reply, private quote, Forward, Report, or announcement compose.
- No source context or media follows the user into the direct conversation; the blank composer is intentional.
- Unknown, archived, or blocked senders do not launch introduction/contact/unblock UX.
- Production entry sites without a complete injected opener fail closed; they do not construct a partial `ConversationWired`.
- Existing shared-viewer protection/availability gates remain conservative and are not relaxed.
- No migration, durable draft, new message type, cross-lane quote/provenance, Bridge/P2P, Go/relay, or device proof exists in this plan.

## Exact Docs And Files Used As Evidence

- `Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/13-announcement-use-case-audit.md`
- `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`
- `Test-Flight-Improv/00-INDEX.md`
- `lib/features/groups/application/group_received_media_action_policy.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/conversation/presentation/widgets/message_context_overlay.dart`
- `lib/shared/widgets/media/media_viewer_item.dart`
- `lib/shared/widgets/media/full_screen_typed_media_viewer.dart`
- `lib/features/contacts/domain/models/contact_model.dart`
- `lib/features/contacts/domain/repositories/contact_repository.dart`
- `lib/features/identity/domain/repositories/identity_repository.dart`
- `lib/features/groups/domain/models/group_model.dart`
- `lib/features/groups/domain/models/group_message.dart`
- `lib/features/groups/domain/repositories/group_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `lib/features/groups/presentation/screens/group_list_wired.dart`
- `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
- `lib/main.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/conversation/presentation/widgets/message_context_overlay_test.dart`
- `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart`
- `test/shared/widgets/media/media_viewer_boundary_test.dart`
- `test/l10n/l10n_integrity_test.dart`
- `scripts/run_test_gates.sh`
- `scripts/run_host_test_gates.sh`

## Why This Is Safe For Downstream Planning And Execution

The formerly ambiguous product/privacy choices are literal and testable, every session has one core seam and a doc-scoped plan path, the callback boundary is explicitly incapable of transport work, stale state is revalidated at dispatch, no unsupported platform/server claim is required, shared Plan 234 ownership is guarded before edits, and final evidence/document synchronization has one named owner.

## Final Closure

All four sessions are accepted. The final product boundary is deliberately
narrow: reader-initiated **Message sender** navigation to an existing active
sender contact's blank 1:1 composer, with fresh fail-closed authority and no
copied context or automatic send. Plan 247 changes no announcement writer,
delivery, retry, status, Go/relay, native/device, database, or payload contract.
