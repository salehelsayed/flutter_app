# Intro Introducer Status Feedback Session Breakdown

## Decomposition artifact updated

- Artifact path:
  `Test-Flight-Improv/Intro-Feature/intro-introducer-status-feedback-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/Intro-Feature/intro-introducer-status-feedback.md`
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

`intro-introducer-status-feedback.md` is only closed when all of the following
are true at the same time:

- when the introducer observes the first accept on an intro pair, the existing
  conversation with the recipient gains a short role-correct system message
  that identifies who accepted and which pair is still in progress
- when the second accept completes mutual acceptance, the introducer receives a
  role-correct local notification and a role-correct system message in the same
  recipient thread that state which pair is now connected without implying that
  the introducer personally became connected
- participant-side mutual-acceptance behavior remains intact for the newly
  connected pair, including the existing B<->C system message and no duplicate
  contacts
- duplicate accept replay does not duplicate introducer-side thread messages or
  introducer-side notifications once the corrected copy exists
- the background-push fallback contract no longer locks the misleading
  introducer mutual-accept phrasing; intro-specific copy is either corrected or
  remains explicitly neutral
- stable intro docs record the corrected coverage truthfully instead of
  continuing to overclaim the old wording as already acceptable

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/Intro-Feature/intro-introducer-status-feedback.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Intro-Feature/test-inventory.md`

Current repo facts that govern the split:

- `lib/features/introduction/application/introduction_listener.dart` inserts a
  system message only for incoming intro `send` actions and currently emits no
  introducer-thread system message for `accept` or `pass`.
- the same listener currently shows the hard-coded mutual-accept body
  `$responderName also accepted! You're now connected.` whenever the local user
  reaches `mutualAccepted`, even when that local user is only the introducer.
- `lib/features/introduction/application/introduction_copy.dart` already owns
  intro-specific send and participant mutual-accept system-message copy, but it
  does not yet provide introducer-facing accept-progress or introducer-facing
  mutual-connect copy.
- `test/features/introduction/application/introduction_listener_test.dart`
  currently locks the misleading introducer mutual-accept notification wording
  and has no direct regression for introducer-thread status messages on first
  accept or mutual acceptance.
- `lib/features/push/application/background_push_notification_fallback.dart`
  preserves provided intro title/body data without synthesizing new intro copy,
  so the safe closure bar is to stop preserving the wrong introducer wording
  and allow corrected or neutral copy.
- `test/features/push/application/background_push_notification_fallback_test.dart`
  currently preserves the misleading participant-style mutual-accept body for
  an intros fallback payload.

Source-of-truth conflicts that materially affected decomposition:

- `libp2p_introduction_test_matrix_full_with_rules.md` row `UX-006` currently
  overstates the introducer-notification copy seam as covered even though the
  live listener and fallback tests still pin the wrong introducer wording.
- `test-inventory.md` currently states that exact intro title/body content is
  covered across `introduction_listener_test.dart` and
  `background_push_notification_fallback_test.dart`, but that statement is only
  truthfully closeable after the introducer-facing wording is corrected.

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | `Land role-correct introducer accept and mutual-connect status feedback` | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/intro-introducer-status-feedback-session-1-plan.md` | none | `accepted` | `Test-Flight-Improv/Intro-Feature/intro-introducer-status-feedback-session-breakdown.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/test-inventory.md` | Accepted on `2026-04-13`: landed introducer-specific accept and mutual-accept copy in `introduction_copy.dart`, introducer-thread status-message insertion plus role-correct introducer notification handling in `introduction_listener.dart`, direct regressions in `introduction_copy_test.dart` and `introduction_listener_test.dart`, a corrected intro fallback copy regression in `background_push_notification_fallback_test.dart`, and green reruns of the targeted suites, `flutter test --no-pub test/features/introduction/application`, `./scripts/run_test_gates.sh intro`, and `./scripts/run_test_gates.sh baseline`. |

## Ordered session breakdown

### Session 1

- Title:
  `Land role-correct introducer accept and mutual-connect status feedback`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/Intro-Feature/intro-introducer-status-feedback-session-1-plan.md`
- Exact scope:
  - add intro-copy helpers for introducer-facing first-accept progress and
    introducer-facing mutual-accept completion text
  - update the intro listener so the introducer's existing thread with the
    recipient receives a short system message when:
    - one side accepts while the other side is still pending
    - the second accept completes the mutual-acceptance pair
  - update the introducer mutual-accept local notification so it names the
    accepter and the connected pair without saying `You're now connected` to
    the introducer
  - preserve participant-side mutual-acceptance system messages and participant
    notifications for the newly connected pair unless execution proves a shared
    copy helper can safely serve both roles
  - refresh direct regressions so duplicate accept replay still produces only
    one introducer-side notification and one introducer-side thread message
  - refresh the push-fallback regression so intro-specific mutual-accept copy
    no longer preserves the misleading introducer phrasing
  - update the stable intro matrix and test inventory only enough to record the
    corrected coverage truthfully
- Why it is its own session:
  - the user-visible gap is one coherent introducer-status feedback seam
  - the listener copy, thread insertion, notification wording, and fallback
    regression refresh share one direct verification surface
  - splitting docs-only or push-only work away from the listener change would
    add bookkeeping without reducing implementation risk
- Likely code-entry files:
  - `lib/features/introduction/application/introduction_copy.dart`
  - `lib/features/introduction/application/introduction_listener.dart`
  - `lib/features/introduction/application/insert_intro_system_message.dart`
  - `test/features/introduction/application/introduction_copy_test.dart`
  - `test/features/introduction/application/introduction_listener_test.dart`
  - `test/features/push/application/background_push_notification_fallback_test.dart`
  - `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/Intro-Feature/test-inventory.md`
  - `Test-Flight-Improv/Intro-Feature/intro-introducer-status-feedback-session-breakdown.md`
- Likely direct tests/regressions:
  - `flutter test --no-pub test/features/introduction/application/introduction_copy_test.dart`
  - `flutter test --no-pub test/features/introduction/application/introduction_listener_test.dart`
  - `flutter test --no-pub test/features/push/application/background_push_notification_fallback_test.dart`
  - `flutter test --no-pub test/features/introduction/application`
- Likely named gates:
  - `./scripts/run_test_gates.sh intro`
  - `./scripts/run_test_gates.sh baseline`
- Matrix/closure docs to update when done:
  - required:
    - `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`
    - `Test-Flight-Improv/Intro-Feature/test-inventory.md`
    - `Test-Flight-Improv/Intro-Feature/intro-introducer-status-feedback-session-breakdown.md`
  - intentionally unchanged unless execution widens:
    - `Test-Flight-Improv/Intro-Feature/_Intro-reliability-gap-audit.md`
    - `Test-Flight-Improv/Intro-Feature/_Intro-reliability-gap-audit-row-and-prompt-map.md`
- Dependency on earlier sessions:
  - none
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`
- Scope guard:
  - do not widen into relay-side synthesized pair-specific push copy if the
    existing generic `intros` push remains neutral and the client-side
    introducer copy is corrected locally
  - do not add new pass-specific introducer-thread behavior unless execution
    proves it is required to keep the accept/mutual-accept status model
    truthful
- Closure note:
  - Accepted on `2026-04-13` after introducer-specific first-accept and
    mutual-accept copy landed in `introduction_copy.dart`, the listener now
    writes introducer-thread status messages into the recipient thread and uses
    role-correct introducer notification copy, the direct intro and push
    regressions passed, and both the Intro and Baseline gates reran green.

## Why this is not fewer sessions

- A docs-only or test-only pass would still leave the misleading introducer
  copy live in the product.
- The current report closes on one bounded listener-owned UX seam rather than
  separate transport, server, or multi-surface architectures.

## Why this is not more sessions

- Introducer-thread system messages, introducer local notification wording, and
  fallback-copy regression refresh all sit on the same intro listener and copy
  surface.
- No separate relay/server or transport session is justified because the
  report accepts neutral generic intros push copy when background delivery does
  not have richer role-aware data.

## Regression and gate contract

- Add or refresh the direct intro-copy and intro-listener regressions first.
- Run the targeted push fallback regression after the listener copy lands.
- Run the touched direct intro application suite before named gates.
- Run `./scripts/run_test_gates.sh intro`.
- Run `./scripts/run_test_gates.sh baseline` because Flutter production intro
  code changes.

## Matrix update contract

- Update:
  - `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/Intro-Feature/test-inventory.md`
  - `Test-Flight-Improv/Intro-Feature/intro-introducer-status-feedback-session-breakdown.md`
- Session ownership:
  - Session `1` owns the closure update because there is only one meaningful
    introducer-facing status-feedback seam in this report.
- Truthfulness rule:
  - record only the introducer-facing first-accept and mutual-accept feedback
    proof that actually lands
  - do not overclaim relay-side pair-specific push synthesis if execution keeps
    the background fallback neutral outside the local listener path

## Structural blockers remaining

- none

## Accepted differences intentionally left unchanged

- This report does not require relay-server copy generation for backgrounded
  introducers if the current `intros` push remains neutral.
- This report does not require a new Feed, Orbit, or thread-aggregation design;
  it only requires truthful recipient-thread status feedback for the
  introducer.

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
  `lib/features/introduction/application/introduction_copy.dart`,
  `lib/features/introduction/application/introduction_listener.dart`,
  `test/features/introduction/application/introduction_copy_test.dart`,
  `test/features/introduction/application/introduction_listener_test.dart`,
  `test/features/push/application/background_push_notification_fallback_test.dart`,
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`,
  `Test-Flight-Improv/Intro-Feature/test-inventory.md`,
  `Test-Flight-Improv/Intro-Feature/intro-introducer-status-feedback-session-1-plan.md`,
  `Test-Flight-Improv/Intro-Feature/intro-introducer-status-feedback-session-breakdown.md`
- why the rollout is safe to complete:
  - the introducer now gets role-correct recipient-thread progress on first
    accept and role-correct recipient-thread plus notification feedback on
    mutual acceptance without being told `You're now connected`
  - participant-side mutual-accept behavior stays intact, including the
    existing participant conversation system message
  - the touched direct suites, broader intro application suite, Intro gate,
    and Baseline gate all passed on `2026-04-13`
