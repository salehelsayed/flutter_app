# Session 34 Plan: Standalone CLI-Backed transport_e2e Fixes

## Final verdict
`implementation-ready`

Reviewer outcome: sufficient with one scope adjustment. Earlier review overstated `A1` and `A4`; current repo evidence shows the shared Flutter send path already preserves honest transport truth. The remaining safe scope is to fix stale acceptance logic in `integration_test/transport_e2e_test.dart`, the reconnect no-address retry gap only if reproduced, and the `B8` / `G6` signal wait race in the standalone orchestrator.

## Final plan

### real scope
- Fix only the reviewed standalone CLI-backed failures: `A1`, `A4`, `A2`, `A5`, `D4`, `A7`, `A8`, `A8b`, `C3`, `B8`, `G6`.
- Allowed edit targets: `integration_test/transport_e2e_test.dart`, `integration_test/scripts/run_transport_e2e.dart`, `go-mknoon/node/node.go`, `go-mknoon/node/send_message_recovery_test.go`.
- Conditional edit targets only if node-level evidence proves insufficient: `go-mknoon/cmd/testpeer/commands.go`, `go-mknoon/cmd/testpeer/commands_test.go`.
- Do not change `lib/features/conversation/application/send_chat_message_use_case.dart`, `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`, or `lib/core/services/p2p_service_impl.dart` unless fresh reproduction proves the current evidence wrong.

### closure bar
- The standalone CLI-backed full orchestrator run passes the named failures above on one real simulator/device run.
- `transport_e2e_test.dart` no longer hard-codes relay-only expectations where the current code intentionally records actual stream truth or explicit inbox fallback truth.
- Reconnect sends recover from the reviewed no-address gap without inventing a second send architecture in the CLI harness.
- `B8` and `G6` wait for the actual app-written signal contents instead of racing on file existence alone.
- Existing direct transport-truth unit tests and the named transport gate remain green.

### source of truth
- Current code and tests beat older prose if they disagree.
- Outgoing transport truth: `lib/features/conversation/application/send_chat_message_use_case.dart` and `test/features/conversation/application/send_chat_message_use_case_test.dart`.
- Incoming transport truth: `lib/core/services/p2p_service_impl.dart`, `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`, and `test/core/services/p2p_service_impl_test.dart`.
- CLI reconnect/send recovery truth: `go-mknoon/node/node.go` and `go-mknoon/node/send_message_recovery_test.go`.
- Target failure surfaces: `integration_test/transport_e2e_test.dart` and `integration_test/scripts/run_transport_e2e.dart`.
- Gate source of truth: `scripts/run_test_gates.sh`; use `Test-Flight-Improv/test-gate-definitions.md` for classification and explanation only.
- Reliability/transport semantics contract: `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`.

### session classification
- `implementation-ready`

### exact problem statement
- `A1`, `A4`, `A2`, `A5`, `D4`, and `A7` still contain relay-only or relay-biased assertions/comments in `transport_e2e_test.dart`, but the shared send/receive code now preserves honest transport truth from the actual stream and explicit inbox fallback.
- `A8`, `A8b`, and `C3` fail after reconnect because the CLI harness sends via `SendMessage` directly; the current Go self-heal retry path covers some retryable stream-open failures, but not the reviewed reconnect no-address case.
- `B8` and `G6` use existence-only file polling between Flutter and the orchestrator even though `run_transport_e2e.dart` already has a content-based `_waitForAppFile(...)` helper.
- User-visible behavior that must improve: the standalone CLI-backed transport E2E run must reflect current transport truth and stop flaking on reconnect/signal timing.
- Must stay unchanged: 1:1 delivery semantics, inbox fallback behavior, dedup rules, and named gate membership.

### files and repos to inspect next
- `integration_test/transport_e2e_test.dart`
- `integration_test/scripts/run_transport_e2e.dart`
- `go-mknoon/node/node.go`
- `go-mknoon/node/send_message_recovery_test.go`
- `go-mknoon/cmd/testpeer/commands.go`
- `go-mknoon/cmd/testpeer/commands_test.go`
- Evidence-only reference file: `lib/features/conversation/application/send_chat_message_use_case.dart`
- Evidence-only reference file: `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
- Evidence-only reference file: `lib/core/services/p2p_service_impl.dart`
- Evidence-only reference file: `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- Evidence-only reference file: `Test-Flight-Improv/test-gate-definitions.md`
- Evidence-only reference file: `scripts/run_test_gates.sh`

### existing tests covering this area
- Honest outgoing transport truth is already covered by `test/features/conversation/application/send_chat_message_use_case_test.dart`.
- Honest incoming transport truth and additive bridge send transport are already covered by `test/core/services/p2p_service_impl_test.dart`.
- Go send self-heal on retryable stream-open failures is already covered by `go-mknoon/node/send_message_recovery_test.go`.
- The real standalone CLI-backed surface is already exercised by `integration_test/transport_e2e_test.dart` plus `integration_test/scripts/run_transport_e2e.dart`.
- Missing today: a Go regression for the reconnect-time no-address failure shape.
- Missing today only if `commands.go` must change: command-level CLI send coverage in `go-mknoon/cmd/testpeer/commands_test.go`.
- The named transport gate does not prove these CLI-backed scenarios when no fixture/orchestrator is present.

### regression/tests to add first
- First add a focused Go regression in `go-mknoon/node/send_message_recovery_test.go` for the exact reconnect no-address stream-open error reproduced from the standalone CLI-backed run. This is the narrowest deterministic proof for `A8` / `A8b` / `C3`.
- If node-level recovery alone is insufficient and `commands.go` must change, add a companion `go-mknoon/cmd/testpeer/commands_test.go` regression for the touched `send_v1` / `send_v2` path before changing the command implementation.
- No new separate Flutter unit test is required for `A1`, `A4`, `A2`, `A5`, `D4`, or `A7`; the stale logic lives in the integration test itself, so the direct proof is the repaired standalone orchestrator run plus the existing transport-truth unit tests above.

### step-by-step implementation plan
1. Reproduce the reviewed failures once with the standalone orchestrator command on a real simulator/device and capture the exact reconnect `A8` / `C3` send error text plus the `B8` / `G6` signal-wait symptom. If the reconnect failure is not a no-address-style stream-open error, stop and rescope instead of forcing the Go retryability fix.
2. In `integration_test/transport_e2e_test.dart`, narrow the fix to the named scenarios only. `A1` / `A4` should accept honest outgoing transports `direct`, `relay`, or `inbox` while still requiring delivered status. `A2` / `A5` / `A7` should accept honest live-stream incoming transports `direct` or `relay`. `D4` must keep the dedup contract at `count == 1`, but accept the surviving live transport as `direct` or `relay` rather than `relay` only. Update stale labels/comments that still say "via relay" when the assertion is transport-truth based.
3. Add the focused Go regression in `go-mknoon/node/send_message_recovery_test.go` for the reproduced reconnect no-address failure.
4. Update `go-mknoon/node/node.go` only at the retryability seam so the reproduced no-address stream-open error participates in the existing self-heal + reopen logic. Do not add a new discover/dial/send flow, broad catch-all retries, or inbox fallback inside the CLI.
5. Re-run the standalone orchestrator command. If `A8`, `A8b`, and `C3` now pass, stop there for the reconnect fix. If they still fail for the same no-address reason, then and only then add the smallest command-level wrapper in `go-mknoon/cmd/testpeer/commands.go` plus `commands_test.go`; otherwise leave `commands.go` unchanged.
6. In `integration_test/scripts/run_transport_e2e.dart`, replace the `B8` and `G6` existence-only waits with content-based waits using `_waitForAppFile(...)` or an equivalent helper that reads the app-written signal file. Keep the same signal names, same timeout budget, and same cleanup behavior unless the reproduction proves a specific timeout needs a narrow increase.
7. Run the exact direct tests, Go package tests, named gate, and standalone CLI-backed command listed below. If only non-target, pre-existing failures remain, document them and stop; do not widen the session.

### risks and edge cases
- Direct vs relay truth can differ run-to-run depending on discovered addresses and reachability; the fix must accept the honest live transport set rather than hard-code one path.
- `D4` must still prove dedup, not just transport acceptance; count and message-ID behavior stay the real assertion.
- Over-broad retryability matching in `node.go` could mask non-retryable failures; keep the predicate tied to the reproduced no-address failure shape.
- Signal waits must not silently accept stale files from earlier phases; preserve existing cleanup and require non-empty content.
- Android `run-as` timing and iOS direct-file timing differ; the wait helper must stay cross-platform.

### exact tests and gates to run
- `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart`
- `flutter test test/core/services/p2p_service_impl_test.dart`
- `cd go-mknoon && go test ./node`
- `cd go-mknoon && go test ./cmd/testpeer`
- `FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport`
- Required direct CLI-backed validation because the named gate does not supply the CLI fixture/orchestrator path: `dart run integration_test/scripts/run_transport_e2e.dart -d <device-id>`
- Optional equivalent auto-detect form when a fixed device id is not required: `dart run integration_test/scripts/run_transport_e2e.dart -p ios`
- Optional equivalent auto-detect form when a fixed device id is not required: `dart run integration_test/scripts/run_transport_e2e.dart -p android`

### known-failure interpretation
- A plain `flutter test integration_test/transport_e2e_test.dart -d <device-id>` run that prints `[TEST] No CLI peer — running self-contained scenarios only` does not validate `A1`, `A4`, `A2`, `A5`, `D4`, `A7`, `A8`, `A8b`, `C3`, `B8`, or `G6`.
- Treat the reviewed named failures above as the in-scope red set for this session.
- If the standalone orchestrator run fails only in unrelated scenarios outside the named set, record them but do not reopen scope.
- If the transport gate fails because of unrelated device boot/attach issues, that blocks validation but does not change implementation scope.

### done criteria
- `A1`, `A4`, `A2`, `A5`, `D4`, and `A7` pass in the standalone CLI-backed run without relay-only assumptions.
- `A8`, `A8b`, and `C3` pass after reconnect via the existing Go self-heal path or the smallest proven CLI wrapper, with no new transport architecture.
- `B8` and `G6` pass via content-based signal synchronization.
- `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart`, `flutter test test/core/services/p2p_service_impl_test.dart`, `cd go-mknoon && go test ./node`, `cd go-mknoon && go test ./cmd/testpeer`, `FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport`, and `dart run integration_test/scripts/run_transport_e2e.dart -d <device-id>` all pass, or any remaining failures are explicitly pre-existing and out of scope.
- No changes land in the shared Flutter send/receive production code unless reproduction proves the current evidence wrong.

### scope guard
- Non-goals: transport API redesign, gate automation changes, broader harness cleanup, new scenario additions, docs-wide reclassification, or changing 1:1 product semantics.
- Overengineering to avoid: reimplementing Flutter's discover/dial/send race inside the CLI, adding generic command retries for every error, or widening signal-helper refactors past `B8` and `G6`.
- Must not change: delivery status semantics, inbox fallback meaning, dedup policy, or named gate membership.

### accepted differences / intentionally out of scope
- `transport_e2e_test.dart` remains a large orchestrated integration test; this session only corrects the reviewed scenarios rather than refactoring the whole file.
- The named transport gate remains as-is; this session only records the exact standalone CLI-backed command required for closure.
- `send_chat_message_use_case.dart`, `handle_incoming_chat_message_use_case.dart`, and `p2p_service_impl.dart` are treated as current-truth references, not planned edit targets, unless reproduction disproves that assumption.

### dependency impact
- This session is a prerequisite for treating the reviewed standalone CLI-backed transport matrix as trustworthy again.
- Follow-up closure or audit work should wait until the direct orchestrator command is green; do not mark the area closed based on the named transport gate alone.
- If reproduction disproves the no-address reconnect premise, skip any CLI retry implementation and reopen planning with the new evidence instead of pushing forward with this plan.

## Reviewer pass
- Verdict: sufficient with adjustments.
- Scope adjustment applied: `A1` and `A4` are not evidence for changing shared Flutter send semantics; only the integration acceptance set and wording are stale against current transport truth.
- Missing validation contract patched: the plan now names the exact standalone CLI-backed command because `./scripts/run_test_gates.sh transport` can run `transport_e2e_test.dart` without a CLI fixture.

## Arbiter pass
- Structural blockers: none.
- Incremental detail: the exact no-address substring should come from the first reproduced failing run before the Go predicate is changed.
- Accepted difference: do not automate the standalone orchestrator into the named gate in this session.

## Structural blockers remaining
- None.

## Incremental details intentionally deferred
- Updating non-target scenario comments/logs outside `A1`, `A4`, `A2`, `A5`, `D4`, `A7`, `A8`, `A8b`, `C3`, `B8`, and `G6`.
- Any `commands.go` change if the node-level retryability fix alone clears the reconnect failures.
- Any script/doc change to make the named transport gate invoke the orchestrator automatically.

## Accepted differences intentionally left unchanged
- The CLI harness will still use its own direct send commands; this session only hardens the narrow reconnect/no-address seam instead of cloning the Flutter app's send stack.
- The standalone CLI-backed command remains a required manual/direct validation step in addition to the named gate.
- Existing 1:1 transport semantics and legacy `reuse` compatibility behavior remain unchanged.

## Exact docs/files used as evidence
- `integration_test/transport_e2e_test.dart`
- `integration_test/scripts/run_transport_e2e.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
- `lib/core/services/p2p_service_impl.dart`
- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/core/services/p2p_service_impl_test.dart`
- `go-mknoon/node/node.go`
- `go-mknoon/node/send_message_recovery_test.go`
- `go-mknoon/cmd/testpeer/commands.go`
- `go-mknoon/cmd/testpeer/commands_test.go`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

## Why the plan is safe or unsafe to implement now
- Safe to implement now because the plan is evidence-backed, bounded to the reviewed failures, names exact stop conditions if the reconnect premise is false, and separates authoritative transport-truth code from the stale test/harness surfaces that actually need correction.
