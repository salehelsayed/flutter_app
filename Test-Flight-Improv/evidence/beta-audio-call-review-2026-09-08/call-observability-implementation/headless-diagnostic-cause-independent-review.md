# Independent review: optional headless admission cause

Reviewed on 2026-09-08, read-only against the exact source and tests below. Graph context: `5feb217917a64e75` / `f0cb0dfdc3303a99`.

## Conclusion

No unresolved source findings in the reviewed patch. The optional diagnostic cause preserves admission, custody and cleanup decisions. It improves the explanation of a deferred result; it does not fix or establish the underlying cause of the live Android deferral.

One preservation counterexample was found during review and fixed by the Dart owner: an optional diagnostic getter could throw after successful evaluation/cleanup, change `admitted` to `deferred`, and trigger extra cleanup; a backend getter could escape from the fallback. All runner reads now use a nonthrowing accessor. Exact regressions preserve the original result, persistence/custody flags and cleanup counts. This was an injectable diagnostic-boundary defect, not evidence that it caused the live call failure.

## Verified boundaries

- The Dart mailbox evaluator retains the original disposition, ACK and replay rollback decisions. The lease decorator forwards the same seven gateway methods, performs one acquisition and returns the original snapshot. Stop, expiry and cleanup gates remain in the same order.
- The completion envelope retains its eight required authority fields. The only optional addition is `diagnosticCause`. Dart emits it only when it is a member of the shared closed reason allowlist. Private text, a call identifier and an absent value retain the legacy envelope shape.
- Native parsing still requires exact identity/nonce/expiry equality, known disposition and Boolean custody fields. Unknown extra keys remain rejected. Malformed optional cause values are ignored without rejecting an otherwise valid completion; valid diagnostic metadata cannot make a wrong nonce valid.
- Native execution checks the optional cause against the allowlist again before logging. An unsatisfied persistence gate reports `pending` with the known cause or `unknown`; the Boolean alone no longer implies that a write failed. The raw custody flags remain available for interpretation.
- Runner finalization remains noncancellable, clears only its owned active runner, and finishes before any authenticated presentation. Diagnostic sink/clock failures are contained. No diagnostic value participates in the call identity or admission gates.

## Validation

The saved Dart log `headless-cause-schema-final-green.log` reports 53 passing tests, including both throwing-getter regressions, completion-envelope privacy tests and the existing runtime preservation tests. The corresponding analyzer log reports no issues. The independent review read both logs and the exact assertions.

The native test source includes malformed optional metadata and wrong-nonce cases, all disposition/custody cases, deferred cause with no presentation, timeout/exception privacy and a throwing diagnostic sink preserving `finish` then `present`. The independent review read `native-cause-build-final.log` (`BUILD SUCCESSFUL in 12s`) and `native-cause-build-test-totals.json`: 101 tests passed with zero failures, errors or skips, including all 21 `HeadlessCallAdmissionWorkerTest` cases, 16 spool, 19 bridge, 33 lifecycle and 12 FCM tests. The native owner confirmed the reviewed parser/execution source remained unchanged for this run.

## Reviewed source fingerprints

| File | SHA256 |
| --- | --- |
| `lib/app/bootstrap/production_headless_call_admission.dart` | `d656dc66cc969dcead925b5fab1a726e8401ccda4e162b12d53c5f2784a09b32` |
| `lib/features/call/infrastructure/headless_call_admission_entrypoint.dart` | `1797f5e1c02df8ee78c39f7ad7c6c83603022c7b98c95bc05f91985a783dcab6` |
| `android/app/src/main/kotlin/com/mknoon/app/call/HeadlessCallAdmissionWorker.kt` | `b4689f835ff8728ecd3e9baedad46521a09aa6a9dad838ac40683738a1dc0566` |
| `test/core/bootstrap/production_headless_call_admission_test.dart` | `266b212c35c08f012e30a82b0f6b6d4d7df9823ce599646434d3c04bb9626143` |
| `test/features/call/infrastructure/headless_call_admission_entrypoint_test.dart` | `fb83c5383f5f2faaf041773864880b8f707575f13a803fe20b909190cf1ef08f` |
| `android/app/src/test/kotlin/com/mknoon/app/call/HeadlessCallAdmissionWorkerTest.kt` | `0f7da661e518146fa26f9d9ea5e0ed110aabe3932ae84a642cd3a401f6ea1002` |

This review performed no phone actions, production mutations, call-authority edits or private-record exports. Existing closed reason values require no new relay schema or Go binding build.
