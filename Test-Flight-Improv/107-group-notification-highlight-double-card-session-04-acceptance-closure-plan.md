Status: accepted_with_explicit_follow_up

# 107 Group Notification Highlight Double Card - Session 04 Plan

Session id: `04-acceptance-closure`

## Planning Progress

- `2026-06-05 16:09 CEST` - Role `Arbiter completed`; files inspected since last update: source doc, breakdown ledger, accepted session 01/02/03 plans, notification matrix, group matrix, in-scope gap matrix, group reliability closure reference, current test map, gate definitions; decision/blocker: no structural blocker remains because sessions 01-03 are accepted and the only remaining work is acceptance/doc closure; next action: run final direct acceptance bundle, update source/stable docs, and persist final program verdict.
- `2026-06-05 16:09 CEST` - Role `Reviewer completed`; files inspected since last update: direct widget/application/notification tests and stable docs; decision/blocker: plan is sufficient if it maps `TC-107-R01`, `TC-107-R02`, and `TC-107-R08` explicitly and avoids overclaiming provider APNs/TestFlight proof; next action: mark execution-ready.
- `2026-06-05 16:08 CEST` - Role `Planner completed`; files inspected since last update: source acceptance requirements and stable matrix rows `GM-004`, `GM-011`, `SC-010`, `GMN-101`, `GMN-104`; decision/blocker: final closure can use existing and newly added direct evidence plus the already-green `groups` gate; next action: reviewer pass.
- `2026-06-05 16:08 CEST` - Role `Evidence Collector completed`; files inspected since last update: source doc and stable docs; decision/blocker: session 01 closed notification focus cue, session 02 proved `logicalDeliveryId`, session 03 closed row convergence and PGC-007 preservation; next action: draft session 04 closure plan.

## Real Scope

Validate the full Report 107 closure state and update existing source/stable docs. This session should not add new product behavior unless acceptance uncovers a real regression.

## Closure Bar

- `TC-107-R01`: one proven logical incoming group delivery with divergent row ids converges to one persisted/user-visible row across live/replay/drain paths.
- `TC-107-R02`: notification-anchor focus uses a single-row cue rather than a second card-like highlight container.
- `TC-107-R08`: PGC-007 same group/sender/text/timestamp rows with different non-empty stable ids and no shared logical identity remain distinct.
- Reaction inspection, quote/media enrichment, timeline ordering, and normal no-highlight entry remain green.
- Stable docs record what is closed, what is residual-only, and which tests/gates define maintenance safety.
- Breakdown records final program verdict using the allowed vocabulary.

## Source Of Truth

- Source doc: `Test-Flight-Improv/107-group-notification-highlight-double-card.md`
- Breakdown: `Test-Flight-Improv/107-group-notification-highlight-double-card-session-breakdown.md`
- Accepted session plans: session 01, 02, and 03 plan artifacts.
- Stable docs: `Test-Flight-Improv/52-notification-journey-test-matrix.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- Current code/tests beat stale prose.

## Session Classification

`acceptance-only`

## Exact Problem Statement

The two double-card causes are now implemented in separate accepted sessions, but the source/stable docs still read as open or older evidence. Final closure must validate the combined path and make the docs durable without overclaiming external provider/device proof.

## Files And Repos To Inspect Next

- `Test-Flight-Improv/107-group-notification-highlight-double-card.md`
- `Test-Flight-Improv/52-notification-journey-test-matrix.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/107-group-notification-highlight-double-card-session-breakdown.md`

## Existing Tests Covering This Area

- Session 01 widget/wired tests cover the notification focus cue, one-target-only highlighting, dark/light backgrounds, reaction-bearing rows, quote/media variants, and normal entry.
- Session 02 tests cover durable `logicalDeliveryId` generation/propagation/persistence and PGC-007 preservation.
- Session 03 tests cover logical delivery convergence, listener live/replay convergence, signed offline replay convergence, reaction/widget coherence, and `groups`.

## Regression Tests To Add Or Tighten First

No new tests are planned for session 04 unless final validation uncovers a gap. The acceptance bundle reruns the direct tests that map to `TC-107-R01`, `TC-107-R02`, and `TC-107-R08`.

## Step-By-Step Implementation Plan

1. Run final direct acceptance tests for focus cue, reaction inspection, logical-delivery convergence, PGC-007 preservation, and notification dedupe.
2. Update the source doc with final closure evidence and residual/provider-device notes.
3. Update stable notification and group matrices with Report 107 evidence.
4. Update the group reliability closure reference with the new logical-delivery convergence contract and reopen rules.
5. Update the breakdown ledger and final program verdict.
6. Run `git diff --check` after docs.

## Risks And Edge Cases

- Overclaiming provider APNs/TestFlight notification-open proof; keep as residual-only unless a device-backed command runs.
- Reopening content-only dedupe; docs must state PGC-007 remains protected.
- Treating session plans as the only closure record; stable docs must be updated.

## Exact Tests And Gates To Run

Final direct acceptance:

```bash
flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart --name "logical delivery convergence|PGC-007"
flutter test test/features/groups/application/group_message_listener_test.dart --name "logical delivery convergence|replayed duplicate group message does not create a second local notification|GP-025"
flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name "logical delivery convergence|GI-024|GI-034"
flutter test test/features/groups/presentation/group_conversation_screen_test.dart --name "notification focus cue stays single-row|group rows keep a single glass shell|row shell stays single"
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --name "highlights the targeted message context|notification-anchor entry keeps group reaction inspection"
flutter test test/integration/group_notification_dedupe_integration_test.dart
```

Already run in session 03 and accepted as final broad group gate unless code changes again:

```bash
./scripts/run_test_gates.sh groups
```

Post-doc sanity:

```bash
git diff --check
```

Do not run `baseline` unless route/app-root/notification startup wiring changes. Do not run `completeness-check` unless new test files or gate classifications are added in session 04.

## Known-Failure Interpretation

No known red result is accepted for session 04 closure. If a final direct acceptance test fails, stop and record `still_open` unless the failure is proven unrelated to Report 107 and already documented.

## Done Criteria

- Final direct acceptance tests pass.
- Source doc and stable docs are updated.
- Breakdown ledger shows sessions 01-04 accepted and final program verdict is `closed` or an explicitly justified allowed residual status.
- Final response lists exact commands/results and whether docs were closed.

## Scope Guard

Do not add product behavior unless final validation proves a real gap. Do not create new stable docs. Do not widen named gates. Do not claim provider APNs/TestFlight proof without running provider/device evidence.

## Reviewer Pass

The acceptance plan is sufficient because it maps each required regression to direct tests and names the stable docs that own closure. It deliberately keeps provider/device notification proof residual-only because no route/startup/provider path changed in this rollout.

## Arbiter Pass

Structural blockers: none.

Incremental details: exact stable doc phrasing can be adjusted to match local table style.

Accepted differences: final provider APNs/TestFlight notification-open confidence remains residual-only; repo-owned direct/widget/gate evidence closes the report.

## Execution Progress

- `2026-06-05 17:24 CEST` - Phase `manual APNs-open follow-up green`; files inspected/touched: `lib/main.dart`, `lib/core/notifications/remote_notification_identity.dart`, `lib/core/notifications/app_root_notification_open.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/push/application/push_decrypt_preview.dart`, `ios/NotificationService/NotificationPreviewResolver.swift`, focused notification/group/push tests, this plan artifact, source doc, and the breakdown ledger; command/result: `flutter test test/core/notifications/recent_remote_notification_gate_test.dart test/core/notifications/app_root_notification_open_test.dart test/features/push/application/push_decrypt_preview_test.dart` -> `All tests passed!` (`+25`); command/result: `flutter test test/features/groups/application/send_group_message_use_case_test.dart --name "text group message does not send plaintext preview fields|PL-014 media metadata omits group keys plaintext and private keys from diagnostics and relay replay|includes media in inbox payload"` -> `All tests passed!` (`+3`); command/result: `flutter test test/features/groups/application/group_message_listener_test.dart --name "suppresses local notification when a recent remote push already announced the same group message|replayed duplicate group message does not create a second local notification|GIRD-006 local group replay suppresses same remote-announced id but not a distinct id"` -> `All tests passed!` (`+3`); command/result: `flutter test test/integration/group_notification_dedupe_integration_test.dart test/features/push/application/background_message_handler_test.dart --name "background push announcement suppresses later local group notification for the same message|records a recent remote notification target even when FCM already carries a visible notification|GIRD-006 does not mark remote announcement when group fallback display fails|suppresses group background fallback when display eligibility denies it"` -> `All tests passed!` (`+4`); decision/blocker: duplicate local notification after APNs-open is closed at the deterministic remote-open/recent-announcement gate, group notification title parity is closed at encrypted preview/NSE seams, and same-active-group notification taps no longer stack another route; next action: run iOS NSE and named gates.
- `2026-06-05 17:24 CEST` - Phase `manual follow-up device and named gates green`; files inspected/touched: iOS notification service resolver and route/open notification wiring; command/result: `xcodebuild build-for-testing -quiet -workspace ios/Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,id=5BA69F1C-B112-47BE-B1FF-8C1003728C8F' -only-testing:RunnerTests/NotificationPreviewResolverTests -parallel-testing-enabled NO` -> exit `0` with only existing project warnings; command/result: `xcodebuild test-without-building -quiet -xctestrun /Users/I560101/Library/Developer/Xcode/DerivedData/Runner-fdlavkflmiabpyeuegpuipvnubvr/Build/Products/Runner_iphonesimulator26.5-arm64.xctestrun -destination 'platform=iOS Simulator,id=5BA69F1C-B112-47BE-B1FF-8C1003728C8F' -only-testing:RunnerTests/NotificationPreviewResolverTests -parallel-testing-enabled NO` -> exit `0` on the existing iPhone 17 simulator; command/result: `./scripts/run_test_gates.sh groups` -> `All tests passed!` (`+321`); command/result: `./scripts/run_test_gates.sh baseline` -> host baseline tests passed (`+100`) but command exited `1` at device integration selection because multiple devices were connected and no `FLUTTER_DEVICE_ID` was specified; command/result: `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh baseline` -> all stages passed: host tests (`+100`), `integration_test/loading_states_smoke_test.dart` (`+7`), and `integration_test/posts_phase1_fake_test.dart` (`+1`) on the existing iPhone 17 simulator; command/result: `xcrun simctl list devices available | rg "5BA69F1C|iPhone 17 \\("` -> existing iPhone 17 `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` booted and clone `CC346536-8FD3-4D4A-9D54-92CFB610D0C1` shutdown; command/result: `git diff --check` -> exit `0`; decision/blocker: no remaining deterministic acceptance blocker for the manual regression; next action: update source/stable docs and final response.
- `2026-06-05 16:36 CEST` - Phase `post-doc sanity green`; files inspected/touched: all Report 107 source/stable/session docs touched by session 04; command/result: `git diff --check` -> exit `0` with no output; decision/blocker: no formatting/whitespace blocker remains; next action: final breakdown sanity and response.
- `2026-06-05 16:34 CEST` - Phase `session 04 docs closed`; files inspected/touched: `Test-Flight-Improv/107-group-notification-highlight-double-card.md`, `Test-Flight-Improv/52-notification-journey-test-matrix.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, this plan artifact, and the breakdown ledger; command/result: no additional test command in this doc-write step; decision/blocker: repo-owned Report 107 closure evidence is now durable in source/stable docs, with provider APNs/TestFlight or simulator notification-open visual proof recorded as explicit follow-up; next action: run post-doc `git diff --check`, then update the breakdown final program verdict.
- `2026-06-05 16:27 CEST` - Phase `final direct acceptance bundle green`; files inspected/touched: direct receive/listener/drain/widget/wired/integration tests and this plan artifact; command/result: `flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart --name "logical delivery convergence|PGC-007"` -> `All tests passed!` (`+3`); command/result: `flutter test test/features/groups/application/group_message_listener_test.dart --name "logical delivery convergence|replayed duplicate group message does not create a second local notification|GP-025"` -> `All tests passed!` (`+3`); command/result: `flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name "logical delivery convergence|GI-024|GI-034"` -> `All tests passed!` (`+3`); command/result: `flutter test test/features/groups/presentation/group_conversation_screen_test.dart --name "notification focus cue stays single-row|group rows keep a single glass shell|row shell stays single"` -> `All tests passed!` (`+3`); command/result: `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --name "highlights the targeted message context|notification-anchor entry keeps group reaction inspection"` -> `All tests passed!` (`+2`); command/result: `flutter test test/integration/group_notification_dedupe_integration_test.dart` -> `All tests passed!` (`+1`); decision/blocker: no repo-owned acceptance blocker; `TC-107-R01`, `TC-107-R02`, and `TC-107-R08` are directly covered; next action: update source/stable docs.
- `2026-06-05 16:09 CEST` - Phase `execution-ready acceptance plan written`; files inspected/touched: session 04 plan artifact, source doc, breakdown, stable notification/group docs, current test map, gate definitions; command/result: no session-04 tests run yet; decision/blocker: no blocker; next action: run final direct acceptance bundle.

## Final Execution Verdict

- Verdict: `accepted_with_explicit_follow_up`
- Repo-owned closure: `TC-107-R01`, `TC-107-R02`, and `TC-107-R08` are accepted. Shared non-empty `logicalDeliveryId` converges divergent row-id logical deliveries under validated group/sender; notification-anchor focus no longer adds a second card-like wrapper; PGC-007 same-content/timestamp stable-id sends without shared logical identity remain distinct.
- Manual follow-up closure: the APNs-open duplicate local notification and repeated notification-tap route stacking regressions reported after initial acceptance are accepted at the deterministic app/NSE seams. Remote group opens mark the target as recently announced before drain, same-active-group notification taps do not push another group route, encrypted group preview now supplies the group title like 1:1 preview parity, and relay-visible payloads still omit plaintext preview fields.
- Stable docs closed: source doc, notification matrix rows `GMN-101` and `GMN-104`, group matrix rows `GM-004`, `GM-011`, and `SC-010`, in-scope gap rows `GM-011` and `SC-010`, and the group reliability closure reference now record Report 107 evidence and reopen rules.
- Explicit follow-up: a fresh provider-backed APNs/TestFlight manual visual pass after this follow-up is still complementary evidence, not a deterministic repo blocker. Route/app-root/notification startup wiring changed in the manual follow-up, so `baseline` was required and passed when pinned to the existing iPhone 17 simulator.
- Conditional gates: `completeness-check` was not required in session 04 because no new test files or gate classifications were added. The required `groups` gate passed again for the manual follow-up with `+321`, and the required `baseline` gate passed when pinned to the existing iPhone 17 simulator.
