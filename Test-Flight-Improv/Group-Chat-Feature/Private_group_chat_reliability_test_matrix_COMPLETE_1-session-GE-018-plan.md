# GE-018 Property Test Random Envelope Tampering Plan

Status: accepted/closed

## Planning Progress

- 2026-05-13 18:52 CEST - Closure completed. Files inspected/touched since last update: `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_decryption_failure_test.go`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, source matrix, session breakdown, and test inventory. Decision/blocker: GE-018 is covered with deterministic Go validator/live-path and Dart durable-replay tamper proofs; the stale GEK003 proof in the same Dart replay suite was repaired to match the current GE-005 fail-closed rotation contract. Next action: continue with GE-019, the next unresolved P0 row.
- 2026-05-13 18:38 CEST - Arbiter completed. Files inspected since last update: local Reviewer findings and full plan. Decision/blocker: no structural blocker remains; GE-018 is execution-ready as a deterministic host Go validator/live-render plus Dart durable-replay tamper proof, with runtime fixes conditional on red invariant evidence. Next action: execute this plan.
- 2026-05-13 18:36 CEST - Reviewer completed. Files inspected since last update: full plan, source row, breakdown row 176, existing Go GK/ER tamper tests, Dart replay signature/drain tests, and gate commands. Decision/blocker: sufficient with one adjustment: the implementation must include both a broad pure Go mutation matrix and at least one side-effect-aware replay/drain proof; no simulator/device proof is required unless runtime bridge/device behavior changes. Next action: Arbiter classify review.
- 2026-05-13 18:34 CEST - Local planning fallback started. Files inspected since last update: spawned planner status and partial plan file. Decision/blocker: spawned planner `019e2227-4335-72b3-988a-6763613cf01c` produced a draft but did not complete reviewer/arbiter before shutdown; no blocker in the draft. Next action: complete Reviewer and Arbiter roles locally without changing scope.
- 2026-05-13 18:28 CEST - Planner completed. Files inspected since last update: Evidence Collector findings, GE-017 accepted plan/test shape, v3 pubsub validator/decryption tests, Dart offline replay signature/drain tests. Decision/blocker: drafted a narrow implementation-ready GE-018 plan using deterministic host proofs in Go validator/render paths plus Dart durable replay; production/Go runtime changes stay conditional on a concrete failing mutation. Next action: Reviewer sufficiency pass.
- 2026-05-13 18:28 CEST - Planner started. Files inspected since last update: `go-mknoon/node/pubsub.go`, `go-mknoon/internal/group_envelope.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_decryption_failure_test.go`, `lib/features/groups/application/group_offline_replay_envelope.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `scripts/run_test_gates.sh`, `Test-Flight-Improv/test-gate-definitions.md`. Decision/blocker: no external blocker; exact GE-018 proof is missing but the repo has enough validator/replay seams to close it without simulator proof. Next action: draft mandatory plan sections.

## Evidence Collector Findings

- At planning intake, source matrix row GE-018 was P0/Open: `Property test random envelope tampering never renders plaintext`; model is a fuzzer that mutates envelope fields; steps are generate valid envelopes, mutate fields, run validator/replay; expected result is only exactly valid authorized envelopes render and all others reject with safe diagnostics. This is superseded by the Execution Evidence and Final Verdict below.
- At planning intake, breakdown row 176 and detailed ledger row 2064 classified GE-018 as `needs_code_and_tests` / `implementation-ready`, with this plan path as the row-owned artifact. The detailed ledger listed likely surfaces across Dart fake group tests, real group app seams, `go-mknoon/node/pubsub.go`, and `go-mknoon/node/group_inbox.go`. This is superseded by the accepted closure below.
- GE-017 closed with one deterministic host property proof in `test/features/groups/integration/group_messaging_smoke_test.dart` and no runtime code changes. GE-018 should copy the deterministic seeded style and failure-context discipline, but not the same fake pubsub surface by default because `FakeGroupPubSubNetwork` carries already-decoded maps and does not exercise v3 envelope signature/validator behavior.
- Go owns the v3 group envelope validator and live render/no-render boundary. `go-mknoon/node/pubsub.go` checks `internal.IsGroupEnvelope`, parses `internal.GroupEnvelope`, verifies group id, transport binding, membership/device authorization, writer role, key epoch/signature, then `handleGroupSubscription` decrypts and emits `group_message:received` or `group_reaction:received`.
- Existing Go tests cover many one-off tamper cases: `GK006` ciphertext tamper, `GK008` wrong key, `GK012` missing signature, `GK013` missing encrypted fields, `GK015` group mismatch, `GK025` type tamper safely producing payload-parse failure rather than rendered plaintext, `GK026` sender id tamper, `GK027` device/transport binding tamper, `GK033` reaction device/epoch validation, and `ER001` safe diagnostics. They do not provide a single GE-018 seeded fuzzer across envelope fields with an oracle that every mutated envelope avoids plaintext render and diagnostics stay safe.
- Dart owns durable offline replay envelope validation. `lib/features/groups/application/group_offline_replay_envelope.dart` signs replay metadata over ciphertext/nonce/plaintext hashes, sender/device binding, group id, payload type, message id, key epoch, and recipient-set hash, then verifies before `group.decrypt`. `lib/features/groups/application/drain_group_offline_inbox_use_case.dart` rejects unsigned relay payloads and signature failures before messages, reactions, cursors, or receipts mutate.
- Existing Dart replay tests cover invalid signatures, unsigned replay forms, missing key placeholders, unknown sender deferral, and delayed repair. They do not provide a GE-018 seeded field-mutation matrix asserting exactly one valid replay renders and every mutated replay rejects without plaintext, cursor, receipt, message, reaction, or system side effects.
- `scripts/run_test_gates.sh groups` is the named Flutter host group gate. It does not run Go tests or application-only replay tests, so GE-018 needs explicit Go and direct Dart commands in addition to the named groups gate when Dart group app code changes.

## Reviewer Sufficiency Review

Verdict: sufficient with adjustments already incorporated.

- Files/tests/gates are concrete enough for execution: primary Go proof in `go-mknoon/node/pubsub_test.go`, live no-render proof in `go-mknoon/node/pubsub_decryption_failure_test.go`, replay side-effect proof in `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, direct Go/Dart commands, named groups gate, full Go sweep, and `git diff --check`.
- No stale assumption found at review time: GE-018 still needed row-owned closure evidence then; adjacent one-off GK/ER tests were support evidence only, not closure.
- Minimum sufficiency adjustment: do not rely solely on a pure validator table. Execution must prove one actual render control and no render/no plaintext on representative live raw-publish mutations, plus replay-drain no-side-effect behavior.
- Overengineering avoided: no simulator/device harness, no envelope version migration, no generic fuzz framework, and no runtime change unless the new proof fails against current behavior.

## Arbiter Decision

No structural blocker remains.

- Structural blockers: none.
- Incremental details: live raw-publish mutation set may be smaller than the pure validator matrix as long as it covers each reject branch and proves no render/no plaintext.
- Accepted differences: type-tamper may fail after decrypt as `payload_parse_failed` rather than at validator time if it remains no-render and diagnostics are safe; host proof is sufficient because GE-018 is validator/replay host-testable and simulator proof is N/A.

## Final Planning Output

- Final verdict: execution-ready.
- Final plan: add deterministic GE-018 host tests for Go validator/live no-render behavior and Dart replay no-side-effect behavior; make only the smallest runtime fix if those tests expose a concrete fail-open or leak.
- Structural blockers remaining: none.
- Incremental details intentionally deferred: exact mutation table names can be adjusted during implementation if a local helper or existing test shape makes a smaller equivalent proof clearer.
- Accepted differences intentionally left unchanged: no simulator/device harness unless runtime bridge/device behavior changes; individual existing GK/ER/EK rows remain support evidence, not closure evidence; type-tamper can be a safe parse failure rather than validator rejection.
- Exact docs/files used as evidence: source matrix row GE-018, breakdown row 176/detailed row 2064, GE-017 plan/test pattern, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_decryption_failure_test.go`, `go-mknoon/node/group_security_harness_test.go`, `lib/features/groups/application/group_offline_replay_envelope.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `scripts/run_test_gates.sh`, and `Test-Flight-Improv/test-gate-definitions.md`.
- Why safe to implement now: the repo already has host-testable validator, live raw-publish, and replay-drain seams; no external fixture is required, and the closure bar is concrete enough to prevent scope drift.

## Execution Evidence

- Added `go-mknoon/node/pubsub_test.go::TestGE018SeededEnvelopeFieldTamperingValidatorClassifiesFailClosed`. It builds valid active-device v3 group envelopes, runs fixed seeds `18018`, `18019`, and `18020` over a shuffled mutation table, and proves valid controls accept while malformed JSON, version/type/group/sender/device/transport/public-key/key-package, ciphertext, nonce, key-epoch, signature, missing-field, and legacy public-key forgery mutations fail closed or remain live-decrypt-only no-render where appropriate.
- Added `go-mknoon/node/pubsub_decryption_failure_test.go::TestGE018SeededEnvelopeTamperingLivePathNeverRendersPlaintext`. It proves a valid live control renders exactly once, then raw-publishes representative tampered envelopes and verifies no `group_message:received`, no `group_reaction:received`, and no sentinel plaintext render for validator rejects, decrypt rejects, and safe payload-parse rejects.
- Added `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart::GE-018 seeded offline replay envelope tampering rejects before plaintext render`. It proves one valid signed replay persists once with a read receipt, then runs a fixed-seed replay mutation matrix over group/payload/message/sender/device/recipient/ciphertext/nonce/signature/key/malformed fields and verifies every mutation leaves no message, no cursor advance, no receipt, and no `group.decrypt` side effect.
- Repaired stale accepted proof `GEK003 partial key-update delivery plus immediate post-rotation send repairs stale recipient after later key arrival` in the same Dart file. The proof now models delayed recipient processing after successful key-update handoff, aligning it with the current GE-005 fail-closed rotation contract where failed required fanout makes rotation return `null`.
- No production runtime code changed for GE-018. The current Go validator/live path and Dart signed replay verifier already satisfied the row once exact seeded no-render/no-side-effect tests were added.

Validation passed:

- Baseline missing proof: `cd go-mknoon && go test ./node -run 'TestGE018' -count=1` reported no GE-018 tests before implementation.
- Baseline missing proof: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GE-018'` reported no matching tests before implementation.
- `gofmt -w node/pubsub_test.go node/pubsub_decryption_failure_test.go`
- `dart format --set-exit-if-changed test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `cd go-mknoon && go test ./node -run 'TestGE018' -count=1` passed.
- `cd go-mknoon && go test ./internal ./node -run 'TestGE018|TestGK006|TestGK007|TestGK008|TestGK012|TestGK013|TestGK015|TestGK025|TestGK026|TestGK027|TestGK033|TestER001' -count=1` passed.
- `dart analyze test/features/groups/application/drain_group_offline_inbox_use_case_test.dart lib/features/groups/application/group_offline_replay_envelope.dart lib/features/groups/application/drain_group_offline_inbox_use_case.dart` exited 0 with only existing info-level `use_null_aware_elements` notes in `group_offline_replay_envelope.dart`.
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GE-018'` passed (`+1`).
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GEK003 partial key-update delivery plus immediate post-rotation send repairs stale recipient after later key arrival'` passed (`+1`).
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` passed (`+79`).
- `./scripts/run_test_gates.sh groups` passed (`+157`).
- `cd go-mknoon && go test ./...` passed, including `bridge` (`109.625s`) and `node` (`362.566s`).
- `git diff --check` on owned GE-018 files plus closure docs passed.

## Final Verdict

Accepted/closed. GE-018 is covered by row-owned seeded Go live-envelope and Dart replay-envelope tamper proofs. All mutated envelopes fail closed without plaintext render or replay side effects, valid controls render/persist once, residual-only none, and GE-019 is the next unresolved P0 session.

## real scope

GE-018 owns one implementation-committed gap closure for randomized private-group envelope tampering. The implementation should add deterministic bounded host proofs first and change runtime code only if those proofs expose a concrete fail-open path.

In scope:

- Add exact GE-018 tests that generate valid authorized group envelopes, mutate one or more fields without re-signing unless the control case is intentionally valid, and run the current validator/render or durable replay path.
- Prove the unmodified authorized control envelope renders exactly once.
- Prove every mutated envelope rejects safely: no `group_message:received`, no `group_reaction:received`, no Dart `GroupMessage`, no reaction/state/cursor side effect, no plaintext or sensitive envelope fragments in diagnostics/log events.
- Make the smallest runtime fix in `go-mknoon/node/pubsub.go`, `go-mknoon/internal/group_envelope.go`, `lib/features/groups/application/group_offline_replay_envelope.dart`, or `lib/features/groups/application/drain_group_offline_inbox_use_case.dart` only when the new GE-018 proof identifies a concrete invariant gap.

Out of scope:

- Do not close GE-019 key-rotation property testing, GE-020 or later soak/concurrency rows, simulator relay parity, real-device harness coverage, broad cryptographic redesign, or closure doc updates during implementation.
- Do not add fake-network-only envelope validation if it would bypass the real v3 Go validator or Dart signed replay verifier.

## closure bar

GE-018 is good enough when deterministic bounded tests prove:

- Exactly valid authorized v3 live group envelopes render once through the Go event path.
- Exactly valid authorized Dart offline replay envelopes render once through `drainGroupOfflineInbox`.
- Mutations of envelope fields fail closed before plaintext render. Mutated field classes must include at minimum: `version`, `type`, `groupId`, `senderId`, `senderDeviceId`, `senderTransportPeerId`, `senderDevicePublicKey`, `senderKeyPackageId`, `senderPublicKey`, `signature`, `keyEpoch`, `encrypted.ciphertext`, `encrypted.nonce`, replay `payloadType`, replay `messageId`, replay `recipientSetHash`, replay `signedPayload`, replay `signatureAlgorithm`, replay sender/device fields, relay `from`, malformed JSON, missing required fields, blank required fields, and wrong-type JSON values.
- Safe diagnostics are emitted for rejected live envelopes without leaking plaintext, group names, raw peer ids, private/public keys, signature, ciphertext, nonce, or sentinel payload markers. Acceptable reject outcomes are validator rejection events, payload-parse-failed events for decrypted-but-schema-invalid payloads, or replay signature/decode skip events; none may become a rendered message/reaction.
- The test is replayable from fixed seeds and logs seed, mutation name, envelope type, expected outcome, and concise hashes/safe ids on failure.

## source of truth

- Current code/tests beat stale docs.
- Source matrix row GE-018 defines the exact behavior and expected result.
- Breakdown row 176 / detailed ledger row 2064 define this as `needs_code_and_tests` and `implementation-ready`.
- `go-mknoon/node/pubsub.go`, `go-mknoon/internal/group_envelope.go`, and existing Go validator/decryption tests are authoritative for live v3 envelopes.
- `group_offline_replay_envelope.dart`, `drain_group_offline_inbox_use_case.dart`, and their tests are authoritative for durable replay envelopes.
- `scripts/run_test_gates.sh` is the named-gate source of truth for Flutter group host gates; Go tests are required direct commands because the named Flutter gates do not run Go.

## session classification

`implementation-ready`

The row-owned gap is missing exact deterministic GE-018 tests and possibly a runtime fix if those tests reveal a fail-open mutation. It must remain `needs_code_and_tests` until concrete code/test evidence closes it.

## exact problem statement

The repo has many fixed tamper tests, but it lacks a single deterministic property-style proof that random envelope-field mutations cannot render private-group plaintext through either the live v3 validator/event path or the durable replay drain path. That leaves room for a field that is not signature-bound, not schema-checked, or not diagnostic-safe to slip through as a visible message/reaction or leak plaintext in reject output.

User-visible behavior that must improve: private group recipients should only see plaintext from exactly valid authorized envelopes. Tampered, malformed, wrong-sender, wrong-device, wrong-key, wrong-group, wrong-type, or replay-mismatched envelopes must reject without visible content.

Behavior that must stay unchanged: valid authorized sends, valid offline replay, durable inbox recovery, GE-017 membership property proof, existing one-off tamper protections, and current safe placeholder behavior for genuinely missing future keys.

## files and repos to inspect next

Primary test files:

- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_decryption_failure_test.go`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`

Primary runtime files, only if the new tests expose a concrete gap:

- `go-mknoon/node/pubsub.go`
- `go-mknoon/internal/group_envelope.go`
- `lib/features/groups/application/group_offline_replay_envelope.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`

Supporting context:

- `go-mknoon/node/group_inbox.go`
- `go-mknoon/node/group_inbox_test.go`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `test/shared/fakes/fake_group_pubsub_network.dart`
- `test/shared/fakes/group_test_user.dart`
- `scripts/run_test_gates.sh`
- `Test-Flight-Improv/test-gate-definitions.md`

## existing tests covering this area

- `go-mknoon/node/pubsub_test.go` has pure validator coverage for valid v3 envelopes, unsupported versions/types, group mismatch, missing signature, sender-id tamper, device/transport binding tamper, reaction epoch/device validation, and relay-visible encryption.
- `go-mknoon/node/pubsub_decryption_failure_test.go` has live raw-publish coverage for ciphertext tamper, wrong key, missing signature, missing encrypted fields, group mismatch, type tamper to reaction, sender-id tamper, and device/transport binding tamper with no message/reaction/decryption events.
- `go-mknoon/node/pubsub_authorization_forward_test.go` has safe reject diagnostic coverage and privacy-safe event/log assertions.
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` has signed replay rejection tests for invalid signature, unsigned replay forms, cursor side-effect prevention, missing key repair, stale epoch skip, unknown sender deferral, and replay through listener.
- GE-017 in `group_messaging_smoke_test.dart` provides the accepted deterministic seeded property style, but it does not exercise envelope-field mutation.

Missing: no exact GE-018 bounded fuzzer ties these seams together, names GE-018, mutates a broad envelope field set, proves one valid control renders, proves every mutation rejects with safe diagnostics, and records replayable seed/mutation context.

## regression/tests to add first

Run missing selectors before implementation:

```bash
cd go-mknoon && go test ./node -run 'TestGE018' -count=1
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GE-018'
```

Expected baseline before implementation: no GE-018 tests are found. Treat that as the missing-proof red baseline, not as closure evidence.

Candidate tests:

- `go-mknoon/node/pubsub_test.go::TestGE018SeededRandomEnvelopeTamperingRejectsExceptExactValidEnvelope`
- `go-mknoon/node/pubsub_decryption_failure_test.go::TestGE018SeededRandomEnvelopeTamperingEmitsSafeDiagnosticsAndNoPlaintext`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart::GE-018 seeded offline replay envelope tampering rejects before plaintext render`

## step-by-step implementation plan

1. Confirm the missing selectors above.
2. Add a deterministic Go mutation table/helper in `pubsub_test.go` that builds valid `group_message` and `group_reaction` envelopes using existing `buildTestEnvelopeWithPlaintext` / `buildTestDeviceEnvelopeWithPlaintext` helpers, then applies seeded mutations to one field at a time.
3. For each Go pure-validator mutation, assert the unmodified control returns `accept` and every mutated case returns the expected safe reject reason or a documented no-render reject class. Failure output must include seed, mutation name, field, envelope type, and validator result.
4. Add a live raw-publish GE-018 test in `pubsub_decryption_failure_test.go` using existing `startLocalNodeForMultiRelayTestWithCollector`, `publishRawGroupEnvelope`, `waitForCollectedValidationReject`, and `assertNoCollectedEventContainingAfter` helpers. Keep the live set bounded to representative mutation classes from each branch: invalid envelope shape, group mismatch, peer mismatch, non-member, unbound/revoked device, bad signature/epoch, encrypted field tamper, and type/payload mismatch.
5. In the live test, assert safe diagnostics and no rendered plaintext: no `group_message:received`, no `group_reaction:received`, no unexpected `group:decryption_failed` for validator rejects, no sentinel plaintext, no raw group id, no peer id, no public/private key, no signature, no ciphertext, and no nonce in reject events/logs.
6. Add a Dart durable replay GE-018 test in `drain_group_offline_inbox_use_case_test.dart`. Build one valid `group_offline_replay` message envelope with `buildGroupOfflineReplayEnvelope`, then mutate replay fields with fixed seed/table and feed each through `drainGroupOfflineInbox`.
7. For the Dart replay test, assert only the unmodified control persists exactly one message. Every mutation must reject before side effects: no message row, no reaction row, no membership/system mutation, no cursor advancement, no receipt persistence, and no `group.decrypt` call when the signature/signed metadata is already invalid.
8. If a mutation fails only because the test model contradicts existing product rules, adjust the test model and document the existing rule in a short comment. Do not change runtime code for a false oracle.
9. If a mutation renders plaintext, advances replay cursor, leaks diagnostics, or validates an envelope that the GE-018 closure bar says must reject, make the narrowest runtime fix in the direct file named by the failure.
10. If a Go signature-binding issue is found, prefer a minimal compatibility-aware validator/signature hardening. Do not redesign the envelope format beyond what the GE-018 failing case requires.
11. If a Dart replay issue is found, harden `_verifyReplaySignature`, `_verifyPlaintextBinding`, or drain side-effect ordering before any decrypt/render/cursor mutation. Do not alter durable replay APIs unless the failure proves they are insufficient.
12. Re-run focused commands and the required gates below. Stop after GE-018 proof and any minimal fix; closure docs are handled after implementation.

## risks and edge cases

- Type-only mutations can be subtle because an envelope may pass signature validation but fail payload parsing. GE-018 accepts that only as a safe reject if no plaintext/reaction/message is emitted and diagnostics are privacy-safe.
- Random tests can become flaky if they depend on pubsub timing. Keep mutation generation deterministic and bound live raw-publish cases to a small representative set; use pure-validator tests for the broad field matrix.
- Diagnostics can leak via logs even when events are safe. Include explicit sentinel plaintext/key/ciphertext/nonce checks against both event collector output and captured logs where available.
- Replay drain can accidentally advance cursors after rejection. The Dart replay test must check cursor and receipt side effects, not only message rows.
- Missing future keys intentionally create placeholders or repairs. GE-018 should distinguish valid missing-key replay behavior from tampered replay; only missing-key controls may create the existing safe placeholder.

## exact tests and gates to run

Focused first:

```bash
cd go-mknoon && go test ./node -run 'TestGE018' -count=1
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GE-018'
```

Formatting and direct regressions:

```bash
gofmt -w go-mknoon/node/pubsub_test.go go-mknoon/node/pubsub_decryption_failure_test.go go-mknoon/node/pubsub.go go-mknoon/internal/group_envelope.go
cd go-mknoon && go test ./internal ./node -run 'TestGE018|TestGK006|TestGK008|TestGK012|TestGK013|TestGK015|TestGK025|TestGK026|TestGK027|TestGK033|TestER001' -count=1
dart format --set-exit-if-changed test/features/groups/application/drain_group_offline_inbox_use_case_test.dart lib/features/groups/application/group_offline_replay_envelope.dart lib/features/groups/application/drain_group_offline_inbox_use_case.dart
dart analyze test/features/groups/application/drain_group_offline_inbox_use_case_test.dart lib/features/groups/application/group_offline_replay_envelope.dart lib/features/groups/application/drain_group_offline_inbox_use_case.dart
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GE-018'
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
```

Named/broader gates:

```bash
./scripts/run_test_gates.sh groups
cd go-mknoon && go test ./...
git diff --check
```

If no Dart runtime files change, `dart analyze` may be scoped to the touched Dart test file. If no Go runtime files change, `gofmt` should target only touched Go test files, but the final `cd go-mknoon && go test ./...` remains required because this row is validator/security-sensitive.

## known-failure interpretation

- Missing GE-018 selectors before implementation are expected and prove the row-owned gap exists.
- Existing GK/ER one-off tamper tests are support evidence only; passing them does not close GE-018 without the new seeded GE-018 proof.
- If `./scripts/run_test_gates.sh groups` fails in unrelated pre-existing UI/group integration tests while focused GE-018 and direct replay tests pass, isolate with direct file selectors and record the unrelated failure separately rather than treating GE-018 as closed.
- Any failure in `TestGE018`, adjacent GK tamper tests, `ER001`, `drain_group_offline_inbox_use_case_test.dart`, `group_offline_replay_envelope.dart`, or `drain_group_offline_inbox_use_case.dart` is presumed related until proven otherwise.

## done criteria

- GE-018 focused Go tests pass and prove broad seeded live-envelope mutation rejection/no-render.
- GE-018 focused Dart replay test passes and proves broad seeded replay-envelope mutation rejection/no-side-effects.
- Exactly valid authorized control envelopes render/persist once in both live and replay paths.
- All mutated envelopes fail closed with safe diagnostics and no plaintext/event/cursor/receipt/system side effects.
- Required format, analyzer, Go direct tests, Dart direct tests, named `groups` gate, full Go tests, and `git diff --check` pass or any unrelated failure is clearly isolated with evidence.
- Any runtime fix is limited to the direct validator/replay seam revealed by the new failing proof.

## scope guard

Do not broaden into:

- New group crypto architecture or envelope version migration beyond a proven GE-018 field-binding bug.
- Simulator/device harness work; GE-018 is a deterministic host proof row.
- Fake pubsub network validation that does not exercise real v3 envelope semantics.
- GE-019 key-rotation access-window property, GE-020 soak behavior, concurrent admin mutations, or generic fuzzing infrastructure.
- Closure doc edits during implementation. Those are post-implementation closure work.

## accepted differences / intentionally out of scope

- Host proof is sufficient for GE-018 because the row asks for a deterministic fuzzer/model and the relevant validator/replay code is host-testable. Real-device relay proof is N/A unless a later closure process explicitly requires it.
- Individual GK/ER/EK tests remain as regression support, not closure evidence for the row.
- Type-tamper outcomes may be represented as a safe payload-parse reject rather than validator rejection only if the envelope never emits a message/reaction/plaintext and the diagnostic remains safe. If the GE-018 oracle requires validator-level rejection for type mutation, that becomes a concrete Go hardening task inside this session.

## dependency impact

- GE-019 random key-rotation access-window testing depends on GE-018 not allowing mutated key-epoch/signature/ciphertext envelopes to render.
- Later soak/concurrency rows should rely on GE-018 for envelope fail-closed behavior instead of re-testing every tamper field.
- If GE-018 requires a signature-binding/runtime compatibility change, GE-019 and any real-device group harness should be revisited for envelope-version assumptions before execution.

## closure/doc update instructions

After implementation and validation, update only in the closure/doc-sync session:

- Source matrix row GE-018 in `Private_group_chat_reliability_test_matrix_COMPLETE_1.md`: mark `Covered`, summarize exact tests, files, and passed commands.
- Breakdown row 176 and detailed closure ledger row 2064 in `Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`: mark `covered/accepted`, list touched files, evidence, residual-only notes, and next unresolved row.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`: add the new GE-018 tests and classify Go direct tests outside the Flutter named gates.
- This plan file: record execution evidence and final verdict if the implementation executor is assigned to update the plan.
