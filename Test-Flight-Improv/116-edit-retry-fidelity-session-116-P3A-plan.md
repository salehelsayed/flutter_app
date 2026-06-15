Status: execution-ready

# 116-P3A - Tombstone Retry Liveness Plan

## Planning Progress

- 2026-06-13 12:20:21 CEST - Planner started. Files inspected since last update: same evidence set. Decision/blocker: plan only sender-side tombstone retry liveness and builder extraction; keep P3B and 116-CLOSURE out of scope. Next action: write mandatory plan sections with exact tests, known-failure handling, scope guard, and dependency impact.
- 2026-06-13 12:20:21 CEST - Planner completed. Files inspected since last update: same evidence set plus direct suite output. Decision/blocker: the draft includes the 115 `inboxed` tombstone custody adjustment, P3A red tests, host-only closure, and 116-CLOSURE device deferral. Next action: reviewer sufficiency pass.
- 2026-06-13 12:20:21 CEST - Reviewer started. Files inspected since last update: drafted plan sections. Decision/blocker: check for missing closure bars, scope drift into P3B/closure, stale status assumptions, and insufficient test mapping. Next action: classify findings and patch if structural blockers exist.
- 2026-06-13 12:23:06 CEST - Reviewer completed / Arbiter started. Files inspected since last update: full drafted plan. Decision/blocker: no structural reviewer blocker remains; stale 115 status and device proof were handled in-plan. Next action: arbiter stop-rule classification.
- 2026-06-13 12:23:06 CEST - Arbiter completed. Files inspected since last update: reviewer findings and final mandatory sections. Decision/blocker: no structural blockers; incremental details are documented as implementation-level decisions. Next action: hand the execution-ready plan to the pipeline.

## Final Verdict

`implementation-ready` for 116-P3A only.

Host-side implementation closure is sufficient for this session because P3A is a sender-side Dart retry/use-case seam using `P2PService`, `Bridge`, repository fakes, and existing named host gates. Real device delete-for-everyone retry proof from doc 116 section 8 remains deferred to `116-CLOSURE`.

## Real Scope

Implement sender-side delete tombstone retry liveness for failed outgoing tombstones:

- Safe stored v2 `message_deletion` envelopes must not fall through to `sendChatMessage` when relay inbox storage fails. They get a direct deletion-envelope replay route.
- Legacy v1 delete tombstones must be rebuilt as encrypted v2 `message_deletion` envelopes when the recipient ML-KEM key exists.
- Legacy tombstones without a recipient ML-KEM key must stay failed, emit explicit telemetry, and never leak v1 bytes.
- `delete_message_use_case.dart` must expose a top-level delete-envelope builder used by both the original delete path and retry rebuild path.
- Current 115 status decision applies: relay inbox custody for deletion envelopes is `status: 'inboxed'`, `transport: 'inbox'`, `wireEnvelope` retained, and tombstone visible. Only acknowledged direct delivery is `status: 'delivered'`, `wireEnvelope: null`, and hidden via `normalizeOutgoingDeleteTombstoneVisibility`.

This session may update `Test-Flight-Improv/116-edit-retry-fidelity.md` only for the P3A tombstone matrix/phase note after implementation. It must not update docs 114 or 115, and it must not do final gate-array capture.

## Closure Bar

P3A is closed when every tombstone route row owned by the breakdown is independently proven:

- v2 tombstone with safe stored envelope and failed relay inbox store retries over the direct deletion-envelope route, never through `sendChatMessage`.
- v2 tombstone with successful relay inbox store adopts the landed 115 custody terminal: `inboxed`, visible, retained `wireEnvelope`.
- legacy v1 tombstone with recipient key rebuilds to encrypted v2 before any transport, stores/replays only v2 bytes, and never leaks the v1 payload.
- legacy v1 tombstone without recipient key remains failed with `RETRY_FAILED_DELETE_REBUILD_UNAVAILABLE {reason: 'missing_recipient_key'}` and no transport calls.
- `deleteMessageForEveryone` still emits the same v2 deletion envelope shape through the extracted builder.
- Direct suites and named host gates listed below pass without removing coverage from gate definitions.

## Source Of Truth

- Active session contract: `Test-Flight-Improv/116-edit-retry-fidelity-session-breakdown.md`, session `116-P3A`.
- Source behavior doc: `Test-Flight-Improv/116-edit-retry-fidelity.md`, Phase 3 and section 6 tombstone rows.
- Current code/tests beat stale prose. The source doc phrase that allows "delivered/inbox" for legacy rebuild is superseded by current 115 evidence in `delete_message_use_case.dart` and `delete_message_use_case_test.dart`: inbox custody is `inboxed`, visible, envelope retained.
- Gate source of truth: `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`.
- Direct production files: `lib/features/conversation/application/retry_failed_messages_use_case.dart`, `lib/features/conversation/application/delete_message_use_case.dart`, `lib/features/conversation/application/delete_message_tombstone_visibility.dart`, `lib/features/conversation/application/outbound_envelope_policy.dart`, and `lib/features/conversation/domain/models/message_deletion_payload.dart`.
- Direct tests: `test/features/conversation/application/retry_failed_messages_use_case_test.dart` and `test/features/conversation/application/delete_message_use_case_test.dart`.

## Session Classification

`implementation-ready`.

Evidence refreshed on 2026-06-13:

- `flutter test test/features/conversation/application/retry_failed_messages_use_case_test.dart test/features/conversation/application/delete_message_use_case_test.dart` passed, 38 tests.
- Current retry code still stores safe v2 envelopes through the generic `wireEnvelope` inbox path and then falls through to `sendChatMessage` on store failure.
- Current legacy v1 deletion test expects no retry and no save, so P3A is not covered.
- `buildDeletionWireEnvelope`, `RETRY_FAILED_DELETE_REBUILD_UNAVAILABLE`, and `RETRY_FAILED_DELETE_TOMBSTONE_SUCCESS` are absent.

## Exact Problem Statement

A failed delete-for-everyone tombstone is represented as an outgoing failed row with `text: ''`, `deletedAt` set, and a `message_deletion` wire envelope. Current retry behavior is live only when the generic inbox re-store succeeds. If inbox re-store fails, the row falls through to `sendChatMessage`, where empty text is invalid, so the tombstone remains failed and the receiver can keep displaying a message the sender meant to delete. Legacy v1 deletion envelopes are skipped as unsafe and also fall through to the empty-text chat path, so they starve silently.

The fix must give tombstones a deletion-envelope retry route while preserving all existing no-downgrade guarantees: no plain `chat_message` payload under a deleted id, no v1 wire leak, no receiver-side changes, and no false `delivered` status for relay custody.

## Files And Repos To Inspect Next

Production:

- `lib/features/conversation/application/retry_failed_messages_use_case.dart`
- `lib/features/conversation/application/delete_message_use_case.dart`
- `lib/features/conversation/application/delete_message_tombstone_visibility.dart`
- `lib/features/conversation/application/outbound_envelope_policy.dart`
- `lib/features/conversation/domain/models/message_deletion_payload.dart`
- `lib/features/p2p/domain/models/send_message_result.dart`

Tests/fakes:

- `test/features/conversation/application/retry_failed_messages_use_case_test.dart`
- `test/features/conversation/application/delete_message_use_case_test.dart`
- `test/core/services/fake_p2p_service.dart`
- `test/core/bridge/fake_bridge.dart`
- `test/features/contacts/domain/repositories/fake_contact_repository.dart`
- `test/features/conversation/domain/repositories/fake_message_repository.dart`

Docs:

- `Test-Flight-Improv/116-edit-retry-fidelity.md`
- `Test-Flight-Improv/116-edit-retry-fidelity-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`

## Existing Tests Covering This Area

Already green and useful:

- `deleteMessageForEveryone keeps a sender-visible failed tombstone on send failure` proves v2 delete envelopes are persisted on initial delete failure.
- `deleteMessageForEveryone sends encrypted v2 deletion when key is present` proves current envelope shape.
- 115 tombstone tests prove `inboxed` custody keeps the tombstone visible and retains `wireEnvelope`.
- `does not replay persisted v1 deletion wireEnvelope to inbox after restart` proves the current v1 leak guard but currently expects starvation, so it must be replaced or reframed for P3A.
- `hides delivered outgoing delete tombstones after failed retry stores in inbox` proves current generic behavior but is stale against the landed 115 custody model for deletion envelopes and must be reframed.

Missing before P3A:

- No test proves direct v2 deletion-envelope replay after inbox store failure.
- No test proves legacy v1 delete rebuild to encrypted v2 with key present.
- No test proves missing-key telemetry for legacy tombstones.
- No test pins the extracted delete-envelope builder as the shared construction seam.

## Regression Contract

Add permanent regressions before implementation. Each source row gets an independent proof, and no combined assertion may stand in for the tombstone matrix:

- v2 tombstone direct replay after inbox failure: proves liveness and no chat fallback.
- v2 tombstone inbox custody success: proves current 115 status semantics during retry.
- legacy v1 tombstone with key present: proves rebuild to encrypted v2 and v1 leak prevention.
- legacy v1 tombstone without key: proves fail-closed telemetry and no transport.
- delete builder extraction pin: proves `deleteMessageForEveryone` and retry rebuild share the same v2 envelope builder behavior.

These tests must fail for the documented reasons before implementation or be explicitly marked green-on-arrival with evidence. If any test unexpectedly passes before implementation, stop and inspect whether prior-agent work already landed P3A.

## Regression/Tests To Add First

In `retry_failed_messages_use_case_test.dart`:

- Add `failed delete tombstone retries over direct deletion route when inbox store fails`.
  Seed `makeFailedDeletedMessage()`, `storeInInboxResult: false`, `sendMessageWithReplyResult: SendMessageResult(sent: true, reply: 'ack')`, and a started node. Assert count 1, one `storeInInbox`, one `sendMessageWithReply`, no `CHAT_MSG_SEND_START`, direct content is type `message_deletion` version `2`, saved status `delivered`, `wireEnvelope` null, and hidden.
- Reframe the existing safe v2 inbox test so a successful retry inbox store saves `status: 'inboxed'`, `transport: 'inbox'`, retained `wireEnvelope`, and visible tombstone.
- Replace the current v1 deletion starvation expectation with `legacy v1 delete tombstone is rebuilt as encrypted v2 when key exists`.
  Seed `makeFailedLegacyDeletedMessage()` and a contact with `mlKemPublicKey`. Assert transported envelope is `message_deletion` version `2` with `encrypted`, no `payload`, no v1 bytes, and saved terminal follows the actual route (`inboxed` for store success).
- Add `legacy tombstone without recipient key stays failed with explicit telemetry`.
  Seed a null-key contact. Capture flow events. Assert count 0, no `storeInInbox`, no `sendMessageWithReply`, saved row remains failed or untouched, and event `RETRY_FAILED_DELETE_REBUILD_UNAVAILABLE` has reason `missing_recipient_key`.

In `delete_message_use_case_test.dart`:

- Add a focused builder extraction test for `buildDeletionWireEnvelope` using `PassthroughCryptoBridge`, a tombstone with `deletedAt`, and a recipient key. Assert envelope type `message_deletion`, version `2`, encrypted block exists, and no v1 `payload` exists.
- Keep existing `deleteMessageForEveryone` envelope-shape tests green after delegation to the new builder.

## Step-By-Step Implementation Plan

1. Add the P3A red tests above, including flow-event capture assertions where needed.
2. Extract a top-level `buildDeletionWireEnvelope` in `delete_message_use_case.dart`.
   Use `MessageDeletionPayload`, `callEncryptMessage`, and `MessageDeletionPayload.buildEncryptedEnvelope`. Preserve current error handling and do not add repository or service interfaces.
3. Refactor `deleteMessageForEveryone` to call the builder without changing its user-visible behavior, emitted events, tombstone cleanup, or 115 `inboxed` custody semantics.
4. In `retry_failed_messages_use_case.dart`, route `msg.isDeleted` before attachment resolution and before `sendChatMessage`.
5. For safe stored v2 deletion envelopes:
   - keep the inbox-first attempt;
   - on inbox success, save `inboxed` + retained `wireEnvelope` + visible tombstone;
   - on inbox failure/error, replay the same v2 envelope via `sendMessageWithReply`;
   - on acknowledged direct success, save `delivered` + direct transport + null `wireEnvelope` + hidden tombstone and emit `RETRY_FAILED_DELETE_TOMBSTONE_SUCCESS`.
6. For legacy v1 or missing deletion envelopes:
   - fetch contact and trimmed `mlKemPublicKey`;
   - if missing, emit `RETRY_FAILED_DELETE_REBUILD_UNAVAILABLE` with `reason: 'missing_recipient_key'` and return false;
   - if present, rebuild v2 with `buildDeletionWireEnvelope`;
   - store rebuilt v2 to inbox first, then try direct replay if inbox storage fails;
   - persist only v2 envelopes for non-delivered retryable states so future retries never see v1 bytes.
7. Use `normalizeOutgoingDeleteTombstoneVisibility` on every tombstone save.
8. Keep `sendChatMessage` untouched except as protected by existing tests. P3A must not make any deleted row reach `CHAT_MSG_SEND_START`.
9. Update only the P3A tombstone rows/phase note in `Test-Flight-Improv/116-edit-retry-fidelity.md` after tests pass. Defer final gate-array capture to `116-CLOSURE`.
10. Run the direct tests and named gates below.

Stop early if the red tests reveal that prior-agent work already implemented the P3A route; in that case, convert the session to evidence/closure of P3A behavior rather than re-implementing.

## Risks And Edge Cases

- Stale status prose: current 115 custody semantics win over older P3 wording. Inbox custody is not delivered.
- Empty-text guard: `sendChatMessage` must continue rejecting empty text; P3A bypasses it with a deletion-envelope route, not by weakening the guard.
- Legacy leak: v1 `payload` bytes must never be sent to inbox or direct transports.
- Missing key: rebuilding encrypted v2 must fail closed and telemetry-visible.
- Direct sent without ack: preserve a visible non-delivered state with the v2 envelope retained, mirroring current delete-use-case semantics, rather than hiding the tombstone.
- Dirty worktree: many unrelated files are modified. Do not revert or normalize unrelated changes.
- Interface churn: adding methods to `P2PService`, `MessageRepository`, `ContactRepository`, or `Bridge` would create fake breakage and is out of scope.

## Device/Relay Proof Profile

P3A mentions relay inbox and direct send paths, but the implementation seam is sender-side Dart orchestration over faked `P2PService` and `Bridge`. Host-only closure is sufficient for this session if the direct regressions and named host gates pass.

No device, real relay, `integration_test`, gomobile rebuild, Go relay deploy, or hardware proof is required to close 116-P3A implementation. The real device delete-for-everyone retry proof in doc 116 section 8 item 5 is deferred to `116-CLOSURE`, where P3A and P3B are validated together.

## Exact Tests And Gates To Run

Direct first:

```bash
flutter test test/features/conversation/application/retry_failed_messages_use_case_test.dart test/features/conversation/application/delete_message_use_case_test.dart
```

Named gates for closure:

```bash
./scripts/run_test_gates.sh 1to1
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline
./scripts/run_test_gates.sh completeness-check
```

Scope-leak detectors:

- Go and relay tests are not required for P3A host closure when no Go/relay files are touched.
- If implementation touches `go-mknoon`, `go-relay-server`, gomobile, DB migrations, or platform relay wiring, treat that as scope drift first; only then run the relevant Go gate to prove no regression.

## Known-Failure Interpretation

- The two direct suites passed at planning intake. A new failure in those suites after P3A edits is a regression unless it is one of the intentionally added red tests before implementation.
- The intentionally added P3A tests should fail before implementation because `buildDeletionWireEnvelope` and tombstone retry helpers/events do not exist and legacy deletion retry currently starves.
- Flutter dependency "newer versions available" output is informational and not a failure.
- If `1to1`, macOS baseline, or completeness-check fails outside touched retry/delete tests, capture the exact existing failing test/gate and classify it as pre-existing only with evidence. Do not remove tests from gates or weaken assertions to make closure green.

## Done Criteria

- P3A red tests fail before implementation for the documented reasons or are proven already covered.
- P3A production implementation lands with no abstract interface changes.
- Direct retry/delete suite passes.
- `1to1`, macOS baseline, and completeness-check pass or have explicit pre-existing failure evidence outside P3A.
- No deleted failed row can reach `sendChatMessage` or emit `CHAT_MSG_SEND_START`.
- All transported tombstone retry envelopes are v2 `message_deletion` envelopes.
- Missing-key legacy tombstone retry emits `RETRY_FAILED_DELETE_REBUILD_UNAVAILABLE` and leaves the row retryable/failed.
- Doc 116 P3A tombstone rows are updated; docs 114/115 and final gate arrays are untouched.

## Scope Guard

Do not implement or edit:

- receiver duplicate-content mismatch telemetry;
- `HandleChatMessageResult.ignoredEdit` listener ack behavior;
- `recovered_inbox_chat_disposition.dart`;
- final 116 gate capture or gate-array script/doc edits;
- docs 114 or 115, except read-only evidence already allowed by doc 116;
- database migrations, status-string redesigns, UI affordances, Go relay/node code, gomobile bridge code, notification code, or device harnesses;
- any repository/service interface method.

Overengineering for this session includes adding retry schedulers, cross-isolate locks, new protocol types, receiver repair flows, or migrations for already-poisoned rows.

## Accepted Differences / Intentionally Out Of Scope

- P3B receiver truthfulness remains separate.
- `116-CLOSURE` owns real device delete retry proof, field telemetry watch, and final gate/docs closure.
- Already-poisoned field rows are not repaired; doc 116 accepts that lost edit metadata is unrecoverable.
- No receiver-initiated content reconciliation is introduced.
- No Go parity change is needed; P3A uses existing app-side P2P send/store APIs.

## Dependency Impact

- `116-CLOSURE` depends on this plan to provide host evidence for the delete-for-everyone retry device scenario.
- `116-P3B` is independent and may run before or after P3A if refreshed against landed code.
- 115 Phase 1 status foundation is already reflected in current code; P3A must preserve its `inboxed` deletion custody model.
- If a later 115 status decision changes deletion receipts or custody semantics, only the terminal-status assertions and doc 116 closure notes should be revisited, not the tombstone retry route itself.

## Reviewer Pass

Reviewer verdict: sufficient with adjustments applied.

Findings checked:

- Missing closure bar: covered by the independent tombstone route rows.
- Stale status assumption: resolved by making current 115 `inboxed` custody authoritative.
- Missing device gate: resolved by classifying P3A as host-sufficient and deferring real device proof to `116-CLOSURE`.
- Scope drift into P3B or gate closure: blocked by explicit scope guard.
- Weak tests: addressed with four retry-side tests plus one builder extraction pin.

## Execution Progress

- 2026-06-13 12:40:45 CEST - Phase: P3A verification complete / closure ready. Files inspected/touched: scoped P3A production/tests, this plan, source doc, and breakdown. Commands finished: direct retry/delete suite passed 41 tests; initial `./scripts/run_test_gates.sh 1to1` exited 1 with one out-of-scope `test/core/bridge/p2p_bridge_client_test.dart` timeout row; exact failing bridge test passed in isolation; `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passed; `./scripts/run_test_gates.sh completeness-check` passed 841/841; `git diff --check` passed; `./graphify-arch/refresh_arch_graph.sh` passed from repo root. A later final aggregate `1to1` pass closed the bridge timeout row.
- 2026-06-13 15:07:40 CEST - Final batch re-audit: `./scripts/run_test_gates.sh 1to1` passed with `+793`; P3A remains accepted and no aggregate-gate blocker remains.
- 2026-06-13 12:36:04 CEST - Phase: direct test green. Files inspected/touched: `lib/features/conversation/application/retry_failed_messages_use_case.dart`, `lib/features/conversation/application/delete_message_use_case.dart`, retry/delete tests, this plan. Command finished: `flutter test test/features/conversation/application/retry_failed_messages_use_case_test.dart test/features/conversation/application/delete_message_use_case_test.dart` passed 41 tests. Decision/blocker: P3A direct behavior is green after narrowing the fake-passthrough assertion. Next action: run named host gates.
- 2026-06-13 12:35:10 CEST - Phase: direct test rerun failed / focused triage. Files inspected/touched: this plan and retry direct test output. Command finished: `flutter test test/features/conversation/application/retry_failed_messages_use_case_test.dart test/features/conversation/application/delete_message_use_case_test.dart` exited 1. Decision/blocker: one scoped P3A assertion failed in `legacy v1 delete tombstone is rebuilt as encrypted v2 when key exists`; route produced v2 `message_deletion`, no top-level payload, and saved `inboxed`, but the test asserted the whole serialized fake-passthrough envelope did not contain `messageId`, which is incompatible with the fake bridge exposing inner plaintext in `encrypted.ciphertext`. Next action: narrow the assertion to top-level envelope shape/no v1 payload, rerun direct suite.
- 2026-06-13 12:34:07 CEST - Phase: parent progress request heartbeat. Files inspected/touched: this plan. Command running: none; parent reported no active `flutter test`/gate process, consistent with the last direct run having exited. Decision/blocker: last direct command `flutter test test/features/conversation/application/retry_failed_messages_use_case_test.dart test/features/conversation/application/delete_message_use_case_test.dart` exited 1 at compile load because `_messageIdPreview` was missing in `retry_failed_messages_use_case.dart`; scoped helper fix is applied but not yet rerun. Next action: format the retry file, rerun the exact direct suite, then record pass/fail evidence here.
- 2026-06-13 12:33:45 CEST - Phase: direct test triage / fix applied. Files inspected/touched: `lib/features/conversation/application/retry_failed_messages_use_case.dart`, this plan. Command finished: direct retry/delete suite exited 1 at compile load. Decision/blocker: scoped seam mismatch only; retry file called a private helper from another library. Added a local `_messageIdPreview` helper. Next action: rerun the same direct suite.
- 2026-06-13 12:33:16 CEST - Phase: implementation patched / direct test starting. Files inspected/touched: `lib/features/conversation/application/retry_failed_messages_use_case.dart`, retry/delete direct tests, this plan. Command running: `flutter test test/features/conversation/application/retry_failed_messages_use_case_test.dart test/features/conversation/application/delete_message_use_case_test.dart`. Decision/blocker: added deleted-row retry branch, v2 replay, legacy rebuild, missing-key telemetry, and direct replay persistence without changing generic chat retry. Next action: capture direct test result and triage any scoped failures.
- 2026-06-13 12:32:06 CEST - Phase: Executor no-progress / local sequential fallback started. Files inspected/touched: P3A plan, `lib/features/conversation/application/retry_failed_messages_use_case.dart`, `lib/features/conversation/application/delete_message_use_case.dart`, `test/features/conversation/application/retry_failed_messages_use_case_test.dart`, `test/features/conversation/application/delete_message_use_case_test.dart`. Command running: none. Decision/blocker: spawned execution process was terminated after no trustworthy final execution result; current artifacts show P3A tests and the delete-envelope builder are now present, but production retry tombstone routing is still missing. Standard-mode local execution fallback is active for P3A only. Next action: patch the deleted-row retry route, run direct tests, then run named gates.
- 2026-06-13 12:28:12 CEST - Phase: RED direct test finished / implementation starting. Files inspected/touched: retry/delete direct tests, this plan. Command finished: `flutter test test/features/conversation/application/retry_failed_messages_use_case_test.dart test/features/conversation/application/delete_message_use_case_test.dart` exited 1. Decision/blocker: expected RED evidence captured: missing `buildDeletionWireEnvelope`, v2 tombstone retry stores as `delivered`, direct tombstone fallback returns 0, legacy v1 delete rebuild and missing-key telemetry absent. Next action: implement builder extraction and tombstone retry route in scoped production files.
- 2026-06-13 12:27:52 CEST - Phase: regression additions completed / RED run starting. Files inspected/touched: `test/features/conversation/application/retry_failed_messages_use_case_test.dart`, `test/features/conversation/application/delete_message_use_case_test.dart`, this plan. Command running: `flutter test test/features/conversation/application/retry_failed_messages_use_case_test.dart test/features/conversation/application/delete_message_use_case_test.dart`. Decision/blocker: required P3A regressions added before production edits; expected RED because builder and tombstone retry route are absent. Next action: capture RED evidence, then implement smallest P3A change.
- 2026-06-13 12:26:35 CEST - Phase: owner files inspected. Files inspected/touched: `lib/features/conversation/application/delete_message_use_case.dart`, `lib/features/conversation/application/retry_failed_messages_use_case.dart`, `test/features/conversation/application/delete_message_use_case_test.dart`, `test/features/conversation/application/retry_failed_messages_use_case_test.dart`, scoped fakes read-only. Command running: none. Decision/blocker: P3A behavior is not landed; no `buildDeletionWireEnvelope`, retry tombstones still use generic `wireEnvelope` inbox/fallback, and existing tests contain stale deletion custody/legacy starvation expectations. Next action: add required regression coverage before production edits.
- 2026-06-13 12:26:07 CEST - Phase: Executor local pass started. Files inspected/touched: this plan, `Test-Flight-Improv/116-edit-retry-fidelity-session-breakdown.md`, scoped worktree status. Command running: none. Decision/blocker: user explicitly assigned this turn as the 116-P3A Executor and forbade spawning; proceed locally within the Executor write scope only. Next action: inspect owner production/test files before adding required regressions.
- 2026-06-13 12:24:52 CEST - Phase: contract extraction started. Files inspected/touched: this plan, `Test-Flight-Improv/116-edit-retry-fidelity-session-breakdown.md`, worktree status. Command running: none. Decision/blocker: nested spawned agents are available; controller will use fresh Executor and QA agents with `gpt-5.5`/`xhigh`. Next action: extract exact P3A scope, tests, gates, non-goals, and spawn Executor.
- 2026-06-13 12:24:52 CEST - Phase: contract extracted. Files inspected/touched: this plan only. Command running: none. Decision/blocker: execute 116-P3A only; add retry/delete regressions before implementation, keep edits scoped to the two use cases, two direct test files, doc 116 P3A notes/rows, and this progress section; required direct test is `flutter test test/features/conversation/application/retry_failed_messages_use_case_test.dart test/features/conversation/application/delete_message_use_case_test.dart`; required named gates are `./scripts/run_test_gates.sh 1to1`, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`, and `./scripts/run_test_gates.sh completeness-check` if feasible. Next action: spawn Executor pass.
- 2026-06-13 12:25:08 CEST - Phase: Executor spawning. Files inspected/touched: this plan. Command running: nested Executor agent launch. Decision/blocker: no blocker; child will add required RED regressions first, then implement P3A and run the required direct test before handoff. Next action: wait for Executor completion evidence.

No structural blocker remains for arbiter review.

## Execution Verdict

Verdict: `accepted`.

P3A host implementation is complete. Failed delete tombstones now route through
a deletion-envelope retry path before any chat fallback: safe v2 envelopes
retry to inbox or direct as `message_deletion`, successful inbox custody stays
`inboxed` with the envelope retained and the tombstone visible, direct ack hides
only after `delivered`, legacy v1 tombstones rebuild to encrypted v2 when a
recipient key exists, and missing-key legacy tombstones remain failed with
`RETRY_FAILED_DELETE_REBUILD_UNAVAILABLE`.

The earlier broad `./scripts/run_test_gates.sh 1to1` aggregate timeout is
closed by the final `+793` pass. Direct P3A tests, macOS baseline,
completeness, diff check, and arch graph refresh passed.

## Arbiter Pass

Structural blockers remaining: none.

Incremental details intentionally deferred:

- A separate direct-sent-without-ack regression is not required for P3A closure if the implementation reuses current delete-use-case terminal semantics and the planned direct-ack and inbox-custody tests pass.
- Go sanity gates remain scope-leak detectors, not required P3A closure gates, unless implementation touches Go or relay files.

Accepted differences intentionally left unchanged:

- Device/real relay proof is deferred to `116-CLOSURE`.
- P3B receiver truthfulness and ignored-edit idempotency remain separate.
- Final 116 gate-array capture remains separate.

Exact docs/files used as evidence:

- `Test-Flight-Improv/116-edit-retry-fidelity.md`
- `Test-Flight-Improv/116-edit-retry-fidelity-session-breakdown.md`
- `lib/features/conversation/application/retry_failed_messages_use_case.dart`
- `lib/features/conversation/application/delete_message_use_case.dart`
- `lib/features/conversation/application/delete_message_tombstone_visibility.dart`
- `lib/features/conversation/application/outbound_envelope_policy.dart`
- `lib/features/conversation/domain/models/message_deletion_payload.dart`
- `lib/features/p2p/domain/models/send_message_result.dart`
- `test/features/conversation/application/retry_failed_messages_use_case_test.dart`
- `test/features/conversation/application/delete_message_use_case_test.dart`
- `test/core/services/fake_p2p_service.dart`
- graphify-arch exact-symbol query: `retryFailedMessages _retryFailedMessageCandidate message_deletion tombstone`

Why the plan is safe to implement now:

- It is bounded to one sender-side retry route and one builder extraction.
- It preserves the landed 115 tombstone status model.
- It requires red tests before production edits and named host gates before closure.
- It forbids receiver, relay, DB, platform, and final gate-capture scope.
