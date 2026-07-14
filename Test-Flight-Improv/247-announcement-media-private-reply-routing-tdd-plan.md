# 247 - Announcement Media Private Reply Routing

Status: accepted
Type: New Feature
Spec: free-text intent — let an announcement recipient deliberately move from received media to an eligible 1:1 composer without creating an announcement write path or silently sending copied content
Classification: accepted
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector / Planner | architecture graph query; group conversation screen/wired/list callers; Orbit/Feed direct and group route builders; contact repository/model; `ConversationWired` initial draft support; announcement send/auth tests; Go writer validator | Intake established that HEAD could identify an announcement sender and higher-level surfaces could open complete direct conversations, but `GroupConversationWired` lacked the direct-message dependencies/opener. The label, contact authority, copied context, and exceptional-state choices were still open at intake. | Superseded by the accepted 2026-07-11 Session-01 decision row below. |
| 2026-07-11 | Wave-1 product/privacy authority / Session 01 | `247-private-reply-decision.md`; source and breakdown; current group/contact model and repository anchors | D-247-01..04 accepted: **Message sender**, current active/unblocked contact only, blank composer with two-field local request, and fail-closed stale/exception behavior. No executable feature changed in Session 01. | Session 02: add the minimum request, pure eligibility policy, and dispatch-time revalidation RED-first. |
| 2026-07-11 | Session 02 accepted closure | Session-02 plan; minimum request/policy/resolver; typed tombstone authority; three focused suites and gate registrations | Independent post-fix QA accepted with zero blockers: focused 6/6, formatter clean, scoped analyzer clean apart from five known default-fatal infos, completeness 1164/1164, and persisted groups evidence 1932/1932. The unrendered fail-closed boundary is closed; Plan 247 remains implementation-in-progress. | Keep Session 03 serialization-blocked until Plan 234 releases shared capability/viewer ownership; then refresh its protection state and plan/execute Session 03. |
| 2026-07-12 | Session 03 accepted closure | Session-03 plan; callback-only bubble/viewer/app-owner route; exact-current revalidation; real blank-route proof; l10n/gates/scope/Graphify evidence | Fresh post-fix QA and separate closure review accepted with zero blockers. Causal 10/10, Session-02 6/6, groups 1951/1951, 1to1 1963/1963, feature-host-all 751/751, completeness 1179/1179; QA `fix_passes=1`, behavior-fix count 0; exactly one post-QA incremental refresh. | Execute acceptance-only Session 04 and synchronize the stable Plan-247/index/announcement closure records. |
| 2026-07-12 | Session 04 accepted host closure | Session-04 plan; current source/tests; focused, named, family, static, immutable, QA, and documentation evidence | Independent QA accepted with zero blockers at Session-04 `fix_passes=0`. Final current evidence: groups 1,951/1,951 plus inherited Go sentinels, 1to1 1,977/1,977, feature-host 754/754 by honest supported segmented resume plus current delta 282/282, completeness 1,185/1,185, host inventory 89, formatter 32/0, analyzer zero warnings/errors, and exact final immutable equality. | Plan 247 is accepted/closed; the later Wave-1 aggregate evidence is recorded in Direct Revalidation Status. |

## Problem And Evidence

- Behavior to improve: a reader may want to respond privately to the sender of an announcement image/video without gaining the ability to reply inside the announcement.
- Impact: the current reader has no Reply action because `GroupConversationScreen` couples quote reply to `canWrite`; inventing a same-thread reply would violate the announcement role model.
- Confirmed current mechanism: announcement reader Reply is hidden at `lib/features/groups/presentation/screens/group_conversation_screen.dart:930-950`, while reaction remains deliberately available.
- Confirmed direct-route mechanism: `FeedWired` and `OrbitWired` already construct `ConversationWired` with the full message/listener/repository dependency set; `ConversationWired` accepts local `initialText` but sends nothing until its normal composer is submitted.
- Confirmed ownership gap: `GroupConversationWired` owns group repositories, Bridge, and `P2PService` but not the direct `MessageRepository`/`ChatMessageListener`; constructing a partial direct screen inside it would be unsafe. A typed opener must be supplied by the owning app surface.
- Confirmed eligibility data: the source `GroupMessage` has `senderPeerId`; `ContactRepository.getContact` returns a durable contact with `isBlocked`. HEAD has no contract for messaging an unknown/non-contact announcement publisher from this surface.
- Confirmed authorization backstop: Flutter and Go both reject non-admin announcement publishing. Private route plumbing must not change `canWrite`, group callbacks, group payloads, or Go validation.
- Existing coverage: group screen tests prove readers lack quote/swipe reply; announcement wired tests prove compose remains absent; Feed/Orbit tests cover their existing direct route builders. No test can fail for an announcement-to-direct opener or source-group command absence.
- Closed executable coverage: exact localized label/feedback rendering, blank-context enforcement, active-contact gating, source/current identity after viewer swipe, app-surface callback plumbing, no-auto-send behavior, source announcement command absence, route failure, and blocked/deleted sender changes while the menu is open all have accepted causal host proof.
- Refuted finding: this cannot reuse the group quote flow. `quotedMessageId` belongs to the source group and has no valid referent in a 1:1 conversation.
- Accepted decision authority: `Test-Flight-Improv/247-private-reply-decision.md` resolves **D-247-01** as `Message sender`, **D-247-02** as current active/unblocked contact only, **D-247-03** as a blank composer with no copied context, and **D-247-04** as fail-closed hiding/revalidation with privacy-minimized feedback.
- Affected production/test files for later sessions: typed private-route request/policy under group presentation/application, `GroupConversationScreen`/`GroupConversationWired`, all production constructors that can open a group conversation, direct route builder reuse/extraction if needed, l10n, focused group/feed/orbit routing tests, and group gate registration.

## Scope Contract And Guard

In scope under accepted D-247-01..04:
- Add a typed `AnnouncementPrivateReplyRequest` carrying only source message ID for local stale-state revalidation and sender peer ID for contact lookup; it is never serialized to a message payload or Bridge command.
- Add an injected `OpenDirectConversation` callback at the group presentation boundary. The app-level owner resolves an eligible contact and opens the existing fully wired `ConversationWired` route.
- Re-load the source message/group/contact when invoked. Fail closed if the row is gone, sender changed, group is no longer an announcement, sender is blocked/ineligible, or the callback is unavailable.
- Open the existing direct route with its default blank composer and no source content. The local non-serializable qualification request contains only `sourceMessageId` and `senderPeerId`; media bytes, local paths, captions, quote/group context, keys/nonces, display metadata, and hidden diagnostics never cross.
- Close the viewer/action sheet before navigation, route exactly once for the currently visible item/message, and return safely to the unchanged announcement.

Must preserve:
- Announcement reader compose/attach/record/quote callbacks stay null and reader reactions stay available -> existing group wired sentinels plus TC-247-06.
- Direct delivery begins only after the user later submits the normal 1:1 composer -> TC-247-03.
- Source announcement message/media and direct history remain unchanged merely by opening/cancelling the route -> TC-247-02/03.
- Go non-admin writer rejection remains GREEN -> TC-247-07.

Hard `Do not`:
- Do not call `sendGroupMessage`, `group:publish`, `group:inboxStore`, or mutate `canWrite`/role/member state.
- Do not call `sendChatMessage` from the announcement action or route coordinator; opening a composer is the terminal action in this plan.
- Do not carry a group `quotedMessageId` into a direct message or invent a cross-lane reply field/message type.
- Do not construct `ConversationWired` inside `GroupConversationWired` with missing dependencies; use the injected app-owner callback.
- Do not auto-add/unblock a contact, initiate an introduction, or expose the action for an unknown, archived, or blocked sender.
- Do not copy source media bytes/files, caption, sender display identity, group title/context, quote identity, or encryption data into 1:1.
- Do not modify Bridge, P2P, relay, group/direct payloads, Go/libp2p code, database schema, or delivery/retry semantics.

Deferred / accepted difference:
- Core announcement media actions remain plan 239 and do not wait for this plan.
- Internal forwarding is plan 240; opening a private composer is not Forward and never sets a forwarded marker.
- Plan 246 closes reporting as an intentional product non-goal; private
  messaging must not approximate it.
- Session 01 deliberately renders no action. The action remains absent until Sessions 02–03 land the accepted policy and complete opener wiring; fail-closed absence remains preferable to a partial or privacy-leaking route.

Dependencies:
- Plan 230 supplies current typed viewer item/message identity and fail-closed action capabilities.
- Plan 239 supplies the announcement media action adapter but explicitly excludes this cross-lane callback.
- Existing complete direct route construction in Feed/Orbit/app-shell surfaces; no messaging transport change is a dependency.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-247-00 | A decision artifact resolves label, sender eligibility, context minimization, and exceptional states before an action key is added. | `Test-Flight-Improv/247-private-reply-decision.md` with `Status: accepted` and explicit D-247-01..04 rows | evidence gate / product+privacy decision | Baseline evidence RED before Session 01: artifact absent and no approved cross-lane semantics -> Session 01 accepted exact visible label, allowed rows, local request shape, and denied rows | N/A; no honest mutation exists before behavior is selected | literal acceptance checks below; passed in Session 01 and unblocks TC-247-01 production/test authoring |
| TC-247-01 | Only the accepted incoming announcement-media/sender rows expose the selected action; discussion, outgoing, system, deleted, blocked, unknown, and stale rows fail closed exactly per D-247. | `test/features/groups/application/announcement_private_reply_policy_test.dart::accepted private-reply matrix is exact and fail closed` | host unit / table-driven group/message/media/contact matrix | after evidence, HEAD compile RED: policy absent -> exact capability set and localized label pass | remove group type, incoming, contact, blocked, or current-row guard -> TC-247-01 red | `flutter test test/features/groups/application/announcement_private_reply_policy_test.dart`; AUTO + add to `GROUP_TESTS` |
| TC-247-02 | Bubble and viewer dispatch the currently visible message/sender once, revalidate state, close transient UI, and call only the injected opener. | `test/features/groups/presentation/announcement_private_reply_routing_test.dart::message and viewer open the current eligible sender exactly once` | widget/application host / typed items + mutable repos + opener recorder | HEAD compile RED: callback/action absent -> page B targets sender B once; a post-menu block/delete invokes zero routes | capture first-page sender, skip re-load, or double-tap while pending -> TC-247-02 red | `flutter test test/features/groups/presentation/announcement_private_reply_routing_test.dart`; AUTO + `GROUP_TESTS` |
| TC-247-03 | Opening/cancelling the direct route creates no direct or group send/upload and leaves both histories/source files unchanged; only a later explicit direct-composer submit may use existing 1:1 delivery. | `test/features/groups/integration/announcement_private_reply_no_auto_send_test.dart::opening private composer has zero delivery and source mutations` | host integration / complete opener fake + throwing direct/group send/upload spies | HEAD compile RED -> route open/cancel logs zero send/upload/Bridge operations and equal snapshots | pre-send context automatically or invoke group reply callback -> TC-247-03 red | `flutter test test/features/groups/integration/announcement_private_reply_no_auto_send_test.dart`; AUTO + `GROUP_TESTS` and `ONE_TO_ONE_TESTS` only if it executes the real direct route fixture |
| TC-247-04 | The local request contains exactly `sourceMessageId` and `senderPeerId`, has no serializer, opens a blank composer, and excludes every field forbidden by D-247-03. | `test/features/groups/application/announcement_private_reply_request_test.dart::private route request is minimum local and non-serializable` | host unit/application / source object filled with sentinel secrets | HEAD compile RED -> exact two-field request; media/path/key/nonce/group-key/display/context sentinels absent from request, diagnostics, and direct payload before submit | build from raw message/attachment map, add a third field/serializer, seed `initialText`, or attach source media -> TC-247-04 red | `flutter test test/features/groups/application/announcement_private_reply_request_test.dart`; AUTO + `GROUP_TESTS` |
| TC-247-05 | Every production group-conversation entry surface supplies the same complete opener or deliberately reports unavailable; no surface constructs a partial direct route. | `test/features/groups/presentation/announcement_private_reply_entry_surface_test.dart::Feed Orbit and GroupList wire one complete direct opener contract` | widget/source-contract host / constructor census + route spies | HEAD compile RED -> each production caller is enumerated; eligible routes receive full existing direct dependencies; unavailable owners hide the action | omit one constructor/caller or instantiate `ConversationWired` in group wired code -> TC-247-05 red | `flutter test test/features/groups/presentation/announcement_private_reply_entry_surface_test.dart`; AUTO + `GROUP_TESTS` |
| TC-247-06 | Announcement reader remains read-only and reaction-capable before, during, and after returning from the private route. | existing `group_conversation_wired_test.dart::announcement readers stay read-only for compose but still keep reaction entry` plus new return-state assertion | `GREEN sentinel` + widget extension / reader fixture | GREEN on HEAD -> remains GREEN and route return does not expose stale compose/quote state | set `canWrite`, preserve hidden quote state, or replace group route -> sentinel red | existing `GROUP_TESTS` path and focused plain-name command |
| TC-247-07 | Go still rejects reader announcement publication and no Go/Bridge/relay/direct payload file is changed by the routing slice. | existing Go announcement authorization tests plus `test/features/groups/application/announcement_private_reply_transport_boundary_test.dart::private route adapter is callback-only` | Go GREEN sentinel + host source-contract | Go GREEN on HEAD, Dart target absent -> authorization stays GREEN and forbidden source/diff allowlist remains empty | add group/direct send call, payload field, Bridge/P2P import, or Go edit -> TC-247-07 red | focused Dart test + pinned Go command + `git diff --exit-code -- go-mknoon go-relay-server` |
| TC-247-08 | Accepted copy/action stays reachable and truthful in English, German, and RTL Arabic on a small viewport, including unavailable feedback. | `test/features/groups/presentation/announcement_private_reply_routing_test.dart::private reply copy is localized accessible and RTL safe` | widget host / 320x568 en/de/ar + semantics tester | HEAD compile RED -> decision-selected label, warning/feedback, and focus order render without overflow | hardcode English or call the action “Reply” when D-247 chose “Message sender” -> TC-247-08 red | focused widget test + existing l10n parity test; AUTO + `GROUP_TESTS` |

### Test Notes

- TC-247-00 must name exact copy and allowed fields, not merely “approved.” The selected contract replaces all D-247 placeholders before status changes.
- TC-247-03 separates navigation from sending. A real normal composer submit may be a preservation control, but the announcement action itself must make zero delivery calls.
- TC-247-05 needs a source/constructor census because group conversations are opened from several app surfaces with different dependency owners; a single happy route is insufficient.

## Implementation Steps

1. **Completed in Session 01:** accept D-247-01..04 in `Test-Flight-Improv/247-private-reply-decision.md`, including exact action/failure copy, eligibility matrix, blank-composer fields, and exception behavior.
2. In Session 02, add TC-247-01/04/07 before production edits and record causal RED/preservation evidence separately; Sessions 03–04 own routing/UI and aggregate proof.
3. Add the pure request/policy and callback-only opener interface; revalidate current group/message/contact state at invocation.
4. Thread the optional opener through every production group-conversation constructor from the complete app owner; stop-if any group widget must import direct delivery use cases.
5. Add the action to message/viewer capabilities, close transient UI, and open the existing direct route with only accepted local draft fields. Do not auto-send.
6. Add localized copy, register owning tests, run direct/group/Go preservation, mutation re-reds, analyzer, and hygiene.

## Risks And Blind Spots

- “Reply” may imply same-thread context that does not exist -> D-247-01/03 and TC-247-04/08 make the accepted semantics explicit.
- Cross-lane routing can accidentally create a send path -> TC-247-03/07 require zero delivery at action time.
- Sender/contact state can change after menu open -> TC-247-01/02 re-load and fail closed.
- Lifecycle / derived-state durability: no new durable state; route return reconstructs action eligibility from current group/message/contact rows in TC-247-02/06.
- Sibling-surface consistency: TC-247-02 compares bubble/viewer and TC-247-05 enumerates every route owner.
- Destructive-action side effects: none; TC-247-03 asserts histories/files unchanged.
- Invariant re-verification under new transitions: current item, source row, group type, contact/block state, and callback availability are rechecked immediately before route dispatch.

## Acceptance Gates

```bash
# Evidence gate; artifact must exist, be accepted, name every decision, and contain no unresolved placeholders
test -s Test-Flight-Improv/247-private-reply-decision.md
rg -x 'Status: accepted' Test-Flight-Improv/247-private-reply-decision.md
for id in D-247-01 D-247-02 D-247-03 D-247-04; do rg -q "$id" Test-Flight-Improv/247-private-reply-decision.md; done
! rg -n 'TBD|TO DECIDE|unresolved|pending approval' Test-Flight-Improv/247-private-reply-decision.md

git status --short

# First causal RED after decision; expect non-zero because policy/action types are absent
flutter test test/features/groups/application/announcement_private_reply_policy_test.dart --plain-name 'accepted private-reply matrix is exact and fail closed'

# Focused GREEN
flutter test test/features/groups/application/announcement_private_reply_policy_test.dart
flutter test test/features/groups/application/announcement_private_reply_request_test.dart
flutter test test/features/groups/application/announcement_private_reply_transport_boundary_test.dart
flutter test test/features/groups/presentation/announcement_private_reply_routing_test.dart
flutter test test/features/groups/presentation/announcement_private_reply_entry_surface_test.dart
flutter test test/features/groups/integration/announcement_private_reply_no_auto_send_test.dart

# Announcement/direct preservation
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'announcement readers stay read-only for compose but still keep reaction entry'
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh 1to1
./scripts/run_host_test_gates.sh feature-host-all
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestIsAllowedWriter_AnnouncementMemberBlocked|TestGroupTopicValidator_AnnouncementNonAdminRejected' -count=1)

git diff --exit-code -- go-mknoon go-relay-server
flutter analyze
git diff --check
```

## Execution Interpretation And Done Criteria

- Historical evidence RED: D-247-01..04 had no accepted answers before Session 01. `247-private-reply-decision.md` now closes that gate.
- Historical Session-02 causal RED: TC-247-01 compile-failed because the private-route policy/request did not exist; Session 02 is now accepted. The visible action/opener remains absent by design until Session 03.
- Green sentinel: announcement read-only/reaction behavior and Go publisher rejection stay GREEN.
- Pre-existing dirty tree / known failure: record at execution start; do not absorb unrelated work.
- Evidence blocker: none. The accepted decision artifact is complete; implementation and acceptance sessions remain.
- Environment blocker: none after evidence; host routes/fakes and Go unit tests close this navigation-only slice.
- Scope drift: any automatic send, cross-lane quote field, payload/schema, group write relaxation, Bridge/P2P/relay, or Go production edit blocks completion.

- [x] D-247-01..04 are concretely accepted and reflected in the source test contract/copy requirements.
- [x] Every post-decision behavior has a causal test or preservation sentinel.
- [x] Current-item routing, revalidation, all production entry surfaces, zero-auto-send, context minimization, and localization pass.
- [x] Announcement group and 1:1 preservation gates pass; Go/relay no-diff and authorization sentinels are green.
- [x] Representative stale-item, blocked-contact, double-tap, auto-send, raw-map, and missing-caller mutations re-red.
- [x] Analyzer/diff hygiene and scope guard pass.

## Handoff

- Accepted authority: `Test-Flight-Improv/247-private-reply-decision.md` is complete and immutable for Sessions 02–04 unless product/privacy explicitly reopens it.
- Next action: preserve the accepted callback-only boundary; reopen Plan 247 only for concrete eligibility, current-item, blank-composer, or zero-send regression evidence.
- Preservation command: `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'announcement readers stay read-only for compose but still keep reaction entry'`.
- Manual registration: the three Session-02 group-owned suites and all three Session-03 suites are registered; the real-route no-auto-send integration is present in both required 1:1 arrays.
- Migration: none.
- Boundary closure: host callback/navigation plus existing pinned Go authorization; no device/relay proof.
- Remaining work: none inside Plan 247. The Wave-1 aggregate `host-all`, required
  availability-bounded device proof, documentation rollup, and final Graphify
  refresh completed on 2026-07-12.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-11 | Session 01 evidence closure | `247-private-reply-decision.md`; source plan; Session-01 plan; session breakdown | exact documentation gates passed; no production/test edit | D-247-01..04 accepted; feature not yet implemented | Superseded by the accepted Session-02 row below. |
| 2026-07-11 | Session 02 accepted closure | Session-02 plan; request/policy/resolver; repository deletion authority; three tests; `GROUP_TESTS` | independent post-fix QA accepted: focused 6/6; completeness 1164/1164; persisted groups 1932/1932; static/format/scope evidence accepted with five known analyzer infos | fail-closed unrendered boundary closed; user-visible action still absent | Session 03 serialization-blocked on Plan-234 shared capability/viewer ownership; Session 04 remains blocked on 03 |
| 2026-07-12 | Session 03 accepted closure | Session-03 plan; application/presentation/opener/l10n production; three causal suites; compatibility fixtures; gate/docs registration | independent post-fix QA and separate closure review accepted; causal 10/10; groups 1951/1951; 1to1 1963/1963; feature-host-all 751/751; completeness 1179/1179; exact scope manifest; one post-QA refresh | callback-only blank direct route implemented and closed with `fix_passes=1`, behavior-fix count 0 | Session 04 execution-ready; overall Plan 247 remains implementation-in-progress |
| 2026-07-12 | Session 04 accepted closure | Session-04 acceptance plan; current scripts/registrations; immutable manifest; six closure records | focused/preservation evidence green; groups 1951 plus Go; current 1to1 1977; feature-host 754 via supported segmented resume and delta 282; completeness 1185; inventory 89; formatter 32/0; analyzer zero warning/error; independent QA and separate closure review accepted | Plan 247 callback-only navigation and zero-send boundary accepted at Session-04 `fix_passes=0`; Session-03 formatting repair separately accepted at `post_closure_fix_passes=1`, behavior-fix count 0 | closed; no per-plan host-all, device, or Graphify refresh |

## Final Execution Result

Plan 247 is accepted and closed. **Message sender** is fresh, fail-closed,
callback-only navigation from an exact current announcement-media parent to an
existing active sender contact's blank 1:1 composer. It copies no context and
performs no automatic send, upload, Forward, persistence, Bridge/P2P, group
write, or source mutation.

Independent Session-04 QA accepted with zero blockers and `fix_passes=0`.
Accepted differences remain deliberate: unknown/archived/blocked senders and
owners without a complete opener expose no action; this is not announcement
Reply, Forward, reporting, contact introduction, or transport behavior. The
Wave-level `host-all`, required availability-bounded device proof, and final
Graphify refresh completed on 2026-07-12.

## Direct Revalidation Status

- **Status (2026-07-12):** accepted/closed; revalidated after the current Wave-1
  app changes with no Plan-247 regression and no production or test edit.
- **Files changed by this revalidation:** this canonical plan only.
- **Focused evidence:**
  - `flutter test test/features/groups/application/announcement_private_reply_policy_test.dart` -> 4/4 passed.
  - `flutter test test/features/groups/application/announcement_private_reply_request_test.dart` -> 1/1 passed.
  - `flutter test test/features/groups/application/announcement_private_reply_transport_boundary_test.dart` -> 1/1 passed.
  - `flutter test test/features/groups/presentation/announcement_private_reply_routing_test.dart` -> 7/7 passed.
  - `flutter test test/features/groups/presentation/announcement_private_reply_entry_surface_test.dart` -> 2/2 passed.
  - `flutter test test/features/groups/integration/announcement_private_reply_no_auto_send_test.dart` -> 1/1 passed.
  - `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'announcement readers stay read-only for compose but still keep reaction entry'` -> 1/1 passed.
  - `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestIsAllowedWriter_AnnouncementMemberBlocked|TestGroupTopicValidator_AnnouncementNonAdminRejected' -count=1)` -> passed (`ok`, 0.583s).
- **Preservation evidence reused without rerun:** `./scripts/run_test_gates.sh groups`
  -> 2,108/2,108 and `./scripts/run_test_gates.sh 1to1` -> 2,062/2,062;
  both were recorded after the current relevant source changes and no later
  Plan-247-relevant source changed.
- **Static/scope evidence:** `dart format --output=none --set-exit-if-changed`
  over the 21 Plan-247 app/test paths -> 21 files, 0 changed; scoped
  `flutter analyze --no-fatal-infos` over the same paths -> exit 0 with 14
  existing infos and zero warnings/errors; scoped `git diff --check -- <the
  same paths plus this plan and the accepted decision artifact>` -> passed.
  The request/transport/no-auto-send/entry-surface suites prove the action
  remains a two-field local request and callback-only blank-composer route with
  zero automatic send, upload, transport, serialization, persistence, or
  source-history/file mutation.
- **Wave aggregate evidence:** the one-time `host-all` executed all `1,130`
  commands (`1,125` initial passes, including all eight Go legs); the exact
  five-file remediation rerun passed `53/53`. Required device and final
  Graphify evidence are complete.
- **Blocker/follow-up:** none inside Plan 247. Plans 244-246 close Report as an
  intentional product non-goal and introduce no external provisioning blocker.
