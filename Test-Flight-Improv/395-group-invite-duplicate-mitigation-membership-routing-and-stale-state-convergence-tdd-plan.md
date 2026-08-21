# 395 - Group Invite Duplicate Hardening, Membership Routing, And Stale UI Reconciliation

Status: implementation-ready for the bounded mitigation below; exact incident transport attribution remains unresolved
Type: Bug
Spec: free-text report from 2026-08-21: an iPhone receives a group invite, accepts it, later receives another notification for the same invite, and a tap opens Intros with “Invite no longer available / Ask for a new invite” even though the user is already a group member
Classification: implementation-ready
Closure tier: simulator

## Planning Progress

| Time | Role | Decision | Next |
|---|---|---|---|
| 2026-08-21 17:35 CEST | Evidence collector | Relay payloads retain groupId and message_id, but Dart maps every group_invite to bare Intros. Acceptance deletes the pending row but does not retire exact delivered iOS cards. Orbit can retain a stale row and maps a cached missing result to a terminal ghost without checking membership. | Plan causal transport, route, and UI branches. |
| 2026-08-21 18:20 CEST | Planner | Captured device logs do not contain the reported delivery/provider sequence. Avoid invite-ID history because multi-use invites legitimately reuse an invite ID. | Keep attribution evidence-gated and make late cards harmless. |
| 2026-08-21 19:05 CEST | Critical reviewer | Pre-edit verdict: plan-fixes-required. The draft added an underpowered physical campaign, a needless custody hash, Feed-wide projection, request epoch, two-sided lock, redundant test owners, and oversized family gates. It also missed transport-aware open dedupe, pre-action membership checks, and existing latest/active-route guards. | Apply only source-backed deltas and rerun the counterexample sweep. |

## Critical Review Disposition

The original direction was sound, but the delivery structure and several implementation bets were not proportionate.

Removed as non-load-bearing:

- The new physical APNs/Sims campaign and credential block. The existing notifications.ios_payload_fast_path adapter sends one direct APNs request and does not exercise InboxStore -> buildPushMessage, so an A1/A2/B extension could pass without proving the relay change.
- SHA-256/domain/recipient collapse-key plumbing. InboxStore already assigns a UUID row ID before persistence; that 36-byte custody ID is sufficient for Apple’s 64-byte apns-collapse-id limit.
- The shared Orbit/Feed projection layer and Feed changes. The reported rendering defect is in Orbit; Feed already filters normal active groups.
- The pending-load request epoch. Authoritative membership filtering after getPendingInvites returns, plus immediate joined-event purge, closes the reported resurrection path without a second ordering mechanism.
- The accept-side authority lock, new convergence test file, and DB/CAS discussion. The incident does not prove a durable store-after-accept race, and the display/action authority checks below make any stale row non-actionable.
- Separate cancellation-policy and group-notification-dedupe integration files, a second native test, per-plan core-host-all/feature-host-all, and the physical campaign.

Added because the first draft missed real bypasses:

- A group-invite open uses provider transport identity for the in-memory open gate. Two callbacks for one delivery dedupe; a later delivery with the same invite ID still reaches membership routing.
- Current membership is checked before Accept or committed Decline work and again before any terminal UI/Ask-new action, not only after notFound.
- The invite route reuses the existing group resolver and preserves newest-route ownership, already-active-group suppression, direct-inbox preparation, and null chat-message highlight.
- Exact iOS retirement is scheduled without awaiting it; a stuck MethodChannel can never block acceptance or navigation.

Post-edit disposition: ready to execute the bounded plan. It does not claim to identify or eliminate every source of a second card.

## Problem And Evidence

Three user-visible problems are in scope:

1. One stored relay custody can retry the same rich iOS provider message without a collapse identity.
2. A group_invite tap loses group/invite identity and always opens generic Intros.
3. Orbit can show or act on a cached invite after the local peer has already joined, then display an invalid terminal/Ask-new state.

Confirmed evidence:

- go-relay-server/inbox.go:609-703 retries the same messaging.Message. InboxStore assigns inboxMessage.ID before persistence at :1724-1741 and :1873-1878. The rich group-invite APNs projection at :806-855 has no apns-collapse-id.
- Both production rich direct-send paths currently call PushService.SendNotification without custody at go-relay-server/inbox.go:2249-2253 and :2293-2310. Opaque wake has its own mailbox identity and is out of scope.
- Apple documents that repeated notifications with one apns-collapse-id are merged for the user and that the value is limited to 64 bytes: https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns
- lib/core/notifications/notification_route_target.dart:217-220 maps group_invite to const intros and discards the relay-supplied groupId/message_id.
- lib/features/push/application/resolve_group_notification_route_target_use_case.dart:29-84 already distinguishes current local member, pending invite, and missing state. Reusing ordinary NotificationRouteTargetKind.group would be wrong because ordinary group opens use a group drain and messageId as a chat highlight.
- lib/core/notifications/notification_open_dedupe_gate.dart:50-79 prefers route message_id and holds a successful key for ten minutes. lib/app/application_root.dart:917-927 passes message.data but drops RemoteMessage.messageId. Without a special case, a distinct later custody using the same invite ID can be suppressed before membership routing.
- Acceptance commits and deletes the durable pending row at lib/features/groups/application/accept_pending_group_invite_use_case.dart:951-970. Orbit is the sole production accept caller and retains the exact PendingGroupInvite across its bounded retries at lib/features/orbit/presentation/screens/orbit_wired.dart:1833-1911.
- iOS can inventory delivered notifications and selectively remove request identifiers. The existing native center abstraction inventories identifiers only at ios/Runner/IosNotificationRecoveryCoordinator.swift:5-19,241-278; it needs a narrow native-only content snapshot for exact matching. Apple APIs: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/getdeliverednotifications%28completionhandler%3A%29 and https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/removedeliverednotifications%28withidentifiers%3A%29
- Orbit starts group and invite loads concurrently at lib/features/orbit/presentation/screens/orbit_wired.dart:571-578. _loadPendingGroupInvites at :984-1015 filters against possibly empty _activeGroups. The joined listener at :1376-1385 starts refreshes without immediately removing the cached invite/outcome.
- Orbit maps accept notFound directly to the unavailable outcome at :1657-1661 and checks only inviter contact eligibility before Ask-new at :1751-1825. Other accept failures can also become terminal rows. Decline writes a tombstone, deletes the row, and can send a decline ACK before Orbit renders a result at lib/features/groups/application/decline_pending_group_invite_use_case.dart:36-64.

Existing preservation evidence:

- test/features/groups/integration/invite_round_trip_test.dart::IJ005 multi-use direct credential replay is duplicate-safe proves the same invite ID may be valid again; no historical invite-ID tombstone or recent-message identity is allowed.
- test/features/groups/application/store_pending_group_invite_use_case_test.dart covers both current-member rejection and retained self-removed shells remaining re-invitable.
- test/features/push/application/resolve_group_notification_route_target_use_case_test.dart already covers membership/pending/missing resolution and remains the resolver owner.
- test/features/orbit/presentation/screens/orbit_wired_test.dart:6103-6169 covers normal successful acceptance. The localized cached-row case at :6189-6265 is a genuine missing-state sentinel; it does not seed a group/member and must not be rewritten as the reported current-member case.
- test/features/push/application/background_push_notification_fallback_test.dart proves group_invite uses intro-like copy today, while test_fixtures/si5_dedupe_keys.json intentionally classifies group_invite as non-message-aware.

Unresolved evidence:

- The captured iPhone/Pixel logs do not include the incident payload or provider attempt sequence. The later card may be a same-custody ambiguous provider retry, a distinct post-ACK custody, or a card already queued before acceptance.
- Therefore the collapse header is bounded same-custody rich-route hardening, not attribution of the reported incident. A distinct custody remains deliverable by design; exact retirement and membership-aware routing own that residual. No exactly-once claim is made.

## Graph Grounding Snapshot

- Architecture graph fingerprint: a029967bac2d292c. The reported stale file is unrelated lib/features/conversation/presentation/screens/conversation_wired.dart.
- Planning query: query_id f669edb672ed4d9a, evidence_digest 8984d0eb9552818b.
- Critical review query: query_id 2d18d0df2a9d49d4, evidence_digest c2726cc2e9b850cd.
- Independent relay/native counterexample branch: query_id c31054c75901408b, evidence_digest b993a6f82fe09405.
- Independent app-route/state counterexample branch: query_id ec2e0101bc104572, evidence_digest 16969ee53b5ea459.
- Post-edit route-kind sweep: query_id 565da62e3d264e9e, evidence_digest 8fc9c34fa1441db4.
- Open proof question retained for execution notes: which custody/provider sequence produced the observed second card?

## Scope Contract And Guard

In scope:

- For a rich iOS group_invite only, use the relay-assigned inboxMessage.ID directly as apns-collapse-id when its trimmed UTF-8 value is 1-64 bytes; otherwise omit the header. Both stored-rich call paths pass the same custody ID into one private rich sender. Provider retries of one row reuse it; a later row gets a different ID. Android and unknown platforms receive no collapse header; non-invite rich sends, public/test SendNotification callers, and opaque mailbox wake remain unchanged.
- Add one strict native retireGroupInvite(groupId, inviteId) operation. It matches delivered provider metadata type=group_invite + exact groupId + exact message_id, or the exact local route payload group_invite:<groupId>|message:<inviteId>; it removes selected request identifiers only.
- Add the async native method to the existing Dart bridge. Expose one synchronous best-effort scheduler on the existing Dart recovery coordinator; it owns Future.sync plus async error containment and returns immediately even when the channel future never completes. Inject that non-awaiting callback into the production GroupInviteListener so every Orbit construction path inherits it without threading another parameter through StartupRouter and FeedWired.
- Add NotificationRouteTargetKind.groupInvite with exact groupId and optional messageId. Use group_invite:<groupId> or group_invite:<groupId>|message:<inviteId>. It remains a direct-inbox, non-conversation route. Legacy remote group_invite data without groupId retains the incumbent bare-Intros fallback; legacy intros local payloads remain readable.
- For the remote-open gate only, raw type=group_invite uses gcm.message_id/provider transport identity and never invite message_id, including the legacy bare-Intros fallback. The Firebase opened-app callback copies RemoteMessage.messageId into that field when present. The recent-remote/SI5 policy remains unchanged.
- Handle group and groupInvite in the existing ApplicationRoot group branch. groupInvite calls the existing resolver after preparation with no second drain; current member opens/keeps the group with null highlight, pending opens Intros, and missing uses existing visible fallback. Preserve latest-context and already-active guards.
- In Orbit, resolve current membership from identity + group repository after the pending repository read. Filter current members independently of _activeGroups, purge joined derived state immediately, preflight Accept and committed Decline, recheck before every terminal outcome, and recheck immediately before Ask-new.
- Invoke the shared exact-retirement scheduler once after final accept success and on a late exact-ID current-member tap. Never await native retirement before returning/opening.

Hard guards:

- No historical invite ledger, invite-ID tombstone, DB migration, relay protocol change, wake-outcome work, or SI5/recent-remote message-aware group-invite change.
- No Feed production change, shared projection object, pending-load epoch, accept/store lock, or new concurrency abstraction.
- No mapping to ordinary group kind, no group-inbox drain, and no invite ID passed as initialHighlightedMessageId.
- No remove-all, cancel-all, conversation/group-wide cancellation, group-only retirement, or malformed-payload widening.
- No awaiting native retirement on the accept/navigation path.
- No new physical/APNs campaign or credential requirement for this bounded plan.

## Test Contract

| ID | Behavior and owner | RED on HEAD | GREEN and counterexample | Registration |
|---|---|---|---|---|
| TC-395-01 | go-relay-server/ordinary_push_projection_test.go::TestRelayNotificationClosure_GroupInviteCustodyRetryCollapse | One stored group-invite row retries with no apns-collapse-id. | Let Store generate custody A, read A.ID through RetrievePendingWithMeta, wait for retryable -> success provider attempts, and assert both exact-iOS attempts use A.ID. ACK that ID, store B with the same invite, retrieve B.ID, and assert B differs. Exercise normal and preflight-selected rich paths. Empty/over-64 IDs omit the header. Android and unknown-platform projections receive no collapse header; non-invite rich and opaque wake remain unchanged. Removing either custody handoff, injecting before exact iOS selection, or deriving from invite ID re-reds. | TestRelayNotificationClosure_ enters the existing groups relay gate. |
| TC-395-02 | ios/RunnerTests/IosNotificationRecoveryTests.swift::testTC395ExactGroupInviteRetirementIsSurgicalAndIdempotent | Native center exposes identifiers only and has no exact operation. | One native test feeds raw delivered userInfo through the production snapshot extractor: provider rows require the exact top-level type/groupId/message_id triplet; local rows require FLN NotificationId plus exact payload. Include newer same-group invite, same invite ID in another group, ordinary group/direct cards, and malformed maps. Only exact copies are removed; re-inventory and a second call are empty/successful. Any wrong extraction, partial match, substring, or remove-all mutation re-reds. | Add one selector to XCODE_TESTS and update every hard-coded census/assertion/message from 16 -> 17. The full 17-selector script remains wave/release-owned. |
| TC-395-03 | test/core/notifications/ios_notification_recovery_bridge_test.dart, local_notification_exact_cancellation_wiring_test.dart, and test/features/orbit/presentation/screens/orbit_wired_test.dart | No exact bridge method or post-success retirement exists. | Bridge sends strict groupId/inviteId. The coordinator’s synchronous scheduler contains synchronous throws and failed futures, and returns while a deliberately uncompleted future remains pending. Final Orbit accept success invokes it exactly once using the retained invite; non-success invokes it zero times and group open is not delayed. The existing source owner proves production bootstrap injects that scheduler once into GroupInviteListener, covering direct-Intros and StartupRouter -> Feed -> Orbit paths. | Existing core/groups owners; no new wiring test file. |
| TC-395-04 | test/core/notifications/notification_route_target_test.dart, notification_route_contract_matrix_test.dart, notification_open_dedupe_gate_test.dart, remote_notification_identity_test.dart, and local_notification_exact_cancellation_wiring_test.dart | group_invite becomes bare Intros; two distinct deliveries can share the invite-ID open key; the warm Firebase callback drops RemoteMessage.messageId. | Exact route round-trip and both contract-matrix loops assert groupId and messageId. Remote group-only invite routes safely without retirement; legacy remote data missing groupId remains bare Intros; malformed new local payloads fail closed. The production source owner proves warm callback enrichment preserves an existing nonblank gcm.message_id and otherwise copies trimmed RemoteMessage.messageId before routing. Same provider transport ID across native/Firebase maps dedupes; different transport IDs with the same group/invite both begin; missing transport ID creates no invite-history key. A legacy type=group_invite map with message_id and transport ID but no groupId still uses the transport key while routing to bare Intros. Realistic group_invite+message_id fixtures still make recent-open marking and foreground-sidecar discard return false. | Add/retain these shared files in GROUP_TESTS and incumbent notification lanes. |
| TC-395-05 | test/features/push/application/prepare_notification_open_use_case_test.dart, handle_foreground_remote_message_use_case_test.dart, background_push_notification_fallback_test.dart, background_message_handler_test.dart, flutter_notification_service_test.dart, and test/integration/notification_tap_smoke_test.dart | The new kind is absent; the existing foreground fixture expects Intros; a naïve group mapping would drain the group inbox and collide with group:<id>. | Prepared and foreground groupInvite flows each perform exactly one direct drain and zero group drains. Local fallback retains exact group_invite payload and intro-like copy. Both background conversation-key and foreground generic-notification allocation use the exact invite payload, never group:<id>. Ordinary group drain/highlight remains unchanged. | Existing AUTO owners plus explicit GROUP_TESTS where required. |
| TC-395-06 | test/features/push/application/chat_and_group_push_open_flow_test.dart, test/core/notifications/app_root_notification_open_test.dart, test/core/notifications/local_notification_exact_cancellation_wiring_test.dart, and integration_test/notification_open_ui_smoke_test.dart | The current-member UI fixture routes to Intros and there is no production groupInvite branch. | Current member -> invoke the non-awaiting exact-retirement scheduler and open group once with null highlight; pending/retained-removed -> Intros; missing -> existing feedback. Resolver gets null drain after the one preparation drain. The private-glue owner locks latest check before side effects, canonical ordinary-group active comparison, scheduler invocation before the active-return, no await on that path, and null highlight. The coordinator test proves an incomplete/failed native future cannot delay late-tap navigation; the existing iOS-simulator UI fixture opens the seeded current-member group instead of Intros. | Host owners enter core/groups as applicable. Run the existing integration fixture only through its pinned simulator wrapper; do not add a new campaign or curated host entry. |
| TC-395-07 | test/features/orbit/presentation/screens/orbit_wired_test.dart::TC-395-07 current-member invite never renders or mutates | Orbit can filter against empty _activeGroups and can turn cached action results into terminal ghosts. | Cover: pending load completes before group hydration but authoritative current membership suppresses row/count; joined stream immediately purges row/outcome/Ask; cached current-member Accept opens existing group without calling accept parsing; committed Decline performs no tombstone/delete/ACK; membership becoming current during a non-notFound failure suppresses terminal UI; Ask-time membership suppresses the draft. The existing genuine-missing localized test and normal unjoined decline remain green. | Existing GROUP_TESTS owner. |
| TC-395-08 | Existing multi-use, retained-shell, ordinary-group, and broad-cancellation sentinels | Green on HEAD. | IJ005 multi-use replay and retained self-removed rejoin remain valid; ordinary group message highlighting/drain is unchanged; local_notification_exact_cancellation_wiring_test.dart continues to forbid blanket cleanup. Any policy-blind history or broad cancellation re-reds. | Existing curated registrations only. |

### RED Discipline

- Record representative TC-395-01, TC-395-04 transport-dedupe, and TC-395-07 current-member action REDs before production edits.
- A RED is valid only when it fails on the stated behavior, not because a fixture, simulator, Firebase setup, or localization is missing.
- TC-395-08 is a green preservation set, not an invented RED.

## Implementation Steps

1. Snapshot git status and preserve all unrelated dirty work.
2. Add TC-395-01. Thread the Store-generated entry.ID only through the two stored-rich paths into one private sender and attach the bounded header only after exact platform=ios selection. Android and unknown platform must not receive it. Keep public SendNotification and opaque wake unchanged.
3. Add the one native TC-395-02 test, then implement a narrow Sendable delivered-request snapshot extracted from raw userInfo, strict exact matching, selective removal, re-inventory, AppDelegate method handling, the Dart bridge method, and the coordinator’s synchronous best-effort scheduler.
4. Add TC-395-04/05. Introduce the distinct route kind, strict payload grammar, transport-ID normalization for Firebase opened-app maps, groupInvite-only open-gate keying, direct preparation, intro-like fallback copy, and distinct local registry identity. Update exhaustive switches without changing recent-remote/SI5 semantics.
5. Add TC-395-06 by extending the existing ApplicationRoot group branch and existing resolver. Preserve the latest-context and already-active guards; pass null highlight for invite routes and do not request another direct drain.
6. Inject the optional non-awaiting scheduler once when production constructs GroupInviteListener. Invoke it at the sole Orbit accept owner and late current-member route; never modify acceptPendingGroupInvite’s signature.
7. Add TC-395-07. Implement one small Orbit-local current-member lookup, authoritative post-load filtering, joined-event purge, action preflights, all-terminal-result recheck, and Ask-time recheck. Do not add a projection service, Feed change, epoch, or lock.
8. Run focused tests and mutations, exact preservation sentinels, exact Go/Xcode boundaries, groups, intro, and completeness. Run scoped format/analyze and Graphify impact/refresh after the coherent app-owned code batch.

## Risks And Blind Spots

- The observed second card may be a distinct custody or already queued before acceptance. TC-395-01 closes only same-custody retry identity; TC-395-03/06/07 make the remaining card harmless.
- Keying the open gate by invite ID would suppress a later card before safe routing. TC-395-04 uses provider transport identity only for groupInvite.
- Native cleanup could delete a sibling or hang UI. TC-395-02 proves exact negative discriminators; the shared scheduler in TC-395-03 proves non-awaited containment for both acceptance and late-tap callers.
- A route refactor could bypass newest-route or already-active ownership. TC-395-06 preserves both existing guards.
- Group-row existence could misclassify a retained removed-member shell. TC-395-06/07 require an actual local member row; TC-395-08 preserves rejoin.
- New local payloads must not break incumbent inputs. TC-395-04 keeps bare intros and remote missing-group fallback readable; downgrade behavior for a notification generated by a newer binary is not claimed because no relay/DB wire format changes and app-store rollback is outside this plan.
- Exhaustive switches do not cover semantic helpers. TC-395-05 explicitly covers fallback copy and conversation/registry identity.
- A pure dedupe test could pass while production still drops Firebase transport identity. TC-395-04 includes a source-wiring assertion at the onMessageOpenedApp entrypoint.
- A header placed on the dual-platform draft could leak through unknown-platform fail-open projection. TC-395-01 requires an exact iOS route and tests the unknown-platform counterexample.
- Pre-normalized native fixtures could hide wrong provider/FLN keys. TC-395-02 enters through the raw userInfo snapshot extractor.
- Accept can fail with more than notFound, and Decline mutates before reporting. TC-395-07 preflights actions and rechecks before every terminal/Ask surface.
- Exact duplicate attribution remains unresolved. A future recurrence with provider/custody traces may justify a separate evidence plan; it is not silently claimed closed here.

## Gate Cadence

- Per-plan: representative causal REDs, all focused Dart/Go/Swift tests, exact multi-use/retained-shell preservation, groups, intro, completeness-check, and scoped analyze/format.
- Do not run per-plan core-host-all, feature-host-all, or full host-all. The relevant dependency wave and final release retain the two full host-all runs required by project cadence.
- No Feed gate and no physical-device campaign. Simulator work is limited to the exact native XCTest and the existing notification-open UI wrapper on one available, explicitly selected iOS simulator.

## Acceptance Gates

~~~bash
# Snapshot before execution.
git status --short

# Representative causal REDs before production edits.
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . \
  -run '^TestRelayNotificationClosure_GroupInviteCustodyRetryCollapse$' -count=1)
flutter test test/core/notifications/notification_open_dedupe_gate_test.dart \
  --plain-name 'TC-395-04 distinct group invite transport ids both route'
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart \
  --plain-name 'TC-395-07 cached current-member accept opens group without terminal invite state'

# Focused Dart GREEN.
flutter test --concurrency=2 --reporter failures-only \
  test/core/notifications/notification_route_target_test.dart \
  test/core/notifications/notification_route_contract_matrix_test.dart \
  test/core/notifications/notification_open_dedupe_gate_test.dart \
  test/core/notifications/remote_notification_identity_test.dart \
  test/core/notifications/app_root_notification_open_test.dart \
  test/core/notifications/ios_notification_recovery_bridge_test.dart \
  test/core/notifications/local_notification_exact_cancellation_wiring_test.dart \
  test/core/notifications/flutter_notification_service_test.dart \
  test/features/push/application/prepare_notification_open_use_case_test.dart \
  test/features/push/application/handle_foreground_remote_message_use_case_test.dart \
  test/features/push/application/resolve_group_notification_route_target_use_case_test.dart \
  test/features/push/application/background_push_notification_fallback_test.dart \
  test/features/push/application/chat_and_group_push_open_flow_test.dart \
  test/features/orbit/presentation/screens/orbit_wired_test.dart \
  test/integration/notification_tap_smoke_test.dart

# Exact background identity owner if it is not already selected above.
flutter test test/features/push/application/background_message_handler_test.dart \
  --plain-name 'TC-395-05 group invite fallback keeps a non-conversation exact route identity'

# Exact preservation sentinels.
flutter test test/features/groups/integration/invite_round_trip_test.dart \
  --plain-name 'IJ005 multi-use direct credential replay is duplicate-safe'
flutter test test/features/groups/application/store_pending_group_invite_use_case_test.dart \
  --plain-name 'retained keyless shell (self not a member) STORES the pending invite, not duplicateGroup'

# Relay GREEN.
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . \
  -run '^TestRelayNotificationClosure_GroupInviteCustodyRetryCollapse$' -count=1)

# Resolve an available simulator at execution time and pin the command to its
# explicit UDID. The planning-time available target is shown here.
xcrun simctl list devices available
xcodebuild test \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=iOS Simulator,id=674DFFF6-5F38-4235-93F6-AF7FBF86AE65' \
  CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO \
  -only-testing:RunnerTests/IosNotificationRecoveryTests/testTC395ExactGroupInviteRetirementIsSurgicalAndIdempotent

# Existing automated UI fixture; use the same explicitly discovered simulator.
dart run integration_test/scripts/run_notification_open_ui_smoke.dart \
  --platform ios --device 674DFFF6-5F38-4235-93F6-AF7FBF86AE65

# Affected curated lanes.
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh intro
./scripts/run_test_gates.sh completeness-check

# Scoped hygiene after implementation.
test -z "$(gofmt -l go-relay-server/inbox.go \
  go-relay-server/ordinary_push_projection_test.go)"
dart format --output=none --set-exit-if-changed \
  lib/core/notifications/notification_route_target.dart \
  lib/core/notifications/notification_open_dedupe_gate.dart \
  lib/core/notifications/app_root_notification_open.dart \
  lib/core/notifications/flutter_notification_service.dart \
  lib/core/notifications/ios_notification_recovery_bridge.dart \
  lib/core/notifications/ios_notification_recovery_coordinator.dart \
  lib/features/push/application/prepare_notification_open_use_case.dart \
  lib/features/push/application/handle_foreground_remote_message_use_case.dart \
  lib/features/push/application/background_push_notification_fallback.dart \
  lib/features/push/application/background_message_handler.dart \
  lib/features/groups/application/group_invite_listener.dart \
  lib/features/orbit/presentation/screens/orbit_wired.dart \
  lib/app/application_root.dart \
  lib/app/bootstrap/production_application_bootstrap.dart
flutter analyze \
  lib/core/notifications \
  lib/features/push/application \
  lib/features/groups/application/group_invite_listener.dart \
  lib/features/orbit/presentation/screens/orbit_wired.dart \
  lib/app/application_root.dart \
  lib/app/bootstrap/production_application_bootstrap.dart
python3 graphify-arch/tdd_context.py affected \
  go-relay-server/inbox.go \
  lib/core/notifications/notification_route_target.dart \
  lib/core/notifications/notification_open_dedupe_gate.dart \
  lib/core/notifications/app_root_notification_open.dart \
  lib/core/notifications/flutter_notification_service.dart \
  lib/core/notifications/ios_notification_recovery_bridge.dart \
  lib/core/notifications/ios_notification_recovery_coordinator.dart \
  lib/app/application_root.dart \
  lib/app/bootstrap/production_application_bootstrap.dart \
  lib/features/push/application/prepare_notification_open_use_case.dart \
  lib/features/push/application/handle_foreground_remote_message_use_case.dart \
  lib/features/push/application/background_push_notification_fallback.dart \
  lib/features/push/application/background_message_handler.dart \
  lib/features/groups/application/group_invite_listener.dart \
  lib/features/orbit/presentation/screens/orbit_wired.dart \
  ios/Runner/IosNotificationRecoveryCoordinator.swift \
  ios/Runner/AppDelegate.swift --budget 600
./graphify-arch/refresh_arch_graph.sh --incremental
git diff --check
~~~

## Device And Native Proof Profile

- Required target: one iOS simulator available at execution time, selected from xcrun simctl list devices available and passed by exact UDID to xcodebuild.
- Planning-time available target: 674DFFF6-5F38-4235-93F6-AF7FBF86AE65.
- Boundary proven: native raw-userInfo extraction, delivered-request parsing, and selective identifier removal through a fake center compiled and executed in RunnerTests; the existing UI harness proves the current-member route on the same simulator.
- Not claimed: a new real-APNs multi-request experiment or attribution of the historical incident. Apple’s documented collapse contract plus the Go header test is the bounded transport evidence.
- Physical iPhone and Android peer: N/A for required closure; this plan contains no iOS-version-specific behavior that needs unavailable hardware and no two-peer interaction.

## Done Criteria

- [ ] One relay custody supplies one stable iOS group-invite collapse ID across provider retries; another custody using the same invite gets a different ID. Android/non-invite/opaque routes are unchanged.
- [ ] Exact native retirement removes only provider/local cards matching type + groupId + inviteId and is idempotent.
- [ ] Successful acceptance and a late current-member tap schedule retirement without waiting; failures never block success/navigation.
- [ ] groupInvite preserves group/invite identity, direct-inbox preparation, intro-like fallback copy, and a non-conversation registry identity.
- [ ] Same provider delivery dedupes across native/Firebase callbacks; distinct provider transport IDs with the same invite both reach routing; SI5/recent-remote group-invite classification is unchanged.
- [ ] Current-member taps open or keep the group with null highlight and preserve latest/active guards; pending/retained-removed and genuine missing states keep their correct fallbacks.
- [ ] Orbit never renders/counts or mutates an invite for a current member, immediately purges joined derived state, and never offers Ask-new to a current member.
- [ ] The existing genuine-missing localized case, normal accept/decline, multi-use replay, retained-shell rejoin, ordinary group route, and surgical-notification guards remain green.
- [ ] Focused Dart/Go/Swift, groups, intro, completeness, scoped hygiene, Graphify affected, and incremental refresh pass. No per-plan family/full host-all or physical campaign runs.
- [ ] Closure notes state that the original duplicate source remains unresolved and make no exactly-once claim.

## Handoff

- First RED: (cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . -run '^TestRelayNotificationClosure_GroupInviteCustodyRetryCollapse$' -count=1)
- First app RED: flutter test test/core/notifications/notification_open_dedupe_gate_test.dart --plain-name 'TC-395-04 distinct group invite transport ids both route'
- Preservation command: run IJ005 plus the retained keyless-shell test exactly as listed above.
- Registration: add only the affected host Dart owners to GROUP_TESTS, one Swift selector to XCODE_TESTS and every hard-coded native census (16 -> 17), and the existing TestRelayNotificationClosure_ Go owner. Keep integration_test/notification_open_ui_smoke_test.dart on its existing simulator-wrapper path rather than a curated host batch. Do not create a Sims owner, Feed owner, new coordinator test file, or new convergence test file.
- Migration: none; DB stays v116.
- Unresolved evidence: the historical second card’s custody/provider sequence.

## Execution Progress

| Time | Phase | Last result | Next |
|---|---|---|---|
| - | not started | Critical review completed; bounded plan ready | Capture representative REDs while preserving the dirty tree. |
