# Group Media All Recipient Coverage Session Breakdown

## decomposition artifact

- Artifact path:
  `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`
- Supporting docs:
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  - `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`
  - `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage.md`
  - `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage-session-breakdown.md`
  - `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- Decomposition date:
  `2026-05-02`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must refresh against landed code, tests, and Report 89/MD-014 evidence before execution
  - do not count text-only group success as closure for image, video, or voice
  - do not count descriptor-only evidence as completed download/render evidence when the source case requires completed media
  - do not close the report on focused GMAR tests alone; the final session owns the required full regression sweep

## downstream execution path

- Sessions should run, in breakdown order, through:
  1. `$implementation-plan-orchestrator`
  2. `$implementation-execution-qa-orchestrator`
  3. `$implementation-closure-audit-orchestrator`
- Run `GMAR-005` only after `GMAR-001` through `GMAR-004` are accepted, marked stale/already-covered with concrete evidence, or truthfully blocked.
- After `GMAR-005`, run the pipeline's final whole-program acceptance/closure pass and persist one final program verdict in this breakdown artifact.
- Allowed final program verdicts for this rollout are `closed`, `accepted_with_explicit_follow_up`, `residual_only`, or `stale/already-covered`.
- A verdict is not trustworthy if the reported failure, "one eligible group member misses media that others can see", is only covered by sender-side, single-recipient, descriptor-only, or optional-failing evidence.
- Current final program verdict:
  `closed`

## Closure Progress

- `2026-05-03 00:14:26 CEST` - Session `GMAR-005`; closure audit completed.
  Docs inspected or updated:
  `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-005-plan.md`,
  `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`,
  `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`,
  `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`,
  `Test-Flight-Improv/test-gate-definitions.md`, and
  `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`. Verdict:
  accepted for GMAR-005 and closed for the final Report 90 program verdict.
  Evidence: the fix-authorized final rerun passed all required commands on
  `2026-05-02` / `2026-05-03`, including direct host GMAR suites, configured
  simulator media proofs, the two GMAR-relevant two-simulator smoke
  orchestrators with relay addresses, device-pinned `run_test_gates.sh all`,
  `completeness-check`, broad `flutter test`, `cd go-mknoon && go test ./...`,
  and `git diff --check`. No `still_open` blocker remains; future work should
  reopen this rollout only on a real regression or a separately scoped broader
  device-lab/announcement matrix requirement.
- `2026-05-02 11:15:54 CEST` - Session `GMAR-001`; closure phase:
  Completion Auditor starting. Docs inspected or updated:
  `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-001-plan.md`,
  `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`,
  `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`,
  `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`.
  Tentative verdict: accepted for text fan-out only; at that time, Report 90
  remained open for GMAR-002 through GMAR-004 media all-recipient parity. Next action:
  complete file-backed closure audit, then update only stale GMAR-001 docs if
  needed.
- `2026-05-02 11:16:56 CEST` - Session `GMAR-001`; closure phase:
  Completion Auditor completed / Closure Writer starting. Docs inspected or
  updated: `test/features/groups/integration/group_messaging_smoke_test.dart`,
  `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-001-plan.md`,
  `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`,
  `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`,
  `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`,
  `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`. Tentative
  verdict: accepted; closed scope is the four-user text fan-out complaint with
  exact sender/text identity and exact-once receipt. Next action: write only
  missing GMAR-001 closure-progress documentation and preserve media parity as
  pending for GMAR-002 through GMAR-004.
- `2026-05-02 11:17:15 CEST` - Session `GMAR-001`; closure phase:
  Closure Writer completed / Closure Reviewer starting. Docs inspected or
  updated:
  `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`.
  Tentative verdict: accepted for GMAR-001 text fan-out closure; no source,
  closure-reference, or inventory wording change required beyond the current
  closure-progress trail because those docs already distinguish text proof from
  open media parity. Next action: review closure docs for overclaiming,
  residual-gap omissions, and consistency with accepted execution evidence.
- `2026-05-02 11:17:53 CEST` - Session `GMAR-001`; closure phase:
  Closure Reviewer completed. Docs inspected or updated:
  `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`,
  `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`,
  `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`.
  Tentative verdict: accepted / closed for GMAR-001 text fan-out only. Next
  action at GMAR-001 closure time: return closure result; GMAR-002 through
  GMAR-004 remained the only Report 90 media all-recipient parity
  implementation/evidence sessions, and GMAR-005 was scheduled as the final
  acceptance/full-sweep session. All later sessions are now accepted.
- `2026-05-02 11:43:07 CEST` - Session `GMAR-002`; Executor recovery
  closure evidence recorded. Docs inspected or updated:
  `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-002-plan.md`,
  `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`,
  `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`,
  `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`,
  and `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`.
  Verdict: accepted for existing-member app-layer image/video/voice download
  parity, one-recipient failure detection, and two-authorized-non-sender Go
  group blob download proof. Historical next action was to keep GMAR-003,
  GMAR-004, and GMAR-005 pending; do not treat GMAR-002 as simulator render/playback,
  new-member, non-creator, offline/reopen/retry, or final full-suite closure.
  All later sessions are now accepted.
- `2026-05-02 11:58:29 CEST` - Session `GMAR-002`; closure audit completed.
  Docs inspected or updated:
  `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-002-plan.md`,
  `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`,
  `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`,
  `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`,
  and `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`. Verdict:
  accepted for existing-member app-layer image/video/voice download parity,
  one-recipient failure detection, and two-authorized-non-sender Go blob proof.
  Closure Writer updated only stale GMAR-002 wording in the discussion closure
  reference and Go inventory row; source and plan evidence were already current.
  Closure Reviewer confirmed GMAR-003 newly-added/non-creator parity, GMAR-004
  visible render/playback/reopen/retry/offline/duplicate behavior, and GMAR-005
  final full-suite closure were pending at GMAR-002 closure time and were not
  claimed by GMAR-002. All later sessions are now accepted.
- `2026-05-02 12:20:35 CEST` - Session `GMAR-003`; executor evidence
  recorded. Docs inspected or updated:
  `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-003-plan.md`,
  `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`,
  `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`,
  `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage.md`,
  `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`,
  and `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`. Verdict:
  accepted for host/app-layer newly-added multi-recipient media parity,
  newly-added sender media parity, existing non-creator sender media parity,
  no-pre-join text/media backfill, and preserved removed-member media
  exclusion. Historical next action was to keep GMAR-004 and GMAR-005 pending; do not
  claim visible simulator/reopen/retry/offline/duplicate behavior or final
  full-suite closure from GMAR-003. GMAR-004 and GMAR-005 are now accepted.
- `2026-05-02 13:51:00 CEST` - Session `GMAR-004`; closure phase:
  Completion Auditor completed / Closure Writer starting. Docs inspected or
  updated:
  `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-004-plan.md`,
  `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`,
  `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`,
  `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`,
  and `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`. Tentative
  verdict: accepted for configured visible media/recovery proof; GMAR-005 final
  full-suite/gate reconciliation was still pending at GMAR-004 closure time and
  is now accepted.
- `2026-05-02 13:51:20 CEST` - Session `GMAR-004`; closure phase:
  Closure Writer completed / Closure Reviewer starting. Docs inspected or
  updated:
  `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`,
  `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`,
  `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, and this
  breakdown. Tentative verdict: accepted; stale configured simulator failure
  wording was converted into fixture-metadata-fixed simulator proof, host
  visible/reopen/retry/offline/duplicate evidence, and signed replay fixture
  evidence without claiming final program closure.
- `2026-05-02 13:51:40 CEST` - Session `GMAR-004`; closure phase:
  Closure Reviewer completed. Docs inspected or updated:
  `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`,
  `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`,
  `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, and this
  breakdown. Verdict: accepted for GMAR-004 visible media parity, reopen
  preservation, retry visibility, offline inbox recovery, duplicate
  live/inbox replay, and the configured simulator proof. Historical next
  action at GMAR-004 closure time: GMAR-005 was still pending, so that closure
  pass did not write a final program verdict. GMAR-005 later closed that final
  verdict on `2026-05-03`.

## run-mode snapshot

- Snapshot refreshed:
  `2026-05-02 10:54:24 CEST`
- Active mode:
  `standard`
- Degraded local continuation:
  `not allowed by this run prompt`
- Source proposal/matrix/closure doc:
  `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`
- Source status vocabulary:
  GMAR source cases are resolved only by concrete evidence in this source doc,
  the named closure references, the Group Chat test inventory, and this
  breakdown ledger. Session statuses use `pending`, `accepted`,
  `accepted_with_explicit_follow_up`, `stale/already-covered`,
  `skipped_due_to_dependency`, `prerequisite-blocked`, and `blocked`.
- Overall closure bar:
  the report had to stay `still_open` until all bullets in this breakdown's
  `overall closure bar` were satisfied, including all-recipient media download
  or render parity, new-member/non-creator parity, user-visible media states,
  exclusion boundaries, doc/gate reconciliation, and the final full-suite gate
  evidence or exact blocker record. GMAR-005 now records that bar as satisfied.
- Final verdict policy for this run:
  persist one final program verdict after all runnable sessions resolve:
  `closed`, `accepted_with_explicit_follow_up`, `residual_only`, or
  `still_open`. Do not treat focused GMAR tests, sender-side media evidence,
  single-recipient completion, descriptor-only proof, or optional-failing
  simulator evidence as enough to close the program.

## recommended plan count

- `5`
- The smallest safe split is:
  - `1` evidence and closure-mapping session for existing text fan-out, current Report 89 media evidence, and stale-overlap classification
  - `1` implementation/evidence session for all eligible existing media recipients independently downloading the same image, video, and voice blobs
  - `1` implementation/evidence session for multiple newly-added recipients and non-creator senders preserving all-recipient media parity without pre-join backfill
  - `1` implementation/evidence session for user-visible simulator/render/reopen, failure, retry, inbox, and duplicate media behavior
  - `1` acceptance/closure session for gate classification, full sweep evidence, matrix/docs reconciliation, and final verdict
- Session disposition counts:
  - `implementation-ready`: `3`
  - `evidence-gated`: `1`
  - `fix-authorized final acceptance/recovery`: `1`
  - `acceptance-only`: `0` after the GMAR-005 resume override
  - `stale/already-covered`: `0` at decomposition time; the pipeline may mark a session stale/already-covered only after verifying current repo evidence and updating the ledger/docs with concrete proof

## overall closure bar

This was the required closure bar before the final verdict. GMAR-005 now records it as satisfied, so `Test-Flight-Improv/90-group-media-all-recipient-coverage.md` is closed unless a real regression reopens it:

- a group with at least four active members proves every participant receives text from every other active participant, not only from the creator
- image, video, and voice sent by any eligible active member produce one stable row and attachment set for every eligible non-sender recipient
- at least two eligible non-sender recipients independently download or render the same group media instead of one recipient completing while another remains descriptor-only where completion is expected
- newly-added multiple recipients receive the same eligible post-join media while pre-join text/media remains excluded
- newly-added or non-creator member media sends reach all existing eligible members with stable sender identity, message identity, attachment metadata, and no duplicate live/inbox rows
- a visible conversation surface or simulator proof shows truthful image/video/voice rows, playback or preview affordances, reopen preservation, and observable failed/pending/retryable states instead of silent omission
- removed members and outsiders remain excluded from later media delivery, inbox recovery, notification open, retry, and direct blob download
- `Test-Flight-Improv/test-gate-definitions.md`, the relevant group closure references, the source doc, the Group Chat test inventory, and this breakdown agree on covered, residual, and manual/device-gated evidence
- the final full-suite gate from the source doc is run or truthfully blocked with exact command, failure, fixture, and non-GMAR impact recorded

## source of truth

Primary governing docs:

- `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`
- `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

Current repo facts that materially affected decomposition:

- `test/features/groups/integration/group_messaging_smoke_test.dart` is already in the `groups` gate and contains a four-user text round-robin proving active participants receive text from all other participants. GMAR-001 tightened it on `2026-05-02` so every participant also checks exact incoming sender/text identity and exact-once appearance.
- `test/features/groups/integration/group_media_fanout_test.dart` is an optional/manual direct suite. GMAR-002 proves existing discussion image/video/voice fan-out with completed downloads for Bob and Charlie, exact per-recipient download calls, and one-recipient failure detection. GMAR-003 now proves newly-added Bob's image/video/voice sends reach Alice and Charlie with completed downloads, and existing non-creator Charlie's image/video/voice sends reach Alice and Bob with completed downloads.
- `test/features/groups/integration/group_new_member_onboarding_test.dart` is an optional/manual direct suite covering new-member post-join text/image/video/voice descriptors and no-backfill boundaries. GMAR-003 now also proves newly-added Bob and Charlie independently download the same post-join image/video/voice while pre-join text/media remains excluded.
- `integration_test/group_new_member_media_simulator_proof_test.dart` and `integration_test/media_message_journey_e2e_test.dart` are optional/manual direct suites. GMAR-004 fixed the configured simulator media proof by adding truthful fixture content hashes and encryption metadata; GMAR-005 fixed stale media-message journey and stable-ID fixtures and reran both suites green on `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`.
- `go-mknoon/integration/media_test.go` covers group media upload/download authorization for one sender, two authorized non-sender members, and one outsider after GMAR-002; both non-senders independently download the same group media byte-for-byte.
- `scripts/run_test_gates.sh` keeps `group_media_fanout_test.dart`, `group_new_member_onboarding_test.dart`, `group_new_member_media_simulator_proof_test.dart`, and `media_message_journey_e2e_test.dart` outside the frozen `groups` gate, so the acceptance session must run them directly or record exact blockers.

## source test case inventory

| Source case | Primary session | Disposition at decomposition |
| --- | --- | --- |
| `GMAR-001` | `GMAR-001` | accepted on `2026-05-02` by tightened `group_messaging_smoke_test.dart` text fan-out proof plus green `groups` gate |
| `GMAR-002` | `GMAR-002`, `GMAR-004` | accepted: existing-member image app-layer completed download plus GMAR-004 visible media-row/failure-state preservation where image media cannot render |
| `GMAR-003` | `GMAR-002`, `GMAR-004` | accepted: existing-member video app-layer completed download plus configured visible playback/preview proof |
| `GMAR-004` | `GMAR-002`, `GMAR-004` | accepted: existing-member voice app-layer completed download plus configured visible playback proof |
| `GMAR-005` | `GMAR-003` | accepted at app-layer boundary: multiple newly-added Bob/Charlie recipients independently download the same post-join image/video/voice while pre-join text/media stays excluded |
| `GMAR-006` | `GMAR-003`, `GMAR-004` | accepted: newly-added sender app-layer all-recipient completed download, with GMAR-004 configured simulator proof covering representative visible incoming/outgoing video/voice rows |
| `GMAR-007` | `GMAR-002` | accepted: two authorized non-sender recipients independently download same group blob; outsider remains rejected |
| `GMAR-008` | `GMAR-004` | accepted: conversation reopen/hydration preserves media rows, attachment metadata, and completed/pending/failed states without duplicates |
| `GMAR-009` | `GMAR-004` | accepted: text success cannot hide media omission; pending/failed/retryable media states remain visible |
| `GMAR-010` | `GMAR-002` | accepted at app-layer boundary: one recipient failure remains observable even if another recipient succeeds |
| `GMAR-011` | `GMAR-001`, `GMAR-003`, `GMAR-004` | accepted: text, app-layer media parity, and configured visible media proof for non-creator/new-member sender paths |
| `GMAR-012` | `GMAR-003` | accepted: no pre-join text/image/video/voice backfill remains intact while multi-new-member media proof tightens |
| `GMAR-013` | `GMAR-004` | accepted: offline recipient recovery includes video/voice media without duplicating already-seen rows |
| `GMAR-014` | `GMAR-004` | accepted: duplicate live plus inbox replay enriches sparse media once without duplicate rows or attachment sets |
| `GMAR-015` | `GMAR-003` | preserved by full `group_media_fanout_test.dart` MD-011 removed-member media exclusion suite |
| `GMAR-016` | `GMAR-004` | accepted: failed or unavailable media state remains visible and recoverable through the scoped repair path |
| Bug regression: member sees only creator messages | `GMAR-001`, `GMAR-003`, `GMAR-004` | accepted at text, app-layer media, and configured visible media boundaries |
| Bug regression: one member misses media others can see | `GMAR-002`, `GMAR-004` | accepted: existing-member app-layer download divergence plus configured visible render/reopen/retry/offline/duplicate proof |
| Gate confidence regression | `GMAR-005` | accepted: optional/manual GMAR suites were run directly, two-simulator smoke evidence passed with relay addresses, and the device-pinned `all` gate passed |
| Full-suite confidence regression | `GMAR-005` | accepted: final full sweep passed, including broad `flutter test`, Go module `go test ./...`, completeness check, and `git diff --check` |

## session ledger

| Session ID | Source cases | Classification | Intended plan file | Depends on | Current status |
| --- | --- | --- | --- | --- | --- |
| `GMAR-001` | `GMAR-001`, bug regression: member sees only creator messages | `evidence-gated` | `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-001-plan.md` | none | `accepted` |
| `GMAR-002` | `GMAR-002`, `GMAR-003`, `GMAR-004`, `GMAR-007`, `GMAR-010`, bug regression: one member misses media others can see | `implementation-ready` | `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-002-plan.md` | `GMAR-001` evidence refresh preferred but not required | `accepted` |
| `GMAR-003` | `GMAR-005`, `GMAR-006`, `GMAR-011`, `GMAR-012`, `GMAR-015`, bug regression: non-creator parity | `implementation-ready` | `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-003-plan.md` | none | `accepted` |
| `GMAR-004` | `GMAR-003`, `GMAR-004`, `GMAR-008`, `GMAR-009`, `GMAR-013`, `GMAR-014`, `GMAR-016`, bug regression: visible media parity | `implementation-ready` | `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-004-plan.md` | `GMAR-002` and `GMAR-003` if they add shared fixtures/helpers | `accepted` |
| `GMAR-005` | final acceptance, gate confidence regression, full-suite confidence regression | `fix-authorized final acceptance/recovery` | `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-005-plan.md` | `GMAR-001`, `GMAR-002`, `GMAR-003`, `GMAR-004` resolved or explicitly blocked | `accepted` |

## ordered session breakdown

### Session GMAR-001

- Title:
  `Existing text fan-out and current media evidence map`
- Session id:
  `GMAR-001`
- Source cases:
  `GMAR-001`, bug regression: member sees only creator messages
- Session classification:
  `evidence-gated`
- Intended plan file:
  `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-001-plan.md`
- Exact scope:
  - verify the current four-user text round-robin still proves all active members receive text from every other active participant
  - map Report 89 media evidence and current Group Chat inventory rows to this narrower all-recipient report without overclaiming descriptor-only or optional-failing media proof
  - update the source doc, group discussion closure reference, and this ledger with concrete current evidence or reclassify uncovered text/media gaps for later sessions
- Why it is its own session:
  - text fan-out is likely already covered, but this report must not let text evidence mask media parity gaps
- Likely code-entry files:
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `test/core/bridge/fake_group_pubsub_network.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
  - `test/features/groups/integration/group_media_fanout_test.dart`
  - `test/features/groups/integration/group_new_member_onboarding_test.dart`
- Likely named gates:
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh completeness-check` if classification docs change
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  - `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` if inventory evidence is corrected or narrowed
  - this breakdown ledger
- Execution evidence:
  - accepted on `2026-05-02` after tightening the existing four-user round-robin text test to assert Admin, Bob, Charlie, and Diana each receive the expected three incoming texts exactly once with matching sender peer IDs and usernames
  - `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name '4 users: round-robin messaging'` passed with `00:00 +1: All tests passed!`
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed with `00:08 +103: All tests passed!`
  - `Group-Chat-Feature/test-inventory.md` was inspected and left unchanged because it already records MD-014 as partial and existing media fan-out as descriptor/app-layer evidence with only one receiver exercising download
  - at GMAR-001 closure time, GMAR-002 through GMAR-004 remained open for all-recipient image/video/voice completion, visible render/playback, and one-recipient-failure detection; GMAR-002 evidence is recorded in the next session section
- Dependency on earlier sessions:
  - none

### Session GMAR-002

- Title:
  `Existing-member all-recipient media download parity`
- Session id:
  `GMAR-002`
- Source cases:
  `GMAR-002`, `GMAR-003`, `GMAR-004`, `GMAR-007`, `GMAR-010`, bug regression: one member misses media others can see
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-002-plan.md`
- Exact scope:
  - strengthen existing-member group media fan-out so at least two eligible non-sender recipients independently receive the same image, video, and voice rows
  - prove completed download state, stable row/message identity, attachment metadata, and media type details for every eligible non-sender recipient where the product contract expects completion
  - fail the regression if Bob succeeds but Charlie is descriptor-only, missing a row, missing metadata, unable to download, or otherwise diverges while both are eligible
  - extend Go/media or Flutter fake-bridge authorization coverage as needed so two authorized non-sender recipients can download the same group blob and an outsider remains rejected
- Why it is its own session:
  - this is the core recipient-parity gap in the report and should be closed before simulator/UI acceptance relies on it
- Likely code-entry files:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `lib/features/conversation/application/download_media_use_case.dart`
  - `test/core/bridge/fake_bridge.dart`
  - `test/core/bridge/fake_group_pubsub_network.dart`
  - `go-mknoon/integration/media_test.go`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_media_fanout_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - `cd go-mknoon && go test -tags integration ./integration -run 'Group.*Media|Media.*Group'`
- Likely named gates:
  - direct focused Flutter suite above
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` if shared group delivery or retry behavior changes
  - Go media integration command when Go media authorization changes
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  - `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
  - this breakdown ledger
- Execution evidence:
  - accepted on `2026-05-02` after strengthening `group_media_fanout_test.dart` so Bob and Charlie each independently download Alice's existing-member image, video, and voice messages with matching incoming message ids, attachment metadata, `downloadStatus == done`, non-null local paths, and exactly three `media:download` calls per recipient
  - one-recipient failure detection was added in the same suite: Charlie's forced image download failure remains `failed`/non-done with no local path while Bob's image/video/voice and Charlie's video/voice downloads remain `done`
  - production `download_media_use_case.dart` now scopes in-flight download dedupe by bridge, media attachment repository, and media file manager identity before `groupId|blobId|mime`, preventing cross-recipient local download bleed while retaining same-owner dedupe
  - `go-mknoon/integration/media_test.go` now proves two authorized non-sender members independently download the same group blob byte-for-byte and outsider rejection still holds
  - `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name 'discussion members independently download image, video, and voice for every eligible recipient'` passed with `00:00 +1: All tests passed!`
  - `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart` passed with `00:00 +6: All tests passed!`
  - `cd go-mknoon && go test -tags integration ./integration -run 'TestRelayGroupMediaUploadDownload|TestRelayGroupMediaVoiceNote' -count=1 -v` passed with `PASS`; key proof lines include `member B download: mime=image/jpeg size=4096`, `member D download: mime=image/jpeg size=4096`, and `outsider correctly rejected: download failed: not authorized`
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed with `00:12 +103: All tests passed!`
  - `git diff --check` passed before doc updates; final post-doc diff check is recorded in the GMAR-002 plan progress
  - `./scripts/run_test_gates.sh completeness-check` was not required because no new test file was added, no suite was reclassified, and `Test-Flight-Improv/test-gate-definitions.md` was not changed
  - at GMAR-002 closure time, GMAR-003 remained pending for newly-added/non-creator media parity and GMAR-004 remained pending for visible render/playback/reopen/retry/offline/duplicate proof; both later accepted, and GMAR-005 later closed final acceptance/full-suite closure
- Dependency on earlier sessions:
  - `GMAR-001` evidence refresh preferred but not required

### Session GMAR-003

- Title:
  `New-member and non-creator all-recipient media parity`
- Session id:
  `GMAR-003`
- Source cases:
  `GMAR-005`, `GMAR-006`, `GMAR-011`, `GMAR-012`, `GMAR-015`, bug regression: non-creator parity
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-003-plan.md`
- Exact scope:
  - prove multiple newly-added members receive the same eligible post-join image, video, and voice rows without receiving pre-join history
  - prove media sent by a newly-added member or any non-creator active member reaches the creator and every other eligible member exactly once
  - preserve no-backfill, sender identity, sender message id, key epoch, attachment metadata, and removed-member exclusion while media coverage tightens
  - reuse Report 89 fixtures where they directly prove this report, but add assertions where Report 89 evidence stops at descriptor-only or one-recipient completion
- Why it is its own session:
  - new-member and non-creator parity exercises membership/key/bootstrap boundaries that are distinct from existing-member media download parity
- Likely code-entry files:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `lib/features/conversation/domain/models/media_attachment.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_new_member_onboarding_test.dart`
  - `test/features/groups/integration/group_media_fanout_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/integration/invite_round_trip_test.dart`
- Likely named gates:
  - direct focused suites above
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh completeness-check` if new direct tests are classified
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`
  - `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage.md` only if reused evidence is corrected or narrowed
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  - `Test-Flight-Improv/test-gate-definitions.md` if new direct suites are added or reclassified
  - this breakdown ledger
- Execution evidence:
  - accepted on `2026-05-02` after strengthening `group_new_member_onboarding_test.dart` so newly-added Bob and Charlie independently download Alice's same post-join image, video, and voice messages with matching sender message ids, Alice sender identity, key epoch, attachment metadata, `downloadStatus == done`, non-null local paths, and exactly three `media:download` calls per recipient
  - the same multi-new-member proof sends pre-join text, image, video, and voice before Bob/Charlie are active and asserts neither recipient receives those rows, attachment records, pending downloads, or pre-join media download calls
  - `group_media_fanout_test.dart` now proves newly-added Bob's image/video/voice sends reach Alice and Charlie with completed downloads, and existing non-creator Charlie's image/video/voice sends reach Alice and Bob with completed downloads; both paths assert exact sender identity, sender message ids, key epoch, attachment metadata, and exact per-recipient download calls
  - the full `group_media_fanout_test.dart` suite passed, preserving MD-011 removed-member future-media exclusion while GMAR-003 assertions tightened
  - `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart --plain-name 'multiple newly-added members independently download the same post-join image, video, and voice without pre-join history'` passed with `00:00 +1: All tests passed!`
  - `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name 'newly-added discussion member media reaches every eligible recipient'` passed with `00:00 +1: All tests passed!`
  - `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name 'existing non-creator discussion member media reaches creator and every eligible recipient'` passed with `00:00 +1: All tests passed!`
  - `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart` passed with `00:01 +7: All tests passed!`
  - `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart` passed with `00:01 +7: All tests passed!`
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed with `00:08 +103: All tests passed!`
  - `git diff --check` passed after the final documentation update
- Boundary:
  - at GMAR-003 closure time, GMAR-004 visible preview/playback/reopen/retry/offline/duplicate simulator behavior and GMAR-005 final full-suite/gate reconciliation remained pending; both later accepted
- Dependency on earlier sessions:
  - none

### Session GMAR-004

- Title:
  `Visible media parity recovery retry inbox duplicate and reopen behavior`
- Session id:
  `GMAR-004`
- Source cases:
  `GMAR-003`, `GMAR-004`, `GMAR-008`, `GMAR-009`, `GMAR-013`, `GMAR-014`, `GMAR-016`, bug regression: visible media parity
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-004-plan.md`
- Exact scope:
  - make the conversation surface prove video and voice rows render with truthful preview/playback affordances for every eligible recipient required by the source doc
  - prove reopening the group conversation preserves the same media rows, attachment metadata, and completed/pending/failed states
  - prove text success cannot silently hide failed media; failed, pending, retryable, and recovered media states remain visible and actionable
  - prove offline inbox recovery and duplicate live plus inbox replay produce one row and one attachment set per eligible recipient
  - triage and fix or truthfully block the configured simulator proof failure recorded in the inventory; GMAR-004 fixed it as stale fixture metadata and reran the configured simulator proof green
- Why it is its own session:
  - descriptor and download tests can pass while the user-visible timeline still omits or misrepresents media
- Likely code-entry files:
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/groups/presentation/screens/group_conversation_screen.dart`
  - `lib/features/conversation/presentation/widgets/media_grid_cell.dart`
  - `lib/features/conversation/presentation/widgets/video_thumbnail_overlay.dart`
  - `lib/features/conversation/presentation/widgets/audio_player_widget.dart`
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
  - `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- Likely direct tests/regressions:
  - `test/features/groups/presentation/group_conversation_screen_test.dart`
  - `test/features/groups/presentation/group_conversation_wired_test.dart`
  - `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
  - `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
  - `integration_test/group_new_member_media_simulator_proof_test.dart`
  - `integration_test/media_message_journey_e2e_test.dart`
  - `integration_test/foreground_group_push_drain_test.dart`
- Likely named gates:
  - direct focused widget/application suites above
  - `flutter test -d <available-device-id> integration_test/group_new_member_media_simulator_proof_test.dart`
  - `flutter test -d <available-device-id> integration_test/media_message_journey_e2e_test.dart`
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` if shared group presentation/recovery behavior changes
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  - `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
  - `Test-Flight-Improv/test-gate-definitions.md` if simulator/direct-suite classification changes
  - this breakdown ledger
- Dependency on earlier sessions:
  - `GMAR-002` and `GMAR-003` if they add shared media fixtures or parity helpers
- Device/relay proof profile requirement:
  - the plan must run `flutter devices --machine` before choosing simulator commands
  - if the configured simulator/device needed for the current inventory failure is unavailable, record the exact missing device id and leave only that device proof blocked; do not weaken host/widget parity requirements
- Execution evidence:
  - accepted on `2026-05-02` after reproducing the configured simulator failure where `VideoThumbnailOverlay` expected two widgets and found zero, then fixing stale fixture metadata by adding content hashes and encryption metadata to the simulator video/voice fixtures without weakening group media integrity policy
  - no GMAR-004 production logic change was required; scoped landed changes were simulator fixture metadata plus host/widget/application tests in `integration_test/group_new_member_media_simulator_proof_test.dart`, `group_conversation_screen_test.dart`, `group_conversation_wired_test.dart`, and `drain_group_offline_inbox_use_case_test.dart`
  - `group_conversation_screen_test.dart` now proves text plus video, voice, and failed media rows remain visibly rendered across rebuild/reopen-style rendering
  - `group_conversation_wired_test.dart` now proves reopen hydration preserves completed, pending, and failed video/voice media metadata without duplicate rows or attachment sets, with unavailable-media retry still wired to the scoped repair path
  - `drain_group_offline_inbox_use_case_test.dart` now proves duplicate live plus signed inbox replay enriches sparse video/voice media once; the fix pass signed legacy fake replay fixtures at the test fake bridge boundary so the full drain suite passes while preserving production signed replay and media integrity policy
  - configured simulator proof passed after clean rebuild: `flutter test --no-pub -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD integration_test/group_new_member_media_simulator_proof_test.dart`
  - `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart` passed
  - `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart` passed
  - `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` passed after the fix pass/final QA
  - `flutter test --no-pub test/features/groups/application/retry_failed_group_messages_use_case_test.dart` passed
  - `flutter test --no-pub test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart` passed
  - `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart` passed
  - `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart` passed
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed
  - `./scripts/run_test_gates.sh completeness-check` passed with `712/712` classified
  - `git diff --check` passed
- Boundary:
  - GMAR-004 did not write the final program verdict and did not claim `./scripts/run_test_gates.sh all`; GMAR-005 later closed final gate/full-suite reconciliation and broader direct optional/manual suite reconciliation such as `media_message_journey_e2e_test.dart`

### Session GMAR-005

- Title:
  `GMAR gate classification full sweep and final closure`
- Session id:
  `GMAR-005`
- Source cases:
  final acceptance, gate confidence regression, full-suite confidence regression
- Session classification:
  `fix-authorized final acceptance/recovery`
- Intended plan file:
  `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-005-plan.md`
- Exact scope:
  - reconcile all GMAR evidence into the source doc, group discussion closure reference, Group Chat test inventory, gate definitions, and this ledger
  - ensure every optional/manual direct media or simulator suite used as GMAR evidence is either run successfully or has an exact blocker recorded
  - run the required final full-suite gate from the source doc: `./scripts/run_test_gates.sh all`, `./scripts/run_test_gates.sh completeness-check`, the GMAR direct optional/manual suites, and any broader repo-level full-suite command that exists at implementation time
  - persist the final program verdict only after unresolved sessions are accepted, accepted with explicit follow-up, residual-only, stale/already-covered, or truthfully blocked according to the source closure bar
- Why it is its own session:
  - final closure depends on evidence from multiple earlier sessions and must not be mixed with implementation
- Likely code-entry files:
  - GMAR-005 ultimately touched repo-owned production code, tests, fixtures, scripts, and docs only where required by failing final gates; see the GMAR-005 plan for the exact recovery ledger
- Likely direct tests/regressions:
  - `./scripts/run_test_gates.sh all`
  - `./scripts/run_test_gates.sh completeness-check`
  - `flutter test test/features/groups/integration/group_media_fanout_test.dart`
  - `flutter test test/features/groups/integration/group_new_member_onboarding_test.dart`
  - `flutter test -d <available-device-id> integration_test/group_new_member_media_simulator_proof_test.dart`
  - `flutter test -d <available-device-id> integration_test/media_message_journey_e2e_test.dart`
  - any broader repo-level full-suite command discovered during planning
- Likely named gates:
  - `./scripts/run_test_gates.sh all`
  - `./scripts/run_test_gates.sh completeness-check`
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  - `Test-Flight-Improv/21-announcement-reliability-closure-reference.md` only if announcement scope is touched or explicitly ruled residual
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
  - this breakdown ledger and final program verdict
- Dependency on earlier sessions:
  - `GMAR-001`, `GMAR-002`, `GMAR-003`, and `GMAR-004` resolved or explicitly blocked
- Closure result:
  - accepted on `2026-05-03` after fixing and rerunning every required failing command and then passing the full GMAR-005 final gate set from command 1 through command 13
  - final program verdict is `closed`; no `still_open` blocker remains
