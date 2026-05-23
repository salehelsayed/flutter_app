# INTRO-REL-010 Execution Plan

Status: execution-ready

## Planning Progress

| Timestamp | Role | Files inspected since last update | Decision/blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-22 21:37 CEST | Planner completed | Draft plan sections in this file. | Draft includes single-row scope, closure bar, source of truth, regression-first steps, direct tests, intro gate, dirty-worktree handling, and Device/Relay non-requirement. | Run strict Reviewer pass against sufficiency questions. |
| 2026-05-22 21:37 CEST | Reviewer started | Full draft plan in this file. | No blocker; review will classify sufficiency, missing files/gates, stale assumptions, and overengineering. | Inspect mandatory headings and exact row/gate language. |
| 2026-05-22 21:38 CEST | Reviewer completed | Full draft plan; mandatory heading check; row/gate language scan; ASCII scan. | Sufficient with one wording adjustment: make the seeded local row explicitly map B to `ownPeerId` to avoid fixture ambiguity. No missing gate or hidden simulator/relay scope found. | Patch the fixture wording and run Arbiter classification. |
| 2026-05-22 21:39 CEST | Arbiter started | Reviewer findings and patched plan. | No blocker identified before classification; verify no structural blocker remains. | Classify structural blockers, incremental details, and accepted differences. |
| 2026-05-22 21:39 CEST | Arbiter completed | Reviewer findings; patched mandatory sections; row/gate/scope guards. | No structural blockers. One incremental detail was already applied; accepted differences are host-only proof, no simulator, no relay, and no Device/Relay profile. | Plan is execution-ready; next agent may execute tests-only closure for `INTRO-REL-010`. |

## Execution Progress

| Timestamp | Phase | Files inspected or touched | Decision/blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-22 21:41 CEST | Contract extraction started | `Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-010-plan.md`; `test/features/introduction/application/handle_incoming_introduction_test.dart`; `git status --short` | Scope is tests-only for valid-existing-intro forged live `accept`/`pass`; worktree is dirty with unrelated intro/relay/DB changes. No nested spawn tool is available, so execution will use the skill's local sequential fallback. | Complete contract extraction and update the owned handler test only unless the regression exposes a real product bug. |
| 2026-05-22 21:41 CEST | Contract extraction completed | Same as above | Required proof: forged X response claiming C is rejected, stored intro status remains unchanged, no pending response is staged, and no B-C contact is created for both `accept` and `pass`. Required commands: `flutter test --no-pub test/features/introduction/application/handle_incoming_introduction_test.dart` and `./scripts/run_test_gates.sh intro`. | Start local Executor implementation in the owned handler test. |
| 2026-05-22 21:42 CEST | Local Executor implementation started | `test/features/introduction/application/handle_incoming_introduction_test.dart`; `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`; shared in-memory fakes | Existing handler rejects response transport-sender mismatches before response staging/loading. Add focused valid-existing-row regression without product edits. | Patch handler test with accept/pass table coverage. |
| 2026-05-22 21:43 CEST | Local Executor implementation completed | `test/features/introduction/application/handle_incoming_introduction_test.dart` | Added valid-existing-intro forged live `accept`/`pass` regression. Product code was not changed. `dart format` reported `Formatted 1 file (0 changed)`. | Run required direct touched test. |
| 2026-05-22 21:43 CEST | Direct test started | `test/features/introduction/application/handle_incoming_introduction_test.dart` | Command running: `flutter test --no-pub test/features/introduction/application/handle_incoming_introduction_test.dart`. | Record result and run intro gate if direct test passes. |
| 2026-05-22 21:43 CEST | Direct test completed | `test/features/introduction/application/handle_incoming_introduction_test.dart` | PASS: `flutter test --no-pub test/features/introduction/application/handle_incoming_introduction_test.dart` completed with `00:00 +31: All tests passed!`. | Run required named intro gate. |
| 2026-05-22 21:44 CEST | Intro gate started | `scripts/run_test_gates.sh`; intro gate membership | Command running: `./scripts/run_test_gates.sh intro`. | Record gate result, then run local QA review. |
| 2026-05-22 21:44 CEST | Intro gate completed | `scripts/run_test_gates.sh`; intro gate membership | PASS: `./scripts/run_test_gates.sh intro` completed with `00:05 +204: All tests passed!`. | Start separate local QA review. |
| 2026-05-22 21:44 CEST | Local QA Reviewer started | Plan progress; `test/features/introduction/application/handle_incoming_introduction_test.dart`; git diff for touched files | Direct test and required named gate passed. Review will check scope adherence, required assertions, and product-code no-touch. | Complete QA review and write final verdict. |
| 2026-05-22 21:45 CEST | Local QA Reviewer completed | `test/features/introduction/application/handle_incoming_introduction_test.dart`; `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-INTRO-REL-010-plan.md`; `git diff --check` | No blocking issues. Regression covers both `accept` and `pass`, seeds an existing valid A/B/C row with local B as `ownPeerId`, asserts rejected result/null model, unchanged stored intro fields, empty pending responses, and no `peer-C` contact. Product code was not edited by this session. `git diff --check` passed. | Write final verdict. |
| 2026-05-22 21:45 CEST | Final verdict written | Same as above | accepted. Required direct test and intro gate passed; source matrix and breakdown were not updated per execution scope. | Stop. |

## real scope

This session owns only `INTRO-REL-010`: a valid local intro row already exists for A/B/C, then unauthorized peer X sends live forged `accept` and `pass` responses claiming `responderId = C`.

Expected row-owned assertions:

- the forged response is rejected with the sender-binding diagnostic already used by the listener/handler path
- the existing intro row has no status mutation after the forged response
- no pending response row is created for that intro
- no B-C contact is created

Default scope is tests-only. Product code may be changed only if the new exact regression fails and the failure proves a real sender-binding/application-state bug.

Owner files for expected test work:

- `test/features/introduction/application/introduction_listener_test.dart`
- `test/features/introduction/application/handle_incoming_introduction_test.dart`

Likely production files to inspect only if the regression fails:

- `lib/features/introduction/application/introduction_listener.dart`
- `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`
- `lib/features/introduction/domain/repositories/introduction_repository.dart`
- `lib/features/introduction/domain/repositories/introduction_repository_impl.dart`

Do not edit source matrix or breakdown status during planning. Source row `INTRO-REL-010` remains `Open` until execution lands the row-owned test and the required gates pass.

## closure bar

Good enough for this session means an automated host-side regression proves the existing-row trust boundary directly: a live response delivered as X but claiming to be C cannot alter B's stored intro state, cannot create or preserve a forged pending response, and cannot create a B-C contact.

Closure requires:

- at least one direct test covers an already persisted valid intro row before the forged response arrives
- both `accept` and `pass` forged response variants are covered, either by two focused cases or a small loop/table in one focused test
- the test verifies pre-state and post-state for intro statuses, pending responses, and contact existence
- direct touched test command passes
- `./scripts/run_test_gates.sh intro` passes
- only after execution/gates, `INTRO-REL-010` can be updated from `Open` to `Covered` with concrete evidence

No Device/Relay Proof Profile is required because this is host-only sender-binding/application-state coverage. It does not change or prove relay storage, direct transport routing, iOS simulator behavior, or three-device delivery.

## source of truth

Authoritative order on disagreement:

1. Current production code and direct tests in the repo.
2. `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` for gate membership.
3. `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15.md` for row requirement and status.
4. `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-breakdown.md` for current session decomposition.
5. This plan for `INTRO-REL-010` execution scope only.

Evidence collected:

- Source row `INTRO-REL-010` is `Open` and requires forged `accept` or `pass` after a valid intro row exists to leave status, pending responses, and contacts unchanged.
- Breakdown classifies `INTRO-REL-010` as `needs_tests_only` / `tests-only`.
- `introduction_listener.dart` rejects payloads where `message.from` does not match `responderId` for `accept`/`pass`.
- `handle_incoming_introduction_use_case.dart` rejects `transportSenderPeerId` mismatch before response staging or applying.
- Existing tests cover forged send, forged deferred response before an intro row exists, and mismatched pending replay discard, but not the exact valid-existing-row live forged response.

## session classification

`implementation-ready`

The work is execution-ready as a tests-only gap closure. It becomes code-and-tests only if the row-owned regression fails against current product behavior.

## exact problem statement

`INTRO-REL-010` is still open because existing coverage proves sender binding around adjacent states, but not the exact row state: B already has a valid A/B/C intro row, then unauthorized X sends a live response claiming to be C.

The missing safety proof is that local intro truth does not make the handler trust forged payload fields. User-visible behavior must improve by preventing a false B-C introduction state or contact from appearing after a forged response. Existing valid accept/pass flows, pending replay behavior, and terminal-state protections must stay unchanged.

## files and repos to inspect next

Test files:

- `test/features/introduction/application/introduction_listener_test.dart`
- `test/features/introduction/application/handle_incoming_introduction_test.dart`
- `test/shared/fakes/in_memory_introduction_repository.dart`
- `test/shared/fakes/in_memory_contact_repository.dart`

Production files only if the new assertion fails:

- `lib/features/introduction/application/introduction_listener.dart`
- `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`
- `lib/features/introduction/domain/repositories/introduction_repository.dart`
- `lib/features/introduction/domain/repositories/introduction_repository_impl.dart`

Gate/docs to inspect during execution:

- `scripts/run_test_gates.sh`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15.md`
- `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-breakdown.md`

## existing tests covering this area

Current adjacent coverage:

- `introduction_listener_test.dart` has `rejects send when transport sender does not match payload introducer`.
- `introduction_listener_test.dart` has `rejects deferred response when transport sender does not match responder`.
- `introduction_listener_test.dart` has a v2 envelope transport-sender mismatch test.
- `handle_incoming_introduction_test.dart` has `transport sender mismatch rejects response before staging`, which proves direct handler rejection and no pending response when no intro row exists.
- `handle_incoming_introduction_test.dart` has `pending response with mismatched transport sender is discarded during replay`, which proves replay safety.
- `handle_incoming_introduction_test.dart` has terminal-state contact guards for late pass/accept rows `INTRO-REL-006` and `INTRO-REL-007`.

Missing row-owned coverage:

- no direct test seeds a valid existing intro row, sends a live forged `accept` or `pass` from X claiming `responderId = C`, and asserts no status mutation, no pending response, and no B-C contact creation.

## regression/tests to add first

Add a focused regression before any product edit.

Preferred shape:

- In `handle_incoming_introduction_test.dart`, seed `IntroductionModel(id: 'intro-existing-forged-response', introducerId: 'peer-A', recipientId: ownPeerId, introducedId: 'peer-C', recipientStatus: pending, introducedStatus: pending, status: pending)` so B is represented by the local peer under test.
- Assert `contactRepo.contactExists('peer-C')` is false and `introRepo.loadPendingResponses(introId)` is empty before delivery.
- Deliver forged live response(s) through `handleIncomingIntroduction` with `transportSenderPeerId: 'peer-forger'`, payload `responderId: 'peer-C'`, and action `accept`, then repeat for `pass` with isolated ids or table-driven cases.
- Assert result is `HandleIntroductionResult.rejected`, returned model is null if current handler rejects before load, stored intro remains unchanged, pending responses remain empty, and `contactExists('peer-C')` remains false.

Optional listener-level addition if implementation chooses to prove the full listener dispatch seam:

- In `introduction_listener_test.dart`, pre-save the same valid intro, send `ChatMessage(from: 'peer-forger', content: IntroductionPayload(action: 'accept'/'pass', responderId: 'peer-C').toJson())`, then assert `IntroductionMessageProcessState.rejected`, `reasonCode == 'transport_sender_mismatch'`, stored intro unchanged, no pending rows, no contact, no notification, and no system message.

The direct handler test is the minimum closure proof because it owns application-state mutation and pending-response staging. A listener test is useful when the executor wants row evidence through `processIncomingMessage`, but it should not duplicate broad notification assertions unless they are cheap and local.

## step-by-step implementation plan

1. Capture the dirty worktree before editing with `git status --short`; do not revert unrelated intro, relay, DB, plist, pubspec, or existing test changes.
2. Open the two owner tests and choose the smallest test location that matches existing style. Prefer extending `handle_incoming_introduction_test.dart` under `handleIncomingIntroduction - accept/pass actions`.
3. Add the row-owned regression first. Use isolated intro ids per action or a table loop so accept and pass cannot mask each other.
4. Run the direct touched test expected to include the new regression:
   `flutter test --no-pub test/features/introduction/application/handle_incoming_introduction_test.dart`
   If a listener test is also touched, also run:
   `flutter test --no-pub test/features/introduction/application/introduction_listener_test.dart`
5. If the new assertion passes without product edits, keep the session tests-only.
6. If the new assertion fails, inspect only the likely production files listed above and make the smallest sender-binding fix that rejects before any existing-row status update, pending-response staging, contact creation, notification, or system-message side effect.
7. Rerun the direct touched test(s).
8. Run the required named gate:
   `./scripts/run_test_gates.sh intro`
9. Only after direct tests and the intro gate pass, update row closure docs in the execution/closure phase: source matrix row `INTRO-REL-010`, breakdown row disposition/session ledger, and `test-inventory.md` only if the test inventory needs to mention the new row-owned assertion.

Stop if evidence shows an equivalent exact valid-existing-row forged-response assertion already exists and passes. In that case, do not add duplicate coverage; document the exact test name and run the required direct test plus intro gate before closure.

## risks and edge cases

- A too-broad listener test could overfit notification/message side effects and obscure the row-owned state invariant. Keep the primary proof on status, pending rows, and contact creation.
- A test that omits a pre-existing intro row would duplicate `INTRO-REL-009` instead of closing `INTRO-REL-010`.
- A test that only covers `accept` leaves the source row's `accept/pass` language under-proved. Cover both variants.
- A false positive can occur if the test asserts only the rejected result but does not reload the stored intro and contact repository after delivery.
- Dirty worktree files already include introduction production/tests and unrelated relay/DB files. Treat failures in files not touched by this session as possible pre-existing unless direct evidence ties them to the new assertion.

## exact tests and gates to run

Required direct test:

```bash
flutter test --no-pub test/features/introduction/application/handle_incoming_introduction_test.dart
```

Required if `introduction_listener_test.dart` is touched:

```bash
flutter test --no-pub test/features/introduction/application/introduction_listener_test.dart
```

Required named gate:

```bash
./scripts/run_test_gates.sh intro
```

No iOS simulator E2E, relay Go test, transport gate, or Device/Relay Proof Profile is required for this session unless execution changes real transport, relay, simulator, or device behavior, which is outside the intended tests-only scope.

## known-failure interpretation

The direct touched test containing the new regression must pass. A failure in the new forged-existing-row assertion is a row-owned failure and either requires the smallest product fix or a documented discovery that the test setup is invalid.

For `./scripts/run_test_gates.sh intro`, classify failures by ownership:

- failures in the newly touched test or sender-binding behavior are row-owned and must be fixed before closure
- unrelated failures in other intro gate files may be pre-existing only if they reproduce without the session diff or are clearly tied to already-dirty unrelated files; record exact test names and output
- do not mark `INTRO-REL-010` as `Covered` while any row-owned direct test or intro-gate failure remains

## done criteria

- A valid-existing-intro live forged `accept` claiming C from X is covered.
- A valid-existing-intro live forged `pass` claiming C from X is covered.
- The regression asserts rejected outcome/diagnostic, unchanged stored intro statuses and overall status, no pending response, and no B-C contact creation.
- Direct touched test command passes.
- `./scripts/run_test_gates.sh intro` passes.
- Product code remains untouched unless the regression first proves a real bug.
- After execution/gates, closure docs can update source row `INTRO-REL-010` to `Covered` with concrete test and gate evidence.

## scope guard

Non-goals:

- do not implement new introduction protocol behavior
- do not change relay, direct transport, inbox storage, encryption, ML-KEM key selection, notification routing, or UI
- do not broaden into `INTRO-REL-015` retry behavior or any already covered row
- do not add simulator or device harnesses
- do not update `INTRO-REL-010` to `Covered` during planning or before gates pass
- do not revert unrelated dirty worktree changes

Overengineering for this session would be adding new sender-auth abstractions, new fake network layers, new Device/Relay proof docs, broad repository rewrites, or multi-row closure logic. The right fix, if needed, is a minimal sender-binding guard in the existing listener/handler path.

## accepted differences / intentionally out of scope

- Host-only application tests are accepted for `INTRO-REL-010` because the row is about deterministic sender-binding and local state mutation after a valid row exists.
- No iOS simulator E2E is required.
- No relay proof is required.
- No transport gate is required.
- No Device/Relay Proof Profile is required because no device, relay, or real transport behavior is being changed or certified.
- Source matrix and breakdown closure updates are intentionally deferred to the execution/closure phase after direct tests and the intro gate pass.

## dependency impact

Closing `INTRO-REL-010` removes one of the two remaining open rows in the TOP 15 intro reliability matrix. `INTRO-REL-015` remains independent and must not inherit this session's scope.

If the sender-binding regression exposes a product bug, later intro reliability work should treat the resulting guard as the canonical response sender-binding behavior for existing-row, deferred, and replay paths. If the test passes without product code, later work can rely on existing listener/handler sender-binding and should not reopen this row unless the exact no-mutation/no-pending/no-contact assertion or the intro gate regresses.

## reviewer checklist

- Plan status before review: `planning-draft`
- Mandatory sections present: yes
- Scope: single row, tests-only unless regression exposes real bug
- Required gates named: yes
- Dirty-worktree handling included: yes
- Matrix status guard included: yes
- Device/Relay Proof Profile note included: yes

## reviewer findings

Sufficiency: sufficient with the fixture wording adjustment applied above.

Missing files, tests, regressions, or gates: none. The plan names the expected owner tests, likely production files only if the regression fails, the direct touched test command, optional listener direct test if touched, and `./scripts/run_test_gates.sh intro`.

Stale or incorrect assumptions: none found after aligning the seeded intro row so local B is represented by `ownPeerId`.

Overengineering: none. The plan rejects simulator, relay, transport, Device/Relay proof, and multi-row expansion for this host-only sender-binding row.

Decomposition: sufficient. The plan gives one exact regression target with accept/pass variants and a stop rule if existing exact coverage is found.

Minimum needed to make sufficient: already applied. No structural blocker remains.

## arbiter decision

Structural blockers: none.

Incremental details: the reviewer-requested fixture wording adjustment was applied so the seeded existing intro maps B to local `ownPeerId`.

Accepted differences intentionally left unchanged:

- host-only application-state proof is sufficient for this sender-binding row
- no iOS simulator E2E is required
- no relay or transport gate is required
- no Device/Relay Proof Profile is required
- source matrix/breakdown closure updates wait until execution and gates pass

Final arbiter verdict: `execution-ready`.
