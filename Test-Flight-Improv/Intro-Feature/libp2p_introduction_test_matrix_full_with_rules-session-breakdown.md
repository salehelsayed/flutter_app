# Libp2p Introduction Test Matrix Full With Rules Session Breakdown

## Decomposition artifact

- Artifact path:
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`
- Supporting docs:
  - `Test-Flight-Improv/Intro-Feature/_Intro-reliability-gap-audit.md`
  - `Test-Flight-Improv/Intro-Feature/test-inventory.md`
  - `Test-Flight-Improv/Intro-Feature/c4-code.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Decomposition date:
  `2026-04-08`
- Isolation note:
  - this artifact was produced in a fresh decomposition agent
  - the handoff was bounded to the named source matrix, the derived adjacent breakdown path, and the explicit row-by-row decomposition constraints
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Downstream execution path

- Row-owned sessions should run through, in breakdown order:
  1. `$implementation-plan-orchestrator`
  2. `$implementation-execution-qa-orchestrator`
  3. `$implementation-closure-audit-orchestrator`
- Execute rows in this default order:
  1. `P0` rows in source order
  2. `P1` rows in source order
  3. `P2` rows in source order
- No shared prerequisite or closure-only session was added. Each matrix row keeps direct ownership.

## Recommended plan count

- `68`
- Smallest safe split:
  - `68` row-owned sessions keyed directly to the source matrix row ids
  - `0` non-row sessions because this matrix can stay row-granular without seam buckets
- Row disposition counts:
  - `covered_in_repo`: `36`
  - `needs_code_and_tests`: `3`
  - `needs_repo_evidence`: `9`
  - `needs_tests_only`: `20`

## Overall closure bar

`libp2p_introduction_test_matrix_full_with_rules.md` is only closed when all of the following are true at the same time:

- every source row is mapped to exactly one session id, with no silent omissions and no seam-bucket merges
- each row is truthfully classified as already covered, tests-only, code-plus-tests, or missing repo-owned evidence based on current intro code and tests
- rows that currently rely on partial or in-memory proof do not get overclaimed as transport-complete without the stronger evidence the source matrix requires
- later closure work updates the source matrix and this breakdown per row, not only by broad intro subsystem
- intro follow-up UI, notification, recovery, and transport rows stay aligned with the current test-inventory and gate-definition docs instead of drifting into stale prose

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Intro-Feature/_Intro-reliability-gap-audit.md`
- `Test-Flight-Improv/Intro-Feature/test-inventory.md`
- `Test-Flight-Improv/Intro-Feature/c4-code.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`

Current repo facts that materially affected row classification:

- `test-inventory.md` now confirms a strong intro host-side gate, a sizeable intro feature suite, direct row-owned proof for the formerly thin non-party guard / exact `Message` CTA / Orbit banner-copy / FriendPickerWired / SentConfirmationWired / push-copy seams, and remaining non-matrix gaps mostly around migration coverage, DB-helper specificity, flow-event inventory, some batch-progress edges, and end-to-end push trigger delivery.
- `_Intro-reliability-gap-audit.md` recorded the sender-local durability closure, and later matrix sessions added the stronger split-brain recovery, avatar no-rollback, and related repair evidence needed to close the formerly deferred intro recovery seams.
- `accept_introduction_use_case.dart` and `pass_introduction_use_case.dart` now reject non-party callers before any mutation or outbound delivery, and direct accept/pass regressions close `RM-009`.
- `send_introduction_use_case.dart` now persists the sender-local intro row before outbound delivery staging, and `send_introduction_test.dart` includes a post-first-delivery crash regression that closes `DR-009`.
- `friend_picker_wired.dart`, `sent_confirmation_wired.dart`, `orbit_wired.dart`, and the intro/push widget suites now have row-owned proof for the formerly thin UX flow, banner, and copy rows rather than only implementation-adjacent behavior.
- `test-gate-definitions.md` makes `./scripts/run_test_gates.sh intro` the primary named gate for intro work and reserves `./scripts/run_test_gates.sh transport` for shared resume, fallback, and transport changes.

## Matrix row inventory

| Row ID | Scenario | Priority | Section | Provisional row disposition | Intended session id |
| --- | --- | --- | --- | --- | --- |
| `IL-001` | Banner shown only when all six gates pass | `P0` | Core Introduction Lifecycle | `covered_in_repo` | `IL-001` |
| `IL-002` | Banner dismissal persists, but overflow re-entry still works | `P1` | Core Introduction Lifecycle | `covered_in_repo` | `IL-002` |
| `IL-003` | Friend picker filters recipient / self / blocked / archived contacts while keeping re-introducible pairs selectable | `P0` | Core Introduction Lifecycle | `covered_in_repo` | `IL-003` |
| `IL-004` | Single introduction send creates one shared introId, two outbound envelopes, and one local row | `P0` | Core Introduction Lifecycle | `covered_in_repo` | `IL-004` |
| `IL-005` | Batch send keeps a concurrency cap of 10, stable ordering, and truthful progress | `P1` | Core Introduction Lifecycle | `covered_in_repo` | `IL-005` |
| `IL-006` | v2 is preferred when an ML-KEM key exists; v1 fallback is used when the key is absent or encrypt fails | `P0` | Core Introduction Lifecycle | `covered_in_repo` | `IL-006` |
| `IL-007` | Online receipt creates a pending intro row, system message, and local notification | `P0` | Core Introduction Lifecycle | `covered_in_repo` | `IL-007` |
| `IL-008` | Offline recipient later receives the intro via inbox / store-and-forward | `P0` | Core Introduction Lifecycle | `covered_in_repo` | `IL-008` |
| `IL-009` | Blocked introducer `send` is rejected without intro row, UI, or notification | `P0` | Core Introduction Lifecycle | `covered_in_repo` | `IL-009` |
| `IL-010` | Already-connected intro is visible but non-actionable and does not inflate the pending badge | `P0` | Core Introduction Lifecycle | `covered_in_repo` | `IL-010` |
| `IL-011` | Duplicate or older same-pair `send` is ignored; newer same-pair `send` replaces stale row | `P0` | Core Introduction Lifecycle | `covered_in_repo` | `IL-011` |
| `IL-012` | Introducer-side row reflects later accept/pass updates from both parties | `P0` | Core Introduction Lifecycle | `covered_in_repo` | `IL-012` |
| `IL-013` | Intro expires after 30 days, and a fresh re-introduction after expiry starts a new valid journey | `P1` | Core Introduction Lifecycle | `needs_tests_only` | `IL-013` |
| `RM-001` | One-sided accept shows waiting / partial state and creates no contact | `P0` | Responses and Mutual Connection | `covered_in_repo` | `RM-001` |
| `RM-002` | Accept order is irrelevant | `P0` | Responses and Mutual Connection | `covered_in_repo` | `RM-002` |
| `RM-003` | A pass from either side yields terminal `passed` and no contact | `P0` | Responses and Mutual Connection | `covered_in_repo` | `RM-003` |
| `RM-004` | One side accepts and the other later passes; overall remains `passed` | `P0` | Responses and Mutual Connection | `covered_in_repo` | `RM-004` |
| `RM-005` | Accept after a terminal pass never reopens the intro | `P0` | Responses and Mutual Connection | `covered_in_repo` | `RM-005` |
| `RM-006` | Accept/pass is sent to both the introducer and the stranger, using intro-carried keys first and contact fallback second | `P0` | Responses and Mutual Connection | `covered_in_repo` | `RM-006` |
| `RM-007` | Duplicate accept/pass deliveries are idempotent | `P0` | Responses and Mutual Connection | `covered_in_repo` | `RM-007` |
| `RM-008` | Unknown responderId is rejected with no mutation | `P0` | Responses and Mutual Connection | `covered_in_repo` | `RM-008` |
| `RM-009` | Non-party caller cannot invoke accept/pass on an intro they do not belong to | `P0` | Responses and Mutual Connection | `covered_in_repo` | `RM-009` |
| `RM-010` | Accept/pass from a now-blocked stranger still completes the handshake path | `P0` | Responses and Mutual Connection | `covered_in_repo` | `RM-010` |
| `RM-011` | The second accept creates exactly one contact on each side with correct keys and introducedBy metadata | `P0` | Responses and Mutual Connection | `covered_in_repo` | `RM-011` |
| `RM-012` | Introducer converges to `mutualAccepted` without duplicate B/C contacts | `P0` | Responses and Mutual Connection | `covered_in_repo` | `RM-012` |
| `RM-013` | Mutual acceptance creates system message and new-connection notification; avatar retry failure does not roll back the contact | `P1` | Responses and Mutual Connection | `needs_tests_only` | `RM-013` |
| `RM-014` | First encrypted chat works immediately after mutual acceptance | `P0` | Responses and Mutual Connection | `covered_in_repo` | `RM-014` |
| `RM-015` | `resolveUnknownInboxSender` repairs a missing contact when intro state proves the contact should exist | `P1` | Responses and Mutual Connection | `covered_in_repo` | `RM-015` |
| `RM-016` | `expireOldIntroductions` heals stale rows to mutualAccepted/passed/expired and reruns missed side effects | `P1` | Responses and Mutual Connection | `needs_tests_only` | `RM-016` |
| `DR-001` | Acked direct send clears the staged outbox row | `P0` | Delivery, Ordering, and Recovery | `covered_in_repo` | `DR-001` |
| `DR-002` | Unacked live send stays retryable, and resume retrier replays via inbox-only semantics | `P0` | Delivery, Ordering, and Recovery | `covered_in_repo` | `DR-002` |
| `DR-003` | Local/direct race converges cleanly with no duplicate intro rows or duplicate delivery side effects | `P1` | Delivery, Ordering, and Recovery | `needs_repo_evidence` | `DR-003` |
| `DR-004` | Relay-probe fallback converges cleanly after direct paths fail | `P1` | Delivery, Ordering, and Recovery | `needs_repo_evidence` | `DR-004` |
| `DR-005` | Partial fan-out is safe: B receives now, C later, and the pair still converges | `P0` | Delivery, Ordering, and Recovery | `needs_repo_evidence` | `DR-005` |
| `DR-006` | Responses arriving before the `send` row are durably staged and replayed correctly | `P0` | Delivery, Ordering, and Recovery | `covered_in_repo` | `DR-006` |
| `DR-007` | Duplicate network deliveries and stale queued envelopes never reopen a terminal intro | `P0` | Delivery, Ordering, and Recovery | `needs_tests_only` | `DR-007` |
| `DR-008` | App resume processes multiple stalled/failed rows and cleans prior delivered+inbox rows | `P1` | Delivery, Ordering, and Recovery | `needs_repo_evidence` | `DR-008` |
| `DR-009` | Sender crash after remote delivery but before local intro persistence heals on restart | `P0` | Delivery, Ordering, and Recovery | `needs_code_and_tests` | `DR-009` |
| `DR-010` | Partition healing after divergent delivery or divergent accepts converges across A/B/C | `P0` | Delivery, Ordering, and Recovery | `needs_repo_evidence` | `DR-010` |
| `DR-011` | Offline relay intro delivery converges to mutual acceptance and first encrypted chat | `P0` | Delivery, Ordering, and Recovery | `needs_repo_evidence` | `DR-011` |
| `DR-012` | Accept/pass notifications fall back to inbox while peers are unreachable and still converge after drain | `P0` | Delivery, Ordering, and Recovery | `needs_repo_evidence` | `DR-012` |
| `DR-013` | Re-introducing the same pair repairs a missed side and ignores stale older delivery | `P0` | Delivery, Ordering, and Recovery | `covered_in_repo` | `DR-013` |
| `DR-014` | Split-brain mutual acceptance heals after restart/reconnect | `P0` | Delivery, Ordering, and Recovery | `needs_repo_evidence` | `DR-014` |
| `DR-015` | Multiple simultaneous intros stay isolated | `P1` | Delivery, Ordering, and Recovery | `needs_repo_evidence` | `DR-015` |
| `DR-016` | Same pair with a different introducer reopens as alreadyConnected without duplicate contacts | `P1` | Delivery, Ordering, and Recovery | `covered_in_repo` | `DR-016` |
| `SC-001` | Replay of the same envelope / messageId / introductionId never duplicates rows, contacts, system messages, or notifications | `P0` | Security, Correctness, and Convergence | `needs_tests_only` | `SC-001` |
| `SC-002` | Tampered ciphertext or wrong secret key is rejected with no state mutation | `P0` | Security, Correctness, and Convergence | `needs_tests_only` | `SC-002` |
| `SC-003` | ML-KEM key mismatch between intro record and current contact state is escalated or rejected, not silently accepted | `P0` | Security, Correctness, and Convergence | `needs_code_and_tests` | `SC-003` |
| `SC-004` | `ensureEnvelopeMessageId` patches missing `messageId` and still accepts legacy `id` envelopes | `P1` | Security, Correctness, and Convergence | `needs_tests_only` | `SC-004` |
| `SC-005` | Blocked-sender rule applies only to `send`; accept/pass always pass through | `P0` | Security, Correctness, and Convergence | `covered_in_repo` | `SC-005` |
| `SC-006` | Key direction awareness remains correct when creating contacts | `P0` | Security, Correctness, and Convergence | `covered_in_repo` | `SC-006` |
| `SC-007` | `alreadyConnected` is terminal and visible, but not counted as pending | `P0` | Security, Correctness, and Convergence | `covered_in_repo` | `SC-007` |
| `SC-008` | `passed`, `expired`, and `alreadyConnected` never regress to pending because of stale delivery | `P0` | Security, Correctness, and Convergence | `needs_tests_only` | `SC-008` |
| `SC-009` | Same-pair dedupe semantics are stable across same introducer and different introducer cases | `P0` | Security, Correctness, and Convergence | `covered_in_repo` | `SC-009` |
| `SC-010` | State isolation holds across multiple intro chains and multiple `introductionId` values | `P0` | Security, Correctness, and Convergence | `covered_in_repo` | `SC-010` |
| `SC-011` | Pending badge counts only truly pending intros | `P0` | Security, Correctness, and Convergence | `covered_in_repo` | `SC-011` |
| `UX-001` | Orbit intro review renders grouped intros and the correct pending count | `P1` | UX, Orbit, Notifications, and Cross-Feature Coverage | `needs_tests_only` | `UX-001` |
| `UX-002` | IntroRow copy and actions are exact for pending, waiting, passed, alreadyConnected, and mutualAccepted states | `P0` | UX, Orbit, Notifications, and Cross-Feature Coverage | `needs_tests_only` | `UX-002` |
| `UX-003` | FriendPickerWired full flow: loading, search, selection, send, progress, and navigation callback | `P1` | UX, Orbit, Notifications, and Cross-Feature Coverage | `needs_tests_only` | `UX-003` |
| `UX-004` | SentConfirmationWired end-to-end matches the sent result set | `P2` | UX, Orbit, Notifications, and Cross-Feature Coverage | `needs_tests_only` | `UX-004` |
| `UX-005` | Conversation banner and overflow entry remain consistent after dismiss, introsSentAt, block/unblock, and message-count changes | `P1` | UX, Orbit, Notifications, and Cross-Feature Coverage | `covered_in_repo` | `UX-005` |
| `UX-006` | New-intro and mutual-accept notifications use the correct title/body content | `P1` | UX, Orbit, Notifications, and Cross-Feature Coverage | `needs_tests_only` | `UX-006` |
| `UX-007` | Notification deep-link opens Orbit intros and preserves shell return behavior | `P1` | UX, Orbit, Notifications, and Cross-Feature Coverage | `covered_in_repo` | `UX-007` |
| `UX-008` | Feed connection card reflects introducedBy metadata and blocked state | `P2` | UX, Orbit, Notifications, and Cross-Feature Coverage | `covered_in_repo` | `UX-008` |
| `UX-009` | Mixed-script, RTL, long, and null usernames render correctly across intro UI surfaces | `P1` | UX, Orbit, Notifications, and Cross-Feature Coverage | `covered_in_repo` | `UX-009` |
| `UX-010` | Orbit live refresh reacts to introReceived, status changes, and delete actions | `P1` | UX, Orbit, Notifications, and Cross-Feature Coverage | `covered_in_repo` | `UX-010` |
| `UX-011` | Orbit intro pending-count banner variant matches the underlying intro state | `P2` | UX, Orbit, Notifications, and Cross-Feature Coverage | `needs_tests_only` | `UX-011` |
| `UX-012` | Delete confirmation and cancel flow for intro rows are reliable | `P1` | UX, Orbit, Notifications, and Cross-Feature Coverage | `covered_in_repo` | `UX-012` |

## Row traceability rule

- Every source row maps to exactly one session id with the same row id because all source ids are filename-safe.
- No source row was merged into a seam bucket and no `duplicate_of` relationship was needed for this matrix.
- Later closure work must report final truth per source row, not only per broad intro subsystem.

## Session ledger

| Session ID | Source row | Priority | Row disposition | Classification | Intended plan file | Depends on | Current status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `IL-001` | `IL-001` | `P0` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-IL-001-plan.md` | `none` | `stale/already-covered` |
| `IL-003` | `IL-003` | `P0` | `covered_in_repo` | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-IL-003-plan.md` | `none` | `accepted` |
| `IL-004` | `IL-004` | `P0` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-IL-004-plan.md` | `none` | `stale/already-covered` |
| `IL-006` | `IL-006` | `P0` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-IL-006-plan.md` | `none` | `stale/already-covered` |
| `IL-007` | `IL-007` | `P0` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-IL-007-plan.md` | `none` | `stale/already-covered` |
| `IL-008` | `IL-008` | `P0` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-IL-008-plan.md` | `none` | `stale/already-covered` |
| `IL-009` | `IL-009` | `P0` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-IL-009-plan.md` | `none` | `stale/already-covered` |
| `IL-010` | `IL-010` | `P0` | `covered_in_repo` | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-IL-010-plan.md` | `none` | `accepted` |
| `IL-011` | `IL-011` | `P0` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-IL-011-plan.md` | `none` | `stale/already-covered` |
| `IL-012` | `IL-012` | `P0` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-IL-012-plan.md` | `none` | `stale/already-covered` |
| `RM-001` | `RM-001` | `P0` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-001-plan.md` | `none` | `stale/already-covered` |
| `RM-002` | `RM-002` | `P0` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-002-plan.md` | `none` | `stale/already-covered` |
| `RM-003` | `RM-003` | `P0` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-003-plan.md` | `none` | `stale/already-covered` |
| `RM-004` | `RM-004` | `P0` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-004-plan.md` | `none` | `stale/already-covered` |
| `RM-005` | `RM-005` | `P0` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-005-plan.md` | `none` | `stale/already-covered` |
| `RM-006` | `RM-006` | `P0` | `covered_in_repo` | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-006-plan.md` | `none` | `accepted` |
| `RM-007` | `RM-007` | `P0` | `covered_in_repo` | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-007-plan.md` | `none` | `accepted` |
| `RM-008` | `RM-008` | `P0` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-008-plan.md` | `none` | `stale/already-covered` |
| `RM-009` | `RM-009` | `P0` | `covered_in_repo` | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-009-plan.md` | `none` | `accepted` |
| `RM-010` | `RM-010` | `P0` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-010-plan.md` | `none` | `stale/already-covered` |
| `RM-011` | `RM-011` | `P0` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-011-plan.md` | `none` | `stale/already-covered` |
| `RM-012` | `RM-012` | `P0` | `covered_in_repo` | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-012-plan.md` | `none` | `accepted` |
| `RM-014` | `RM-014` | `P0` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-014-plan.md` | `none` | `stale/already-covered` |
| `DR-001` | `DR-001` | `P0` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-001-plan.md` | `none` | `stale/already-covered` |
| `DR-002` | `DR-002` | `P0` | `covered_in_repo` | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-002-plan.md` | `none` | `accepted` |
| `DR-005` | `DR-005` | `P0` | `needs_repo_evidence` | `evidence-gated` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-005-plan.md` | `none` | `accepted` |
| `DR-006` | `DR-006` | `P0` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-006-plan.md` | `none` | `stale/already-covered` |
| `DR-007` | `DR-007` | `P0` | `needs_tests_only` | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-007-plan.md` | `none` | `accepted` |
| `DR-009` | `DR-009` | `P0` | `needs_code_and_tests` | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-009-plan.md` | `none` | `accepted` |
| `DR-010` | `DR-010` | `P0` | `needs_repo_evidence` | `evidence-gated` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-010-plan.md` | `none` | `accepted` |
| `DR-011` | `DR-011` | `P0` | `needs_repo_evidence` | `evidence-gated` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-011-plan.md` | `none` | `accepted` |
| `DR-012` | `DR-012` | `P0` | `needs_repo_evidence` | `evidence-gated` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-012-plan.md` | `none` | `accepted` |
| `DR-013` | `DR-013` | `P0` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-013-plan.md` | `none` | `stale/already-covered` |
| `DR-014` | `DR-014` | `P0` | `needs_repo_evidence` | `evidence-gated` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-014-plan.md` | `none` | `accepted` |
| `SC-001` | `SC-001` | `P0` | `needs_tests_only` | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-SC-001-plan.md` | `none` | `accepted` |
| `SC-002` | `SC-002` | `P0` | `needs_tests_only` | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-SC-002-plan.md` | `none` | `accepted` |
| `SC-003` | `SC-003` | `P0` | `needs_code_and_tests` | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-SC-003-plan.md` | `none` | `accepted` |
| `SC-005` | `SC-005` | `P0` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-SC-005-plan.md` | `none` | `stale/already-covered` |
| `SC-006` | `SC-006` | `P0` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-SC-006-plan.md` | `none` | `stale/already-covered` |
| `SC-007` | `SC-007` | `P0` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-SC-007-plan.md` | `none` | `stale/already-covered` |
| `SC-008` | `SC-008` | `P0` | `needs_tests_only` | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-SC-008-plan.md` | `none` | `accepted` |
| `SC-009` | `SC-009` | `P0` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-SC-009-plan.md` | `none` | `stale/already-covered` |
| `SC-010` | `SC-010` | `P0` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-SC-010-plan.md` | `none` | `stale/already-covered` |
| `SC-011` | `SC-011` | `P0` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-SC-011-plan.md` | `none` | `stale/already-covered` |
| `UX-002` | `UX-002` | `P0` | `needs_tests_only` | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-UX-002-plan.md` | `none` | `accepted` |
| `IL-002` | `IL-002` | `P1` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-IL-002-plan.md` | `none` | `stale/already-covered` |
| `IL-005` | `IL-005` | `P1` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-IL-005-plan.md` | `none` | `stale/already-covered` |
| `IL-013` | `IL-013` | `P1` | `needs_tests_only` | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-IL-013-plan.md` | `none` | `accepted` |
| `RM-013` | `RM-013` | `P1` | `needs_tests_only` | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-013-plan.md` | `none` | `accepted` |
| `RM-015` | `RM-015` | `P1` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-015-plan.md` | `none` | `stale/already-covered` |
| `RM-016` | `RM-016` | `P1` | `needs_tests_only` | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-016-plan.md` | `none` | `accepted` |
| `DR-003` | `DR-003` | `P1` | `needs_repo_evidence` | `evidence-gated` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-003-plan.md` | `none` | `accepted` |
| `DR-004` | `DR-004` | `P1` | `needs_repo_evidence` | `evidence-gated` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-004-plan.md` | `none` | `accepted` |
| `DR-008` | `DR-008` | `P1` | `needs_repo_evidence` | `evidence-gated` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-008-plan.md` | `none` | `accepted` |
| `DR-015` | `DR-015` | `P1` | `needs_repo_evidence` | `evidence-gated` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-015-plan.md` | `none` | `accepted` |
| `DR-016` | `DR-016` | `P1` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-016-plan.md` | `none` | `stale/already-covered` |
| `SC-004` | `SC-004` | `P1` | `needs_tests_only` | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-SC-004-plan.md` | `none` | `accepted` |
| `UX-001` | `UX-001` | `P1` | `needs_tests_only` | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-UX-001-plan.md` | `none` | `accepted` |
| `UX-003` | `UX-003` | `P1` | `needs_tests_only` | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-UX-003-plan.md` | `none` | `accepted` |
| `UX-005` | `UX-005` | `P1` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-UX-005-plan.md` | `none` | `stale/already-covered` |
| `UX-006` | `UX-006` | `P1` | `needs_tests_only` | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-UX-006-plan.md` | `none` | `accepted` |
| `UX-007` | `UX-007` | `P1` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-UX-007-plan.md` | `none` | `stale/already-covered` |
| `UX-009` | `UX-009` | `P1` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-UX-009-plan.md` | `none` | `stale/already-covered` |
| `UX-010` | `UX-010` | `P1` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-UX-010-plan.md` | `none` | `stale/already-covered` |
| `UX-012` | `UX-012` | `P1` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-UX-012-plan.md` | `none` | `stale/already-covered` |
| `UX-004` | `UX-004` | `P2` | `needs_tests_only` | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-UX-004-plan.md` | `none` | `accepted` |
| `UX-008` | `UX-008` | `P2` | `covered_in_repo` | `stale/already-covered` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-UX-008-plan.md` | `none` | `stale/already-covered` |
| `UX-011` | `UX-011` | `P2` | `needs_tests_only` | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-UX-011-plan.md` | `none` | `accepted` |

## Current pipeline state

- sessions processed so far: `32/68`
- sessions accepted so far: `32`
- sessions resolved as `stale/already-covered`: `36`
- sessions currently blocked: `0`
- latest accepted session: `UX-011`
- next runnable session in order: `none`
- current doc state: `closed`
- final program verdict is persisted below
- delivery mode:
  degraded local continuation mode entered on `2026-04-08` after repeated
  fresh-child planning/execution/closure and continuation-controller passes
  no-progressed under bounded wait while the persisted breakdown and session
  artifacts remained safe enough to resume locally
- closure alignment note:
  `UX-011` is now truthfully closed on landed Orbit banner regressions and a
  green intro gate rerun, so all remaining sessions are resolved with no open
  ordering or truth-alignment blocker left in this breakdown

## Final program acceptance

- final program verdict:
  `closed`
- docs updated:
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`,
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`,
  `Test-Flight-Improv/Intro-Feature/test-inventory.md`,
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-005-plan.md`,
  `Test-Flight-Improv/Intro-Feature/_Intro-reliability-gap-audit.md`,
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-007-plan.md`,
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-009-plan.md`,
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-010-plan.md`,
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-011-plan.md`,
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-012-plan.md`,
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-014-plan.md`,
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-015-plan.md`,
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-SC-001-plan.md`,
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-SC-002-plan.md`,
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-SC-003-plan.md`,
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-SC-004-plan.md`,
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-SC-008-plan.md`,
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-UX-001-plan.md`,
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-UX-003-plan.md`,
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-UX-004-plan.md`,
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-UX-006-plan.md`,
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-UX-011-plan.md`,
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-UX-002-plan.md`,
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-IL-013-plan.md`,
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-013-plan.md`,
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-016-plan.md`,
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-003-plan.md`,
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-004-plan.md`,
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-008-plan.md`
- what is now closed:
  every source row in
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`
  now resolves to `Closed` or `Covered`, and the formerly unresolved intro
  recovery, hardening, and UX proof rows are all reflected in the maintained
  matrix, inventory, and session ledger
- still-open blocker for safe continuation:
  none
- explicit follow-up that remains:
  none
- safe-to-close rationale:
  all `68/68` sessions are resolved, the source matrix no longer contains an
  open row, and the matrix, inventory, and breakdown now align on the same
  final intro-program truth

## Ordered session breakdown

### Session IL-001

- Source row / scenario / disposition / classification / plan: `IL-001` / `Banner shown only when all six gates pass` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-IL-001-plan.md`
- Scope / ownership: preserve the currently covered IL-001 contract for "Banner shown only when all six gates pass" and reopen only if new contradictory evidence appears; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/introduction/application/check_intro_banner_use_case.dart`, `lib/features/conversation/presentation/screens/conversation_wired.dart`, `lib/features/introduction/presentation/widgets/intro_banner.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `check_intro_banner_test.dart`, `check_intro_banner_extended_test.dart`, and regression case 10.; `test/features/introduction/application/check_intro_banner_test.dart`, `test/features/introduction/application/check_intro_banner_extended_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session IL-003

- Source row / scenario / disposition / classification / plan: `IL-003` / `Friend picker filters recipient / self / blocked / archived contacts while keeping re-introducible pairs selectable` / `covered_in_repo` / `implementation-ready` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-IL-003-plan.md`
- Scope / ownership: add or tighten row-owned proof for "Friend picker filters recipient / self / blocked / archived contacts while keeping re-introducible pairs selectable" without widening product scope, then refresh the matrix row with the new direct evidence; session owns `tests only`.
- Likely code-entry files: `lib/features/introduction/presentation/screens/friend_picker_wired.dart`, `lib/features/introduction/presentation/screens/friend_picker_screen.dart`, `lib/features/contacts/domain/repositories/contact_repository.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by the new recipient/self/blocked/archived exclusion regression in `friend_picker_wired_test.dart`, the existing same-pair reintroduction picker proof in `friend_picker_wired_test.dart`, `friend_picker_test.dart`, `introduction_regression_test.dart`, and a green `./scripts/run_test_gates.sh intro` rerun on `2026-04-08`.; `test/features/introduction/presentation/screens/friend_picker_wired_test.dart`, `test/features/introduction/presentation/screens/friend_picker_test.dart`, `test/features/introduction/regression/introduction_regression_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.
- Closure update:
  accepted on `2026-04-08` after a narrow picker fix excluded the current
  identity in `lib/features/introduction/presentation/screens/friend_picker_wired.dart`,
  while the new wired regression proved recipient/self/blocked/archived
  filtering without regressing eligible same-pair reselection

### Session IL-004

- Source row / scenario / disposition / classification / plan: `IL-004` / `Single introduction send creates one shared introId, two outbound envelopes, and one local row` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-IL-004-plan.md`
- Scope / ownership: preserve the currently covered IL-004 contract for "Single introduction send creates one shared introId, two outbound envelopes, and one local row" and reopen only if new contradictory evidence appears; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/introduction/application/send_introduction_use_case.dart`, `lib/features/introduction/application/introduction_outbound_delivery.dart`, `lib/features/introduction/domain/models/introduction_payload.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `send_introduction_test.dart` and `introduction_multi_node_test.dart`.; `test/features/introduction/application/send_introduction_test.dart`, `test/features/introduction/integration/introduction_multi_node_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session IL-006

- Source row / scenario / disposition / classification / plan: `IL-006` / `v2 is preferred when an ML-KEM key exists; v1 fallback is used when the key is absent or encrypt fails` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-IL-006-plan.md`
- Scope / ownership: preserve the currently covered IL-006 contract for "v2 is preferred when an ML-KEM key exists; v1 fallback is used when the key is absent or encrypt fails" and reopen only if new contradictory evidence appears; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/introduction/application/send_introduction_use_case.dart`, `lib/features/introduction/application/accept_introduction_use_case.dart`, `lib/features/introduction/application/pass_introduction_use_case.dart`, `lib/features/introduction/application/introduction_outbound_delivery.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `send_introduction_test.dart`, `accept_introduction_test.dart`, `pass_introduction_test.dart`, and regression case 11.; `test/features/introduction/application/send_introduction_test.dart`, `test/features/introduction/application/accept_introduction_test.dart`, `test/features/introduction/application/pass_introduction_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session IL-007

- Source row / scenario / disposition / classification / plan: `IL-007` / `Online receipt creates a pending intro row, system message, and local notification` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-IL-007-plan.md`
- Scope / ownership: preserve the currently covered IL-007 contract for "Online receipt creates a pending intro row, system message, and local notification" and reopen only if new contradictory evidence appears; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/introduction/application/send_introduction_use_case.dart`, `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`, `lib/features/introduction/application/introduction_listener.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `introduction_listener_test.dart`, `introduction_multi_node_test.dart`, and `introduction_smoke_test.dart`.; `test/features/introduction/application/introduction_listener_test.dart`, `test/features/introduction/integration/introduction_multi_node_test.dart`, `test/features/introduction/integration/introduction_smoke_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session IL-008

- Source row / scenario / disposition / classification / plan: `IL-008` / `Offline recipient later receives the intro via inbox / store-and-forward` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-IL-008-plan.md`
- Scope / ownership: preserve the currently covered IL-008 contract for "Offline recipient later receives the intro via inbox / store-and-forward" and reopen only if new contradictory evidence appears; the matching three-simulator proof should come from `INTRO_E2E_SCENARIO=happy ./smoke_test_friends.sh`; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/introduction/application/send_introduction_use_case.dart`, `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`, `lib/features/introduction/application/introduction_listener.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `introduction_multi_node_test.dart` offline relay flow.; `test/features/introduction/integration/introduction_multi_node_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session IL-009

- Source row / scenario / disposition / classification / plan: `IL-009` / `Blocked introducer `send` is rejected without intro row, UI, or notification` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-IL-009-plan.md`
- Scope / ownership: preserve the currently covered IL-009 contract for "Blocked introducer `send` is rejected without intro row, UI, or notification" and reopen only if new contradictory evidence appears; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/introduction/application/send_introduction_use_case.dart`, `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`, `lib/features/introduction/application/introduction_listener.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `introduction_listener_test.dart`.; `test/features/introduction/application/introduction_listener_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session IL-010

- Source row / scenario / disposition / classification / plan: `IL-010` / `Already-connected intro is visible but non-actionable and does not inflate the pending badge` / `needs_tests_only` / `implementation-ready` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-IL-010-plan.md`
- Scope / ownership: add or tighten row-owned proof for "Already-connected intro is visible but non-actionable and does not inflate the pending badge" without widening product scope, then refresh the matrix row with the new direct evidence; the matching three-simulator proof should come from `INTRO_E2E_SCENARIO=copy ./smoke_test_friends.sh`; session owns `tests only`.
- Likely code-entry files: `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`, `lib/features/introduction/application/load_introductions_use_case.dart`, `lib/features/introduction/presentation/widgets/intro_row.dart`, `lib/features/orbit/presentation/screens/orbit_wired.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `handle_incoming_introduction_test.dart` already-connected visibility and pending-badge exclusions, `intro_row_test.dart` non-actionable `Already connected` UI coverage, `introduction_multi_node_test.dart` existing-contact convergence, and a green rerun of `./scripts/run_test_gates.sh intro` on 2026-04-08.; `test/features/introduction/application/handle_incoming_introduction_test.dart`, `test/features/introduction/integration/introduction_multi_node_test.dart`, `test/features/introduction/application/load_introductions_test.dart`, `test/features/introduction/presentation/widgets/intro_row_test.dart`, `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.
- Closure note: Accepted on `2026-04-08` after the missing `Already connected` widget proof landed in `intro_row_test.dart`; direct row suites and `./scripts/run_test_gates.sh intro` were green in the same pass.

### Session IL-011

- Source row / scenario / disposition / classification / plan: `IL-011` / `Duplicate or older same-pair `send` is ignored; newer same-pair `send` replaces stale row` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-IL-011-plan.md`
- Scope / ownership: preserve the currently covered IL-011 contract for "Duplicate or older same-pair `send` is ignored; newer same-pair `send` replaces stale row" and reopen only if new contradictory evidence appears; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/introduction/application/send_introduction_use_case.dart`, `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`, `lib/features/introduction/application/introduction_listener.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `handle_incoming_introduction_test.dart` and `introduction_smoke_test.dart`.; `test/features/introduction/application/handle_incoming_introduction_test.dart`, `test/features/introduction/integration/introduction_smoke_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session IL-012

- Source row / scenario / disposition / classification / plan: `IL-012` / `Introducer-side row reflects later accept/pass updates from both parties` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-IL-012-plan.md`
- Scope / ownership: preserve the currently covered IL-012 contract for "Introducer-side row reflects later accept/pass updates from both parties" and reopen only if new contradictory evidence appears; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/introduction/application/send_introduction_use_case.dart`, `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`, `lib/features/introduction/application/introduction_listener.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `introduction_multi_node_test.dart`; the inventory note explicitly says the seam exists even if the prose summary undercounts it.; `test/features/introduction/integration/introduction_multi_node_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session RM-001

- Source row / scenario / disposition / classification / plan: `RM-001` / `One-sided accept shows waiting / partial state and creates no contact` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-001-plan.md`
- Scope / ownership: preserve the currently covered RM-001 contract for "One-sided accept shows waiting / partial state and creates no contact" and reopen only if new contradictory evidence appears; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/introduction/application/accept_introduction_use_case.dart`, `lib/features/introduction/application/pass_introduction_use_case.dart`, `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `accept_introduction_test.dart`, `mutual_acceptance_test.dart`, `intro_row_test.dart`, and smoke coverage.; `test/features/introduction/application/accept_introduction_test.dart`, `test/features/introduction/application/mutual_acceptance_test.dart`, `test/features/introduction/presentation/widgets/intro_row_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session RM-002

- Source row / scenario / disposition / classification / plan: `RM-002` / `Accept order is irrelevant` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-002-plan.md`
- Scope / ownership: preserve the currently covered RM-002 contract for "Accept order is irrelevant" and reopen only if new contradictory evidence appears; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/introduction/application/accept_introduction_use_case.dart`, `lib/features/introduction/application/pass_introduction_use_case.dart`, `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `mutual_acceptance_test.dart` and `introduction_multi_node_test.dart`.; `test/features/introduction/application/mutual_acceptance_test.dart`, `test/features/introduction/integration/introduction_multi_node_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session RM-003

- Source row / scenario / disposition / classification / plan: `RM-003` / `A pass from either side yields terminal `passed` and no contact` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-003-plan.md`
- Scope / ownership: preserve the currently covered RM-003 contract for "A pass from either side yields terminal `passed` and no contact" and reopen only if new contradictory evidence appears; the matching three-simulator proof should come from `INTRO_E2E_SCENARIO=pass ./smoke_test_friends.sh`; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/introduction/application/accept_introduction_use_case.dart`, `lib/features/introduction/application/pass_introduction_use_case.dart`, `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `pass_introduction_test.dart`, `mutual_acceptance_test.dart`, and `introduction_smoke_test.dart`.; `test/features/introduction/application/pass_introduction_test.dart`, `test/features/introduction/application/mutual_acceptance_test.dart`, `test/features/introduction/integration/introduction_smoke_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session RM-004

- Source row / scenario / disposition / classification / plan: `RM-004` / `One side accepts and the other later passes; overall remains `passed`` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-004-plan.md`
- Scope / ownership: preserve the currently covered RM-004 contract for "One side accepts and the other later passes; overall remains `passed`" and reopen only if new contradictory evidence appears; the matching three-simulator proof should come from `INTRO_E2E_SCENARIO=pass ./smoke_test_friends.sh`; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/introduction/application/accept_introduction_use_case.dart`, `lib/features/introduction/application/pass_introduction_use_case.dart`, `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `mutual_acceptance_test.dart` and `introduction_multi_node_test.dart`.; `test/features/introduction/application/mutual_acceptance_test.dart`, `test/features/introduction/integration/introduction_multi_node_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session RM-005

- Source row / scenario / disposition / classification / plan: `RM-005` / `Accept after a terminal pass never reopens the intro` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-005-plan.md`
- Scope / ownership: preserve the currently covered RM-005 contract for "Accept after a terminal pass never reopens the intro" and reopen only if new contradictory evidence appears; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/introduction/application/accept_introduction_use_case.dart`, `lib/features/introduction/application/pass_introduction_use_case.dart`, `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `mutual_acceptance_test.dart` (`accept after pass still results in passed`).; `test/features/introduction/application/mutual_acceptance_test.dart`, `accept after pass still results in passed`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session RM-006

- Source row / scenario / disposition / classification / plan: `RM-006` / `Accept/pass is sent to both the introducer and the stranger, using intro-carried keys first and contact fallback second` / `needs_tests_only` / `implementation-ready` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-006-plan.md`
- Scope / ownership: add or tighten row-owned proof for "Accept/pass is sent to both the introducer and the stranger, using intro-carried keys first and contact fallback second" without widening product scope, then refresh the matrix row with the new direct evidence; session owns `tests only`.
- Likely code-entry files: `lib/features/introduction/application/accept_introduction_use_case.dart`, `lib/features/introduction/application/pass_introduction_use_case.dart`, `lib/features/introduction/application/introduction_outbound_delivery.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `accept_introduction_test.dart` and `pass_introduction_test.dart` both-recipient delivery, intro-carried stranger-key, and stranger contact-fallback ML-KEM coverage, plus a green rerun of `./scripts/run_test_gates.sh intro` on 2026-04-08.; `test/features/introduction/application/accept_introduction_test.dart`, `test/features/introduction/application/pass_introduction_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.
- Closure note: Accepted on `2026-04-08` after row-owned accept/pass regressions proved stranger contact-key fallback when the intro record omits the ML-KEM key; direct response suites and `./scripts/run_test_gates.sh intro` were green in the same pass.

### Session RM-007

- Source row / scenario / disposition / classification / plan: `RM-007` / `Duplicate accept/pass deliveries are idempotent` / `needs_tests_only` / `implementation-ready` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-007-plan.md`
- Scope / ownership: add or tighten row-owned proof for "Duplicate accept/pass deliveries are idempotent" without widening product scope, then refresh the matrix row with the new direct evidence; session owns `tests only`.
- Likely code-entry files: `lib/features/introduction/application/accept_introduction_use_case.dart`, `lib/features/introduction/application/pass_introduction_use_case.dart`, `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `introduction_regression_test.dart` duplicate accept and duplicate pass idempotency regressions, plus a green rerun of `./scripts/run_test_gates.sh intro` on 2026-04-08.; `test/features/introduction/regression/introduction_regression_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.
- Closure note: Accepted on `2026-04-08` after a dedicated duplicate-pass regression joined the existing duplicate-accept coverage in `introduction_regression_test.dart`; the row suite and `./scripts/run_test_gates.sh intro` were green in the same pass.

### Session RM-008

- Source row / scenario / disposition / classification / plan: `RM-008` / `Unknown responderId is rejected with no mutation` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-008-plan.md`
- Scope / ownership: preserve the currently covered RM-008 contract for "Unknown responderId is rejected with no mutation" and reopen only if new contradictory evidence appears; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/introduction/application/accept_introduction_use_case.dart`, `lib/features/introduction/application/pass_introduction_use_case.dart`, `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by regression case 2.; `./scripts/run_test_gates.sh intro`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session RM-009

- Source row / scenario / disposition / classification / plan: `RM-009` / `Non-party caller cannot invoke accept/pass on an intro they do not belong to` / `needs_code_and_tests` / `implementation-ready` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-009-plan.md`
- Scope / ownership: close the current repo gap for "Non-party caller cannot invoke accept/pass on an intro they do not belong to" in the owning intro seam, then land row-owned regressions that prove the fix end to end; session owns `code changes and tests`.
- Likely code-entry files: `lib/features/introduction/application/accept_introduction_use_case.dart`, `lib/features/introduction/application/pass_introduction_use_case.dart`, `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by explicit non-party caller guards in `accept_introduction_use_case.dart` and `pass_introduction_use_case.dart`, direct no-mutation/no-outbound-delivery regressions in `accept_introduction_test.dart` and `pass_introduction_test.dart`, and a green rerun of `./scripts/run_test_gates.sh intro` on `2026-04-08`.; `test/features/introduction/application/accept_introduction_test.dart`, `test/features/introduction/application/pass_introduction_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`, `Test-Flight-Improv/Intro-Feature/test-inventory.md`.
- Closure note: Accepted on `2026-04-08` after the response use cases gained explicit non-party caller guards and direct accept/pass regressions proved no state mutation or outbound delivery for unauthorized callers; the row suites and `./scripts/run_test_gates.sh intro` were green in the same pass.

### Session RM-010

- Source row / scenario / disposition / classification / plan: `RM-010` / `Accept/pass from a now-blocked stranger still completes the handshake path` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-010-plan.md`
- Scope / ownership: preserve the currently covered RM-010 contract for "Accept/pass from a now-blocked stranger still completes the handshake path" and reopen only if new contradictory evidence appears; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/introduction/application/accept_introduction_use_case.dart`, `lib/features/introduction/application/pass_introduction_use_case.dart`, `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `introduction_listener_test.dart` and regression cases 14a/14b.; `test/features/introduction/application/introduction_listener_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session RM-011

- Source row / scenario / disposition / classification / plan: `RM-011` / `The second accept creates exactly one contact on each side with correct keys and introducedBy metadata` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-011-plan.md`
- Scope / ownership: preserve the currently covered RM-011 contract for "The second accept creates exactly one contact on each side with correct keys and introducedBy metadata" and reopen only if new contradictory evidence appears; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/introduction/application/accept_introduction_use_case.dart`, `lib/features/introduction/application/pass_introduction_use_case.dart`, `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `create_connection_on_mutual_acceptance_test.dart`, `introduction_multi_node_test.dart`, and regression cases 7a/7b.; `test/features/introduction/application/create_connection_on_mutual_acceptance_test.dart`, `test/features/introduction/integration/introduction_multi_node_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session RM-012

- Source row / scenario / disposition / classification / plan: `RM-012` / `Introducer converges to `mutualAccepted` without duplicate B/C contacts` / `needs_tests_only` / `implementation-ready` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-012-plan.md`
- Scope / ownership: add or tighten row-owned proof for "Introducer converges to `mutualAccepted` without duplicate B/C contacts" without widening product scope, then refresh the matrix row with the new direct evidence; session owns `tests only`.
- Likely code-entry files: `lib/features/introduction/application/accept_introduction_use_case.dart`, `lib/features/introduction/application/pass_introduction_use_case.dart`, `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `introduction_multi_node_test.dart` introducer-side `mutualAccepted` convergence plus one-contact-each assertions for B and C, together with the existing introducer-local row persistence proof and a green rerun of `./scripts/run_test_gates.sh intro` on `2026-04-08`.; `test/features/introduction/integration/introduction_multi_node_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.
- Closure note: Accepted on `2026-04-08` after a dedicated multi-node regression proved the introducer's row converges to `mutualAccepted` while keeping exactly one contact for B and one for C; the direct suite and `./scripts/run_test_gates.sh intro` were green in the same pass.

### Session RM-014

- Source row / scenario / disposition / classification / plan: `RM-014` / `First encrypted chat works immediately after mutual acceptance` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-014-plan.md`
- Scope / ownership: preserve the currently covered RM-014 contract for "First encrypted chat works immediately after mutual acceptance" and reopen only if new contradictory evidence appears; the matching three-simulator proof should come from `INTRO_E2E_SCENARIO=happy ./smoke_test_friends.sh`; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/introduction/application/accept_introduction_use_case.dart`, `lib/features/introduction/application/pass_introduction_use_case.dart`, `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `introduction_multi_node_test.dart` offline-relay-to-first-chat scenario.; `test/features/introduction/integration/introduction_multi_node_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session DR-001

- Source row / scenario / disposition / classification / plan: `DR-001` / `Acked direct send clears the staged outbox row` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-001-plan.md`
- Scope / ownership: preserve the currently covered DR-001 contract for "Acked direct send clears the staged outbox row" and reopen only if new contradictory evidence appears; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/introduction/application/introduction_outbound_delivery.dart`, `lib/features/introduction/application/send_introduction_use_case.dart`, `lib/core/lifecycle/handle_app_resumed.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `introduction_outbound_delivery_test.dart`.; `test/features/introduction/application/introduction_outbound_delivery_test.dart`; `./scripts/run_test_gates.sh intro`, `./scripts/run_test_gates.sh transport`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session DR-002

- Source row / scenario / disposition / classification / plan: `DR-002` / `Unacked live send stays retryable, and resume retrier replays via inbox-only semantics` / `needs_tests_only` / `implementation-ready` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-002-plan.md`
- Scope / ownership: add or tighten row-owned proof for "Unacked live send stays retryable, and resume retrier replays via inbox-only semantics" without widening product scope, then refresh the matrix row with the new direct evidence; session owns `tests only`.
- Likely code-entry files: `lib/features/introduction/application/introduction_outbound_delivery.dart`, `lib/core/lifecycle/handle_app_resumed.dart`, `lib/core/services/pending_message_retrier.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `introduction_outbound_delivery_test.dart` unacked sent-row retention, direct inbox replay, and `handleAppResumed` inbox-only retry coverage, plus a green rerun of `./scripts/run_test_gates.sh intro` on `2026-04-08`.; `test/features/introduction/application/introduction_outbound_delivery_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.
- Closure note: Accepted on `2026-04-08` after a row-owned outbound-delivery regression proved app resume invokes the intro retrier and that the retrier replays sent intro rows through inbox-only semantics without re-running the live send path; the direct suite and `./scripts/run_test_gates.sh intro` were green in the same pass.

### Session DR-005

- Source row / scenario / disposition / classification / plan: `DR-005` / `Partial fan-out is safe: B receives now, C later, and the pair still converges` / `needs_repo_evidence` / `evidence-gated` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-005-plan.md`
- Scope / ownership: land and preserve row-owned proof for "Partial fan-out is safe: B receives now, C later, and the pair still converges" on the same `introductionId`, using the dedicated delayed-fanout host regression plus the matching `INTRO_E2E_SCENARIO=partial ./smoke_test_friends.sh` transport proof; session owns `tests and proof`.
- Likely code-entry files: `test/features/introduction/integration/introduction_multi_node_test.dart`, `lib/core/debug/intro_e2e_runner.dart`, `smoke_test_friends.sh`.
- Current repo evidence / likely direct tests / likely named gates: Covered by the delayed same-intro recovery regression in `introduction_multi_node_test.dart`, the new `partial` three-simulator scenario in `smoke_test_friends.sh` backed by `intro_e2e_runner.dart`, `./scripts/run_test_gates.sh intro`, and `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport`.; `test/features/introduction/integration/introduction_multi_node_test.dart`, `lib/core/debug/intro_e2e_runner.dart`, `smoke_test_friends.sh`; `./scripts/run_test_gates.sh intro`, `./scripts/run_test_gates.sh transport`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.
- Closure note: Accepted on `2026-04-08` after the row-owned delayed same-intro recovery regression, `INTRO_E2E_SCENARIO=partial ./smoke_test_friends.sh`, `./scripts/run_test_gates.sh intro`, and `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport` were all green in the same pass.

### Session DR-006

- Source row / scenario / disposition / classification / plan: `DR-006` / `Responses arriving before the `send` row are durably staged and replayed correctly` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-006-plan.md`
- Scope / ownership: preserve the currently covered DR-006 contract for "Responses arriving before the `send` row are durably staged and replayed correctly" and reopen only if new contradictory evidence appears; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/introduction/application/introduction_outbound_delivery.dart`, `lib/features/introduction/application/send_introduction_use_case.dart`, `lib/core/lifecycle/handle_app_resumed.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `handle_incoming_introduction_test.dart`, `introduction_listener_test.dart`, and `introduction_multi_node_test.dart`.; `test/features/introduction/application/handle_incoming_introduction_test.dart`, `test/features/introduction/application/introduction_listener_test.dart`, `test/features/introduction/integration/introduction_multi_node_test.dart`; `./scripts/run_test_gates.sh intro`, `./scripts/run_test_gates.sh transport`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session DR-007

- Source row / scenario / disposition / classification / plan: `DR-007` / `Duplicate network deliveries and stale queued envelopes never reopen a terminal intro` / `needs_tests_only` / `implementation-ready` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-007-plan.md`
- Scope / ownership: add or tighten row-owned proof for "Duplicate network deliveries and stale queued envelopes never reopen a terminal intro" without widening product scope, then refresh the matrix row with the new direct evidence; session owns `tests only`.
- Likely code-entry files: `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`, `test/features/introduction/application/handle_incoming_introduction_test.dart`, `test/features/introduction/application/mutual_acceptance_test.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `handle_incoming_introduction_test.dart` duplicate-send-does-not-reopen and older-same-pair-stale-send terminal-pass regressions, existing `mutual_acceptance_test.dart` `accept after pass still results in passed`, and a green rerun of `./scripts/run_test_gates.sh intro` on `2026-04-08`.; `test/features/introduction/application/handle_incoming_introduction_test.dart`, `test/features/introduction/application/mutual_acceptance_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.
- Closure note: Accepted on `2026-04-08` after row-owned stale/duplicate terminal-send regressions landed in `handle_incoming_introduction_test.dart`, the existing terminal-pass guard in `mutual_acceptance_test.dart` stayed green, and `./scripts/run_test_gates.sh intro` passed in the same session.

### Session DR-009

- Source row / scenario / disposition / classification / plan: `DR-009` / `Sender crash after remote delivery but before local intro persistence heals on restart` / `needs_code_and_tests` / `implementation-ready` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-009-plan.md`
- Scope / ownership: close the current repo gap for "Sender crash after remote delivery but before local intro persistence heals on restart" in the owning intro seam, then land row-owned regressions that prove the fix end to end; the matching three-simulator proof should come from `INTRO_E2E_SCENARIO=repair ./smoke_test_friends.sh`; session owns `code changes and tests`.
- Likely code-entry files: `lib/features/introduction/application/send_introduction_use_case.dart`, `test/features/introduction/application/send_introduction_test.dart`, `lib/core/debug/intro_e2e_runner.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by the local-first sender persistence change in `send_introduction_use_case.dart`, the crash-window regression `persists the sender local intro row before a later delivery-stage crash` in `send_introduction_test.dart`, `INTRO_E2E_SCENARIO=repair ./smoke_test_friends.sh`, `./scripts/run_test_gates.sh intro`, and `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport` on `2026-04-09`.; `test/features/introduction/application/send_introduction_test.dart`, `test/features/introduction/application/introduction_outbound_delivery_test.dart`; `./scripts/run_test_gates.sh intro`, `./scripts/run_test_gates.sh transport`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`, `Test-Flight-Improv/Intro-Feature/_Intro-reliability-gap-audit.md`.
- Closure note: Accepted on `2026-04-09` after sender-local intro persistence moved ahead of outbound delivery staging, a row-owned crash-window regression proved the sender still keeps the local intro row after one remote delivery and a later staged-delivery failure, and the `repair` scenario plus intro and transport gates all passed in the same session.

### Session DR-010

- Source row / scenario / disposition / classification / plan: `DR-010` / `Partition healing after divergent delivery or divergent accepts converges across A/B/C` / `needs_repo_evidence` / `evidence-gated` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-010-plan.md`
- Scope / ownership: land and preserve row-owned proof for "Partition healing after divergent delivery or divergent accepts converges across A/B/C" without widening into later split-brain or offline-first-chat work; the matching three-simulator proof should come from `INTRO_E2E_SCENARIO=partition ./smoke_test_friends.sh`; session owns `tests and proof`.
- Likely code-entry files: `test/features/introduction/integration/introduction_multi_node_test.dart`, `lib/core/debug/intro_e2e_runner.dart`, `smoke_test_friends.sh`.
- Current repo evidence / likely direct tests / likely named gates: Covered by the partition-heal regression `introducer heals after partitioned accept deliveries and converges with B and C` in `introduction_multi_node_test.dart`, the dedicated `partition` three-simulator scenario in `smoke_test_friends.sh`, and a green rerun of `./scripts/run_test_gates.sh intro` on `2026-04-09`.; `test/features/introduction/integration/introduction_multi_node_test.dart`, `smoke_test_friends.sh`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.
- Closure note: Accepted on `2026-04-09` after a row-owned partition-heal regression proved B and C can converge while A is partitioned away and that A later heals back to the same intro truth without duplicate B/C contacts; `INTRO_E2E_SCENARIO=partition ./smoke_test_friends.sh` and `./scripts/run_test_gates.sh intro` were green in the same session.

### Session DR-011

- Source row / scenario / disposition / classification / plan: `DR-011` / `Offline relay intro delivery converges to mutual acceptance and first encrypted chat` / `needs_repo_evidence` / `evidence-gated` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-011-plan.md`
- Scope / ownership: land and preserve row-owned proof for "Offline relay intro delivery converges to mutual acceptance and first encrypted chat" without widening into unrelated conversation smoke scope; the matching three-simulator proof should come from `INTRO_E2E_SCENARIO=offline-chat ./smoke_test_friends.sh`; session owns `tests and proof`.
- Likely code-entry files: `test/features/introduction/integration/introduction_multi_node_test.dart`, `lib/core/debug/intro_e2e_runner.dart`, `smoke_test_friends.sh`.
- Current repo evidence / likely direct tests / likely named gates: Covered by the existing host regression `offline relay intro delivery converges to mutual acceptance and first encrypted chat` in `introduction_multi_node_test.dart`, the dedicated `offline-chat` three-simulator scenario in `smoke_test_friends.sh` backed by `intro_e2e_runner.dart`, and a green rerun of `./scripts/run_test_gates.sh intro` on `2026-04-09`.; `test/features/introduction/integration/introduction_multi_node_test.dart`, `lib/core/debug/intro_e2e_runner.dart`, `smoke_test_friends.sh`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.
- Closure note: Accepted on `2026-04-09` after the existing host regression still proved offline inbox delivery, later mutual acceptance, and the first encrypted post-intro chat, while the new `offline-chat` three-simulator scenario reproduced the same row on real devices and `./scripts/run_test_gates.sh intro` stayed green in the same session.

### Session DR-012

- Source row / scenario / disposition / classification / plan: `DR-012` / `Accept/pass notifications fall back to inbox while peers are unreachable and still converge after drain` / `needs_repo_evidence` / `evidence-gated` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-012-plan.md`
- Scope / ownership: land and preserve row-owned proof for "Accept/pass notifications fall back to inbox while peers are unreachable and still converge after drain" without widening into unrelated transport recovery rows; session owns `tests and proof`.
- Likely code-entry files: `test/features/introduction/integration/introduction_multi_node_test.dart`, `smoke_test_friends.sh`, `lib/features/introduction/application/pass_introduction_use_case.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by the existing host regression `accept notifications fall back to inbox while peers are unreachable and converge after drain`, the new host regression `pass notifications fall back to inbox while peers are unreachable and converge after drain`, the dedicated `pass-fallback` three-simulator scenario in `smoke_test_friends.sh`, and a green rerun of `./scripts/run_test_gates.sh intro` on `2026-04-09`.; `test/features/introduction/integration/introduction_multi_node_test.dart`, `smoke_test_friends.sh`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.
- Closure note: Accepted on `2026-04-09` after the repo gained a symmetric pass-fallback inbox regression, the dedicated `pass-fallback` three-simulator scenario proved both offline targets later drain to the same terminal `passed` truth without creating contacts, and `./scripts/run_test_gates.sh intro` stayed green in the same session.

### Session DR-013

- Source row / scenario / disposition / classification / plan: `DR-013` / `Re-introducing the same pair repairs a missed side and ignores stale older delivery` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-013-plan.md`
- Scope / ownership: preserve the currently covered DR-013 contract for "Re-introducing the same pair repairs a missed side and ignores stale older delivery" and reopen only if new contradictory evidence appears; the matching three-simulator proof should come from `INTRO_E2E_SCENARIO=refresh ./smoke_test_friends.sh`; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/introduction/application/introduction_outbound_delivery.dart`, `lib/features/introduction/application/send_introduction_use_case.dart`, `lib/core/lifecycle/handle_app_resumed.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `introduction_multi_node_test.dart` and `introduction_smoke_test.dart`.; `test/features/introduction/integration/introduction_multi_node_test.dart`, `test/features/introduction/integration/introduction_smoke_test.dart`; `./scripts/run_test_gates.sh intro`, `./scripts/run_test_gates.sh transport`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session DR-014

- Source row / scenario / disposition / classification / plan: `DR-014` / `Split-brain mutual acceptance heals after restart/reconnect` / `needs_repo_evidence` / `evidence-gated` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-014-plan.md`
- Scope / ownership: keep the current intro contract honest and add the missing repo-owned transport, recovery, or top-level proof for "Split-brain mutual acceptance heals after restart/reconnect" instead of relying only on in-memory intro coverage; the matching three-simulator proof should come from `INTRO_E2E_SCENARIO=split-brain ./smoke_test_friends.sh`; session owns `evidence only`.
- Likely code-entry files: `lib/features/introduction/application/expire_old_introductions_use_case.dart`, `lib/features/introduction/application/resolve_unknown_inbox_sender_use_case.dart`, `lib/core/debug/intro_e2e_runner.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered on 2026-04-09 by `test/features/introduction/integration/introduction_multi_node_test.dart` split-brain recovery regression, `INTRO_E2E_SCENARIO=split-brain ./smoke_test_friends.sh`, and a green rerun of `./scripts/run_test_gates.sh intro`; `test/features/introduction/integration/introduction_multi_node_test.dart`, `smoke_test_friends.sh`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`, `Test-Flight-Improv/Intro-Feature/_Intro-reliability-gap-audit.md`.

### Session SC-001

- Source row / scenario / disposition / classification / plan: `SC-001` / `Replay of the same envelope / messageId / introductionId never duplicates rows, contacts, system messages, or notifications` / `needs_tests_only` / `implementation-ready` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-SC-001-plan.md`
- Scope / ownership: add or tighten row-owned proof for "Replay of the same envelope / messageId / introductionId never duplicates rows, contacts, system messages, or notifications" without widening product scope, then refresh the matrix row with the new direct evidence; session owns `tests only`.
- Likely code-entry files: `lib/features/introduction/application/introduction_listener.dart`, `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`, `lib/features/introduction/domain/models/introduction_payload.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered on 2026-04-09 by `test/features/introduction/application/introduction_listener_test.dart` duplicate-send and duplicate-accept replay regressions, `test/features/introduction/integration/introduction_multi_node_test.dart` late-delivery replay convergence, `test/features/introduction/regression/introduction_regression_test.dart` blocked duplicate-accept idempotency, and a green rerun of `./scripts/run_test_gates.sh intro`.; `test/features/introduction/application/introduction_listener_test.dart`, `test/features/introduction/integration/introduction_multi_node_test.dart`, `test/features/introduction/regression/introduction_regression_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session SC-002

- Source row / scenario / disposition / classification / plan: `SC-002` / `Tampered ciphertext or wrong secret key is rejected with no state mutation` / `needs_tests_only` / `implementation-ready` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-SC-002-plan.md`
- Scope / ownership: add or tighten row-owned proof for "Tampered ciphertext or wrong secret key is rejected with no state mutation" without widening product scope, then refresh the matrix row with the new direct evidence; session owns `tests only`.
- Likely code-entry files: `lib/features/introduction/application/introduction_listener.dart`, `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`, `lib/features/introduction/domain/models/introduction_payload.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered on 2026-04-09 by `test/features/introduction/application/introduction_listener_test.dart` wrong-key and tampered-v2 rejection regressions and a green rerun of `./scripts/run_test_gates.sh intro`.; `test/features/introduction/application/introduction_listener_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session SC-003

- Source row / scenario / disposition / classification / plan: `SC-003` / `ML-KEM key mismatch between intro record and current contact state is escalated or rejected, not silently accepted` / `needs_code_and_tests` / `implementation-ready` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-SC-003-plan.md`
- Scope / ownership: close the current repo gap for "ML-KEM key mismatch between intro record and current contact state is escalated or rejected, not silently accepted" in the owning intro seam, then land row-owned regressions that prove the fix end to end; session owns `code changes and tests`.
- Likely code-entry files: `lib/features/introduction/application/accept_introduction_use_case.dart`, `lib/features/introduction/application/pass_introduction_use_case.dart`, `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by the new accept/pass mismatch rejection regressions in `accept_introduction_test.dart` and `pass_introduction_test.dart`, plus a green rerun of `./scripts/run_test_gates.sh intro` on `2026-04-09`.; `test/features/introduction/application/accept_introduction_test.dart`, `test/features/introduction/application/pass_introduction_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.
- Closure note: Accepted on `2026-04-09` after `accept_introduction_use_case.dart` and `pass_introduction_use_case.dart` began rejecting intro/contact stranger ML-KEM mismatches before mutation or outbound delivery; the new direct regressions and a green `./scripts/run_test_gates.sh intro` rerun closed the row.

### Session SC-005

- Source row / scenario / disposition / classification / plan: `SC-005` / `Blocked-sender rule applies only to `send`; accept/pass always pass through` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-SC-005-plan.md`
- Scope / ownership: preserve the currently covered SC-005 contract for "Blocked-sender rule applies only to `send`; accept/pass always pass through" and reopen only if new contradictory evidence appears; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/introduction/application/introduction_listener.dart`, `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`, `lib/features/introduction/domain/models/introduction_payload.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `introduction_listener_test.dart` and regression cases 14a/14b.; `test/features/introduction/application/introduction_listener_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session SC-006

- Source row / scenario / disposition / classification / plan: `SC-006` / `Key direction awareness remains correct when creating contacts` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-SC-006-plan.md`
- Scope / ownership: preserve the currently covered SC-006 contract for "Key direction awareness remains correct when creating contacts" and reopen only if new contradictory evidence appears; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/introduction/application/introduction_listener.dart`, `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`, `lib/features/introduction/domain/models/introduction_payload.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `create_connection_on_mutual_acceptance_test.dart` and regression cases 7a/7b.; `test/features/introduction/application/create_connection_on_mutual_acceptance_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session SC-007

- Source row / scenario / disposition / classification / plan: `SC-007` / ``alreadyConnected` is terminal and visible, but not counted as pending` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-SC-007-plan.md`
- Scope / ownership: preserve the currently covered SC-007 contract for "`alreadyConnected` is terminal and visible, but not counted as pending" and reopen only if new contradictory evidence appears; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/introduction/application/introduction_listener.dart`, `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`, `lib/features/introduction/domain/models/introduction_payload.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `handle_incoming_introduction_test.dart`, `load_introductions` coverage, and regression case 3.; `test/features/introduction/application/handle_incoming_introduction_test.dart`, `load_introductions`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session SC-008

- Source row / scenario / disposition / classification / plan: `SC-008` / ``passed`, `expired`, and `alreadyConnected` never regress to pending because of stale delivery` / `needs_tests_only` / `implementation-ready` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-SC-008-plan.md`
- Scope / ownership: add or tighten row-owned proof for "`passed`, `expired`, and `alreadyConnected` never regress to pending because of stale delivery" without widening product scope, then refresh the matrix row with the new direct evidence; session owns `tests only`.
- Likely code-entry files: `lib/features/introduction/application/introduction_listener.dart`, `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`, `lib/features/introduction/domain/models/introduction_payload.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by the stale-send terminal-state regressions in `handle_incoming_introduction_test.dart` for `passed`, `expired`, and `alreadyConnected`, plus a green rerun of `./scripts/run_test_gates.sh intro` on `2026-04-09`.; `test/features/introduction/application/handle_incoming_introduction_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.
- Closure note: Accepted on `2026-04-09` after row-owned stale-send regressions proved that `passed`, `expired`, and `alreadyConnected` intro rows are not replaced by older pending sends; the direct handle-incoming suite and a green `./scripts/run_test_gates.sh intro` rerun closed the row.

### Session SC-009

- Source row / scenario / disposition / classification / plan: `SC-009` / `Same-pair dedupe semantics are stable across same introducer and different introducer cases` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-SC-009-plan.md`
- Scope / ownership: preserve the currently covered SC-009 contract for "Same-pair dedupe semantics are stable across same introducer and different introducer cases" and reopen only if new contradictory evidence appears; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/introduction/application/introduction_listener.dart`, `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`, `lib/features/introduction/domain/models/introduction_payload.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `handle_incoming_introduction_test.dart`, `introduction_smoke_test.dart`, and `introduction_multi_node_test.dart`.; `test/features/introduction/application/handle_incoming_introduction_test.dart`, `test/features/introduction/integration/introduction_smoke_test.dart`, `test/features/introduction/integration/introduction_multi_node_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session SC-010

- Source row / scenario / disposition / classification / plan: `SC-010` / `State isolation holds across multiple intro chains and multiple `introductionId` values` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-SC-010-plan.md`
- Scope / ownership: preserve the currently covered SC-010 contract for "State isolation holds across multiple intro chains and multiple `introductionId` values" and reopen only if new contradictory evidence appears; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/introduction/application/introduction_listener.dart`, `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`, `lib/features/introduction/domain/models/introduction_payload.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered logically by `mutual_acceptance_test.dart` and multi-node chain/circular flows.; `test/features/introduction/application/mutual_acceptance_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session SC-011

- Source row / scenario / disposition / classification / plan: `SC-011` / `Pending badge counts only truly pending intros` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-SC-011-plan.md`
- Scope / ownership: preserve the currently covered SC-011 contract for "Pending badge counts only truly pending intros" and reopen only if new contradictory evidence appears; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/introduction/application/introduction_listener.dart`, `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`, `lib/features/introduction/domain/models/introduction_payload.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `handle_incoming_introduction_test.dart`, `orbit_intros_wiring_test.dart`, and regression case 3.; `test/features/introduction/application/handle_incoming_introduction_test.dart`, `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session UX-002

- Source row / scenario / disposition / classification / plan: `UX-002` / `IntroRow copy and actions are exact for pending, waiting, passed, alreadyConnected, and mutualAccepted states` / `needs_tests_only` / `implementation-ready` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-UX-002-plan.md`
- Scope / ownership: add or tighten row-owned proof for "IntroRow copy and actions are exact for pending, waiting, passed, alreadyConnected, and mutualAccepted states" without widening product scope, then refresh the matrix row with the new direct evidence; session owns `tests only`.
- Likely code-entry files: `lib/features/introduction/presentation/widgets/intro_row.dart`, `lib/features/introduction/presentation/widgets/intros_tab.dart`, `lib/features/orbit/presentation/screens/orbit_screen.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `intro_row_test.dart` pending/waiting/passed/alreadyConnected state coverage and the new exact `Message` CTA regression for mutual acceptance, plus a green rerun of `./scripts/run_test_gates.sh intro` on `2026-04-09`.; `test/features/introduction/presentation/widgets/intro_row_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.
- Closure note: Accepted on `2026-04-09` after the row sanity check confirmed `Already connected` copy was already pinned in `intro_row_test.dart`; the only remaining gap was the exact mutual-accept `Message` CTA, which is now covered by a direct widget regression and a green `./scripts/run_test_gates.sh intro` rerun.

### Session IL-002

- Source row / scenario / disposition / classification / plan: `IL-002` / `Banner dismissal persists, but overflow re-entry still works` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-IL-002-plan.md`
- Scope / ownership: preserve the currently covered IL-002 contract for "Banner dismissal persists, but overflow re-entry still works" and reopen only if new contradictory evidence appears; the matching three-simulator proof should come from `INTRO_E2E_SCENARIO=copy ./smoke_test_friends.sh`; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/introduction/application/check_intro_banner_use_case.dart`, `lib/features/conversation/presentation/screens/conversation_wired.dart`, `lib/features/introduction/presentation/widgets/intro_banner.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `introduction_smoke_test.dart`, `intro_wiring_smoke_test.dart`, and `conversation_overflow_intro_test.dart`.; `test/features/introduction/integration/introduction_smoke_test.dart`, `test/features/introduction/integration/intro_wiring_smoke_test.dart`, `test/features/conversation/presentation/screens/conversation_overflow_intro_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session IL-005

- Source row / scenario / disposition / classification / plan: `IL-005` / `Batch send keeps a concurrency cap of 10, stable ordering, and truthful progress` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-IL-005-plan.md`
- Scope / ownership: preserve the currently covered IL-005 contract for "Batch send keeps a concurrency cap of 10, stable ordering, and truthful progress" and reopen only if new contradictory evidence appears; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/introduction/application/send_introduction_use_case.dart`, `lib/features/introduction/application/introduction_outbound_delivery.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `send_introduction_test.dart`.; `test/features/introduction/application/send_introduction_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session IL-013

- Source row / scenario / disposition / classification / plan: `IL-013` / `Intro expires after 30 days, and a fresh re-introduction after expiry starts a new valid journey` / `needs_tests_only` / `implementation-ready` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-IL-013-plan.md`
- Scope / ownership: add or tighten row-owned proof for "Intro expires after 30 days, and a fresh re-introduction after expiry starts a new valid journey" without widening product scope, then refresh the matrix row with the new direct evidence; the matching three-simulator proof should come from `INTRO_E2E_SCENARIO=refresh ./smoke_test_friends.sh`; session owns `tests only`.
- Likely code-entry files: `lib/features/introduction/application/expire_old_introductions_use_case.dart`, `lib/features/introduction/application/send_introduction_use_case.dart`, `lib/features/introduction/domain/models/introduction_model.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by the expired-refresh regressions in `send_introduction_test.dart` and `introduction_smoke_test.dart`, plus a green rerun of `./scripts/run_test_gates.sh intro` on `2026-04-09`.; `test/features/introduction/application/send_introduction_test.dart`, `test/features/introduction/integration/introduction_smoke_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.
- Closure note: Accepted on `2026-04-09` after row-owned send and smoke regressions proved that an `expired` intro can be replaced by a fresh pending same-pair re-introduction instead of being revived or duplicated; the targeted suites and a green `./scripts/run_test_gates.sh intro` rerun closed the row.

### Session RM-013

- Source row / scenario / disposition / classification / plan: `RM-013` / `Mutual acceptance creates system message and new-connection notification; avatar retry failure does not roll back the contact` / `needs_tests_only` / `implementation-ready` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-013-plan.md`
- Scope / ownership: add or tighten row-owned proof for "Mutual acceptance creates system message and new-connection notification; avatar retry failure does not roll back the contact" without widening product scope, then refresh the matrix row with the new direct evidence; session owns `tests only`.
- Likely code-entry files: `lib/features/introduction/application/accept_introduction_use_case.dart`, `lib/features/introduction/application/pass_introduction_use_case.dart`, `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `create_connection_on_mutual_acceptance_test.dart` system-message and avatar no-rollback regressions, `introduction_listener_test.dart` local new-connection notification coverage, and a green rerun of `./scripts/run_test_gates.sh intro` on `2026-04-09`.; `test/features/introduction/application/create_connection_on_mutual_acceptance_test.dart`, `test/features/introduction/application/introduction_listener_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`, `Test-Flight-Improv/Intro-Feature/_Intro-reliability-gap-audit.md`.
- Closure note: Accepted on `2026-04-09` after the new `create_connection_on_mutual_acceptance_test.dart` regression proved that the avatar retry path can fail without removing the created contact or system message; existing notification proof and a green `./scripts/run_test_gates.sh intro` rerun completed the row.

### Session RM-015

- Source row / scenario / disposition / classification / plan: `RM-015` / ``resolveUnknownInboxSender` repairs a missing contact when intro state proves the contact should exist` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-015-plan.md`
- Scope / ownership: preserve the currently covered RM-015 contract for "`resolveUnknownInboxSender` repairs a missing contact when intro state proves the contact should exist" and reopen only if new contradictory evidence appears; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/introduction/application/resolve_unknown_inbox_sender_use_case.dart`, `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`, `lib/main.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `resolve_unknown_inbox_sender_use_case_test.dart`.; `test/features/introduction/application/resolve_unknown_inbox_sender_use_case_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session RM-016

- Source row / scenario / disposition / classification / plan: `RM-016` / ``expireOldIntroductions` heals stale rows to mutualAccepted/passed/expired and reruns missed side effects` / `needs_tests_only` / `implementation-ready` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-RM-016-plan.md`
- Scope / ownership: add or tighten row-owned proof for "`expireOldIntroductions` heals stale rows to mutualAccepted/passed/expired and reruns missed side effects" without widening product scope, then refresh the matrix row with the new direct evidence; session owns `tests only`.
- Likely code-entry files: `lib/features/introduction/application/expire_old_introductions_use_case.dart`, `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`, `lib/features/introduction/application/resolve_unknown_inbox_sender_use_case.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by the expanded `expire_old_introductions_use_case_test.dart` matrix for mutualAccepted/passed/expired healing and alreadyConnected no-op behavior, plus a green rerun of `./scripts/run_test_gates.sh intro` on `2026-04-09`.; `test/features/introduction/application/expire_old_introductions_use_case_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`, `Test-Flight-Improv/Intro-Feature/_Intro-reliability-gap-audit.md`.
- Closure note: Accepted on `2026-04-09` after `expire_old_introductions_use_case_test.dart` grew from a narrow mutual-accept repair check into a row-owned startup-healing matrix for mutualAccepted, passed, and expired rows, with the intro gate green in the same pass.

### Session DR-003

- Source row / scenario / disposition / classification / plan: `DR-003` / `Local/direct race converges cleanly with no duplicate intro rows or duplicate delivery side effects` / `needs_repo_evidence` / `evidence-gated` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-003-plan.md`
- Scope / ownership: keep the current intro contract honest and add the missing repo-owned transport, recovery, or top-level proof for "Local/direct race converges cleanly with no duplicate intro rows or duplicate delivery side effects" instead of relying only on in-memory intro coverage; session owns `evidence only`.
- Likely code-entry files: `lib/features/introduction/application/introduction_outbound_delivery.dart`, `lib/core/services/p2p_service.dart`, `lib/core/debug/intro_e2e_runner.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by the forced local/direct race regression in `introduction_smoke_test.dart`, the duplicate-send listener dedupe regression in `introduction_listener_test.dart`, and a green rerun of `./scripts/run_test_gates.sh intro` on `2026-04-09`.; `test/features/introduction/integration/introduction_smoke_test.dart`, `test/features/introduction/application/introduction_listener_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.
- Closure note: Accepted on `2026-04-09` after a forced local/direct race in `introduction_smoke_test.dart` proved both delivery arms can fire for the same intro while the receiver still converges to one intro row and one system message; existing duplicate-send notification proof and a green `./scripts/run_test_gates.sh intro` rerun completed the row.

### Session DR-004

- Source row / scenario / disposition / classification / plan: `DR-004` / `Relay-probe fallback converges cleanly after direct paths fail` / `needs_repo_evidence` / `evidence-gated` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-004-plan.md`
- Scope / ownership: keep the current intro contract honest and add the missing repo-owned transport, recovery, or top-level proof for "Relay-probe fallback converges cleanly after direct paths fail" instead of relying only on in-memory intro coverage; session owns `evidence only`.
- Likely code-entry files: `lib/features/introduction/application/introduction_outbound_delivery.dart`, `lib/core/services/p2p_service.dart`, `lib/core/debug/intro_e2e_runner.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by the isolated relay-probe fallback regression in `introduction_outbound_delivery_test.dart` and a green rerun of `./scripts/run_test_gates.sh intro` on `2026-04-09`.; `test/features/introduction/application/introduction_outbound_delivery_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.
- Closure note: Accepted on `2026-04-09` after `introduction_outbound_delivery_test.dart` gained an isolated relay-probe regression proving the direct path can fail, `probeRelay(...)` can recover the send, and the staged outbox row still clears on success.

### Session DR-008

- Source row / scenario / disposition / classification / plan: `DR-008` / `App resume processes multiple stalled/failed rows and cleans prior delivered+inbox rows` / `needs_repo_evidence` / `evidence-gated` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-008-plan.md`
- Scope / ownership: keep the current intro contract honest and add the missing repo-owned transport, recovery, or top-level proof for "App resume processes multiple stalled/failed rows and cleans prior delivered+inbox rows" instead of relying only on in-memory intro coverage; session owns `evidence only`.
- Likely code-entry files: `lib/features/introduction/application/introduction_outbound_delivery.dart`, `lib/core/lifecycle/handle_app_resumed.dart`, `lib/core/services/pending_message_retrier.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by the multi-row retry cleanup regression in `introduction_outbound_delivery_test.dart`, the existing intro-retry ordering proof in `handle_app_resumed_upload_ordering_test.dart`, and a green rerun of `./scripts/run_test_gates.sh intro` on `2026-04-09`.; `test/features/introduction/application/introduction_outbound_delivery_test.dart`, `test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.
- Closure note: Accepted on `2026-04-09` after `introduction_outbound_delivery_test.dart` gained a multi-row retry regression proving failed, stalled, and delivered+inbox intro outbox rows are all processed correctly in one pass, with the intro gate green in the same pass.

### Session DR-015

- Source row / scenario / disposition / classification / plan: `DR-015` / `Multiple simultaneous intros stay isolated` / `needs_repo_evidence` / `evidence-gated` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-015-plan.md`
- Scope / ownership: keep the current intro contract honest and add the missing repo-owned transport, recovery, or top-level proof for "Multiple simultaneous intros stay isolated" instead of relying only on in-memory intro coverage; session owns `evidence only`.
- Likely code-entry files: `lib/features/introduction/application/send_introduction_use_case.dart`, `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`, `lib/core/debug/intro_e2e_runner.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered on 2026-04-09 by `test/features/introduction/integration/introduction_multi_node_test.dart` concurrent-chain isolation regression and a green rerun of `./scripts/run_test_gates.sh intro`; `test/features/introduction/integration/introduction_multi_node_test.dart`, `test/features/introduction/application/mutual_acceptance_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session DR-016

- Source row / scenario / disposition / classification / plan: `DR-016` / `Same pair with a different introducer reopens as alreadyConnected without duplicate contacts` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-DR-016-plan.md`
- Scope / ownership: preserve the currently covered DR-016 contract for "Same pair with a different introducer reopens as alreadyConnected without duplicate contacts" and reopen only if new contradictory evidence appears; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/introduction/application/introduction_outbound_delivery.dart`, `lib/features/introduction/application/send_introduction_use_case.dart`, `lib/core/lifecycle/handle_app_resumed.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `introduction_multi_node_test.dart`.; `test/features/introduction/integration/introduction_multi_node_test.dart`; `./scripts/run_test_gates.sh intro`, `./scripts/run_test_gates.sh transport`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session SC-004

- Source row / scenario / disposition / classification / plan: `SC-004` / ``ensureEnvelopeMessageId` patches missing `messageId` and still accepts legacy `id` envelopes` / `needs_tests_only` / `implementation-ready` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-SC-004-plan.md`
- Scope / ownership: add or tighten row-owned proof for "`ensureEnvelopeMessageId` patches missing `messageId` and still accepts legacy `id` envelopes" without widening product scope, then refresh the matrix row with the new direct evidence; session owns `tests only`.
- Likely code-entry files: `lib/features/introduction/domain/models/introduction_payload.dart`, `lib/features/introduction/application/introduction_outbound_delivery.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered on `2026-04-09` by the dedicated payload-helper regressions in `introduction_payload_test.dart`, including the new missing-`messageId` plus legacy-`id` normalization case, and a green rerun of `./scripts/run_test_gates.sh intro`.; `test/features/introduction/application/introduction_payload_test.dart`, `test/features/introduction/application/introduction_payload_extended_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.
- Closure note: Accepted on `2026-04-09` after `introduction_payload_test.dart` gained a dedicated regression proving `ensureEnvelopeMessageId(...)` adds a dedupe-safe top-level `messageId` to legacy-shaped encrypted intro envelopes without breaking their legacy top-level `id`, with the intro gate green in the same pass.

### Session UX-001

- Source row / scenario / disposition / classification / plan: `UX-001` / `Orbit intro review renders grouped intros and the correct pending count` / `needs_tests_only` / `implementation-ready` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-UX-001-plan.md`
- Scope / ownership: add or tighten row-owned proof for "Orbit intro review renders grouped intros and the correct pending count" without widening product scope, then refresh the matrix row with the new direct evidence; session owns `tests only`.
- Likely code-entry files: `lib/features/orbit/presentation/screens/orbit_screen.dart`, `lib/features/orbit/presentation/screens/orbit_wired.dart`, `lib/features/introduction/presentation/widgets/intros_tab.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered on `2026-04-09` by the OrbitScreen intro-review widget regression in `orbit_screen_archived_groups_test.dart`, the existing grouped-data wiring checks in `orbit_intros_wiring_test.dart`, and a green rerun of `./scripts/run_test_gates.sh intro`.; `test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart`, `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.
- Closure note: Accepted on `2026-04-09` after `orbit_screen_archived_groups_test.dart` gained a dedicated OrbitScreen regression proving the rendered `Intros` view keeps introducer grouping and the visible `Intros` pending count aligned on the same screen, with the intro gate green in the same pass.

### Session UX-003

- Source row / scenario / disposition / classification / plan: `UX-003` / `FriendPickerWired full flow: loading, search, selection, send, progress, and navigation callback` / `needs_tests_only` / `implementation-ready` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-UX-003-plan.md`
- Scope / ownership: add or tighten row-owned proof for "FriendPickerWired full flow: loading, search, selection, send, progress, and navigation callback" without widening product scope, then refresh the matrix row with the new direct evidence; session owns `tests only`.
- Likely code-entry files: `lib/features/introduction/presentation/screens/friend_picker_wired.dart`, `lib/features/introduction/presentation/screens/friend_picker_screen.dart`, `lib/features/introduction/application/send_introduction_use_case.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered on `2026-04-09` by the full-flow `FriendPickerWired` regression in `friend_picker_wired_test.dart`, the existing wired filtering and reintroduction checks, and a green rerun of `./scripts/run_test_gates.sh intro`.; `test/features/introduction/presentation/screens/friend_picker_wired_test.dart`, `test/features/introduction/presentation/screens/friend_picker_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.
- Closure note: Accepted on `2026-04-09` after `friend_picker_wired_test.dart` gained a full wired-flow regression proving the picker loads, filters by search, updates selection state, exposes live send progress, and returns the sent introduction list to its parent callback, with the intro gate green in the same pass.

### Session UX-005

- Source row / scenario / disposition / classification / plan: `UX-005` / `Conversation banner and overflow entry remain consistent after dismiss, introsSentAt, block/unblock, and message-count changes` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-UX-005-plan.md`
- Scope / ownership: preserve the currently covered UX-005 contract for "Conversation banner and overflow entry remain consistent after dismiss, introsSentAt, block/unblock, and message-count changes" and reopen only if new contradictory evidence appears; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/introduction/application/check_intro_banner_use_case.dart`, `lib/features/conversation/presentation/screens/conversation_wired.dart`, `lib/features/introduction/presentation/widgets/intro_banner.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by banner tests, overflow tests, dismiss tests, and intro wiring smoke.; `test/features/introduction/application/dismiss_banner_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session UX-006

- Source row / scenario / disposition / classification / plan: `UX-006` / `New-intro and mutual-accept notifications use the correct title/body content` / `needs_tests_only` / `implementation-ready` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-UX-006-plan.md`
- Scope / ownership: add or tighten row-owned proof for "New-intro and mutual-accept notifications use the correct title/body content" without widening product scope, then refresh the matrix row with the new direct evidence; the matching three-simulator proof should come from `INTRO_E2E_SCENARIO=copy ./smoke_test_friends.sh`; session owns `tests only`.
- Likely code-entry files: `lib/features/introduction/application/introduction_listener.dart`, `lib/features/push/application/show_notification_use_case.dart`, `lib/features/push/application/background_push_notification_fallback.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered on `2026-04-09` by the exact new-intro and mutual-accept local-notification assertions in `introduction_listener_test.dart`, the new intros-fallback copy regressions in `background_push_notification_fallback_test.dart`, and a green rerun of `./scripts/run_test_gates.sh intro`.; `test/features/introduction/application/introduction_listener_test.dart`, `test/features/push/application/background_push_notification_fallback_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.
- Closure note: Accepted on `2026-04-09` after the existing exact-copy assertions in `introduction_listener_test.dart` were paired with new `background_push_notification_fallback_test.dart` regressions that preserve intro-review and mutual-accept title/body content on push-backed fallback notifications, with the intro gate green in the same pass.

### Session UX-007

- Source row / scenario / disposition / classification / plan: `UX-007` / `Notification deep-link opens Orbit intros and preserves shell return behavior` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-UX-007-plan.md`
- Scope / ownership: preserve the currently covered UX-007 contract for "Notification deep-link opens Orbit intros and preserves shell return behavior" and reopen only if new contradictory evidence appears; the matching three-simulator proof should come from `INTRO_E2E_SCENARIO=copy ./smoke_test_friends.sh`; session owns `no execution because already covered`.
- Likely code-entry files: `lib/main.dart`, `lib/features/push/application/prepare_notification_open_use_case.dart`, `lib/features/orbit/presentation/screens/orbit_wired.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `intro_notification_orbit_route_test.dart`, `chat_and_group_push_open_flow_test.dart`, and background push tests.; `test/features/push/application/intro_notification_orbit_route_test.dart`, `test/features/push/application/chat_and_group_push_open_flow_test.dart`, `test/integration/notification_tap_smoke_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session UX-009

- Source row / scenario / disposition / classification / plan: `UX-009` / `Mixed-script, RTL, long, and null usernames render correctly across intro UI surfaces` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-UX-009-plan.md`
- Scope / ownership: preserve the currently covered UX-009 contract for "Mixed-script, RTL, long, and null usernames render correctly across intro UI surfaces" and reopen only if new contradictory evidence appears; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/introduction/presentation/widgets/intro_row.dart`, `lib/features/introduction/presentation/widgets/intro_group_header.dart`, `lib/features/introduction/presentation/widgets/intro_system_message.dart`, `lib/features/introduction/presentation/screens/sent_confirmation_screen.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered across `intro_row_test.dart`, `intro_group_header_test.dart`, `intro_system_message_test.dart`, `intros_tab_extended_test.dart`, and `sent_confirmation_test.dart`.; `test/features/introduction/presentation/widgets/intro_row_test.dart`, `test/features/introduction/presentation/widgets/intro_group_header_test.dart`, `test/features/introduction/presentation/widgets/intro_system_message_test.dart`, `test/features/introduction/presentation/widgets/intros_tab_extended_test.dart`, `test/features/introduction/presentation/screens/sent_confirmation_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session UX-010

- Source row / scenario / disposition / classification / plan: `UX-010` / `Orbit live refresh reacts to introReceived, status changes, and delete actions` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-UX-010-plan.md`
- Scope / ownership: preserve the currently covered UX-010 contract for "Orbit live refresh reacts to introReceived, status changes, and delete actions" and reopen only if new contradictory evidence appears; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/orbit/presentation/screens/orbit_wired.dart`, `lib/features/orbit/presentation/screens/orbit_screen.dart`, `lib/features/introduction/application/introduction_listener.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `orbit_intros_wiring_test.dart` and intro-related `orbit_wired_test.dart`.; `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`, `test/features/orbit/presentation/screens/orbit_wired_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session UX-012

- Source row / scenario / disposition / classification / plan: `UX-012` / `Delete confirmation and cancel flow for intro rows are reliable` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-UX-012-plan.md`
- Scope / ownership: preserve the currently covered UX-012 contract for "Delete confirmation and cancel flow for intro rows are reliable" and reopen only if new contradictory evidence appears; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/orbit/presentation/screens/orbit_wired.dart`, `lib/features/orbit/presentation/widgets/confirmation_dialog.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by intro-related `orbit_wired_test.dart`.; `test/features/orbit/presentation/screens/orbit_wired_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session UX-004

- Source row / scenario / disposition / classification / plan: `UX-004` / `SentConfirmationWired end-to-end matches the sent result set` / `needs_tests_only` / `implementation-ready` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-UX-004-plan.md`
- Scope / ownership: add or tighten row-owned proof for "SentConfirmationWired end-to-end matches the sent result set" without widening product scope, then refresh the matrix row with the new direct evidence; session owns `tests only`.
- Likely code-entry files: `lib/features/introduction/presentation/screens/sent_confirmation_wired.dart`, `lib/features/introduction/presentation/screens/sent_confirmation_screen.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered on `2026-04-09` by the dedicated `SentConfirmationWired` wrapper regression in `sent_confirmation_wired_test.dart`, the existing pure screen assertions in `sent_confirmation_test.dart`, and a green rerun of `./scripts/run_test_gates.sh intro`.; `test/features/introduction/presentation/screens/sent_confirmation_wired_test.dart`, `test/features/introduction/presentation/screens/sent_confirmation_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.
- Closure note: Accepted on `2026-04-09` after `sent_confirmation_wired_test.dart` gained a direct wrapper regression proving the sent result set reaches the screen unchanged and the back-to-conversation callback still fires, with the intro gate green in the same pass.

### Session UX-008

- Source row / scenario / disposition / classification / plan: `UX-008` / `Feed connection card reflects introducedBy metadata and blocked state` / `covered_in_repo` / `stale/already-covered` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-UX-008-plan.md`
- Scope / ownership: preserve the currently covered UX-008 contract for "Feed connection card reflects introducedBy metadata and blocked state" and reopen only if new contradictory evidence appears; session owns `no execution because already covered`.
- Likely code-entry files: `lib/features/feed/presentation/widgets/introduction_connection_card.dart`, `lib/features/feed/presentation/widgets/connection_card.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered by `introduction_connection_card_test.dart` and feed-mapping assertions.; `test/features/feed/presentation/widgets/introduction_connection_card_test.dart`, `test/features/feed/presentation/widgets/connection_card_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.

### Session UX-011

- Source row / scenario / disposition / classification / plan: `UX-011` / `Orbit intro pending-count banner variant matches the underlying intro state` / `needs_tests_only` / `implementation-ready` / `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-UX-011-plan.md`
- Scope / ownership: add or tighten row-owned proof for "Orbit intro pending-count banner variant matches the underlying intro state" without widening product scope, then refresh the matrix row with the new direct evidence; session owns `tests only`.
- Likely code-entry files: `lib/features/orbit/presentation/screens/orbit_screen.dart`, `lib/features/orbit/presentation/screens/orbit_wired.dart`, `lib/features/orbit/presentation/widgets/friends_filter_toggle.dart`.
- Current repo evidence / likely direct tests / likely named gates: Covered on 2026-04-09 by the OrbitScreen banner regressions in `orbit_screen_archived_groups_test.dart` for zero, singular, and plural pending-intro states, plus a green rerun of `./scripts/run_test_gates.sh intro`.; `test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart`; `./scripts/run_test_gates.sh intro`.
- Dependency / docs to update when done: `none`; `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`, `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`.
- Closure update:
  accepted on `2026-04-09` after `orbit_screen_archived_groups_test.dart`
  gained direct Orbit intro-banner regressions proving the banner hides at
  zero pending intros and switches between singular and plural count copy for
  one vs many pending intro review items, with the intro gate green in the
  same pass
