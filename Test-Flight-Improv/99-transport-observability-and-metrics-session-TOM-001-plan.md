# TOM-001 - Dart Diagnostics Privacy and Settings Readout Proof Plan

Status: accepted

## Planning Progress

- 2026-05-29 21:08:30 CEST - Arbiter completed. Files inspected since last update: final reviewer verdict and corrected plan. Decision/blocker: no structural blockers remain; classify simulator/baseline/card-test choices as accepted differences or conditional execution details. Next action: hand off execution-ready plan.
- 2026-05-29 21:08:00 CEST - Arbiter started. Files inspected since last update: final reviewer verdict, closure bar, exact tests/gates, accepted differences. Decision/blocker: classify the prior reviewer finding and remaining conditional gates. Next action: write arbiter pass and final status.
- 2026-05-29 21:07:10 CEST - Final Reviewer completed. Files inspected since last update: corrected plan sections and TOM-001 coverage ledger. Decision/blocker: sufficient as-is after inbox-success branch proof was added; no missing direct tests, named gates, scope guard, or dirty-worktree handling remain. Next action: run arbiter classification and finalize execution-ready status.
- 2026-05-29 21:04:25 CEST - Reviewer completed. Files inspected since last update: full draft plan, current `send_chat_message_use_case.dart` event branches. Decision/blocker: structural coverage gap found because inbox-fallback success has a separate `CHAT_MSG_SEND_SUCCESS` payload with `textPreview`; patch plan to require direct success, inbox success, and failed-send privacy proof. Next action: apply one plan patch, then run final reviewer/arbiter.
- 2026-05-29 21:03:50 CEST - Reviewer started. Files inspected since last update: full draft plan and TOM-001 checklist coverage. Decision/blocker: reviewing sufficiency of privacy branch coverage, settings readout proof, gates, and simulator treatment. Next action: record review result and patch if structural.

## Execution Progress

- 2026-05-29 21:03:04 CEST - Local fallback QA completed. Files inspected or touched: `lib/features/conversation/application/send_chat_message_use_case.dart`, `test/features/conversation/application/send_chat_message_use_case_test.dart`, `test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart`, `test/core/debug/transport_metrics_privacy_test.dart`, `test/core/utils/flow_event_emitter_test.dart`. Command result: all direct tests passed; `./scripts/run_test_gates.sh 1to1` passed. Decision/blocker: TOM-001 closure bar met; no TOM-002+ scope added. Next action: mark session accepted in the breakdown and continue TOM-002.
- 2026-05-29 20:59:33 CEST - Fresh narrower child contract re-extracted locally. Files inspected or touched: TOM-001 plan, execution skill contract, `git status --short`, `rg textPreview`, diffs for `lib/features/conversation/application/send_chat_message_use_case.dart` and `test/features/conversation/application/send_chat_message_use_case_test.dart`, current settings diagnostics card and `TransportMetrics`. Command running: none. Decision/blocker: no blocker; per user instruction this fresh child will execute and QA locally without spawning additional agents, preserving pre-existing dirty worktree changes. Next action: complete Executor implementation for preview removal and focused settings card proof.
- 2026-05-29 21:12:45 CEST - First execution child closed after no-progress. Files inspected or touched: TOM-001 plan progress, `git status --short`, `rg textPreview` over TOM-001 owner files. Command result: prior child only spawned worker `019e7518-692a-74a3-9179-d96bd095c41f` and did not land TOM-001 code/test changes or a final execution verdict under bounded wait. Decision/blocker: not a product blocker; use the allowed fresh narrower execution child for the same TOM-001 owner files/tests before any fallback. Next action: spawn narrower execution child.
- 2026-05-29 20:56:09 CEST - Contract extraction started. Files inspected: TOM-001 plan, session breakdown, `git status --short`, touched-file diff summary. Command running: none. Decision/blocker: no blocker; dirty worktree confirmed and scope limited to TOM-001. Next action: extract exact contract and spawn Executor.
- 2026-05-29 20:56:09 CEST - Contract extracted. Files inspected: `Test-Flight-Improv/99-transport-observability-and-metrics-session-TOM-001-plan.md`, `Test-Flight-Improv/99-transport-observability-and-metrics-session-breakdown.md`, `lib/features/conversation/application/send_chat_message_use_case.dart`, settings diagnostics card paths, existing dirty diffs. Command running: none. Decision/blocker: execute only send-flow preview removal, direct send privacy regression, focused settings card refresh/readout proof, required direct tests, `./scripts/run_test_gates.sh 1to1`, and `git diff --check`; baseline only if settings/app wiring changes beyond the focused card/test. Next action: spawn isolated Executor.
- 2026-05-29 20:56:37 CEST - Executor spawned/running. Files inspected or touched: plan progress section only. Command running: spawned worker agent `019e7518-692a-74a3-9179-d96bd095c41f` executing TOM-001. Decision/blocker: no blocker. Next action: wait for Executor result, then inspect landed diffs and spawn QA.
- 2026-05-29 20:56:53 CEST - Executor contract extracted locally. Files inspected: `git status --short`, this TOM-001 plan, orientation-only session breakdown, execution skill contract. Command running: none. Decision/blocker: no blocker; dirty worktree confirmed and scope remains TOM-001 only. Next action: inspect owner-file diffs before touching any already-modified file.
- 2026-05-29 20:57:53 CEST - Owner inspection completed. Files inspected: `git diff -- lib/features/conversation/application/send_chat_message_use_case.dart`, `git diff -- lib/core/utils/flow_event_emitter.dart`, `lib/features/conversation/application/send_chat_message_use_case.dart`, `test/features/conversation/application/send_chat_message_use_case_test.dart`, `lib/features/settings/presentation/widgets/settings_transport_diagnostics_card.dart`, `lib/core/debug/transport_metrics.dart`. Command running: none. Decision/blocker: preserve pre-existing transport-metrics and sanitizer edits; do not touch `flow_event_emitter.dart` unless later evidence requires it. Next action: add send-path privacy regression before production cleanup.

## Execution Verdict

Verdict: accepted.

Landed TOM-001 evidence:
- `lib/features/conversation/application/send_chat_message_use_case.dart` no longer emits `textPreview` in `CHAT_MSG_SEND_START`, `CHAT_MSG_SEND_SUCCESS`, or `CHAT_MSG_SEND_FAILED` details.
- `test/features/conversation/application/send_chat_message_use_case_test.dart` captures direct success, inbox-fallback success, failed send, and start events and asserts no send event exposes `textPreview` or distinctive message fragments.
- `test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart` proves the rendered settings card refreshes aggregate transport mix, fallback rungs, latency, LAN state, and baseline report from a mutated `TransportMetrics` instance.

Tests/gates:
- `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart` passed.
- `flutter test test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart` passed after rerun; first attempt hit a native-assets build race from parallel Flutter startup.
- `flutter test test/core/debug/transport_metrics_privacy_test.dart` passed.
- `flutter test test/core/utils/flow_event_emitter_test.dart` passed.
- `./scripts/run_test_gates.sh 1to1` passed.

Residuals: none for TOM-001. LAN production wiring, relay metrics, group evidence, and final source-doc closure remain owned by TOM-002 through TOM-005.

## real scope

TOM-001 changes only the Dart diagnostics/privacy surface for 1:1 send flow events and the settings diagnostics readout proof.

In scope:
- Remove message-derived `textPreview` data from transport-adjacent send flow events in `lib/features/conversation/application/send_chat_message_use_case.dart`.
- Keep send-path behavior, persistence, transport race ordering, offline inbox fallback, failed-send handling, and `TransportMetrics` counts unchanged.
- Add a direct send-path privacy regression that fails on the current `textPreview` payloads and proves send flow events do not expose the message body or preview-derived fields.
- Add a focused widget or screen smoke proof that `SettingsTransportDiagnosticsCard` visibly refreshes from a mutated `TransportMetrics` instance and displays aggregate transport mix, fallback rungs, latency, LAN state, and baseline report.

Out of scope:
- LAN production snapshot wiring, relay Prometheus metrics, group diagnostics, final acceptance/source-doc closure, analytics export, telemetry policy, and transport protocol changes.

## closure bar

This session is closed only when every TOM-001 contract item has direct proof:

| Contract item | Planned proof |
| --- | --- |
| Remove or replace message-derived `textPreview` from transport-adjacent send flow events | A send-use-case flow-event regression captures direct success, inbox-fallback success, and failed send events, including their start events, and asserts no event details contain a `textPreview` key or the distinctive message text/preview fragment. |
| Add a direct send-path privacy regression | The regression exercises the real `sendChatMessage` use-case harness in `test/features/conversation/application/send_chat_message_use_case_test.dart`; it must fail before callsite cleanup and pass after. |
| Prove aggregate transport mix in settings | A focused card/screen widget test mutates `TransportMetrics`, taps the refresh affordance, and asserts the visible `Transport mix (N=...)` line and bucket labels/values are present. |
| Prove rung counts in settings | The same focused readout test asserts the `Fallback rungs` section and known rung counts from the mutated metrics. |
| Prove latency in settings | The same focused readout test asserts the `Latency (median / p95)` section and known per-transport latency text. |
| Prove LAN line in settings | The same focused readout test asserts the `LAN` section and the baseline report line for active/inactive discovery with peer count. |
| Prove baseline report after metrics change and refresh | The focused readout test starts from an initial snapshot, mutates the metrics object, taps `settings-transport-debug-refresh` or `settings-transport-debug-refresh-button`, and asserts the `settings-transport-debug-report` text reflects the new aggregate baseline. |

Reviewer closure bar:
- The reviewer must confirm the regression is against actual send flow events, not only the sanitizer.
- The reviewer must confirm the settings proof reads rendered UI, not only `TransportMetrics` getters.
- The reviewer must confirm no TOM-002+ scope or transport-delivery behavior was added.

Arbiter closure bar:
- If the reviewer finds no structural blocker, stop after recording the pass.
- If the reviewer finds a missing regression/gate/scope guard, patch the plan once and run one final reviewer/arbiter pass.

## source of truth

- Active contract: TOM-001 entry in `Test-Flight-Improv/99-transport-observability-and-metrics-session-breakdown.md`.
- Supporting problem statement: `Test-Flight-Improv/99-transport-observability-and-metrics.md`.
- Current code/tests beat stale prose.
- Gate source of truth: `Test-Flight-Improv/test-gate-definitions.md`; `scripts/run_test_gates.sh` wins for exact gate behavior if docs and script disagree.
- This plan owns only `Test-Flight-Improv/99-transport-observability-and-metrics-session-TOM-001-plan.md`; final source-doc closure wording is deferred to TOM-005.

## session classification

`implementation-ready`

Host-side direct tests and the `1to1` named gate are sufficient for TOM-001 because the planned implementation changes diagnostic payload fields and a settings card proof only. It must not alter real transport ordering or multi-device delivery semantics.

## exact problem statement

Current send-path diagnostics emit message-derived `textPreview` in `CHAT_MSG_SEND_START`, direct/reuse/race/relay `CHAT_MSG_SEND_SUCCESS`, inbox-fallback `CHAT_MSG_SEND_SUCCESS`, and `CHAT_MSG_SEND_FAILED` flow events. That leaks message-derived content into a transport-adjacent diagnostics channel that is supposed to remain aggregate-only and identifier/content-free.

The settings diagnostics card already reads `TransportMetrics`, but there is no focused widget/screen proof that the visible card refreshes after metrics change and shows the aggregate transport mix, fallback rungs, latency, LAN state, and baseline report expected by the source doc.

User-visible behavior that must improve: diagnostics in TestFlight/debug review are privacy-safe and still useful for aggregate transport reliability triage.

Behavior that must stay unchanged: message send results, failed-send persistence, offline inbox fallback, transport metric bucket/rung/latency accounting, settings screen availability with and without `TransportMetrics`, and existing sanitizer behavior unless a narrow defense-in-depth change is intentionally made.

## files and repos to inspect next

Production:
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/core/utils/flow_event_emitter.dart` only if a narrow sanitizer defense is needed after callsite cleanup
- `lib/features/settings/presentation/widgets/settings_transport_diagnostics_card.dart`
- `lib/features/settings/presentation/screens/settings_wired.dart` only if the card cannot be tested directly or wiring changes are required
- `lib/core/debug/transport_metrics.dart` for expected bucket/rung/latency/LAN report vocabulary

Tests:
- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/core/debug/transport_metrics_privacy_test.dart`
- `test/core/utils/flow_event_emitter_test.dart` only if `flow_event_emitter.dart` changes
- New or existing focused settings widget/screen test, preferably `test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart`
- Existing settings screen tests only if `settings_wired.dart` is touched

Docs/gates:
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

## existing tests covering this area

- `test/core/debug/transport_metrics_test.dart` covers canonical transport buckets, fallback rung counts, latency stats, LAN snapshot, reset, and baseline report text.
- `test/core/debug/transport_metrics_privacy_test.dart` covers receive-arm flow-event privacy and external aggregate getter/baseline privacy, but not the full send-path flow events that currently contain `textPreview`.
- `test/core/utils/flow_event_emitter_test.dart` covers sanitizer redaction for secrets, peer IDs, multiaddrs, and diagnostic secret fixtures.
- `test/features/conversation/application/send_chat_message_use_case_test.dart` already has a flow-event capture helper and a timing-event test, making it the narrowest actual send-path regression location.
- Settings tests exist under `test/features/settings/...`, but no focused `SettingsTransportDiagnosticsCard` widget test was found.

## regression/tests to add first

Add the tests before production cleanup:

1. In `test/features/conversation/application/send_chat_message_use_case_test.dart`, add a test named along the lines of `send flow events omit message-derived previews`.
   - Use the existing `captureFlowEvents` helper and real `sendChatMessage` wrapper.
   - Exercise a direct/reuse/race/relay successful send with a distinctive message body that would currently be truncated into `textPreview`.
   - Exercise an inbox-fallback successful send by configuring the fake service so active send fails and `storeInInbox` succeeds.
   - Exercise a failed send path by configuring the fake service so active send and inbox fallback fail.
   - Assert all captured `CHAT_MSG_SEND_*` events have no `textPreview` detail key.
   - Assert serialized event payloads do not contain the distinctive message body or expected preview fragment.
   - This should fail against current code because start/success/failed events include `textPreview`.

2. Add `test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart` or an equivalent focused settings-wired smoke.
   - Pump the card with a `TransportMetrics` instance.
   - Assert the initial snapshot is rendered.
   - Mutate metrics with known direct/relay/wifi/inbox/unknown counts, fallback rungs, direct/relay latency samples, and LAN availability.
   - Tap `settings-transport-debug-refresh` or `settings-transport-debug-refresh-button`.
   - Assert visible labels and values for transport mix, fallback rungs, latency, LAN, and `settings-transport-debug-report` update to the new baseline.

3. If the implementation touches `flow_event_emitter.dart`, add a focused `test/core/utils/flow_event_emitter_test.dart` assertion that the new sanitizer rule redacts only the intended message-preview key(s). Do not use sanitizer redaction as the only proof for send events; the send events should not contain `textPreview` at all.

## step-by-step implementation plan

1. Record dirty-worktree evidence with `git status --short`. For each file that will be touched and is already modified, inspect `git diff -- <file>` before editing and preserve unrelated user/other-agent changes.
2. Add the send-path privacy regression in `send_chat_message_use_case_test.dart` and run the targeted `flutter test` command to confirm it fails for the expected `textPreview` leak.
3. Add the focused settings diagnostics readout/refresh widget test. It may pass on current code; that is acceptable because it is a missing proof rather than necessarily a product bug.
4. Remove `textPreview` from send flow-event detail maps in `send_chat_message_use_case.dart`.
5. Remove now-unused `textPreview` plumbing from `_completeSuccessfulSend` and callers if no production use remains. Do not remove message text used for persistence or user-visible conversation content.
6. Prefer callsite removal over sanitizer masking. Touch `flow_event_emitter.dart` only if a narrow defense-in-depth redaction is still necessary, and then add the matching sanitizer test.
7. Run `dart format` on touched Dart files.
8. Run the exact direct tests listed below.
9. Run `./scripts/run_test_gates.sh 1to1` because `send_chat_message_use_case.dart` changes.
10. Run `./scripts/run_test_gates.sh baseline` only if implementation touches `settings_wired.dart`, `main.dart`, app routing/wiring, or another baseline-gate surface beyond the focused card/test.
11. Do not update TOM-002+ plans, LAN docs, relay docs, group docs, or final acceptance wording in this session.

Stop early and re-plan if removing `textPreview` appears to require changing send result semantics, transport race timing, persistence, inbox fallback, encryption payloads, or public `TransportMetrics` APIs.

## risks and edge cases

- The send-use-case helper currently passes `textPreview` into `_completeSuccessfulSend`; removing that argument must not change the persisted message, logged outgoing content, delivery status, or timing event.
- Failed sends must still record the failed rung and must not increment a delivered transport bucket.
- Inbox fallback success has its own `CHAT_MSG_SEND_SUCCESS` details map and must be covered by the send-path privacy regression, not only code review.
- `CHAT_MSG_SEND_TIMING` already avoids `textPreview`; keep it aggregate-only and avoid adding message IDs beyond the existing short internal ID.
- Settings card snapshots are intentionally refreshed by button/tap; the test should mutate metrics before refresh and assert the rendered text changes only after refresh.
- The current worktree is dirty; failures may be caused by pre-existing edits in touched files.

## exact tests and gates to run

Direct tests after adding the regressions and implementing:

```bash
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart
flutter test test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart
flutter test test/core/debug/transport_metrics_privacy_test.dart
```

Conditional direct test:

```bash
flutter test test/core/utils/flow_event_emitter_test.dart
```

Run the conditional direct test only if `lib/core/utils/flow_event_emitter.dart` changes.

Required named gate when `send_chat_message_use_case.dart` changes:

```bash
./scripts/run_test_gates.sh 1to1
```

Conditional named gate if settings/app wiring changes beyond the focused card or a standalone widget test:

```bash
./scripts/run_test_gates.sh baseline
```

Final hygiene:

```bash
git diff --check
```

No `$run-flutter-reliability-sims` gate is required for the default TOM-001 path because the planned code change removes diagnostic payload fields and adds a widget proof; it must not alter actual 1:1 delivery, device state, relay behavior, or libp2p transport behavior. If implementation changes real delivery/transport behavior, pause and re-plan with the simulator closure rule.

## known-failure interpretation

- The worktree was dirty before this plan was created, including modified send, settings, flow-event, app wiring, and transport-metrics files plus untracked TOM artifacts. Do not revert or normalize those changes.
- If a direct test fails before TOM-001 changes are applied, capture the failure as pre-existing and do not claim TOM-001 closure until the touched regression passes in the final state.
- If a direct test or required named gate fails only after TOM-001 edits, treat it as session-owned until evidence proves it is unrelated.
- `Test-Flight-Improv/test-gate-definitions.md` records a known 2026-05-28 completeness-check classification failure for three unrelated files. TOM-001 does not require `completeness-check` unless execution adds or reclassifies broad test inventory files.
- Historical green gate notes are supporting context only; they do not excuse new failures in the required direct tests or `1to1` gate.

## done criteria

- Send flow-event regression exists and passes, proving no `textPreview` key and no message body/preview fragment in captured send events.
- `send_chat_message_use_case.dart` no longer emits `textPreview` in transport-adjacent send flow events.
- Direct/reuse/race/relay success, inbox-fallback success, and failed send paths remain behaviorally unchanged except for diagnostics payload contents.
- Focused settings card/screen test exists and passes, proving rendered aggregate mix, rung counts, latency, LAN, and baseline report refresh after metrics mutation.
- `test/core/debug/transport_metrics_privacy_test.dart` still passes.
- `test/core/utils/flow_event_emitter_test.dart` passes if the sanitizer is touched.
- `./scripts/run_test_gates.sh 1to1` passes or any failure is documented as pre-existing with evidence and TOM-001 remains not fully closed.
- `./scripts/run_test_gates.sh baseline` passes if required by touched settings/app wiring.
- `git diff --check` passes.
- No TOM-002+ implementation, relay, group, LAN production snapshot, or final acceptance docs are changed by this session.

## reviewer pass

Initial reviewer verdict: sufficient with one structural adjustment.

- Missing files, tests, regressions, or gates: the draft's send-path privacy proof did not explicitly require the inbox-fallback success branch, even though current code has a separate inbox-success `CHAT_MSG_SEND_SUCCESS` details map with `textPreview`.
- Stale or incorrect assumptions: none after treating current code as source of truth.
- Overengineering: none; the plan remains callsite cleanup plus focused tests.
- Decomposition: sufficient for TOM-001 once inbox-success branch coverage is added.
- Minimum needed to make sufficient: require the send-path regression to cover direct success, inbox-fallback success, and failed send events.
- Checklist parity: complete after the inbox-success patch above.

Final reviewer verdict after patch: sufficient as-is.

- Missing files, tests, regressions, or gates: none.
- Stale or incorrect assumptions: none found; current code remains the source of truth for branch coverage.
- Overengineering: none.
- Decomposition: narrow enough for one executor session.
- Minimum needed to make sufficient: already applied.
- Checklist parity: every TOM-001 contract item maps to a direct proof, conditional gate, accepted difference, or explicit non-goal.

## arbiter pass

Final arbiter verdict: `execution-ready`.

Structural blockers:
- None remaining.
- The initial missing inbox-fallback success privacy proof was structural because current code has a separate inbox-success event payload. The plan now requires direct success, inbox-fallback success, and failed-send coverage, so the blocker is resolved.

Incremental details:
- Exact test names can be chosen during implementation as long as the assertions and files match this plan.
- `flow_event_emitter_test.dart` remains conditional on touching `flow_event_emitter.dart`.

Accepted differences:
- A focused card widget test is sufficient unless production `SettingsWired` or app wiring changes.
- `./scripts/run_test_gates.sh baseline` is conditional for the no-wiring-change path.
- `$run-flutter-reliability-sims` is not required unless implementation changes real delivery, device-state, relay, or libp2p transport behavior.

## scope guard

Do not:
- Change P2P send ordering, timeouts, retry policy, relay probing, inbox fallback, encryption, persistence, or delivery status.
- Change `TransportMetrics` bucket/rung canonicalization unless a direct existing test proves the current API is already broken for TOM-001.
- Add analytics, exporters, server metrics, dashboards, or opt-in telemetry.
- Wire LAN availability production snapshots; that belongs to TOM-002.
- Add group diagnostics; that belongs to TOM-004.
- Update final source-doc closure wording; that belongs to TOM-005.
- Broaden frozen named gates or classify new tests in `test-gate-definitions.md` unless execution adds a new integration/cross-feature file that the repo's gate policy requires.

Overengineering signals:
- Adding a new diagnostics abstraction for two callsite payload removals.
- Replacing the settings card architecture instead of testing the existing refresh/readout behavior.
- Masking `textPreview` only in the sanitizer while leaving message-derived keys in actual send events.

## accepted differences / intentionally out of scope

- A focused `SettingsTransportDiagnosticsCard` widget test is acceptable instead of a full `SettingsWired` smoke if production screen wiring is not changed; the TOM-001 contract allows either card or settings-wired proof.
- `./scripts/run_test_gates.sh baseline` is intentionally conditional. It is required only if settings/app wiring changes beyond the card or focused widget test.
- `$run-flutter-reliability-sims` is intentionally not part of the default closure because TOM-001 must not change real multi-device delivery behavior. If implementation crosses that boundary, the plan is no longer sufficient.
- Source doc final closure, LAN production state, relay Prometheus tests, and group-message diagnostics remain for TOM-002 through TOM-005.

## dependency impact

- TOM-002 depends on the settings diagnostics terminology and card API staying stable; if TOM-001 changes the card API, TOM-002 planning must refresh against this plan's final implementation.
- TOM-005 depends on TOM-001 for privacy/readout evidence and should cite exact direct tests/gate evidence after execution.
- If TOM-001 cannot close the send privacy regression, downstream acceptance must not claim aggregate-only diagnostics are complete.

## dirty-worktree handling

- Treat all pre-existing modified/untracked files shown by `git status --short` as user/other-agent work.
- Before editing an already-modified likely owner file, inspect its current diff and preserve unrelated changes.
- Do not run `git checkout`, `git reset`, or any destructive cleanup.
- Keep this session's documentation/code/test delta attributable to TOM-001 only.

## reviewer and arbiter stop rule

The implementation executor should use this plan without widening scope. The QA reviewer should check the mandatory TOM-001 proofs, direct tests, named gates, and dirty-worktree attribution. The arbiter should classify any QA findings as structural blockers, incremental details, or accepted differences; if there is no structural blocker, stop rather than expanding into TOM-002+ work.

## exact docs/files used as evidence

- `Test-Flight-Improv/99-transport-observability-and-metrics-session-breakdown.md`
- `Test-Flight-Improv/99-transport-observability-and-metrics.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/core/utils/flow_event_emitter.dart`
- `lib/core/debug/transport_metrics.dart`
- `lib/features/settings/presentation/widgets/settings_transport_diagnostics_card.dart`
- `lib/features/settings/presentation/screens/settings_wired.dart`
- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/core/debug/transport_metrics_privacy_test.dart`
- `test/core/utils/flow_event_emitter_test.dart`
- `test/features/settings/presentation/screens/settings_wired_test.dart`
