# 247 - Announcement Media Private Reply Routing

Status: evidence-gated
Type: New Feature
Spec: free-text intent — let an announcement recipient deliberately move from received media to an eligible 1:1 composer without creating an announcement write path or silently sending copied content
Classification: evidence-gated
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector / Planner | architecture graph query; group conversation screen/wired/list callers; Orbit/Feed direct and group route builders; contact repository/model; `ConversationWired` initial draft support; announcement send/auth tests; Go writer validator | HEAD can identify an announcement sender and open existing direct conversations from higher-level surfaces, but `GroupConversationWired` lacks the direct-message dependencies/opener. A callback-only route can preserve transport isolation, yet product must decide whether this is “Message sender” or a contextual private reply and what source content may be copied. | Resolve D-247-01..04; then add route-policy RED tests before callback plumbing. |

## Problem And Evidence

- Behavior to improve: a reader may want to respond privately to the sender of an announcement image/video without gaining the ability to reply inside the announcement.
- Impact: the current reader has no Reply action because `GroupConversationScreen` couples quote reply to `canWrite`; inventing a same-thread reply would violate the announcement role model.
- Confirmed current mechanism: announcement reader Reply is hidden at `lib/features/groups/presentation/screens/group_conversation_screen.dart:930-950`, while reaction remains deliberately available.
- Confirmed direct-route mechanism: `FeedWired` and `OrbitWired` already construct `ConversationWired` with the full message/listener/repository dependency set; `ConversationWired` accepts local `initialText` but sends nothing until its normal composer is submitted.
- Confirmed ownership gap: `GroupConversationWired` owns group repositories, Bridge, and `P2PService` but not the direct `MessageRepository`/`ChatMessageListener`; constructing a partial direct screen inside it would be unsafe. A typed opener must be supplied by the owning app surface.
- Confirmed eligibility data: the source `GroupMessage` has `senderPeerId`; `ContactRepository.getContact` returns a durable contact with `isBlocked`. HEAD has no contract for messaging an unknown/non-contact announcement publisher from this surface.
- Confirmed authorization backstop: Flutter and Go both reject non-admin announcement publishing. Private route plumbing must not change `canWrite`, group callbacks, group payloads, or Go validation.
- Existing coverage: group screen tests prove readers lack quote/swipe reply; announcement wired tests prove compose remains absent; Feed/Orbit tests cover their existing direct route builders. No test can fail for an announcement-to-direct opener or source-group command absence.
- Missing coverage: product label/context policy, active-contact gating, source/current identity after viewer swipe, app-surface callback plumbing, no-auto-send behavior, source announcement command absence, route failure, and blocked/deleted sender changes while the menu is open.
- Refuted finding: this cannot reuse the group quote flow. `quotedMessageId` belongs to the source group and has no valid referent in a 1:1 conversation.
- Unresolved findings (blocking): **D-247-01** label/expectation (`Message sender` versus `Reply privately`); **D-247-02** active-contact-only versus an introduction/contact-request path for unknown senders; **D-247-03** blank composer versus a privacy-minimized editable context seed and exactly which caption/media facts may cross lanes; **D-247-04** behavior for self-authored, deleted, blocked, left-group, and unavailable-sender messages.
- Affected production/test files after decision: typed private-route request/policy under group presentation/application, `GroupConversationScreen`/`GroupConversationWired`, all production constructors that can open a group conversation, direct route builder reuse/extraction if needed, l10n, focused group/feed/orbit routing tests, and group gate registration.

## Scope Contract And Guard

In scope after D-247-01..04 are accepted:
- Add a typed `AnnouncementPrivateReplyRequest` carrying only source message ID for local stale-state revalidation and sender peer ID for contact lookup; it is never serialized to a message payload or Bridge command.
- Add an injected `OpenDirectConversation` callback at the group presentation boundary. The app-level owner resolves an eligible contact and opens the existing fully wired `ConversationWired` route.
- Re-load the source message/group/contact when invoked. Fail closed if the row is gone, sender changed, group is no longer an announcement, sender is blocked/ineligible, or the callback is unavailable.
- Keep any accepted context seed local and editable; no automatic send/upload occurs. If D-247-03 selects blank composer, pass no source content. If it selects context, allow only the recorded minimized fields and test that media bytes, local paths, keys/nonces, group keys, and hidden peer diagnostics never cross.
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
- Do not auto-add/unblock a contact, initiate an introduction, or expose the action for an unknown sender unless D-247-02 explicitly chooses and separately contracts that behavior.
- Do not copy source media bytes/files, caption, sender identity, group title, or encryption data into 1:1 without the explicit D-247-03 decision.
- Do not modify Bridge, P2P, relay, group/direct payloads, Go/libp2p code, database schema, or delivery/retry semantics.

Deferred / accepted difference:
- Core announcement media actions remain plan 239 and do not wait for this plan.
- Internal forwarding is plan 240; opening a private composer is not Forward and never sets a forwarded marker.
- Reporting is plan 246 and must not be approximated by private messaging.
- Until D-247-01..04 are approved, no private-reply/message-sender action is rendered; this fail-closed absence is preferable to a misleading or privacy-leaking route.

Dependencies:
- Plan 230 supplies current typed viewer item/message identity and fail-closed action capabilities.
- Plan 239 supplies the announcement media action adapter but explicitly excludes this cross-lane callback.
- Existing complete direct route construction in Feed/Orbit/app-shell surfaces; no messaging transport change is a dependency.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-247-00 | A decision artifact resolves label, sender eligibility, context minimization, and exceptional states before an action key is added. | `Test-Flight-Improv/247-private-reply-decision.md` with `Status: accepted` and explicit D-247-01..04 rows | evidence gate / product+privacy decision | HEAD evidence RED: artifact absent and no approved cross-lane semantics -> exact visible label, allowed rows, local draft shape, and denied rows become testable | N/A; no honest mutation exists before behavior is selected | literal acceptance checks below; blocks TC-247-01 production/test authoring |
| TC-247-01 | Only the accepted incoming announcement-media/sender rows expose the selected action; discussion, outgoing, system, deleted, blocked, unknown, and stale rows fail closed exactly per D-247. | `test/features/groups/application/announcement_private_reply_policy_test.dart::accepted private-reply matrix is exact and fail closed` | host unit / table-driven group/message/media/contact matrix | after evidence, HEAD compile RED: policy absent -> exact capability set and localized label pass | remove group type, incoming, contact, blocked, or current-row guard -> TC-247-01 red | `flutter test test/features/groups/application/announcement_private_reply_policy_test.dart`; AUTO + add to `GROUP_TESTS` |
| TC-247-02 | Bubble and viewer dispatch the currently visible message/sender once, revalidate state, close transient UI, and call only the injected opener. | `test/features/groups/presentation/announcement_private_reply_routing_test.dart::message and viewer open the current eligible sender exactly once` | widget/application host / typed items + mutable repos + opener recorder | HEAD compile RED: callback/action absent -> page B targets sender B once; a post-menu block/delete invokes zero routes | capture first-page sender, skip re-load, or double-tap while pending -> TC-247-02 red | `flutter test test/features/groups/presentation/announcement_private_reply_routing_test.dart`; AUTO + `GROUP_TESTS` |
| TC-247-03 | Opening/cancelling the direct route creates no direct or group send/upload and leaves both histories/source files unchanged; only a later explicit direct-composer submit may use existing 1:1 delivery. | `test/features/groups/integration/announcement_private_reply_no_auto_send_test.dart::opening private composer has zero delivery and source mutations` | host integration / complete opener fake + throwing direct/group send/upload spies | HEAD compile RED -> route open/cancel logs zero send/upload/Bridge operations and equal snapshots | pre-send context automatically or invoke group reply callback -> TC-247-03 red | `flutter test test/features/groups/integration/announcement_private_reply_no_auto_send_test.dart`; AUTO + `GROUP_TESTS` and `ONE_TO_ONE_TESTS` only if it executes the real direct route fixture |
| TC-247-04 | The accepted blank/minimized editable seed crosses the route exactly and excludes every field forbidden by D-247-03. | `test/features/groups/application/announcement_private_reply_request_test.dart::private route seed is editable privacy-minimized and non-serializable` | host unit/application / source object filled with sentinel secrets | HEAD compile RED -> exact allowed seed; media/path/key/nonce/group-key/hidden-id sentinels absent from request, diagnostics, direct payload before submit | build from raw message/attachment map or attach source media -> TC-247-04 red | `flutter test test/features/groups/application/announcement_private_reply_request_test.dart`; AUTO + `GROUP_TESTS` |
| TC-247-05 | Every production group-conversation entry surface supplies the same complete opener or deliberately reports unavailable; no surface constructs a partial direct route. | `test/features/groups/presentation/announcement_private_reply_entry_surface_test.dart::Feed Orbit and GroupList wire one complete direct opener contract` | widget/source-contract host / constructor census + route spies | HEAD compile RED -> each production caller is enumerated; eligible routes receive full existing direct dependencies; unavailable owners hide the action | omit one constructor/caller or instantiate `ConversationWired` in group wired code -> TC-247-05 red | `flutter test test/features/groups/presentation/announcement_private_reply_entry_surface_test.dart`; AUTO + `GROUP_TESTS` |
| TC-247-06 | Announcement reader remains read-only and reaction-capable before, during, and after returning from the private route. | existing `group_conversation_wired_test.dart::announcement readers stay read-only for compose but still keep reaction entry` plus new return-state assertion | `GREEN sentinel` + widget extension / reader fixture | GREEN on HEAD -> remains GREEN and route return does not expose stale compose/quote state | set `canWrite`, preserve hidden quote state, or replace group route -> sentinel red | existing `GROUP_TESTS` path and focused plain-name command |
| TC-247-07 | Go still rejects reader announcement publication and no Go/Bridge/relay/direct payload file is changed by the routing slice. | existing Go announcement authorization tests plus `test/features/groups/application/announcement_private_reply_transport_boundary_test.dart::private route adapter is callback-only` | Go GREEN sentinel + host source-contract | Go GREEN on HEAD, Dart target absent -> authorization stays GREEN and forbidden source/diff allowlist remains empty | add group/direct send call, payload field, Bridge/P2P import, or Go edit -> TC-247-07 red | focused Dart test + pinned Go command + `git diff --exit-code -- go-mknoon go-relay-server` |
| TC-247-08 | Accepted copy/action stays reachable and truthful in English, German, and RTL Arabic on a small viewport, including unavailable feedback. | `test/features/groups/presentation/announcement_private_reply_routing_test.dart::private reply copy is localized accessible and RTL safe` | widget host / 320x568 en/de/ar + semantics tester | HEAD compile RED -> decision-selected label, warning/feedback, and focus order render without overflow | hardcode English or call the action “Reply” when D-247 chose “Message sender” -> TC-247-08 red | focused widget test + existing l10n parity test; AUTO + `GROUP_TESTS` |

### Test Notes

- TC-247-00 must name exact copy and allowed fields, not merely “approved.” The selected contract replaces all D-247 placeholders before status changes.
- TC-247-03 separates navigation from sending. A real normal composer submit may be a preservation control, but the announcement action itself must make zero delivery calls.
- TC-247-05 needs a source/constructor census because group conversations are opened from several app surfaces with different dependency owners; a single happy route is insufficient.

## Implementation Steps

1. Resolve D-247-01..04 in `Test-Flight-Improv/247-private-reply-decision.md`, recording exact action copy, eligibility matrix, context fields, and exception behavior; keep status evidence-gated until then.
2. After acceptance, add TC-247-01/02/03/05/07 before production edits and record causal RED/Go GREEN separately.
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

- Expected evidence RED: D-247-01..04 have no approved answers in HEAD or current product docs.
- Expected causal RED after evidence: TC-247-01 compile-fails because no private-route policy/action exists.
- Green sentinel: announcement read-only/reaction behavior and Go publisher rejection stay GREEN.
- Pre-existing dirty tree / known failure: record at execution start; do not absorb unrelated work.
- Evidence blocker: missing label, eligibility, context/privacy, or exceptional-state decision keeps the plan evidence-gated and the action absent.
- Environment blocker: none after evidence; host routes/fakes and Go unit tests close this navigation-only slice.
- Scope drift: any automatic send, cross-lane quote field, payload/schema, group write relaxation, Bridge/P2P/relay, or Go production edit blocks completion.

- [ ] D-247-01..04 are concretely accepted and reflected in every relevant test row/copy.
- [ ] Every post-decision behavior has a causal test or preservation sentinel.
- [ ] Current-item routing, revalidation, all production entry surfaces, zero-auto-send, context minimization, and localization pass.
- [ ] Announcement group and 1:1 preservation gates pass; Go/relay no-diff and authorization sentinels are green.
- [ ] Representative stale-item, blocked-contact, double-tap, auto-send, raw-map, and missing-caller mutations re-red.
- [ ] Analyzer/diff hygiene and scope guard pass.

## Handoff

- First action: product/privacy must create and accept `Test-Flight-Improv/247-private-reply-decision.md` with D-247-01..04; do not add UI before that.
- First causal RED after acceptance: `flutter test test/features/groups/application/announcement_private_reply_policy_test.dart --plain-name 'accepted private-reply matrix is exact and fail closed'`.
- Preservation command: `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'announcement readers stay read-only for compose but still keep reaction entry'`.
- Manual registration: add new group-owned headline files to `GROUP_TESTS`; add the no-auto-send integration to 1:1 arrays only if it executes the real direct route fixture.
- Migration: none.
- Boundary closure: host callback/navigation plus existing pinned Go authorization; no device/relay proof.
- Unresolved evidence: action naming, unknown-sender policy, context minimization, and exceptional-state semantics D-247-01..04.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | evidence gate | - | - | no accepted cross-lane reply policy | D-247-01..04 unresolved | product/privacy decision |
