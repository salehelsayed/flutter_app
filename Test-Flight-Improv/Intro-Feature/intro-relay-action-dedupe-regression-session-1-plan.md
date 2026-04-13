# Session 1 Plan: Intro Relay Action Dedupe Regression

**Final Verdict:** sufficient as revised

## 1. Real Scope

- Keep Session 1 limited to the relay inbox dedupe seam for introduction
  envelopes in `go-relay-server/`.
- Add the missing direct regression proof that two different intro actions for
  the same `introductionId` survive dedupe when they arrive with distinct
  action-scoped top-level `messageId` values.
- Preserve the existing duplicate-dedupe contract for exact retries of the same
  intro action.
- Update only the stable intro test documentation needed to record the new
  relay-owned proof.
- Do not expand into intro protocol redesign, app-side state-machine changes,
  malformed-envelope hardening beyond the current normalized-client contract, or
  broad transport/device reruns unless the new proof exposes a real bug.

## 2. Closure Bar

- `go-relay-server/inbox_dedup_test.go` directly proves a `send` intro and a
  later `accept` intro for the same `introductionId` are both retained when
  their top-level `messageId` values differ.
- The same proof exists for both the plaintext intro envelope shape and the
  encrypted intro envelope shape used by the repo today.
- Exact duplicates of the same `send` or same `accept` still dedupe to one
  stored record.
- The touched Go suite passes, and the resulting docs record the relay-owned
  proof without overclaiming malformed-envelope behavior.

## 3. Source Of Truth

- Active session contract:
  - `Test-Flight-Improv/Intro-Feature/intro-relay-action-dedupe-regression-session-breakdown.md`
- Product / proposal intent:
  - `Test-Flight-Improv/Intro-Feature/intro-relay-action-dedupe-regression.md`
- Governing repo evidence:
  - `go-relay-server/inbox.go`
  - `go-relay-server/inbox_dedup_test.go`
  - `go-relay-server/inbox_test.go`
  - `lib/features/introduction/application/introduction_outbound_delivery.dart`
  - `lib/features/introduction/domain/models/introduction_payload.dart`
  - `test/features/introduction/application/introduction_payload_test.dart`
  - `test/features/introduction/application/introduction_outbound_delivery_test.dart`
- Stable documentation to refresh if proof lands:
  - `Test-Flight-Improv/Intro-Feature/test-inventory.md`
- On disagreement, current code and tests beat stale prose.

## 4. Session Classification

- `implementation-ready`

## 5. Exact Problem Statement

- The repo already scopes intro transport IDs by action and sender on the
  client, and the relay dedupe extractor already prefers top-level
  `messageId`.
- What is still missing is direct relay-owned proof that a `send` intro and a
  later `accept` intro for the same `introductionId` both survive inbox dedupe
  because their action-scoped transport IDs differ.
- If that proof regresses, a later response could be collapsed into the earlier
  intro record at the relay seam even though the app-level logic remains
  distinct.
- User-visible behavior that must improve: the repo must directly prove this
  relay dedupe contract rather than inferring it only from app-side tests.
- Behavior that must stay unchanged: exact duplicate retries still dedupe, and
  intro push routing stays on the `intros` route with generic copy.

## 6. Files And Repos To Inspect Next

- Primary production seam:
  - `go-relay-server/inbox.go`
- Direct regression surfaces:
  - `go-relay-server/inbox_dedup_test.go`
  - `go-relay-server/inbox_test.go`
- Adjacent client evidence:
  - `lib/features/introduction/domain/models/introduction_payload.dart`
  - `lib/features/introduction/application/introduction_outbound_delivery.dart`
  - `test/features/introduction/application/introduction_payload_test.dart`
  - `test/features/introduction/application/introduction_outbound_delivery_test.dart`
- Closure docs:
  - `Test-Flight-Improv/Intro-Feature/test-inventory.md`
  - `Test-Flight-Improv/Intro-Feature/intro-relay-action-dedupe-regression-session-breakdown.md`

## 7. Existing Tests Covering This Area

- `go-relay-server/inbox_dedup_test.go` already covers:
  - duplicate generic message dedupe
  - different generic IDs both storing
  - duplicate plaintext intro dedupe
  - duplicate encrypted intro dedupe
  - malformed JSON falling through without dedupe
- `go-relay-server/inbox_test.go` already covers intro push routing to
  `intros` with generic intro copy.
- `test/features/introduction/application/introduction_payload_test.dart`
  already proves action-scoped intro `messageId` generation and normalization.
- `test/features/introduction/application/introduction_outbound_delivery_test.dart`
  already proves distinct intro actions for the same intro carry different
  transport-level IDs through outbound delivery.
- Missing today: one direct relay-owned proof that two different intro actions
  for the same `introductionId` both survive dedupe because the top-level
  `messageId` values differ.

## 8. Regressions/Tests To Add First

- Add a plaintext relay regression that stores:
  - one `send` intro with `messageId=intro-1::send::peer-A`
  - one later `accept` intro with `messageId=intro-1::accept::peer-B`
  - the same shared `payload.introductionId=intro-1`
  - and asserts the inbox count is `2`
- Add the same regression for the encrypted intro envelope shape.
- If helpful for readability, add targeted exact-duplicate checks for repeated
  `accept` using the same scoped `messageId`, but do not rewrite the existing
  duplicate tests unless the new cases make them redundant.
- Only change `go-relay-server/inbox.go` if the new tests expose an actual bug.

## 9. Step-By-Step Implementation Plan

- Re-read `extractMessageId(...)` and the existing relay dedupe tests to lock
  the exact JSON shapes already accepted by the inbox store.
- Write the new plaintext and encrypted action-distinct intro regressions in
  `go-relay-server/inbox_dedup_test.go` first.
- Run the targeted Go relay tests to confirm whether current code already
  satisfies the new proof.
- If the tests fail, make the smallest possible fix in `go-relay-server/inbox.go`
  to preserve top-level action-scoped `messageId` precedence without widening
  behavior.
- Rerun the touched Go suite.
- Update `Test-Flight-Improv/Intro-Feature/test-inventory.md` with the new
  relay-owned proof.
- Update the session breakdown ledger and final program verdict once execution
  and closure are complete.
- Stop immediately after the relay seam, direct proof, and closure docs are
  truthful; do not widen into app-side intro code unless the new proof proves a
  cross-stack defect.

## 10. Risks And Edge Cases

- Plaintext intro envelopes still carry `payload.introductionId`, so the tests
  must include distinct top-level `messageId` values to exercise the intended
  current-client contract rather than the malformed fallback path.
- Encrypted intro envelopes cannot expose payload internals to relay dedupe, so
  the proof must rely entirely on the top-level `messageId`.
- Exact duplicate retries must stay deduped after the new action-distinct
  regressions land.
- If a fix is needed, do not reorder extraction in a way that breaks generic
  `id` or `msgId` dedupe behavior already covered elsewhere in the same file.

## 11. Exact Tests And Gates To Run

- Targeted direct rerun while iterating:
  - `cd go-relay-server && go test ./... -run 'TestInboxStoreDedup_Introduction'`
- Full touched Go module suite for closure:
  - `cd go-relay-server && go test ./...`
- No named Test-Flight gate is required for the default Go-only proof path.
- If execution widens into Flutter intro delivery code, also run:
  - `./scripts/run_test_gates.sh intro`

## 12. Known-Failure Interpretation

- No current known red gate state is part of the default Go-only path.
- Treat any new failure in `cd go-relay-server && go test ./...` as a real
  Session 1 blocker until proven otherwise.
- Do not promote unrelated Flutter gate noise into this session unless the work
  actually widens into Flutter intro delivery code.

## 13. Done Criteria

- The new relay-owned regressions exist and prove plaintext plus encrypted
  action-distinct intro envelopes both survive dedupe.
- The touched Go relay suite passes.
- `Test-Flight-Improv/Intro-Feature/test-inventory.md` truthfully records the
  new proof.
- The session breakdown records Session `1` as resolved and persists a final
  program verdict for the doc.
- No broader intro or transport scope was introduced without evidence forcing
  it.

## 14. Scope Guard

- Do not redesign intro envelope formats.
- Do not change app-side intro state handling, inbox replay logic, or UI copy
  unless the relay tests prove they are implicated.
- Do not widen into multi-device, smoke, or transport validation just because
  the underlying feature is reliability-sensitive.
- Do not claim malformed plaintext envelopes without top-level `messageId` are
  newly safe unless code and tests explicitly change that behavior.

## 15. Accepted Differences / Intentionally Out Of Scope

- The current malformed-plaintext fallback to `payload.introductionId` remains
  intentionally unchanged in this session.
- The broader intro matrix rows already closed for app-level replay and
  envelope normalization remain unchanged unless execution proves they became
  stale.
- No new push-content or notification-open flow work belongs to this session.

## 16. Dependency Impact

- If Session 1 lands with Go-only proof, later docs in this batch can proceed
  without inheriting any open relay blocker from this report.
- If Session 1 exposes a real cross-stack bug in Flutter intro delivery
  normalization, the rest of this batch should pause until that widened scope
  is either fixed or explicitly recorded as a blocker in the breakdown.

## Structural Blockers Remaining

- None.

## Accepted Differences Intentionally Left Unchanged

- No malformed-envelope hardening beyond the current normalized-client contract.
- No broader transport rerun unless the direct relay proof forces it.

## Exact Docs/Files Used As Evidence

- `Test-Flight-Improv/Intro-Feature/intro-relay-action-dedupe-regression-session-breakdown.md`
- `Test-Flight-Improv/Intro-Feature/intro-relay-action-dedupe-regression.md`
- `Test-Flight-Improv/Intro-Feature/test-inventory.md`
- `go-relay-server/inbox.go`
- `go-relay-server/inbox_dedup_test.go`
- `go-relay-server/inbox_test.go`
- `lib/features/introduction/domain/models/introduction_payload.dart`
- `lib/features/introduction/application/introduction_outbound_delivery.dart`
- `test/features/introduction/application/introduction_payload_test.dart`
- `test/features/introduction/application/introduction_outbound_delivery_test.dart`

## Why The Plan Is Safe To Implement Now

- The missing seam is narrow, already supported by adjacent client-side
  evidence, and isolated to one relay regression family.
- The plan can stop after adding proof if current code already satisfies the
  contract.
- No structural blocker remains, and the verification contract is exact.
