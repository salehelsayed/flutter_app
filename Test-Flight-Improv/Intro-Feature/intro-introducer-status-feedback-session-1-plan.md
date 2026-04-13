# Session 1 Plan: Intro Introducer Status Feedback

**Final Verdict:** sufficient as revised

## 1. Real Scope

- Keep Session 1 limited to introducer-facing accept and mutual-accept status
  feedback for the existing intro seam.
- Add role-correct copy for introducer-side first-accept progress, introducer-
  side mutual-accept completion, and the recipient-thread system messages that
  surface those updates.
- Preserve participant-side mutual-accept behavior for the newly connected
  pair.
- Refresh only the intro docs needed to record the corrected copy coverage
  truthfully.
- Do not widen into relay-side copy generation, Orbit redesign, Feed redesign,
  or a broad pass-status UX rewrite unless the current intro listener seam
  proves insufficient.

## 2. Closure Bar

- When the introducer receives the first accept, the recipient thread gains one
  short system message that clearly identifies the accepter and the pair still
  in progress.
- When the second accept completes mutual acceptance, the introducer receives a
  role-correct notification and a role-correct recipient-thread system message
  that name the connected pair without saying `You're now connected` to the
  introducer.
- Participant-side mutual-accept notifications and participant-side B<->C
  system messages stay intact.
- Duplicate accept replay does not duplicate introducer-side system messages or
  introducer-side notifications.
- The stable intro matrix and test inventory stop overclaiming the old
  introducer wording as already correct.

## 3. Source Of Truth

- Active session contract:
  - `Test-Flight-Improv/Intro-Feature/intro-introducer-status-feedback-session-breakdown.md`
- Product / proposal intent:
  - `Test-Flight-Improv/Intro-Feature/intro-introducer-status-feedback.md`
- Governing repo evidence:
  - `lib/features/introduction/application/introduction_copy.dart`
  - `lib/features/introduction/application/introduction_listener.dart`
  - `lib/features/introduction/application/insert_intro_system_message.dart`
  - `test/features/introduction/application/introduction_copy_test.dart`
  - `test/features/introduction/application/introduction_listener_test.dart`
  - `test/features/push/application/background_push_notification_fallback_test.dart`
- Stable docs to refresh:
  - `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/Intro-Feature/test-inventory.md`
  - `Test-Flight-Improv/Intro-Feature/intro-introducer-status-feedback-session-breakdown.md`
- On disagreement, current code and tests beat stale prose.

## 4. Session Classification

- `implementation-ready`

## 5. Exact Problem Statement

- The intro listener currently inserts a system message only for incoming
  `send` actions and emits no introducer-thread message for later `accept`
  progress.
- On mutual acceptance, the listener currently uses participant wording for
  every role: `$responderName also accepted! You're now connected.`
- That body is correct for the newly connected pair, but wrong for the
  introducer because the introducer is not one of the connected users.
- The push fallback helper itself is neutral, but the fallback regression still
  pins the wrong introducer mutual-accept body when intro-specific copy is
  provided.
- User-visible behavior that must improve: the introducer can follow pair-by-
  pair progress from the existing recipient thread, and the introducer mutual-
  accept notification names the accepter and the connected pair truthfully.
- Behavior that must stay unchanged: recipient and introduced users still get
  participant-side mutual-accept behavior, and duplicate accept replay remains
  idempotent.

## 6. Files And Repos To Inspect Next

- Primary production seam:
  - `lib/features/introduction/application/introduction_copy.dart`
  - `lib/features/introduction/application/introduction_listener.dart`
  - `lib/features/introduction/application/insert_intro_system_message.dart`
- Direct regression surfaces:
  - `test/features/introduction/application/introduction_copy_test.dart`
  - `test/features/introduction/application/introduction_listener_test.dart`
  - `test/features/push/application/background_push_notification_fallback_test.dart`
- Stable docs:
  - `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/Intro-Feature/test-inventory.md`
  - `Test-Flight-Improv/Intro-Feature/intro-introducer-status-feedback-session-breakdown.md`

## 7. Existing Tests Covering This Area

- `introduction_copy_test.dart` already pins:
  - introducer send copy
  - recipient-side and introduced-side send copy
  - participant-side mutual-accept system-message copy
- `introduction_listener_test.dart` already pins:
  - new-intro system-message insertion
  - participant-side mutual-accept notification copy
  - duplicate send replay and duplicate accept replay idempotency
- `background_push_notification_fallback_test.dart` already pins:
  - generic intro fallback visibility
  - pass-through of provided intro title/body copy
- Missing today:
  - no direct introducer first-accept thread-message regression
  - no direct introducer mutual-accept notification regression
  - no direct introducer mutual-accept thread-message regression
  - no direct copy helper coverage for introducer-specific accept-progress and
    mutual-connect wording

## 8. Regressions/Tests To Add First

- Extend `introduction_copy_test.dart` with focused introducer-side copy cases
  for:
  - first accept from the recipient
  - first accept from the introduced party
  - mutual-accept thread copy
  - mutual-accept notification copy
- Extend `introduction_listener_test.dart` with introducer-side listener cases
  that prove:
  - first accept writes one recipient-thread system message and no false
    connection notification
  - mutual acceptance writes one recipient-thread system message and one
    role-correct introducer notification
  - duplicate accept replay does not duplicate those introducer-side effects
- Refresh `background_push_notification_fallback_test.dart` so the pass-through
  intro-specific mutual-accept copy uses the corrected introducer wording.

## 9. Step-By-Step Implementation Plan

- Add small introducer-facing copy helpers in `introduction_copy.dart`.
- Update `IntroductionListener.processIncomingMessage(...)` for `accept`:
  - detect the introducer role
  - insert a recipient-thread system message for introducer-visible first
    accept and mutual acceptance
  - keep participant-side copy unchanged
  - emit role-correct introducer notification copy on mutual acceptance
- Add the direct copy tests and listener regressions.
- Refresh the push fallback pass-through regression.
- Run the targeted direct suites.
- Run the broader intro application suite.
- Run the Intro gate and Baseline gate for closure.
- Update the stable docs and breakdown after code/test evidence is green.
- Stop as soon as the introducer accept/mutual-accept seam is truthful; do not
  widen into pass UX or relay-side push generation without hard evidence.

## 10. Risks And Edge Cases

- The introducer thread is always the recipient thread, even when the
  introduced party accepts first; the copy must stay pair-correct in both
  orders.
- Duplicate accept replay must not write a second system message or a second
  notification.
- Participant-side mutual-accept copy must not regress while the introducer
  branch is added.
- Missing usernames should still degrade to safe fallback labels instead of
  blank copy.
- The existing `messageRepo` insertion helper writes raw system messages with
  no dedupe layer, so replay safety must rely on the listener's success-only
  side-effect path.

## 11. Exact Tests And Gates To Run

- Direct suites while iterating:
  - `flutter test --no-pub test/features/introduction/application/introduction_copy_test.dart`
  - `flutter test --no-pub test/features/introduction/application/introduction_listener_test.dart`
  - `flutter test --no-pub test/features/push/application/background_push_notification_fallback_test.dart`
- Broader touched feature suite:
  - `flutter test --no-pub test/features/introduction/application`
- Named gates for closure:
  - `./scripts/run_test_gates.sh intro`
  - `./scripts/run_test_gates.sh baseline`

## 12. Known-Failure Interpretation

- `test-inventory.md` is already dirty from other intro-coverage rollouts; keep
  those landed changes and layer this session's truthful coverage update on
  top.
- Treat any red failure in the touched intro application suites as a real
  Session 1 issue until proven unrelated.
- If the Intro or Baseline gate fails, document any unrelated preexisting
  failure explicitly rather than silently dropping the gate from closure.

## 13. Done Criteria

- Introducer-side first accept writes a recipient-thread system message with
  role-correct copy.
- Introducer-side mutual acceptance writes a recipient-thread system message
  and a role-correct notification.
- Participant-side mutual-accept behavior stays green.
- Duplicate accept replay stays idempotent for introducer-side thread messages
  and notifications.
- The touched direct suites, broader intro application suite, Intro gate, and
  Baseline gate were rerun or any unrelated preexisting failure was explicitly
  documented.
- The breakdown persists an accepted session result and a final program
  verdict.

## 14. Scope Guard

- Do not change relay-server intro push generation in this session.
- Do not redesign the Intros tab, Orbit, Feed, or conversation layout.
- Do not widen into pass-specific introducer history unless the accept/mutual-
  accept closure bar cannot be met without it.
- Do not replace the participant-side mutual-accept copy with introducer copy.

## 15. Accepted Differences / Intentionally Out Of Scope

- Generic background `intros` push copy may remain neutral when richer
  role-aware data is not available.
- Pass-specific introducer timeline UX stays out of scope for this session.
- No server-side or transport re-rollout belongs to this session unless the
  local listener seam proves insufficient.

## 16. Dependency Impact

- If Session 1 lands cleanly, this doc can close without opening a separate
  push-architecture or intro-feed follow-up.
- If Session 1 proves the listener seam cannot represent the correct pair
  progress safely, the breakdown should record a real blocker instead of
  inventing a larger design mid-session.

## Structural Blockers Remaining

- None.

## Accepted Differences Intentionally Left Unchanged

- No relay-side role-aware intro push generation.
- No pass-specific introducer timeline UX.
- No Orbit or Feed redesign.

## Exact Docs/Files Used As Evidence

- `Test-Flight-Improv/Intro-Feature/intro-introducer-status-feedback-session-breakdown.md`
- `Test-Flight-Improv/Intro-Feature/intro-introducer-status-feedback.md`
- `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Intro-Feature/test-inventory.md`
- `lib/features/introduction/application/introduction_copy.dart`
- `lib/features/introduction/application/introduction_listener.dart`
- `lib/features/introduction/application/insert_intro_system_message.dart`
- `test/features/introduction/application/introduction_copy_test.dart`
- `test/features/introduction/application/introduction_listener_test.dart`
- `test/features/push/application/background_push_notification_fallback_test.dart`

## Why The Plan Is Safe To Implement Now

- The missing behavior is narrow and already sits inside the existing intro
  listener and intro-copy seam.
- The direct regressions are clear and keep the blast radius inside intro
  application code plus one push fallback test.
- No structural blocker remains, and the stop rule is explicit if the current
  seam cannot close the gap safely.
