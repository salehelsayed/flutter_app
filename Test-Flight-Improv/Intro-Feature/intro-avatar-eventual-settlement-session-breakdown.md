# Intro Avatar Eventual Settlement Session Breakdown

## Decomposition artifact updated

- Artifact path:
  `Test-Flight-Improv/Intro-Feature/intro-avatar-eventual-settlement-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/Intro-Feature/intro-avatar-eventual-settlement.md`
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

`intro-avatar-eventual-settlement.md` is only closed when all of the following
are true at the same time:

- a mutual-acceptance contact still appears immediately even when avatar
  download is temporarily unavailable
- the repo has direct proof that a later intro-owned recovery pass can settle
  the avatar for an already-created mutual-acceptance contact after the initial
  fire-and-forget window was missed
- that later avatar recovery does not duplicate the contact and does not
  duplicate the intro system message
- the existing no-rollback contract stays true when avatar download still fails
- stable intro docs record the new recovery proof without overstating it as a
  generic global avatar subsystem guarantee

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/Intro-Feature/intro-avatar-eventual-settlement.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/Intro-Feature/_Intro-reliability-gap-audit.md`
- `Test-Flight-Improv/Intro-Feature/test-inventory.md`
- `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`

Current repo facts that govern the split:

- `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`
  creates the new contact first, then starts avatar download as fire-and-forget
  work, retries once after five seconds, and then only emits
  `INTRO_AVATAR_DOWNLOAD_ERROR`.
- `test/features/introduction/application/create_connection_on_mutual_acceptance_test.dart`
  already proves avatar retry failure does not roll back the created contact or
  the intro system message.
- `lib/features/introduction/application/expire_old_introductions_use_case.dart`
  already provides an intro-owned later recovery hook that Feed and Orbit call
  on reload via `feed_wired.dart` and `orbit_wired.dart`, but it currently only
  repairs stale stored `pending` rows and reruns mutual-acceptance side effects
  when the stored intro status was wrong.
- `IntroductionRepository` already exposes
  `getIntroductionsByRecipient(...)` and `getIntroductionsByIntroduced(...)`, so
  an intro-owned later recovery pass can inspect already-mutualAccepted intro
  rows without inventing a new persistence surface first.
- `ProfileUpdateListener` only reacts to incoming `profile_update` messages
  carrying an `avatarVersion`; it does not create a later recovery path for a
  newly created intro contact whose first avatar download window was missed and
  who receives no subsequent profile-update message.

Source-of-truth conflicts that materially affected decomposition:

- `libp2p_introduction_test_matrix_full_with_rules.md` row `RM-013` truthfully
  closes the narrower no-rollback contract, but it does not claim eventual
  avatar settlement after the initial failure window.
- `_Intro-reliability-gap-audit.md` still records post-mutual-acceptance avatar
  follow-up as only best-effort, so this report cannot be downgraded to stale
  or already covered on current repo evidence.

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | `Add intro-owned later avatar settlement for mutual-acceptance contacts` | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/intro-avatar-eventual-settlement-session-1-plan.md` | none | `accepted` | `Test-Flight-Improv/Intro-Feature/intro-avatar-eventual-settlement-session-breakdown.md`, `Test-Flight-Improv/Intro-Feature/_Intro-reliability-gap-audit.md`, `Test-Flight-Improv/Intro-Feature/test-inventory.md` | Accepted on `2026-04-13`: `handle_mutual_acceptance_use_case.dart` now retries avatar settlement for existing intro-created contacts that still lack an avatar, `expire_old_introductions_use_case.dart` now revisits already-mutualAccepted intro rows for that intro-owned recovery pass, the new later-settlement regressions landed in `create_connection_on_mutual_acceptance_test.dart` and `expire_old_introductions_use_case_test.dart`, and `flutter test --no-pub test/features/introduction/application`, `./scripts/run_test_gates.sh intro`, and `./scripts/run_test_gates.sh baseline` all passed. |

## Ordered session breakdown

### Session 1

- Title:
  `Add intro-owned later avatar settlement for mutual-acceptance contacts`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/Intro-Feature/intro-avatar-eventual-settlement-session-1-plan.md`
- Exact scope:
  - extend the intro-owned mutual-acceptance recovery path so a later reload can
    retry avatar settlement for a contact that already exists from a
    mutual-accepted intro but still has no avatar
  - reuse the existing `expireOldIntroductions(...)` seam or a narrowly
    adjacent intro-owned helper instead of inventing a brand-new global avatar
    substrate
  - preserve current contact creation, system message insertion, and
    no-rollback behavior when avatar download still fails
  - add direct tests for:
    - immediate contact creation remaining intact
    - later avatar settlement after the initial window was missed
    - no duplicate contact or duplicate system message during later recovery
  - update stable intro docs only enough to record the new recovery proof and
    close the current best-effort gap truthfully
- Why it is its own session:
  - this is one coherent intro-owned reliability seam
  - the implementation and proof sit on the same mutual-acceptance plus
    intro-recovery boundary
  - splitting recovery code from the direct proof would add bookkeeping without
    separate verification value
- Likely code-entry files:
  - `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`
  - `lib/features/introduction/application/expire_old_introductions_use_case.dart`
  - `test/features/introduction/application/create_connection_on_mutual_acceptance_test.dart`
  - `test/features/introduction/application/expire_old_introductions_use_case_test.dart`
  - `Test-Flight-Improv/Intro-Feature/_Intro-reliability-gap-audit.md`
  - `Test-Flight-Improv/Intro-Feature/test-inventory.md`
  - `Test-Flight-Improv/Intro-Feature/intro-avatar-eventual-settlement-session-breakdown.md`
- Likely direct tests/regressions:
  - `flutter test --no-pub test/features/introduction/application/create_connection_on_mutual_acceptance_test.dart`
  - `flutter test --no-pub test/features/introduction/application/expire_old_introductions_use_case_test.dart`
  - `flutter test --no-pub test/features/introduction/application`
- Likely named gates:
  - `./scripts/run_test_gates.sh intro`
  - `./scripts/run_test_gates.sh baseline`
- Matrix/closure docs to update when done:
  - required:
    - `Test-Flight-Improv/Intro-Feature/_Intro-reliability-gap-audit.md`
    - `Test-Flight-Improv/Intro-Feature/test-inventory.md`
    - `Test-Flight-Improv/Intro-Feature/intro-avatar-eventual-settlement-session-breakdown.md`
  - intentionally unchanged unless execution widens:
    - `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`
- Dependency on earlier sessions:
  - none
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`
- Closure note:
  - Accepted on `2026-04-13` after the intro-owned later avatar settlement seam
    landed in `handle_mutual_acceptance_use_case.dart` and
    `expire_old_introductions_use_case.dart`, with direct regressions proving
    later recovery does not duplicate contact side effects and with the intro
    plus baseline gates green.

## Why this is not fewer sessions

- A docs-only pass would still leave avatar recovery best-effort after the
  initial miss.
- Closing the report requires both the intro-owned recovery behavior and direct
  proof that later recovery does not duplicate contact side effects.

## Why this is not more sessions

- The later retry trigger, idempotence guard, and direct tests all live on the
  same mutual-acceptance repair seam.
- No separate UI, transport, or generic settings-avatar session is justified by
  current repo evidence.

## Regression and gate contract

- Add the later-settlement regressions first in:
  - `test/features/introduction/application/create_connection_on_mutual_acceptance_test.dart`
  - `test/features/introduction/application/expire_old_introductions_use_case_test.dart`
- Run the touched direct suites before wider gates.
- Run `./scripts/run_test_gates.sh intro`.
- Run `./scripts/run_test_gates.sh baseline` because Flutter production intro
  code changes.
- Do not widen into transport or settings-global avatar flows unless execution
  proves the intro-owned seam cannot close the gap truthfully.

## Matrix update contract

- Update:
  - `Test-Flight-Improv/Intro-Feature/_Intro-reliability-gap-audit.md`
  - `Test-Flight-Improv/Intro-Feature/test-inventory.md`
  - `Test-Flight-Improv/Intro-Feature/intro-avatar-eventual-settlement-session-breakdown.md`
- Session ownership:
  - Session `1` owns the closure update because there is only one meaningful
    intro-owned recovery seam in this report.
- Truthfulness rule:
  - record later avatar settlement only for mutual-acceptance intro contacts and
    only through the intro-owned repair path that actually lands
  - do not overclaim a generic global avatar retry system if the landed change
    remains scoped to intro-created contacts

## Structural blockers remaining

- none

## Accepted differences intentionally left unchanged

- This report does not require a global contact-avatar reconciliation system for
  non-intro contacts.
- This report does not require new push or transport behavior if intro-owned
  local recovery closes the user-visible gap.

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
  `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`,
  `lib/features/introduction/application/expire_old_introductions_use_case.dart`,
  `test/features/introduction/application/create_connection_on_mutual_acceptance_test.dart`,
  `test/features/introduction/application/expire_old_introductions_use_case_test.dart`,
  `Test-Flight-Improv/Intro-Feature/_Intro-reliability-gap-audit.md`,
  `Test-Flight-Improv/Intro-Feature/test-inventory.md`,
  `Test-Flight-Improv/Intro-Feature/intro-avatar-eventual-settlement-session-1-plan.md`,
  `Test-Flight-Improv/Intro-Feature/intro-avatar-eventual-settlement-session-breakdown.md`
- why the rollout is safe to complete:
  - intro-created contacts still appear immediately and keep the no-rollback
    guarantee when avatar download fails
  - a later intro-owned recovery pass now settles missing avatars for
    already-created mutual-acceptance contacts without duplicating the contact
    or the intro system message
  - the touched direct intro suites, Intro gate, and Baseline gate all passed
