Status: accepted/closed

# Private Group Chat Reliability Matrix COMPLETE 1 - Session GK-011 Plan

## Planning Progress

- 2026-05-12 07:39:25 CEST - Planner completed. Files inspected since last update: draft plan sections and evidence summary. Decision/blocker: draft includes code/test proof, exact commands, known-failure interpretation, and GK-010/GK-012+ exclusions. Next action: run reviewer sufficiency pass.
- 2026-05-12 07:39:25 CEST - Reviewer started. Files inspected since last update: full draft plan. Decision/blocker: review for missing mandatory sections, stale assumptions, overbroad files, and gate sufficiency. Next action: record reviewer findings.
- 2026-05-12 07:40:10 CEST - Reviewer completed. Files inspected since last update: full draft plan, mandatory-section checklist, current validator order, source-row allowed reasons, and exact command list. Decision/blocker: sufficient as-is; no structural blockers found. Next action: run arbiter classification and stop-rule decision.
- 2026-05-12 07:40:30 CEST - Arbiter started. Files inspected since last update: reviewer findings and full draft plan. Decision/blocker: classify reviewer output into structural blockers, incremental details, and accepted differences. Next action: write final arbiter decision.
- 2026-05-12 07:40:51 CEST - Arbiter completed. Files inspected since last update: reviewer findings, mandatory sections, and final planning output. Decision/blocker: no structural blockers; stop rule met with no patch loop. Next action: plan is execution-ready for GK-011.

## Execution Progress

- 2026-05-12 07:44:09 CEST - Executor started/contract extracted. Files inspected since last update: this GK-011 plan, skill execution contract, `git status --short`, `go-mknoon/node/pubsub.go`, and `go-mknoon/node/pubsub_test.go` diffs. Decision/blocker: execution is safe and narrow; intended files are already dirty with unrelated GM/GK work, so GK-011 will preserve existing diffs and make only additive/minimal changes. Next action: add row-owned GK-011 tests first.
- 2026-05-12 07:45:23 CEST - Regression-first focused command completed. Files touched since last update: `go-mknoon/node/pubsub_test.go`. Command: `(cd go-mknoon && go test ./node -run '^(TestGK011ValidateGroupEnvelopeRejectsMissingSenderIDAsInvalidEnvelope|TestGK011GroupTopicValidatorRejectsMissingSenderIDAsInvalidEnvelopeNoPanic)$' -count=1)`. Decision/blocker: expected RED confirmed; omitted `senderId` rejects as `peer_mismatch` and real validator emits `group:validation_rejected` reason `peer_mismatch`, not `invalid_envelope`. Next action: add minimal post-parse SenderId guard in production and mirror it in the pure validator helper.
- 2026-05-12 07:45:57 CEST - Executor implementation completed and gofmt applied. Files touched since last update: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`. Decision/blocker: added post-parse `strings.TrimSpace(env.SenderId) == ""` rejection as `invalid_envelope` in production and mirrored it in `validateGroupEnvelopeForTransportPeer`; added structured JSON field deletion helper and exact GK-011 tests. Next action: run required focused, adjacent, broader, race, and diff hygiene commands.
- 2026-05-12 07:45:59 CEST - Required focused command passed. Command: `(cd go-mknoon && go test ./node -run '^(TestGK011ValidateGroupEnvelopeRejectsMissingSenderIDAsInvalidEnvelope|TestGK011GroupTopicValidatorRejectsMissingSenderIDAsInvalidEnvelopeNoPanic)$' -count=1)`. Result: `ok github.com/mknoon/go-mknoon/node 0.517s`. Next action: run adjacent parser/validator sweep.
- 2026-05-12 07:46:02 CEST - Required adjacent parser/validator sweep passed. Command: `(cd go-mknoon && go test ./node ./internal -run '^(TestGK011ValidateGroupEnvelopeRejectsMissingSenderIDAsInvalidEnvelope|TestGK011GroupTopicValidatorRejectsMissingSenderIDAsInvalidEnvelopeNoPanic|TestGroupTopicValidator_InvalidJSON|TestGroupTopicValidator_UnknownGroup|TestGroupTopicValidator_UnauthorizedSender|TestGroupTopicValidator_BadSignature|TestGroupTopicValidator_RejectsUnauthorizedEventFamiliesBeforeForward|TestGK010ParseGroupEnvelopeRejectsMissingGroupID|TestParseGroupEnvelope_MissingFields|TestMarshalParseGroupEnvelope_RoundTrip|TestIsGroupEnvelope_V3GroupMessage|TestIsGroupEnvelope_InvalidJSON)$' -count=1)`. Result: `ok github.com/mknoon/go-mknoon/node 0.344s`; `ok github.com/mknoon/go-mknoon/internal 0.580s`. Next action: run broader Go row sweep.
- 2026-05-12 07:46:08 CEST - Required broader Go row sweep passed. Command: `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK011|TestGK010' -count=1)`. Result: `ok github.com/mknoon/go-mknoon/node 4.347s`; `ok github.com/mknoon/go-mknoon/internal 0.756s`; `ok github.com/mknoon/go-mknoon/crypto 0.623s`. Next action: run race-recommended focused command.
- 2026-05-12 07:46:13 CEST - Race-recommended focused command passed. Command: `(cd go-mknoon && go test -race ./node -run '^(TestGK011ValidateGroupEnvelopeRejectsMissingSenderIDAsInvalidEnvelope|TestGK011GroupTopicValidatorRejectsMissingSenderIDAsInvalidEnvelopeNoPanic)$' -count=1)`. Result: `ok github.com/mknoon/go-mknoon/node 1.523s`. Next action: run diff hygiene.
- 2026-05-12 07:47:11 CEST - Diff hygiene passed and final Executor verdict written. Command: `git diff --check`. Result: no output, exit 0. Decision/blocker: no blockers remain for the Executor-scoped GK-011 plan; source matrix and session breakdown closure rows intentionally unchanged. Next action: hand off final result.
- 2026-05-12 07:51:10 CEST - QA Reviewer completed. Files inspected since last update: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, source matrix GK-010/GK-011/GK-012+ rows, session-breakdown GK-010/GK-011/GK-012+ rows, scoped diffs, and this plan. Commands rerun independently: focused GK-011 selector, adjacent parser/validator sweep, broader Go row sweep, focused race selector, and `git diff --check`. Results: `ok github.com/mknoon/go-mknoon/node 0.427s`; `ok github.com/mknoon/go-mknoon/node 0.334s`; `ok github.com/mknoon/go-mknoon/internal 0.470s`; `ok github.com/mknoon/go-mknoon/node 4.455s`; `ok github.com/mknoon/go-mknoon/internal 0.176s`; `ok github.com/mknoon/go-mknoon/crypto 0.249s`; `ok github.com/mknoon/go-mknoon/node 1.429s`; `git diff --check` no output, exit 0. Decision/blocker: accepted; no blocking or non-blocking QA findings. Source matrix/breakdown closure rows remain unchanged for GK-011, GK-010 remains closed, and GK-012+ remain untouched. Next action: report QA verdict.
- 2026-05-12 07:58:20 CEST - Closure Writer completed. Files inspected since last update: source matrix GK-011/GK-012 rows, breakdown current update and GK-011 ledger rows, accepted GK-011 plan evidence, and final-program-verdict search. Files touched since last update: source matrix, session breakdown, and this plan. Decision/blocker: closure docs accepted for the completed row; row-owned evidence now lives in the source matrix, breakdown, and Closure Note. Next action: run stale-state and diff-hygiene verification.

## Final Execution Verdict

- Final verdict: accepted.
- Files changed for GK-011: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, and this GK-011 plan.
- Tests added: `TestGK011ValidateGroupEnvelopeRejectsMissingSenderIDAsInvalidEnvelope` and `TestGK011GroupTopicValidatorRejectsMissingSenderIDAsInvalidEnvelopeNoPanic`.
- Production behavior change: after `ParseGroupEnvelope` succeeds, missing or whitespace-only `SenderId` now rejects as `invalid_envelope` before group-id, transport-peer, member, device, writer, key, signature, decrypt, or receive handling.
- Required evidence: regression-first focused command failed for the expected pre-fix `peer_mismatch`; all required post-fix focused, adjacent, broader, race, and diff hygiene commands passed.
- Blockers remaining: none.

## Final QA Verdict

- QA verdict: accepted.
- Blocking issues: none.
- Non-blocking follow-ups: none.
- Scope result: production guard rejects omitted, blank, or whitespace-only `SenderId` as `invalid_envelope` immediately after `ParseGroupEnvelope` and before group-id, transport-peer, member, device, signature, decrypt, or receive handling; `validateGroupEnvelopeForTransportPeer` mirrors the same guard.
- Test result: exact GK-011 pure and real-validator tests are present, delete the `senderId` key through structured JSON mutation, use a non-empty transport peer, call the real `groupTopicValidator`, include an explicit panic guard, and observe `group:validation_rejected` reason `invalid_envelope`.
- Documentation state: source matrix GK-011 is now `Covered`; breakdown GK-011 rows are `covered/accepted`; GK-010 remains closed, and GK-012+ remain untouched.
- Required QA commands: focused, adjacent, broader, race, and diff hygiene commands all passed on the independent QA rerun.

## Closure Note

- Closure status: accepted/closed.
- Closure evidence: source matrix GK-011 is `Covered`; breakdown GK-011 inventory, disposition, session ledger row 62, ordered session row 62, and session closure ledger record `covered/accepted`.
- Landed proof: `go-mknoon/node/pubsub.go` rejects omitted, blank, or whitespace-only `SenderId` as `invalid_envelope` immediately after `ParseGroupEnvelope`, and `validateGroupEnvelopeForTransportPeer` mirrors the production guard.
- Tests: `go-mknoon/node/pubsub_test.go::TestGK011ValidateGroupEnvelopeRejectsMissingSenderIDAsInvalidEnvelope` and `TestGK011GroupTopicValidatorRejectsMissingSenderIDAsInvalidEnvelopeNoPanic` delete the JSON `senderId` key through structured JSON mutation, use a non-empty transport peer, run the real validator, include a panic guard, and observe `group:validation_rejected` reason `invalid_envelope`.
- Validation: regression-first focused evidence first failed as `peer_mismatch`; executor, QA, and fresh audit reruns passed the focused, adjacent, broader, race, and `git diff --check` commands recorded above.
- Accepted differences: GK-011 closes on `invalid_envelope` rather than `non_member`; `ParseGroupEnvelope` remains groupId-only for this row.
- Residual-only: none for GK-011. GK-012 remains the next unresolved P0 row.

## Evidence Summary

- Source matrix row `GK-011` is now `Covered` and says: "Envelope parser/validator rejects missing senderId." Preconditions are an envelope with no `senderId`; steps deliver the envelope, run the validator, and inspect the reason; expected result is rejection as `non_member` or `invalid_envelope` with no panic. Unit and integration are `Required`, race is `Recommended`, and the closure evidence is the row-named node validator proof plus executor, QA, fresh-audit, race, and diff-hygiene proof.
- Session breakdown row `GK-011` is `needs_code_and_tests` / `covered/accepted` and owns exactly GK-011. It records `go-mknoon/node/pubsub.go` as the production evidence surface and `go-mknoon/node/pubsub_test.go` as the row-owned test evidence surface.
- GK-010 is closed and out of scope. Its plan and matrix row prove missing `groupId` parser behavior only; they explicitly leave missing `senderId` to GK-011.
- `go-mknoon/internal/group_envelope.go::ParseGroupEnvelope` still unmarshals JSON and only rejects missing `GroupId`; GK-011 intentionally keeps missing or blank `SenderId` as validator-owned structural validation.
- `go-mknoon/node/pubsub.go::groupTopicValidator` now calls `IsGroupEnvelope`, `ParseGroupEnvelope`, then rejects `strings.TrimSpace(env.SenderId) == ""` as `invalid_envelope` before group id match, transport-peer binding, config lookup, membership lookup, device binding, writer check, key lookup, or signature verification.
- `go-mknoon/node/pubsub.go::groupEnvelopeMatchesTransportPeer` remains the nonblank claimed-sender transport binding check; GK-011 proof prevents omitted sender identity from reaching that path.
- `go-mknoon/node/pubsub.go::findMember` still trims peer IDs and returns nil for blank or whitespace peer IDs, but GK-011 closure no longer depends on that downstream safety net.
- `go-mknoon/node/pubsub_test.go::validateGroupEnvelopeForTransportPeer` mirrors the production missing-`SenderId` guard and returns `reject:invalid_envelope`.
- `go-mknoon/node/pubsub_test.go::buildTestEnvelope` can create a valid signed envelope, but because `GroupEnvelope.SenderId` has no `omitempty`, setting `SenderId` to `""` still serializes a `senderId` key. The GK-011 precondition requires deleting the JSON field with structured JSON map mutation.
- `go-mknoon/node/group_security_harness_test.go::mutateGroupEnvelope` parses to `GroupEnvelope` and re-marshals, so it cannot produce an omitted `senderId` field by itself.
- The worktree is already dirty with many modified and untracked files. GK-011 execution must preserve unrelated edits and touch only the row-owned files unless fresh evidence shows an unavoidable direct dependency.

## real scope

Own exactly source matrix row GK-011: a v3 group envelope with `version`, `type`, matching `groupId`, valid encrypted payload/signature material, and no JSON `senderId` field must be rejected before membership, device, writer, signature, decrypt, or receive handling can accept it or panic.

In scope for execution:

- Add a row-owned failing regression in `go-mknoon/node/pubsub_test.go` that constructs a valid signed group envelope, deletes the JSON `senderId` key, proves it is still recognized as a v3 group envelope, and expects `validateGroupEnvelopeForTransportPeer(...) == "reject:invalid_envelope"`.
- Add a row-owned real validator regression in `go-mknoon/node/pubsub_test.go` that calls `Node.groupTopicValidator(...)` with the same omitted-`senderId` envelope, asserts `pubsub.ValidationReject`, observes `group:validation_rejected` reason `invalid_envelope`, and proves no panic.
- Add the smallest production guard in `go-mknoon/node/pubsub.go` so parsed envelopes with `strings.TrimSpace(env.SenderId) == ""` reject as `invalid_envelope` before `groupEnvelopeMatchesTransportPeer`, `findMember`, `activeMemberDeviceForEnvelope`, `isAllowedWriter`, or signature verification.
- Mirror that guard in the pure test helper `validateGroupEnvelopeForTransportPeer` so focused tests stay aligned with production validator order.
- Add a small test helper, if needed, to delete a top-level envelope JSON field via `encoding/json` map unmarshal/delete/marshal instead of string replacement.

Out of scope:

- Do not reopen or change GK-010 missing-`groupId` behavior.
- Do not implement GK-012 missing-signature, GK-013 missing-encrypted-fields, GK-014 version/type matrix, GK-015 group mismatch, GK-026 sender tamper, or any later GK row.
- Do not change encryption, signature data, key-epoch grace, device binding, discovery, offline replay, Flutter/Dart group behavior, or relay behavior unless the GK-011 tests expose a direct contradiction.
- Do not update matrix or breakdown closure rows during implementation unless the caller explicitly asks for closure documentation after tests pass.

## closure bar

GK-011 is good enough when:

- The repo has exact row-owned tests named with `GK011`.
- A JSON envelope with the `senderId` key omitted, not merely set to an empty string, is rejected deterministically.
- The pure validator and real `groupTopicValidator` both reject the omitted sender before transport binding can produce `peer_mismatch`.
- The observable real-validator reason is `invalid_envelope`, which is one of the source-row allowed outcomes.
- Test completion and an explicit panic guard prove "no panic."
- GK-010 remains closed and untouched except for read-only evidence.
- The required focused Go tests, adjacent parser/validator sweep, broader Go sweep, and diff hygiene command pass or have isolated pre-existing failures recorded.

## source of truth

- Primary row contract: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GK-011`.
- Session contract: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` row/session `GK-011`.
- Current production behavior: `go-mknoon/node/pubsub.go` and `go-mknoon/internal/group_envelope.go`.
- Current direct tests and helpers: `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/group_security_harness_test.go`, and `go-mknoon/internal/group_envelope_test.go`.
- Gate source: `Test-Flight-Improv/test-gate-definitions.md`; if it disagrees with `scripts/run_test_gates.sh`, the script wins.
- On disagreement, current code and direct tests beat stale prose, but the GK-011 row controls scope and acceptable rejection outcomes.

## session classification

accepted/closed.

The session is closed as implementation-committed gap closure because the row-named regressions were added, the production validator now rejects omitted/blank sender identity as `invalid_envelope`, and the source matrix plus breakdown now carry concrete `Covered` / `covered/accepted` evidence.

## exact problem statement

GK-011 is closed because the repository now has a direct contract for envelopes that omit `senderId`.

Parser behavior still allows such envelopes because `ParseGroupEnvelope` only checks `groupId`; that is accepted because the source row says validator coverage is required. Before the GK-011 guard, validation was fail-closed but path-dependent: the pure helper could reach `reject:non_member`, while the real validator with a non-empty pubsub peer rejected earlier as `peer_mismatch`. The accepted row behavior is now stable `invalid_envelope` before those downstream paths.

User-visible behavior protected by this row: malformed group envelopes without a sender identity are classified as invalid input and never proceed to membership, device, signature, decrypt, or receive-event processing.

What must stay unchanged: valid group messages and reactions, GK-010 missing-`groupId` parser rejection, unknown-group rejection, group mismatch rejection, transport-peer mismatch rejection for nonblank claimed senders, non-member rejection for nonblank unauthorized senders, and existing signature/key behavior.

## files and repos to inspect next

Before editing, re-run `git status --short` and inspect current diffs for intended write files because this worktree is already dirty.

Production:

- `go-mknoon/node/pubsub.go`
- `go-mknoon/internal/group_envelope.go` only to confirm parser behavior stays compatible; do not edit unless fresh evidence proves validator-only guarding cannot satisfy GK-011.

Tests/helpers:

- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/group_security_harness_test.go`
- `go-mknoon/internal/group_envelope_test.go`
- `go-mknoon/node/pubsub_delivery_test.go` for `waitForCollectedValidationReject`
- `go-mknoon/node/node_test.go` for `testEventCollector`

Docs/gates:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `README.md` Go test/build notes

## existing tests covering this area

- `go-mknoon/internal/group_envelope_test.go::TestGK010ParseGroupEnvelopeRejectsMissingGroupID` covers missing `groupId` only.
- `go-mknoon/internal/group_envelope_test.go::TestParseGroupEnvelope_MissingFields` covers missing `groupId` only and is not a sender test.
- `go-mknoon/node/pubsub_test.go::TestGroupTopicValidator_InvalidJSON` covers non-v3 invalid JSON.
- `go-mknoon/node/pubsub_test.go::TestGroupTopicValidator_UnknownGroup` covers nil config after a parseable envelope.
- `go-mknoon/node/pubsub_test.go::TestGroupTopicValidator_UnauthorizedSender` covers a nonblank sender that is not a member.
- `go-mknoon/node/pubsub_test.go::TestGroupTopicValidator_BadSignature` and spoofing tests cover bad member keys/signatures after sender/member lookup.
- `go-mknoon/node/pubsub_test.go::TestGroupTopicValidator_RejectsUnauthorizedEventFamiliesBeforeForward` covers real validator rejection for removed non-members across message families.
- `go-mknoon/node/pubsub_test.go::TestGM028EmptyPeerIDDoesNotInflateDiscoveryOrPublishPreflight` proves blank peer IDs are trimmed/rejected in member lookup and config normalization, but it is not an envelope-validator proof and does not pin GK-011.

Missing:

- No exact `GK-011` test builds a v3-looking group envelope with the `senderId` key omitted.
- No test asserts the pure validator returns `reject:invalid_envelope` before transport binding or membership lookup for missing sender identity.
- No test asserts the real `groupTopicValidator` emits `group:validation_rejected` reason `invalid_envelope` and does not panic for omitted `senderId`.

## regression/tests to add first

Add these tests before production changes and confirm they fail for the expected current reason. Keep them in `go-mknoon/node/pubsub_test.go`.

1. `TestGK011ValidateGroupEnvelopeRejectsMissingSenderIDAsInvalidEnvelope`

Build a valid signed envelope:

```go
privB64, pubB64 := generateEd25519KeyPair(t)
groupKey, err := mcrypto.GenerateGroupKey()
groupId := "group-gk-011"
senderId := "sender-gk-011"
keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
config := &GroupConfig{
    Name: "GK-011",
    GroupType: GroupTypeChat,
    Members: []GroupMember{{PeerId: senderId, Role: GroupRoleAdmin, PublicKey: pubB64}},
    CreatedBy: senderId,
}
validEnvelope := buildTestEnvelope(t, groupId, senderId, privB64, pubB64, groupKey, keyInfo.KeyEpoch, "missing sender id")
missingSenderEnvelope := deleteGroupEnvelopeJSONField(t, validEnvelope, "senderId")
```

Then assert:

- The decoded JSON has no `senderId` key.
- `internal.IsGroupEnvelope(missingSenderEnvelope)` is true.
- `internal.ParseGroupEnvelope(missingSenderEnvelope)` returns a non-nil envelope with `SenderId == ""` and nil error unless implementation-time evidence has already moved this to parser rejection.
- `validateGroupEnvelopeForTransportPeer(missingSenderEnvelope, groupId, config, keyInfo, senderId)` returns `reject:invalid_envelope`.

Expected pre-fix failure: current code likely returns `reject:peer_mismatch` on the non-empty transport path, or `reject:non_member` if the test accidentally uses blank transport. The test must use non-empty transport to match the live validator path.

2. `TestGK011GroupTopicValidatorRejectsMissingSenderIDAsInvalidEnvelopeNoPanic`

Use the same envelope construction and deletion helper. Configure a node without starting libp2p:

```go
collector := &testEventCollector{}
n := New(collector)
n.groupConfigs = map[string]*GroupConfig{groupId: config}
n.groupKeys = map[string]*GroupKeyInfo{groupId: keyInfo}
validator := n.groupTopicValidator(groupId)
msg := &pubsub.Message{Message: &pb.Message{Data: []byte(missingSenderEnvelope)}}
```

Then assert:

- Wrap the validator call with a `defer`/`recover` check so panic is an explicit test failure.
- `validator(context.Background(), peer.ID(senderId), msg)` returns `pubsub.ValidationReject`.
- `waitForCollectedValidationReject(t, collector, 0, "invalid_envelope", keyInfo.KeyEpoch, time.Second)` observes the emitted rejection reason.

Helper to add if none exists:

```go
func deleteGroupEnvelopeJSONField(t *testing.T, envelopeJSON string, field string) string {
    t.Helper()
    var raw map[string]interface{}
    if err := json.Unmarshal([]byte(envelopeJSON), &raw); err != nil {
        t.Fatalf("unmarshal envelope: %v", err)
    }
    delete(raw, field)
    mutated, err := json.Marshal(raw)
    if err != nil {
        t.Fatalf("marshal envelope without %s: %v", field, err)
    }
    return string(mutated)
}
```

Place this helper near `buildTestEnvelope` / validator helpers and keep it generic enough for later rows, but do not use it to implement GK-012+ in this session.

## step-by-step implementation plan

1. Re-check `git status --short` and inspect diffs for `go-mknoon/node/pubsub.go` and `go-mknoon/node/pubsub_test.go`. Preserve unrelated edits.
2. Add `TestGK011ValidateGroupEnvelopeRejectsMissingSenderIDAsInvalidEnvelope`, `TestGK011GroupTopicValidatorRejectsMissingSenderIDAsInvalidEnvelopeNoPanic`, and the structured JSON deletion helper in `go-mknoon/node/pubsub_test.go`.
3. Run the focused GK-011 selector and confirm it fails for the expected current gap: `reject:peer_mismatch` or `reject:non_member` instead of `reject:invalid_envelope`, or a missing rejection event reason. If the tests already pass because another user has added the explicit guard, stop before adding duplicate production code and proceed to verification.
4. In `go-mknoon/node/pubsub.go`, add a minimal helper or inline guard immediately after `ParseGroupEnvelope` succeeds and before the group-id/transport checks:

```go
if strings.TrimSpace(env.SenderId) == "" {
    n.logPubSubValidationReject("invalid_envelope", groupId, pid, env)
    return pubsub.ValidationReject
}
```

If adding a helper, keep it narrow, for example:

```go
func groupEnvelopeHasSenderId(env *internal.GroupEnvelope) bool {
    return env != nil && strings.TrimSpace(env.SenderId) != ""
}
```

5. Mirror the same guard in `go-mknoon/node/pubsub_test.go::validateGroupEnvelopeForTransportPeer` immediately after parse succeeds and before `env.GroupId != groupId` or `groupEnvelopeMatchesTransportPeer(...)`.
6. Do not change `go-mknoon/internal/group_envelope.go` unless the tests prove validator-only guarding cannot produce the source-row outcome. The preferred GK-011 outcome is validator-level `invalid_envelope`, not broad parser required-field expansion.
7. Run `gofmt` on touched Go files.
8. Run focused, adjacent, broader, and race-recommended commands listed below.
9. Review `git diff -- go-mknoon/node/pubsub.go go-mknoon/node/pubsub_test.go` and confirm the only production behavior change is the missing/blank `SenderId` validator guard.
10. Stop after code and test proof. Do not update GK-011 closure docs unless explicitly requested after implementation.

## risks and edge cases

- Omitted JSON key versus empty string: the row precondition is no `senderId`, so the test must delete the JSON field. The production guard should also reject empty or whitespace `senderId` because JSON unmarshal maps both omitted and empty string to `""`.
- Real validator path: without an explicit guard, missing `senderId` can reject as `peer_mismatch` before membership lookup. That does not match the allowed row reasons and hides the structural-envelope failure.
- Blank member records: current `findMember` trims blank peer IDs and returns nil, and config normalization has tests for blank peers, but GK-011 should not depend on those downstream protections.
- Parser blast radius: adding sender validation inside `ParseGroupEnvelope` may affect later malformed-envelope rows and helpers that intentionally parse then mutate. Prefer validator guard unless implementation-time evidence proves parser enforcement is already the active design.
- Signature data does not include `senderId`, but GK-011 is missing sender, not tampered sender. GK-026 owns sender tamper attribution.
- Device binding should not run for omitted sender identity. GK-027 owns sender device binding tamper.
- There is no offline/restart behavior in this row. Do not add simulator, relay, database, or Flutter state work for GK-011.

## exact tests and gates to run

Regression-first expected red command:

```bash
(cd go-mknoon && go test ./node -run '^(TestGK011ValidateGroupEnvelopeRejectsMissingSenderIDAsInvalidEnvelope|TestGK011GroupTopicValidatorRejectsMissingSenderIDAsInvalidEnvelopeNoPanic)$' -count=1)
```

After implementation, required focused command:

```bash
(cd go-mknoon && go test ./node -run '^(TestGK011ValidateGroupEnvelopeRejectsMissingSenderIDAsInvalidEnvelope|TestGK011GroupTopicValidatorRejectsMissingSenderIDAsInvalidEnvelopeNoPanic)$' -count=1)
```

Required adjacent validator/parser sweep:

```bash
(cd go-mknoon && go test ./node ./internal -run '^(TestGK011ValidateGroupEnvelopeRejectsMissingSenderIDAsInvalidEnvelope|TestGK011GroupTopicValidatorRejectsMissingSenderIDAsInvalidEnvelopeNoPanic|TestGroupTopicValidator_InvalidJSON|TestGroupTopicValidator_UnknownGroup|TestGroupTopicValidator_UnauthorizedSender|TestGroupTopicValidator_BadSignature|TestGroupTopicValidator_RejectsUnauthorizedEventFamiliesBeforeForward|TestGK010ParseGroupEnvelopeRejectsMissingGroupID|TestParseGroupEnvelope_MissingFields|TestMarshalParseGroupEnvelope_RoundTrip|TestIsGroupEnvelope_V3GroupMessage|TestIsGroupEnvelope_InvalidJSON)$' -count=1)
```

Required broader Go row sweep:

```bash
(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK011|TestGK010' -count=1)
```

Race-recommended focused command:

```bash
(cd go-mknoon && go test -race ./node -run '^(TestGK011ValidateGroupEnvelopeRejectsMissingSenderIDAsInvalidEnvelope|TestGK011GroupTopicValidatorRejectsMissingSenderIDAsInvalidEnvelopeNoPanic)$' -count=1)
```

Diff hygiene:

```bash
gofmt -w go-mknoon/node/pubsub.go go-mknoon/node/pubsub_test.go
git diff --check
```

Named Flutter gates are not required for a Go-only validator guard. If implementation touches `lib/features/groups/application/group_offline_replay_envelope.dart` despite this plan's scope guard, also run:

```bash
flutter test test/features/groups/application/group_offline_replay_envelope_test.dart
./scripts/run_test_gates.sh completeness-check
```

## known-failure interpretation

- The regression-first GK-011 focused command is expected to fail before production changes if it gets `reject:peer_mismatch` or `reject:non_member` instead of `reject:invalid_envelope`. That is the row-owned gap.
- After implementation, any failure in either `TestGK011...` test is row-owned and blocks closure.
- If `internal.ParseGroupEnvelope` already rejects missing `senderId` because another user has changed parser behavior before implementation starts, treat that as compatible only if both GK-011 tests can be adjusted to expect `reject:invalid_envelope` without adding duplicate production code. Do not broaden parser behavior further.
- If adjacent existing tests fail after adding the guard, inspect whether the failure involves a blank/whitespace sender. If yes, it is likely row-owned. If unrelated, record exact package/test names and preserve scope.
- If the broader Go row sweep fails in unrelated packages or tests that are already dirty, document the exact failing tests and rerun the focused GK-011 selector. Do not expand GK-011 into unrelated failures.
- `git diff --check` failures in `go-mknoon/node/pubsub.go` or `go-mknoon/node/pubsub_test.go` are row-owned. Failures in unrelated dirty files should be recorded separately and not fixed under GK-011 without explicit approval.

## done criteria

- `go-mknoon/node/pubsub_test.go` contains exact `GK011` pure and real-validator tests using a JSON envelope with the `senderId` key omitted.
- `go-mknoon/node/pubsub.go` rejects missing or whitespace `SenderId` as `invalid_envelope` immediately after parse and before transport/member/device/signature/decrypt handling, unless an equivalent guard already exists by implementation time.
- `validateGroupEnvelopeForTransportPeer` mirrors the production rejection order.
- Focused GK-011 command passes.
- Adjacent validator/parser sweep passes or has documented unrelated pre-existing failures.
- Broader Go row sweep passes or has documented unrelated pre-existing failures.
- Race-recommended focused command is run and passes, or any inability to run it is explicitly recorded.
- `gofmt` has been applied to touched Go files.
- `git diff --check` is clean for touched files.
- GK-010 remains closed and no GK-012+ work is included.

## scope guard

- Do not change the group envelope wire format, signature data, encryption payload shape, key rotation grace policy, sender-device binding policy, group config normalization, discovery, relay inbox, Flutter offline replay, or database behavior.
- Do not convert this into a full envelope schema validator for every required field. GK-012 and GK-013 own signature and encrypted-field gaps.
- Do not treat `peer_mismatch` as sufficient closure for GK-011. The row allows `non_member` or `invalid_envelope`, and this plan chooses the more explicit `invalid_envelope`.
- Do not rely only on `findMember(config, "") == nil`; it is a downstream safety net, not the GK-011 closure proof.
- Do not update source matrix or session breakdown closure state in the implementation pass unless asked.

## accepted differences / intentionally out of scope

- Accepted: GK-011 will close on `invalid_envelope`, not `non_member`, because omitted sender identity is a structural envelope defect.
- Accepted: `ParseGroupEnvelope` may continue to check only `groupId`; the source note explicitly says validator coverage is needed.
- Accepted: the test may assert parser currently allows missing `senderId` as evidence for validator ownership. If parser behavior has already changed by implementation time, keep the validator outcome stable and avoid duplicate changes.
- Out of scope: missing signature, missing encrypted fields, tampered sender identity, tampered envelope type, and sender-device mismatch rows.
- Out of scope: Flutter offline replay unless implementation touches Dart envelope parsing.

## dependency impact

- GK-012 and GK-013 may reuse the JSON field-deletion helper later, but they must get their own row-owned tests and should not be implemented here.
- GK-026 sender tamper remains separate because it has a nonblank claimed sender and depends on config-key attribution, not missing identity.
- The explicit invalid-envelope guard gives later malformed-envelope rows a clear place to add narrow structural checks if their own plans choose that route.
- If implementation changes parser required-field policy instead of validator-only guarding, later GK-012/GK-013 plans must re-check parser versus validator ownership before adding tests.

## Reviewer Findings

- Sufficiency: sufficient as-is.
- Missing files/tests/gates: none structurally. The plan names direct production/test files, row-owned pure and real-validator tests, focused Go commands, adjacent parser/validator sweep, broader Go row sweep, race-recommended focused command, and diff hygiene.
- Stale or incorrect assumptions: none found. The plan correctly treats parser missing-`senderId` rejection as optional/future evidence, not the current required path.
- Overengineering: none found. The guard is a single structural `SenderId` check and does not expand into full envelope schema validation.
- Decomposition: narrow enough for implementation. The tests are added first, the production edit has one intended behavior change, and GK-010/GK-012+ are explicitly excluded.
- Minimum needed: implement the plan as written; no patch loop required before arbiter.

## Arbiter Decision

- Structural blockers: none.
- Incremental details: implementation may choose inline `strings.TrimSpace(env.SenderId) == ""` or a tiny helper such as `groupEnvelopeHasSenderId`; the test helper name may change if an equivalent structured JSON deletion helper already exists by implementation time; the Flutter offline replay command remains conditional on Dart changes.
- Accepted differences: closing on `invalid_envelope` rather than `non_member` is intentional because omitted sender identity is malformed input; keeping `ParseGroupEnvelope` groupId-only is intentional because the source row says validator coverage is required; GK-012+ malformed fields remain out of scope.
- Stop rule: reviewer found the plan sufficient as-is and no structural blocker exists, so no patch loop is required.

## Final Planning Output

- Final verdict: execution-ready for GK-011.
- Final plan: add row-owned GK-011 pure and real-validator tests first, prove the current missing-`senderId` path is not stable enough, then add the minimal post-parse validator guard in `go-mknoon/node/pubsub.go` and mirror it in `validateGroupEnvelopeForTransportPeer`.
- Structural blockers remaining: none.
- Incremental details intentionally deferred: helper naming and whether the guard is inline or helper-backed are implementation details; Flutter offline replay testing is only required if Dart code is touched.
- Accepted differences intentionally left unchanged: `invalid_envelope` is the planned accepted row outcome; parser required-field behavior remains unchanged unless fresh evidence already moved it; GK-010 stays closed and GK-012+ stay out of scope.
- Exact docs/files used as evidence: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`, `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`, `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-010-plan.md`, `Test-Flight-Improv/test-gate-definitions.md`, `README.md`, `go-mknoon/internal/group_envelope.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, `go-mknoon/node/node_test.go`, and `git status --short`.
- Why the plan is safe to implement now: it is scoped to one P0 matrix row, starts with failing row-owned tests, changes only the validator's missing/blank sender handling, preserves existing valid/non-member/group-mismatch/signature behavior, names exact verification commands, and records how to isolate unrelated dirty-worktree failures.
