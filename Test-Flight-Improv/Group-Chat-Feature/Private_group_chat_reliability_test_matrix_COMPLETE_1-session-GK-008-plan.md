# GK-008 Plan: Signature rejects wrong public key

Status: accepted/closed

## Planning Progress

- 2026-05-12 05:50:22 CEST - Planner completed. Files inspected since last update: complete draft sections, exact test shape, existing generic signature tests, adjacent live PubSub rejection helpers, and test/gate contract. Decision/blocker: draft is GK-008-only, implementation-ready, and tests-only unless the new regression proves current validator behavior is wrong. Next action: run reviewer pass for sufficiency and scope drift.
- 2026-05-12 05:52:10 CEST - Reviewer started. Files inspected since last update: full draft plan, mandatory section checklist, source row semantics, and exact gate list. Decision/blocker: review focus is row-owned proof, live integration necessity, device-binding avoidance, and GK-009+/GK-012 scope exclusion. Next action: classify sufficiency and required adjustments.
- 2026-05-12 05:52:10 CEST - Reviewer completed. Files inspected since last update: full draft plan and evidence notes. Decision/blocker: sufficient as-is; no structural blockers. The plan requires exact pure and live proof, preserves source/breakdown closure boundaries, and avoids Flutter gates unless Dart files are touched. Next action: run arbiter classification and stop-rule decision.
- 2026-05-12 05:52:31 CEST - Arbiter started. Files inspected since last update: reviewer pass, closure bar, scope guard, exact tests/gates, and accepted differences. Decision/blocker: classify findings into structural blockers, incremental details, and accepted differences. Next action: finalize execution-ready status if no structural blocker remains.
- 2026-05-12 05:52:31 CEST - Arbiter completed. Files inspected since last update: reviewer findings and final plan sections. Decision/blocker: no structural blockers remain; no patch loop required. Incremental details are limited to implementation-time naming/placement choices; accepted differences are documented. Next action: plan is execution-ready for GK-008 only.

## Execution Progress

- 2026-05-12 05:55:58 CEST - Executor started. Files inspected since last update: this GK-008 plan, dirty worktree status, `go-mknoon/node/pubsub_decryption_failure_test.go`, existing validator/envelope helpers, and adjacent GK-006/GK-007 tests. Decision/blocker: contract is tests-only unless the row-named regression proves a production acceptance defect; target file already had unrelated local GK-006/GK-007 edits and they were preserved. Next action: run required gofmt and Go test commands.
- 2026-05-12 05:55:58 CEST - Executor edited. Files touched since last update: `go-mknoon/node/pubsub_decryption_failure_test.go`. Decision/blocker: added `TestGK008SignatureRejectsWrongPublicKeyAndEmitsNoMessage` near GK-006/GK-007; production code untouched. Next action: run required command 1, `gofmt`.
- 2026-05-12 05:56:18 CEST - Required command 1 finished. Command: `(cd go-mknoon && gofmt -w node/pubsub_decryption_failure_test.go)`. Result: pass, exit 0, no stdout/stderr. Next action: run required focused selector.
- 2026-05-12 05:56:48 CEST - Required command 2 finished. Command: `(cd go-mknoon && go test ./node -run '^(TestGK008SignatureRejectsWrongPublicKeyAndEmitsNoMessage|TestGroupTopicValidator_BadSignature|TestGroupTopicValidator_SpoofedPublicKey|TestGroupTopicValidator_RejectsForgedMembershipSystemEventSignature|TestGK006TamperedCiphertextAfterSigningRejectedByValidatorAndEmitsNoMessage)$' -count=1)`. Result: pass, exit 0, output `ok  	github.com/mknoon/go-mknoon/node	5.173s`. Next action: run required focused race selector.
- 2026-05-12 05:57:15 CEST - Required command 3 finished. Command: `(cd go-mknoon && go test -race ./node -run '^TestGK008SignatureRejectsWrongPublicKeyAndEmitsNoMessage$' -count=1)`. Result: pass, exit 0, output `ok  	github.com/mknoon/go-mknoon/node	4.138s`. Next action: run required broader Go sweep.
- 2026-05-12 06:01:19 CEST - Required command 4 finished. Command: `(cd go-mknoon && go test ./node ./internal ./crypto -count=1)`. Result: pass, exit 0, output `ok  	github.com/mknoon/go-mknoon/node	214.614s`; `ok  	github.com/mknoon/go-mknoon/internal	0.343s`; `ok  	github.com/mknoon/go-mknoon/crypto	0.701s`. Next action: run required diff hygiene.
- 2026-05-12 06:01:38 CEST - Required command 5 finished. Command: `git diff --check`. Result: pass, exit 0, no stdout/stderr. Next action: inspect final diff and write executor verdict only.
- 2026-05-12 06:02:14 CEST - Final diff hygiene recheck finished after verdict write. Command: `git diff --check`. Result: pass, exit 0, no stdout/stderr. Next action: return executor result; do not update source matrix, session breakdown closure rows, or final program verdict.

## Executor Verdict

Verdict: accepted.

Files changed by this executor:

- `go-mknoon/node/pubsub_decryption_failure_test.go`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-008-plan.md`

Implementation summary:

- Added exact row-named regression `TestGK008SignatureRejectsWrongPublicKeyAndEmitsNoMessage` near GK-006/GK-007.
- The regression builds an envelope for member B/node A with member B's configured public key while signing the same `BuildGroupSignatureData` payload with attacker key X.
- The regression proves signature verification succeeds with X public key, fails with B public key, pure `validateGroupEnvelope(...)` returns `reject:bad_signature`, live node B emits `group:validation_rejected` reason `bad_signature_or_epoch` at epoch 8, and no post-baseline `group_message:received`, `group_reaction:received`, `group:decryption_failed`, or plaintext marker appears.
- Production code was not changed because the regression passed against existing validator behavior.

Exact command results:

- `(cd go-mknoon && gofmt -w node/pubsub_decryption_failure_test.go)` - pass, exit 0, no stdout/stderr.
- `(cd go-mknoon && go test ./node -run '^(TestGK008SignatureRejectsWrongPublicKeyAndEmitsNoMessage|TestGroupTopicValidator_BadSignature|TestGroupTopicValidator_SpoofedPublicKey|TestGroupTopicValidator_RejectsForgedMembershipSystemEventSignature|TestGK006TamperedCiphertextAfterSigningRejectedByValidatorAndEmitsNoMessage)$' -count=1)` - pass, exit 0, output `ok  	github.com/mknoon/go-mknoon/node	5.173s`.
- `(cd go-mknoon && go test -race ./node -run '^TestGK008SignatureRejectsWrongPublicKeyAndEmitsNoMessage$' -count=1)` - pass, exit 0, output `ok  	github.com/mknoon/go-mknoon/node	4.138s`.
- `(cd go-mknoon && go test ./node ./internal ./crypto -count=1)` - pass, exit 0, output `ok  	github.com/mknoon/go-mknoon/node	214.614s`; `ok  	github.com/mknoon/go-mknoon/internal	0.343s`; `ok  	github.com/mknoon/go-mknoon/crypto	0.701s`.
- `git diff --check` - pass, exit 0, no stdout/stderr.

Blockers/pre-existing failures: none encountered in required commands.

## Evidence Collector Notes

- At planning time, source matrix row `GK-008` was `P0` / `Open`: "Signature rejects wrong public key." Preconditions are "Envelope signed by X but claims B"; steps are build envelope with X signature and validate under B member public key; expected result is validator rejection as `bad_signature_or_epoch`. Unit and Integration are `Required`; Fake Network is `Recommended`; 3-Party E2E is `N/A`.
- At planning time, the session breakdown classified `GK-008` as `needs_tests_only` / `implementation-ready`, pointed to this plan path, and said exact row-owned proof must be added or verified. It also recorded GK-006 and GK-007 as covered separately; GK-009+ remain later rows.
- `go-mknoon/node/pubsub.go` verifies group envelope signatures with `verifyGroupEnvelopeSignature(groupId, sourceDevice.DeviceSigningPublicKey, env, keyInfo, time.Now())`; live validator failure logs and emits `group:validation_rejected` reason `bad_signature_or_epoch`.
- `go-mknoon/node/pubsub.go` uses `activeMemberDeviceForEnvelope` to resolve the trusted configured legacy/member-device signing key. For legacy members with no `Devices`, the trusted key is `GroupMember.PublicKey`; for device members it is `GroupMemberDevice.DeviceSigningPublicKey`.
- `go-mknoon/crypto/group.go` signs only `groupId|epoch|ciphertext` through `BuildGroupSignatureData`. `go-mknoon/crypto/sign.go` returns `false` for a valid signature checked under the wrong Ed25519 public key.
- Existing pure tests `TestGroupTopicValidator_BadSignature` and `TestGroupTopicValidator_SpoofedPublicKey` already prove generic bad-signature rejection, but they are not GK-008 row-named and do not prove live PubSub diagnostic/no-message behavior.
- Existing live GK-006/GK-007 tests in `go-mknoon/node/pubsub_decryption_failure_test.go` supply the current row-owned pattern: build a valid envelope, mutate or mismatch it, assert pure validator behavior, publish through a real two-node local PubSub path, capture events after a baseline, and assert no plaintext receive/reaction event leaks.
- `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, and `go-mknoon/node/node_test.go` already provide local node, publish, event collector, validation reject, and no-event helpers.

## real scope

Own exactly source row GK-008: an envelope signed by key X while claiming sender/member B must be rejected by the group validator under B's configured public key.

In scope:

- Add one exact row-named Go node regression, preferably `TestGK008SignatureRejectsWrongPublicKeyAndEmitsNoMessage`.
- Prove the envelope signature verifies under attacker/key X but not under the configured member B public key.
- Assert pure `validateGroupEnvelope(...)` rejects as `reject:bad_signature`.
- Assert live two-node PubSub emits `group:validation_rejected` reason `bad_signature_or_epoch` and does not emit `group_message:received`, `group_reaction:received`, or `group:decryption_failed` after the baseline.
- Reuse existing Go node helpers and adjacent signature tests.

Out of scope:

- Do not update source matrix or breakdown closure rows during this planning task or initial implementation.
- Do not implement GK-009 signature-data determinism, GK-012 missing signature, GK-017 stale epoch, GA-009 legacy-device variants, malformed-envelope rows, offline replay, Flutter UI, or simulator work.
- Do not change signature algorithms, envelope schema, key rotation policy, event names, or production behavior unless the new exact regression proves current production accepts the wrong key.

## closure bar

GK-008 is good enough when the repo has row-owned evidence that:

- The test constructs a v3 group envelope whose `senderId` is member B and whose configured `GroupMember.PublicKey` is B's Ed25519 public key.
- The envelope is actually signed with private key X, while its public-key claim remains B-compatible enough to reach signature verification rather than earlier membership/device rejection.
- A direct signature sanity check proves the signature verifies under X's public key and fails under B's public key.
- `validateGroupEnvelope` returns `reject:bad_signature`.
- A real receiver validator emits `group:validation_rejected` with reason `bad_signature_or_epoch` and the expected key epoch.
- No plaintext receive, reaction, or decrypt-failure event is emitted after the tampered publish baseline.
- Focused Go selector, race selector, broader Go sweep over `./node ./internal ./crypto`, and `git diff --check` pass, or any unrelated pre-existing failures are isolated and documented.

## source of truth

- Current code and tests win over stale docs.
- Source row `GK-008` in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` is the row contract.
- Breakdown row/session `GK-008` in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` is the session contract.
- `go-mknoon/node/pubsub.go` is authoritative for live PubSub validation, configured-key lookup, bad-signature rejection, and `group:validation_rejected` event emission.
- `go-mknoon/node/pubsub_test.go::validateGroupEnvelope` is the pure validator mirror used for focused unit-style proof.
- `go-mknoon/node/group.go` defines `GroupConfig`, `GroupMember`, `GroupMemberDevice`, roles, and key info used by the validator.
- `go-mknoon/crypto/group.go` and `go-mknoon/crypto/sign.go` are authoritative for signature data and Ed25519 sign/verify behavior.
- `go-mknoon/internal/group_envelope.go` is authoritative for v3 envelope fields.

## session classification

implementation-ready.

This is implementation-committed gap closure. Current production code appears to reject the wrong public key already, so the expected implementation is tests-only. It is not docs-only or evidence-only because the source row remains `Open` and lacks exact row-owned live proof.

## exact problem statement

GK-008 remains open because existing tests prove generic wrong-key signature rejection but do not supply exact row-owned evidence for the source semantics: envelope signed by key X, claiming member B, validated under B's configured public key, rejected as `bad_signature_or_epoch`, and no plaintext/decrypt event emitted.

The user-visible behavior that must stay unchanged is fail-closed group message handling: a sender cannot publish readable group content by claiming another member's public key while signing with a different private key. The validator should reject before decrypt/render, and diagnostics should identify the rejection as `bad_signature_or_epoch`.

## files and repos to inspect next

Before editing:

- `git status --short`
- `go-mknoon/node/pubsub_decryption_failure_test.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group.go`
- `go-mknoon/node/group_security_harness_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/node_test.go`
- `go-mknoon/crypto/group.go`
- `go-mknoon/crypto/sign.go`
- `go-mknoon/internal/group_envelope.go`

Fallback-only if tests prove a production defect:

- `go-mknoon/crypto/signature_test.go`
- `go-mknoon/internal/group_envelope_test.go`
- `go-mknoon/node/pubsub_key_rotation_grace_test.go`

Do not inspect or edit Flutter/Dart files unless the executor proves the GK-008 fix touches bridge/offline replay serialization, which is not expected.

## existing tests covering this area

- `go-mknoon/crypto/signature_test.go::TestVerify_WrongPublicKey` proves direct Ed25519 verification fails under a different public key.
- `go-mknoon/node/pubsub_test.go::TestGroupTopicValidator_BadSignature` builds an envelope signed with one key and validates against a different configured member key, expecting `reject:bad_signature`.
- `go-mknoon/node/pubsub_test.go::TestGroupTopicValidator_SpoofedPublicKey` proves a spoofed sender public key is rejected by the pure validator.
- `go-mknoon/node/pubsub_test.go::TestGroupTopicValidator_RejectsForgedMembershipSystemEventSignature` and adjacent security-event tests cover other forged-envelope signature paths.
- `go-mknoon/node/pubsub_decryption_failure_test.go::TestGK006TamperedCiphertextAfterSigningRejectedByValidatorAndEmitsNoMessage` proves live bad-signature rejection diagnostics and no-message behavior for post-signing ciphertext tamper.
- `go-mknoon/node/pubsub_decryption_failure_test.go::TestGK007NonceByteTamperFailsDecryptAndEmitsNoMessage` proves the adjacent nonce/decrypt path and should remain separate.

Missing:

- No exact `GK-008` row-named regression combines wrong-public-key signature facts, pure validator rejection, live `bad_signature_or_epoch`, and no receive/reaction/decrypt event.

## regression/tests to add first

Add `TestGK008SignatureRejectsWrongPublicKeyAndEmitsNoMessage` in `go-mknoon/node/pubsub_decryption_failure_test.go`, near the existing GK-006/GK-007 integrity tests.

Preferred test shape:

- Generate legit member B signing keys and attacker X signing keys.
- Start node A and node B, with node B using `startLocalNodeForMultiRelayTestWithCollector`.
- Use node A's `PeerId()` as the sender/member B identity so the live validator's transport-peer binding can pass.
- Configure the group with node A as admin and `PublicKey: memberBPubB64`; include node B as a writer/receiver with its own generated public key.
- Build the envelope with node A's sender id, attacker private key X, and member B public key in the envelope claim, for example by calling `buildTestEnvelope(t, groupId, senderPeerId, attackerPrivB64, memberBPubB64, groupKey, keyInfo.KeyEpoch, plaintextMarker)`.
- Parse the envelope and assert the signature verifies with attacker public key X but fails with member B public key over `BuildGroupSignatureData(groupId, keyEpoch, ciphertext)`.
- Assert `validateGroupEnvelope(envelopeJSON, groupId, config, keyInfo) == "reject:bad_signature"`.
- Connect local nodes and wait for peer visibility.
- Take a node B event baseline.
- Unregister only node A's local topic validator if raw publish would otherwise fail before fanout; keep node B's validator registered.
- Publish the raw envelope through node A with `publishRawGroupEnvelope`.
- Wait for node B `group:validation_rejected` reason `bad_signature_or_epoch` at the expected key epoch.
- Assert no `group_message:received`, no `group_reaction:received`, no `group:decryption_failed`, and no plaintext marker appear after the baseline.

Do not set `SenderDevicePublicKey` unless the test is intentionally using a device-member row; setting it to X would cause `unbound_device` and miss GK-008's signature-rejection branch.

## step-by-step implementation plan

1. Reconfirm dirty worktree state and do not overwrite unrelated changes.
2. Reopen the target test and helper files listed above.
3. Add `TestGK008SignatureRejectsWrongPublicKeyAndEmitsNoMessage` to `go-mknoon/node/pubsub_decryption_failure_test.go`.
4. Build the exact wrong-key envelope signed by X while claiming member B's configured public key and node A sender identity.
5. Add local signature sanity assertions under X and under B before validator assertions so failures point at test construction rather than PubSub.
6. Assert pure validator result is `reject:bad_signature`.
7. Add the live two-node PubSub leg and event baseline.
8. If node A's own validator rejects raw publish before fanout, unregister only node A's topic validator before publish; do not disable node B's validator.
9. Assert node B emits `group:validation_rejected` reason `bad_signature_or_epoch` and emits no received/reaction/decryption-failed/plaintext event after baseline.
10. Run `gofmt` on the edited Go test file.
11. Run the focused selector. If it passes, do not edit production.
12. If pure validation returns `accept`, inspect `verifyGroupEnvelopeSignature`, `BuildGroupSignatureData`, and `VerifyPayload`; make the smallest production fix only if the test is shaped correctly.
13. If live validation returns `peer_mismatch`, `unbound_device`, or `non_member`, fix the test setup first because those reasons do not satisfy GK-008.
14. Run the focused race selector, broader Go sweep, and `git diff --check`.
15. Leave source matrix and breakdown closure updates to a later closure writer after executor and QA evidence exist.

## risks and edge cases

- A mismatched `senderId` or missing transport binding can produce `peer_mismatch` before signature verification. Use node A's `PeerId()` as `SenderId`.
- Setting device public-key fields incorrectly can produce `unbound_device` before signature verification. For this legacy-member GK-008 proof, omit device fields.
- If the envelope uses attacker public key in the claim instead of B's key and the validator ignores `SenderPublicKey` for legacy members, the test can still reject, but the row is clearer when the envelope claim and config both name B's public key.
- Node A's local validator may reject the malformed raw publish before node B receives it. Disable only node A's validator for the raw publish leg.
- Diagnostic events are rate-limited by reason/group/sender/transport tuple. Use a unique group id and take the baseline immediately before publish.
- A `group:decryption_failed` event would mean the wrong-key envelope bypassed signature validation; that is a GK-008 blocker.

## exact tests and gates to run

Run from `/Users/I560101/Project-Sat/mknoon-2/flutter_app`.

If the Go test file is edited:

```sh
(cd go-mknoon && gofmt -w node/pubsub_decryption_failure_test.go)
```

Focused GK-008 and adjacent signature/integrity selector:

```sh
(cd go-mknoon && go test ./node -run '^(TestGK008SignatureRejectsWrongPublicKeyAndEmitsNoMessage|TestGroupTopicValidator_BadSignature|TestGroupTopicValidator_SpoofedPublicKey|TestGroupTopicValidator_RejectsForgedMembershipSystemEventSignature|TestGK006TamperedCiphertextAfterSigningRejectedByValidatorAndEmitsNoMessage)$' -count=1)
```

Focused race proof for the live PubSub validator path:

```sh
(cd go-mknoon && go test -race ./node -run '^TestGK008SignatureRejectsWrongPublicKeyAndEmitsNoMessage$' -count=1)
```

Broader Go sweep:

```sh
(cd go-mknoon && go test ./node ./internal ./crypto -count=1)
```

Diff hygiene:

```sh
git diff --check
```

Do not run Flutter gates for the expected tests-only Go implementation. If execution unexpectedly touches Dart/Flutter bridge, offline replay, or group application files, add the relevant Flutter unit/gate command before closure.

## known-failure interpretation

- Any failure in `TestGK008SignatureRejectsWrongPublicKeyAndEmitsNoMessage` is row-owned and blocks GK-008 closure.
- If the signature verifies under B's public key, the test did not actually sign with X or has malformed key setup; fix the test before touching production.
- If pure validation returns `peer_mismatch`, `unbound_device`, `non_member`, or `unauthorized`, the test setup missed the row's signature-verification branch.
- If pure validation returns `accept`, treat it as a likely production defect after confirming the signature sanity assertions.
- If live PubSub never sees `group:validation_rejected`, first check whether node A's local validator blocked fanout.
- Any `group_message:received`, `group_reaction:received`, `group:decryption_failed`, or plaintext marker after baseline is a GK-008 blocker.
- Pre-existing dirty-worktree failures outside Go group envelope/signature/validator paths should be separated and documented; they do not convert GK-008 into docs-only work.
- Do not mark GK-008 covered while the focused row proof or focused race proof fails.

## done criteria

- `go-mknoon/node/pubsub_decryption_failure_test.go` contains an exact row-named GK-008 regression.
- The regression proves signature validity under X and invalidity under B for the same group signature data.
- Pure validator rejects as `reject:bad_signature`.
- Live receiver emits `group:validation_rejected` reason `bad_signature_or_epoch`.
- No receive, reaction, decryption-failed, or plaintext marker event appears after the malformed publish baseline.
- Existing generic bad-signature/spoofed-key tests still pass.
- Focused Go selector, focused race selector, broader Go sweep over `./node ./internal ./crypto`, and `git diff --check` pass or any non-row failures are explicitly isolated.
- Source matrix and session breakdown closure rows remain untouched until a separate closure task records executor and QA evidence.

## scope guard

Non-goals:

- Do not close or edit GK-009, GK-010, GK-011, GK-012, GK-017, GA-009, offline replay rows, or Flutter/UI rows.
- Do not change the signature algorithm, signature data format, envelope schema, member/device authorization model, key epoch behavior, or event names unless GK-008's exact regression proves the current production behavior is wrong.
- Do not add a broad signature-audit suite, fuzzing, 3-party E2E, simulator proof, or new harness.
- Do not update source matrix/breakdown closure rows during implementation; closure requires post-execution and QA evidence.

Overengineering:

- Property tests for every envelope field, multi-device device-key variants, and offline replay key-claim parity are beyond GK-008.
- Rewriting existing generic signature tests instead of adding a small row-named test would create unnecessary churn.

## accepted differences / intentionally out of scope

- Existing generic signature tests are useful evidence but are not accepted as closure alone because they are not row-owned and do not assert live `group:validation_rejected` or no-message behavior.
- The planned test uses a two-node Go PubSub host path rather than Flutter or 3-party E2E. This is sufficient because the source row marks 3-Party E2E `N/A`, and the row's required integration behavior is the Go validator/event path.
- Device-specific `SenderDevicePublicKey` mismatch is intentionally out of scope; that can reject as `unbound_device` and belongs to device-binding rows such as GA-009 or later multi-device coverage.
- GK-009 deterministic signature-data coverage remains separate even though GK-008 uses `BuildGroupSignatureData` to construct and verify the wrong-key proof.

## dependency impact

Closing GK-008 unblocks GK-009 in the ordered P0 flow. If GK-008 execution proves a production signature-verification defect, GK-009 signature-data determinism and later malformed/missing-signature rows should be reviewed after the narrow fix, but they must not be absorbed into GK-008.

## reviewer pass

Sufficiency: sufficient as-is.

Missing files, tests, regressions, or gates: none. The plan names the source matrix row, breakdown row, Go validator/signature/envelope production seams, helper files, existing generic signature tests, an exact row-named regression, focused normal and race Go commands, broader `./node ./internal ./crypto` sweep, and `git diff --check`.

Stale or incorrect assumptions: none found. Current code evidence shows the live validator verifies with the configured member/device signing public key and maps failed verification to `bad_signature_or_epoch`; the plan still includes a production-fix fallback if execution disproves that evidence.

Overengineering: none found. The plan uses one row-named Go node regression with existing helpers and avoids Flutter, simulator, device-binding, GK-009+, and GK-012 scope.

Minimum needed to make sufficient: already met. No structural patch required.

## arbiter pass

Structural blockers: none.

Incremental details intentionally deferred:

- Exact test placement can remain near GK-006/GK-007 in `pubsub_decryption_failure_test.go`; the executor may choose a nearby signature-test location if it preserves both pure and live proof.
- The focused selector may be adjusted for equivalent adjacent signature tests, but it must include the exact GK-008 test and at least the existing generic bad-signature/spoofed-key coverage.

Accepted differences intentionally left unchanged:

- Generic existing signature tests are evidence, not closure.
- The plan requires a two-node Go PubSub proof instead of Flutter or 3-party E2E.
- Device-public-key mismatch is deferred because it would exercise `unbound_device`, not the GK-008 `bad_signature_or_epoch` branch.

Stop-rule decision: no structural blockers remain, so this plan is execution-ready without a patch loop.

## QA Reviewer Pass

Verdict: passed.

Inspected files:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-008-plan.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `go-mknoon/node/pubsub_decryption_failure_test.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/group_security_harness_test.go`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/node.go`
- `go-mknoon/node/group_inbox.go`

Execution sufficiency findings:

- Blocking findings: none.
- Non-blocking findings: none.
- `TestGK008SignatureRejectsWrongPublicKeyAndEmitsNoMessage` matches GK-008 row semantics: the envelope claims member B/node A and B's configured public key, is signed with attacker key X, proves the signature verifies with X and fails with B, gets pure `validateGroupEnvelope(...) == "reject:bad_signature"`, publishes through a real two-node PubSub path with only node A's local validator unregistered, observes node B `group:validation_rejected` reason `bad_signature_or_epoch` at epoch 8, and asserts no post-baseline `group_message:received`, `group_reaction:received`, `group:decryption_failed`, or plaintext marker.
- Production code was not changed for GK-008. The GK-008 executor touched only `go-mknoon/node/pubsub_decryption_failure_test.go` and this plan; current ambient production diffs are outside this QA verdict and were not modified by this pass.
- No GK-009+, GK-012, device-binding, Flutter, source-matrix closure, breakdown closure, or final program verdict scope was absorbed.
- At QA time before the closure-writer pass, source matrix row GK-008 remained `Open`; breakdown rows still listed GK-008 as `implementation-ready` / missing row-owned proof, and no final program verdict was written. The closure note below supersedes that pre-closure state.

Exact command results:

- `(cd go-mknoon && go test ./node -run '^(TestGK008SignatureRejectsWrongPublicKeyAndEmitsNoMessage|TestGroupTopicValidator_BadSignature|TestGroupTopicValidator_SpoofedPublicKey|TestGroupTopicValidator_RejectsForgedMembershipSystemEventSignature|TestGK006TamperedCiphertextAfterSigningRejectedByValidatorAndEmitsNoMessage)$' -count=1)` - pass, exit 0, output `ok  	github.com/mknoon/go-mknoon/node	5.241s`.
- `(cd go-mknoon && go test -race ./node -run '^TestGK008SignatureRejectsWrongPublicKeyAndEmitsNoMessage$' -count=1)` - pass, exit 0, output `ok  	github.com/mknoon/go-mknoon/node	4.172s`.
- `(cd go-mknoon && go test ./node ./internal ./crypto -count=1)` - pass, exit 0, output `ok  	github.com/mknoon/go-mknoon/node	215.286s`; `ok  	github.com/mknoon/go-mknoon/internal	1.142s`; `ok  	github.com/mknoon/go-mknoon/crypto	0.724s`.
- `git diff --check` - pass, exit 0, no stdout/stderr.

## Closure Note

- 2026-05-12 06:14:27 CEST - Closure Writer accepted GK-008 and updated the source matrix plus session breakdown to `Covered` / `covered/accepted`. Evidence: `go-mknoon/node/pubsub_decryption_failure_test.go::TestGK008SignatureRejectsWrongPublicKeyAndEmitsNoMessage` builds an envelope for member B/node A with member B's configured public key while signing with attacker key X, proves signature verification succeeds with X and fails with B for the same `BuildGroupSignatureData` payload, proves pure `validateGroupEnvelope(...) == "reject:bad_signature"`, unregisters only node A local validator for raw fanout, publishes through the real two-node PubSub path, observes node B `group:validation_rejected` reason `bad_signature_or_epoch` at epoch 8, and asserts no post-baseline `group_message:received`, `group_reaction:received`, `group:decryption_failed`, or plaintext marker.
- Executor evidence: focused selector `ok github.com/mknoon/go-mknoon/node 5.173s`; race selector `ok github.com/mknoon/go-mknoon/node 4.138s`; broader Go sweep `ok node 214.614s`, `ok internal 0.343s`, `ok crypto 0.701s`; `git diff --check` passed.
- Independent QA evidence: focused selector `ok github.com/mknoon/go-mknoon/node 5.241s`; race selector `ok github.com/mknoon/go-mknoon/node 4.172s`; broader Go sweep `ok node 215.286s`, `ok internal 1.142s`, `ok crypto 0.724s`; `git diff --check` passed.
- Production code unchanged for GK-008; residual-only none. GK-009 remains the next unresolved P0 continuation row.
