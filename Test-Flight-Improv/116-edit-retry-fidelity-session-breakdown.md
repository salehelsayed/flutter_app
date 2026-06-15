# 116 Edit Retry Fidelity Session Breakdown

Status: reusable-breakdown

Source doc: `Test-Flight-Improv/116-edit-retry-fidelity.md`
Intended breakdown artifact: `Test-Flight-Improv/116-edit-retry-fidelity-session-breakdown.md`

## Recommended plan count

3 actionable future session plans.

The ledger also records 2 stale/already-covered historical sessions so the later
pipeline does not re-plan Phases 1-2 unless a regression reopens them.

## Decomposition artifact

- Artifact path: `Test-Flight-Improv/116-edit-retry-fidelity-session-breakdown.md`
- Proposal/source doc path: `Test-Flight-Improv/116-edit-retry-fidelity.md`
- Downstream workflow rule: detailed planning happens one session at a time;
  later sessions must be refreshed against landed code before execution.
- Plan path rule: every intended plan path is doc-scoped under
  `Test-Flight-Improv/116-edit-retry-fidelity-session-<session-id>-plan.md`.

## Run mode snapshot

- Active mode: `standard`.
- Degraded local continuation: not explicitly allowed for this run.
- Source proposal/matrix/closure doc: `Test-Flight-Improv/116-edit-retry-fidelity.md`
  section 6 matrix plus the same doc's closure/amendment logs.
- Source row/status vocabulary: section 6 is a coverage matrix without a
  dedicated status column; session closure is recorded through phase closure
  log entries and concrete covering tests/gates.
- Overall closure bar: failed-then-retried edits must converge sender and
  receiver content plus edited badge, or remain visibly non-delivered; tombstone
  retry, receiver divergence, ignored-edit idempotency, and final gate evidence
  must be recorded without touching unrelated rollout docs.
- Final verdict policy: persist exactly one of `closed`,
  `accepted_with_explicit_follow_up`, `residual_only`, or `still_open` after
  P3A, P3B, and CLOSURE are resolved.

## Overall closure bar

Failed-then-retried edits must either converge sender and receiver text plus
edited badge or remain visibly non-delivered. A retry must never mint, persist,
or replay a plain chat payload under an edited or deleted message id. Failed
delete tombstones must have a live v2 deletion-envelope retry route, receiver
dedup must expose divergent plain duplicates without applying unauthenticated
content, ignored edit replays must ack truthfully, and the 116 gate/docs/device
evidence must be closed without touching unrelated rollout docs.

## Source of truth

- `Test-Flight-Improv/116-edit-retry-fidelity.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `lib/features/conversation/application/retry_failed_messages_use_case.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/conversation/application/delete_message_use_case.dart`
- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/conversation/application/recovered_inbox_chat_disposition.dart`
- Direct suites named in the 116 source doc:
  `retry_failed_messages_use_case_test.dart`,
  `send_chat_message_use_case_test.dart`,
  `handle_incoming_chat_message_use_case_test.dart`,
  `delete_message_use_case_test.dart`,
  `chat_message_listener_test.dart`,
  `recovered_inbox_chat_disposition_test.dart`, and
  `test/features/conversation/integration/edit_retry_round_trip_test.dart`.
- Graphify-arch exact-symbol intake:
  `retry_failed_messages_use_case deriveRetryAction`,
  `sendChatMessage downgrade gate`,
  `_retryInFlightMessageIds retry single-flight retry_failed_messages_use_case`,
  `tombstone retry delete_message_tombstone_visibility`, and
  `duplicate-content-mismatch retry_failed_messages_use_case send_chat_message_use_case`.

## Session ledger

| Session id | Title | Classification | Intended plan file | Depends on | Initial status |
|---|---|---|---|---|---|
| 116-P1 | Fallback retry fidelity and edit convergence | stale/already-covered | `Test-Flight-Improv/116-edit-retry-fidelity-session-116-P1-plan.md` | 115 Phase 1 status foundation | stale/already-covered |
| 116-P2 | Downgrade writer gate and retry single-flight | stale/already-covered | `Test-Flight-Improv/116-edit-retry-fidelity-session-116-P2-plan.md` | 116-P1 | stale/already-covered |
| 116-P3A | Tombstone retry liveness | implementation-ready | `Test-Flight-Improv/116-edit-retry-fidelity-session-116-P3A-plan.md` | 116-P2 and landed 115 status decision | accepted / host-closed |
| 116-P3B | Receiver divergence and ignored-edit idempotency | implementation-ready | `Test-Flight-Improv/116-edit-retry-fidelity-session-116-P3B-plan.md` | 116-P2; can run before or after 116-P3A if refreshed | accepted / host-closed |
| 116-CLOSURE | Gate capture, device evidence, and closure log | closure-only | `Test-Flight-Improv/116-edit-retry-fidelity-session-116-CLOSURE-plan.md` | 116-P3A and 116-P3B | residual_only |

## Ordered session breakdown

### 116-P1 - Fallback retry fidelity and edit convergence

- Classification: `stale/already-covered`
- Intended plan file: `Test-Flight-Improv/116-edit-retry-fidelity-session-116-P1-plan.md`
- Exact scope: row-derived retry action metadata, original `editedAt` and
  `createdAt` preservation, v1 edit reconstruction, and the
  `edit_retry_round_trip_test.dart` convergence proof.
- Why its own session: this was the correctness floor for id-keyed dedup and
  receipt safety.
- Likely code-entry files: `retry_failed_messages_use_case.dart`,
  `message_payload.dart`, and the edit retry integration test.
- Likely direct tests/regressions:
  `retry_failed_messages_use_case_test.dart`,
  `retry_unacked_messages_use_case_test.dart`,
  `send_reaction_use_case_test.dart`, and
  `edit_retry_round_trip_test.dart`.
- Likely named gates: `./scripts/run_test_gates.sh 1to1`,
  `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`,
  `./scripts/run_test_gates.sh completeness-check`, plus Go sanity gates as
  scope-leak detectors.
- Matrix/closure docs to update when done: already recorded in the source
  doc's Phase 1 closure log; final gate capture remains assigned to
  116-CLOSURE.
- Dependency: 115 Phase 1 status foundation.
- Current evidence: `deriveRetryAction`, row-derived fallback arguments, and
  `edit_retry_round_trip_test.dart` exist. Do not execute unless reopened by a
  real regression.

### 116-P2 - Downgrade writer gate and retry single-flight

- Classification: `stale/already-covered`
- Intended plan file: `Test-Flight-Improv/116-edit-retry-fidelity-session-116-P2-plan.md`
- Exact scope: `sendChatMessage` no-downgrade gate for edited/deleted rows,
  `CHAT_MSG_SEND_ACTION_DOWNGRADE_BLOCKED`, retry single-flight, and
  settled-row recheck.
- Why its own session: this made downgraded envelopes unmintable and closed
  concurrency/stale-snapshot retry windows before downstream custody sweep
  work.
- Likely code-entry files: `send_chat_message_use_case.dart` and
  `retry_failed_messages_use_case.dart`.
- Likely direct tests/regressions:
  `send_chat_message_use_case_test.dart` and
  `retry_failed_messages_use_case_test.dart`.
- Likely named gates: `./scripts/run_test_gates.sh 1to1`,
  `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`,
  `./scripts/run_test_gates.sh completeness-check`, plus Go sanity gates as
  scope-leak detectors.
- Matrix/closure docs to update when done: already recorded in the source
  doc's Phase 2 closure log; final gate capture remains assigned to
  116-CLOSURE.
- Dependency: 116-P1.
- Current evidence: downgrade gate symbols and `_retryInFlightMessageIds` exist
  in current code. Do not execute unless reopened by a real regression.

### 116-P3A - Tombstone retry liveness

- Classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/116-edit-retry-fidelity-session-116-P3A-plan.md`
- Exact scope: implement a delete-tombstone retry route that never traverses
  `sendChatMessage`: stored v2 deletion-envelope direct replay after inbox
  store failure, legacy v1 tombstone rebuild to v2 when recipient key exists,
  missing-key fail-closed telemetry, and delete-envelope builder extraction
  from `delete_message_use_case.dart`.
- Why its own session: this is sender-side retry behavior and deletion-envelope
  construction, with different code paths and tests from receiver dedup/listener
  behavior.
- Likely code-entry files:
  `retry_failed_messages_use_case.dart`,
  `delete_message_use_case.dart`,
  `delete_message_tombstone_visibility.dart`, and
  `outbound_envelope_policy.dart`.
- Likely direct tests/regressions:
  `retry_failed_messages_use_case_test.dart` tombstone trio and
  `delete_message_use_case_test.dart` builder extraction pin.
- Likely named gates: direct Flutter suite for retry/delete use cases,
  `./scripts/run_test_gates.sh 1to1`,
  `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`, and
  `./scripts/run_test_gates.sh completeness-check`.
- Matrix/closure docs to update when done: mark the tombstone rows of
  `Test-Flight-Improv/116-edit-retry-fidelity.md` section 6 and Phase 3 closure
  notes; defer final gate-array edits to 116-CLOSURE.
- Dependency: 116-P2 and the current 115 status decision. Refresh status-string
  handling before implementation.
- Current status: `accepted` for the P3A host
  implementation. The sender-side tombstone retry path now keeps inbox-custody
  delete tombstones `inboxed` with retained v2 envelopes, replays stored v2
  deletion envelopes without traversing `sendChatMessage`, rebuilds legacy
  tombstones to v2 when a recipient key exists, and fail-closes with
  `RETRY_FAILED_DELETE_REBUILD_UNAVAILABLE` when the recipient key is missing.
- Closure evidence: direct retry/delete suites passed with 41 tests;
  `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`,
  `./scripts/run_test_gates.sh completeness-check`, `git diff --check`, and
  `./graphify-arch/refresh_arch_graph.sh` passed. The final expanded
  `./scripts/run_test_gates.sh 1to1` rerun passed with `+793` after the bridge
  timeout test was made deterministic and send-then-lock 7c was aligned with
  Doc 115 receipt-gated custody semantics.

### 116-P3B - Receiver divergence and ignored-edit idempotency

- Classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/116-edit-retry-fidelity-session-116-P3B-plan.md`
- Exact scope: emit `CHAT_MSG_RECEIVE_DUPLICATE_CONTENT_MISMATCH` for divergent
  non-edit duplicate text without applying unauthenticated content; map
  `HandleChatMessageResult.ignoredEdit` to a `ChatMessageProcessState`
  idempotent success path; confirm ignored edit nonces with `ok=true`; map
  staged ignored-edit replays to `rejected/'ignored_edit'`.
- Why its own session: this is receiver/listener/staging disposition behavior
  and has independent tests and compile-driven enum/switch work.
- Likely code-entry files:
  `handle_incoming_chat_message_use_case.dart`,
  `chat_message_listener.dart`, and
  `recovered_inbox_chat_disposition.dart`.
- Likely direct tests/regressions:
  `handle_incoming_chat_message_use_case_test.dart`,
  `chat_message_listener_test.dart`, and
  `recovered_inbox_chat_disposition_test.dart`.
- Likely named gates: direct Flutter suite for the three receiver/listener
  tests, `./scripts/run_test_gates.sh 1to1`,
  `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`, and
  `./scripts/run_test_gates.sh completeness-check`.
- Matrix/closure docs to update when done: mark duplicate mismatch,
  known-id edit pin, ignored edit ack, and staged replay rows in the source
  doc's matrix; defer final gate-array edits to 116-CLOSURE.
- Dependency: 116-P2. It can run before or after 116-P3A if refreshed against
  landed code.
- Current status: `accepted` for the P3B host
  implementation. Duplicate divergent non-edit content now emits
  `CHAT_MSG_RECEIVE_DUPLICATE_CONTENT_MISMATCH` without applying the incoming
  text; ignored edits now map to an explicit process state that confirms direct
  nonces with `ok=true`; staged ignored-edit replays map to
  `rejected/'ignored_edit'`.
- Closure evidence: direct receiver/listener/disposition suites passed 96
  tests; macOS baseline, completeness-check, `git diff --check`, and
  `./graphify-arch/refresh_arch_graph.sh` passed. The final expanded
  `./scripts/run_test_gates.sh 1to1` rerun passed with `+793`.

### 116-CLOSURE - Gate capture, device evidence, and closure log

- Classification: `closure-only`
- Intended plan file: `Test-Flight-Improv/116-edit-retry-fidelity-session-116-CLOSURE-plan.md`
- Exact scope: close the source doc after 116-P3A/P3B, add the 116 gate capture
  and required 1:1 file entries, run or record required host/device evidence,
  update closure logs, and leave open questions explicitly accepted or assigned.
- Why its own session: it validates multiple implementation slices and includes
  gate/doc/device evidence rather than a single code seam.
- Likely code-entry files: none unless gate-array doc/script entries are still
  missing; expected doc/script files are `test-gate-definitions.md`,
  `scripts/run_test_gates.sh`, and the source doc.
- Likely direct tests/regressions: source doc section 8 evidence items,
  `./scripts/run_test_gates.sh 1to1`,
  `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`,
  `./scripts/run_test_gates.sh completeness-check`, direct Flutter suites
  touched by P3A/P3B, and Go sanity gates as scope-leak detectors.
- Likely named gates: same as above; device evidence includes divergence
  repro/repair, lost-ack idempotency, mixed-version interop, delete retry, and
  field telemetry watch where available.
- Matrix/closure docs to update when done:
  `Test-Flight-Improv/116-edit-retry-fidelity.md`,
  `Test-Flight-Improv/test-gate-definitions.md`, and
  `scripts/run_test_gates.sh`.
- Dependency: 116-P3A and 116-P3B.
- Current status: `residual_only`. The 116 integration file
  is now present in the frozen `1to1` array and gate definitions, the source
  doc closure log has a final verdict, Go scope-leak sanity passed, and the
  final expanded `1to1` gate passed with `+793`. Release/device evidence is
  archived as unclaimed residual lab evidence.

## Why this is not fewer sessions

Combining P3A and P3B would bundle sender-side deletion-envelope retry with
receiver/listener/staging semantics. They touch different production seams,
different tests, and different failure modes. Closure/gate/device evidence
also validates both implementation slices and should not be hidden in either
code session.

## Why this is not more sessions

The Phase 3 sender-side tombstone cases share one retry route and one direct
test family, so splitting v2 replay, v1 rebuild, and missing-key telemetry
would create bookkeeping. The receiver mismatch and ignored-edit ack/disposition
changes are one receiver truthfulness slice because the same edit retry
idempotency contract drives all of them. Phases 1-2 are already covered and
should not become fresh sessions without a regression.

## Regression and gate contract

Apply `Test-Flight-Improv/14-regression-test-strategy.md` by pairing each
production bug with a permanent targeted regression and by running named gates
when shared 1:1 send, retry, listener, inbox, staging, or recovery paths change.
Apply `Test-Flight-Improv/test-gate-definitions.md` by keeping exact file paths
classified, keeping `./scripts/run_test_gates.sh completeness-check` green, and
not removing red tests from gate definitions to mask failures.

Minimum gate contract per pending implementation session:

- Direct touched suites first.
- `./scripts/run_test_gates.sh 1to1`.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`.
- `./scripts/run_test_gates.sh completeness-check`.

## Final Program Verdict

Verdict: residual_only

Date: 2026-06-13T15:07:40Z

Doc 116 implementation is closed. P1/P2 were already closed, P3A and P3B are
host-closed, and closure artifacts record the 116 gate capture. The final
expanded `./scripts/run_test_gates.sh 1to1` rerun passed with `+793`, and the
later completeness pass reached `844/844`. Release/device evidence from the
source doc's section 8 is archived as unclaimed residual lab evidence.
- Go sanity gates only as scope-leak detectors because doc 116 is app-side
  Dart-only.

## Matrix update contract

Update the existing matrix in `Test-Flight-Improv/116-edit-retry-fidelity.md`
section 6 rather than creating a new matrix doc.

- 116-P3A owns tombstone route rows: v2 tombstone, legacy v1 tombstone with key,
  legacy v1 tombstone without key.
- 116-P3B owns receiver truthfulness rows: divergent non-edit duplicate,
  known-id edit pin, superseded identical edit, and staged superseded edit
  replay.
- 116-CLOSURE owns final gate capture, source-doc closure logs, and gate-array
  doc/script updates.

## Downstream execution path

For each pending session, run:

- `$implementation-plan-orchestrator`
- `$implementation-execution-qa-orchestrator`
- `$implementation-closure-audit-orchestrator`

For `116-P1` and `116-P2`, do not execute downstream unless a fresh regression
reopens the covered scope. If reopened, use the doc-scoped intended plan path
listed in the ledger.

## Structural blockers remaining

None for decomposition.

Execution-time blockers refreshed and resolved:

- The landed 115 status decision was used for P3A deletion inbox terminals:
  `status: 'inboxed'`, `transport: 'inbox'`, retained wire envelope, and
  visible tombstone until receipt/direct ack.
- This doc owned the final coordinated gate-array edit. The 116 gate capture
  now exists in `Test-Flight-Improv/test-gate-definitions.md`, and
  `edit_retry_round_trip_test.dart` is listed in both the public gate doc and
  `scripts/run_test_gates.sh`.

## Accepted differences intentionally left unchanged

- No migration for already-poisoned field rows; the source doc says the lost
  edit metadata is unrecoverable.
- No receiver-initiated content repair for divergent plain duplicates; emitting
  telemetry without applying unauthenticated content is the intended defense.
- No repository/interface-level lock for retry single-flight; the covered
  file-private set remains accepted until retries move across isolates.
- No Go, relay, gomobile, or DB schema work is included unless a pending session
  proves the source doc stale.

## Exact docs/files used as evidence

- Graphify-arch query results for `deriveRetryAction` and
  `_retryInFlightMessageIds` locate current retry fidelity and single-flight in
  `retry_failed_messages_use_case.dart`.
- Graphify-arch query for `sendChatMessage downgrade gate` locates
  `send_chat_message_use_case.dart`.
- Graphify-arch query for tombstone retry locates the deletion/tombstone
  family and confirms the relevant retry/delete/delete-visibility concepts.
- Graphify-arch and direct source reads were used to locate the receiver,
  listener, and staging-disposition seams for P3B before implementation.
- Direct `rg` confirmed:
  `deriveRetryAction`, `_retryInFlightMessageIds`,
  `RETRY_FAILED_MESSAGE_SKIPPED_IN_FLIGHT`,
  `RETRY_FAILED_MESSAGE_SKIPPED_SETTLED`,
  `CHAT_MSG_SEND_ACTION_DOWNGRADE_BLOCKED`,
  `edited_row_plain_send`, and `deleted_row_plain_send` exist.
- Direct `rg`/test evidence now confirms the formerly pending symbols and
  entries exist: `CHAT_MSG_RECEIVE_DUPLICATE_CONTENT_MISMATCH`,
  `RETRY_FAILED_DELETE_REBUILD_UNAVAILABLE`, `buildDeletionWireEnvelope`,
  `ChatMessageProcessState.ignoredEdit`, `ignored_edit`, and
  `edit_retry_round_trip_test.dart` in both 1:1 gate definitions.

## Why the decomposition is safe to send into downstream planning/execution

It preserves the source doc's closure reality instead of re-executing covered
Phases 1-2, uses only doc-scoped plan paths, splits the remaining Phase 3 work
by independently verifiable seams, keeps closure/gate/device evidence separate,
and carries the current blockers into the planning boundary so implementation
agents refresh status and gate ownership before writing code.
