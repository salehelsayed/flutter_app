# Intro Relay Action Dedupe Regression Session Breakdown

## Decomposition artifact updated

- Artifact path:
  `Test-Flight-Improv/Intro-Feature/intro-relay-action-dedupe-regression-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/Intro-Feature/intro-relay-action-dedupe-regression.md`
- Decomposition date:
  `2026-04-13`
- Decomposition mode:
  bounded local decomposition fallback after the fresh decomposition agent left
  no reusable current-doc artifact on disk
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Downstream execution path

- Session `1` should run through:
  1. `$implementation-plan-orchestrator`
  2. `$implementation-execution-qa-orchestrator`
  3. `$implementation-closure-audit-orchestrator`

## Recommended plan count

- `1`

## Overall closure bar

`intro-relay-action-dedupe-regression.md` is only closed when all of the
following are true at the same time:

- the relay inbox seam has direct repo-owned proof that two different intro
  actions for the same `introductionId` both survive dedupe when they arrive
  with distinct action-scoped top-level `messageId` values
- that proof exists for the plaintext intro envelope shape and the encrypted
  intro envelope shape currently used by the repo
- exact duplicate retries of the same intro action still dedupe to one stored
  record
- intro push routing still uses the existing `intros` route and generic copy
  contract after the relay-owned proof lands
- closure docs record the relay-owned proof without overclaiming unsupported
  malformed-envelope or broader transport guarantees

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/Intro-Feature/intro-relay-action-dedupe-regression.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/Intro-Feature/test-inventory.md`
- `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`

Current repo facts that govern the split:

- `go-relay-server/inbox.go` currently extracts dedupe IDs in this order:
  top-level `id`, top-level `messageId`, top-level `msgId`, `payload.id`, then
  `payload.introductionId`.
- `lib/features/introduction/application/introduction_outbound_delivery.dart`
  already builds an action-scoped transport ID with
  `IntroductionPayload.buildEnvelopeMessageId(...)` and normalizes every intro
  envelope through `IntroductionPayload.ensureEnvelopeMessageId(...)` before
  live send or inbox fallback.
- `test/features/introduction/application/introduction_payload_test.dart`
  already proves `send` and `accept` for the same intro get different
  transport-level `messageId` values and that missing or legacy-shaped
  envelopes are patched with a top-level `messageId`.
- `test/features/introduction/application/introduction_outbound_delivery_test.dart`
  already proves outbound deliveries for the same intro carry distinct scoped
  message IDs.
- `go-relay-server/inbox_dedup_test.go` currently covers duplicate plaintext
  intros, duplicate encrypted intros, and generic different-ID behavior, but it
  does not directly store two different intro actions for the same
  `introductionId` and prove both survive relay dedupe.
- `go-relay-server/inbox_test.go` already proves intro push payloads use the
  `intros` route and generic intro copy when a relay-stored intro message is
  turned into a push notification.

Source-of-truth conflicts that materially affected decomposition:

- `libp2p_introduction_test_matrix_full_with_rules.md` already closes
  application-level replay and envelope-normalization rows (`SC-001` and
  `SC-004`), but those closures do not themselves prove the relay store keeps
  action-distinct intro envelopes separate.
- The current proposal does not justify a broader transport or end-to-end
  re-rollout when the missing seam is a relay-owned dedupe proof that can be
  closed with focused Go-side regression coverage unless execution exposes a
  real product bug.

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | `Land relay-owned proof for action-distinct intro message IDs` | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/intro-relay-action-dedupe-regression-session-1-plan.md` | none | `accepted` | `Test-Flight-Improv/Intro-Feature/intro-relay-action-dedupe-regression-session-breakdown.md`, `Test-Flight-Improv/Intro-Feature/test-inventory.md` | Accepted on `2026-04-13`: landed `TestInboxStoreDedup_IntroductionPlaintextDifferentActionMessageIDs` and `TestInboxStoreDedup_IntroductionEncryptedDifferentActionMessageIDs` in `go-relay-server/inbox_dedup_test.go`, confirmed exact duplicate retries still dedupe, and reran `cd go-relay-server && go test ./... -run 'TestInboxStoreDedup_Introduction'` plus the full `cd go-relay-server && go test ./...` suite green with no production code changes required. |

## Ordered session breakdown

### Session 1

- Title:
  `Land relay-owned proof for action-distinct intro message IDs`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/Intro-Feature/intro-relay-action-dedupe-regression-session-1-plan.md`
- Exact scope:
  - add relay-owned regressions in `go-relay-server/inbox_dedup_test.go` that
    store a `send` intro envelope and a later `accept` intro envelope with the
    same `introductionId` but different scoped top-level `messageId` values and
    prove both records are retained
  - cover the current plaintext intro envelope shape and the current encrypted
    intro envelope shape
  - keep the existing exact-duplicate dedupe contract truthful for repeated
    `send` and repeated `accept` deliveries
  - preserve the existing intro push-route behavior proven in
    `go-relay-server/inbox_test.go`; only touch that suite if execution needs a
    direct regression refresh after relay changes
  - update stable intro test documentation only enough to record the new
    relay-owned proof without re-opening the broader intro matrix
  - update this breakdown with the landed execution and closure result
- Why it is its own session:
  - this is one coherent relay inbox dedupe seam
  - the missing proof is concentrated in one Go-side regression family
  - splitting docs-only work away from the regression would add bookkeeping
    without independent verification value
- Likely code-entry files:
  - `go-relay-server/inbox_dedup_test.go`
  - `go-relay-server/inbox.go`
  - `go-relay-server/inbox_test.go`
  - `Test-Flight-Improv/Intro-Feature/test-inventory.md`
  - `Test-Flight-Improv/Intro-Feature/intro-relay-action-dedupe-regression-session-breakdown.md`
- Likely direct tests/regressions:
  - `cd go-relay-server && go test ./...`
  - targeted reruns for the intro relay dedupe cases in
    `go-relay-server/inbox_dedup_test.go`
- Likely named gates:
  - none for the default Go-only proof path
  - if execution widens into Flutter intro delivery code, also run
    `./scripts/run_test_gates.sh intro`
- Matrix/closure docs to update when done:
  - required:
    - `Test-Flight-Improv/Intro-Feature/test-inventory.md`
    - `Test-Flight-Improv/Intro-Feature/intro-relay-action-dedupe-regression-session-breakdown.md`
  - intentionally unchanged unless execution widens:
    - `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`
    - `Test-Flight-Improv/Intro-Feature/_Intro-reliability-gap-audit.md`
- Dependency on earlier sessions:
  - none
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`
- Closure note:
  - Accepted on `2026-04-13` after the relay-owned plaintext and encrypted
    action-split dedupe regressions landed in
    `go-relay-server/inbox_dedup_test.go` and both the targeted introduction
    rerun plus the full `go-relay-server` suite passed without needing a change
    to `go-relay-server/inbox.go`.

## Why this is not fewer sessions

- A docs-only pass would still leave the relay seam without direct proof that
  action-distinct intro envelopes survive dedupe.
- The report closes on one focused regression family; no prerequisite planning
  or acceptance-only slice adds separate verification value.

## Why this is not more sessions

- Plaintext and encrypted intro envelopes share the same relay dedupe seam and
  the same success criteria.
- Push-route preservation is already on the same relay test surface, so a
  second closure-only session would just split one bounded verification pass
  into bookkeeping.

## Regression and gate contract

- Add the relay-owned `send`-then-`accept` dedupe regressions first in
  `go-relay-server/inbox_dedup_test.go`.
- Rerun the touched Go relay suite with `cd go-relay-server && go test ./...`.
- No named Test-Flight gate is required for the default Go-only proof path.
- If execution changes Flutter intro payload normalization or outbound delivery,
  rerun `./scripts/run_test_gates.sh intro` before closure.

## Matrix update contract

- Update:
  - `Test-Flight-Improv/Intro-Feature/test-inventory.md`
  - `Test-Flight-Improv/Intro-Feature/intro-relay-action-dedupe-regression-session-breakdown.md`
- Session ownership:
  - Session `1` owns the closure update because there is only one meaningful
    relay-owned seam in this report.
- Truthfulness rule:
  - record only the relay-owned proof that action-scoped top-level
    `messageId` values keep `send` and later `accept` / `pass` messages
    distinct at the inbox store
  - do not overclaim malformed plaintext envelopes with no top-level
    `messageId` as newly safe unless execution actually changes that behavior

## Structural blockers remaining

- none

## Accepted differences intentionally left unchanged

- This report does not require changing the current fallback to
  `payload.introductionId` for malformed plaintext intro envelopes that arrive
  without a top-level `messageId`; it requires proof for the normalized current
  client contract.
- This report does not require a broader transport or three-device intro rerun
  unless the focused relay proof exposes a real cross-stack regression.

## Current pipeline state

- sessions processed so far: `1/1`
- sessions accepted so far: `1`
- sessions accepted_with_explicit_follow_up so far: `0`
- sessions currently blocked: `0`
- next runnable session in order: `none`
- current doc state: `closed`
- final program verdict is persisted below

## Final program acceptance

- final program verdict:
  `closed`
- docs updated:
  `go-relay-server/inbox_dedup_test.go`,
  `Test-Flight-Improv/Intro-Feature/test-inventory.md`,
  `Test-Flight-Improv/Intro-Feature/intro-relay-action-dedupe-regression-session-1-plan.md`,
  `Test-Flight-Improv/Intro-Feature/intro-relay-action-dedupe-regression-session-breakdown.md`
- why the rollout is safe to complete:
  - the relay seam now has direct repo-owned proof that action-distinct
    top-level `messageId` values keep `send` and later `accept` intro envelopes
    for the same `introductionId` separate in storage
  - exact duplicate retries remain deduped
  - the full touched Go relay suite passed and no blocker remains for this doc
