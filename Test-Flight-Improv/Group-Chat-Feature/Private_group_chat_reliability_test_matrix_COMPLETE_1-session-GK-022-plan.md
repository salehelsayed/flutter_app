Status: accepted/closed

# GK-022 Removed Member Cannot Decrypt Post-Removal Inbox Messages Plan

## Planning Progress

- 2026-05-12 17:10 CEST - Role: Arbiter completed - Files inspected since last update: source row GK-022, breakdown row 73, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_offline_replay_envelope.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/group_offline_replay_envelope_test.dart`, `go-mknoon/node/group_inbox.go`, and `go-mknoon/node/group_inbox_test.go`. Decision/blocker: execution-ready tests-first plan; no true external blocker and no production change is planned unless the row-owned RED proof shows plaintext decrypt/persistence or an unsafe decrypt attempt. Next action: execute this plan.
- 2026-05-12 17:09 CEST - Role: Reviewer completed - Files inspected since last update: existing future-epoch replay and MD-011 tests plus replay signature/decrypt helpers. Decision/blocker: plan is sufficient if it adds a GK-022-named stale-removed-member proof rather than overclaiming existing generic future-epoch or media-specific tests. Next action: arbiter classification.
- 2026-05-12 17:08 CEST - Role: Planner completed - Files inspected since last update: group offline replay envelope decode/decrypt path, drain decode-error handling, placeholder persistence, and Go group inbox recipient request shaping. Decision/blocker: smallest closure is a Dart offline replay test proving a removed/stale client with only E1 does not decrypt or render an E2 post-removal inbox envelope even if relay returns it. Next action: reviewer pass.
- 2026-05-12 17:06 CEST - Role: Evidence Collector completed - Files inspected since last update: source row GK-022, breakdown row 73, GK-021 closure, replay decrypt code, drain tests around future epochs and MD-011, and group inbox store request tests. Decision/blocker: repo already has the core missing-key/placeholder behavior, but GK-022 lacks a row-owned proof named for a removed member with old key and post-removal message content. Next action: draft the plan.
- 2026-05-12 17:05 CEST - Role: Controller fallback started - Files inspected since last update: child planner artifact. Decision/blocker: spawned planner wrote only intake and was closed as no-progress; continue planning locally under the skill workflow. Next action: collect concrete repo evidence.

## real scope

Own source row GK-022 only: "Removed member cannot decrypt inbox messages encrypted after removal." Add row-owned automated proof that a stale removed client C holding only the old E1 group key cannot decrypt or render a post-removal E2 inbox replay envelope, even if the relay returns that envelope to C.

Expected first implementation is tests-only in `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`. Production code changes are allowed only if the new GK-022 proof shows C's app calls `group.decrypt` with stale material, persists the post-removal plaintext, stores media/decrypt side effects, or otherwise renders post-removal content.

This session does not own removed-window backlog after re-add (GK-023), late-join history entitlement (GK-024), live PubSub validator behavior (GK-021/GK-025+), relay ACL enforcement, or broad group membership UX.

## closure bar

GK-022 closes because the source matrix row is now `Covered` with concrete evidence naming:

- a GK-022 row-owned offline replay test where the local/stale removed member has E1 only and the returned inbox envelope is signed/encrypted for E2
- proof that no `group.decrypt` bridge command is issued for the missing E2 key
- proof that the post-removal plaintext is not rendered or persisted, with only an undecryptable placeholder or skip evidence
- focused, adjacent replay/decrypt tests, the relevant group gate when practical, and `git diff --check`

## source of truth

Current code and tests win over stale prose. Source row GK-022 defines the acceptance contract. Breakdown row 73 defines this row-owned session and now records `covered/accepted` tests-only evidence. Existing GM-004, GM-005, GM-007, GM-013, GM-016, GM-033, and MD-011 evidence is supporting context only; GK-022 still needs a row-named proof for the inbox decrypt boundary.

## session classification

`implementation-ready` as tests-only first. If the focused GK-022 proof fails because post-removal plaintext is decrypted or persisted, reclassify this same session to code-and-tests and patch the smallest repo-owned seam in the offline replay decrypt/drain path or recipient filtering path shown by the failure.

## exact problem statement

The repo had generic future-epoch replay coverage and media-specific removed-member coverage, but lacked exact GK-022 evidence for a removed member C who still has the old key and retrieves an inbox message encrypted after removal. The user-visible privacy risk was that stale local state plus relay replay could render A/B post-removal plaintext to C.

The behavior that must stay unchanged:

- signed replay envelopes are still verified before trusted decode
- current members with the correct key can decrypt valid replay envelopes
- missing future keys create safe repair/placeholder behavior without plaintext
- GK-023 remains responsible for re-added C and removed-window backlog filtering

## files and repos to inspect next

- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/group_offline_replay_envelope.dart`
- `test/features/groups/application/group_offline_replay_envelope_test.dart`
- `go-mknoon/node/group_inbox.go`
- `go-mknoon/node/group_inbox_test.go`
- Supporting only if focused proof fails: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/group_config_payload.dart`, and `test/features/groups/application/send_group_message_use_case_test.dart`

## existing tests covering this area

- `future epoch encrypted replay creates one undecryptable placeholder without decrypting` proves a missing future epoch replay saves one undecryptable placeholder and does not call `group.decrypt`, but it is generic and not GK-022/removed-member named.
- `MD-011 removed member cannot decode future media replay with only the old epoch` proves media-specific future replay does not leak media/plaintext to a removed member, but GK-022 needs the generic group message row.
- `group_offline_replay_envelope_test.dart` proves replay signatures bind sender and payload before decrypt.
- `go-mknoon/node/group_inbox_test.go` proves recipientPeerIds are marshaled, normalized, and opaque replay envelopes do not leak plaintext at relay-visible request shape.

## regression/tests to add first

Add a focused test in `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`:

`GK-022 removed member with old key cannot decrypt post-removal inbox replay`

The test should:

1. keep the local stale group for C and save only E1 in `groupRepo`
2. build a signed replay envelope for an E2 post-removal message using a `GroupKeyInfo` passed directly to the envelope builder, without saving E2 locally
3. return that envelope from `_CursorInboxBridge` as if the relay leaked or replayed it to C
4. run `drainGroupOfflineInbox`
5. assert `payload.verify` may run but `group.decrypt` does not run
6. assert the E2 plaintext text is not persisted or rendered
7. assert the saved row, if any, is the generic `groupUndecryptablePlaceholderText`, has `status == 'undecryptable'`, `keyGeneration == 2`, and no media/download/decrypt side effects

## step-by-step implementation plan

1. Add the GK-022 test near the existing future-epoch and MD-011 replay tests in `drain_group_offline_inbox_use_case_test.dart`.
2. Reuse existing helpers (`signedReplayEnvelope`, `_CursorInboxBridge`, flow-event capture) rather than adding new harness layers.
3. Run the focused GK-022 test.
4. If the focused test fails because the app decrypts or persists plaintext, inspect `decryptGroupOfflineReplayEnvelope`, `_persistUndecryptablePlaceholderFromEnvelope`, and `handleDecodeError`; patch the smallest behavior so missing E2 remains non-decryptable and non-rendering.
5. If the failure shows store-side recipient leakage rather than decrypt/render leakage, inspect `send_group_message_use_case.dart` and group inbox retry payload shaping, then patch only the removed-recipient exclusion needed by this row.
6. Run adjacent replay tests and the broader group gate.
7. Update the source matrix and all GK-022 breakdown/plan closure rows only after test evidence is concrete.

## risks and edge cases

- A test that simply omits the E2 key without verifying no decrypt command ran would be too weak.
- A test that uses media only would duplicate MD-011 and not close GK-022's generic message contract.
- A test that deletes the local group before drain would prove no retrieval, not "retrieves relay messages and cannot decrypt."
- Do not convert missing-key privacy behavior into visible plaintext-like placeholder content.
- Do not add repair behavior that later gives the removed member the E2 key.

## exact tests and gates to run

Focused:

```bash
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GK-022 removed member with old key cannot decrypt post-removal inbox replay'
```

Adjacent:

```bash
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name 'GK-022 removed member with old key cannot decrypt post-removal inbox replay|future epoch encrypted replay creates one undecryptable placeholder without decrypting|MD-011 removed member cannot decode future media replay with only the old epoch'
```

Replay signature/decrypt support:

```bash
flutter test --no-pub test/features/groups/application/group_offline_replay_envelope_test.dart
```

Go inbox request support:

```bash
(cd go-mknoon && go test ./node -run 'TestBuildGroupInboxStoreRequest|TestGM028BuildGroupInboxStoreRequestDropsBlankRecipientPeerIds' -count=1)
```

Broader group gate and hygiene:

```bash
./scripts/run_test_gates.sh groups
git diff --check
```

## known-failure interpretation

Focused GK-022 failure is current-row blocking if C gets post-removal plaintext, `group.decrypt` runs with stale/missing E2 state, an undecryptable placeholder is not created where expected, or the placeholder contains the protected text. Adjacent failures are GK-022 blockers only if they touch offline replay signature verification, missing-key decode handling, inbox placeholder behavior, recipient filtering, or group message persistence. Unrelated dirty-worktree failures must be recorded without reverting unrelated work.

## done criteria

- A GK-022 row-named regression is in the working tree.
- Focused, adjacent, replay-signature, Go inbox request support, group gate, and `git diff --check` pass or any non-run gate has a precise blocker recorded.
- Source matrix GK-022 row is `Covered` with exact file/test/gate evidence.
- Breakdown Gap-Closure Reconciliation, Closure Progress, Session Closure Ledger, Matrix Row Inventory, Row Disposition Map, Session Ledger row 73, and Ordered Session Breakdown row 73 are updated.
- This plan is marked `accepted/closed` by closure.
- No final program verdict is written while GK-023 and later rows remain unresolved.

## scope guard

Do not implement GK-023 removed-window backlog after re-add, GK-024 late-join entitlement, a new multi-key history model, new relay ACL protocol, device/simulator harness expansion, or broad group-message UI changes. Do not change group encryption/signature formats unless focused GK-022 evidence proves a current-row privacy gap that cannot be fixed in replay drain or recipient filtering.

## accepted differences / intentionally out of scope

Direct host replay/decrypt proof is acceptable for GK-022 because the row is about local decrypt/render behavior after retrieval. Real relay/device proof and relay-side ACL enforcement are supplemental unless implementation touches bridge transport or relay code. GK-023 owns the re-added-member removed-window backlog case, and GK-024 owns late-join pre-history.

## dependency impact

GK-023 depends on GK-022 preserving the rule that missing post-removal epoch material does not decrypt or render stale content. If GK-022 requires a production replay-drain fix, GK-023 and GK-024 should use the same privacy boundary rather than reopen it. If GK-022 lands tests-only, later rows should treat it as proof for stale removed-member missing-key decrypt denial only, not as backlog entitlement proof after re-add.

## Execution Progress

- 2026-05-12 17:17 CEST - Phase: broader gate completed - Files inspected or touched: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, this plan. Command finished: `./scripts/run_test_gates.sh groups` -> `00:17 +136: All tests passed!`. Decision/blocker: broader group gate is green. Next action: write final execution verdict.
- 2026-05-12 17:16 CEST - Phase: support gates completed - Files inspected or touched: `test/features/groups/application/group_offline_replay_envelope_test.dart`, `go-mknoon/node/group_inbox_test.go`, this plan. Commands finished: `flutter test --no-pub test/features/groups/application/group_offline_replay_envelope_test.dart` -> `00:00 +2: All tests passed!`; `(cd go-mknoon && go test ./node -run 'TestBuildGroupInboxStoreRequest|TestGM028BuildGroupInboxStoreRequestDropsBlankRecipientPeerIds' -count=1)` -> `ok github.com/mknoon/go-mknoon/node 0.518s`; `git diff --check` passed with no output. Decision/blocker: replay signature/decrypt and Go inbox request support are green. Next action: run broader group gate.
- 2026-05-12 17:15 CEST - Phase: adjacent replay gates completed - Files inspected or touched: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, this plan. Commands finished: `dart format --set-exit-if-changed test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` -> `Formatted 1 file (0 changed)`; adjacent replay selector -> `00:00 +3: All tests passed!`. Decision/blocker: GK-022, generic future-epoch replay, and MD-011 removed-member media replay proofs are green together. Next action: run replay signature and Go inbox support.
- 2026-05-12 17:15 CEST - Phase: focused proof completed - Files inspected or touched: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, this plan. Command finished: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GK-022 removed member with old key cannot decrypt post-removal inbox replay'` -> `00:00 +1: All tests passed!`. Decision/blocker: GK-022 focused proof is green tests-only; no production code change is justified. Next action: run adjacent replay/decrypt selectors.

## Final Execution Verdict

Verdict: `accepted`.

Files changed:

- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-022-plan.md`

What landed:

- `GK-022 removed member with old key cannot decrypt post-removal inbox replay` proves a stale removed client with only E1 stored locally can retrieve an E2 post-removal signed replay envelope without decrypting or rendering its plaintext.
- The test asserts E1 remains present, E2 remains absent, `payload.verify` runs, `group.decrypt` does not run, the protected post-removal plaintext is not persisted in visible messages, and the only persisted row is an `undecryptable` placeholder at `keyGeneration == 2` with `groupUndecryptablePlaceholderText`.

Tests and gates:

- Focused GK-022 selector: `00:00 +1: All tests passed!`.
- Adjacent replay selector: `00:00 +3: All tests passed!`.
- Replay signature support: `00:00 +2: All tests passed!`.
- Go inbox request support: `ok github.com/mknoon/go-mknoon/node 0.518s`.
- Groups gate: `00:17 +136: All tests passed!`.
- `dart format --set-exit-if-changed test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` passed with `0 changed`.
- `git diff --check` passed with no output.

Production code changed: none.

Blockers: none for GK-022 execution.

## Closure Note

Verdict: `accepted/closed`.

Source matrix row GK-022 is now `Covered`, and breakdown row 73 plus the Gap-Closure Reconciliation, Closure Progress, Session Closure Ledger, Matrix Row Inventory, Row Disposition Map, and Session Ledger all record `covered/accepted` evidence. No production, relay, transport, or device harness code changed.

Closure evidence:

- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart::GK-022 removed member with old key cannot decrypt post-removal inbox replay`
- Focused GK-022 selector: `00:00 +1: All tests passed!`
- Adjacent GK-022/future-epoch/MD-011 replay selector: `00:00 +3: All tests passed!`
- Replay signature support: `00:00 +2: All tests passed!`
- Go inbox request support: `ok github.com/mknoon/go-mknoon/node 0.518s`
- Groups gate: `00:17 +136: All tests passed!`
- `dart format --set-exit-if-changed test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` passed with `0 changed`
- `git diff --check` passed with no output

Accepted differences: direct host replay/decrypt proof is sufficient for this local decrypt/render row. Real relay/device and relay ACL proof are supplemental because GK-022 landed tests-only without relay, transport, or device-harness changes. Residual-only: none for GK-022. GK-023 remains the next unresolved P0 row. No final program verdict was written.
