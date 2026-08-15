# 369 - GAP-N03 Durable Completed Local Notification Outcome Foundation

Status: **POST-EXECUTION AUDIT CLOSED / N03 DURABLE LOCAL OUTCOME FOUNDATION CODE COMPLETE / N03 SLICE 1 OF 2 / HOST VERIFIED / DEFAULT-OFF / NOT N03-COMPLETE / NOT RELEASE-ELIGIBLE**
Type: Modification
Spec: `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2.md` §§5.1, 6, 8, and 9; GAP-N03 and WP-03 in `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md`
Classification: implementation-ready local persistence and projection boundary; prerequisite for the relay outcome protocol
Closure tier: deterministic host only; no notification UI/native/device campaign

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-15 | Evidence Collector | N01/N02 receipts; PRD/GAP-N03; `NotificationPresentationResult`; durable event claims; direct/group display outboxes and projection owners; lifecycle/read owners; migration and gate inventories | Causally this slice consumes N01's authenticated event/display custody. Plan 368 is the single frozen-tree provenance preflight and transitively binds Plan 367 and Plan 366/N01. Current terminal results conflate completed effects with replay/dedup terminal states, and display custody is deleted without retaining an outcome. | Define one narrow completed-outcome authority before any relay action exists. |
| 2026-08-15 | Planner using `$tdd-plan` | Graphify TDD context, source anchors, v106/v107 transaction seams, OQ-02/OQ-03 decisions, available-device matrix | Reuse the two display owners and one shared v116 outbox. Do not create direct/group/platform ledgers or let compatibility push paths emit outcomes. | Execute TC-369-01 RED after the dependency preflight. |

## Problem And Evidence

- Behavior to improve: after an authenticated incoming direct/group message or
  reaction is durably projected, the installation has no typed, durable fact
  saying that the exact event completed in-chat, reached the OS notification
  boundary, or was intentionally suppressed by local policy.
- Impact: the relay cannot safely distinguish transport persistence from a
  completed local effect. A later `wake_not_required` implementation would
  otherwise suppress recovery from a replay marker, stale row, ambiguous native
  callback, or delivery ACK.
- Confirmed current gap:
  - `NotificationPresentationResult` in
    `lib/core/notifications/notification_service.dart` has only `shown`,
    `terminalSuppressed`, and `contendedRetryable`;
  - `maybeShowNotification` in
    `lib/features/push/application/show_notification_use_case.dart` returns the
    same terminal value for exact-chat visibility, recovery suppression, recent
    remote presentation, and an already-owned durable claim;
  - `DirectNotificationProjectionOwner` and `GroupMessageListener` collapse
    every non-retry terminal result, then `completeIfExact` deletes v107/v106
    display custody without retaining a completed outcome.
- Existing coverage: v106/v107 tests prove exact revision CAS, durable retry,
  generation-safe cancellation, direct/group isolation, and cross-process event
  claim semantics. These are reuse seams, not a completed outcome protocol.
- Missing coverage owned here: typed terminal discrimination; atomic outcome +
  exact display completion; crash/retry persistence; installation-local
  correlation; and explicit exclusion of replay, policy, duplicate,
  native-ambiguous, and compatibility paths.
- Refuted finding: the filesystem event claim is not by itself the outbound
  outcome authority. It may prove first publication ownership, but it cannot be
  atomically retained with both SQL display-custody completion owners and it
  deliberately treats malformed/NSE/unknown publication residue fail-closed.
- Unresolved finding: native NSE, Android service, WorkManager, and reconciler
  adoption requires the later N04-N06 shared lifecycle/ledger wave. This plan
  does not falsely classify those paths or advertise a capability.

Primary production/test/gate files:

- `lib/core/database/app_database_version.dart`
- `lib/core/database/production_migration_registry.dart`
- new `lib/core/database/migrations/116_notification_completed_outcome_outbox.dart`
- new outcome model/helper/repository under `lib/core/notifications/` and
  `lib/core/database/helpers/`
- new `test/shared/fixtures/wake_outcome_correlation_v1.json`, consumed verbatim
  by Dart here and Go in Plan 370
- v106/v107 display helpers/repositories and the direct/group projection owners
- `lib/features/push/application/show_notification_use_case.dart`
- account-migration snapshot export, schema inventory, and active-import policy
  for the installation-local v116 table
- focused migration, outcome, show, and direct/group projection-owner tests
- `scripts/run_test_gates.sh` and the existing simulation-discovery description

## Dependency Contract

Causally this plan consumes N01's authenticated canonical event/display
custody. The single practical provenance preflight is GAP-N02's
checksum-bound Plan-368 tree because that receipt transitively binds Plan 367
and Plan 366/N01. It does not make N01/N02 live, S2, B1b, migration activation,
PRD, or release acceptance a prerequisite. Before the first RED, validate:

```text
receipt: Test-Flight-Improv/evidence/368/README.md
receipt SHA-256: 0d6747b448a97103b750eaa275a37ded1cceeff096582b0fb05b15d1357ca5f1
marker: N02_OPAQUE_WAKE_MECHANISM_CODE_COMPLETE
frozen tested tree: 924e8f64ebc7c9dca2de83890ecad144fefbdaf2
dirty snapshot: d15109f11a37cda022fd90e44526d5bf15b03091578d3dd3ccf71738d5676428
Graphify: 27ea9a664ebf98d9
```

```bash
(
  set -euo pipefail
  cd Test-Flight-Improv/evidence/368
  shasum -a 256 -c README.md.sha256
  rg -x 'N02_OPAQUE_WAKE_MECHANISM_CODE_COMPLETE' README.md
  test "$(shasum -a 256 README.md | awk '{print $1}')" = \
    '0d6747b448a97103b750eaa275a37ded1cceeff096582b0fb05b15d1357ca5f1'
  git cat-file -e '924e8f64ebc7c9dca2de83890ecad144fefbdaf2^{tree}'
)
```

Plan 368 transitively validates/retests Plan 367. Do not repeat the Plan-367
migration preflight unless this plan unexpectedly changes its vault or route
internals. This plan preserves the opaque route and fixed wake but does not
advertise `opaque_wake_v1`, deploy Redis migration state, or activate live push.

The following product decisions are recorded by the PRD addendum. This plan
preserves them but deliberately leaves their owning implementation to the
later named gaps:

- OQ-02: exact-conversation activation cleanup is generation-safe and
  independent of read; a final pre-publication check prevents stale A.
- OQ-03: `resumed` plus exact conversation visibility is sufficient for local
  read; no viewport, latest-row, or scroll machinery is introduced.
- OQ-04: read/unread, badge, notification cleanup, and outcomes are
  installation-local; a sibling device remains independent.

Plan 369 does not implement OQ-02/OQ-03. Until N04/N05/N11 provide their fresh
final-effect/read authority, current same-chat and read branches complete as
`terminalWithoutOutcome`; they cannot emit `inChat` or read-derived
`suppressedPolicy`. This conservative dependency is why the new producer and
combined capability remain default-off.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `27ea9a664ebf98d9`; current.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "N03 durable wake obligation authenticated wake_not_required completed local notification outcome NotificationPresentationResult linked-device installation-local exact visible conversation Plans 367 368" --profile tdd --budget 700`
- Anchors: `NotificationPresentationResult` ->
  `lib/core/notifications/notification_service.dart`; notification decision ->
  `lib/features/push/application/show_notification_use_case.dart`; direct/group
  display custody -> v107/v106 repositories and projection owners.
- Surfaced proof/gate files: `show_notification_use_case_test.dart`,
  `flutter_notification_service_test.dart`, direct/group display wiring tests,
  and the `1to1`/`groups` curated arrays.
- Graph gaps requiring source search: SQL transaction bodies, native replacement
  callback ordering, and relay protocol details; verified directly in source.
- Reuse rule: anchors may be handed to execution/review, but current-source and
  command evidence remain authoritative.

## Scope Contract And Guard

### In scope

- DB v116 adds one table, `notification_completed_outcome_outbox`, in the
  installation's identity SQLCipher database. It stores only:
  - a 64-character lowercase `wake_correlation` primary key;
  - local `outcome` in `in_chat | os_posted | suppressed_policy`;
  - revision, attempt count, bounded retry timestamps/error code, and immutable
    completion/creation timestamps plus a seven-day `expires_at`.
- The table is capped at 512 live rows per identity database. Insert first
  prunes expired rows. If capacity is still full, display custody completes as
  `terminalWithoutOutcome`; it does not retry the OS effect or evict any
  unexpired pending outcome. The generic wake therefore remains required.
- Freeze one cross-runtime correlation frame. Let `P` be the UTF-8 bytes of the
  exact canonical local physical libp2p peer-ID string and `E` the UTF-8 bytes
  of the exact authenticated event key. Both strings must be non-empty, valid
  UTF-8, and already canonical (no trimming or case folding). Hash:

  ```text
  uint32_be(len(D)) || D || uint32_be(len(P)) || P ||
  kind_byte || uint32_be(len(E)) || E
  D = ASCII("mknoon/wake-outcome/v1")
  ```

  where `kind_byte` is `0x01` direct message, `0x02` direct reaction,
  `0x03` group message, or `0x04` group reaction. The stored correlation is the
  lowercase 64-hex SHA-256. The event keys are respectively the authenticated
  direct `messageId`, raw authenticated direct `reactionId`, authenticated group
  `logicalDeliveryId` (fall back to exact authenticated `messageId` only for a
  legacy envelope where the field is absent), and raw authenticated group
  `notificationTransitionId`. Group `messageId` is otherwise excluded because
  alias custody may rekey it while `logicalDeliveryId` remains stable. Reaction
  keys are not bounded local notification/collapse identities, and no key is a
  push-route generation. Publish
  `test/shared/fixtures/wake_outcome_correlation_v1.json` with inputs,
  `preimageHex`, and digest for four real envelopes, including an alias group
  message and long reaction ID that would differ after local bounding. Dart in
  this plan and Go in Plan 370 consume that same fixture; neither hashes JSON.
- Resolve `P` from the incumbent secure physical transport identity authority:
  the primary installation uses its identity `peerId`; a linked secondary uses
  its linked credential `transportPeerId`. Never use the logical account ID or
  transient running P2P state. Missing, malformed, over-bound, or mismatched
  physical/event authority yields `terminalWithoutOutcome`; apply incumbent
  authenticated-envelope bounds and no trimming, normalization, or case folding.
- v116 has no historical backfill. An old terminal/display fact cannot prove a
  completed effect or mint a correlation after the fact.
- v116 is installation-local and is excluded from account migration/export and
  active import. A transferred identity must start with an empty outcome table;
  copying recipient-bound correlations to another physical installation would
  be inert at best and unsafe authority at worst. Add an explicit inventory and
  importer policy assertion rather than relying on the current copy-every-table
  loop. The snapshot exporter currently copies the full SQLCipher DB: erase only
  v116 rows from that exported copy before its integrity check, inventory, and
  checksum, while retaining the empty schema for a valid current-version
  snapshot. Never mutate the live source database. Active import must clear any
  pre-existing destination v116 rows before deliberately skipping transferred
  rows; “excluded” cannot leave stale target-installation authority behind.
- Extend the existing v107/v106 `completeIfExact` transaction seam to accept an
  optional typed outcome. When present, the transaction reselects every current
  READY comparand/revision, inserts the immutable outcome, writes the incumbent
  terminal fact, and deletes exact display custody together. Every canonical
  terminal `UPDATE`/append, including the currently unchecked group-message and
  group-reaction updates, must affect exactly one authorized row before the
  display row may be deleted. A stale CAS or database fault rolls the complete
  transaction back.
- Exact replay of the same correlation/outcome is idempotent. If a valid row
  already exists for the same correlation with a different approved category,
  the immutable first completed effect wins: do not overwrite or delete it,
  complete the exact display custody idempotently, and emit only a coarse
  `outcome_category_replay` diagnostic. Every approved category has the same
  wire meaning (`wakeNotRequired: true`), so a category race must not strand a
  card or create another protocol state.
- Split the lossy presentation result into five meanings:
  `osPosted`, `inChat`, `suppressedPolicy`, `terminalWithoutOutcome`, and
  `contendedRetryable`. Preserve concise compatibility helpers instead of
  teaching unrelated callers about the outbox. In this slice, `osPosted` is the
  only production-eligible outcome and only after the native/plugin callback
  returns normally. `inChat` and `suppressedPolicy` are reserved typed/schema
  values with no production emitter until their N04/N05/N11 authority exists.
- Carry an immutable `OutcomeCandidate?` with the projection disposition through
  both existing direct/group retry coordinators into
  `completeIfExact(expected, outcome: candidate)`. The candidate contains the
  physical recipient ID, producer kind, exact canonical event key, approved
  category, and completion time. Do not side-map candidates by event ID. On
  retry, reconstruct and revalidate those inputs from current canonical event
  state plus the secure identity authority before invoking the existing SQL
  transaction.
- Once the native/plugin callback returns normally, later recent-remote/dedupe
  bookkeeping failure must not erase the truthful `osPosted` candidate. Retain
  or log that bookkeeping residue separately. A callback-entered failure remains
  ambiguous and creates no outcome.
- Only canonical direct/group v107/v106 display owners may append the v116 row.
  The production append seam remains default-off until Plan 370 supplies the
  protocol/drainer and the combined capability is explicitly enabled.
- Add repository load/retry/complete-CAS methods so Plan 370 can drain rows
  without a new scheduler or database migration.
- Current blocked-direct and muted-group branches run before canonical v107/v106
  display custody, and `suppressNotification` is not typed authority. They stay
  `terminalWithoutOutcome`; do not widen staging or invent a second policy owner
  merely to populate the reserved `suppressedPolicy` value. N05/N06/N11 adopt
  that category once one shared final-policy authority exists.

### Must preserve

- Delivery/inbox ACK never creates or deletes a completed outcome ->
  `TC-369-05`.
- `suppressNotification`, recent-remote dedupe, committed/unavailable claim,
  stale/deleted/hidden/private residue, and unanchored compatibility fallbacks
  retire or retry without v116 insertion -> `TC-369-03` and `TC-369-05`.
- Android native callback entered then threw remains ambiguous: no completed
  outcome, no second publish -> `TC-369-03`.
- Sibling read/outcome state remains independent -> `TC-369-05`.
- Existing v106-v115 data, migration order, downgrade refusal, direct/group
  display retry, event claim, tone, and iOS handoff contracts remain green.

### Hard `Do not`

- Do not add the relay action, debounce coordinator, provider send, capability
  advertisement, or bridge fanout; Plan 370 owns them.
- Do not create direct/group/platform-specific outcome tables, a second display
  owner, worker, scheduler, service, protocol, or native callback writer.
- Do not turn v116 into the full PRD `LocalNotificationRecord`. N04-N06 still own
  fresh cross-isolate visibility, native effect owners, read/cancel/mute
  convergence, and the universal ledger.
- Do not let rich push fallbacks, NSE sidecars, dropped-FCM generations, generic
  delivery ACKs, or a missing event identity mint an outcome.
- Do not add viewport/scroll-to-latest requirements or cross-device clearing.
- Do not emit `suppressedPolicy` from blocked/muted/archive/missing membership,
  generic no-display eligibility, or a caller-supplied suppression reason in
  this slice.
- Do not add final pre-native abort, activation cleanup, read-trigger changes,
  lifecycle plumbing, or lease/registry APIs here. N04/N05/N11 own those
  corrections and are rollout prerequisites for `inChat`/read outcomes.

### Deferred / accepted difference

- N04: durable monotonic `AppVisibilitySnapshot` across Flutter/native owners.
- N05: universal final-effect/read/delete/mute gate in NSE, Android service,
  WorkManager, and reconciler.
- N06: full `LocalNotificationRecord` and cross-owner reconciliation.
- N07/N08: iOS/Android fixed-wake consumers and native outcome adoption.
- WP-07/GAP-N12: live capability activation, APNs/FCM, consolidated iOS, rollout,
  A-control, and release proof.

These deferrals mean only canonical Flutter display custody can create a v116
row in this slice. They do not require a third N03 plan.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-369-00 | Plan-368 receipt/marker/tree is valid and N02 controls remain default-off | dependency command above | host / checksum-bound final-tree receipt | no N03 dependency record -> exact validated transitive provenance | corrupt copied receipt SHA in a test fixture -> preflight red | exact command; no redundant N02 rerun |
| TC-369-01 | Fresh v116 and v115->v116 create one constrained, seven-day, 512-row-capped outbox; no backfill; production full-chain registry reaches v116; account migration deliberately exports an empty table and imports no installation-local rows; run twice/reopen/downgrade refuse | migration `TC-369-01 v116 outcome outbox is additive bounded and empty`; full-chain `TC-369-01 production registry reaches v116 exactly once`; account tests `TC-369-01 exported snapshot carries empty outcome authority`, `TC-369-01 migration inventory marks outcome installation local`, and `TC-369-01 active import never transfers completed outcomes`; seed both source and destination v116 rows, assert export empty/source unchanged/post-import destination empty | host SQLite + migration fixtures | current version 115/no table and full-copy exporter/importer -> version 116/table plus explicit no-transfer policy | drop registry step/correlation uniqueness/expiry, backfill a terminal row, export live rows, mutate source while sanitizing, preserve stale destination rows, or import sibling rows -> red | new migration path; exact account tests; justified `core-host-all` |
| TC-369-02 | Exact direct/group completion inserts an approved outcome and deletes custody atomically; all terminal writes are exact-one; stale/fault rolls back; a different approved-category replay preserves the immutable first row and completes | two direct/group top-level cases named `TC-369-02 exact display completion and outcome are one transaction` | real host SQLite / direct + group rows | completion only deletes custody -> one immutable outcome or explicit fail-safe no-outcome | split insert/delete, ignore zero-row group update, overwrite first category, or retry category replay forever -> red | shared core path; later core-host registration |
| TC-369-03 | Typed results distinguish OS callback success, reserved in-chat/policy, terminal-no-outcome, and retry; native ambiguity/replay/dedup/policy never qualifies; post-success bookkeeping failure still returns `osPosted` | `show_notification_use_case_test.dart::TC-369-03 only an approved completed effect carries an outcome` | host / fake plugin + native-boundary fake | `terminalSuppressed` conflates causes -> exact typed result and conservative no-outcome counterexamples | map recent-remote/same-chat/policy to outcome, lose native success after bookkeeping fault, or classify callback ambiguity -> red | pin existing test path in both curated arrays |
| TC-369-04 | One language-neutral four-envelope fixture freezes LP32BE peer/kind/raw-event framing, primary/linked physical identity, group alias logical-delivery identity, and raw-vs-bounded reaction behavior | `notification_completed_outcome_correlation_test.dart::TC-369-04 wake correlation byte contract is canonical and installation local` | host pure bytes + production parsers | no algorithm -> stable preimage/digest vectors | concatenate strings, trim/fold, use bounded reaction/group message ID, logical account, or omit peer -> red | shared core path; later core-host registration |
| TC-369-05 | Immutable candidates flow through both real retry coordinators; only canonical direct/group display owners append `osPosted`; delivery ACK, policy prefilters, compatibility paths, missing local identity, bypass presentation, and sibling install do not | `direct_notification_display_outbox_wiring_test.dart::TC-369-05 canonical display custody is the sole outcome producer` and `group_notification_display_outbox_wiring_test.dart::TC-369-05 canonical display custody is the sole outcome producer`, each proving enabled append and default-off zero | host real coordinator/owner wiring + repositories | coordinators carry disposition only -> exact optional candidate reaches atomic completion | side-map by event ID, let unanchored fallback append, emit policy before custody, or bind sibling identity -> red | incumbent direct/group curated paths |
| TC-369-06 | Repository `loadReady`, `recordRetryIfExact`, expiry/capacity, reopen, and `completeIfExact` are revision-exact; wrong revision or repository fault retains the row | `notification_completed_outcome_outbox_test.dart::TC-369-06 outcome repository is bounded and revision exact` | real host SQLite / direct repository calls | no durable row API -> bounded load/retry/exact completion | delete on retry disposition, accept wrong revision, or load expired row -> red | shared core path; later core/wave registration |

### Test notes

- `terminalWithoutOutcome` is a successful local display-custody disposition,
  not permission to send `wake_not_required`.
- Exactly nine focused top-level TC-369-01..06 host tests are planned: two for
  migration/registry TC-369-01, two for the direct/group atomic TC-369-02, one
  each for TC-369-03/04/06, and two direct/group TC-369-05 owners. Keep
  permutations inside those causal owners; zero
  selection or any skipped child is a gate failure.
- Three exact account-migration TC-369-01 owners run in their separate command,
  giving twelve planned host owners total without bloating the focused bundle.

## Implementation Steps

1. Snapshot `git status --short` and archive the Plan-368 prerequisite result.
   Record unrelated inherited changes; do not normalize the dirty tree.
2. Author TC-369-01/02 REDs. Add v116, registry/version wiring, the frozen
   correlation vectors, bounded outcome model/helper/repository, explicit
   account-transfer exclusion, and atomic direct/group completion APIs. Make
   every group terminal write exact-one and make invariant conflict/capacity
   complete safely without outcome. Stop if native code needs to open this
   table or if more than one table is proposed.
3. Author TC-369-03 RED. Replace the lossy result at the shared decision seam,
   preserving no-outcome classifications for same-chat/read, replay, dedup, and
   ambiguity. Do not change the native-boundary registry or lifecycle/read
   owners in this plan.
4. Author TC-369-04/05 REDs. Freeze/consume the language-neutral correlation
   fixture, carry immutable candidates through both incumbent retry coordinators,
   wire only exact `osPosted` through canonical direct/group display custody,
   and prove every policy/bypass path remains no-outcome.
5. Carry the optional outcome through the existing retry coordinator completion
   callback and atomically append only from canonical v106/v107 display owners.
   Keep the production append flag false until Plan 370 wires the authenticated
   drainer and combined capability.
6. Add load/retry/complete-CAS behavior and the exact exclusions in TC-369-06.
   Keep the inherited stale notification SQLCipher harness outside this plan;
   do not turn its unrelated v112/v113 expectations into N03 RED evidence or
   create a new mobile harness for an additive host-proven table.
7. Keep new `test/core/**` paths auto-registered for later core/wave gates. Add
   only the direct/group retry/wiring paths to their incumbent curated arrays,
   and pin `show_notification_use_case_test.dart` in `ONE_TO_ONE_TESTS` (it is
   already in groups). Run focused tests with concurrency 4, mutations
   sequentially, and curated lanes serially.
8. Run analyzer/diff/format hygiene, refresh the architecture graph once, and
   create a checksum-bound `Test-Flight-Improv/evidence/369/README.md` receipt.

## Risks And Blind Spots

- False outcome from a generic terminal branch -> explicit
  `terminalWithoutOutcome` counterexamples in TC-369-03/06.
- OS call ambiguity -> callback-entered failure is no-outcome and retains
  fail-closed ownership in TC-369-03.
- Outcome survives while display custody disappears -> one SQL transaction and
  rollback faults in TC-369-02.
- Imported/sibling row suppresses this installation -> recipient-bound
  correlation and sibling sentinel in TC-369-06.
- Global DB version changes but import/schema sentinels stay stale -> exact
  account-migration policy tests plus one justified `core-host-all`.
- Final lifecycle/read/native owners remain incomplete -> same-chat/read stay
  no-outcome, capability remains default-off, and N04-N11 deferrals are
  explicit; no N03 PRD/release claim is allowed.

## Gate Cadence

- Focused causal tests run as one Flutter command with `--concurrency=4` where
  files are independent. Mutation edits and database fault cases remain serial.
- Per-plan closure runs the focused bundle, exact v106/v107/event-claim/native/
  sibling sentinels and curated `1to1` and `groups` once each. The curated
  scripts are serial because they share Flutter/Go/Redis resources.
- One dart-only `core-host-all` is justified because v116 changes the global DB
  version and schema inventory/import reverse dependencies outside both curated
  arrays. No `feature-host-all`, performance family, or full `host-all` is
  justified.
- Full `host-all` runs once after the named N03-N06 shared
  lifecycle/ledger/outcome dependency wave, then once at final rollout/release.
- There is no notification UI, sound, APNs/FCM, two-peer, or iOS device leg.

## Device/Relay Proof Profile

- Profile: host-only local persistence/projection boundary.
- Phone/two-peer: N/A. GAP-N03 normally has no per-gap device gate, and this
  slice changes no native/plugin/provider behavior. Repeating an additive table
  assertion on the USB Android and emulator would add time without an
  independent causal boundary.
- The project rule still applies later: any N07/N08/native N03-wave phone proof
  must use the re-resolved USB Android plus Android emulator; unavailable targets
  are policy N/A. No iPhone is introduced here.

## Acceptance Gates

```bash
# Baseline and prerequisite.
set -euo pipefail
git status --short
command -v jq >/dev/null
plan369_gate_dir="$(mktemp -d /tmp/plan369-gates.XXXXXX)"
(
  set -euo pipefail
  cd Test-Flight-Improv/evidence/368
  shasum -a 256 -c README.md.sha256
  rg -x 'N02_OPAQUE_WAKE_MECHANISM_CODE_COMPLETE' README.md
  test "$(shasum -a 256 README.md | awk '{print $1}')" = \
    '0d6747b448a97103b750eaa275a37ded1cceeff096582b0fb05b15d1357ca5f1'
  git cat-file -e '924e8f64ebc7c9dca2de83890ecad144fefbdaf2^{tree}'
)

# After authoring the named test, prove one selected semantic RED before
# production edits. A missing test/file or zero selection is not RED evidence.
(
  set -uo pipefail
  red_status=0
  flutter test \
    test/core/database/migrations/116_notification_completed_outcome_outbox_test.dart \
    --plain-name 'TC-369-01 v116 outcome outbox is additive bounded and empty' \
    --file-reporter "json:$plan369_gate_dir/red.json" || red_status=$?
  test "$(jq -s '[.[] | select(.type == "testStart" and (.test.name | contains("TC-369-01")))] | length' "$plan369_gate_dir/red.json")" -eq 1
  test "$red_status" -ne 0
)

# Focused GREEN; exactly nine named host owners, bounded concurrency, zero skips.
(
  set -euo pipefail
  flutter test --concurrency=4 \
    test/core/database/migrations/116_notification_completed_outcome_outbox_test.dart \
    test/core/database/integration/full_migration_chain_test.dart \
    test/core/notifications/notification_completed_outcome_correlation_test.dart \
    test/core/notifications/notification_completed_outcome_outbox_test.dart \
    test/features/push/application/show_notification_use_case_test.dart \
    test/features/conversation/application/direct_notification_display_outbox_wiring_test.dart \
    test/features/groups/application/group_notification_display_outbox_wiring_test.dart \
    --name 'TC-369-0[1-6]' \
    --file-reporter "json:$plan369_gate_dir/focused.json"
  test "$(jq -s '[.[] | select(.type == "testStart" and (.test.name | test("TC-369-0[1-6]")))] | length' "$plan369_gate_dir/focused.json")" -eq 9
  test "$(jq -s '[.[] | select(.type == "testDone" and .skipped == true)] | length' "$plan369_gate_dir/focused.json")" -eq 0
)

# Five exact preservation sentinels outside the new causal owners.
(
  set -euo pipefail
  flutter test --concurrency=4 \
    test/core/notifications/durable_notification_tone_lease_test.dart \
    test/core/notifications/flutter_notification_service_test.dart \
    test/core/notifications/direct_group_notification_lane_isolation_test.dart \
    test/features/groups/integration/group_multi_device_convergence_test.dart \
    --name '^(typed message claim uses exact NSE filename and token-matched commit|honors claim and tone files written by the Swift NSE|typed group card disables Android auto-cancel and persists an exact payload generation|same ids remain notification kind and peer scoped|same-user multi-device convergence mute, unread, and local notifications stay device-local across joined sibling devices)$' \
    --file-reporter "json:$plan369_gate_dir/preservation.json"
  test "$(jq -s '[.[] | select(.type == "testStart" and .test.url != null)] | length' "$plan369_gate_dir/preservation.json")" -eq 5
  test "$(jq -s '[.[] | select(.type == "testDone" and .skipped == true)] | length' "$plan369_gate_dir/preservation.json")" -eq 0
)

# Curated lanes are deliberately serial and run once each.
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh groups

# Global schema/import policy is outside both curated arrays; run it exactly,
# then one justified core family (never full host-all).
flutter test --concurrency=2 \
  test/features/account_migration/application/migration_database_snapshot_exporter_test.dart \
  test/features/account_migration/application/migration_database_schema_inventory_test.dart \
  test/features/account_migration/application/migration_database_active_importer_test.dart \
  --name 'TC-369-01' \
  --file-reporter "json:$plan369_gate_dir/account.json"
test "$(jq -s '[.[] | select(.type == "testStart" and (.test.name | test("TC-369-01")))] | length' "$plan369_gate_dir/account.json")" -eq 3
test "$(jq -s '[.[] | select(.type == "testDone" and .skipped == true)] | length' "$plan369_gate_dir/account.json")" -eq 0
./scripts/run_host_test_gates.sh core-host-all \
  --batch-flutter --concurrency 4 --dart-only

# Hygiene and one coherent graph refresh.
while IFS= read -r path; do
  test -z "$path" || dart format --output=none --set-exit-if-changed "$path"
done < <(
  {
    git diff --name-only \
      924e8f64ebc7c9dca2de83890ecad144fefbdaf2 -- '*.dart'
    git ls-files --others --exclude-standard -- '*.dart'
  } | sort -u
)
flutter analyze
git diff --check
./graphify-arch/refresh_arch_graph.sh --incremental
```

For each of at least four representative mutations—non-atomic completion,
unchecked zero-row group terminal update, recent-remote promoted to outcome,
and correlation peer/kind framing removed—record the named test going red,
revert only the mutation, and rerun the focused GREEN bundle. Do not mutate the
user's unrelated dirty files.

## Execution Interpretation And Done Criteria

- Expected RED: TC-369-01 fails because DB v116/table do not exist; subsequent
  cases fail on the current collapsed terminal result and non-atomic completion.
- Green sentinel: exact direct/group display completion leaves either one
  immutable approved outcome or no outcome by explicit classification, never a
  partial transaction.
- Pre-existing dirty tree: Plans 364-368 and their implementation/evidence are
  inherited. Snapshot and preserve them; do not require a broad source commit.
- Environment blocker: host Flutter/Dart/SQLite tooling only. Device/S2/provider
  availability is irrelevant to this plan.
- Scope drift: native writer, relay action, additional table/worker/scheduler,
  per-screen activation callbacks, or capability activation blocks completion
  and requires re-review.

- [x] Plan-368 checksum/marker/tree preflight passes.
- [x] Every TC-369 behavior has a named causal test, and the four listed
      representative mutations re-red their owners.
- [x] v116 create/upgrade/reopen/downgrade and full migration-chain host proofs pass.
- [x] Only canonical v106/v107 display custody can append an outcome.
- [x] Replay/dedup/ambiguous/compatibility/delivery-ACK counterexamples append none.
- [x] Account migration/export/import never transfers installation-bound v116
      rows, and global version/schema sentinels are updated deliberately.
- [x] Same-chat/read remain explicit no-outcome until N04/N05/N11; no lifecycle,
      activation, viewport, or cross-device clearing scope leaked into this plan.
- [x] Focused, preservation, both curated lanes, exact account-migration tests,
      one justified dart-only `core-host-all`, analyzer/format/diff, and graph
      refresh pass; no feature/full-host sweep runs.
- [x] A checksum-bound frozen-tree receipt records retained logs or explicitly
      labels any non-retained attestation.

Done boundary: the checksum-valid
[`evidence/369` receipt](evidence/369/README.md) binds the final tested tree and
records `N03_DURABLE_LOCAL_OUTCOME_FOUNDATION_CODE_COMPLETE`. This is the
default-off local foundation only; Plan 370 still owns the authenticated relay
outcome/coordinator/drain, and full N03/live/PRD/release acceptance remains
open.

## Handoff

- Completion marker after a checksum-valid final-tree audit:
  `N03_DURABLE_LOCAL_OUTCOME_FOUNDATION_CODE_COMPLETE`.
- First causal RED: TC-369-01 command above.
- Preservation: exact v106/v107/event-claim/native-boundary/sibling bundle above.
- Manual registration: keep new core paths in the core/later-wave inventory;
  retain direct/group retry/wiring paths in their incumbent curated arrays; pin
  the existing show test in `ONE_TO_ONE_TESTS`.
- Migration: DB v116, no backfill, host SQLite/full-chain plus explicit
  account-export/import policy; no per-gap phone proof.
- Boundary closure: default-off Flutter/local foundation only. No relay action,
  native outcome writer, N03 PRD acceptance, live push, or release eligibility.
- Next plan: Plan 370 validates the receipt and supplies the only relay protocol,
  debounce coordinator, bridge fanout, and default-off combined capability.

The Plan-369 receipt must include these exact machine-readable identity lines
in addition to its sibling checksum and completion marker:

```text
Base HEAD: <40 lowercase hex>
Frozen tested tree: <40 lowercase hex>
Dirty snapshot SHA-256: <64 lowercase hex>
Graphify fingerprint: <16 lowercase hex>
```

Retain the gate logs, or label their hashes as non-retained attestations.

## Reviewer Findings

Independent `$tdd-review` counterexample passes initially rejected the broader
draft because it pulled final pre-native abort/read/activation work from
N04/N05/N11, tried to manufacture policy outcomes before canonical custody,
left correlation byte framing ambiguous, ignored zero-row group terminal
writes, and allowed a conflict/capacity path to strand display custody. The
revised contract removes those owners, reserves `inChat`/`suppressedPolicy`,
freezes the cross-runtime frame and raw reaction identity, requires exact-one
terminal writes, bounds the table, and makes conflict/capacity fail safely.

## Arbiter Decision

**PASS FOR EXECUTION after the Plan-368 preflight.** This is one bounded local
persistence/projection slice. It does not claim N03 behavior closure, add a
native owner, or create a third delivery structure. Plan 370 is its only N03
successor.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-15 | TC-369-00 prerequisite | `evidence/368/README.md`, sibling checksum, frozen tree | Checksum, exact marker, pinned receipt SHA, and tree object PASS | Plan-368 frozen tree `924e8f64ebc7c9dca2de83890ecad144fefbdaf2` | **PASS** | TC-369-01 RED |
| 2026-08-15 | Semantic RED | v116 migration owner | Selected TC-369-01 failed before the table/migration existed | One exact owner selected; raw output not retained | **Expected RED** | Implement bounded local authority |
| 2026-08-15 | Foundation GREEN | v116 model/correlation/repository; direct/group projection/completion; identity; account transfer | Focused exactly 9/9 PASS; preservation 5/5; account 3/3 | Typed exact authority, rollback, no-outcome counterexamples, and installation locality proven | **PASS** | Mutations and family gates |
| 2026-08-15 | Mutation audit | direct/group completion, presentation result, correlation | Four isolated mutations each re-red TC-369-02/03/04 and were reverted | Raw mutation logs explicitly non-retained | **PASS** | Curated lanes |
| 2026-08-15 | Curated/family gates | registered 1:1/groups/core surfaces | `1to1` +3261 ~10 PASS; `groups` +4201 PASS; dart-only core 412 paths / +3324 PASS / 0 skip/fail | Final authoritative logs hashed in receipt | **PASS** | Hygiene |
| 2026-08-15 | Hygiene and integration fanout | 68 changed Dart files; SQLCipher sentinels; runtime-root/DTR records | Format canonical; full analyzer `No issues found!`; diff clean; stale current-schema assertions repinned to v116 | No phone, feature/full-host, or full host-all gate required | **PASS** | Graph/freeze |
| 2026-08-15 | Graph/freeze/receipt | Graphify artifacts; alternate Git index; `evidence/369` | Current/anchored `ec9a45bfd76c0f40`; frozen tree `61e1b1935a022e7ad0f54d207549903a728e9b86`; receipt checksum PASS | Receipt SHA-256 `8d4229405b1b39ac26dd2304fa77455322be8b25c1b1f573a4903f0044d4873c` | **CLOSED AT DEFAULT-OFF LOCAL-FOUNDATION BOUNDARY** | Plan 370 TC-370-00 |
