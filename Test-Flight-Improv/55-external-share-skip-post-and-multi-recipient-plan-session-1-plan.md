# 55 - External Share Skip Post and Multi-Recipient Plan - Session 1 Plan

## Final Verdict

`execution-safe`

## 1. Real Scope

This session changes only the native iOS external-share handoff seam and the
proof for that seam:

- update `ios/Share Extension/ShareViewController.swift` so the share extension
  redirects into Mknoon without waiting for the native `Post` button
- update the direct iOS source regression so the repo no longer accepts the
  current manual `Post` gate as intentional behavior
- capture executable native proof the repo can run locally:
  - the direct iOS source regression
  - a successful `iphonesimulator` Runner build that includes the share
    extension target

This session does not change:

- the Flutter picker interaction model
- batch-send behavior
- Android share entry
- startup/onboarding/QR routing unless the native redirect evidence proves a
  narrow dependency-threading issue

## 2. Closure Bar

Session 1 is good enough only when all of the following are true:

- iOS share entry no longer relies on the native `Post` compose screen
- the source regression explicitly proves the redirect seam now auto-redirects
- the `iphonesimulator` Runner build completes successfully with the share
  extension still integrated into the host app packaging path
- no new native packaging blocker remains that would make Session 2 unsafe to
  start

## 3. Source Of Truth

Primary repo evidence for this session:

- `Test-Flight-Improv/55-external-share-skip-post-and-multi-recipient-plan-session-breakdown.md`
- `Test-Flight-Improv/55-external-share-skip-post-and-multi-recipient-plan.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `ios/Share Extension/ShareViewController.swift`
- `ios/Share Extension/RSIShareFallback.swift`
- `test/core/services/share_intent_ios_test.dart`

Disagreement rule:

- current code and direct tests beat stale prose
- the session breakdown is the active contract for scope/dependency
- `test-gate-definitions.md` is authoritative if this unexpectedly widens into
  Flutter production code

## 4. Session Classification

`evidence-gated`

## 5. Exact Problem Statement

Current repo evidence shows the iOS share extension still blocks on the native
compose screen because `ShareViewController.shouldAutoRedirect()` returns
`false`. The existing source regression covers extension setup but does not pin
the redirect expectation, so the repo currently accepts the wrong first-screen
behavior as valid. This session must correct that seam and prove, with
executable native evidence, that the redirect contract is intentional and still
packages cleanly through the host app plus share-extension build.

## 6. Files And Repos To Inspect Next

Production files:

- `ios/Share Extension/ShareViewController.swift`
- `ios/Share Extension/RSIShareFallback.swift` as source-of-truth reference only

Tests and docs:

- `test/core/services/share_intent_ios_test.dart`
- `Test-Flight-Improv/55-external-share-skip-post-and-multi-recipient-plan-session-breakdown.md`

Native build tooling:

- `xcodebuild` against `ios/Runner.xcworkspace`

## 7. Existing Tests Covering This Area

Already covered:

- `test/core/services/share_intent_ios_test.dart` proves the extension wiring,
  entitlements, and fallback/controller presence

Missing and required for this session:

- a direct assertion that the extension now auto-redirects instead of waiting
  for native `Post`
- executable native proof that the updated redirect still builds and packages
  with the host app plus share extension

## 8. Regression/Tests To Add First

Update `test/core/services/share_intent_ios_test.dart` first so it explicitly
asserts the controller source contains the auto-redirect contract and no longer
permits the current `false` override. This is the fastest direct proof that the
native seam changed intentionally before the native build validation.

## 9. Step-By-Step Implementation Plan

1. Inspect `ShareViewController.swift` and the current iOS share regression to
   confirm the only native seam in play is `shouldAutoRedirect()`.
2. Update the direct source regression first so it fails against the current
   `false` behavior and expects auto-redirect instead.
3. Change `ShareViewController.swift` to auto-redirect into the host app.
4. Run the direct iOS regression suite:
   `flutter test test/core/services/share_intent_ios_test.dart`.
5. Run the explicit native packaging proof:
   `xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build`.
6. If the source regression fails or the `iphonesimulator` build fails, stop
   and record Session 1 as blocked in the breakdown instead of continuing to
   Session 2.
7. If both commands pass, update the breakdown ledger with the exact proof
   captured and unblock Session 2.

## 10. Risks And Edge Cases

- the receive-sharing-intent plugin may rely on the old native callback timing;
  auto-redirect could surface a hidden integration issue that only appears in
  native packaging or later runtime validation
- this session does not exercise a full share-sheet invocation end to end, so
  later rollout notes must not overclaim release validation from this session
- if the native change unexpectedly touches Flutter startup/share routing, this
  session must stop and explicitly record that widened seam before any broader
  work

## 11. Exact Tests And Gates To Run

Required direct test:

- `flutter test test/core/services/share_intent_ios_test.dart`

Required native proof:

- `xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build`

Named gates:

- none by default
- run `./scripts/run_test_gates.sh baseline` only if execution widens into
  Flutter production files beyond the native extension seam

## 12. Known-Failure Interpretation

There is no known approved failure for this direct iOS regression. A failure in
`test/core/services/share_intent_ios_test.dart` after the regression update is
new evidence that the native seam was not landed coherently. A failing
`iphonesimulator` build is also blocking, not a deferable follow-up.

## 13. Done Criteria

- `ShareViewController.swift` auto-redirects
- `test/core/services/share_intent_ios_test.dart` directly proves that contract
- the direct regression passes
- the `iphonesimulator` Runner build succeeds with the updated share-extension
  contract intact
- the session breakdown ledger records the result clearly enough for Session 2

## 14. Scope Guard

- do not change picker UI, selection state, or send behavior in this session
- do not redesign native share-extension plumbing beyond the redirect seam
- do not touch Android unless a separate reproduced issue appears
- do not treat a missing or failing `iphonesimulator` build as acceptable
  completion

## 15. Accepted Differences / Intentionally Out Of Scope

- Android native entry remains unchanged
- the Flutter picker stays single-target until Session 2
- no batch-send coordination or closure-doc refresh belongs in this session

## 16. Dependency Impact

- Session 2 depends on this session closing acceptably
- if Session 1 blocks on native packaging or direct regression proof, Session 2
  must stay `prerequisite-blocked`
- if Session 1 lands cleanly, Session 2 may proceed with the Flutter picker and
  batch-send slice

## Structural Blockers Remaining

- none in the plan itself; execution must still prove the simulator-backed
  native packaging contract

## Incremental Details Intentionally Deferred

- none

## Accepted Differences Intentionally Left Unchanged

- broader share-flow redesign and multi-recipient behavior stay for Session 2

## Exact Docs/Files Used As Evidence

- `Test-Flight-Improv/55-external-share-skip-post-and-multi-recipient-plan-session-breakdown.md`
- `Test-Flight-Improv/55-external-share-skip-post-and-multi-recipient-plan.md`
- `ios/Share Extension/ShareViewController.swift`
- `ios/Share Extension/RSIShareFallback.swift`
- `test/core/services/share_intent_ios_test.dart`

## Why The Plan Is Safe To Implement Now

The plan is bounded to one native seam, one direct regression family, and one
explicit native build proof that the repo can actually execute in automation. It
does not guess about later Flutter work, and it stops explicitly if the redirect
breaks native packaging, which keeps Session 2 from building on false
assumptions.
