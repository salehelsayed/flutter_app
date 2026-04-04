# Session 2 Plan: 1:1 text, active-conversation, and multi-thread journey coverage

## Real scope

- Close the Session 2 coverage gaps for `2.2`, `2.3`, `2.4`, `18.1`, and
  `18.2` from
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md`.
- Keep the work on 1:1 text-thread behavior only: rapid bilateral exchange,
  long-message rendering, live receive while the target conversation is
  already open, and isolation across concurrent 1:1 threads.
- Do not widen into media transfer, transport/lifecycle recovery, contact
  bootstrap, or introduction flows.

## Closure bar

Session 2 is good enough when the repo has direct automated evidence that:

- rapid bilateral 1:1 bursts keep delivery status and ordering honest,
- long text still renders legibly in the actual 1:1 presentation seam,
- an already-open conversation surface reflects a newly received message
  without needing a route reset, and
- concurrent 1:1 contacts stay isolated so one contact's activity does not
  contaminate another thread/card state.

The session may finish as test-only if current production code already behaves
correctly and only stronger direct proof is missing.

## Source of truth

- Active controller doc:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-breakdown.md`
- Proposal/source doc:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo.md`
- Coverage matrix and gap statements:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md`
- Regression policy:
  `Test-Flight-Improv/14-regression-test-strategy.md`
- Gate source of truth:
  `Test-Flight-Improv/test-gate-definitions.md`

When docs disagree with current repo code/tests, repo evidence wins. In
particular, this session must refresh against the already-modified
`test/features/feed/presentation/screens/feed_wired_test.dart` and
`test/features/feed/domain/utils/group_messages_into_threads_test.dart`
instead of assuming the audit text is still fully current.

## Session classification

`implementation-ready`

## Exact problem statement

The repo already has useful 1:1 building blocks, but the current coverage story
for these rows is still fragmented:

- `2.2` has basic bilateral exchange proof in
  `test/features/conversation/integration/two_user_message_exchange_test.dart`,
  but not the explicit rapid multi-round burst with delivered-state assertions
  the audit calls out.
- `2.3` still lacks a direct long-message rendering assertion in the actual
  letter/conversation UI seam.
- `2.4` has adjacent listener and notification suppression coverage, but not a
  direct open-conversation screen proof unless current repo edits already added
  one.
- `18.1` and `18.2` have stronger current thread-isolation evidence than the
  original audit captured:
  `test/features/feed/domain/utils/group_messages_into_threads_test.dart`
  already proves separate threads per contact and same-contact burst grouping,
  and `test/features/feed/presentation/screens/feed_wired_test.dart` now
  contains an "incoming chat updates only the affected contact thread" proof.
  Session 2 still needs to determine whether one more direct proof is required
  for rapid A/B switching or whether current landed tests already close that
  ask honestly.

The goal is to add only the minimum direct proofs still missing after that
current-repo refresh.

## Files and repos to inspect next

Production files:

- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/conversation/application/mark_conversation_read_use_case.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/feed/application/feed_projection.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/core/notifications/active_conversation_tracker.dart`

Primary direct tests:

- `test/features/conversation/integration/two_user_message_exchange_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/conversation/presentation/widgets/letter_card_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/feed/integration/feed_card_flow_test.dart`
- `test/features/feed/domain/utils/group_messages_into_threads_test.dart`

## Existing tests covering this area

- `test/features/conversation/integration/two_user_message_exchange_test.dart`
  already covers baseline bilateral exchange, duplicate rejection, and offline
  inbox continuity.
- `test/features/feed/domain/utils/group_messages_into_threads_test.dart`
  already covers multiple contacts producing separate threads and same-contact
  burst grouping.
- `test/features/feed/presentation/screens/feed_wired_test.dart` already
  contains targeted per-contact thread update proof in the current worktree.
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  already covers optimistic send and message list behavior, but it still needs
  a direct read on whether open-conversation live receive is proven.
- `test/features/conversation/presentation/widgets/letter_card_test.dart`
  covers status and message-body basics, but not the long-message rendering
  scenario named by the audit.

## Regression/tests to add first

- Extend `test/features/conversation/integration/two_user_message_exchange_test.dart`
  with:
  - a rapid multi-round bilateral burst that asserts all sends settle as
    delivered and both conversations preserve full ordered history;
  - if still needed after repo refresh, a narrow multi-contact interleave proof
    that keeps Bob and Cara isolated in Alice's conversation state.
- Add the smallest direct long-message rendering proof to either
  `test/features/conversation/presentation/widgets/letter_card_test.dart` or
  `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  based on where the real rendering seam lives.
- Add one open-conversation receive proof to
  `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  if the current file does not already show a newly arrived message while the
  screen remains mounted.
- Only touch `test/features/feed/presentation/screens/feed_wired_test.dart`
  when current evidence shows the existing per-contact thread update test still
  falls short of the `18.1` / `18.2` ask.

## Step-by-step implementation plan

1. Re-read the Session 2 matrix rows and the current worktree versions of the
   six direct test files above.
2. Reclassify `18.1` and `18.2` against current repo evidence before adding
   anything new.
3. Prefer test-only strengthening first; add production code only if a new
   direct proof exposes a real 1:1 thread-state bug.
4. Land the rapid bilateral exchange proof in the deterministic two-user
   integration seam.
5. Land the long-message and open-conversation proofs in the smallest widget or
   screen seam that honestly exercises the behavior.
6. Run the exact direct Session 2 suites.
7. Run `./scripts/run_test_gates.sh 1to1`.
8. Run `./scripts/run_test_gates.sh feed` only if accepted changes touched feed
   production code or feed-owned direct proofs.
9. Run `./scripts/run_test_gates.sh baseline` only if execution widened into
   shared startup or notification/app-root behavior.

## Risks and edge cases

- Rapid-exchange tests can become timing-sensitive if they rely on sleeps
  instead of deterministic fake-network sequencing.
- A long-message test can become a shallow text-presence check that misses the
  actual rendering seam.
- Multi-contact isolation proof can duplicate current feed-thread tests unless
  execution first refreshes against the modified worktree.
- The dirty worktree already includes non-Session-2 changes in feed and
  conversation files; execution must work with those edits rather than
  overwriting them.

## Exact tests and gates to run

Direct suites required for Session 2:

```bash
flutter test test/features/conversation/integration/two_user_message_exchange_test.dart
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart
flutter test test/features/conversation/presentation/widgets/letter_card_test.dart
flutter test test/features/feed/presentation/screens/feed_wired_test.dart
flutter test test/features/feed/integration/feed_card_flow_test.dart
flutter test test/features/feed/domain/utils/group_messages_into_threads_test.dart
```

Required named gate:

```bash
./scripts/run_test_gates.sh 1to1
```

Conditional named gates:

```bash
./scripts/run_test_gates.sh feed
./scripts/run_test_gates.sh baseline
```

Run `feed` only if feed-owned production or direct proof changes land. Run
`baseline` only if execution touches shared startup, notification, or app-root
paths.

## Known-failure interpretation

- Treat unrelated pre-existing failures in the dirty worktree as historical
  noise unless one of the exact Session 2 direct suites or named gates fails.
- If `feed_wired_test.dart` already contains newer current-repo proof than the
  audit assumed, that is accepted updated evidence, not a Session 2 regression.

## Done criteria

- Session 2 has direct proof or honest current-repo reclassification for `2.2`,
  `2.3`, `2.4`, `18.1`, and `18.2`.
- The exact direct suites are green.
- `./scripts/run_test_gates.sh 1to1` is green.
- No media, lifecycle, or startup scope was pulled into the landing.
- The breakdown ledger is updated with the accepted outcome and exact evidence.

## Scope guard

- No media viewer/upload changes.
- No transport, resume, reconnect, or migration work.
- No contact bootstrap or introduction flow changes.
- No gate-definition edits unless a new permanent direct suite truly needs
  classification.

## Accepted differences / intentionally out of scope

- Session 2 does not need real transport/device-backed proof; deterministic
  direct suites are enough for this seam.
- Session 2 does not need a brand-new feed harness if the current feed and
  conversation tests already express the needed thread isolation directly.

## Dependency impact

- Session 2 has no prerequisite session dependency.
- Its outcome informs only the final Session 10 matrix refresh and any later
  1:1 closure wording decisions; it should not reopen Sessions 1, 3, or 7
  unless execution reveals a shared bug outside the stated scope.
