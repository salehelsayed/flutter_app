Status: accepted/closed

# GK-007 Execution-Safe Plan

## Planning Progress

| Timestamp | Role | Files inspected since last update | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-05-12 05:11:34 CEST | Planner completed | Complete draft sections, existing adjacent tests, and test/gate contract | Draft is GK-007-only. It requires a row-named exact nonce-byte tamper regression; existing invalid-base64 nonce test cannot close GK-007 as-is. | Run reviewer pass for sufficiency, stale assumptions, and scope drift. |
| 2026-05-12 05:13:59 CEST | Reviewer started | Full draft plan; mandatory section scan; `Test-Flight-Improv/test-gate-definitions.md`; `scripts/run_test_gates.sh` | Review focus: exact row ownership, source-of-truth/gate accuracy, offline replay scope, and GK-008+ exclusion. | Classify sufficiency and patch only if structural blockers exist. |
| 2026-05-12 05:13:59 CEST | Reviewer completed | Full draft plan and gate definitions | Sufficient with minor evidence-detail adjustment: named gate docs confirm `groups` is the Flutter group gate and script wins, but GK-007 expected path remains Go-only unless Dart/Flutter files change. No structural blocker. | Run arbiter classification and final stop-rule decision. |
| 2026-05-12 05:14:36 CEST | Arbiter started | Reviewer pass, closure bar, scope guard, exact gates, accepted differences | Classify reviewer findings under stop rule. | Finalize execution-ready plan if no structural blocker remains. |
| 2026-05-12 05:14:36 CEST | Arbiter completed | Reviewer findings and final plan sections | No structural blockers remain. Incremental gate evidence detail is already applied; accepted differences are documented. Stop rule says no patch loop is required. | Plan is execution-ready for GK-007 only. |

## Execution Progress

| Timestamp | Role | Files inspected or touched | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-05-12 05:17:23 CEST | Executor started | `git status --short`; `go-mknoon/node/pubsub_decryption_failure_test.go`; `go-mknoon/node/group_security_harness_test.go`; `go-mknoon/node/pubsub_delivery_test.go`; `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/pubsub.go`; plan contract | Contract extracted. Worktree has broad pre-existing dirty files, including target Go test and production files; GK-007 edits will stay scoped to the row-named test and this progress/verdict section unless the exact test proves a production defect. | Add `TestGK007NonceByteTamperFailsDecryptAndEmitsNoMessage` and run required commands. |
| 2026-05-12 05:23:31 CEST | Executor completed | `go-mknoon/node/pubsub_decryption_failure_test.go`; this plan file | Added row-named GK-007 regression plus an after-baseline event wait helper. `gofmt` completed with exit 0. Focused selector passed: `ok github.com/mknoon/go-mknoon/node 5.832s`. Race selector passed: `ok github.com/mknoon/go-mknoon/node 3.620s`. Broader Go sweep passed: `ok github.com/mknoon/go-mknoon/node 213.353s`; `ok github.com/mknoon/go-mknoon/internal 0.267s`; `ok github.com/mknoon/go-mknoon/crypto 0.606s`. `git diff --check` passed with no output. No production fallback used. | Final executor verdict: `accepted_candidate`. |

## Evidence Collector Notes

- Source matrix row `GK-007` is `P0` / `Open`: "Nonce tamper fails decrypt and emits no message." Preconditions require a valid envelope with one nonce byte changed. Expected result is AES-GCM failure with `group:decryption_failed`, not plaintext. Unit and Integration are `Required`; Fake Network is `Recommended`; 3-Party E2E is `N/A`.
- Breakdown row `GK-007` is row-owned and `implementation-ready`, with candidate production seams `go-mknoon/node/pubsub.go`, `go-mknoon/internal/group_envelope.go`, `go-mknoon/crypto/group.go`, and the offline replay companion. Its missing proof is an exact GK-007 nonce-tamper regression.
- Adjacent `GK-006` is covered/accepted by `go-mknoon/node/pubsub_decryption_failure_test.go::TestGK006TamperedCiphertextAfterSigningRejectedByValidatorAndEmitsNoMessage`. That test proves post-signing ciphertext mutation is rejected by signature validation, emits `group:validation_rejected`, and emits no receive/decrypt event. GK-007 must not reuse that signature-rejection branch because nonce is not signed.
- `go-mknoon/crypto/group.go` uses AES-256-GCM. `EncryptGroupMessage` generates a 12-byte nonce, `DecryptGroupMessage` decodes the nonce and returns `aes-gcm decrypt` on GCM authentication failure, and `BuildGroupSignatureData` signs only `groupId|epoch|ciphertext`.
- `go-mknoon/node/pubsub.go` signs and verifies only ciphertext through `BuildGroupSignatureData`, validates group membership/signature before subscription delivery, then decrypts with `env.Encrypted.Ciphertext` and `env.Encrypted.Nonce`; decrypt failures emit `group:decryption_failed` and skip `group_message:received`.
- `go-mknoon/internal/group_envelope.go` keeps ciphertext and nonce as separate v3 envelope fields; `ParseGroupEnvelope` only requires `groupId`, so missing/malformed encrypted field validation is a later row, not GK-007.
- Existing adjacent test `TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedNonce` mutates `env.Encrypted.Nonce = "tampered-nonce"`. It proves invalid nonce base64/decode failure emits `group:decryption_failed`, but it does not prove "nonce byte changed" while preserving valid base64/12-byte nonce length or the AES-GCM auth-failure branch.
- Existing direct crypto test `go-mknoon/crypto/group_test.go::TestGroupEncryptDecrypt_TamperedNonce` flips a decoded nonce byte and proves decryption fails, but it does not deliver a signed group envelope through the node subscription/event path.
- `go-mknoon/node/group_security_harness_test.go` provides `buildTestEnvelope`, `mutateGroupEnvelope`, `publishRawGroupEnvelope`, and local-node connect helpers. `go-mknoon/node/pubsub_delivery_test.go` provides `assertNoCollectedEventContainingAfter` and validator-event helpers. `go-mknoon/node/pubsub_test.go` provides `validateGroupEnvelope`.
- Offline replay uses `lib/features/groups/application/group_offline_replay_envelope.dart`, which signs hashes for ciphertext, nonce, and plaintext before Dart replay decrypt. That is a separate Dart replay envelope and does not emit the Go PubSub `group_message:received` path. It is out of scope unless GK-007 execution touches Dart offline replay or bridge serialization.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` confirm the public named gate source of truth: the script wins on disagreement, and `groups` is the Flutter group messaging gate for Dart group send/receive/retry/resume/invite/announcement behavior. GK-007 does not require that gate unless Flutter group files are touched.

## real scope

Own exactly source row GK-007: a valid signed v3 group envelope whose nonce is changed after signing must not produce plaintext and must emit `group:decryption_failed`.

In scope:

- Add or tighten one exact row-named Go node regression for decoded nonce-byte tamper, preserving valid base64 and 12 decoded nonce bytes.
- Prove the mutated envelope still passes signature validation because nonce is not signed.
- Prove the real receiver decrypt path emits `group:decryption_failed` with an AES-GCM decrypt error and no `group_message:received` or `group_reaction:received`.
- Preserve existing GK-006 and adjacent tampered ciphertext tests.

Out of scope:

- Do not update source matrix or breakdown closure rows during this planning task.
- Do not absorb GK-008+ rows, signature wrong-key behavior, deterministic signature data, missing/malformed encrypted fields, offline replay rows, key rotation, membership, Flutter UI, or simulator E2E.
- Do not change the signature-data contract to cover nonce in GK-007 unless the executor finds the row expectation is invalid and the source docs are intentionally revised in a separate task.

## closure bar

GK-007 is good enough when row-owned evidence proves:

- A valid signed group envelope is constructed with valid ciphertext, valid 12-byte nonce, and current key epoch.
- The test decodes the nonce, flips exactly one byte, re-encodes it with standard base64, and does not re-sign.
- `validateGroupEnvelope` returns `accept`, proving the current signature validator does not reject nonce mutation before decrypt.
- A real receiver processes the tampered envelope and emits `group:decryption_failed`.
- The decryption-failed payload includes the expected `groupId`, `senderId`, `keyEpoch`, `localKeyEpoch`, and a non-empty error containing `aes-gcm decrypt`.
- No `group_message:received`, `group_reaction:received`, or plaintext marker is emitted after the tampered delivery.
- Focused Go selector, focused race selector, broader Go sweep, and `git diff --check` pass or any unrelated known failures are clearly separated.

## source of truth

- Current code and tests win over stale prose.
- Source row GK-007 in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` is the row contract.
- Breakdown row/session GK-007 in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` is the session contract.
- Adjacent GK-006 closure plan/evidence is authoritative only for the ciphertext-tamper split and must not be expanded to nonce tamper.
- `go-mknoon/node/pubsub.go` owns publish, validation, subscription decrypt, and event emission.
- `go-mknoon/crypto/group.go` owns AES-GCM decrypt behavior and signature-data construction.
- `go-mknoon/internal/group_envelope.go` owns v3 envelope shape.
- `Test-Flight-Improv/test-gate-definitions.md` / `scripts/run_test_gates.sh` matter only if Flutter/Dart files are touched; exact Go commands are the primary GK-007 gates.

## session classification

implementation-ready.

The expected implementation is tests-only because current production code already routes nonce mutation to AES-GCM decrypt failure. Production changes are fallback-only if the exact row-owned regression disproves that evidence.

## exact problem statement

GK-007 is open because the repo lacks exact row-owned proof that a nonce byte mutation after signing is caught at decrypt time and never emits plaintext. The closest node test mutates the nonce into invalid base64, which proves a decode failure but not the AES-GCM authentication failure described by the row. The direct crypto test flips a nonce byte, but it does not prove node event behavior.

User-visible behavior must stay unchanged: tampered encrypted group content never renders or persists as a received plaintext group message. Diagnostic behavior for this row should be `group:decryption_failed`, not `group_message:received`.

## files and repos to inspect next

Before implementation:

- `git status --short`
- `go-mknoon/node/pubsub_decryption_failure_test.go`
- `go-mknoon/node/group_security_harness_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/crypto/group.go`
- `go-mknoon/internal/group_envelope.go`

Fallback-only if tests prove a production defect:

- `go-mknoon/crypto/group_test.go`
- `go-mknoon/internal/group_envelope_test.go`
- `lib/features/groups/application/group_offline_replay_envelope.dart`
- `test/features/groups/application/group_offline_replay_envelope_test.dart`

## existing tests covering this area

- `go-mknoon/crypto/group_test.go::TestGroupEncryptDecrypt_TamperedNonce` flips a decoded nonce byte and proves direct AES-GCM decrypt fails.
- `go-mknoon/node/pubsub_decryption_failure_test.go::TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedNonce` proves a malformed nonce string emits `group:decryption_failed`, but it is not exact GK-007 row proof.
- `go-mknoon/node/pubsub_decryption_failure_test.go::TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedCiphertext` proves a re-signed tampered ciphertext reaches AES-GCM failure.
- `go-mknoon/node/pubsub_decryption_failure_test.go::TestGK006TamperedCiphertextAfterSigningRejectedByValidatorAndEmitsNoMessage` proves post-signing ciphertext tamper is rejected by signature validation and stays separate from GK-007.
- `go-mknoon/node/pubsub_test.go::validateGroupEnvelope` tests pure validator behavior for signature and membership cases.
- `test/features/groups/application/group_offline_replay_envelope_test.dart` covers Dart offline replay signature/hash binding before decrypt; it is not Go PubSub GK-007 coverage.

Missing:

- No exact `GK-007` / row-named Go node test flips a decoded nonce byte in a valid signed envelope, proves validator acceptance, proves AES-GCM decrypt failure, and proves no receive event.

## regression/tests to add first

Add `TestGK007NonceByteTamperFailsDecryptAndEmitsNoMessage` in `go-mknoon/node/pubsub_decryption_failure_test.go`.

Preferred shape:

- Reuse `buildTestEnvelope` and `mutateGroupEnvelope`.
- Decode `env.Encrypted.Nonce` with `base64.StdEncoding.DecodeString`.
- Assert decoded nonce length is 12.
- Flip one byte, for example `nonceBytes[0] ^= 0xFF`.
- Re-encode with `base64.StdEncoding.EncodeToString`.
- Do not call `mutateAndResignGroupEnvelope`.
- Assert `validateGroupEnvelope(tamperedEnvelope, groupId, config, keyInfo) == "accept"`.
- Publish the raw envelope to a real receiving node with a collector.
- Wait for `group:decryption_failed`.
- Assert the error contains `aes-gcm decrypt` rather than only `decode nonce`.
- Assert no `group_message:received`, no `group_reaction:received`, and no plaintext marker after the baseline.

Decision on existing adjacent test:

- Do not accept `TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedNonce` as GK-007 closure as-is. It mutates the nonce to invalid base64 and is not row-named.
- Preferred implementation is to add the exact GK-007 regression and leave the existing invalid-base64 test as adjacent malformed-input coverage.
- If the executor chooses to rewrite/rename the existing test instead, it must preserve equivalent invalid-base64 coverage elsewhere or explicitly document that GK-013 owns malformed encrypted-field/base64 behavior. Adding the row-named test is the narrower and safer path.

## step-by-step implementation plan

1. Reconfirm dirty worktree state and do not overwrite unrelated edits.
2. Reopen the target test and helpers listed above; reuse local harness functions instead of adding a new harness.
3. Add `TestGK007NonceByteTamperFailsDecryptAndEmitsNoMessage` near the existing tampered nonce/ciphertext tests.
4. Build a valid signed envelope from node A to node B using a real generated group key and shared `GroupKeyInfo`.
5. Mutate only the nonce by decoding, flipping one decoded byte, and re-encoding. Do not re-sign.
6. Assert pure validator acceptance. If the validator rejects as bad signature, stop and investigate whether production or docs changed to sign nonce; do not force an AES-GCM expectation on a signature-rejection architecture without updating the row contract separately.
7. Publish the tampered envelope through the two-node local PubSub path.
8. Assert `group:decryption_failed` on node B with `groupId`, `senderId`, `keyEpoch`, `localKeyEpoch`, and `error` containing `aes-gcm decrypt`.
9. Add a baseline and quiet-window assertion for no `group_message:received`, no `group_reaction:received`, and no plaintext marker after the tampered publish.
10. Run `gofmt` on edited Go test files.
11. Run focused Go selector and race selector. If they pass, do not edit production.
12. If the test fails because decryption emits plaintext, make the smallest production fix in `go-mknoon/crypto/group.go` or `go-mknoon/node/pubsub.go` so nonce tamper fails closed, then rerun all gates.
13. If the test fails because only `decode nonce` is emitted, confirm the test really preserves valid base64/12 bytes before touching production.
14. Run the broader Go sweep and `git diff --check`.
15. After separate execution and QA evidence exists, a later closure task can update only GK-007 source matrix and GK-007 breakdown rows.

## risks and edge cases

- Invalid-base64 nonce mutation would accidentally retest the existing adjacent behavior and leave GK-007 open.
- Re-signing is unnecessary for nonce mutation because nonce is not signed; re-signing would obscure the row's signature-data assumption.
- If node A is also the receiver or the sender is skipped as self, the test may miss the receiver decrypt path. Use distinct local nodes and collect on node B.
- If the collector baseline is taken too early or too late, a prior event may be misread as the row result. Take a baseline immediately before raw publish and inspect events after that baseline.
- The expected error string should be specific enough to distinguish AES-GCM auth failure from base64 decode failure, but not so specific that it depends on the standard library's wrapped message.
- Offline replay signs `nonceHash` in Dart and may reject nonce tamper before decrypt; that is an accepted architecture difference outside GK-007's Go PubSub row unless touched.

## exact tests and gates to run

Run from `/Users/I560101/Project-Sat/mknoon-2/flutter_app`.

If editing the Go test file:

```sh
(cd go-mknoon && gofmt -w node/pubsub_decryption_failure_test.go)
```

Focused row and adjacent tamper selector:

```sh
(cd go-mknoon && go test ./node -run '^(TestGK007NonceByteTamperFailsDecryptAndEmitsNoMessage|TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedNonce|TestGK006TamperedCiphertextAfterSigningRejectedByValidatorAndEmitsNoMessage|TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedCiphertext)$' -count=1)
```

Focused race proof for the PubSub/event path:

```sh
(cd go-mknoon && go test -race ./node -run '^TestGK007NonceByteTamperFailsDecryptAndEmitsNoMessage$' -count=1)
```

Broader Go sweep:

```sh
(cd go-mknoon && go test ./node ./internal ./crypto -count=1)
```

Diff hygiene:

```sh
git diff --check
```

Conditional Flutter/offline replay only if Dart replay or bridge envelope serialization is touched:

```sh
flutter test test/features/groups/application/group_offline_replay_envelope_test.dart
```

Run `./scripts/run_test_gates.sh groups` only if execution touches Flutter group message/listener/replay files beyond the offline replay unit seam.

## known-failure interpretation

- Failure of `TestGK007NonceByteTamperFailsDecryptAndEmitsNoMessage` is row-owned and blocks GK-007 closure.
- Any `group_message:received`, `group_reaction:received`, or plaintext marker after the tampered nonce publish is a GK-007 blocker.
- A `group:decryption_failed` error containing only `decode nonce` means the test is not exact; fix the test mutation before considering production changes.
- A validator result other than `accept` means either the test mutated more than nonce or the signature contract has changed; stop and reassess the source row before implementation expands.
- Focused adjacent test failures in GK-006/tampered-ciphertext are blockers if caused by GK-007 changes.
- Existing unrelated dirty-worktree failures outside Go group envelope/signature/decryption paths should be separated and documented; do not mark GK-007 covered while the focused row proof fails.
- If the broader full Go sweep has unrelated pre-existing failures, rerun the focused selector and a row-relevant package selector, then record the exact unrelated failing tests for closure reviewer judgment.

## done criteria

- `go-mknoon/node/pubsub_decryption_failure_test.go` contains an exact row-named GK-007 regression.
- The test flips one decoded nonce byte, preserves valid base64 and 12 decoded bytes, and does not mutate ciphertext or re-sign.
- Pure validator acceptance is asserted for the tampered nonce envelope.
- Receiver emits `group:decryption_failed` with AES-GCM decrypt error metadata.
- Receiver emits no `group_message:received`, no `group_reaction:received`, and no plaintext marker for the tampered delivery.
- Existing GK-006 and adjacent tampered nonce/ciphertext tests still pass.
- Focused Go, race Go, broader Go, and `git diff --check` pass or any non-row failures are explicitly isolated.
- Source matrix and breakdown closure rows remain untouched until a later closure task has execution plus QA evidence.

## scope guard

Non-goals:

- Do not close or edit GK-008+ rows.
- Do not add wrong-public-key, signature-data determinism, missing signature, malformed encrypted-field, offline replay, simulator, or Flutter UI work.
- Do not redesign signing to include nonce in this session; that is a signature-contract change that would require a separate row/source update.
- Do not replace AES-GCM, change event names, change envelope schema, change key epoch policy, or alter membership/device validation.
- Do not create a new test harness when existing node helpers cover this path.

Overengineering:

- Property/fuzz tamper suites, all-field signature audits, 3-party E2E, and broad offline replay proof are beyond GK-007.
- Broad source-matrix/breakdown closure edits during planning are out of scope.

## accepted differences / intentionally out of scope

- Live Go PubSub signatures currently cover ciphertext but not nonce. GK-007 intentionally proves the accepted current behavior: validator accepts nonce mutation and AES-GCM decrypt catches it.
- Offline replay's Dart envelope signs hashes including `nonceHash`, so nonce tamper there may fail before decrypt. That difference is accepted and out of scope for this Go PubSub row.
- GK-006's signature-rejection branch for ciphertext mutation is closed separately and should remain unchanged.
- 3-Party E2E is `N/A` for this row; a two-node Go PubSub host test supplies required integration evidence.

## dependency impact

Closing GK-007 unblocks GK-008 in the ordered P0 flow. If GK-007 execution reveals nonce is now signed or should be signed, GK-009 signature-data determinism and later signature-contract rows need separate review before closure docs change.

If production code must change to keep nonce tamper from emitting plaintext, later malformed-envelope and offline replay rows should be revisited only for regression impact, not absorbed into GK-007.

## Reviewer Pass

Sufficiency: sufficient with minor evidence-detail adjustment.

Missing files, tests, regressions, or gates: none after adding gate-definition evidence to the notes. The plan names the source row, breakdown row, GK-006 adjacent evidence, exact Go files, exact row-named regression, focused selector, race selector, broader Go sweep, conditional Flutter replay test, and `git diff --check`.

Stale or incorrect assumptions: none found. Current code signs ciphertext but not nonce, so nonce mutation should pass validation and fail at AES-GCM decrypt. The plan includes a stop point if that assumption is disproven.

Overengineering: none found. The plan avoids GK-008+, signature determinism, malformed envelopes, offline replay, Flutter UI, and 3-party E2E.

Decomposition: sufficient. Implementation is one narrow regression first, with production fallback only if the regression exposes a real defect.

Minimum needed: no structural patch required; proceed to arbiter.

## Arbiter Decision

Structural blockers: none.

Incremental details: gate-definition evidence was added during reviewer pass. No further incremental detail is required before implementation.

Accepted differences: Go PubSub nonce tamper is expected to pass signature validation and fail at AES-GCM decrypt because nonce is not signed; Dart offline replay signs `nonceHash` and may reject earlier; GK-006 ciphertext signature rejection is already closed separately.

Stop rule: no structural blocker remains, so the plan is execution-ready and no additional reviewer/arbiter loop is required.

## Final Plan Verdict

Execution-ready for GK-007 only.

The implementation should start with `TestGK007NonceByteTamperFailsDecryptAndEmitsNoMessage` and stop without production edits if the exact row-owned regression passes against current code. Closure docs and source matrix rows must wait for a separate execution plus QA closure task.

## Final Execution Verdict

`accepted_candidate`

GK-007 execution added `TestGK007NonceByteTamperFailsDecryptAndEmitsNoMessage` in `go-mknoon/node/pubsub_decryption_failure_test.go`. The test builds a valid signed two-node group envelope, flips exactly one decoded 12-byte nonce byte, keeps the signature and ciphertext unchanged, proves pure validator acceptance, publishes through local PubSub, observes `group:decryption_failed` with `aes-gcm decrypt`, and asserts no post-baseline `group_message:received`, `group_reaction:received`, or plaintext marker.

Required command results:

- `(cd go-mknoon && gofmt -w node/pubsub_decryption_failure_test.go)` -> exit 0, no output.
- `(cd go-mknoon && go test ./node -run '^(TestGK007NonceByteTamperFailsDecryptAndEmitsNoMessage|TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedNonce|TestGK006TamperedCiphertextAfterSigningRejectedByValidatorAndEmitsNoMessage|TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedCiphertext)$' -count=1)` -> `ok github.com/mknoon/go-mknoon/node 5.832s`.
- `(cd go-mknoon && go test -race ./node -run '^TestGK007NonceByteTamperFailsDecryptAndEmitsNoMessage$' -count=1)` -> `ok github.com/mknoon/go-mknoon/node 3.620s`.
- `(cd go-mknoon && go test ./node ./internal ./crypto -count=1)` -> `ok github.com/mknoon/go-mknoon/node 213.353s`; `ok github.com/mknoon/go-mknoon/internal 0.267s`; `ok github.com/mknoon/go-mknoon/crypto 0.606s`.
- `git diff --check` -> exit 0, no output.

Pre-existing failures encountered: none in the required commands.

## QA Reviewer Pass

2026-05-12 05:30:50 CEST - Independent QA result: `passed`.

Scope reviewed: GK-007 only. Source matrix and session breakdown were not updated. Existing unrelated dirty files were preserved.

Files/helpers inspected: `go-mknoon/node/pubsub_decryption_failure_test.go` lines 14-31 and 345-450; `go-mknoon/node/group_security_harness_test.go` lines 70-84 and 125-139; `go-mknoon/node/pubsub_test.go` lines 722-769; `go-mknoon/node/pubsub_delivery_test.go` lines 1304-1317; `go-mknoon/node/pubsub.go` lines 582-614 and 887-952; `go-mknoon/crypto/group.go` lines 63-110; `go-mknoon/internal/group_envelope.go` lines 8-68.

Behavior confirmed: `TestGK007NonceByteTamperFailsDecryptAndEmitsNoMessage` decodes the nonce, requires exactly 12 bytes, flips exactly one decoded byte, re-encodes with standard base64, preserves ciphertext and signature, does not re-sign, asserts `validateGroupEnvelope(...) == "accept"`, publishes the raw envelope to node B, observes `group:decryption_failed` with `aes-gcm decrypt`, and asserts no post-baseline `group_message:received`, `group_reaction:received`, or plaintext marker.

Blocking findings: none.

Required reruns:

- `(cd go-mknoon && go test ./node -run '^(TestGK007NonceByteTamperFailsDecryptAndEmitsNoMessage|TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedNonce|TestGK006TamperedCiphertextAfterSigningRejectedByValidatorAndEmitsNoMessage|TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedCiphertext)$' -count=1)` -> `ok github.com/mknoon/go-mknoon/node 5.839s`.
- `(cd go-mknoon && go test -race ./node -run '^TestGK007NonceByteTamperFailsDecryptAndEmitsNoMessage$' -count=1)` -> `ok github.com/mknoon/go-mknoon/node 3.652s`.
- `(cd go-mknoon && go test ./node ./internal ./crypto -count=1)` -> `ok github.com/mknoon/go-mknoon/node 210.756s`; `ok github.com/mknoon/go-mknoon/internal 0.640s`; `ok github.com/mknoon/go-mknoon/crypto 0.384s`.
- `git diff --check` -> exit 0, no output.

## Closure Note

2026-05-12 05:36 CEST - `accepted/closed`. Source matrix GK-007 and session-breakdown GK-007 rows were updated to `Covered`/`covered/accepted` using the execution and independent QA evidence recorded above. The accepted proof is `TestGK007NonceByteTamperFailsDecryptAndEmitsNoMessage`: it flips one decoded 12-byte nonce byte, preserves valid base64/ciphertext/signature, does not re-sign, proves validator acceptance, publishes through the real two-node PubSub path, observes `group:decryption_failed` with `aes-gcm decrypt`, and emits no post-baseline receive/reaction/plaintext marker. No production code changed; GK-008 remains the next unresolved P0 continuation.
