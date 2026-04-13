# Session 1 Plan: Intro Avatar Eventual Settlement

**Final Verdict:** sufficient as revised

## 1. Real Scope

- Keep Session 1 limited to intro-owned recovery for mutual-acceptance contacts
  whose initial avatar download window was missed.
- Reuse the existing intro recovery seam rather than inventing a generic global
  avatar retry subsystem.
- Preserve immediate contact creation, system message insertion, local
  new-connection notification behavior, and the existing no-rollback contract.
- Update only the intro docs needed to record the new later-settlement proof.
- Do not widen into unrelated contact-request, settings-global avatar, or
  transport work unless the intro-owned seam proves insufficient.

## 2. Closure Bar

- A later intro-owned recovery pass can retry avatar settlement for an
  already-created mutual-acceptance contact that still has no avatar.
- The direct tests prove that later recovery updates the contact avatar without
  duplicating the contact or duplicating the intro system message.
- The existing immediate contact-creation and avatar-failure no-rollback
  contracts remain green.
- The touched intro docs truthfully describe the new recovery proof and stop
  calling this seam best-effort only.

## 3. Source Of Truth

- Active session contract:
  - `Test-Flight-Improv/Intro-Feature/intro-avatar-eventual-settlement-session-breakdown.md`
- Product / proposal intent:
  - `Test-Flight-Improv/Intro-Feature/intro-avatar-eventual-settlement.md`
- Governing repo evidence:
  - `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`
  - `lib/features/introduction/application/expire_old_introductions_use_case.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/orbit/presentation/screens/orbit_wired.dart`
  - `lib/features/settings/application/profile_update_listener.dart`
  - `test/features/introduction/application/create_connection_on_mutual_acceptance_test.dart`
  - `test/features/introduction/application/expire_old_introductions_use_case_test.dart`
- Stable docs to refresh:
  - `Test-Flight-Improv/Intro-Feature/_Intro-reliability-gap-audit.md`
  - `Test-Flight-Improv/Intro-Feature/test-inventory.md`
  - `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md` only if execution actually changes the truth of `RM-013`
- On disagreement, current code and tests beat stale prose.

## 4. Session Classification

- `implementation-ready`

## 5. Exact Problem Statement

- `handleMutualAcceptance(...)` currently creates the new contact and then
  attempts avatar download only in one fire-and-forget window with a single
  retry.
- If that window is missed, the repo has no later intro-owned recovery path for
  a contact that already exists but still lacks an avatar.
- `expireOldIntroductions(...)` already runs on intro-related Feed/Orbit reloads
  and already reruns missed mutual-acceptance side effects for stale pending
  rows, but it does not revisit already-mutualAccepted contacts with missing
  avatars.
- User-visible behavior that must improve: a later app reload/recovery pass can
  settle the avatar for an intro-created contact after the initial window was
  missed.
- Behavior that must stay unchanged: contact creation must remain immediate,
  system message insertion must remain singular, and avatar failure must still
  never roll back the contact.

## 6. Files And Repos To Inspect Next

- Primary production seam:
  - `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`
  - `lib/features/introduction/application/expire_old_introductions_use_case.dart`
- Call-site evidence for later trigger:
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/orbit/presentation/screens/orbit_wired.dart`
- Adjacent but intentionally not primary:
  - `lib/features/settings/application/profile_update_listener.dart`
  - `lib/features/settings/application/download_profile_picture_use_case.dart`
- Direct regression surfaces:
  - `test/features/introduction/application/create_connection_on_mutual_acceptance_test.dart`
  - `test/features/introduction/application/expire_old_introductions_use_case_test.dart`
- Closure docs:
  - `Test-Flight-Improv/Intro-Feature/_Intro-reliability-gap-audit.md`
  - `Test-Flight-Improv/Intro-Feature/test-inventory.md`
  - `Test-Flight-Improv/Intro-Feature/intro-avatar-eventual-settlement-session-breakdown.md`

## 7. Existing Tests Covering This Area

- `test/features/introduction/application/create_connection_on_mutual_acceptance_test.dart`
  already proves:
  - contact creation on mutual acceptance
  - correct key and metadata mapping
  - system message insertion
  - avatar retry failure does not roll back the contact or system message
- `test/features/introduction/application/expire_old_introductions_use_case_test.dart`
  already proves:
  - stale pending mutualAccepted rows repair to mutualAccepted
  - contact recreation and system-message insertion rerun when the row was
    stored incorrectly as pending
  - passed / expired / alreadyConnected repair behavior
- Missing today:
  - no direct proof that a later intro-owned recovery pass settles the avatar
    for a mutualAccepted contact that already exists but still has no avatar
  - no direct proof that this later recovery remains idempotent for contact and
    system-message side effects

## 8. Regressions/Tests To Add First

- Extend `create_connection_on_mutual_acceptance_test.dart` with a focused case
  that proves an existing contact with a missing avatar can still trigger a
  later intro-owned avatar retry without duplicating system-message side
  effects, if `handleMutualAcceptance(...)` becomes the retry seam.
- Extend `expire_old_introductions_use_case_test.dart` with a direct later-
  settlement case:
  - intro already stored as `mutualAccepted`
  - contact already exists but has no avatar
  - first download window was missed
  - later intro recovery reruns and settles the avatar
  - no duplicate contact and no duplicate system message are produced
- Keep one existing no-rollback failure case green to prove the recovery change
  did not weaken the original safety contract.

## 9. Step-By-Step Implementation Plan

- Re-read `handleMutualAcceptance(...)` and `expireOldIntroductions(...)` to
  decide the smallest safe place to retry avatar settlement for existing
  mutualAccepted contacts.
- Implement a narrow avatar-retry helper or branch that:
  - only runs when the contact already exists
  - only retries when the contact still lacks an avatar
  - does not recreate the contact
  - does not insert another intro system message
- Extend `expireOldIntroductions(...)` so later Feed/Orbit intro refreshes can
  reach already-mutualAccepted intro rows with missing-avatar contacts.
- Add the direct later-settlement tests before widening documentation.
- Run the targeted intro application suites.
- If the change stays inside intro-owned application code, rerun the Intro gate
  and Baseline gate for closure.
- Update the audit, inventory, and breakdown once code and proof are stable.
- Stop as soon as later avatar settlement is truthful for intro-created
  contacts; do not widen into a generic avatar reconciler.

## 10. Risks And Edge Cases

- Duplicate accept or replay paths already call `handleMutualAcceptance(...)`;
  the new logic must not create duplicate contacts or duplicate system messages
  when a contact already exists.
- Existing contacts with an avatar already settled must remain a no-op.
- The later retry trigger must stay scoped to intro-created contacts or
  intro-owned mutualAccepted rows rather than sweeping every contact.
- `ProfileUpdateListener` still owns later versioned avatar updates; this
  session should not break or replace that path.
- Feed/Orbit currently call `expireOldIntroductions(...)`; if the new recovery
  hook relies on that path, the tests must prove the use case itself rather than
  only the UI callers.

## 11. Exact Tests And Gates To Run

- Direct suites while iterating:
  - `flutter test --no-pub test/features/introduction/application/create_connection_on_mutual_acceptance_test.dart`
  - `flutter test --no-pub test/features/introduction/application/expire_old_introductions_use_case_test.dart`
- Broader touched feature suite:
  - `flutter test --no-pub test/features/introduction/application`
- Named gates for closure:
  - `./scripts/run_test_gates.sh intro`
  - `./scripts/run_test_gates.sh baseline`
- Only if execution unexpectedly widens into lifecycle/transport:
  - `./scripts/run_test_gates.sh transport`

## 12. Known-Failure Interpretation

- No current known red state is documented for the direct intro application
  suites in this session plan.
- Treat any new failure in the targeted intro suites as a real Session 1 issue
  until proven otherwise.
- If the Intro or Baseline gate fails, first determine whether the failure is
  preexisting and unrelated; do not silently drop the gate from closure just to
  keep the rollout moving.

## 13. Done Criteria

- Later intro-owned recovery can settle a missing avatar for an already-created
  mutualAccepted contact.
- Direct tests prove no duplicate contact and no duplicate system message during
  later recovery.
- Immediate contact creation and no-rollback behavior remain green.
- The Intro and Baseline gates were rerun or any unrelated preexisting failure
  was explicitly documented.
- The breakdown persists an accepted session result and a final program verdict.

## 14. Scope Guard

- Do not build a generic global avatar background worker.
- Do not modify non-intro contact acceptance flows unless a narrow shared helper
  is strictly necessary and stays behavior-preserving.
- Do not widen into transport or push work unless the intro-owned recovery seam
  cannot close the gap.
- Do not change the meaning of `RM-013` unless the landed evidence really
  expands that matrix row's truthful contract.

## 15. Accepted Differences / Intentionally Out Of Scope

- Global avatar reconciliation for non-intro contacts remains out of scope.
- Later avatar updates driven by explicit remote `profile_update` messages stay
  owned by `ProfileUpdateListener`.
- No new transport, push, or settings-surface behavior belongs to this session.

## 16. Dependency Impact

- If Session 1 lands cleanly, doc 3 can proceed without inheriting any open
  intro-avatar blocker from this report.
- If Session 1 proves the intro-owned seam is insufficient, the batch should
  stop here and record that blocker rather than guessing at a larger avatar
  architecture mid-batch.

## Structural Blockers Remaining

- None.

## Accepted Differences Intentionally Left Unchanged

- No generic avatar worker.
- No profile-update redesign.
- No transport widening unless forced by evidence.

## Exact Docs/Files Used As Evidence

- `Test-Flight-Improv/Intro-Feature/intro-avatar-eventual-settlement-session-breakdown.md`
- `Test-Flight-Improv/Intro-Feature/intro-avatar-eventual-settlement.md`
- `Test-Flight-Improv/Intro-Feature/_Intro-reliability-gap-audit.md`
- `Test-Flight-Improv/Intro-Feature/test-inventory.md`
- `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`
- `lib/features/introduction/application/expire_old_introductions_use_case.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `lib/features/settings/application/profile_update_listener.dart`
- `test/features/introduction/application/create_connection_on_mutual_acceptance_test.dart`
- `test/features/introduction/application/expire_old_introductions_use_case_test.dart`

## Why The Plan Is Safe To Implement Now

- The missing behavior is narrow and already sits next to an existing intro-
  owned recovery seam.
- The plan keeps the blast radius inside intro application code and direct
  tests.
- No structural blocker remains, and the stop rule is clear if the seam proves
  insufficient.
