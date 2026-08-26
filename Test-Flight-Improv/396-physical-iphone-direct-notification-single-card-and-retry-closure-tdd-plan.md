# 396 - Physical iPhone Direct-Notification Single-Card And Retry Closure

Status: complete by explicit user acceptance on 2026-08-22; automated physical PASS waived and not claimed
Type: Verification with bounded direct-retry hardening
Spec: 2026-08-21 user report that manual iPhone testing may show the same notification twice, possibly from an old and a new presentation path, after Plans 394 and 395 completed
Classification: completed with documented physical-proof limitation
Closure tier: physical device

## Planning Progress

| Time | Role | Decision | Next |
|---|---|---|---|
| 2026-08-21 CEST | Evidence collector | Plans 394 and 395 are complete. The registered `notifications.ios_payload_fast_path` capability already uses a physical iPhone, real development APNs, the production NSE, a warm-background app, native delivered-notification inventory, and zero manual actions. | Reuse it instead of creating another device harness. |
| 2026-08-21 CEST | Causality audit | Rich and fixed opaque wakes are mutually exclusive and fixed-wake admission is disabled in `ios.device.production`; “old rich plus new fixed wake” is not a viable cause in this profile. The credible causes are a provider card plus a Flutter-local card, or an ambiguous rich-provider retry. | Add source-qualified inventory and one bounded retry proof. |
| 2026-08-21 CEST | Scope review | A physical group-invite leg would not prove Plan 395's `InboxStore -> buildPushMessage` collapse projection and would recreate the underpowered campaign that its review removed. An Android sender would create a second topology before the existing iPhone topology is exhausted. | Keep one physical iPhone, one direct-rich payload, and exact Plan 395 host/native preservation only. |
| 2026-08-21 CEST | Initial sufficiency audit | The draft reused one capability and one iPhone, selected focused owners plus the affected `1to1` lane, and excluded family/full aggregates and optional device matrices. | Run the independent counterexample review before execution. |
| 2026-08-21 CEST | Independent `$tdd-review` | The direction was confirmed, but the direct-APNs fixture could not invoke FlutterFire's background callback, the local classifier did not cover the real typed payload envelope, the retry oracle could pass on a sanitized replacement, early recovery failures lacked an exact cleanup owner, and the Sims artifact-schema entrypoint was omitted. | Apply exact plan fixes without adding a harness, peer, capability, or broad test gate. |
| 2026-08-21 CEST | Review-fix integration | The plan now uses one FCM-shaped direct-APNs fixture, OS-trigger plus bounded-envelope source attribution, a first-delivery-fenced retry proof with useful-content authority, same-request passive replacement preservation, unconditional bounded rollback, and the incumbent artifact-schema entrypoint. | Execute the revised focused contract once; allow at most one evidence-backed rerun after a plan-owned repair. |
| 2026-08-22 CEST | Execution and closure | The deterministic TC-396-01/02/04/06 implementation landed in the working tree. Two registered iPhone 13 attempts failed before a complete source/retry result: the first before provider setup and the sole rerun after first-request APNs acceptance, with a 155-second NSE observation containing zero markers. A later manual Pixel-to-iPhone 11 diagnostic on the sole remaining `com.mknoon.app` installation produced one visible card and live NSE `envelope staged`, `decrypt OK`, and authorized content-handoff evidence. | The user explicitly directed Codex to assume the plan finished and update this document. Close administratively without another campaign and without representing the manual diagnostic as the missing content-addressed PASS. |

## Problem And Evidence

The user-visible question is narrow: can one logical direct notification leave two cards on the current physical-iPhone path, and, if so, which owner created them?

Established behavior and evidence:

- `tool/sims/critical_features.json:713-730` registers `notifications.ios_payload_fast_path` as required and automation-ready. It uses `ios.device.production`, one exclusive physical iPhone, real development APNs/NSE, content-addressed evidence, and the existing private setup/cleanup adapter. The physical send is direct to development APNs; the production relay projection is proven separately in Go and the combined result is a composed proof, not relay-to-APNs E2E.
- `ios/RunnerUITests/NotificationTapUITests.swift:889-921` launches the production-bundle app, grants notification permission, and backgrounds it. No user tap is needed for setup.
- The recovery leg inventories `UNUserNotificationCenter.getDeliveredNotifications` at `ios/Runner/AppDelegate.swift:569-716` and already requires counts `1 -> 2 -> 1` around an unrelated sentinel. Therefore one accepted provider request producing two persistent cards already fails; it is not merely a screenshot smoke test.
- The current receipt does not say whether a failing second card is provider-rich, Flutter-local, or unknown. It also returns after the first ordered NSE sequence and normally writes the durable artifact only on PASS. A failure can therefore lose the causal source evidence that would prevent another guessing loop.
- `go-mknoon/cmd/iospayloadproducer/main.go:384-399` currently emits `aps.alert` plus `mutable-content`, while production rich direct payloads also set `content-available` at `go-relay-server/inbox.go:959-988`. The fixture also lacks a bounded `gcm.message_id`, and FlutterFire's background callback is gated on that key in the installed plugin. A provider=1/local=0 result from the old fixture therefore never exercised the suspected Dart/local contender.
- `lib/core/notifications/conversation_notification_content_kind.dart:121-195` shows that a typed direct Flutter-local card normally carries `mknoon-conversation-card-v1:<base64url>` rather than a bare route. Source attribution must derive remote/local origin from Apple's request trigger and then validate the exact provider route or bounded local envelope; `userInfo` shape alone is not source authority.
- `lib/core/bridge/p2p_bridge_client.dart:839-883`, `go-relay-server/inbox.go:285-332`, and `ios/NotificationService/NotificationService.swift:69-79` establish exclusive rich-versus-opaque selection. The `ios.device.production` profile does not enable the wake-outcome coordinator. This plan must not add work for the refuted dual-route hypothesis.
- `go-relay-server/inbox.go:662-759` retries the same provider message after transient errors. Plan 395 added stable custody collapse only for stored rich `group_invite` at `go-relay-server/inbox.go:1251-1283`; the same helper deliberately leaves stored direct `new_message` without an `apns-collapse-id`. A provider-accepted-but-ambiguous first attempt can therefore expose two ordinary rich requests.
- `ios/NotificationService/NotificationService.swift:241-246` sanitizes an ordinary duplicate while `sanitizeNotificationContentForUnresolvedExpiry` leaves routing `userInfo` intact. If two same-collapse deliveries both reach the NSE, a terminal provider-shaped count can therefore pass while the surviving replacement is blank/passive. The retry oracle must bind both device handoffs and the final useful-content state.
- The NSE/Dart recent-remote seam normally prevents a provider card and Flutter local card from both surviving. Its exact parity owners are `ios/NotificationService/NotificationPreviewResolver.swift` (`RecentRemoteShownMarkerStore`), `lib/core/notifications/recent_remote_notification_gate.dart`, and `lib/features/push/application/show_notification_use_case.dart`. A physical mismatch remains evidence-gated; this plan does not pre-authorize a new dedupe service.
- Plan 395 already owns group-invite custody collapse, exact accepted-card retirement, and harmless membership-aware late taps. Its historical second-card provider/custody sequence remains unresolved, and distinct custody remains intentionally deliverable. Plan 396 neither adds an invite-ID tombstone nor claims exactly-once group invites.

## Graph Grounding Snapshot

- Architecture graph fingerprint: `1ab67f0274d6296f`.
- Branch checkpoint: `c42f9d930b3451a5`.
- Planning query: `query_id=36b2f9dd3de84f7f`, `evidence_digest=81c919dd455d15f8`.
- Exact refinement after the browse checkpoint: `query_id=8022aac87636456e`, `evidence_digest=3f56f13332d8ff29`.
- Anchors: `RecentRemoteShownMarkerStore` in `ios/NotificationService/NotificationPreviewResolver.swift`, `_submit_apns` in `integration_test/scripts/ios_notification_provider_adapter.py`, `processPendingIosNotificationRecoveryProof` in `ios/Runner/AppDelegate.swift`, and `projectStoredDirectPushMessageForPlatform` in `go-relay-server/inbox.go`.
- Open proof question: does the suspected duplicate classify as provider-rich plus Flutter-local, two provider-rich requests, or no duplicate on the bounded current path?

## Scope Contract And Guard

In scope:

- Extend the existing `notifications.ios_payload_fast_path` capability in place. Do not add a capability, general device controller, second application, or second artifact framework.
- Make the existing private direct-APNs fixture FCM-shaped for this one bounded test: retain the encrypted rich `new_message`, add `aps.content-available = 1`, and add one synthetic bounded `gcm.message_id`. Prove that FlutterFire reached the registered background Dart handler and that the existing recent-remote gate produced the sole terminal local-contender outcome. This emulates the production callback shape without claiming an actual FCM transport leg.
- In its fresh warm-background recovery leg, observe one exact direct `new_message` through a bounded settle window and retain source-qualified delivered inventory: OS-derived remote/local origin, matching provider-rich, matching Flutter-local, matching unknown, matching expected rich copy, matching sanitized provider copy, total delivered, stable-sample count, and hashed request identities only. A local match understands the bounded `mknoon-conversation-card-v1` envelope and validates its embedded route/event identity.
- Count the complete observation window for NSE and redacted Flutter effect markers. PASS requires the expected background handler reach, one `recent_remote_push` suppression, and zero matching `NOTIFICATION_SHOWN`; a transient local presentation cannot disappear before inventory and still pass.
- Retain a secret-free diagnostic receipt on PASS and FAIL. A failing receipt is evidence, never a Sims PASS artifact.
- Add one fresh-install same-payload retry leg to the same campaign. Submit the first encrypted APNs request with one bounded collapse identity, require its exact authorized NSE handoff and stable useful provider card, then submit the same bytes again with the same collapse identity. Require two HTTP 200 acceptances with distinct hashed provider IDs, a second trusted-passive device/NSE handoff, a final request-identifier hash bound to the collapse-identity hash, exactly one useful provider card with zero sanitized/local/unknown cards, and zero matching local-show effects across the complete retry window.
- Close the matching production gap with the existing durable inbox custody ID: stored rich iOS `new_message` and `group_invite` reuse the same bounded collapse ID across retries; distinct rows differ. At the existing NSE recovery seam, distinguish the exact same Apple request identifier plus same ordinary identity from a different-request duplicate: the former retains trusted copy as a passive/silent replacement, while the latter keeps the incumbent sanitization. Public sends, contact/invite-like non-message types, Android, unknown platforms, reactions, group-topic/strict-group message projection, and opaque mailbox wake remain unchanged.
- If the single-submission leg records a matching Flutter-local card or matching `NOTIFICATION_SHOWN`, add one sanitized causal fixture from that evidence and repair only the existing NSE/Dart recent-remote key/consume seam. The final device oracle remains one useful provider-rich card, zero Flutter-local cards, and zero matching local-show effects.
- Make cleanup independent of provider-setup completion. A typed failure before setup, after sender seeding, or between the two retry submissions must still invoke the existing idempotent sender/fixture/candidate-app rollback and retain the redacted causal diagnostic before deleting private intermediates.
- Update `integration_test/scripts/run_ios_notification_payload_sims.dart` so its existing `--artifact-schema` output declares the new source, background-contender, retry, useful-content, and cleanup checks exactly once.
- Update the two UI-23 coverage documents and the index only with the exact physical direct-rich claim and any causally proven fix. Do not convert this into consolidated Apple/release acceptance.

Out of scope:

- A new iOS harness, manual taps, manual log review, or blind automatic reruns of a failed whole device campaign.
- An Android sender/iPhone receiver live-P2P topology. The existing warm-background APNs path first tests the suspected provider/local double-presentation boundary. A later real-live race requires new evidence, not speculative inclusion here.
- Physical group-invite, group-message, reaction, media, muted, foreground, cold-kill, multi-iPhone, OS-version, TestFlight, production-APNs, notification-sound, or exhaustive flavor matrices.
- Fixed-wake activation, notification-filtering entitlements, an app-wide notification ledger, a new dedupe database/store, invite-ID history, or broad cancellation.
- A general APNs submission API, generalized rollback framework, or cross-platform notification-source abstraction. The fixture, retry resubmission, source projection, and cleanup stay private to the incumbent capability.
- A guarantee of one audible effect. This plan proves delivered-card cardinality and source ownership; iOS does not expose a reliable programmatic sound-count oracle in this rig.
- Per-plan `core-host-all`, `feature-host-all`, or full `host-all`.

## Test Contract

| ID | Required behavior | Test owner and causal oracle | Failure meaning |
|---|---|---|---|
| TC-396-01 | Native delivered inventory derives remote/local origin from Apple's notification trigger, then classifies the exact logical message as useful provider-rich, sanitized provider-rich, Flutter-local, or unknown without exporting raw request IDs, `userInfo`, tokens, message text, peer IDs, or ciphertext. A valid Flutter-local shape requires a bounded numeric `NotificationId` and either the still-supported exact legacy route or a valid bounded `mknoon-conversation-card-v1` envelope whose embedded route/event identity matches. Provider-shaped local notifications, malformed envelopes, mixed shapes, wrong events, and invalid numeric IDs fail to unknown. | Add focused vectors to `ios/RunnerTests/IosNotificationRecoveryTests.swift`, one small cross-language vector file at `test/shared/fixtures/ios_direct_notification_source_v1.json` read by that suite and `test/core/notifications/conversation_notification_content_kind_test.dart`, and exact result-schema vectors to `ios/RunnerTests/IosReceiverBootstrapHandoffTests.swift`. Mutating trigger origin, embedded route, useful content, or envelope version must fail. | The device count can misattribute a producer, miss the actual local payload, or accept a blank provider replacement. |
| TC-396-02 | The private producer emits the exact encrypted rich route plus `aps.alert`, `mutable-content:1`, `content-available:1`, and one bounded synthetic `gcm.message_id`; no plaintext or protected receiver material escapes. The protected recovery probe waits at least three seconds after the observed provider handoff, then requires three identical inventory samples at 500 ms spacing within an eight-second hard deadline. Its versioned receipt includes exact source/useful-content counts, bounded sample metadata, hashed request identities, complete-window NSE counts, and redacted Flutter contender-effect counts. The incumbent Sims entrypoint and row list every new check exactly once. | `go-mknoon/cmd/iospayloadproducer/main_test.go`, `scripts/test/ios_receiver_bootstrap_test.py`, `scripts/test/ios_receiver_bootstrap_contract_test.dart`, `test/integration/ios_notification_payload_xcui_contract_test.dart`, `test/integration/ios_notification_payload_campaign_support_test.dart`, `integration_test/scripts/run_ios_notification_payload_sims.dart`, and `test/tool/sims/sims_manifest_test.dart`. Mutations that omit either FCM-shape key, accept `>= 1`, drop an effect marker, or advertise the old artifact schema must fail. | Dart never ran, an early/transient local presentation disappeared before inventory, or the registered artifact contract remained stale. |
| TC-396-03 | One real development-APNs submission to the explicitly pinned warm-background iPhone produces exactly one ordered authorized NSE stage/decrypt/handoff sequence, reaches FlutterFire's registered background Dart handler, records exactly one `NOTIFICATION_SUPPRESSED reason=recent_remote_push`, records zero matching `NOTIFICATION_SHOWN`, and settles at one useful provider-rich card with zero sanitized provider-rich/Flutter-local/unknown cards. It retains zero child builds, zero manual actions, and automatic restoration/removal. | The existing registered `notifications.ios_payload_fast_path` capability, extended in place. The content-addressed PASS artifact binds the inventory and redacted complete-window effect receipt; a secret-free failure diagnostic is retained when any exact oracle fails. | This is the physical answer for the direct-APNs/NSE plus production-shaped Flutter-local contender boundary; absence of the Dart marker is not a PASS. |
| TC-396-04 | A stored rich iOS direct `new_message` uses its existing inbox row custody ID as a nonempty, trimmed, <=64-byte collapse identity. Transient retries of the same row reuse it; ACK plus a new row differs. `group_invite` retains Plan 395 behavior. Public sends, Android, unknown platform, contact-like types, reactions, group pushes, and opaque wake remain unchanged. For an exact same request identifier plus ordinary identity, the NSE retains trusted title/body as a passive/silent replacement; a different-request duplicate remains sanitized. The physical leg fences the first accepted request through its authorized NSE handoff and stable useful card before sending the identical second request. It then proves a second trusted-passive NSE handoff, two distinct accepted provider-ID hashes, final request-ID hash equal to collapse-ID hash, exactly one useful provider card with zero sanitized/local/unknown cards, and zero matching local-show effects across the complete retry window. | Add `TestRelayNotificationClosure_DirectMessageCustodyRetryCollapse` beside the Plan 395 test, focused same-request-versus-different-request native REDs in `IosNotificationRecoveryTests`/`NotificationPreviewResolverTests`, no-network provider-adapter first/second receipt tests, and the same existing physical campaign. The Go RED proves the missing header; the native RED proves the incumbent same-request blanking behavior. | A retry was not observed on the phone, a blank/passive shell replaced useful copy, a transient local contender appeared, a different event was over-coalesced, or the production projection diverged from the device mechanism. |
| TC-396-05 | If and only if TC-396-03 records `matchingFlutterLocalCount > 0` or a matching local-show effect, a sanitized captured key-shape reproduces the mismatch in a focused host test before the minimal existing-seam repair. Both live-first/FCM-late and FCM-first/live-late preservation remain one-card, and the physical rerun reaches useful-provider=1, local=0, local-show=0. No local duplicate evidence means no additional Dart/recent-remote product edit in this branch. | `test/core/notifications/recent_remote_notification_gate_test.dart`, `test/features/push/application/show_notification_use_case_test.dart`, `test/integration/chat_notification_dedupe_integration_test.dart`, plus the exact Swift shared-key fixture only if the captured mismatch is native. | A speculative client-side dedupe change was made without physical causality, or a transient/persistent local contender remains. |
| TC-396-06 | Cleanup is idempotent on PASS and every typed failure, including before provider setup, after sender projection, and between retry submissions: network restored, app terminated/uninstalled, notification state cleared, relay fixture and sender projection cleared, protected intermediates deleted, raw syslog deleted, and only the already-written redacted bounded diagnostic retained. Plan 395 invite collapse and surgical retirement remain green. | Add focused pre-provider/post-seed/mid-retry failure contracts to `test/integration/ios_notification_payload_xcui_contract_test.dart` and the existing provider/bootstrap rollback suites. Preserve `TestRelayNotificationClosure_GroupInviteCustodyRetryCollapse` and `IosNotificationRecoveryTests.testTC395ExactGroupInviteRetirementIsSurgicalAndIdempotent`. Do not create a generalized rollback framework. | The proof pollutes the dedicated phone/fixture, deletes its causal diagnostic before retention, or regresses the just-landed invite closure. |

### RED Discipline

- TC-396-01/02 must first fail because the current versioned receipts have no OS-derived source/useful-content inventory, the producer omits the FCM background-callback shape, and the Sims entrypoint advertises only the old checks.
- TC-396-04's Go test must first fail because the current stored `new_message` assertion requires no collapse header. Its native same-request RED must also show that an incumbent ordinary duplicate is sanitized to blank/passive while retaining provider routing. Do not weaken Plan 395's distinct-custody, different-request sanitization, or platform-preservation cases to make either test green.
- TC-396-03 is a physical acceptance oracle, not a manufactured production RED. If it passes on the first instrumented build, record that result and make no TC-396-05 production edit.
- A TC-396-03 local duplicate or local-show marker authorizes only the existing sidecar/key/consume branch. An absent background-handler marker, unknown source, sanitized provider replacement, secret-bearing diagnostic, unstable inventory, or missing second retry handoff is a failed plan, not permission to add another architecture layer.

## Implementation Steps

1. Add the TC-396-01 native and shared-envelope receipt tests with the one fixed JSON vector named in the contract. At the `UNUserNotificationCenter` callback boundary derive a private remote/local origin from `UNPushNotificationTrigger`, then reuse `IosDeliveredNotificationSnapshot` for bounded route/envelope, event, useful-content, and sanitized-content projection. Do not add a persistent owner, public MethodChannel API, or general notification-source abstraction.
2. Add the producer RED, then make only the private payload fixture FCM-shaped with `content-available:1` and a bounded synthetic `gcm.message_id`. Preserve the current encrypted rich route, exact APNs size/privacy checks, and direct development-APNs submission. Retain only a hash of the synthetic ID.
3. Version the private recovery result/host receipt and thread exact source, useful/sanitized content, stable-sample, background-handler, suppression, local-show, and complete-window NSE counts through `IosReceiverBootstrapHandoff.swift`, `AppDelegate.swift`, `ios_receiver_bootstrap.py`, the XCUITest driver, campaign validator, device criteria, fixtures, `run_ios_notification_payload_sims.dart`, and Sims registration tests. Write a redacted diagnostic before any throw; the content-addressed Sims artifact remains PASS-only.
4. Change the provider adapter's bounded retry mode into two explicitly bound submissions: setup/first-send returns the first typed receipt, the driver waits for its authorized NSE handoff and stable useful card, and one private second-send action consumes the first receipt and reuses identical payload bytes/collapse identity. It requires a second HTTP 200/APNs ID and a second device handoff. Do not add a general provider API or retry the whole phase.
5. Add the TC-396-04 Go and native REDs. Broaden only `projectStoredDirectPushMessageForPlatform` from exact `group_invite` to `{group_invite, new_message}`. In the existing recovery handoff/result seam, distinguish same-request/same-identity ordinary replacement from a different-request duplicate; preserve trusted title/body but force the former silent/passive, and retain incumbent sanitization for the latter. Preserve custody bounds, clone-on-write headers, reaction behavior, and Plan 395.
6. Make recovery cleanup unconditional on provider setup: after writing any available redacted diagnostic, independently attempt the existing UI/network, sender, provider/fixture, notification-state, and candidate-app cleanup owners according to acquired state. Add only the focused failure matrix in TC-396-06; no cleanup coordinator framework.
7. Extend the existing capability with the retry leg, not a new capability. One run serially performs the incumbent fast-path tap leg, the FCM-shaped source-qualified recovery leg, and the first-delivery-fenced retry leg from fresh cleanup boundaries while reusing one central signed product set.
8. Run the physical campaign once. If it exposes a source-backed plan-owned defect inside a named in-scope seam, retain the first failure, add the exact RED, apply only that allowed existing-seam repair, and rerun the single capability once. Any failure of that sole rerun blocks. Otherwise record the conditional branch as skipped; never rerun for unclassified noise.
9. Record exact composed evidence and limitations in the two UI-23 documents and index. Refresh Graphify once after the coherent app-owned change batch; do not refresh it between RED and GREEN edits.

## Risks And Blind Spots

- Apple collapse is a replacement/coalescing mechanism, not proof that two already-delivered requests can never make two sounds. The device oracle requires one final card but makes no sound-count claim.
- The first-delivery fence proves the second accepted request reached the device after the first useful card existed. The Go test independently proves production derives that header from durable direct custody. This is a composed production-projection plus direct-APNs/NSE proof, not end-to-end relay/FCM retry attribution.
- The synthetic `gcm.message_id` and `content-available` exercise the installed FlutterFire/background-handler boundary but do not claim transport through FCM. Missing background-handler evidence fails the physical claim rather than being inferred from final inventory.
- The current physical run cannot reproduce an actual live P2P delivery from Android. If the bounded APNs/local proof passes but a later manual live race is reproducible, retain its logs and plan that exact topology then; do not silently claim it here.
- iOS notification UI grouping is not a cardinality oracle. Native delivered inventory plus complete-window NSE/Flutter effect counts is authoritative for this card/source claim; XCUITest remains presentation/tap support only.
- A fresh dedicated install intentionally destroys prior `com.mknoon.app` data and permissions. The selected phone is test-only by user confirmation; cleanup removes the candidate app rather than pretending to restore arbitrary prior app state.
- Plan 395's distinct post-ACK group-invite custody remains deliverable by design. This direct-message plan must not reinterpret it as a duplicate key.

## Gate Cadence

- Always: representative receipt/classifier/producer/same-request REDs, focused Dart/Python/Swift/Go GREEN, exact direct/invite projection tests, the exact sidecar preservation owners, one registered physical-iPhone capability run, and scoped hygiene.
- TC-396-05 Dart/NSE production edits run only when the retained device inventory or complete-window effect log proves a Flutter-local duplicate/show. Without that evidence, the three named files run only as preservation owners and no additional recent-remote product edit is made.
- The production changes remain inside direct-message relay projection and the iOS direct-notification handoff, so `1to1` is the sole affected curated lane. `groups` is not run: the group-invite behavior is unchanged and its exact Go/native preservation owners are already selected.
- Do not run `core-host-all`, `feature-host-all`, or full `host-all`. The later Apple/release dependency wave and final release retain aggregate ownership.

## Acceptance Gates

~~~bash
# Snapshot and live matrix. Preserve unrelated user changes.
git status --short
flutter devices --machine
xcrun simctl list devices available

# Representative causal REDs before implementation. Use the exact new names.
GOTOOLCHAIN=go1.25.0 go -C go-mknoon test ./cmd/iospayloadproducer \
  -run '^TestTC396ProductionShapedBackgroundPayload$' -count=1
flutter test test/core/notifications/conversation_notification_content_kind_test.dart \
  --plain-name 'TC-396 shared direct local envelope vector matches Swift source classifier'
python3 -m unittest \
  scripts.test.ios_receiver_bootstrap_test.IosReceiverBootstrapTest.test_notification_recovery_retains_exact_source_inventory
flutter test test/integration/ios_notification_payload_campaign_support_test.dart \
  --plain-name 'TC-396 duplicate source inventory cannot pass as one card'
flutter test test/tool/sims/sims_manifest_test.dart \
  --plain-name 'TC-396 iOS payload artifact schema registers source and retry checks exactly once'
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . \
  -run '^TestRelayNotificationClosure_DirectMessageCustodyRetryCollapse$' -count=1)
xcodebuild test \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=iOS Simulator,id=674DFFF6-5F38-4235-93F6-AF7FBF86AE65' \
  CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO \
  -only-testing:RunnerTests/IosNotificationRecoveryTests/testTC396DeliveredInventoryClassifiesExactSources \
  -only-testing:RunnerTests/NotificationPreviewResolverTests/testTC396SameCollapseOrdinaryRetryPreservesTrustedContentPassively

# Focused host GREEN. These files are independent and Flutter uses bounded
# concurrency; no aggregate host gate is hidden here.
flutter test --concurrency=2 --reporter failures-only \
  test/core/notifications/conversation_notification_content_kind_test.dart \
  test/integration/ios_notification_payload_campaign_support_test.dart \
  test/integration/ios_notification_payload_xcui_contract_test.dart \
  test/integration/ios_notification_provider_adapter_contract_test.dart \
  test/integration/notification_tap_device_criteria_test.dart \
  scripts/test/ios_receiver_bootstrap_contract_test.dart \
  test/tool/sims/sims_manifest_test.dart
python3 -m unittest \
  scripts.test.ios_receiver_bootstrap_test \
  scripts.test.ios_notification_provider_adapter_test
GOTOOLCHAIN=go1.25.0 go -C go-mknoon test ./cmd/iospayloadproducer -count=1

# Exact local/provider dedupe preservation; these do not authorize an additional
# recent-remote product edit unless TC-396-03 retained a local card/show effect.
flutter test --concurrency=2 --reporter failures-only \
  test/core/notifications/recent_remote_notification_gate_test.dart \
  test/features/push/application/show_notification_use_case_test.dart \
  test/integration/chat_notification_dedupe_integration_test.dart

# Exact relay GREEN and Plan 395 preservation in one package invocation.
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . \
  -run '^(TestRelayNotificationClosure_DirectMessageCustodyRetryCollapse|TestRelayNotificationClosure_GroupInviteCustodyRetryCollapse)$' \
  -count=1)

# Resolve an available simulator again at execution, then pin both exact native
# selectors. The planning-time simulator is shown here.
xcodebuild test \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=iOS Simulator,id=674DFFF6-5F38-4235-93F6-AF7FBF86AE65' \
  CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO \
  -only-testing:RunnerTests/IosNotificationRecoveryTests/testTC396DeliveredInventoryClassifiesExactSources \
  -only-testing:RunnerTests/IosNotificationRecoveryTests/testTC396SameRequestDuplicateIsDistinctFromDifferentRequestDuplicate \
  -only-testing:RunnerTests/IosReceiverBootstrapHandoffTests/testTC396RecoveryResultPublishesBoundedSourceCounts \
  -only-testing:RunnerTests/NotificationPreviewResolverTests/testTC396SameCollapseOrdinaryRetryPreservesTrustedContentPassively \
  -only-testing:RunnerTests/IosNotificationRecoveryTests/testTC395ExactGroupInviteRetirementIsSurgicalAndIdempotent

# Sole affected curated lane after every focused owner is green.
./scripts/run_test_gates.sh 1to1

# One registered physical campaign only. Re-resolve the live matrix and pin a
# currently available dedicated iPhone whose provisioning/staging attestation
# contains the UDID. Planning-time selection: Saleh's iPhone, iOS 26.6.
SIMS_IOS_PHYSICAL_DEVICE_ID=00008150-001C3C6A3684401C \
  dart tool/sims/sims.dart major --only notifications.ios_payload_fast_path \
  --prepare-builds
~~~

### Evidence-Triggered Local Repair And Single Rerun

Run this block only when the retained TC-396-03 diagnostic proves a matching Flutter-local card or local-show effect. The first failed diagnostic remains retained. The first command captures the causal RED. After applying only the evidenced existing-seam repair, run the same test GREEN, the three preservation owners, the affected `1to1` lane, and then the one Sims capability once. Any failure of that sole rerun blocks.

~~~bash
# Before the repair: causal RED.
flutter test test/core/notifications/recent_remote_notification_gate_test.dart \
  --plain-name 'TC-396 captured iPhone provider-local key shape suppresses exactly once'

# After the repair: exact causal GREEN and affected preservation only.
flutter test test/core/notifications/recent_remote_notification_gate_test.dart \
  --plain-name 'TC-396 captured iPhone provider-local key shape suppresses exactly once'
flutter test --concurrency=2 --reporter failures-only \
  test/core/notifications/recent_remote_notification_gate_test.dart \
  test/features/push/application/show_notification_use_case_test.dart \
  test/integration/chat_notification_dedupe_integration_test.dart
# If that captured repair changes the Swift marker-key producer, also run:
xcodebuild test \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=iOS Simulator,id=674DFFF6-5F38-4235-93F6-AF7FBF86AE65' \
  CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO \
  -only-testing:RunnerTests/NotificationPreviewResolverTests/testGateMessageKeyMatchesSharedDedupeFixture

./scripts/run_test_gates.sh 1to1

SIMS_IOS_PHYSICAL_DEVICE_ID=00008150-001C3C6A3684401C \
  dart tool/sims/sims.dart major --only notifications.ios_payload_fast_path \
  --prepare-builds
~~~

### Always-Run Hygiene And Impact

~~~bash
# Scoped hygiene. Formatting unchanged files is harmless; no broad test suite is
# implied by listing all possible in-plan owners here.
test -z "$(gofmt -l go-relay-server/inbox.go \
  go-relay-server/ordinary_push_projection_test.go)"
test -z "$(gofmt -l go-mknoon/cmd/iospayloadproducer/main.go \
  go-mknoon/cmd/iospayloadproducer/main_test.go)"
python3 -m py_compile \
  integration_test/scripts/ios_receiver_bootstrap.py \
  integration_test/scripts/ios_notification_provider_adapter.py \
  scripts/test/ios_receiver_bootstrap_test.py \
  scripts/test/ios_notification_provider_adapter_test.py
dart format --output=none --set-exit-if-changed \
  integration_test/scripts/run_ios_notification_payload_sims.dart \
  integration_test/scripts/ios_notification_payload_xcui_driver.dart \
  integration_test/scripts/notification_ios_payload_campaign.dart \
  integration_test/support/ios_notification_payload_campaign.dart \
  test/core/notifications/conversation_notification_content_kind_test.dart \
  test/integration/ios_notification_payload_campaign_support_test.dart \
  test/integration/ios_notification_payload_xcui_contract_test.dart \
  test/integration/ios_notification_provider_adapter_contract_test.dart \
  test/integration/notification_tap_device_criteria_test.dart \
  test/tool/sims/sims_manifest_test.dart \
  tool/sims/device_criteria.dart
git diff --check

# App-owned impact and one refresh after implementation, not after docs only.
python3 graphify-arch/tdd_context.py affected \
  ios/NotificationService/NotificationService.swift \
  ios/NotificationService/IosNotificationRecovery.swift \
  ios/NotificationService/NotificationPreviewResolver.swift \
  ios/Runner/IosNotificationRecoveryCoordinator.swift \
  ios/Runner/IosReceiverBootstrapHandoff.swift \
  ios/Runner/AppDelegate.swift \
  go-mknoon/cmd/iospayloadproducer/main.go \
  go-relay-server/inbox.go \
  integration_test/scripts/run_ios_notification_payload_sims.dart \
  integration_test/scripts/notification_ios_payload_campaign.dart \
  integration_test/support/ios_notification_payload_campaign.dart \
  integration_test/scripts/ios_receiver_bootstrap.py \
  integration_test/scripts/ios_notification_provider_adapter.py \
  integration_test/scripts/ios_notification_payload_xcui_driver.dart \
  lib/core/notifications/recent_remote_notification_gate.dart \
  lib/features/push/application/show_notification_use_case.dart \
  tool/sims/critical_features.json \
  tool/sims/device_criteria.dart \
  --budget 600
./graphify-arch/refresh_arch_graph.sh --incremental
~~~

The conditional block is skipped on a no-local-duplicate result because that captured-shape test must not be invented. A non-local, source-backed in-scope correction discovered by the first physical run may also use the same single-rerun budget after its exact focused RED; it does not authorize another campaign or aggregate gate.

## Device And Relay Proof Profile

- Planning-time physical target: `00008150-001C3C6A3684401C` (`Saleh's iPhone`, iOS 26.6 / 23G71). Execution must rediscover the live matrix and pass one explicit current UDID; no “first iPhone” selection.
- Planning-time native-test simulator: `674DFFF6-5F38-4235-93F6-AF7FBF86AE65` (iPhone 17 Pro, iOS 26.5). Re-resolve and pin if unavailable.
- Android `21071FDF600CSC` and `emulator-5554` are available but deliberately unused. This is an iOS OS-boundary proof and needs no second peer.
- Build: one centrally prepared, signed `ios.device.production` app/XCTest bundle; child build count remains zero inside all three serial device legs.
- Provider: direct Apple development APNs submission with the real NSE, the existing disposable production-code relay/state fixture for setup and sender projection, dedicated receiver authorization, and automatic cleanup. The device leg does not claim relay-to-FCM emission; the Go projection and device mechanism form the composed proof. No production deployment or TestFlight.
- Destructive behavior: fresh install/reset, permission grant, notification clear, state clear, candidate app uninstall, and fixture cleanup are authorized because the user confirmed these are test phones. Arbitrary prior app data is not recoverable and is not claimed restored.
- Retry policy: individual provider submissions have exact typed receipts; the whole physical campaign is not automatically retried. Retain the first failure and permit at most one post-fix rerun after an exact RED proves a plan-owned correction inside a named in-scope seam. Any failure of that sole rerun blocks; unclassified noise never triggers a retry.

## Done Criteria

- [x] TC-396-01/02 source, envelope, FCM-shape, bounded-window, artifact-schema, and useful-content implementation and focused contract coverage are present. The complete post-timing host/native replay is waived by the user-directed closure rather than claimed green.
- [x] `TestRelayNotificationClosure_DirectMessageCustodyRetryCollapse` and the narrow direct-message custody-collapse production projection are present, with the Plan 395 group-invite behavior retained. The final exact Go replay is waived rather than newly claimed.
- [x] The same-request native handling and focused tests retain trusted content passively for the exact replacement while preserving different-request sanitization. The final native selector replay is waived rather than newly claimed.
- [x] `notifications.ios_payload_fast_path` remains the sole capability, and its row plus `--artifact-schema` surface the added source/background/retry/useful-content/cleanup checks.
- [x] **User-accepted waiver, not a PASS claim:** no content-addressed physical PASS produced the required source-count tuple. The sole rerun timed out with zero NSE markers after APNs accepted its first request. The later one-card manual iPhone 11 result is retained only as diagnostic evidence.
- [x] **User-accepted waiver, not a retry-proof claim:** no registered run reached the fenced second submission, so the two-acceptance/two-handoff retry tuple remains absent.
- [x] No speculative recent-remote/Dart dedupe edit was made. Because TC-396-03 produced no valid source/effect receipt, the conditional branch was not evaluated as `local=0`; that distinction is retained.
- [x] Bounded redacted failure diagnostics were retained and raw temporary syslog/result bundles were deleted. Network restoration and candidate removal were attested. The sole rerun's missing final relay/sender cleanup receipt and retained `rollback_spawn_pending` lifecycle are accepted as an evidence limitation, not represented as a clean cleanup PASS.
- [x] The bounded cleanup owners and structural failure contracts are implemented without a generalized rollback layer. A complete final pre-provider/post-seed/mid-retry gate replay is waived rather than newly claimed.
- [x] Plan 395 preservation owners remain present; their final exact replay is waived rather than newly claimed.
- [x] No per-plan family or full-host aggregate was run. The remaining complete focused/native/`1to1` replay is waived by the closure decision.
- [x] This plan records the exact composed-proof boundary, failed physical evidence, manual diagnostic limitation, and no-sound/no-live-P2P/no-full-Apple limitations. Separate UI-23/index edits are waived by the user's instruction to update this document and close.

Original technical closure required a fully green first physical run or one green source-backed rerun. That technical condition was not met. By explicit user direction on 2026-08-22, it is superseded for this document's status only: Plan 396 is administratively complete, with the absent content-addressed source/retry PASS and incomplete rerun-cleanup attestation preserved as limitations. This closure must not be cited as automated physical acceptance.

## Handoff

Closed by explicit user acceptance. Do not run another Plan 396 campaign or add recovery infrastructure under this document. Any future request for automated source-count and retry-count closure must be handled as an explicitly authorized follow-up rather than retroactively upgrading this record.

Independent `$tdd-review` completed on 2026-08-21 with `plan-fixes-required`; its exact causal-boundary, classifier, retry, cleanup, registration, and command corrections are incorporated above. No second review is required unless the plan changes materially again.

## Execution Progress

Completed by user-directed administrative acceptance on 2026-08-22.

- Deterministic implementation: TC-396-01/02/04/06 production and contract surfaces are present in the working tree. TC-396-05 made no speculative recent-remote/Dart product change.
- Registered attempt 1: `capture-1787397116874127-76166` on iPhone 13 stopped before provider setup. Its recovery receipt records candidate removal and relay-fixture cleanup.
- Sole registered rerun: `capture-1787398527524646-90356` on iPhone 13 reached first-request APNs acceptance at `2026-08-22T11:36:48.580Z`, then timed out after 155 seconds with all NSE marker counts equal to zero. It produced no recovery/retry phase, source-count tuple, retry-count tuple, or content-addressed PASS artifact.
- Cleanup evidence: network restoration, candidate uninstall, and private temporary-file deletion were observed. The retained provider lifecycle remains `rollback_spawn_pending`, so final relay/sender cleanup is not claimed as fully attested.
- Manual diagnostic: after removing the obsolete `com.mknoon.sims.groupmedia269` installation, the remaining `com.mknoon.app` on iPhone 11 registered APNs/FCM and its relay route. A later Pixel-to-iPhone message produced one visible notification; live logs recorded `PUSH_NSE_ENVELOPE_STAGED success=true`, `PUSH_NSE_DECRYPT_OK`, and `PUSH_NSE_CONTENT_HANDOFF authorized=true`. This was manual FCM-path diagnosis, not the plan's direct-APNs campaign proof.
- Closure decision: the user instructed, “assume the plan is finished, update the document.” No third campaign was run. Missing aggregate gate replay, physical source/retry PASS, final cleanup attestation, and separate UI-23/index updates are accepted limitations and are not silently promoted to passing evidence.
