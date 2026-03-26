# Session 7 Plan: One Onboarding Golden Path

## 1. Scope
- Add one cross-feature onboarding golden path only.
- Use the new-user identity creation branch as the primary path. Existing recovery/restore coverage already exists, so do not add a second branch unless the single path becomes nondeterministic.
- The regression should prove one concise flow end-to-end: fresh identity creation, accepted contact request, and first successful 1:1 message.
- Keep the work to tests plus the smallest local test scaffolding needed for determinism. Do not change app code.

## 2. Files To Inspect Next
- `lib/main.dart`
- `lib/features/identity/application/generate_identity_use_case.dart`
- `lib/features/identity/application/restore_identity_use_case.dart`
- `lib/features/identity/application/startup_decision.dart`
- `lib/features/identity/presentation/screens/identity_choice_wired.dart`
- `lib/features/identity/presentation/startup_router.dart`
- `lib/features/contact_request/application/handle_incoming_message_use_case.dart`
- `lib/features/contact_request/application/accept_and_reciprocate_use_case.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `test/features/identity/presentation/screens/identity_choice_wired_test.dart`
- `test/features/identity/presentation/screens/startup_router_test.dart`
- `test/features/identity/application/generate_identity_use_case_test.dart`
- `test/features/identity/application/restore_identity_use_case_test.dart`
- `test/features/contact_request/application/accept_and_reciprocate_use_case_test.dart`
- `test/features/contact_request/integration/contact_request_flow_test.dart`
- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/features/conversation/integration/two_user_message_exchange_test.dart`
- `test/features/identity/domain/repositories/fake_identity_repository.dart`
- `test/core/bridge/fake_bridge.dart`
- `test/shared/fakes/fake_p2p_network.dart`
- `test/shared/fakes/in_memory_contact_request_repository.dart`
- `test/shared/fakes/test_user.dart`
- `test/integration/onboarding_golden_path_test.dart`

## 3. Existing Tests Covering This Area
- `test/features/identity/presentation/screens/startup_router_recovery_test.dart` covers startup recovery and the restore path.
- `test/features/identity/presentation/screens/startup_router_test.dart` covers new-user versus returning-user startup routing decisions without requiring a full widget bootstrap.
- `test/features/identity/presentation/screens/identity_choice_wired_test.dart` covers the create-identity handoff and progress-route sequencing.
- `test/features/identity/application/generate_identity_use_case_test.dart` covers identity generation and persistence.
- `test/features/identity/application/restore_identity_use_case_test.dart` covers mnemonic-based recovery.
- `test/features/contact_request/application/accept_and_reciprocate_use_case_test.dart` covers accept + reciprocal send behavior.
- `test/features/contact_request/integration/contact_request_flow_test.dart` covers incoming request parsing, persistence, acceptance, and reciprocal key-update behavior.
- `test/features/conversation/application/send_chat_message_use_case_test.dart` covers the shared 1:1 send contract.
- `test/features/conversation/integration/two_user_message_exchange_test.dart` covers a full two-user 1:1 exchange over the fake network.
- `test/features/conversation/integration/offline_inbox_roundtrip_test.dart` covers offline inbox fallback.

## 4. Regressions/Tests To Add First
- Start from the existing `test/integration/onboarding_golden_path_test.dart` regression and tighten or extend it only if the current assertions do not fully prove the Session 7 contract.
- The required contract is one path only:
  - create the identity
  - receive and accept a contact request
  - send the first 1:1 message
- `test/integration/onboarding_golden_path_test.dart` is already classified in `Test-Flight-Improv/test-gate-definitions.md`, `Test-Flight-Improv/test-gates-reference.md`, and `scripts/run_test_gates.sh`; only update the gate inventory if Session 7 changes the integration/orchestration test file inventory.
- Execution may be validation-only if `test/integration/onboarding_golden_path_test.dart` already proves the full Session 7 contract without changes.
- Do not add a second onboarding variant for restore/login parity unless the single create path proves impossible to keep deterministic.

## 5. Step-by-Step Implementation Plan
1. Build the onboarding regression around existing fake repositories, fake bridge, and fake P2P helpers rather than creating a new test harness.
2. Inspect `test/integration/onboarding_golden_path_test.dart` first against the Session 7 contract and treat no-code-change verification as sufficient if the current test already covers the required flow.
3. If the current test is missing coverage, drive identity creation through the existing generation flow, not a custom shortcut, so the test exercises the real onboarding contract.
4. Inject an incoming contact request, accept it through `acceptAndReciprocateContactRequest`, and assert the contact is persisted.
5. Send the first 1:1 message with the shared `sendChatMessage` path and assert the message is persisted/sent successfully.
6. Keep the scenario to one peer pair and one message; do not expand into multiple contacts, multiple payload types, or retry matrices.
7. Treat `test/integration/onboarding_golden_path_test.dart` as the primary execution target first; only create a second file if the existing file cannot stay readable after the minimum missing assertions are added.
8. If Session 7 changes the set of integration/orchestration test files, update the gate inventory and run `./scripts/run_test_gates.sh completeness-check` before widening verification.
9. Run the onboarding golden path test first, then the direct feature suites, then the required gates.

## 6. Risks And Edge Cases
- The reciprocal send in `acceptAndReciprocateContactRequest` is fire-and-forget, so the test must wait for the side effect in a bounded way without turning into a broad timing test.
- Identity creation and first-message send both depend on the same shared bridge/P2P fakes; if the test becomes flaky, keep the contract at the use-case layer rather than pulling in more UI.
- The first message path is the real risk surface here; a passing contact-request flow alone would not prove the onboarding contract.
- The restore branch is already covered elsewhere, so adding it here would be overengineering unless the create path is unstable.
- A new `test/integration/*.dart` file must be explicitly classified; otherwise completeness-check will fail even if the Dart test passes.

## 7. Exact Tests To Run After Implementation
- `flutter test test/integration/onboarding_golden_path_test.dart`
- `flutter test test/features/identity`
- `flutter test test/features/contact_request`
- `flutter test test/features/conversation`
- `./scripts/run_test_gates.sh 1to1`
- `./scripts/run_test_gates.sh baseline`
- `./scripts/run_test_gates.sh completeness-check` if Session 7 changes the integration/orchestration test inventory or gate classification docs
- If multiple Flutter targets are attached, set `FLUTTER_DEVICE_ID=<device-id>` for integration-backed gate runs.
- When running `./scripts/run_test_gates.sh baseline`, treat the rerun result as authoritative. Record any failing baseline item from current evidence; do not rely on the older Session 1 failure note.

## 8. Subsystem Gates And Whether Startup/Transport Tests Are Needed
- Required subsystem gate: `1:1 Reliability Gate`.
- Required baseline gate: `Baseline Gate`.
- Startup / transport tests are not needed.
- Reason: this session only stitches together existing identity, contact-request, and 1:1 conversation use cases. It does not modify `lib/features/p2p/`, `lib/main.dart`, startup bootstrap, resume handling, relay fallback, or any device-backed transport path.
- Baseline gate handling rule for execution: the gate must still be run, and the rerun result is the source of truth for Session 7. Any failing baseline item on the rerun is current session evidence and must be recorded directly.

## 9. Done Criteria
- One permanent onboarding golden path regression exists and stays narrowly scoped.
- The test proves fresh identity creation, accepted contact request, and first successful 1:1 message in one flow.
- The direct feature suites for identity, contact request, and conversation run cleanly for the touched surface.
- The `1:1 Reliability Gate` and `Baseline Gate` are run for this session.
- If Session 7 changes the integration/orchestration file inventory, the gate inventory is updated and completeness-check remains green.
- Any Baseline Gate failure on the current rerun is recorded explicitly from current evidence; only the current rerun result controls whether the session is blocked.
- Validation-only execution is acceptable if the existing onboarding regression already satisfies the roadmap contract and the required tests and gates are rerun.
- No app code is changed and no startup/transport gate is introduced.

## 10. Explicit Assumptions For Review
- I am assuming the create-identity branch is the right primary onboarding path for this session; restore/recovery remains covered by existing tests and is intentionally out of scope here.
- I am assuming the existing `test/integration/onboarding_golden_path_test.dart` file is the right home for Session 7 and should stay in the optional/manual direct-suite bucket instead of widening the frozen named gates.
- I am assuming the 1:1 gate is required because the golden path exercises `sendChatMessage`, which is the shared durable send contract the gate protects.
- I am assuming no startup/transport gate is required because the session does not touch bootstrap, relay fallback, or resume behavior.
- I am assuming the Session 7 baseline rerun is the only authoritative source for baseline status, including any failure or pass outcome.
- If the new test proves too large for a single file, the next adjustment should be to tighten the scenario, not to split it into a broader matrix.
