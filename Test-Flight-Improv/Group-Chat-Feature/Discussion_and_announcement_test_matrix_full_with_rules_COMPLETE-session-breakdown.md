# Discussion and Announcement Test Matrix Row Breakdown

## Recommended Plan Count

- recommended plan count: 118
- default posture held: one matrix row = one session
- added prerequisite sessions: 0
- added closure-only sessions: 0

## Decomposition Artifact

- artifact path: `/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`
- generated from source matrix: `/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- generated on: 2026-04-11
- workflow executed in order: Matrix Intake -> Row Inventory -> Evidence Map -> Row Disposition -> Dependency Pass -> Breakdown Write
- adjacent breakdown present at intake: no
- source rows inventoried: 118
- ordered sessions written: 118
- unresolved row-owned sessions remaining after decomposition: 60
- disposition counts: covered_in_repo=50, needs_tests_only=14, needs_code_and_tests=28, needs_repo_evidence=5, repo_external_proof=4, blocked_by_prerequisite=9, unsupported_product_scope=8

## Overall Closure Bar

- overall verdict: `still_open`
- closure bar: this rollout does not close until every non-unsupported source row is either proven `covered_in_repo` with concrete evidence or executed through its row-owned plan and then updated in the source matrix.
- row-owned truth rule: later closure must report final truth per source row id, not only per subsystem or seam.
- unsupported rows rule: rows classified `unsupported_product_scope` stay explicitly out of implementation scope unless product scope changes.

## Source Of Truth

- primary matrix: `/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- repo coverage inventory: `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- create / send / receive / invite / recovery docs:
  - `Test-Flight-Improv/Group-Chat-Feature/C4-01-Create-Discussion.md`
  - `Test-Flight-Improv/Group-Chat-Feature/C4-02-Send-Message.md`
  - `Test-Flight-Improv/Group-Chat-Feature/C4-03-Receive-Message.md`
  - `Test-Flight-Improv/Group-Chat-Feature/C4-04-Invite-And-Join.md`
  - `Test-Flight-Improv/Group-Chat-Feature/C4-05-Recovery-And-Reliability.md`
- audit context: `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`
- current repo code and tests override stale prose when they materially disagree.

## Matrix Row Inventory

| source row id | scenario | priority | source section or table | provisional row disposition | intended session id |
|---|---|---|---|---|---|
| CB-001 | Blank-name create auto-generates a stable, readable group name | P1 | Create, Bootstrap, and Configuration Truth | covered_in_repo | CB-001 |
| CB-002 | Create blocks over-limit selection before any local or bridge state is created | P0 | Create, Bootstrap, and Configuration Truth | covered_in_repo | CB-002 |
| CB-003 | Partial per-member add failure during create yields a truthful successful subset only | P0 | Create, Bootstrap, and Configuration Truth | needs_tests_only | CB-003 |
| CB-004 | Create-time invite degradation is explicit when node is stopped, recipient has no ML-KEM key, or direct send fails | P0 | Create, Bootstrap, and Configuration Truth | needs_code_and_tests | CB-004 |
| CB-005 | Post-create `group:updateConfig` or `members_added` publish failure does not leave ghost local membership | P0 | Create, Bootstrap, and Configuration Truth | needs_code_and_tests | CB-005 |
| CB-006 | Create-time description support is honest | P1 | Create, Bootstrap, and Configuration Truth | needs_repo_evidence | CB-006 |
| CB-007 | Persisted topic namespace matches the real `/mknoon/group/{groupId}` namespace | P1 | Create, Bootstrap, and Configuration Truth | needs_repo_evidence | CB-007 |
| CB-008 | Group create never reports success into a locally keyless state | P0 | Create, Bootstrap, and Configuration Truth | needs_code_and_tests | CB-008 |
| DV-001 | Create discussion group successfully | P0 | Membership Visibility and Invite Lifecycle | covered_in_repo | DV-001 |
| DV-002 | Create announcement group successfully with admin-only compose | P0 | Membership Visibility and Invite Lifecycle | covered_in_repo | DV-002 |
| DV-003 | Adding members shows immediate feedback and a durable in-chat add-members event | P0 | Membership Visibility and Invite Lifecycle | needs_code_and_tests | DV-003 |
| DV-004 | Accepting a pending invite creates a durable join / acceptance event visible to existing members | P0 | Membership Visibility and Invite Lifecycle | needs_code_and_tests | DV-004 |
| DV-005 | Invite decline and expiry leave no ghost membership or ghost access | P0 | Membership Visibility and Invite Lifecycle | covered_in_repo | DV-005 |
| DV-006 | Removing a member updates lists and creates a durable removal event for remaining members | P0 | Membership Visibility and Invite Lifecycle | covered_in_repo | DV-006 |
| DV-007 | Removed member converges to removed state after offline reconnect | P0 | Membership Visibility and Invite Lifecycle | covered_in_repo | DV-007 |
| DV-008 | Voluntary leave creates a durable `X left the group` event visible to remaining members | P1 | Membership Visibility and Invite Lifecycle | needs_code_and_tests | DV-008 |
| DV-009 | Duplicate invite preview for the same group replaces the earlier pending row instead of duplicating cards | P1 | Membership Visibility and Invite Lifecycle | covered_in_repo | DV-009 |
| DV-010 | Blocked, unknown, or sender-mismatch invites are rejected without ghost pending or joined state | P0 | Membership Visibility and Invite Lifecycle | covered_in_repo | DV-010 |
| DV-011 | Pending-invite route target opens the review surface until the group is actually joined | P1 | Membership Visibility and Invite Lifecycle | covered_in_repo | DV-011 |
| DV-012 | Accepting or declining an invite on one device does not incorrectly clear the sibling device pending row | P1 | Membership Visibility and Invite Lifecycle | covered_in_repo | DV-012 |
| DV-013 | Partial invite fan-out result is explicit per recipient | P0 | Membership Visibility and Invite Lifecycle | needs_code_and_tests | DV-013 |
| DV-014 | Batch add with no latest group key is explicit and does not silently look like completed onboarding | P0 | Membership Visibility and Invite Lifecycle | needs_code_and_tests | DV-014 |
| DV-015 | Remove, rotate, and re-invite gives the rejoined member the correct rotated epoch | P0 | Membership Visibility and Invite Lifecycle | covered_in_repo | DV-015 |
| DV-016 | New-member history boundary stays future-only except for the explicitly allowed post-join replay contract | P0 | Membership Visibility and Invite Lifecycle | covered_in_repo | DV-016 |
| ID-001 | Creator/admin identity resolves to username instead of raw peer ID when a username exists | P0 | Identity, Roles, Avatars, and Mixed-Social-Graph Behavior | needs_code_and_tests | ID-001 |
| ID-002 | Member list and conversation surfaces show consistent participant identity, including avatars, for current members | P1 | Identity, Roles, Avatars, and Mixed-Social-Graph Behavior | needs_code_and_tests | ID-002 |
| ID-003 | Once membership exists, non-friend members can still read and write in the same discussion group | P0 | Identity, Roles, Avatars, and Mixed-Social-Graph Behavior | needs_tests_only | ID-003 |
| ID-004 | Supported onboarding path exists for non-friend participants when product scope says mixed-social-graph groups are allowed | P1 | Identity, Roles, Avatars, and Mixed-Social-Graph Behavior | needs_repo_evidence | ID-004 |
| ID-005 | Admin promotion and demotion update permissions, badges, and visible timeline history consistently | P0 | Identity, Roles, Avatars, and Mixed-Social-Graph Behavior | covered_in_repo | ID-005 |
| ID-006 | Sole-admin leave stays blocked until a valid admin state exists | P0 | Identity, Roles, Avatars, and Mixed-Social-Graph Behavior | covered_in_repo | ID-006 |
| ID-007 | Explicit admin transfer or ownership handoff behaves cleanly if the feature exists | P2 | Identity, Roles, Avatars, and Mixed-Social-Graph Behavior | unsupported_product_scope | ID-007 |
| ID-008 | Duplicate re-add, duplicate invite, or stale membership replay does not create duplicate member rows or duplicate timeline spam | P1 | Identity, Roles, Avatars, and Mixed-Social-Graph Behavior | needs_tests_only | ID-008 |
| ID-009 | Invite-carried avatar metadata persists and resolves cleanly after accept | P1 | Identity, Roles, Avatars, and Mixed-Social-Graph Behavior | needs_tests_only | ID-009 |
| ID-010 | Non-friend fallback identity and avatar remain readable when full avatar sharing is unavailable | P1 | Identity, Roles, Avatars, and Mixed-Social-Graph Behavior | needs_code_and_tests | ID-010 |
| CX-001 | Long-pressing a supported group message opens one coherent context surface, not only a detached reaction bar | P1 | Long-Press Context Actions and Overlay Parity | needs_code_and_tests | CX-001 |
| CX-002 | Group long-press reply entry reaches the existing quote-reply path for supported messages | P1 | Long-Press Context Actions and Overlay Parity | needs_code_and_tests | CX-002 |
| CX-003 | Group long-press copy action copies exact text for supported rows and dismisses cleanly | P1 | Long-Press Context Actions and Overlay Parity | needs_code_and_tests | CX-003 |
| CX-004 | Unsupported group edit/delete actions stay honestly hidden without blocking the rest of the context surface | P1 | Long-Press Context Actions and Overlay Parity | needs_code_and_tests | CX-004 |
| CX-005 | Local-only long-press actions remain available even when reactions are unavailable | P1 | Long-Press Context Actions and Overlay Parity | needs_code_and_tests | CX-005 |
| CX-006 | Any future group long-press overlay preserves swipe-to-quote, reaction toggles, and current row rendering | P1 | Long-Press Context Actions and Overlay Parity | needs_code_and_tests | CX-006 |
| CX-007 | Group action parity stays consistent regardless of whether the conversation was entered from `Orbit`, `Feed`, or a notification anchor | P1 | Long-Press Context Actions and Overlay Parity | needs_tests_only | CX-007 |
| UI-001 | Each group message renders as one clear bubble without a doubled or stacked-card artifact | P1 | Message Rendering and Visual Stability | needs_code_and_tests | UI-001 |
| UI-002 | Row-shell stability survives quote enrichment, reaction updates, media auto-download, and replay enrichment | P1 | Message Rendering and Visual Stability | needs_tests_only | UI-002 |
| RX-001 | Tapping a visible group reaction chip reveals which members reacted and with which emoji | P1 | Reaction Transparency and Participant Identity | needs_code_and_tests | RX-001 |
| RX-002 | Inspecting a group reaction cluster is non-destructive and does not silently remove the viewer's own reaction | P1 | Reaction Transparency and Participant Identity | needs_code_and_tests | RX-002 |
| RX-003 | Reaction participant identity stays readable even when reaction rows only persist peer IDs or when reactors are non-friends | P1 | Reaction Transparency and Participant Identity | needs_code_and_tests | RX-003 |
| RX-004 | Reaction inspection parity is preserved across `Orbit` and `Feed` entry points | P1 | Reaction Transparency and Participant Identity | needs_code_and_tests | RX-004 |
| RX-005 | Inline Feed group-thread reactions and permissions behave coherently if inline interaction stays in scope | P1 | Reaction Transparency and Participant Identity | needs_code_and_tests | RX-005 |
| RX-006 | Live, replayed, and post-rotation reactions remain truthful after resume/rejoin | P1 | Reaction Transparency and Participant Identity | needs_tests_only | RX-006 |
| MM-001 | Discussion members can send text, media, replies, and reactions to all current members | P0 | Messaging, Compose, Media, Voice, and Delivery Truth | covered_in_repo | MM-001 |
| MM-002 | Announcement groups enforce admin-only compose while readers still see and react | P0 | Messaging, Compose, Media, Voice, and Delivery Truth | covered_in_repo | MM-002 |
| MM-003 | Voice-only send is supported, empty non-media send is blocked, and announcement readers never expose stale send/record controls | P1 | Messaging, Compose, Media, Voice, and Delivery Truth | covered_in_repo | MM-003 |
| MM-004 | Quote reply survives send, render, failure, and retry paths without losing user intent | P1 | Messaging, Compose, Media, Voice, and Delivery Truth | covered_in_repo | MM-004 |
| MM-005 | Media upload failure leaves a truthful failed/retryable row, and targeted retry/delete only affects that row | P1 | Messaging, Compose, Media, Voice, and Delivery Truth | covered_in_repo | MM-005 |
| MM-006 | The sender-facing state machine stays honest across publish success, publish timeout, no-peer fallback, inbox failure, and retry | P0 | Messaging, Compose, Media, Voice, and Delivery Truth | covered_in_repo | MM-006 |
| MM-007 | Publish timeout plus inbox success remains successful in UI and storage | P0 | Messaging, Compose, Media, Voice, and Delivery Truth | covered_in_repo | MM-007 |
| MM-008 | Publish-success pending rows finalize only through an owned path, not silent drift | P1 | Messaging, Compose, Media, Voice, and Delivery Truth | needs_tests_only | MM-008 |
| MM-009 | Zero-peer plus inbox-fail sends recover through one explicit retry owner and never get stranded between retry lanes | P1 | Messaging, Compose, Media, Voice, and Delivery Truth | needs_code_and_tests | MM-009 |
| MM-010 | Discussion and announcement sends survive background, route unmount, and zero-peer fallback with honest final status | P0 | Messaging, Compose, Media, Voice, and Delivery Truth | needs_tests_only | MM-010 |
| MM-011 | Legacy `topicPeers == null` bridge compatibility preserves truthful terminal state | P1 | Messaging, Compose, Media, Voice, and Delivery Truth | covered_in_repo | MM-011 |
| MM-012 | Send rules during active group recovery are explicit and intentional | P1 | Messaging, Compose, Media, Voice, and Delivery Truth | needs_tests_only | MM-012 |
| MM-013 | Non-friend member media delivery works the same as friend media delivery once membership exists | P0 | Messaging, Compose, Media, Voice, and Delivery Truth | needs_tests_only | MM-013 |
| MM-014 | Share-to-group respects write eligibility and partial-failure truth across writable groups | P1 | Messaging, Compose, Media, Voice, and Delivery Truth | covered_in_repo | MM-014 |
| MM-015 | Announcement sends after key rotation still use the new epoch and remain deliverable | P1 | Messaging, Compose, Media, Voice, and Delivery Truth | covered_in_repo | MM-015 |
| RC-001 | Live receive plus replay dedupe prevents duplicate visible rows when pubsub and inbox both deliver the same message | P0 | Receive, Rendering, Notification, and Conversation Integrity | covered_in_repo | RC-001 |
| RC-002 | Duplicate replay enriches missing quote/media metadata rather than creating a second row | P1 | Receive, Rendering, Notification, and Conversation Integrity | covered_in_repo | RC-002 |
| RC-003 | Unknown-group, unauthorized-sender, post-removal, and post-dissolve messages do not appear beyond allowed cutoffs | P0 | Receive, Rendering, Notification, and Conversation Integrity | covered_in_repo | RC-003 |
| RC-004 | Sequential messages, delayed delivery, and burst traffic preserve ordering and avoid user-visible loss within supported capacity | P1 | Receive, Rendering, Notification, and Conversation Integrity | covered_in_repo | RC-004 |
| RC-005 | A sibling device for the same user stores own live publishes as local sent history | P1 | Receive, Rendering, Notification, and Conversation Integrity | covered_in_repo | RC-005 |
| RC-006 | Media auto-download and row upsert do not create duplicate rows or destroy scroll/context | P1 | Receive, Rendering, Notification, and Conversation Integrity | needs_tests_only | RC-006 |
| RC-007 | Notification anchors open the group and highlight the targeted message context | P1 | Receive, Rendering, Notification, and Conversation Integrity | covered_in_repo | RC-007 |
| RC-008 | Notification truth suppresses own-message, active-conversation, and recent-remote-push duplicate alerts | P1 | Receive, Rendering, Notification, and Conversation Integrity | covered_in_repo | RC-008 |
| RC-009 | Decryption failure or payload-parse failure creates no ghost message and remains diagnosable | P1 | Receive, Rendering, Notification, and Conversation Integrity | repo_external_proof | RC-009 |
| RC-010 | Dispatcher overflow or high-burst receive load has an owned contract and monitoring story | P1 | Receive, Rendering, Notification, and Conversation Integrity | repo_external_proof | RC-010 |
| RY-001 | Cold-start rejoin and drain re-establish live delivery exactly once | P0 | Recovery, Replay, Retention, and Offline Privacy | covered_in_repo | RY-001 |
| RY-002 | Foreground resume runs rejoin, drain, stuck-send recovery, upload retry, failed-send retry, and inbox retry in the intended order | P1 | Recovery, Replay, Retention, and Offline Privacy | covered_in_repo | RY-002 |
| RY-003 | Paused / hidden lifecycle pre-commits `sending` rows to failed so later recovery can pick them up | P0 | Recovery, Replay, Retention, and Offline Privacy | covered_in_repo | RY-003 |
| RY-004 | Watchdog or node-requested recovery acknowledges only after a clean rejoin | P1 | Recovery, Replay, Retention, and Offline Privacy | covered_in_repo | RY-004 |
| RY-005 | Archived groups still drain/rejoin as intended while dissolved groups stay read-only and skipped from rejoin | P1 | Recovery, Replay, Retention, and Offline Privacy | covered_in_repo | RY-005 |
| RY-006 | Multi-page cursor drain recovers backlog exactly once across pages and cursor continuation | P1 | Recovery, Replay, Retention, and Offline Privacy | covered_in_repo | RY-006 |
| RY-007 | Partition heal and delayed delivery converge without duplicates and resume live delivery | P0 | Recovery, Replay, Retention, and Offline Privacy | needs_code_and_tests | RY-007 |
| RY-008 | Recovery does not burst all joined groups at once | P1 | Recovery, Replay, Retention, and Offline Privacy | covered_in_repo | RY-008 |
| RY-009 | Long-offline mixed-window recovery keeps retained backlog, drops expired non-system backlog, still applies old system membership events, and surfaces truthful retention messaging | P1 | Recovery, Replay, Retention, and Offline Privacy | covered_in_repo | RY-009 |
| RY-010 | Replay without `GroupMessageListener` or without `reactionRepo` never silently claims full convergence | P1 | Recovery, Replay, Retention, and Offline Privacy | needs_code_and_tests | RY-010 |
| RY-011 | Invite-accept drain includes offline reactions in the same user-visible catch-up window, or the deferred model is explicitly owned | P1 | Recovery, Replay, Retention, and Offline Privacy | needs_code_and_tests | RY-011 |
| RY-012 | Invite acceptance that returns `bridgeError` still converges to a live joined group without needing the invite row again | P1 | Recovery, Replay, Retention, and Offline Privacy | needs_code_and_tests | RY-012 |
| RY-013 | Offline group replay payloads stored on the relay are opaque to relay operators | P0 | Recovery, Replay, Retention, and Offline Privacy | blocked_by_prerequisite | RY-013 |
| RY-014 | Encrypted replay remains seamless for text, replies, image, video, GIF/file, and recorded voice | P0 | Recovery, Replay, Retention, and Offline Privacy | blocked_by_prerequisite | RY-014 |
| RY-015 | Encrypted replay respects add/remove/leave membership boundaries | P0 | Recovery, Replay, Retention, and Offline Privacy | blocked_by_prerequisite | RY-015 |
| RY-016 | Encrypted replay remains reliable through retry, resume, cursor drain, reconnect, and dedupe | P0 | Recovery, Replay, Retention, and Offline Privacy | blocked_by_prerequisite | RY-016 |
| MD-001 | Same-user live publishes on a sibling device store as local sent history without duplicate unread or notification confusion | P1 | Multi-Device and Cross-Surface Convergence | covered_in_repo | MD-001 |
| MD-002 | Membership updates converge across sibling devices without duplicate local membership or role drift | P1 | Multi-Device and Cross-Surface Convergence | covered_in_repo | MD-002 |
| MD-003 | Mute, unread, and local notifications stay device-local across sibling devices | P1 | Multi-Device and Cross-Surface Convergence | covered_in_repo | MD-003 |
| MD-004 | True device/simulator multi-device E2E proves sibling-device behavior beyond in-memory fakes | P1 | Multi-Device and Cross-Surface Convergence | repo_external_proof | MD-004 |
| MD-005 | Message-level behavior stays consistent when entering the same group from `Orbit`, `Feed`, or push | P1 | Multi-Device and Cross-Surface Convergence | needs_tests_only | MD-005 |
| MD-006 | Group-message and group-invite push routes navigate to the correct surface | P1 | Multi-Device and Cross-Surface Convergence | covered_in_repo | MD-006 |
| SV-001 | Only current members can publish discussion messages; unauthorized peers do not create visible rows | P0 | Security, Validator, Bridge-Contract, and Observability | covered_in_repo | SV-001 |
| SV-002 | Announcement readers cannot bypass write restrictions via stale callbacks or raw publish | P0 | Security, Validator, Bridge-Contract, and Observability | covered_in_repo | SV-002 |
| SV-003 | Removed members are only accepted for delayed pre-cutoff traffic, not post-cutoff traffic | P0 | Security, Validator, Bridge-Contract, and Observability | covered_in_repo | SV-003 |
| SV-004 | Replay attack with tampered timestamps or reordered envelopes does not create duplicate visible messages or bypass cutoffs | P1 | Security, Validator, Bridge-Contract, and Observability | blocked_by_prerequisite | SV-004 |
| SV-005 | Tampered payload, wrong key, tampered nonce, or tampered ciphertext creates no visible message and yields diagnosable rejection | P1 | Security, Validator, Bridge-Contract, and Observability | blocked_by_prerequisite | SV-005 |
| SV-006 | Previous-key grace during rotation accepts legitimate in-flight traffic without reopening indefinite stale-key access | P1 | Security, Validator, Bridge-Contract, and Observability | blocked_by_prerequisite | SV-006 |
| SV-007 | Concurrent key-rotation races across admins converge to one final usable epoch | P1 | Security, Validator, Bridge-Contract, and Observability | blocked_by_prerequisite | SV-007 |
| SV-008 | Concurrent remove/promote or remove/rotate conflicts converge to one final visible member/admin map and usable key state | P1 | Security, Validator, Bridge-Contract, and Observability | needs_tests_only | SV-008 |
| SV-009 | Description pass-through between Dart and Go is explicit and tested if create-time description is supported | P2 | Security, Validator, Bridge-Contract, and Observability | unsupported_product_scope | SV-009 |
| SV-010 | Topic namespace / `topicName` contract between Go and Dart is explicit and tested | P1 | Security, Validator, Bridge-Contract, and Observability | needs_repo_evidence | SV-010 |
| SV-011 | Flow-event names and payload shapes for group timing/recovery/retry observability are pinned | P2 | Security, Validator, Bridge-Contract, and Observability | needs_repo_evidence | SV-011 |
| SV-012 | Native dispatcher overflow or dropped diagnostics are surfaced to monitoring instead of remaining silent | P2 | Security, Validator, Bridge-Contract, and Observability | blocked_by_prerequisite | SV-012 |
| UX-001 | Per-group mute suppresses notifications without dropping delivery | P1 | Quality-of-Life and Higher-Level Product Capabilities | covered_in_repo | UX-001 |
| UX-002 | Dissolving the group keeps history readable but blocks further writing | P1 | Quality-of-Life and Higher-Level Product Capabilities | covered_in_repo | UX-002 |
| UX-003 | Search inside group history works if the feature exists | P2 | Quality-of-Life and Higher-Level Product Capabilities | unsupported_product_scope | UX-003 |
| UX-004 | Pinning and unpinning important messages works if the feature exists | P2 | Quality-of-Life and Higher-Level Product Capabilities | unsupported_product_scope | UX-004 |
| UX-005 | Per-message edit, delete, or tombstone works if the feature exists | P2 | Quality-of-Life and Higher-Level Product Capabilities | unsupported_product_scope | UX-005 |
| UX-006 | Read receipts or reader counts work if the feature exists | P2 | Quality-of-Life and Higher-Level Product Capabilities | unsupported_product_scope | UX-006 |
| UX-007 | Member-level moderation such as mute or ban works if the feature exists | P2 | Quality-of-Life and Higher-Level Product Capabilities | unsupported_product_scope | UX-007 |
| UX-008 | Scheduled announcements, edit-after-send, delete-after-send, or analytics work if the feature exists | P2 | Quality-of-Life and Higher-Level Product Capabilities | unsupported_product_scope | UX-008 |
| UX-009 | End-to-end push trigger path for group message and group invite is verified on real device if push is in scope | P1 | Quality-of-Life and Higher-Level Product Capabilities | repo_external_proof | UX-009 |
| UX-010 | Share-target picker shows only writable groups and respects announcement read-only filtering | P1 | Quality-of-Life and Higher-Level Product Capabilities | covered_in_repo | UX-010 |

## Row Traceability Rule

- every source row maps to exactly one session id in this artifact; no duplicate or seam-bucket collapse was introduced.
- session ids preserve the source row ids verbatim because every row id is filename-safe.
- later closure work must report final truth per source row, even when multiple rows touch the same code-entry files or test harnesses.

## Session Ledger

| session id | source row id | priority | row disposition | session classification | execution ownership | dependency | intended plan file |
|---|---|---|---|---|---|---|---|
| CB-002 | CB-002 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CB-002-plan.md |
| CB-003 | CB-003 | P0 | needs_tests_only | implementation-ready | tests only | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CB-003-plan.md |
| CB-004 | CB-004 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CB-004-plan.md |
| CB-005 | CB-005 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CB-005-plan.md |
| CB-008 | CB-008 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CB-008-plan.md |
| DV-001 | DV-001 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-001-plan.md |
| DV-002 | DV-002 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-002-plan.md |
| DV-003 | DV-003 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-003-plan.md |
| DV-004 | DV-004 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-004-plan.md |
| DV-005 | DV-005 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-005-plan.md |
| DV-006 | DV-006 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-006-plan.md |
| DV-007 | DV-007 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-007-plan.md |
| DV-010 | DV-010 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-010-plan.md |
| DV-013 | DV-013 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-013-plan.md |
| DV-014 | DV-014 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-014-plan.md |
| DV-015 | DV-015 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-015-plan.md |
| DV-016 | DV-016 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-016-plan.md |
| ID-001 | ID-001 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-001-plan.md |
| ID-003 | ID-003 | P0 | needs_tests_only | implementation-ready | tests only | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-003-plan.md |
| ID-005 | ID-005 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-005-plan.md |
| ID-006 | ID-006 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-006-plan.md |
| MM-001 | MM-001 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-001-plan.md |
| MM-002 | MM-002 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-002-plan.md |
| MM-006 | MM-006 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-006-plan.md |
| MM-007 | MM-007 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-007-plan.md |
| MM-010 | MM-010 | P0 | needs_tests_only | implementation-ready | tests only | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-010-plan.md |
| MM-013 | MM-013 | P0 | needs_tests_only | implementation-ready | tests only | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-013-plan.md |
| RC-001 | RC-001 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-001-plan.md |
| RC-003 | RC-003 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-003-plan.md |
| RY-001 | RY-001 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-001-plan.md |
| RY-003 | RY-003 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-003-plan.md |
| RY-007 | RY-007 | P0 | needs_code_and_tests | implementation-ready | code changes and tests | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-007-plan.md |
| RY-013 | RY-013 | P0 | blocked_by_prerequisite | prerequisite-blocked | evidence only until the blocking prerequisite exists | none in-repo; blocked by missing prerequisite feature or proof surface for this row | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-013-plan.md |
| RY-014 | RY-014 | P0 | blocked_by_prerequisite | prerequisite-blocked | evidence only until the blocking prerequisite exists | none in-repo; blocked by missing prerequisite feature or proof surface for this row | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-014-plan.md |
| RY-015 | RY-015 | P0 | blocked_by_prerequisite | prerequisite-blocked | evidence only until the blocking prerequisite exists | none in-repo; blocked by missing prerequisite feature or proof surface for this row | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-015-plan.md |
| RY-016 | RY-016 | P0 | blocked_by_prerequisite | prerequisite-blocked | evidence only until the blocking prerequisite exists | none in-repo; blocked by missing prerequisite feature or proof surface for this row | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-016-plan.md |
| SV-001 | SV-001 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-001-plan.md |
| SV-002 | SV-002 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-002-plan.md |
| SV-003 | SV-003 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-003-plan.md |
| CB-001 | CB-001 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CB-001-plan.md |
| CB-006 | CB-006 | P1 | needs_repo_evidence | evidence-gated | evidence only inside the current repo scope | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CB-006-plan.md |
| CB-007 | CB-007 | P1 | needs_repo_evidence | evidence-gated | evidence only inside the current repo scope | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CB-007-plan.md |
| DV-008 | DV-008 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-008-plan.md |
| DV-009 | DV-009 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-009-plan.md |
| DV-011 | DV-011 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-011-plan.md |
| DV-012 | DV-012 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-012-plan.md |
| ID-002 | ID-002 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-002-plan.md |
| ID-004 | ID-004 | P1 | needs_repo_evidence | evidence-gated | evidence only inside the current repo scope | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-004-plan.md |
| ID-008 | ID-008 | P1 | needs_tests_only | implementation-ready | tests only | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-008-plan.md |
| ID-009 | ID-009 | P1 | needs_tests_only | implementation-ready | tests only | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-009-plan.md |
| ID-010 | ID-010 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-010-plan.md |
| CX-001 | CX-001 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CX-001-plan.md |
| CX-002 | CX-002 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CX-002-plan.md |
| CX-003 | CX-003 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CX-003-plan.md |
| CX-004 | CX-004 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CX-004-plan.md |
| CX-005 | CX-005 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CX-005-plan.md |
| CX-006 | CX-006 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CX-006-plan.md |
| CX-007 | CX-007 | P1 | needs_tests_only | implementation-ready | tests only | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CX-007-plan.md |
| UI-001 | UI-001 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UI-001-plan.md |
| UI-002 | UI-002 | P1 | needs_tests_only | implementation-ready | tests only | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UI-002-plan.md |
| RX-001 | RX-001 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RX-001-plan.md |
| RX-002 | RX-002 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RX-002-plan.md |
| RX-003 | RX-003 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RX-003-plan.md |
| RX-004 | RX-004 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RX-004-plan.md |
| RX-005 | RX-005 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RX-005-plan.md |
| RX-006 | RX-006 | P1 | needs_tests_only | implementation-ready | tests only | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RX-006-plan.md |
| MM-003 | MM-003 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-003-plan.md |
| MM-004 | MM-004 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-004-plan.md |
| MM-005 | MM-005 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-005-plan.md |
| MM-008 | MM-008 | P1 | needs_tests_only | implementation-ready | tests only | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-008-plan.md |
| MM-009 | MM-009 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-009-plan.md |
| MM-011 | MM-011 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-011-plan.md |
| MM-012 | MM-012 | P1 | needs_tests_only | implementation-ready | tests only | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-012-plan.md |
| MM-014 | MM-014 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-014-plan.md |
| MM-015 | MM-015 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-015-plan.md |
| RC-002 | RC-002 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-002-plan.md |
| RC-004 | RC-004 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-004-plan.md |
| RC-005 | RC-005 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-005-plan.md |
| RC-006 | RC-006 | P1 | needs_tests_only | implementation-ready | tests only | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-006-plan.md |
| RC-007 | RC-007 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-007-plan.md |
| RC-008 | RC-008 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-008-plan.md |
| RC-009 | RC-009 | P1 | repo_external_proof | evidence-gated | evidence only with external proof ownership | none in-repo; depends on external proof owner or device-lab / native / relay harness | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-009-plan.md |
| RC-010 | RC-010 | P1 | repo_external_proof | evidence-gated | evidence only with external proof ownership | none in-repo; depends on external proof owner or device-lab / native / relay harness | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-010-plan.md |
| RY-002 | RY-002 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-002-plan.md |
| RY-004 | RY-004 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-004-plan.md |
| RY-005 | RY-005 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-005-plan.md |
| RY-006 | RY-006 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-006-plan.md |
| RY-008 | RY-008 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-008-plan.md |
| RY-009 | RY-009 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-009-plan.md |
| RY-010 | RY-010 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-010-plan.md |
| RY-011 | RY-011 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-011-plan.md |
| RY-012 | RY-012 | P1 | needs_code_and_tests | implementation-ready | code changes and tests | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-012-plan.md |
| MD-001 | MD-001 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MD-001-plan.md |
| MD-002 | MD-002 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MD-002-plan.md |
| MD-003 | MD-003 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MD-003-plan.md |
| MD-004 | MD-004 | P1 | repo_external_proof | evidence-gated | evidence only with external proof ownership | none in-repo; depends on external proof owner or device-lab / native / relay harness | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MD-004-plan.md |
| MD-005 | MD-005 | P1 | needs_tests_only | implementation-ready | tests only | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MD-005-plan.md |
| MD-006 | MD-006 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MD-006-plan.md |
| SV-004 | SV-004 | P1 | blocked_by_prerequisite | prerequisite-blocked | evidence only until the blocking prerequisite exists | none in-repo; blocked by missing prerequisite feature or proof surface for this row | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-004-plan.md |
| SV-005 | SV-005 | P1 | blocked_by_prerequisite | prerequisite-blocked | evidence only until the blocking prerequisite exists | none in-repo; blocked by missing prerequisite feature or proof surface for this row | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-005-plan.md |
| SV-006 | SV-006 | P1 | blocked_by_prerequisite | prerequisite-blocked | evidence only until the blocking prerequisite exists | none in-repo; blocked by missing prerequisite feature or proof surface for this row | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-006-plan.md |
| SV-007 | SV-007 | P1 | blocked_by_prerequisite | prerequisite-blocked | evidence only until the blocking prerequisite exists | none in-repo; blocked by missing prerequisite feature or proof surface for this row | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-007-plan.md |
| SV-008 | SV-008 | P1 | needs_tests_only | implementation-ready | tests only | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-008-plan.md |
| SV-010 | SV-010 | P1 | needs_repo_evidence | evidence-gated | evidence only inside the current repo scope | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-010-plan.md |
| UX-001 | UX-001 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-001-plan.md |
| UX-002 | UX-002 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-002-plan.md |
| UX-009 | UX-009 | P1 | repo_external_proof | evidence-gated | evidence only with external proof ownership | none in-repo; depends on external proof owner or device-lab / native / relay harness | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-009-plan.md |
| UX-010 | UX-010 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-010-plan.md |
| ID-007 | ID-007 | P2 | unsupported_product_scope | stale/already-covered | no execution because the row is out of current product scope | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-007-plan.md |
| SV-009 | SV-009 | P2 | unsupported_product_scope | stale/already-covered | no execution because the row is out of current product scope | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-009-plan.md |
| SV-011 | SV-011 | P2 | needs_repo_evidence | evidence-gated | evidence only inside the current repo scope | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-011-plan.md |
| SV-012 | SV-012 | P2 | blocked_by_prerequisite | prerequisite-blocked | evidence only until the blocking prerequisite exists | none in-repo; blocked by missing prerequisite feature or proof surface for this row | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-012-plan.md |
| UX-003 | UX-003 | P2 | unsupported_product_scope | stale/already-covered | no execution because the row is out of current product scope | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-003-plan.md |
| UX-004 | UX-004 | P2 | unsupported_product_scope | stale/already-covered | no execution because the row is out of current product scope | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-004-plan.md |
| UX-005 | UX-005 | P2 | unsupported_product_scope | stale/already-covered | no execution because the row is out of current product scope | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-005-plan.md |
| UX-006 | UX-006 | P2 | unsupported_product_scope | stale/already-covered | no execution because the row is out of current product scope | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-006-plan.md |
| UX-007 | UX-007 | P2 | unsupported_product_scope | stale/already-covered | no execution because the row is out of current product scope | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-007-plan.md |
| UX-008 | UX-008 | P2 | unsupported_product_scope | stale/already-covered | no execution because the row is out of current product scope | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-008-plan.md |

## Ordered Session Breakdown

### Session CB-002
- source row id: `CB-002`
- scenario title: Create blocks over-limit selection before any local or bridge state is created
- source section: Create, Bootstrap, and Configuration Truth
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CB-002-plan.md`
- exact scope: Preserve the current repo truth for source row CB-002 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/update_group_metadata_use_case.dart`, `lib/features/groups/application/group_config_payload.dart`, `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
- existing tests or current proof: The test inventory shows limit enforcement for create and add paths, and the C4 create flow calls out pre-limit checking before bridge create. Current repo references: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/presentation/create_group_picker_wired_test.dart`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Smoke (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row CB-002; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session CB-003
- source row id: `CB-003`
- scenario title: Partial per-member add failure during create yields a truthful successful subset only
- source section: Create, Bootstrap, and Configuration Truth
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CB-003-plan.md`
- exact scope: Add row-specific regression proof for source row CB-003 without broadening scope beyond the exact user-visible contract in this row.
- execution ownership: tests only
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/update_group_metadata_use_case.dart`, `lib/features/groups/application/group_config_payload.dart`, `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
- existing tests or current proof: `C4-01` explicitly says create skips individual add failures, but the current docs do not prove a fully user-visible partial-failure contract. Current repo references: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/presentation/create_group_picker_wired_test.dart`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- likely missing tests: test/features/groups/application/create_group_with_members_use_case_test.dart, test/features/groups/application/create_group_use_case_test.dart, test/features/groups/presentation/create_group_picker_wired_test.dart
- likely named gates: Unit (Required), Integration (Required), Smoke (Recommended), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row CB-003; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session CB-004
- source row id: `CB-004`
- scenario title: Create-time invite degradation is explicit when node is stopped, recipient has no ML-KEM key, or direct send fails
- source section: Create, Bootstrap, and Configuration Truth
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CB-004-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row CB-004 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/update_group_metadata_use_case.dart`, `lib/features/groups/application/group_config_payload.dart`, `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
- existing tests or current proof: `sendGroupInvite()` returns `nodeNotRunning`, `encryptionRequired`, and send-failed outcomes, but the create flow still completes. The current user-visible per-recipient truth contract is not pinned. Current repo references: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/presentation/create_group_picker_wired_test.dart`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- likely missing tests: test/features/groups/application/create_group_with_members_use_case_test.dart, test/features/groups/application/create_group_use_case_test.dart, test/features/groups/presentation/create_group_picker_wired_test.dart
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row CB-004; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session CB-005
- source row id: `CB-005`
- scenario title: Post-create `group:updateConfig` or `members_added` publish failure does not leave ghost local membership
- source section: Create, Bootstrap, and Configuration Truth
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CB-005-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row CB-005 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/update_group_metadata_use_case.dart`, `lib/features/groups/application/group_config_payload.dart`, `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
- existing tests or current proof: `C4-04` explicitly says later update/publish failures do not roll back prior local saves in the invite path. Current repo references: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/presentation/create_group_picker_wired_test.dart`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- likely missing tests: test/features/groups/application/create_group_with_members_use_case_test.dart, test/features/groups/application/create_group_use_case_test.dart, test/features/groups/presentation/create_group_picker_wired_test.dart
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row CB-005; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session CB-008
- source row id: `CB-008`
- scenario title: Group create never reports success into a locally keyless state
- source section: Create, Bootstrap, and Configuration Truth
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CB-008-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row CB-008 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/update_group_metadata_use_case.dart`, `lib/features/groups/application/group_config_payload.dart`, `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
- existing tests or current proof: The audit and current matrix explicitly identify this as a remaining bootstrap-integrity gap. Current repo references: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/presentation/create_group_picker_wired_test.dart`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- likely missing tests: test/features/groups/application/create_group_with_members_use_case_test.dart, test/features/groups/application/create_group_use_case_test.dart, test/features/groups/presentation/create_group_picker_wired_test.dart
- likely named gates: Unit (Required), Integration (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row CB-008; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session DV-001
- source row id: `DV-001`
- scenario title: Create discussion group successfully
- source section: Membership Visibility and Invite Lifecycle
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-001-plan.md`
- exact scope: Preserve the current repo truth for source row DV-001 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- existing tests or current proof: Strong current create coverage is called out in the audit and test inventory. Current repo references: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/application/group_invite_listener_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Recommended), Integration (Required), Smoke (Required), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row DV-001; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session DV-002
- source row id: `DV-002`
- scenario title: Create announcement group successfully with admin-only compose
- source section: Membership Visibility and Invite Lifecycle
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-002-plan.md`
- exact scope: Preserve the current repo truth for source row DV-002 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- existing tests or current proof: Covered by announcement-path tests and the current matrix. Current repo references: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/application/group_invite_listener_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Smoke (Required), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row DV-002; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session DV-003
- source row id: `DV-003`
- scenario title: Adding members shows immediate feedback and a durable in-chat add-members event
- source section: Membership Visibility and Invite Lifecycle
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-003-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row DV-003 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- existing tests or current proof: The audit and current matrix both flag the missing durable `members_added` timeline behavior. Current repo references: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/application/group_invite_listener_test.dart`
- likely missing tests: test/features/groups/application/add_group_member_use_case_test.dart, test/features/groups/application/accept_pending_group_invite_use_case_test.dart, test/features/groups/application/decline_pending_group_invite_use_case_test.dart
- likely named gates: Unit (Required), Integration (Required), Smoke (Required), Fake Network (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row DV-003; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session DV-004
- source row id: `DV-004`
- scenario title: Accepting a pending invite creates a durable join / acceptance event visible to existing members
- source section: Membership Visibility and Invite Lifecycle
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-004-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row DV-004 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- existing tests or current proof: Explicitly called out as missing in the audit and current matrix. Current repo references: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/application/group_invite_listener_test.dart`
- likely missing tests: test/features/groups/application/add_group_member_use_case_test.dart, test/features/groups/application/accept_pending_group_invite_use_case_test.dart, test/features/groups/application/decline_pending_group_invite_use_case_test.dart
- likely named gates: Unit (Required), Integration (Required), Smoke (Recommended), Fake Network (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row DV-004; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session DV-005
- source row id: `DV-005`
- scenario title: Invite decline and expiry leave no ghost membership or ghost access
- source section: Membership Visibility and Invite Lifecycle
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-005-plan.md`
- exact scope: Preserve the current repo truth for source row DV-005 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- existing tests or current proof: Already covered by listener, accept/decline, and invite-round-trip tests. Current repo references: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/application/group_invite_listener_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row DV-005; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session DV-006
- source row id: `DV-006`
- scenario title: Removing a member updates lists and creates a durable removal event for remaining members
- source section: Membership Visibility and Invite Lifecycle
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-006-plan.md`
- exact scope: Preserve the current repo truth for source row DV-006 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- existing tests or current proof: Current repo coverage already proves the removal path and recipient-side timeline persistence. Current repo references: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/application/group_invite_listener_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Recommended), Integration (Required), Smoke (Required), Fake Network (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row DV-006; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session DV-007
- source row id: `DV-007`
- scenario title: Removed member converges to removed state after offline reconnect
- source section: Membership Visibility and Invite Lifecycle
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-007-plan.md`
- exact scope: Preserve the current repo truth for source row DV-007 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- existing tests or current proof: Explicitly covered in replay/recovery and membership smoke coverage. Current repo references: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/application/group_invite_listener_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Fake Network (Required), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row DV-007; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session DV-010
- source row id: `DV-010`
- scenario title: Blocked, unknown, or sender-mismatch invites are rejected without ghost pending or joined state
- source section: Membership Visibility and Invite Lifecycle
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-010-plan.md`
- exact scope: Preserve the current repo truth for source row DV-010 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- existing tests or current proof: The C4 invite flow and test inventory both document blocked-sender, unknown-sender, and sender-mismatch guards. Current repo references: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/application/group_invite_listener_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row DV-010; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session DV-013
- source row id: `DV-013`
- scenario title: Partial invite fan-out result is explicit per recipient
- source section: Membership Visibility and Invite Lifecycle
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-013-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row DV-013 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- existing tests or current proof: `C4-04` says the current UI pops with the locally added count even if some invite sends fail. Current repo references: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/application/group_invite_listener_test.dart`
- likely missing tests: test/features/groups/application/add_group_member_use_case_test.dart, test/features/groups/application/accept_pending_group_invite_use_case_test.dart, test/features/groups/application/decline_pending_group_invite_use_case_test.dart
- likely named gates: Unit (Required), Integration (Required), Smoke (Recommended), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row DV-013; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session DV-014
- source row id: `DV-014`
- scenario title: Batch add with no latest group key is explicit and does not silently look like completed onboarding
- source section: Membership Visibility and Invite Lifecycle
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-014-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row DV-014 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- existing tests or current proof: The invite path explicitly skips invite fan-out when no key exists, while still locally adding members. Current repo references: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/application/group_invite_listener_test.dart`
- likely missing tests: test/features/groups/application/add_group_member_use_case_test.dart, test/features/groups/application/accept_pending_group_invite_use_case_test.dart, test/features/groups/application/decline_pending_group_invite_use_case_test.dart
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row DV-014; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session DV-015
- source row id: `DV-015`
- scenario title: Remove, rotate, and re-invite gives the rejoined member the correct rotated epoch
- source section: Membership Visibility and Invite Lifecycle
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-015-plan.md`
- exact scope: Preserve the current repo truth for source row DV-015 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- existing tests or current proof: The invite-round-trip integration coverage already includes this path. Current repo references: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/application/group_invite_listener_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Recommended), Integration (Required), Fake Network (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row DV-015; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session DV-016
- source row id: `DV-016`
- scenario title: New-member history boundary stays future-only except for the explicitly allowed post-join replay contract
- source section: Membership Visibility and Invite Lifecycle
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-016-plan.md`
- exact scope: Preserve the current repo truth for source row DV-016 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- existing tests or current proof: Called out directly by the invite-round-trip integration tests. Current repo references: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/application/group_invite_listener_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row DV-016; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session ID-001
- source row id: `ID-001`
- scenario title: Creator/admin identity resolves to username instead of raw peer ID when a username exists
- source section: Identity, Roles, Avatars, and Mixed-Social-Graph Behavior
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-001-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row ID-001 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/presentation/widgets/group_member_row.dart`, `lib/features/groups/presentation/widgets/group_avatar.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/home/application/identity_avatar_resolver.dart`, `lib/features/home/presentation/widgets/user_avatar.dart`, `lib/features/groups/application/group_avatar_storage.dart`
- existing tests or current proof: The audit and current matrix both call out the missing creator-username backfill. Current repo references: `test/features/groups/presentation/group_info_wired_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/application/group_avatar_storage_test.dart`, `test/features/groups/integration/group_multi_device_convergence_test.dart`
- likely missing tests: test/features/groups/presentation/group_info_wired_test.dart, test/features/groups/presentation/group_conversation_wired_test.dart, test/features/groups/application/group_avatar_storage_test.dart
- likely named gates: Unit (Required), Integration (Required), Smoke (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row ID-001; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session ID-003
- source row id: `ID-003`
- scenario title: Once membership exists, non-friend members can still read and write in the same discussion group
- source section: Identity, Roles, Avatars, and Mixed-Social-Graph Behavior
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-003-plan.md`
- exact scope: Add row-specific regression proof for source row ID-003 without broadening scope beyond the exact user-visible contract in this row.
- execution ownership: tests only
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/presentation/widgets/group_member_row.dart`, `lib/features/groups/presentation/widgets/group_avatar.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/home/application/identity_avatar_resolver.dart`, `lib/features/home/presentation/widgets/user_avatar.dart`, `lib/features/groups/application/group_avatar_storage.dart`
- existing tests or current proof: The audit and current matrix both treat the transport as membership-driven, but note missing direct row-owned proof. Current repo references: `test/features/groups/presentation/group_info_wired_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/application/group_avatar_storage_test.dart`, `test/features/groups/integration/group_multi_device_convergence_test.dart`
- likely missing tests: test/features/groups/presentation/group_info_wired_test.dart, test/features/groups/presentation/group_conversation_wired_test.dart, test/features/groups/application/group_avatar_storage_test.dart
- likely named gates: Unit (Required), Integration (Required), Smoke (Recommended), Fake Network (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row ID-003; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session ID-005
- source row id: `ID-005`
- scenario title: Admin promotion and demotion update permissions, badges, and visible timeline history consistently
- source section: Identity, Roles, Avatars, and Mixed-Social-Graph Behavior
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-005-plan.md`
- exact scope: Preserve the current repo truth for source row ID-005 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/presentation/widgets/group_member_row.dart`, `lib/features/groups/presentation/widgets/group_avatar.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/home/application/identity_avatar_resolver.dart`, `lib/features/home/presentation/widgets/user_avatar.dart`, `lib/features/groups/application/group_avatar_storage.dart`
- existing tests or current proof: Explicitly covered by `group_info_wired_test.dart` and listener coverage per the audit. Current repo references: `group_info_wired_test.dart`, `test/features/groups/presentation/group_info_wired_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/application/group_avatar_storage_test.dart`, `test/features/groups/integration/group_multi_device_convergence_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Smoke (Recommended), Fake Network (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row ID-005; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session ID-006
- source row id: `ID-006`
- scenario title: Sole-admin leave stays blocked until a valid admin state exists
- source section: Identity, Roles, Avatars, and Mixed-Social-Graph Behavior
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-006-plan.md`
- exact scope: Preserve the current repo truth for source row ID-006 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/presentation/widgets/group_member_row.dart`, `lib/features/groups/presentation/widgets/group_avatar.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/home/application/identity_avatar_resolver.dart`, `lib/features/home/presentation/widgets/user_avatar.dart`, `lib/features/groups/application/group_avatar_storage.dart`
- existing tests or current proof: Membership smoke and leave-group coverage already prove the sole-admin guard. Current repo references: `test/features/groups/presentation/group_info_wired_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/application/group_avatar_storage_test.dart`, `test/features/groups/integration/group_multi_device_convergence_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Smoke (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row ID-006; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MM-001
- source row id: `MM-001`
- scenario title: Discussion members can send text, media, replies, and reactions to all current members
- source section: Messaging, Compose, Media, Voice, and Delivery Truth
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-001-plan.md`
- exact scope: Preserve the current repo truth for source row MM-001 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`, `lib/features/groups/presentation/widgets/group_compose_area.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/widgets/compose_area.dart`
- existing tests or current proof: Strong current coverage exists across send, receive, reaction, and smoke tests. Current repo references: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Recommended), Integration (Required), Smoke (Required), Fake Network (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MM-001; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MM-002
- source row id: `MM-002`
- scenario title: Announcement groups enforce admin-only compose while readers still see and react
- source section: Messaging, Compose, Media, Voice, and Delivery Truth
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-002-plan.md`
- exact scope: Preserve the current repo truth for source row MM-002 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`, `lib/features/groups/presentation/widgets/group_compose_area.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/widgets/compose_area.dart`
- existing tests or current proof: This is one of the strongest current shipped contracts. Current repo references: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Smoke (Required), Fake Network (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MM-002; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MM-006
- source row id: `MM-006`
- scenario title: The sender-facing state machine stays honest across publish success, publish timeout, no-peer fallback, inbox failure, and retry
- source section: Messaging, Compose, Media, Voice, and Delivery Truth
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-006-plan.md`
- exact scope: Preserve the current repo truth for source row MM-006 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`, `lib/features/groups/presentation/widgets/group_compose_area.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/widgets/compose_area.dart`
- existing tests or current proof: The send use-case matrix is already heavily covered in tests. Current repo references: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Smoke (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MM-006; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MM-007
- source row id: `MM-007`
- scenario title: Publish timeout plus inbox success remains successful in UI and storage
- source section: Messaging, Compose, Media, Voice, and Delivery Truth
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-007-plan.md`
- exact scope: Preserve the current repo truth for source row MM-007 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`, `lib/features/groups/presentation/widgets/group_compose_area.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/widgets/compose_area.dart`
- existing tests or current proof: Explicitly covered in the send use case and wired UI tests. Current repo references: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MM-007; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MM-010
- source row id: `MM-010`
- scenario title: Discussion and announcement sends survive background, route unmount, and zero-peer fallback with honest final status
- source section: Messaging, Compose, Media, Voice, and Delivery Truth
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-010-plan.md`
- exact scope: Add row-specific regression proof for source row MM-010 without broadening scope beyond the exact user-visible contract in this row.
- execution ownership: tests only
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`, `lib/features/groups/presentation/widgets/group_compose_area.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/widgets/compose_area.dart`
- existing tests or current proof: Strong coverage exists, but the test inventory still records skipped bg-task edge cases. Current repo references: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: test/features/groups/application/send_group_message_use_case_test.dart, test/features/groups/application/retry_failed_group_messages_use_case_test.dart, test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart
- likely named gates: Unit (Required), Integration (Required), Smoke (Required), Fake Network (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MM-010; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MM-013
- source row id: `MM-013`
- scenario title: Non-friend member media delivery works the same as friend media delivery once membership exists
- source section: Messaging, Compose, Media, Voice, and Delivery Truth
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-013-plan.md`
- exact scope: Add row-specific regression proof for source row MM-013 without broadening scope beyond the exact user-visible contract in this row.
- execution ownership: tests only
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`, `lib/features/groups/presentation/widgets/group_compose_area.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/widgets/compose_area.dart`
- existing tests or current proof: The audit already identifies this as membership-driven in code but not yet row-owned as a direct regression. Current repo references: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: test/features/groups/application/send_group_message_use_case_test.dart, test/features/groups/application/retry_failed_group_messages_use_case_test.dart, test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart
- likely named gates: Unit (Recommended), Integration (Required), Smoke (Recommended), Fake Network (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MM-013; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RC-001
- source row id: `RC-001`
- scenario title: Live receive plus replay dedupe prevents duplicate visible rows when pubsub and inbox both deliver the same message
- source section: Receive, Rendering, Notification, and Conversation Integrity
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-001-plan.md`
- exact scope: Preserve the current repo truth for source row RC-001 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- existing tests or current proof: Strongly covered in handle-incoming and resume-recovery tests. Current repo references: `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/notifications/notification_route_target_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Smoke (Recommended), Fake Network (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RC-001; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RC-003
- source row id: `RC-003`
- scenario title: Unknown-group, unauthorized-sender, post-removal, and post-dissolve messages do not appear beyond allowed cutoffs
- source section: Receive, Rendering, Notification, and Conversation Integrity
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-003-plan.md`
- exact scope: Preserve the current repo truth for source row RC-003 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- existing tests or current proof: The inventory shows direct cutoff and dissolve-boundary coverage. Current repo references: `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/notifications/notification_route_target_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RC-003; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RY-001
- source row id: `RY-001`
- scenario title: Cold-start rejoin and drain re-establish live delivery exactly once
- source section: Recovery, Replay, Retention, and Offline Privacy
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-001-plan.md`
- exact scope: Preserve the current repo truth for source row RY-001 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- existing tests or current proof: Startup-rejoin smoke coverage already exists. Current repo references: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`, `test/core/lifecycle/handle_app_paused_group_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Recommended), Integration (Required), Smoke (Recommended), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RY-001; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RY-003
- source row id: `RY-003`
- scenario title: Paused / hidden lifecycle pre-commits `sending` rows to failed so later recovery can pick them up
- source section: Recovery, Replay, Retention, and Offline Privacy
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-003-plan.md`
- exact scope: Preserve the current repo truth for source row RY-003 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- existing tests or current proof: `handleAppPaused` group tests explicitly cover this preventive reliability hook. Current repo references: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`, `test/core/lifecycle/handle_app_paused_group_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RY-003; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RY-007
- source row id: `RY-007`
- scenario title: Partition heal and delayed delivery converge without duplicates and resume live delivery
- source section: Recovery, Replay, Retention, and Offline Privacy
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-007-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row RY-007 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- existing tests or current proof: Recovery tests include partition-heal behavior, but the inventory still flags no dedicated multi-simulator proof. Current repo references: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`, `test/core/lifecycle/handle_app_paused_group_test.dart`
- likely missing tests: test/features/groups/application/drain_group_offline_inbox_use_case_test.dart, test/features/groups/application/rejoin_group_topics_use_case_test.dart, test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart
- likely named gates: Unit (Required), Integration (Required), Smoke (Recommended), Fake Network (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RY-007; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RY-013
- source row id: `RY-013`
- scenario title: Offline group replay payloads stored on the relay are opaque to relay operators
- source section: Recovery, Replay, Retention, and Offline Privacy
- row disposition: `blocked_by_prerequisite`
- session classification: `prerequisite-blocked`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-013-plan.md`
- exact scope: Hold source row RY-013 as row-owned work, but do not advance it past prerequisite-blocked until the missing feature or harness exists.
- execution ownership: evidence only until the blocking prerequisite exists
- proof ownership: blocked on missing prerequisite feature or proof harness
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- existing tests or current proof: The attached docs explicitly state current replay payloads are still plaintext. Current repo references: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`, `test/core/lifecycle/handle_app_paused_group_test.dart`
- likely missing tests: blocked on prerequisite feature or harness; add repo-local regression only after the prerequisite lands
- likely named gates: Unit (Required), Integration (Required), Fake Network (Required)
- dependency on earlier sessions: none in-repo; blocked by missing prerequisite feature or proof surface for this row
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RY-013; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RY-014
- source row id: `RY-014`
- scenario title: Encrypted replay remains seamless for text, replies, image, video, GIF/file, and recorded voice
- source section: Recovery, Replay, Retention, and Offline Privacy
- row disposition: `blocked_by_prerequisite`
- session classification: `prerequisite-blocked`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-014-plan.md`
- exact scope: Hold source row RY-014 as row-owned work, but do not advance it past prerequisite-blocked until the missing feature or harness exists.
- execution ownership: evidence only until the blocking prerequisite exists
- proof ownership: blocked on missing prerequisite feature or proof harness
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- existing tests or current proof: The audit and current matrix call this out as a required future contract, not yet a landed implementation. Current repo references: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`, `test/core/lifecycle/handle_app_paused_group_test.dart`
- likely missing tests: blocked on prerequisite feature or harness; add repo-local regression only after the prerequisite lands
- likely named gates: Unit (Required), Integration (Required), Smoke (Required), Fake Network (Required), 3-Party E2E (Required)
- dependency on earlier sessions: none in-repo; blocked by missing prerequisite feature or proof surface for this row
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RY-014; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RY-015
- source row id: `RY-015`
- scenario title: Encrypted replay respects add/remove/leave membership boundaries
- source section: Recovery, Replay, Retention, and Offline Privacy
- row disposition: `blocked_by_prerequisite`
- session classification: `prerequisite-blocked`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-015-plan.md`
- exact scope: Hold source row RY-015 as row-owned work, but do not advance it past prerequisite-blocked until the missing feature or harness exists.
- execution ownership: evidence only until the blocking prerequisite exists
- proof ownership: blocked on missing prerequisite feature or proof harness
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- existing tests or current proof: This is the membership-window promise implied by the audit and invariants. Current repo references: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`, `test/core/lifecycle/handle_app_paused_group_test.dart`
- likely missing tests: blocked on prerequisite feature or harness; add repo-local regression only after the prerequisite lands
- likely named gates: Unit (Required), Integration (Required), Fake Network (Required), 3-Party E2E (Required)
- dependency on earlier sessions: none in-repo; blocked by missing prerequisite feature or proof surface for this row
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RY-015; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RY-016
- source row id: `RY-016`
- scenario title: Encrypted replay remains reliable through retry, resume, cursor drain, reconnect, and dedupe
- source section: Recovery, Replay, Retention, and Offline Privacy
- row disposition: `blocked_by_prerequisite`
- session classification: `prerequisite-blocked`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-016-plan.md`
- exact scope: Hold source row RY-016 as row-owned work, but do not advance it past prerequisite-blocked until the missing feature or harness exists.
- execution ownership: evidence only until the blocking prerequisite exists
- proof ownership: blocked on missing prerequisite feature or proof harness
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- existing tests or current proof: The current docs treat this as a future parity requirement, not a shipped contract. Current repo references: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`, `test/core/lifecycle/handle_app_paused_group_test.dart`
- likely missing tests: blocked on prerequisite feature or harness; add repo-local regression only after the prerequisite lands
- likely named gates: Unit (Required), Integration (Required), Smoke (Recommended), Fake Network (Required), 3-Party E2E (Required)
- dependency on earlier sessions: none in-repo; blocked by missing prerequisite feature or proof surface for this row
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RY-016; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session SV-001
- source row id: `SV-001`
- scenario title: Only current members can publish discussion messages; unauthorized peers do not create visible rows
- source section: Security, Validator, Bridge-Contract, and Observability
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-001-plan.md`
- exact scope: Preserve the current repo truth for source row SV-001 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/domain/models/group_invite_payload.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `lib/core/utils/push_diagnostics_logger.dart`
- existing tests or current proof: The validator and membership-smoke coverage together already prove the membership gate story. Current repo references: `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/announcement_happy_path_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/domain/models/group_invite_payload_test.dart`, `test/features/groups/domain/models/group_message_payload_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row SV-001; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session SV-002
- source row id: `SV-002`
- scenario title: Announcement readers cannot bypass write restrictions via stale callbacks or raw publish
- source section: Security, Validator, Bridge-Contract, and Observability
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-002-plan.md`
- exact scope: Preserve the current repo truth for source row SV-002 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/domain/models/group_invite_payload.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `lib/core/utils/push_diagnostics_logger.dart`
- existing tests or current proof: The current tests already cover read-only mode plus stale callback protection. Current repo references: `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/announcement_happy_path_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/domain/models/group_invite_payload_test.dart`, `test/features/groups/domain/models/group_message_payload_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row SV-002; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session SV-003
- source row id: `SV-003`
- scenario title: Removed members are only accepted for delayed pre-cutoff traffic, not post-cutoff traffic
- source section: Security, Validator, Bridge-Contract, and Observability
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-003-plan.md`
- exact scope: Preserve the current repo truth for source row SV-003 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/domain/models/group_invite_payload.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `lib/core/utils/push_diagnostics_logger.dart`
- existing tests or current proof: Directly covered in incoming-message and resume-recovery tests. Current repo references: `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/announcement_happy_path_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/domain/models/group_invite_payload_test.dart`, `test/features/groups/domain/models/group_message_payload_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row SV-003; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session CB-001
- source row id: `CB-001`
- scenario title: Blank-name create auto-generates a stable, readable group name
- source section: Create, Bootstrap, and Configuration Truth
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CB-001-plan.md`
- exact scope: Preserve the current repo truth for source row CB-001 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/update_group_metadata_use_case.dart`, `lib/features/groups/application/group_config_payload.dart`, `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
- existing tests or current proof: Covered by `create_group_with_members_use_case_test.dart` auto-name cases and create-picker coverage in `test-inventory.md`. Current repo references: `create_group_with_members_use_case_test.dart`, `test-inventory.md`, `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/presentation/create_group_picker_wired_test.dart`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row CB-001; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session CB-006
- source row id: `CB-006`
- scenario title: Create-time description support is honest
- source section: Create, Bootstrap, and Configuration Truth
- row disposition: `needs_repo_evidence`
- session classification: `evidence-gated`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CB-006-plan.md`
- exact scope: Pin the current repo contract for source row CB-006 with row-specific proof and truth alignment before any broader seam work is claimed complete.
- execution ownership: evidence only inside the current repo scope
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/update_group_metadata_use_case.dart`, `lib/features/groups/application/group_config_payload.dart`, `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
- existing tests or current proof: `C4-01` says the active create UI does not expose description and Go `GroupCreate()` does not parse it. Current repo references: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/presentation/create_group_picker_wired_test.dart`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- likely missing tests: contract-pin or traceability tests around the cited boundary, plus matrix/doc truth alignment
- likely named gates: Unit (Required), Integration (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row CB-006; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session CB-007
- source row id: `CB-007`
- scenario title: Persisted topic namespace matches the real `/mknoon/group/{groupId}` namespace
- source section: Create, Bootstrap, and Configuration Truth
- row disposition: `needs_repo_evidence`
- session classification: `evidence-gated`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CB-007-plan.md`
- exact scope: Pin the current repo contract for source row CB-007 with row-specific proof and truth alignment before any broader seam work is claimed complete.
- execution ownership: evidence only inside the current repo scope
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/update_group_metadata_use_case.dart`, `lib/features/groups/application/group_config_payload.dart`, `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
- existing tests or current proof: `C4-01` and `test-inventory.md` both call out the topic-name mismatch gap. Current repo references: `test-inventory.md`, `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/presentation/create_group_picker_wired_test.dart`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- likely missing tests: contract-pin or traceability tests around the cited boundary, plus matrix/doc truth alignment
- likely named gates: Unit (Required), Integration (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row CB-007; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session DV-008
- source row id: `DV-008`
- scenario title: Voluntary leave creates a durable `X left the group` event visible to remaining members
- source section: Membership Visibility and Invite Lifecycle
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-008-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row DV-008 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- existing tests or current proof: The audit and current matrix flag this as only partially wired today. Current repo references: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/application/group_invite_listener_test.dart`
- likely missing tests: test/features/groups/application/add_group_member_use_case_test.dart, test/features/groups/application/accept_pending_group_invite_use_case_test.dart, test/features/groups/application/decline_pending_group_invite_use_case_test.dart
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row DV-008; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session DV-009
- source row id: `DV-009`
- scenario title: Duplicate invite preview for the same group replaces the earlier pending row instead of duplicating cards
- source section: Membership Visibility and Invite Lifecycle
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-009-plan.md`
- exact scope: Preserve the current repo truth for source row DV-009 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- existing tests or current proof: `PendingGroupInviteRepository` upserts by `group_id`; the listener test inventory already calls this out. Current repo references: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/application/group_invite_listener_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row DV-009; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session DV-011
- source row id: `DV-011`
- scenario title: Pending-invite route target opens the review surface until the group is actually joined
- source section: Membership Visibility and Invite Lifecycle
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-011-plan.md`
- exact scope: Preserve the current repo truth for source row DV-011 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- existing tests or current proof: `resolveGroupNotificationRouteTarget()` and the current C4 invite doc explicitly define this route behavior. Current repo references: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/application/group_invite_listener_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Recommended), Integration (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row DV-011; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session DV-012
- source row id: `DV-012`
- scenario title: Accepting or declining an invite on one device does not incorrectly clear the sibling device pending row
- source section: Membership Visibility and Invite Lifecycle
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-012-plan.md`
- exact scope: Preserve the current repo truth for source row DV-012 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- existing tests or current proof: The accept/decline tests explicitly cover sibling-device pending-row independence. Current repo references: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/application/group_invite_listener_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row DV-012; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session ID-002
- source row id: `ID-002`
- scenario title: Member list and conversation surfaces show consistent participant identity, including avatars, for current members
- source section: Identity, Roles, Avatars, and Mixed-Social-Graph Behavior
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-002-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row ID-002 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/presentation/widgets/group_member_row.dart`, `lib/features/groups/presentation/widgets/group_avatar.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/home/application/identity_avatar_resolver.dart`, `lib/features/home/presentation/widgets/user_avatar.dart`, `lib/features/groups/application/group_avatar_storage.dart`
- existing tests or current proof: The audit says conversation uses `UserAvatar` while member rows still degrade to placeholders, especially for non-friends. Current repo references: `test/features/groups/presentation/group_info_wired_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/application/group_avatar_storage_test.dart`, `test/features/groups/integration/group_multi_device_convergence_test.dart`
- likely missing tests: test/features/groups/presentation/group_info_wired_test.dart, test/features/groups/presentation/group_conversation_wired_test.dart, test/features/groups/application/group_avatar_storage_test.dart
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row ID-002; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session ID-004
- source row id: `ID-004`
- scenario title: Supported onboarding path exists for non-friend participants when product scope says mixed-social-graph groups are allowed
- source section: Identity, Roles, Avatars, and Mixed-Social-Graph Behavior
- row disposition: `needs_repo_evidence`
- session classification: `evidence-gated`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-004-plan.md`
- exact scope: Pin the current repo contract for source row ID-004 with row-specific proof and truth alignment before any broader seam work is claimed complete.
- execution ownership: evidence only inside the current repo scope
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/presentation/widgets/group_member_row.dart`, `lib/features/groups/presentation/widgets/group_avatar.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/home/application/identity_avatar_resolver.dart`, `lib/features/home/presentation/widgets/user_avatar.dart`, `lib/features/groups/application/group_avatar_storage.dart`
- existing tests or current proof: The attached docs consistently say current onboarding is more constrained than current send/receive behavior. Current repo references: `test/features/groups/presentation/group_info_wired_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/application/group_avatar_storage_test.dart`, `test/features/groups/integration/group_multi_device_convergence_test.dart`
- likely missing tests: contract-pin or traceability tests around the cited boundary, plus matrix/doc truth alignment
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row ID-004; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session ID-008
- source row id: `ID-008`
- scenario title: Duplicate re-add, duplicate invite, or stale membership replay does not create duplicate member rows or duplicate timeline spam
- source section: Identity, Roles, Avatars, and Mixed-Social-Graph Behavior
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-008-plan.md`
- exact scope: Add row-specific regression proof for source row ID-008 without broadening scope beyond the exact user-visible contract in this row.
- execution ownership: tests only
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/presentation/widgets/group_member_row.dart`, `lib/features/groups/presentation/widgets/group_avatar.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/home/application/identity_avatar_resolver.dart`, `lib/features/home/presentation/widgets/user_avatar.dart`, `lib/features/groups/application/group_avatar_storage.dart`
- existing tests or current proof: The inventory proves duplicate add/duplicate invite guards, but not the full no-timeline-spam contract. Current repo references: `test/features/groups/presentation/group_info_wired_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/application/group_avatar_storage_test.dart`, `test/features/groups/integration/group_multi_device_convergence_test.dart`
- likely missing tests: test/features/groups/presentation/group_info_wired_test.dart, test/features/groups/presentation/group_conversation_wired_test.dart, test/features/groups/application/group_avatar_storage_test.dart
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row ID-008; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session ID-009
- source row id: `ID-009`
- scenario title: Invite-carried avatar metadata persists and resolves cleanly after accept
- source section: Identity, Roles, Avatars, and Mixed-Social-Graph Behavior
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-009-plan.md`
- exact scope: Add row-specific regression proof for source row ID-009 without broadening scope beyond the exact user-visible contract in this row.
- execution ownership: tests only
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/presentation/widgets/group_member_row.dart`, `lib/features/groups/presentation/widgets/group_avatar.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/home/application/identity_avatar_resolver.dart`, `lib/features/home/presentation/widgets/user_avatar.dart`, `lib/features/groups/application/group_avatar_storage.dart`
- existing tests or current proof: Lower-level invite tests prove metadata persistence and download path, but full surface proof remains indirect. Current repo references: `test/features/groups/presentation/group_info_wired_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/application/group_avatar_storage_test.dart`, `test/features/groups/integration/group_multi_device_convergence_test.dart`
- likely missing tests: test/features/groups/presentation/group_info_wired_test.dart, test/features/groups/presentation/group_conversation_wired_test.dart, test/features/groups/application/group_avatar_storage_test.dart
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row ID-009; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session ID-010
- source row id: `ID-010`
- scenario title: Non-friend fallback identity and avatar remain readable when full avatar sharing is unavailable
- source section: Identity, Roles, Avatars, and Mixed-Social-Graph Behavior
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-010-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row ID-010 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/presentation/widgets/group_member_row.dart`, `lib/features/groups/presentation/widgets/group_avatar.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/home/application/identity_avatar_resolver.dart`, `lib/features/home/presentation/widgets/user_avatar.dart`, `lib/features/groups/application/group_avatar_storage.dart`
- existing tests or current proof: This is the trust-preserving fallback contract implied by the audit’s non-friend identity gap. Current repo references: `test/features/groups/presentation/group_info_wired_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/application/group_avatar_storage_test.dart`, `test/features/groups/integration/group_multi_device_convergence_test.dart`
- likely missing tests: test/features/groups/presentation/group_info_wired_test.dart, test/features/groups/presentation/group_conversation_wired_test.dart, test/features/groups/application/group_avatar_storage_test.dart
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row ID-010; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session CX-001
- source row id: `CX-001`
- scenario title: Long-pressing a supported group message opens one coherent context surface, not only a detached reaction bar
- source section: Long-Press Context Actions and Overlay Parity
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CX-001-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row CX-001 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/conversation/presentation/widgets/message_context_overlay.dart`, `lib/features/conversation/presentation/widgets/reaction_display.dart`
- existing tests or current proof: The audit and current matrix both call out the 1:1 overlay parity gap. Current repo references: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/integration/group_reaction_roundtrip_test.dart`
- likely missing tests: test/features/groups/presentation/group_conversation_wired_test.dart, test/features/groups/presentation/group_conversation_screen_test.dart, test/features/groups/integration/group_reaction_roundtrip_test.dart
- likely named gates: Unit (Recommended), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row CX-001; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session CX-002
- source row id: `CX-002`
- scenario title: Group long-press reply entry reaches the existing quote-reply path for supported messages
- source section: Long-Press Context Actions and Overlay Parity
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CX-002-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row CX-002 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/conversation/presentation/widgets/message_context_overlay.dart`, `lib/features/conversation/presentation/widgets/reaction_display.dart`
- existing tests or current proof: Reply transport already exists; the missing part is the group UI host path. Current repo references: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/integration/group_reaction_roundtrip_test.dart`
- likely missing tests: test/features/groups/presentation/group_conversation_wired_test.dart, test/features/groups/presentation/group_conversation_screen_test.dart, test/features/groups/integration/group_reaction_roundtrip_test.dart
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row CX-002; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session CX-003
- source row id: `CX-003`
- scenario title: Group long-press copy action copies exact text for supported rows and dismisses cleanly
- source section: Long-Press Context Actions and Overlay Parity
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CX-003-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row CX-003 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/conversation/presentation/widgets/message_context_overlay.dart`, `lib/features/conversation/presentation/widgets/reaction_display.dart`
- existing tests or current proof: This is a local UI affordance, not a transport limitation. Current repo references: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/integration/group_reaction_roundtrip_test.dart`
- likely missing tests: test/features/groups/presentation/group_conversation_wired_test.dart, test/features/groups/presentation/group_conversation_screen_test.dart, test/features/groups/integration/group_reaction_roundtrip_test.dart
- likely named gates: Unit (Required), Integration (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row CX-003; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session CX-004
- source row id: `CX-004`
- scenario title: Unsupported group edit/delete actions stay honestly hidden without blocking the rest of the context surface
- source section: Long-Press Context Actions and Overlay Parity
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CX-004-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row CX-004 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/conversation/presentation/widgets/message_context_overlay.dart`, `lib/features/conversation/presentation/widgets/reaction_display.dart`
- existing tests or current proof: The product already lacks group edit/delete; the gap is blocking the whole surface instead of only those actions. Current repo references: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/integration/group_reaction_roundtrip_test.dart`
- likely missing tests: test/features/groups/presentation/group_conversation_wired_test.dart, test/features/groups/presentation/group_conversation_screen_test.dart, test/features/groups/integration/group_reaction_roundtrip_test.dart
- likely named gates: Unit (Required), Integration (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row CX-004; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session CX-005
- source row id: `CX-005`
- scenario title: Local-only long-press actions remain available even when reactions are unavailable
- source section: Long-Press Context Actions and Overlay Parity
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CX-005-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row CX-005 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/conversation/presentation/widgets/message_context_overlay.dart`, `lib/features/conversation/presentation/widgets/reaction_display.dart`
- existing tests or current proof: The current group UI disables long-press entirely when reaction callbacks are absent. Current repo references: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/integration/group_reaction_roundtrip_test.dart`
- likely missing tests: test/features/groups/presentation/group_conversation_wired_test.dart, test/features/groups/presentation/group_conversation_screen_test.dart, test/features/groups/integration/group_reaction_roundtrip_test.dart
- likely named gates: Unit (Required), Integration (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row CX-005; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session CX-006
- source row id: `CX-006`
- scenario title: Any future group long-press overlay preserves swipe-to-quote, reaction toggles, and current row rendering
- source section: Long-Press Context Actions and Overlay Parity
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CX-006-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row CX-006 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/conversation/presentation/widgets/message_context_overlay.dart`, `lib/features/conversation/presentation/widgets/reaction_display.dart`
- existing tests or current proof: This preservation bar is called out in the current matrix. Current repo references: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/integration/group_reaction_roundtrip_test.dart`
- likely missing tests: test/features/groups/presentation/group_conversation_wired_test.dart, test/features/groups/presentation/group_conversation_screen_test.dart, test/features/groups/integration/group_reaction_roundtrip_test.dart
- likely named gates: Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row CX-006; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session CX-007
- source row id: `CX-007`
- scenario title: Group action parity stays consistent regardless of whether the conversation was entered from `Orbit`, `Feed`, or a notification anchor
- source section: Long-Press Context Actions and Overlay Parity
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CX-007-plan.md`
- exact scope: Add row-specific regression proof for source row CX-007 without broadening scope beyond the exact user-visible contract in this row.
- execution ownership: tests only
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/conversation/presentation/widgets/message_context_overlay.dart`, `lib/features/conversation/presentation/widgets/reaction_display.dart`
- existing tests or current proof: Reaction parity is explicitly called out in the audit; broader action parity should be pinned too. Current repo references: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/integration/group_reaction_roundtrip_test.dart`
- likely missing tests: test/features/groups/presentation/group_conversation_wired_test.dart, test/features/groups/presentation/group_conversation_screen_test.dart, test/features/groups/integration/group_reaction_roundtrip_test.dart
- likely named gates: Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row CX-007; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session UI-001
- source row id: `UI-001`
- scenario title: Each group message renders as one clear bubble without a doubled or stacked-card artifact
- source section: Message Rendering and Visual Stability
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UI-001-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row UI-001 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/shared/widgets/media/media_grid.dart`, `lib/shared/widgets/media/media_thumbnail_image.dart`, `lib/features/feed/domain/utils/group_messages_into_threads.dart`
- existing tests or current proof: User screenshots plus the audit already confirm the defect; no direct visual regression test exists yet. Current repo references: `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/shared/widgets/media/media_grid_test.dart`, `test/shared/widgets/media/media_thumbnail_image_test.dart`
- likely missing tests: test/features/groups/presentation/group_conversation_screen_test.dart, test/features/groups/presentation/group_conversation_wired_test.dart, test/shared/widgets/media/media_grid_test.dart
- likely named gates: Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row UI-001; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session UI-002
- source row id: `UI-002`
- scenario title: Row-shell stability survives quote enrichment, reaction updates, media auto-download, and replay enrichment
- source section: Message Rendering and Visual Stability
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UI-002-plan.md`
- exact scope: Add row-specific regression proof for source row UI-002 without broadening scope beyond the exact user-visible contract in this row.
- execution ownership: tests only
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/shared/widgets/media/media_grid.dart`, `lib/shared/widgets/media/media_thumbnail_image.dart`, `lib/features/feed/domain/utils/group_messages_into_threads.dart`
- existing tests or current proof: Existing tests prove upsert, scroll preservation, and reaction/media updates, but not a dedicated visual-shell regression contract. Current repo references: `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/shared/widgets/media/media_grid_test.dart`, `test/shared/widgets/media/media_thumbnail_image_test.dart`
- likely missing tests: test/features/groups/presentation/group_conversation_screen_test.dart, test/features/groups/presentation/group_conversation_wired_test.dart, test/shared/widgets/media/media_grid_test.dart
- likely named gates: Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row UI-002; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RX-001
- source row id: `RX-001`
- scenario title: Tapping a visible group reaction chip reveals which members reacted and with which emoji
- source section: Reaction Transparency and Participant Identity
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RX-001-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row RX-001 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_reaction_use_case.dart`, `lib/features/groups/application/remove_group_reaction_use_case.dart`, `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/feed/application/feed_reaction_store.dart`
- existing tests or current proof: The audit and current matrix both call out missing reaction-participant disclosure. Current repo references: `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/remove_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_reaction_roundtrip_test.dart`, `test/features/feed/application/feed_reaction_store_test.dart`
- likely missing tests: test/features/groups/application/send_group_reaction_use_case_test.dart, test/features/groups/application/remove_group_reaction_use_case_test.dart, test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RX-001; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RX-002
- source row id: `RX-002`
- scenario title: Inspecting a group reaction cluster is non-destructive and does not silently remove the viewer's own reaction
- source section: Reaction Transparency and Participant Identity
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RX-002-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row RX-002 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_reaction_use_case.dart`, `lib/features/groups/application/remove_group_reaction_use_case.dart`, `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/feed/application/feed_reaction_store.dart`
- existing tests or current proof: Today the chip tap is wired to mutation-first behavior. Current repo references: `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/remove_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_reaction_roundtrip_test.dart`, `test/features/feed/application/feed_reaction_store_test.dart`
- likely missing tests: test/features/groups/application/send_group_reaction_use_case_test.dart, test/features/groups/application/remove_group_reaction_use_case_test.dart, test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RX-002; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RX-003
- source row id: `RX-003`
- scenario title: Reaction participant identity stays readable even when reaction rows only persist peer IDs or when reactors are non-friends
- source section: Reaction Transparency and Participant Identity
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RX-003-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row RX-003 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_reaction_use_case.dart`, `lib/features/groups/application/remove_group_reaction_use_case.dart`, `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/feed/application/feed_reaction_store.dart`
- existing tests or current proof: The current model stores peer IDs, not display usernames, so readable lookup must be proven. Current repo references: `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/remove_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_reaction_roundtrip_test.dart`, `test/features/feed/application/feed_reaction_store_test.dart`
- likely missing tests: test/features/groups/application/send_group_reaction_use_case_test.dart, test/features/groups/application/remove_group_reaction_use_case_test.dart, test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RX-003; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RX-004
- source row id: `RX-004`
- scenario title: Reaction inspection parity is preserved across `Orbit` and `Feed` entry points
- source section: Reaction Transparency and Participant Identity
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RX-004-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row RX-004 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_reaction_use_case.dart`, `lib/features/groups/application/remove_group_reaction_use_case.dart`, `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/feed/application/feed_reaction_store.dart`
- existing tests or current proof: Explicitly called out in the audit and current matrix. Current repo references: `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/remove_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_reaction_roundtrip_test.dart`, `test/features/feed/application/feed_reaction_store_test.dart`
- likely missing tests: test/features/groups/application/send_group_reaction_use_case_test.dart, test/features/groups/application/remove_group_reaction_use_case_test.dart, test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RX-004; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RX-005
- source row id: `RX-005`
- scenario title: Inline Feed group-thread reactions and permissions behave coherently if inline interaction stays in scope
- source section: Reaction Transparency and Participant Identity
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RX-005-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row RX-005 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `feed_screen.dart`, `lib/features/groups/application/send_group_reaction_use_case.dart`, `lib/features/groups/application/remove_group_reaction_use_case.dart`, `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/feed/application/feed_reaction_store.dart`
- existing tests or current proof: `feed_screen.dart` has its own group-specific reaction path, so it needs its own proof. Current repo references: `feed_screen.dart`, `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/remove_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_reaction_roundtrip_test.dart`, `test/features/feed/application/feed_reaction_store_test.dart`
- likely missing tests: test/features/groups/application/send_group_reaction_use_case_test.dart, test/features/groups/application/remove_group_reaction_use_case_test.dart, test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart
- likely named gates: Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RX-005; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RX-006
- source row id: `RX-006`
- scenario title: Live, replayed, and post-rotation reactions remain truthful after resume/rejoin
- source section: Reaction Transparency and Participant Identity
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RX-006-plan.md`
- exact scope: Add row-specific regression proof for source row RX-006 without broadening scope beyond the exact user-visible contract in this row.
- execution ownership: tests only
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_reaction_use_case.dart`, `lib/features/groups/application/remove_group_reaction_use_case.dart`, `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/feed/application/feed_reaction_store.dart`
- existing tests or current proof: Live reaction round-trip is covered; replay and invite-accept immediacy are still not fully proven. Current repo references: `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/remove_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`, `test/features/groups/integration/group_reaction_roundtrip_test.dart`, `test/features/feed/application/feed_reaction_store_test.dart`
- likely missing tests: test/features/groups/application/send_group_reaction_use_case_test.dart, test/features/groups/application/remove_group_reaction_use_case_test.dart, test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RX-006; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MM-003
- source row id: `MM-003`
- scenario title: Voice-only send is supported, empty non-media send is blocked, and announcement readers never expose stale send/record controls
- source section: Messaging, Compose, Media, Voice, and Delivery Truth
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-003-plan.md`
- exact scope: Preserve the current repo truth for source row MM-003 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`, `lib/features/groups/presentation/widgets/group_compose_area.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/widgets/compose_area.dart`
- existing tests or current proof: The test inventory has direct wired-path proof for these guards. Current repo references: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MM-003; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MM-004
- source row id: `MM-004`
- scenario title: Quote reply survives send, render, failure, and retry paths without losing user intent
- source section: Messaging, Compose, Media, Voice, and Delivery Truth
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-004-plan.md`
- exact scope: Preserve the current repo truth for source row MM-004 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`, `lib/features/groups/presentation/widgets/group_compose_area.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/widgets/compose_area.dart`
- existing tests or current proof: Current tests cover quote send, render, and failure-restoration behavior. Current repo references: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MM-004; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MM-005
- source row id: `MM-005`
- scenario title: Media upload failure leaves a truthful failed/retryable row, and targeted retry/delete only affects that row
- source section: Messaging, Compose, Media, Voice, and Delivery Truth
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-005-plan.md`
- exact scope: Preserve the current repo truth for source row MM-005 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`, `lib/features/groups/presentation/widgets/group_compose_area.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/widgets/compose_area.dart`
- existing tests or current proof: The wired-path tests already cover targeted retry/delete and durable media staging. Current repo references: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MM-005; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MM-008
- source row id: `MM-008`
- scenario title: Publish-success pending rows finalize only through an owned path, not silent drift
- source section: Messaging, Compose, Media, Voice, and Delivery Truth
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-008-plan.md`
- exact scope: Add row-specific regression proof for source row MM-008 without broadening scope beyond the exact user-visible contract in this row.
- execution ownership: tests only
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`, `lib/features/groups/presentation/widgets/group_compose_area.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/widgets/compose_area.dart`
- existing tests or current proof: The send C4 documents the distinction, but the full user-visible contract is not yet singled out as a dedicated row. Current repo references: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: test/features/groups/application/send_group_message_use_case_test.dart, test/features/groups/application/retry_failed_group_messages_use_case_test.dart, test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MM-008; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MM-009
- source row id: `MM-009`
- scenario title: Zero-peer plus inbox-fail sends recover through one explicit retry owner and never get stranded between retry lanes
- source section: Messaging, Compose, Media, Voice, and Delivery Truth
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-009-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row MM-009 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`, `lib/features/groups/presentation/widgets/group_compose_area.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/widgets/compose_area.dart`
- existing tests or current proof: The audit and current matrix both call out this retry-owner precision gap. Current repo references: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: test/features/groups/application/send_group_message_use_case_test.dart, test/features/groups/application/retry_failed_group_messages_use_case_test.dart, test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MM-009; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MM-011
- source row id: `MM-011`
- scenario title: Legacy `topicPeers == null` bridge compatibility preserves truthful terminal state
- source section: Messaging, Compose, Media, Voice, and Delivery Truth
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-011-plan.md`
- exact scope: Preserve the current repo truth for source row MM-011 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`, `lib/features/groups/presentation/widgets/group_compose_area.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/widgets/compose_area.dart`
- existing tests or current proof: Directly covered in send use-case tests per the inventory. Current repo references: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MM-011; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MM-012
- source row id: `MM-012`
- scenario title: Send rules during active group recovery are explicit and intentional
- source section: Messaging, Compose, Media, Voice, and Delivery Truth
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-012-plan.md`
- exact scope: Add row-specific regression proof for source row MM-012 without broadening scope beyond the exact user-visible contract in this row.
- execution ownership: tests only
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`, `lib/features/groups/presentation/widgets/group_compose_area.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/widgets/compose_area.dart`
- existing tests or current proof: Tests prove announcement recovery guards and stale callback protection; the broader end-user contract still deserves a row. Current repo references: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: test/features/groups/application/send_group_message_use_case_test.dart, test/features/groups/application/retry_failed_group_messages_use_case_test.dart, test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MM-012; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MM-014
- source row id: `MM-014`
- scenario title: Share-to-group respects write eligibility and partial-failure truth across writable groups
- source section: Messaging, Compose, Media, Voice, and Delivery Truth
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-014-plan.md`
- exact scope: Preserve the current repo truth for source row MM-014 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`, `lib/features/groups/presentation/widgets/group_compose_area.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/widgets/compose_area.dart`
- existing tests or current proof: The test inventory includes share-target filtering, partial-failure truth, and background-task group share coverage. Current repo references: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MM-014; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MM-015
- source row id: `MM-015`
- scenario title: Announcement sends after key rotation still use the new epoch and remain deliverable
- source section: Messaging, Compose, Media, Voice, and Delivery Truth
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-015-plan.md`
- exact scope: Preserve the current repo truth for source row MM-015 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`, `lib/features/groups/presentation/widgets/group_compose_area.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/widgets/compose_area.dart`
- existing tests or current proof: Covered by rotation and resume-recovery announcement tests in the inventory. Current repo references: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MM-015; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RC-002
- source row id: `RC-002`
- scenario title: Duplicate replay enriches missing quote/media metadata rather than creating a second row
- source section: Receive, Rendering, Notification, and Conversation Integrity
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-002-plan.md`
- exact scope: Preserve the current repo truth for source row RC-002 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- existing tests or current proof: Explicitly covered by incoming-message tests. Current repo references: `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/notifications/notification_route_target_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RC-002; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RC-004
- source row id: `RC-004`
- scenario title: Sequential messages, delayed delivery, and burst traffic preserve ordering and avoid user-visible loss within supported capacity
- source section: Receive, Rendering, Notification, and Conversation Integrity
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-004-plan.md`
- exact scope: Preserve the current repo truth for source row RC-004 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- existing tests or current proof: Current smoke coverage includes ordering, delayed delivery, and burst handling. Current repo references: `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/notifications/notification_route_target_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Recommended), Integration (Required), Smoke (Recommended), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RC-004; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RC-005
- source row id: `RC-005`
- scenario title: A sibling device for the same user stores own live publishes as local sent history
- source section: Receive, Rendering, Notification, and Conversation Integrity
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-005-plan.md`
- exact scope: Preserve the current repo truth for source row RC-005 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- existing tests or current proof: The multi-device convergence tests already prove this behavior. Current repo references: `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/notifications/notification_route_target_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RC-005; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RC-006
- source row id: `RC-006`
- scenario title: Media auto-download and row upsert do not create duplicate rows or destroy scroll/context
- source section: Receive, Rendering, Notification, and Conversation Integrity
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-006-plan.md`
- exact scope: Add row-specific regression proof for source row RC-006 without broadening scope beyond the exact user-visible contract in this row.
- execution ownership: tests only
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- existing tests or current proof: Existing tests prove upsert optimization and scroll preservation, but not one dedicated end-user contract row. Current repo references: `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/notifications/notification_route_target_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: test/features/groups/application/handle_incoming_group_message_use_case_test.dart, test/features/groups/application/group_message_listener_test.dart, test/features/groups/integration/group_resume_recovery_test.dart
- likely named gates: Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RC-006; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RC-007
- source row id: `RC-007`
- scenario title: Notification anchors open the group and highlight the targeted message context
- source section: Receive, Rendering, Notification, and Conversation Integrity
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-007-plan.md`
- exact scope: Preserve the current repo truth for source row RC-007 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- existing tests or current proof: Explicitly covered by group conversation wired tests. Current repo references: `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/notifications/notification_route_target_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Integration (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RC-007; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RC-008
- source row id: `RC-008`
- scenario title: Notification truth suppresses own-message, active-conversation, and recent-remote-push duplicate alerts
- source section: Receive, Rendering, Notification, and Conversation Integrity
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-008-plan.md`
- exact scope: Preserve the current repo truth for source row RC-008 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- existing tests or current proof: Already covered by listener notification tests and the existing matrix. Current repo references: `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/notifications/notification_route_target_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RC-008; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RC-009
- source row id: `RC-009`
- scenario title: Decryption failure or payload-parse failure creates no ghost message and remains diagnosable
- source section: Receive, Rendering, Notification, and Conversation Integrity
- row disposition: `repo_external_proof`
- session classification: `evidence-gated`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-009-plan.md`
- exact scope: Collect the row-specific external proof surface for RC-009 and record the owned repo boundary without swallowing neighboring rows.
- execution ownership: evidence only with external proof ownership
- proof ownership: repo-external proof owner or harness
- likely code-entry files: `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- existing tests or current proof: `C4-03` says Go emits diagnostic events, but Dart does not explicitly route them today. Current repo references: `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/notifications/notification_route_target_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: external harness or device-lab proof, then a repo-local contract test that records the owned boundary
- likely named gates: Unit (Required), Integration (Recommended), Fake Network (Recommended)
- dependency on earlier sessions: none in-repo; depends on external proof owner or device-lab / native / relay harness
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RC-009; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RC-010
- source row id: `RC-010`
- scenario title: Dispatcher overflow or high-burst receive load has an owned contract and monitoring story
- source section: Receive, Rendering, Notification, and Conversation Integrity
- row disposition: `repo_external_proof`
- session classification: `evidence-gated`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-010-plan.md`
- exact scope: Collect the row-specific external proof surface for RC-010 and record the owned repo boundary without swallowing neighboring rows.
- execution ownership: evidence only with external proof ownership
- proof ownership: repo-external proof owner or harness
- likely code-entry files: `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- existing tests or current proof: `C4-03` documents a bounded dispatcher queue with drop-on-overflow behavior, but no direct proof exists in the current matrix. Current repo references: `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/notifications/notification_route_target_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: external harness or device-lab proof, then a repo-local contract test that records the owned boundary
- likely named gates: Unit (Required), Integration (Recommended), Fake Network (Recommended)
- dependency on earlier sessions: none in-repo; depends on external proof owner or device-lab / native / relay harness
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RC-010; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RY-002
- source row id: `RY-002`
- scenario title: Foreground resume runs rejoin, drain, stuck-send recovery, upload retry, failed-send retry, and inbox retry in the intended order
- source section: Recovery, Replay, Retention, and Offline Privacy
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-002-plan.md`
- exact scope: Preserve the current repo truth for source row RY-002 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- existing tests or current proof: The lifecycle tests explicitly pin the ordered resume flow. Current repo references: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`, `test/core/lifecycle/handle_app_paused_group_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RY-002; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RY-004
- source row id: `RY-004`
- scenario title: Watchdog or node-requested recovery acknowledges only after a clean rejoin
- source section: Recovery, Replay, Retention, and Offline Privacy
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-004-plan.md`
- exact scope: Preserve the current repo truth for source row RY-004 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- existing tests or current proof: Pending retrier and recovery tests already pin the ack semantics. Current repo references: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`, `test/core/lifecycle/handle_app_paused_group_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RY-004; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RY-005
- source row id: `RY-005`
- scenario title: Archived groups still drain/rejoin as intended while dissolved groups stay read-only and skipped from rejoin
- source section: Recovery, Replay, Retention, and Offline Privacy
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-005-plan.md`
- exact scope: Preserve the current repo truth for source row RY-005 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- existing tests or current proof: The inventory explicitly notes archived inclusion and dissolved exclusion in recovery tests. Current repo references: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`, `test/core/lifecycle/handle_app_paused_group_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RY-005; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RY-006
- source row id: `RY-006`
- scenario title: Multi-page cursor drain recovers backlog exactly once across pages and cursor continuation
- source section: Recovery, Replay, Retention, and Offline Privacy
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-006-plan.md`
- exact scope: Preserve the current repo truth for source row RY-006 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- existing tests or current proof: Existing recovery tests already cover multi-page drain and cursor continuation. Current repo references: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`, `test/core/lifecycle/handle_app_paused_group_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RY-006; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RY-008
- source row id: `RY-008`
- scenario title: Recovery does not burst all joined groups at once
- source section: Recovery, Replay, Retention, and Offline Privacy
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-008-plan.md`
- exact scope: Preserve the current repo truth for source row RY-008 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- existing tests or current proof: The recovery integration tests already call out multi-group throttle behavior. Current repo references: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`, `test/core/lifecycle/handle_app_paused_group_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Recommended), Integration (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RY-008; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RY-009
- source row id: `RY-009`
- scenario title: Long-offline mixed-window recovery keeps retained backlog, drops expired non-system backlog, still applies old system membership events, and surfaces truthful retention messaging
- source section: Recovery, Replay, Retention, and Offline Privacy
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-009-plan.md`
- exact scope: Preserve the current repo truth for source row RY-009 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- existing tests or current proof: Already covered in the current matrix and in recovery tests. Current repo references: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`, `test/core/lifecycle/handle_app_paused_group_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Fake Network (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RY-009; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RY-010
- source row id: `RY-010`
- scenario title: Replay without `GroupMessageListener` or without `reactionRepo` never silently claims full convergence
- source section: Recovery, Replay, Retention, and Offline Privacy
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-010-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row RY-010 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- existing tests or current proof: `C4-05` explicitly says system side effects are not replayed without the listener and reactions are skipped without `reactionRepo`. Current repo references: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`, `test/core/lifecycle/handle_app_paused_group_test.dart`
- likely missing tests: test/features/groups/application/drain_group_offline_inbox_use_case_test.dart, test/features/groups/application/rejoin_group_topics_use_case_test.dart, test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RY-010; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RY-011
- source row id: `RY-011`
- scenario title: Invite-accept drain includes offline reactions in the same user-visible catch-up window, or the deferred model is explicitly owned
- source section: Recovery, Replay, Retention, and Offline Privacy
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-011-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row RY-011 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- existing tests or current proof: The audit and current matrix both call out this immediate-catch-up gap. Current repo references: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`, `test/core/lifecycle/handle_app_paused_group_test.dart`
- likely missing tests: test/features/groups/application/drain_group_offline_inbox_use_case_test.dart, test/features/groups/application/rejoin_group_topics_use_case_test.dart, test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RY-011; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RY-012
- source row id: `RY-012`
- scenario title: Invite acceptance that returns `bridgeError` still converges to a live joined group without needing the invite row again
- source section: Recovery, Replay, Retention, and Offline Privacy
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-012-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row RY-012 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- existing tests or current proof: Explicitly identified by the audit and current matrix. Current repo references: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`, `test/core/lifecycle/handle_app_paused_group_test.dart`
- likely missing tests: test/features/groups/application/drain_group_offline_inbox_use_case_test.dart, test/features/groups/application/rejoin_group_topics_use_case_test.dart, test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RY-012; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MD-001
- source row id: `MD-001`
- scenario title: Same-user live publishes on a sibling device store as local sent history without duplicate unread or notification confusion
- source section: Multi-Device and Cross-Surface Convergence
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MD-001-plan.md`
- exact scope: Preserve the current repo truth for source row MD-001 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/domain/models/group_multi_device_policy.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/features/feed/application/load_group_feed_snapshot_use_case.dart`, `lib/features/orbit/application/load_orbit_groups_use_case.dart`
- existing tests or current proof: Multi-device convergence tests already cover same-user sent-history behavior. Current repo references: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/core/notifications/notification_route_target_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MD-001; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MD-002
- source row id: `MD-002`
- scenario title: Membership updates converge across sibling devices without duplicate local membership or role drift
- source section: Multi-Device and Cross-Surface Convergence
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MD-002-plan.md`
- exact scope: Preserve the current repo truth for source row MD-002 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/domain/models/group_multi_device_policy.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/features/feed/application/load_group_feed_snapshot_use_case.dart`, `lib/features/orbit/application/load_orbit_groups_use_case.dart`
- existing tests or current proof: Explicitly covered by multi-device convergence tests. Current repo references: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/core/notifications/notification_route_target_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MD-002; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MD-003
- source row id: `MD-003`
- scenario title: Mute, unread, and local notifications stay device-local across sibling devices
- source section: Multi-Device and Cross-Surface Convergence
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MD-003-plan.md`
- exact scope: Preserve the current repo truth for source row MD-003 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/domain/models/group_multi_device_policy.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/features/feed/application/load_group_feed_snapshot_use_case.dart`, `lib/features/orbit/application/load_orbit_groups_use_case.dart`
- existing tests or current proof: Called out directly in the multi-device convergence tests. Current repo references: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/core/notifications/notification_route_target_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MD-003; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MD-004
- source row id: `MD-004`
- scenario title: True device/simulator multi-device E2E proves sibling-device behavior beyond in-memory fakes
- source section: Multi-Device and Cross-Surface Convergence
- row disposition: `repo_external_proof`
- session classification: `evidence-gated`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MD-004-plan.md`
- exact scope: Collect the row-specific external proof surface for MD-004 and record the owned repo boundary without swallowing neighboring rows.
- execution ownership: evidence only with external proof ownership
- proof ownership: repo-external proof owner or harness
- likely code-entry files: `lib/features/groups/domain/models/group_multi_device_policy.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/features/feed/application/load_group_feed_snapshot_use_case.dart`, `lib/features/orbit/application/load_orbit_groups_use_case.dart`
- existing tests or current proof: `test-inventory.md` explicitly calls out true multi-device E2E as missing. Current repo references: `test-inventory.md`, `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/core/notifications/notification_route_target_test.dart`
- likely missing tests: external harness or device-lab proof, then a repo-local contract test that records the owned boundary
- likely named gates: Integration (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none in-repo; depends on external proof owner or device-lab / native / relay harness
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MD-004; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MD-005
- source row id: `MD-005`
- scenario title: Message-level behavior stays consistent when entering the same group from `Orbit`, `Feed`, or push
- source section: Multi-Device and Cross-Surface Convergence
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MD-005-plan.md`
- exact scope: Add row-specific regression proof for source row MD-005 without broadening scope beyond the exact user-visible contract in this row.
- execution ownership: tests only
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/domain/models/group_multi_device_policy.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/features/feed/application/load_group_feed_snapshot_use_case.dart`, `lib/features/orbit/application/load_orbit_groups_use_case.dart`
- existing tests or current proof: The audit explicitly requires entry-point parity, but direct proof is incomplete. Current repo references: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/core/notifications/notification_route_target_test.dart`
- likely missing tests: test/features/groups/integration/group_multi_device_convergence_test.dart, test/features/groups/presentation/group_conversation_wired_test.dart, test/core/notifications/notification_route_target_test.dart
- likely named gates: Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MD-005; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MD-006
- source row id: `MD-006`
- scenario title: Group-message and group-invite push routes navigate to the correct surface
- source section: Multi-Device and Cross-Surface Convergence
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MD-006-plan.md`
- exact scope: Preserve the current repo truth for source row MD-006 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/domain/models/group_multi_device_policy.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/features/feed/application/load_group_feed_snapshot_use_case.dart`, `lib/features/orbit/application/load_orbit_groups_use_case.dart`
- existing tests or current proof: Current notification-route and push-navigation tests already cover the mapping. Current repo references: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/core/notifications/notification_route_target_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Integration (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MD-006; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session SV-004
- source row id: `SV-004`
- scenario title: Replay attack with tampered timestamps or reordered envelopes does not create duplicate visible messages or bypass cutoffs
- source section: Security, Validator, Bridge-Contract, and Observability
- row disposition: `blocked_by_prerequisite`
- session classification: `prerequisite-blocked`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-004-plan.md`
- exact scope: Hold source row SV-004 as row-owned work, but do not advance it past prerequisite-blocked until the missing feature or harness exists.
- execution ownership: evidence only until the blocking prerequisite exists
- proof ownership: blocked on missing prerequisite feature or proof harness
- likely code-entry files: `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/domain/models/group_invite_payload.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `lib/core/utils/push_diagnostics_logger.dart`
- existing tests or current proof: `test-inventory.md` explicitly calls this out as a security coverage gap. Current repo references: `test-inventory.md`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/announcement_happy_path_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/domain/models/group_invite_payload_test.dart`, `test/features/groups/domain/models/group_message_payload_test.dart`
- likely missing tests: blocked on prerequisite feature or harness; add repo-local regression only after the prerequisite lands
- likely named gates: Unit (Required), Integration (Recommended), Fake Network (Recommended)
- dependency on earlier sessions: none in-repo; blocked by missing prerequisite feature or proof surface for this row
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row SV-004; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session SV-005
- source row id: `SV-005`
- scenario title: Tampered payload, wrong key, tampered nonce, or tampered ciphertext creates no visible message and yields diagnosable rejection
- source section: Security, Validator, Bridge-Contract, and Observability
- row disposition: `blocked_by_prerequisite`
- session classification: `prerequisite-blocked`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-005-plan.md`
- exact scope: Hold source row SV-005 as row-owned work, but do not advance it past prerequisite-blocked until the missing feature or harness exists.
- execution ownership: evidence only until the blocking prerequisite exists
- proof ownership: blocked on missing prerequisite feature or proof harness
- likely code-entry files: `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/domain/models/group_invite_payload.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `lib/core/utils/push_diagnostics_logger.dart`
- existing tests or current proof: Go-side crypto coverage exists, but the inventory still notes missing dedicated group-message app-level rejection proof. Current repo references: `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/announcement_happy_path_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/domain/models/group_invite_payload_test.dart`, `test/features/groups/domain/models/group_message_payload_test.dart`
- likely missing tests: blocked on prerequisite feature or harness; add repo-local regression only after the prerequisite lands
- likely named gates: Unit (Required), Integration (Recommended), Fake Network (Recommended)
- dependency on earlier sessions: none in-repo; blocked by missing prerequisite feature or proof surface for this row
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row SV-005; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session SV-006
- source row id: `SV-006`
- scenario title: Previous-key grace during rotation accepts legitimate in-flight traffic without reopening indefinite stale-key access
- source section: Security, Validator, Bridge-Contract, and Observability
- row disposition: `blocked_by_prerequisite`
- session classification: `prerequisite-blocked`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-006-plan.md`
- exact scope: Hold source row SV-006 as row-owned work, but do not advance it past prerequisite-blocked until the missing feature or harness exists.
- execution ownership: evidence only until the blocking prerequisite exists
- proof ownership: blocked on missing prerequisite feature or proof harness
- likely code-entry files: `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/domain/models/group_invite_payload.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `lib/core/utils/push_diagnostics_logger.dart`
- existing tests or current proof: `C4-03` documents current-or-previous-key grace behavior, but the attached inventory does not show this pinned as a direct user-visible contract. Current repo references: `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/announcement_happy_path_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/domain/models/group_invite_payload_test.dart`, `test/features/groups/domain/models/group_message_payload_test.dart`
- likely missing tests: blocked on prerequisite feature or harness; add repo-local regression only after the prerequisite lands
- likely named gates: Unit (Required), Integration (Recommended), Fake Network (Recommended)
- dependency on earlier sessions: none in-repo; blocked by missing prerequisite feature or proof surface for this row
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row SV-006; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session SV-007
- source row id: `SV-007`
- scenario title: Concurrent key-rotation races across admins converge to one final usable epoch
- source section: Security, Validator, Bridge-Contract, and Observability
- row disposition: `blocked_by_prerequisite`
- session classification: `prerequisite-blocked`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-007-plan.md`
- exact scope: Hold source row SV-007 as row-owned work, but do not advance it past prerequisite-blocked until the missing feature or harness exists.
- execution ownership: evidence only until the blocking prerequisite exists
- proof ownership: blocked on missing prerequisite feature or proof harness
- likely code-entry files: `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/domain/models/group_invite_payload.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `lib/core/utils/push_diagnostics_logger.dart`
- existing tests or current proof: The inventory explicitly calls out key-rotation race coverage as missing. Current repo references: `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/announcement_happy_path_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/domain/models/group_invite_payload_test.dart`, `test/features/groups/domain/models/group_message_payload_test.dart`
- likely missing tests: blocked on prerequisite feature or harness; add repo-local regression only after the prerequisite lands
- likely named gates: Unit (Required), Integration (Recommended), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none in-repo; blocked by missing prerequisite feature or proof surface for this row
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row SV-007; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session SV-008
- source row id: `SV-008`
- scenario title: Concurrent remove/promote or remove/rotate conflicts converge to one final visible member/admin map and usable key state
- source section: Security, Validator, Bridge-Contract, and Observability
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-008-plan.md`
- exact scope: Add row-specific regression proof for source row SV-008 without broadening scope beyond the exact user-visible contract in this row.
- execution ownership: tests only
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/domain/models/group_invite_payload.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `lib/core/utils/push_diagnostics_logger.dart`
- existing tests or current proof: Some convergence coverage exists today, but not the full stress space. Current repo references: `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/announcement_happy_path_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/domain/models/group_invite_payload_test.dart`, `test/features/groups/domain/models/group_message_payload_test.dart`
- likely missing tests: test/features/groups/integration/group_membership_smoke_test.dart, test/features/groups/integration/announcement_happy_path_test.dart, test/features/groups/application/handle_incoming_group_message_use_case_test.dart
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row SV-008; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session SV-010
- source row id: `SV-010`
- scenario title: Topic namespace / `topicName` contract between Go and Dart is explicit and tested
- source section: Security, Validator, Bridge-Contract, and Observability
- row disposition: `needs_repo_evidence`
- session classification: `evidence-gated`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-010-plan.md`
- exact scope: Pin the current repo contract for source row SV-010 with row-specific proof and truth alignment before any broader seam work is claimed complete.
- execution ownership: evidence only inside the current repo scope
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/domain/models/group_invite_payload.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `lib/core/utils/push_diagnostics_logger.dart`
- existing tests or current proof: Explicitly called out by `C4-01` and the test inventory. Current repo references: `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/announcement_happy_path_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/domain/models/group_invite_payload_test.dart`, `test/features/groups/domain/models/group_message_payload_test.dart`
- likely missing tests: contract-pin or traceability tests around the cited boundary, plus matrix/doc truth alignment
- likely named gates: Unit (Required), Integration (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row SV-010; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session UX-001
- source row id: `UX-001`
- scenario title: Per-group mute suppresses notifications without dropping delivery
- source section: Quality-of-Life and Higher-Level Product Capabilities
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-001-plan.md`
- exact scope: Preserve the current repo truth for source row UX-001 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/groups/application/dissolve_group_use_case.dart`, `lib/features/share/application/handle_share_intent_use_case.dart`, `lib/features/share/application/share_batch_delivery_coordinator.dart`, `lib/features/push/application/show_notification_use_case.dart`
- existing tests or current proof: Strong current coverage already exists for mute behavior. Current repo references: `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/groups/application/dissolve_group_use_case_test.dart`, `test/features/share/application/handle_share_intent_use_case_test.dart`, `test/features/share/application/share_batch_delivery_coordinator_test.dart`, `test/core/notifications/notification_push_tap_navigate_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row UX-001; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session UX-002
- source row id: `UX-002`
- scenario title: Dissolving the group keeps history readable but blocks further writing
- source section: Quality-of-Life and Higher-Level Product Capabilities
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-002-plan.md`
- exact scope: Preserve the current repo truth for source row UX-002 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/groups/application/dissolve_group_use_case.dart`, `lib/features/share/application/handle_share_intent_use_case.dart`, `lib/features/share/application/share_batch_delivery_coordinator.dart`, `lib/features/push/application/show_notification_use_case.dart`
- existing tests or current proof: Already covered in dissolve and membership/replay tests. Current repo references: `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/groups/application/dissolve_group_use_case_test.dart`, `test/features/share/application/handle_share_intent_use_case_test.dart`, `test/features/share/application/share_batch_delivery_coordinator_test.dart`, `test/core/notifications/notification_push_tap_navigate_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row UX-002; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session UX-009
- source row id: `UX-009`
- scenario title: End-to-end push trigger path for group message and group invite is verified on real device if push is in scope
- source section: Quality-of-Life and Higher-Level Product Capabilities
- row disposition: `repo_external_proof`
- session classification: `evidence-gated`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-009-plan.md`
- exact scope: Collect the row-specific external proof surface for UX-009 and record the owned repo boundary without swallowing neighboring rows.
- execution ownership: evidence only with external proof ownership
- proof ownership: repo-external proof owner or harness
- likely code-entry files: `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/groups/application/dissolve_group_use_case.dart`, `lib/features/share/application/handle_share_intent_use_case.dart`, `lib/features/share/application/share_batch_delivery_coordinator.dart`, `lib/features/push/application/show_notification_use_case.dart`
- existing tests or current proof: The inventory says routing is tested but full FCM/APNs trigger delivery is not. Current repo references: `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/groups/application/dissolve_group_use_case_test.dart`, `test/features/share/application/handle_share_intent_use_case_test.dart`, `test/features/share/application/share_batch_delivery_coordinator_test.dart`, `test/core/notifications/notification_push_tap_navigate_test.dart`
- likely missing tests: external harness or device-lab proof, then a repo-local contract test that records the owned boundary
- likely named gates: Integration (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none in-repo; depends on external proof owner or device-lab / native / relay harness
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row UX-009; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session UX-010
- source row id: `UX-010`
- scenario title: Share-target picker shows only writable groups and respects announcement read-only filtering
- source section: Quality-of-Life and Higher-Level Product Capabilities
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-010-plan.md`
- exact scope: Preserve the current repo truth for source row UX-010 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/groups/application/dissolve_group_use_case.dart`, `lib/features/share/application/handle_share_intent_use_case.dart`, `lib/features/share/application/share_batch_delivery_coordinator.dart`, `lib/features/push/application/show_notification_use_case.dart`
- existing tests or current proof: Explicitly covered by cross-feature share tests in the inventory. Current repo references: `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/groups/application/dissolve_group_use_case_test.dart`, `test/features/share/application/handle_share_intent_use_case_test.dart`, `test/features/share/application/share_batch_delivery_coordinator_test.dart`, `test/core/notifications/notification_push_tap_navigate_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row UX-010; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session ID-007
- source row id: `ID-007`
- scenario title: Explicit admin transfer or ownership handoff behaves cleanly if the feature exists
- source section: Identity, Roles, Avatars, and Mixed-Social-Graph Behavior
- row disposition: `unsupported_product_scope`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-007-plan.md`
- exact scope: Keep source row ID-007 explicitly out of implementation scope while the capability stays unsupported; only row-specific truth-alignment and scope proof belong here.
- execution ownership: no execution because the row is out of current product scope
- proof ownership: product-scope excluded in the current repo contract
- likely code-entry files: `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/presentation/widgets/group_member_row.dart`, `lib/features/groups/presentation/widgets/group_avatar.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/home/application/identity_avatar_resolver.dart`, `lib/features/home/presentation/widgets/user_avatar.dart`, `lib/features/groups/application/group_avatar_storage.dart`
- existing tests or current proof: The audit and current matrix both say explicit ownership handoff is not yet landed. Current scope proof: `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`, `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- likely missing tests: none while the capability stays out of scope
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row ID-007; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session SV-009
- source row id: `SV-009`
- scenario title: Description pass-through between Dart and Go is explicit and tested if create-time description is supported
- source section: Security, Validator, Bridge-Contract, and Observability
- row disposition: `unsupported_product_scope`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-009-plan.md`
- exact scope: Keep source row SV-009 explicitly out of implementation scope while the capability stays unsupported; only row-specific truth-alignment and scope proof belong here.
- execution ownership: no execution because the row is out of current product scope
- proof ownership: product-scope excluded in the current repo contract
- likely code-entry files: `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/domain/models/group_invite_payload.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `lib/core/utils/push_diagnostics_logger.dart`
- existing tests or current proof: `test-inventory.md` explicitly flags description pass-through as a Go/Dart boundary gap. Current scope proof: `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`, `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- likely missing tests: none while the capability stays out of scope
- likely named gates: Unit (Required), Integration (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row SV-009; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session SV-011
- source row id: `SV-011`
- scenario title: Flow-event names and payload shapes for group timing/recovery/retry observability are pinned
- source section: Security, Validator, Bridge-Contract, and Observability
- row disposition: `needs_repo_evidence`
- session classification: `evidence-gated`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-011-plan.md`
- exact scope: Pin the current repo contract for source row SV-011 with row-specific proof and truth alignment before any broader seam work is claimed complete.
- execution ownership: evidence only inside the current repo scope
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/domain/models/group_invite_payload.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `lib/core/utils/push_diagnostics_logger.dart`
- existing tests or current proof: `test-inventory.md` explicitly calls out missing flow-event contract inventory coverage. Current repo references: `test-inventory.md`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/announcement_happy_path_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/domain/models/group_invite_payload_test.dart`, `test/features/groups/domain/models/group_message_payload_test.dart`
- likely missing tests: contract-pin or traceability tests around the cited boundary, plus matrix/doc truth alignment
- likely named gates: Unit (Required), Integration (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row SV-011; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session SV-012
- source row id: `SV-012`
- scenario title: Native dispatcher overflow or dropped diagnostics are surfaced to monitoring instead of remaining silent
- source section: Security, Validator, Bridge-Contract, and Observability
- row disposition: `blocked_by_prerequisite`
- session classification: `prerequisite-blocked`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-012-plan.md`
- exact scope: Hold source row SV-012 as row-owned work, but do not advance it past prerequisite-blocked until the missing feature or harness exists.
- execution ownership: evidence only until the blocking prerequisite exists
- proof ownership: blocked on missing prerequisite feature or proof harness
- likely code-entry files: `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/domain/models/group_invite_payload.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `lib/core/utils/push_diagnostics_logger.dart`
- existing tests or current proof: This follows from the bounded-dispatcher behavior documented in `C4-03`. Current repo references: `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/announcement_happy_path_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/domain/models/group_invite_payload_test.dart`, `test/features/groups/domain/models/group_message_payload_test.dart`
- likely missing tests: blocked on prerequisite feature or harness; add repo-local regression only after the prerequisite lands
- likely named gates: Unit (Required), Integration (Recommended), Fake Network (Recommended)
- dependency on earlier sessions: none in-repo; blocked by missing prerequisite feature or proof surface for this row
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row SV-012; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session UX-003
- source row id: `UX-003`
- scenario title: Search inside group history works if the feature exists
- source section: Quality-of-Life and Higher-Level Product Capabilities
- row disposition: `unsupported_product_scope`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-003-plan.md`
- exact scope: Keep source row UX-003 explicitly out of implementation scope while the capability stays unsupported; only row-specific truth-alignment and scope proof belong here.
- execution ownership: no execution because the row is out of current product scope
- proof ownership: product-scope excluded in the current repo contract
- likely code-entry files: `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/groups/application/dissolve_group_use_case.dart`, `lib/features/share/application/handle_share_intent_use_case.dart`, `lib/features/share/application/share_batch_delivery_coordinator.dart`, `lib/features/push/application/show_notification_use_case.dart`
- existing tests or current proof: The audit and inventory both say group search is not landed. Current scope proof: `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`, `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- likely missing tests: none while the capability stays out of scope
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row UX-003; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session UX-004
- source row id: `UX-004`
- scenario title: Pinning and unpinning important messages works if the feature exists
- source section: Quality-of-Life and Higher-Level Product Capabilities
- row disposition: `unsupported_product_scope`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-004-plan.md`
- exact scope: Keep source row UX-004 explicitly out of implementation scope while the capability stays unsupported; only row-specific truth-alignment and scope proof belong here.
- execution ownership: no execution because the row is out of current product scope
- proof ownership: product-scope excluded in the current repo contract
- likely code-entry files: `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/groups/application/dissolve_group_use_case.dart`, `lib/features/share/application/handle_share_intent_use_case.dart`, `lib/features/share/application/share_batch_delivery_coordinator.dart`, `lib/features/push/application/show_notification_use_case.dart`
- existing tests or current proof: Not landed according to the audit. Current scope proof: `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`, `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- likely missing tests: none while the capability stays out of scope
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row UX-004; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session UX-005
- source row id: `UX-005`
- scenario title: Per-message edit, delete, or tombstone works if the feature exists
- source section: Quality-of-Life and Higher-Level Product Capabilities
- row disposition: `unsupported_product_scope`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-005-plan.md`
- exact scope: Keep source row UX-005 explicitly out of implementation scope while the capability stays unsupported; only row-specific truth-alignment and scope proof belong here.
- execution ownership: no execution because the row is out of current product scope
- proof ownership: product-scope excluded in the current repo contract
- likely code-entry files: `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/groups/application/dissolve_group_use_case.dart`, `lib/features/share/application/handle_share_intent_use_case.dart`, `lib/features/share/application/share_batch_delivery_coordinator.dart`, `lib/features/push/application/show_notification_use_case.dart`
- existing tests or current proof: Not landed according to the audit. Current scope proof: `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`, `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- likely missing tests: none while the capability stays out of scope
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row UX-005; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session UX-006
- source row id: `UX-006`
- scenario title: Read receipts or reader counts work if the feature exists
- source section: Quality-of-Life and Higher-Level Product Capabilities
- row disposition: `unsupported_product_scope`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-006-plan.md`
- exact scope: Keep source row UX-006 explicitly out of implementation scope while the capability stays unsupported; only row-specific truth-alignment and scope proof belong here.
- execution ownership: no execution because the row is out of current product scope
- proof ownership: product-scope excluded in the current repo contract
- likely code-entry files: `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/groups/application/dissolve_group_use_case.dart`, `lib/features/share/application/handle_share_intent_use_case.dart`, `lib/features/share/application/share_batch_delivery_coordinator.dart`, `lib/features/push/application/show_notification_use_case.dart`
- existing tests or current proof: Not landed according to the audit. Current scope proof: `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`, `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- likely missing tests: none while the capability stays out of scope
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row UX-006; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session UX-007
- source row id: `UX-007`
- scenario title: Member-level moderation such as mute or ban works if the feature exists
- source section: Quality-of-Life and Higher-Level Product Capabilities
- row disposition: `unsupported_product_scope`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-007-plan.md`
- exact scope: Keep source row UX-007 explicitly out of implementation scope while the capability stays unsupported; only row-specific truth-alignment and scope proof belong here.
- execution ownership: no execution because the row is out of current product scope
- proof ownership: product-scope excluded in the current repo contract
- likely code-entry files: `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/groups/application/dissolve_group_use_case.dart`, `lib/features/share/application/handle_share_intent_use_case.dart`, `lib/features/share/application/share_batch_delivery_coordinator.dart`, `lib/features/push/application/show_notification_use_case.dart`
- existing tests or current proof: Not landed according to the audit. Current scope proof: `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`, `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- likely missing tests: none while the capability stays out of scope
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row UX-007; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session UX-008
- source row id: `UX-008`
- scenario title: Scheduled announcements, edit-after-send, delete-after-send, or analytics work if the feature exists
- source section: Quality-of-Life and Higher-Level Product Capabilities
- row disposition: `unsupported_product_scope`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-008-plan.md`
- exact scope: Keep source row UX-008 explicitly out of implementation scope while the capability stays unsupported; only row-specific truth-alignment and scope proof belong here.
- execution ownership: no execution because the row is out of current product scope
- proof ownership: product-scope excluded in the current repo contract
- likely code-entry files: `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/groups/application/dissolve_group_use_case.dart`, `lib/features/share/application/handle_share_intent_use_case.dart`, `lib/features/share/application/share_batch_delivery_coordinator.dart`, `lib/features/push/application/show_notification_use_case.dart`
- existing tests or current proof: Not landed according to the audit. Current scope proof: `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`, `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- likely missing tests: none while the capability stays out of scope
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row UX-008; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

## Downstream Execution Path

- use this artifact as the row-granular source for later plan generation.
- create doc-scoped plan files as `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-<session-id>-plan.md` adjacent to the source matrix.
- execute sessions in this order unless a later controller has an explicit reason to pause: all P0 sessions in source order, then all P1 sessions in source order, then all P2 sessions in source order.
- do not merge adjacent rows into seam buckets during execution unless the strict merge rule is re-evaluated and still preserves exact row traceability.
- when a row closes, update the source matrix row status with concrete evidence and refresh this breakdown only if the row disposition or execution ordering materially changes.
