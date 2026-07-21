# 266 - Group-Exit Failures Must Be Diagnosable In Release Builds

Status: implemented and acceptance-evidence complete 2026-07-21 (immutable Plan
264 and final Plan 265 handoffs consumed; all scoped host and available-device gates
passed)
Type: Bug + modification (release-safe diagnosability)
Spec: free-text intent from the 2026-07-20 field-debugging session — a release user
who cannot complete a group exit must see a short support code, and bounded evidence
must remain readable later without installing a debug build
Classification: closed
Closure tier: host application/database/widget proof plus one release-build,
real-SQLCipher proof on an available Android target
Boundary triggers: Flutter/Dart application, encrypted database migration, release UI,
proof-only Android release instrumentation, and device; no Go/native-handler behavior,
bridge wire-format, relay, or peer-topology change

## Planning Progress

| Time | Role | Files inspected | Decision / blocker | Next action |
|---|---|---|---|---|
| 2026-07-20 | Planner | Flow-event emitter, leave result, three exit surfaces, Go `GroupLeaveTopic` | Drafted raw-cause codes, a sanitized-string ring, and inline recovery | Re-ground against Plans 264/265 |
| 2026-07-21 | Evidence collector / planner | In-flight Plan 264 state/migration/runner, Plan 265 contract, leave bridge, Go node lifecycle, diagnostics/settings/DB surfaces, terminal-shell exits, gates, l10n, and current tests | Raw cause persistence, `Bridge.reinitialize()`, inline native retry, and a debug-section reuse are refuted; Plan 266 must consume typed outcomes after 264/265 | Freeze the bounded structured contract and run `$tdd-review` |
| 2026-07-21 | Baseline verifier | `flow_event_emitter_test.dart`, `settings_transport_diagnostics_card_test.dart` | Existing sanitizer/debug-diagnostics preservation baseline passed 12/12; it is not durable release-exit evidence | Keep it as a preservation sentinel, not the implementation seam |
| 2026-07-21 | Three independent reviewers | Final runner/coordinator entrypoints, same-id membership, terminal deletes, exit flow events, migration/account transfer, Settings composition, device proof, tests/gates | Initial `plan-fixes-required`: background bypasses, stale-intent correlation, multi-fact atomicity, live flow-event leaks, incomplete Settings wiring, and overclaimed process restart were causal blockers | Structural corrections applied in v3; retain prerequisite guard |

## Exact Problem And Grounded Evidence

- The release observability gap is narrower than v1 claimed. Ordinary flow-event
  printing is disabled by `flowEventLoggingEnabled = kDebugMode` in
  `lib/core/utils/flow_event_emitter.dart`, although an `FDC_FLOW_LOG` build override
  and separate push diagnostics exist. A normal production build therefore does not
  retain the group-exit cause for later support inspection.
- The current leave result exposes a coarse status and raw `Object? cause` in
  `lib/features/groups/application/leave_group_and_delete_local_history_use_case.dart`.
  Group Info and Orbit still collapse multiple failures into generic localized copy;
  current `BB-010 native leave failure stays on info screen and shows failed leave`
  proves that baseline. The in-flight Plan 264 workspace is changing those paths, so
  its transient symbols are evidence only, not an API this plan may edit or freeze.
- `BridgeCommandException` preserves structured `command`, `errorCode`, and optional
  `errorMessage` in `lib/core/bridge/bridge_group_helpers.dart`. The Go
  `GroupLeaveTopic` returns `NOT_INITIALIZED` when the node is absent. Only the typed
  code may be classified; neither `errorMessage` nor `toString()` is an allowlisted
  diagnostic value.
- `sanitizeFlowEventDetails` is a log-oriented key denylist. It does not generally
  redact arbitrary group ids, usernames, file paths, exception text, or bound string
  length. A combined rollback error can also wrap a typed bridge exception in a
  `StateError`. Persisting a "sanitized cause string" would therefore both leak and
  misclassify. This plan persists no raw cause or sanitized free text.
- Current Dart exit paths also emit raw group-id prefixes and/or `error.toString()`
  through `callGroupLeave`, Group Info, Group List, Orbit, the legacy leave use case,
  and dissolved-delete handling. The flow-event sink receives sanitized details even
  when printing is disabled, and the sanitizer does not remove every such value.
  Plan 266 must replace the final post-handoff exit-specific details with only public
  code/phase/severity; a repository-only privacy test is insufficient.
- `Bridge.reinitialize()` in `lib/core/bridge/go_bridge_client.dart` replaces Dart
  event-channel subscriptions; it does not start a Go node. Node startup requires the
  account/private-key/peer authority owned by `P2PServiceImpl`. Plan 266 must not call
  it as recovery. Go leave is idempotent, but Plan 264 already owns durable
  `native_leave_pending` retry and commit-unknown handling; Plan 266 must not issue a
  second `group:leave`.
- Plan 264's expected v103 `group_exit_intents` row is current action authority, not
  history: it has one bounded `last_error_code` and is deleted after membership-safe
  cleanup. Plan 266 requires a separate, bounded history that survives group and
  intent deletion. It must not overload `group_event_log`, which is an unbounded,
  identifier-bearing protocol/event chain.
- Existing settings diagnostics are session-only/debug-only. `_buildDebugSection()`
  in `settings_wired.dart` returns `null` outside debug builds and shares a slot with
  destructive-intro debug cards. Release exit diagnostics need a dedicated ordinary
  settings row; the debug guard and transport card remain unchanged.
- Plan 264 owns the durable role/notice/rotation/native/cleanup state machine and all
  active/stuck surface routing. Plan 265 decides which live publish, offline replay,
  and post-claim rotation faults become non-blocking degradations. Plan 266 observes
  their final typed outcomes; it does not reopen either policy.
- The in-flight runner is invoked through foreground requests, an unawaited queued
  kick, `processAll()` at recovery, runtime/rejoin callbacks, and resume/app-shell
  recovery. Several callers intentionally discard the returned result. Recording only
  in widgets or the foreground coordinator would miss real release failures. The final
  composition therefore needs one diagnosing processor/decorator at every processor
  entrypoint; widgets are presentation-only.
- The exit family also includes local deletion of a Plan 263 self-removed shell and a
  dissolved shell. Only their terminal local-cleanup failure is diagnostic here.
  `alreadyAbsent`, a state-race `refusedStateChanged`, and the dissolve/admin action
  itself are not failures owned by 266.
- Current live target discovery on 2026-07-21 found USB Android
  `21071FDF600CSC` (Pixel 6, API 36), Android emulators `emulator-5554` and
  `emulator-5556`, and available iOS targets. This plan needs one Android release
  proof, not two peers or iOS. Execution must rediscover and pin a currently available
  target; an unavailable target/version is `N/A (target unavailable by project
  policy)`, not a blocker.

Affected production areas after the prerequisite handoff:

- the accepted post-264 group-exit outcome/observation seam;
- a Plan-266-owned classifier/recorder and typed diagnostic model;
- one production-composed diagnosing processor, one disjoint application
  snapshot/action adapter, and application decorators for both terminal-shell delete
  operations; no widget writes diagnostics;
- expected DB v104 migration, helper, repository, and production registry/version;
- exit-specific flow-event scrubbing and shared failure-code presentation on Group
  Info, Orbit, the exit recovery projection, and Group List only if Plan 264 makes it
  production-reachable;
- one composition-root repository threaded through the full production Settings graph
  (`main`/restarted `StartupRouter` -> Feed/FTE/QR return -> `FeedWired` ->
  `OrbitWired` -> `SettingsWired`, plus main's direct Orbit) into a release-visible
  Settings row and sheet;
- full migration-chain and encrypted one-time Move Account compatibility;
- en/ar/de l10n, tests, group gate registration, and reliability discovery.

## Graph Grounding Snapshot

- Compact query:
  `python3 graphify-arch/tdd_context.py query "Plan 266 release group exit diagnosability: LeaveGroupAndDeleteLocalHistoryResult cause flowEventLoggingEnabled sanitizeFlowEventDetails GroupExitIntent last_error_code GroupExitIntentRunner group_info_wired group_list_wired orbit_wired Settings diagnostics NOT_INITIALIZED exact tests and GROUP_TESTS" --profile tdd --budget 700`.
- Graph fingerprint: `2cc83552c00316a9`; repository HEAD at planning time:
  `19dc1ca3a79277baa7079772352d77190d7c870b`.
- The graph was anchored but reported the in-flight
  `lib/features/groups/application/group_exit_intent_sink.dart` neighborhood stale,
  as expected while Plan 264 is being implemented elsewhere. No transient Plan 264
  symbol is accepted without post-handoff source verification.
- Stable anchors surfaced: `GROUP_TESTS` in `scripts/run_test_gates.sh`,
  `GroupExitIntentRunner`, and `LeaveGroupAndDeleteLocalHistoryResult`; targeted source
  verification supplied the settings, privacy, terminal-shell, l10n, and exact test
  selectors the compact graph did not contain.
- Execution must rerun the compact query with exact final 264/265 symbols. Use
  `--ensure-fresh` only after those changes are immutable and a fresh topology is
  actually required.

## Scope Contract And Guard

In scope:

- Introduce one exhaustive classifier at the final accepted exit boundary. Before it,
  one narrow bridge adapter converts `(command, allowlisted errorCode)` and typed
  timeout/uncertain outcomes into a Dart enum. Exact `group:leave` +
  `NOT_INITIALIZED` alone produces node-unavailable; `INVALID_INPUT`/`GROUP_ERROR` are
  explicit rejection; `INTERNAL_ERROR`/timeout/accepted commit-unknown outcomes are
  uncertain; an unknown command/code is `unexpected`. No free-text, `errorMessage`, or
  `toString()` parsing is permitted.
- Surface a short stable public code on every actionable exit failure. Persist every
  recordable failure and accepted degradation as structured allowlisted data even
  when flow logging is disabled. Expected policy controls and success are excluded.
- Compose one Plan-266-owned diagnosing processor/decorator as the only processor
  reference supplied to foreground, queued-unawaited, `processAll`, runtime/rejoin,
  resume, and app-shell entrypoints. It calls the accepted Plan-264 processor exactly
  once, observes every returned map entry exactly once, returns the identical result
  or error/stack, and submits diagnostics outside the runner's keyed tail. Surfaces
  only present returned/persisted facts and never append them.
- Compose one disjoint diagnosing snapshot/action adapter as the only production
  active/stuck Leave entry used by Group Info, Orbit, and Group List if reachable. It
  invokes the final Plan-264 identity/snapshot resolver and request/queue/retry action
  exactly once, returns their exact disposition/result, and observes only failures
  that return before any intent/processor observation: missing identity, snapshot or
  repository throw, pending-role drain throw, enqueue refusal, and final-handoff
  equivalents (EX01/EX02). Any result with an intent is left solely to the diagnosing
  processor, preventing foreground double observation. Pre-intent rows remain
  Settings history only and never drive recovery; widgets neither resolve authority
  independently nor append diagnostics.
- Add a bounded encrypted history with empty backfill. Rows survive deletion of the
  group and `group_exit_intents`, remain newest-first across database reopen, and can
  be cleared explicitly. Voluntary rows carry an opaque action reference so recovery
  cannot attach an old same-group failure to a new intent/membership.
- Use one shared presenter so equivalent typed outcomes have equivalent code/copy.
  The immutable handoff first freezes Plan 264's exact process -> request -> container
  navigation matrix; Plan 266 may add code/copy to that accepted container but may not
  turn `started`/`queued` into failure or change pop/sheet behavior. Recovery queries
  the current exact action reference, never only the group reference.
- Add a dedicated release-visible Settings preference. Loading and successful-empty
  hide the row; initial discovery error shows one fixed unavailable row because
  emptiness is unknown; nonempty shows the row. The sheet shows localized summary,
  timestamp, public code, and opaque group reference, and has explicit reload/clear
  success and failure states.
- Construct one repository at the database composition root and thread that identical
  instance through every production Settings route: root and restarted
  `StartupRouter`, its direct Feed and both FTE branches, FTE/QR return-to-Feed,
  Feed-to-Orbit, main's direct Orbit, and Orbit-to-Settings. Re-census after the 264
  handoff. `PostsWired` currently constructs Settings but has no `lib/` instantiation;
  keep it a preservation/dead component unless execution proves it production-live—do
  not create a route solely for 266.
- Wrap the application-level self-removed action (including identity/required-callback
  resolution) and strict dissolved-local-delete operation (including required
  repository availability). A pre-action production authority/wiring failure returns
  EX01 with zero delete; an invoked cleanup failure returns EX10. Each action invokes
  the destructive inner operation once, records before a widget mounted check can
  return, preserves the exact result or thrown error/stack, and never records
  `deleted`, `alreadyAbsent`, `refusedStateChanged`, or
  `deleteLocallyIfDissolved: false`. Source wiring makes missing production callbacks
  non-reachable; nullable test seams alone do not manufacture records.
- Replace raw identifiers/free-form errors at every reachable post-handoff Dart
  group-exit flow-event site with allowlisted public code/phase/severity only. Do not
  broaden the global sanitizer.

Must preserve:

- Plan 264 remains the sole writer of exit phases, retry policy, native calls, and
  membership-safe cleanup. A diagnostic failure cannot change an intent phase,
  convert a result, repeat a side effect, or block navigation/recovery.
- Plan 265's final blocking/degraded boundary remains authoritative. In particular,
  delivery/rotation degradation may produce `EX08`/`EX09` history while the leave
  result and immediate success UX stay successful.
- Last-admin guidance, expected pending-role queueing, explicit cancel, `alreadyAbsent`,
  `refusedStateChanged`, and ordinary success do not create false failure records.
- Every final Plan-264 request/process status keeps its accepted container and
  navigation behavior exactly. Uncertain and cleanup-incomplete semantics remain
  distinct; Group Info ordinary success still pops exactly once; conversation Info
  navigation and queued read-only state remain usable.
- Existing debug flow logging, sanitizer behavior, transport diagnostics, settings
  one-screen layout when no exit record exists, generated l10n, RTL, 2x text scale,
  and semantics/live-region conventions remain intact.

Hard `Do not`:

- Do not edit or test against Plan 264's moving production/test seams until its
  implementation and proof names are immutable. Do not treat the transient dirty
  workspace as the RED baseline.
- Do not call `Bridge.reinitialize()`, start the node, retry `group:leave`, advance or
  delete an intent, retry signing/delivery/rotation, or add another exit coordinator.
- Do not persist/display/log `cause.toString()`, exception text, stack traces, error
  messages, raw group/member/peer ids, names, paths, keys, payloads, or a generic
  sanitized map. Do not use a new runtime verbose-log toggle.
- Do not attach the recorder inside Plan 264's keyed membership tail, await diagnostic
  persistence before returning an exit result, let a detached Future escape uncaught,
  double-observe `processAll`, let the foreground action adapter observe a result with
  an intent, or let a widget append the same result again.
- Do not leave identity/snapshot resolution in a production widget beside the
  diagnosing action boundary, or let the action adapter change a Plan-264 disposition.
- Do not lift `_buildDebugSection()` out of `kDebugMode`, reuse `TransportMetrics` as
  durable history, append diagnostics to `group_event_log`, or add unbounded/exported
  logs.
- Do not add a foreign key/cascade from diagnostic rows to group/intent tables. Do not
  infer historical failures during migration.
- Do not change Go/native handlers, bridge commands or payloads, relay behavior,
  crypto, role/dissolve/invite policy, or require a second phone/iOS target.

Deferred:

- Admin role-change, invite, dissolve-transition, and non-exit errors may reuse the
  mechanism only under a separately reviewed plan. Plan 266 does not claim them.
- Support export/share/copy of diagnostic history, remote telemetry, support upload,
  verbose logging, retention configuration, and ongoing cross-device synchronization
  are out of scope. The existing encrypted one-time Move Account operation transfers
  the whole SQLCipher database; preserving the allowlisted table in a same-version
  move is an accepted compatibility requirement, not a support export feature.

## Frozen Public Vocabulary And Recordability

Codes are ASCII, stable, untranslated support identifiers. Localized prose explains
them; code interpolation in RTL is wrapped with Unicode LRI/PDI (`\u2066`/`\u2069`).
Changing a code meaning after release requires a new code, not semantic reuse.

| Public code | Typed meaning | Phase / severity | Record and immediate UI |
|---|---|---|---|
| `EX01` | Membership/identity/required production action or persistence authority could not be established | `authority` / failure | Persist when the application action can submit; show failure code; zero destructive call |
| `EX02` | Pending-role convergence or its retry failed, rather than merely being queued | `role_sync` / failure | Persist; show in recovery failure copy |
| `EX03` | Mandatory stable leave notice could not be prepared or durably committed | `notice` / failure | Persist; show in recovery/failure copy |
| `EX04` | Native bridge returned typed `NOT_INITIALIZED` | `native` / failure | Persist; show engine-unavailable copy; zero recovery calls from 266 |
| `EX05` | Native leave was explicitly rejected by allowlisted `INVALID_INPUT`/`GROUP_ERROR` or the final equivalent typed outcome | `native` / failure | Persist; show failure code in the accepted container |
| `EX06` | Native leave result is commit-unknown/uncertain | `native` / failure | Persist; show uncertain copy and code |
| `EX07` | Native leave committed but exact local cleanup is incomplete | `cleanup` / warning | Persist; append code to cleanup-incomplete copy |
| `EX08` | Signed leave-notice delivery is degraded under Plan 265 | `delivery` / warning | Persist; immediate leave remains success |
| `EX09` | Post-claim key rotation is deferred under Plan 265 | `rotation` / warning | Persist; immediate leave remains success |
| `EX10` | Self-removed or dissolved terminal shell could not complete local deletion | `local_delete` / failure | Persist; show local-delete failure code |
| `EX99` | Unknown command/code or otherwise recordable typed outcome has no recognized mapping | owning phase / failure | Persist fixed `unexpected` reason; never attach raw detail or silently treat it as EX05 |

Explicit non-records: `blockedLastAdmin`, an expected pending-role classification or
successful queue, cancel, no-op/already-running, ordinary `left`, `deleted`,
`alreadyAbsent`, `refusedStateChanged`, and user-dismissed UI. Repeated failed attempts
may each create one row because each is a user-observable event; the hard 20-row cap
prevents unbounded growth.

## Durable Data Contract

After the immutable handoff, execution reserves the actual next production migration
number. It is expected to be v104 because the in-flight Plan 264 currently reserves
v103. If v104 is occupied or Plan 264 lands a different version/registry shape, stop,
rename/rebase this entire migration and its proofs, and re-review before RED.

Expected `group_exit_diagnostics` columns:

| Column | Contract |
|---|---|
| `id INTEGER PRIMARY KEY` | Local ordering/identity only; no `sqlite_sequence` residue after Clear |
| `occurred_at TEXT NOT NULL` | Exactly 24 characters in canonical UTC millisecond form, e.g. `2026-07-21T09:03:00.000Z`; writer converts to UTC and round-trips through `millisecondsSinceEpoch` so ordinary nonzero microseconds truncate consistently |
| `group_ref TEXT NOT NULL` | Exactly 12 lowercase hex characters: truncated SHA-256 of the exact canonical repository group-id UTF-8 bytes, with no trim/case normalization; never the raw id/name |
| `intent_ref TEXT` | Post-enqueue voluntary rows: exactly 24 lowercase hex characters from SHA-256 of the exact Plan-264 intent id; exact pre-intent EX01/EX02 and terminal-shell rows: SQL `NULL`; never displayed |
| `exit_kind TEXT NOT NULL` | CHECK in `voluntary`, `self_removed_shell`, `dissolved_shell` |
| `severity TEXT NOT NULL` | CHECK in `failure`, `warning` |
| `phase TEXT NOT NULL` | CHECK in `authority`, `role_sync`, `notice`, `native`, `cleanup`, `delivery`, `rotation`, `local_delete` |
| `public_code TEXT NOT NULL` | CHECK in `EX01`..`EX10`, `EX99` |
| `reason_code TEXT NOT NULL` | CHECK in the finite internal set below |

`reason_code` is exactly one of `authority_unavailable`, `role_sync_failed`,
`notice_prepare_failed`, `node_not_initialized`, `native_rejected`,
`native_uncertain`, `cleanup_incomplete`, `notice_delivery_degraded`,
`rotation_deferred`, `terminal_shell_cleanup`, or `unexpected`. One exhaustive
composite table CHECK locks every allowed `(public_code, reason_code, phase, severity,
exit_kind, intent_ref-nullability)` tuple. It permits null voluntary action references
only for the exact final-handoff pre-intent EX01/EX02 variants and requires 24-hex for
every post-enqueue voluntary fact; direct inserts cannot manufacture a native warning,
terminal EX04, or voluntary EX10. Timestamp/group/action format checks reject
noncanonical or invalid characters. There is no payload/text/detail column, foreign
key, or group cascade.

The writer accepts ordinary `DateTime` values, converts to UTC, truncates through
`millisecondsSinceEpoch`, and then emits the 24-character form. Direct 27-character
microsecond, non-UTC, malformed, or impossible-tuple SQL inserts remain rejected.

One `appendOutcome(List<Diagnostic>)` transaction validates and inserts the complete
one-or-more fact set for a single processor outcome, then prunes once to the newest 20
by `id`; EX08+EX09 are therefore both committed or neither is. Readers return newest
first by `id`, not wall clock. Concurrent writers through separate handles still leave
at most 20 valid rows, including under clock rollback. Clear is idempotent and
linearizable with append: a batch committed before Clear is removed; a batch that
commits after Clear returns survives. Clear never resets or changes exit authority.
Migration backfill is empty, rerunnable, registered in create and upgrade chains, and
does not mutate v103/group rows. The diagnosing processor returns without awaiting the
submission Future; both synchronous/async write errors are caught with fixed safe
handling, and a never-completing writer cannot retain Plan 264's keyed tail or block a
later action. The in-memory public code is still presented when persistence is
unavailable.

Recovery lookup requires both the current row's exact `group_ref` and non-null
`intent_ref`; pre-intent null-reference rows are never candidates.
An old intent A diagnostic is never displayed for new intent/membership B; with only A
present, current recovery shows no code. Settings remains historical and may show both.
The whole encrypted table transfers during a same-v104 Move Account snapshot/import;
a v103 manifest is refused before active target rows are deleted or replaced.

## Dependencies And Execution Entry Guard

Hard prerequisites:

1. Plan 264 has an immutable accepted handoff: final migration number, exit intent
   phases, runner/coordinator result types, exact PB264 selector names, UI routing,
   bounded outcome vocabulary, exact processor interface/composition points,
   navigation matrix, and no active edits to the same files.
2. Plan 265 has a final `stale-already-covered` or accepted residual implementation
   disposition, with exact delivery/rotation degradation constants and tests. Plan
   266 must map that final vocabulary rather than the v1 `EX04 envelope-failed` guess.
3. The next database version and both production migration lists are re-verified free.

At execution start, record HEAD/status and create a handoff map from each public code
to one final typed source. If any source exists only as exception text or a single
overwritten `last_error_code` cannot distinguish concurrent delivery/rotation facts,
stop and amend/re-review the typed observation seam. Do not parse or guess.
The handoff map must also prove every raw runner reference is either the diagnosing
processor's private `inner` field or replaced at production composition. It must also
freeze the no-intent predicate at the process-wide action sink and classify Group List
as production only if Plan 264 actually made it reachable.

### Execution typed-handoff amendment (2026-07-21)

The immutable-handoff audit found that the accepted processor's
`status + intent + Object? cause` cannot distinguish queued authority failure from
queued notice preparation failure, or native identity failure from a structured
bridge result, without parsing raw exception data. Execution therefore freezes this
additional Plan-266-owned typed seam before accepting the first RED:

- The runner gains a diagnostic-aware execution envelope for both returned and thrown
  exits. It carries the exact intent snapshot, an immutable deduplicated fact list,
  and either the exact result or the original error plus stack. Normal processor calls
  replay that envelope, so accepted result/error/stack behavior is unchanged; the
  diagnosing decorator observes the envelope only after the keyed tail completes,
  submits outside it, and then returns or rethrows the identical value.
- `GroupExitIntentProcessResult` and mapped `GroupExitIntentRequestResult` carry the
  same immutable facts for immediate presentation and `processAll` map entries. The
  closed sources are authority unavailable, role-sync failed, notice preparation
  failed, native node unavailable, native rejected, native uncertain, cleanup
  incomplete, delivery degraded, rotation deferred, and unexpected. Every fact also
  carries its owning phase, so EX99 never guesses a phase. Expected controls set none.
- Facts are per processor invocation, not decoded from the final stored value on every
  retry. The runner accumulates EX08 only when a degraded notice completion commits
  and EX09 only when a rotation-deferred transition commits. Both commits in one pass
  produce one atomic `[EX08, EX09]` submission; a later native retry does not re-record
  either old fact. The accumulator survives later returned or thrown exits in that
  same invocation.
- Uncaught repository/lock/CAS paths set a typed phase fallback before the await, so
  the execution envelope retains a causal fact without wrapping or parsing the error.
  Notice prepare/commit/retry faults are EX03; a native-success persistence failure
  and any authority/cleanup failure after `cleanup_pending` are EX07; prepared-notice
  contract mismatch and genuinely unmapped typed branches are phase-bearing EX99.
- The native callback first resolves identity authority, then a narrow adapter maps
  only exact `BridgeCommandException.command/errorCode`, `TimeoutException`, and the
  accepted typed commit-unknown marker into a typed native outcome. Messages and
  `toString()` are never inputs. Identity failure remains authority, not native.
- Accepted Plan-265 `GroupExitPersistedOutcome` remains the durable transition source
  used to detect a newly committed delivery/rotation delta; its mere presence on a
  later intent snapshot is not a new diagnostic event.
- The diagnosing processor classifies only the closed per-invocation facts. It never
  interprets raw cause. Coordinator-owned drain throws and pre-enqueue
  identity/member/repository/enqueue refusals create typed EX02/EX01 facts directly;
  every coordinator mapping propagates processor facts, including successful
  `started`/`noOp` mappings that may carry newly committed warnings. The disjoint
  action adapter records only its typed null-intent snapshot/request facts; every
  intent-bearing result remains processor-owned.
- Terminal application adapters resolve identity/required production callbacks before
  invoking their inner destructive action. Pre-invocation authority failure is EX01
  with zero inner calls; an invoked self-removed/dissolved cleanup failure is EX10.
  Dissolved deletion exposes a typed state-refusal distinct from cleanup failure, so
  the expected swipe/dialog race remains a non-record without parsing `StateError`.

The initial PB266-01 missing-file compile probe run while this defect was being audited
is not accepted as causal RED evidence. Execution must obtain an independent READY
re-review of this amendment, then rerun PB266-01 against the frozen API before any
production implementation.

## Test Contract

Every row requires literal RED for the named reason on immutable execution HEAD,
GREEN, and a representative mutation re-red. If Plan 264/265 unexpectedly supplies an
equivalent assertion, map the exact selector and keep only the residual RED; do not
duplicate proof. The schema and release Settings behavior cannot be stale unless a
separately accepted implementation already owns them.

| Case | Behavior | Named test / proof | Tier / fixture | HEAD -> GREEN | Representative mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-266-01 | Exact bridge command/code and final typed outcomes map exhaustively without free-text parsing | `test/features/groups/application/group_exit_release_diagnostics_test.dart::PB266-01 allowlisted bridge and typed outcomes map without free-text parsing` | Host application; final 264/265 outcome table; `group:leave` error-code table; hostile messages/objects | Post-handoff compile/behavior RED -> exact `NOT_INITIALIZED`/known rejection/uncertain mappings, unknown command/code -> EX99, every non-record -> none; message text containing a code has no effect | Match message/`toString`, map unknown to EX05, or omit a typed outcome -> red | Exact test; new file once in `GROUP_TESTS`; AUTO feature family |
| TC-266-02 | `NOT_INITIALIZED` is `EX04` and observation causes no recovery or native side effect | Same file `::PB266-02 not initialized is diagnostic only and never reinitializes or retries leave` | Host; typed bridge error, command log, reinitialize/start spies | Current v1 contract would retry. GREEN shows engine copy data, one pre-existing native attempt total, and zero reinitialize/start/extra-leave calls | Add any recovery call or map by message text -> red | Exact test; same registration |
| TC-266-03 | Disjoint snapshot/action and processor observers cover every pre/post-intent entry exactly once; widgets never resolve/persist | `test/features/groups/application/group_exit_diagnostic_wiring_test.dart::PB266-03 disjoint observers cover snapshot pre-intent and every processor path once` | Host/source wiring; real missing identity, snapshot throw, role-drain throw, enqueue refusal, coordinator-repository throw, duplicate-suppression; raw-runner/recorder spies; queued-unawaited, `processAll`, runtime/rejoin, resume/app-shell | Compile/wiring RED -> each pre-intent failure creates one null-intent row with zero processor/native; each processor outcome/map entry observed once with post-intent ref; controls/success excluded; all production surfaces use action adapter, raw runner only wrapper inner, widget writes/resolvers absent | Remove action adapter, bypass snapshot, observe an intent result, route processor raw, double-observe map, allow post-intent null, or record queue/control -> red | Exact test; new file once in `GROUP_TESTS`; feature family |
| TC-266-04 | Detached diagnostic submission is non-authoritative, error-contained, and independent of flow logging | Application test `::PB266-04 pending or failed writer cannot retain exit authority or escape uncaught` | Host; `flowEventLoggingEnabled=false`; sync throw, async throw under captured zone, never-completing submitter; identical result/error-stack and two same-group calls | RED if write is awaited/uncaught. GREEN returns the exact result or error/stack, presents the code, lets the next same-group processor call run, changes no phase/command, and emits only fixed safe failure telemetry | Await writer inside keyed tail, omit async catch, require logging, or change result -> red | Exact test plus `flow_event_emitter_test.dart`; same application registration |
| TC-266-05 | Expected v104 schema/full chain and Move Account compatibility are exact | `test/core/database/migrations/104_group_exit_diagnostics_test.dart::PB266-05 v104 diagnostic schema constraints registry and empty rerun are exact`; `test/core/database/integration/full_migration_chain_test.dart::PB266-05 full create and v103 to v104 preserve predecessor state`; `test/features/account_migration/application/migration_database_active_importer_test.dart::PB266-05 same-v104 move transfers allowlisted diagnostics and v103 mismatch preserves target`; device companion below | Real SQLite v103 seed; both registries/create/upgrade/rerun; schema/CHECK/FK inspection; host active-import compatibility plus real-SQLCipher export/staged-open companion | Compile/schema RED -> exact v104 table, empty backfill, full chain, predecessor byte sentinels, host same-v104 replacement/mismatch safety; device companion proves encrypted transfer | Remove tuple/registry leg, infer rows, accept old manifest, drop rows on same-version move, or omit cipher companion -> red | New migration file once in `GROUP_TESTS`; exact shared tests; core + feature families; device companion |
| TC-266-06 | Helper atomically appends one outcome's 1..N facts, canonicalizes time, caps at 20, and linearizes append/clear | `test/core/database/helpers/group_exit_diagnostics_db_helpers_test.dart::PB266-06 diagnostic batches are atomic canonical bounded and clear-linearizable` | Real SQLite; nonzero sub-millisecond input; direct 27-char/non-UTC/invalid tuple/hex; EX08+EX09 fault; 25 nonmonotonic clocks; two handles/barriers; reopen; clear-before/after-append | Compile RED -> writer truncates via UTC milliseconds to 24 chars; batch all-or-none; newest 20 by id; direct malformed/cross-field rows rejected; no `sqlite_sequence`; frozen clear ordering | Reject ordinary microsecond `now`, keep 27 chars, insert facts separately, sort timestamp, accept wrong tuple/character, or lose after-clear append -> red | Exact test; new file once; `core-host-all` + groups |
| TC-266-07 | History survives cleanup while current recovery is scoped to the exact action, not stale same-group history | Helper/repository test `::PB266-07 cleanup preserves history and exact intent reference rejects stale membership diagnostics` | Real SQLite; intent A failure/cancel, same group re-entry + intent B, group/intent cleanup, DB reopen; terminal null-intent rows | RED before table -> history A/B survives without FK/raw IDs; recovery for B shows only B and shows none if only A exists; Settings may list both | Query only by group ref, add cascade, expose intent ref, or accept terminal/voluntary nullability mismatch -> red | Exact test; same helper/repository registration |
| TC-266-08 | Hostile details are absent from storage/rendering and every reachable Dart exit flow event | Repository test `::PB266-08 hostile cause identifiers paths and secrets never cross storage or rendering`; application/surface test `::PB266-08 exit flow events expose only allowlisted code phase and severity` | Host + real DB + enabled flow sink; drive bridge request, legacy/final leave, Info/List/Orbit, self-removed, and dissolved-delete failures with full-id/prefix/name/peer/path/key/error/stack/huge nested sentinels | Current flow-event RED -> only fixed event name plus code/phase/severity and opaque DB refs appear; all full/prefix/raw sentinels absent with logging false and true | Restore group-id prefix, `error.toString`, sanitized raw map, error message, or raw bridge code -> red | Exact new tests plus final reachable surface files; core/feature families + groups |
| TC-266-09 | Shared presentation adds codes without changing the immutable Plan-264 navigation/container matrix | `test/features/groups/presentation/group_info_wired_test.dart::PB266-09 Group Info codes every applicable outcome in its accepted container`; `test/features/orbit/presentation/screens/orbit_wired_test.dart::PB266-09 Orbit preserves the same route matrix and codes`; conditional Group List equivalent only if production-reachable | Widget; final process -> request -> container table; applicable EX01/04/05/06/07/99; navigation/command spies | Generic-copy RED -> exact code/copy parity in the already accepted snackbar/sheet/destination, while every `started`/`queued`/blocked/failure/success route and side-effect count remains semantic equivalent | Convert queued/started to failure, force failure-stays, hard-code one surface, omit EX99, or drop uncertain distinction -> red | Existing reachable files already once in `GROUP_TESTS`; `feature-host-all` |
| TC-266-10 | Fresh recovery presents EX02/EX03 and current post-intent codes only, scoped to the exact action | `test/features/groups/presentation/widgets/group_exit_recovery_sheet_test.dart::PB266-10 recreated recovery shows only current EX02 EX03 and retry code`; `test/features/groups/presentation/group_conversation_wired_test.dart::PB266-10 conversation reaches current coded recovery after remount` | Widget + real repository; create EX02/EX03 and retry failure through diagnosing paths (no diagnostic seed), close/reopen DB, dispose/remount; old A/new B; callback completers | RED -> exact EX02/EX03 copy plus B-only code, only-A/no-current shows none, announcement once, retry/cancel remains 264-owned, Info reachable, reads append nothing | Seed directly, omit EX02/03, query group-only, keep snackbar state, consume on read, or disable retry -> red | Existing files registered; `feature-host-all` + groups |
| TC-266-11 | Plan-265 delivery/rotation degradations commit as one atomic fact set without turning success into failure | Application/helper test `::PB266-11 delivery and rotation warnings commit together while leave remains successful` | Host; final combined outcome; injected failure between fact inserts; both fact orders; result/navigation spies | RED until final handoff -> EX08+EX09 both persist or neither; a successful result and accepted container remain unchanged | Split transactions, overwrite/drop one warning, map either to failure, or show failed-leave copy -> red | Exact test plus final PB265 selectors; application/helper registrations |
| TC-266-12 | Application terminal actions capture EX01/EX10 before unmount without changing strict-delete policy | `delete_self_removed_group_shell_use_case_test.dart::PB266-12 diagnosing self-removed action codes authority and cleanup once`; `delete_group_and_messages_use_case_test.dart::PB266-12 diagnosing dissolved local action preserves throw and records once` plus reachable surface selectors | Host/widget; missing identity/callback/repository, typed results, thrown error+stack, unmounted callback, `deleteLocallyIfDissolved` true/false, command/reload spies | RED -> pre-action production authority failure is EX01 with zero delete; cleanup failure records EX10 before mounted check; exact result/error/stack preserved; false/deleted/absent/state-race do not record; one delete and zero native leave | Persist only in widget, silently return on missing production authority, swallow/replace error, record false/race, retry delete, or invoke voluntary leave -> red | Self-removed file already once; add dissolved-delete file once to `GROUP_TESTS`; feature family |
| TC-266-13 | Production Settings wiring and loading/empty/error/list/clear states are explicit and race-safe | `test/features/settings/presentation/widgets/group_exit_diagnostics_sheet_test.dart::PB266-13 release Settings discovery and clear states are complete`; `test/features/orbit/presentation/screens/orbit_settings_entry_test.dart::PB266-13 full production Settings graph threads one diagnostic repository` | Widget/source wiring; identity spy from main through restarted StartupRouter, direct Feed, both FTE branches, FTE/QR returns, Feed->Orbit, direct Orbit, Orbit->Settings; loading/empty/initial-error/2 rows/sheet error/clear error/clear race | Compile/wiring RED -> the identical root repo reaches every live Settings path; `PostsWired` remains classified non-production; loading/empty hidden, initial error fixed row, nonempty newest-first, failures retain data, clear re-queries/preserves after-clear append, all outside debug | Replace one path with new/null repo, omit restart/FTE/QR/direct Orbit, silently count Posts as live, gate on debug, hide error, or lose after-clear append -> red | New sheet file once; existing Orbit source test already once; `feature-host-all` + groups |
| TC-266-14 | Every EX01-EX10/EX99 has localized presentation; RTL, semantics, 2x, generated API, and Settings states are preserved | Sheet test `::PB266-14 all exit codes are isolated announced and overflow safe in en ar de`; `test/l10n/orbit_strings_parity_test.dart`; `test/l10n/l10n_integrity_test.dart`; exact Settings T1/T5/T7 selectors | Widget/l10n; iterate full public vocabulary in en/ar/de; textScale 2; RTL; semantics; loading/empty/initial-error repositories | RED for new keys -> every code has fixed prose, ASCII code within LRI/PDI in RTL, live announcement, no overflow; loading/empty/error remain one-screen | Delete one code handler/isolate/live region/locale key or overflow error row -> red | Exact tests; existing l10n/settings registrations; feature family |
| TC-266-15 | A real encrypted release build closes/reopens SQLCipher, remounts Settings, and reads the durable code | `integration_test/group_exit_release_diagnostics_sqlcipher_proof_test.dart::PB266-15 release SQLCipher diagnostic survives database reopen and Settings remount` | One explicit pinned-device Android `connectedReleaseAndroidTest` release-instrumentation run; production callbacks/repository/navigation; fresh + v103 upgrade + wrong-key/downgrade/close-reopen/rerun; widget dispose/remount | Device compile/behavior RED -> `kDebugMode=false`, real cipher active, allowlisted batch survives DB reopen and Settings remount, hostile sentinels absent; no process-restart claim | Use memory/plain DB, debug-only entry, omit close/reopen/remount, or leak sentinel -> red | Add explicit `group` discovery record; device proof after host gates |

## Implementation Sequence

1. **Immutable preflight:** wait for Plan 264, record its accepted handoff, resolve Plan
   265, re-query Graphify, verify migration/version ownership, map every typed source,
   and rediscover devices. Touch nothing if any seam is still moving.
2. **First RED:** add only PB266-01 against the final outcome API and prove it fails
   because the typed classifier/public vocabulary is absent. Implement the pure
   bridge adapter/classifier/model; run mutation re-red.
3. **Observer policy RED/GREEN:** add PB266-02/03/04. Compose the disjoint
   identity/snapshot/action adapter across every production surface and the diagnosing
   processor at every processor entrypoint, outside Plan 264's keyed tail. Prove their
   exact predicate, exact-once observation, identical result/error, detached caught
   submission, zero widget authority resolution/writes, and duplicate suppression.
   Then add the terminal-delete decorators and scrub only reachable exit flow events.
4. **Migration and repository RED/GREEN:** reserve actual vNext; add the table,
   registry/version, helper, model, repository, intent scoping, atomic batch,
   cap/clear/privacy/survival proofs; run the full migration chain, historical terminal-
   version updates, and same-version Move Account compatibility before UI wiring.
5. **Shared presentation RED/GREEN:** build one localized presenter, wire the final
   Plan-264 production surfaces/recovery projection, and preserve its exact status-to-
   container navigation matrix, single-flight, and side-effect counts.
6. **Settings/l10n RED/GREEN:** construct one repository at the composition root and
   thread it through the entire StartupRouter/FTE/QR/Feed/Orbit -> Settings graph and
   main's direct Orbit path, including StartupRouter recreation. Add the
   frozen loading/empty/initial-error/list/sheet-error/clear-race states, en/ar/de
   keys/generated API, RTL isolates, semantics, 2x layout, and one-screen sentinels.
   Do not alter the debug section.
7. **Registration and closure:** add new causal tests exactly once to `GROUP_TESTS`,
   add the explicit reliability-discovery record, run focused/preservation/curated
   and justified family gates, then run the one release Android proof.
8. **Documentation:** record RED/GREEN/mutation/device evidence and limits. After this
   coherent app-owned change only, refresh `graphify-arch` incrementally once.

## Acceptance Gates

### 0. Prerequisite and stale-plan preflight

```bash
git rev-parse HEAD
git status --short
rg -n "Status:|PB264-(09|10|12|15|16|17)|native_leave_pending|cleanup_pending|last_error_code" \
  Test-Flight-Improv/264-pending-role-broadcast-convergence-tdd-plan.md
rg -n "Status:|stale-already-covered|PB265-|delivery|rotation" \
  Test-Flight-Improv/265-voluntary-leave-prework-degradation-tdd-plan.md
rg -n "currentIdentityDatabaseVersion|103_group_exit_intents|104_group_exit" \
  lib/core/database/app_database_version.dart \
  lib/core/database/production_migration_registry.dart \
  lib/core/database/migrations
rg -n "groupExitIntentRunner|processGroup\(|processAll\(|StartupRouter\(|FirstTimeExperienceWired\(|QrScannerWired\(|FeedWired\(|OrbitWired\(|SettingsWired\(" \
  lib/main.dart lib/features/identity/presentation/startup_router.dart \
  lib/features/home/presentation/screens/first_time_experience_wired.dart \
  lib/features/qr_code/presentation/screens/qr_scanner_wired.dart \
  lib/features/feed/presentation/screens/feed_wired.dart \
  lib/features/orbit/presentation/screens/orbit_wired.dart \
  lib/features/posts/presentation/screens/posts_wired.dart
python3 graphify-arch/tdd_context.py query \
  "Plan 266 final typed GroupExitIntentRunner and Plan 265 degradation outcomes into release diagnostics Settings" \
  --profile tdd --budget 700
flutter devices --machine
adb devices
xcrun simctl list devices available
```

Stop unless the 264 workspace is immutable, 265 has a final disposition, the typed
mapping is complete, and the database version is free. If 104 is not the next version,
rename/rebase every `104` artifact below and re-review.

### 1. Literal first RED

```bash
flutter test --no-pub \
  test/features/groups/application/group_exit_release_diagnostics_test.dart \
  --plain-name 'PB266-01 allowlisted bridge and typed outcomes map without free-text parsing'
```

Record the assertion/compile reason before production edits. A failure caused by
transient Plan-264 compilation or stale test fixtures is not accepted RED.

### 2. Focused application, database, repository, widget, l10n, and preservation proof

```bash
flutter test --no-pub \
  test/features/groups/application/group_exit_release_diagnostics_test.dart \
  test/features/groups/application/group_exit_diagnostic_wiring_test.dart \
  test/features/groups/application/delete_self_removed_group_shell_use_case_test.dart \
  test/features/groups/application/delete_group_and_messages_use_case_test.dart \
  test/core/database/migrations/104_group_exit_diagnostics_test.dart \
  test/core/database/helpers/group_exit_diagnostics_db_helpers_test.dart \
  test/features/groups/domain/repositories/group_exit_diagnostic_repository_impl_test.dart \
  test/features/settings/presentation/widgets/group_exit_diagnostics_sheet_test.dart

flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart \
  --plain-name 'PB266-05 full create and v103 to v104 preserve predecessor state'
flutter test --no-pub \
  test/features/account_migration/application/migration_database_active_importer_test.dart \
  --plain-name 'PB266-05 same-v104 move transfers allowlisted diagnostics and v103 mismatch preserves target'

flutter test --no-pub \
  test/features/groups/presentation/group_info_wired_test.dart \
  test/features/groups/presentation/group_list_wired_test.dart \
  test/features/orbit/presentation/screens/orbit_wired_test.dart \
  test/features/groups/presentation/widgets/group_exit_recovery_sheet_test.dart \
  test/features/groups/presentation/group_conversation_wired_test.dart \
  test/features/orbit/presentation/screens/orbit_settings_entry_test.dart

flutter test --no-pub \
  test/l10n/orbit_strings_parity_test.dart \
  test/l10n/l10n_integrity_test.dart \
  test/features/settings/presentation/screens/settings_one_screen_layout_test.dart \
  test/core/utils/flow_event_emitter_test.dart \
  test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart

flutter test --no-pub \
  test/core/database/migrations/102_groups_self_removed_at_test.dart \
  test/core/database/migrations/103_group_exit_intents_test.dart

flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart \
  --plain-name 'GCA-009 leave group deletes local messages and pops to first route'
flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart \
  --plain-name 'BB-010 native leave failure stays on info screen and shows failed leave'
flutter test --no-pub test/features/groups/presentation/group_list_wired_test.dart \
  --plain-name 'G2: "Leave" on a stuck group leaves it (group torn down, never silent)'
flutter test --no-pub test/features/orbit/presentation/screens/orbit_wired_test.dart \
  --plain-name 'active exit prework failure stays in group and shows localized retry'
flutter test --no-pub test/features/orbit/presentation/screens/orbit_wired_test.dart \
  --plain-name 'normal exit confirms once and last-admin race reopens guidance'
flutter test --no-pub test/features/groups/presentation/widgets/group_exit_recovery_sheet_test.dart \
  --plain-name 'retry failure leaves the recovery sheet operable'
flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'info button navigates to group info'
```

Re-anchor equivalent PB264/PB265 selector names from their accepted handoffs and run
PB264-09/10/12/15/16/17 plus every mapped PB265 degradation selector directly. Text
expectations may adopt the new code template; navigation, authority, ordering, retry,
and side-effect assertions may not weaken.

Update historical v102/v103 tests only so they preserve those migration boundaries:
the self-removed SQLCipher proof's first upgrade target becomes literal `102`, and the
exit-intent proof's first upgrade target becomes literal `103`; later reopens stay at
those versions. Relax only terminal-current/registry-last assertions for v104. Do not
weaken schema, empty-backfill, downgrade, or predecessor-row assertions.

### 3. Generated l10n, registration, analysis, and hygiene

```bash
flutter gen-l10n

for test_path in \
  test/features/groups/application/group_exit_release_diagnostics_test.dart \
  test/features/groups/application/group_exit_diagnostic_wiring_test.dart \
  test/core/database/migrations/104_group_exit_diagnostics_test.dart \
  test/core/database/helpers/group_exit_diagnostics_db_helpers_test.dart \
  test/features/groups/domain/repositories/group_exit_diagnostic_repository_impl_test.dart \
  test/features/settings/presentation/widgets/group_exit_diagnostics_sheet_test.dart \
  test/features/groups/application/delete_group_and_messages_use_case_test.dart \
  test/features/groups/application/delete_self_removed_group_shell_use_case_test.dart \
  test/features/orbit/presentation/screens/orbit_settings_entry_test.dart; do
  test "$(awk '/^readonly GROUP_TESTS=\(/,/^\)/' scripts/run_test_gates.sh | \
    rg -F -c "\"${test_path}\"")" -eq 1
done

./scripts/check_reliability_simulation_discovery.sh --records-tsv | \
  rg '^group\ttest\tintegration_test/group_exit_release_diagnostics_sqlcipher_proof_test\.dart\t'

flutter analyze --no-pub
git diff --check
```

Run `dart format --set-exit-if-changed` over the exact changed Dart files recorded by
execution; do not format or rewrite unrelated Plan-264 files.

### 4. Curated and justified family gates

```bash
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh core-host-all \
  --batch-flutter --concurrency 4 --reporter failures-only
./scripts/run_host_test_gates.sh feature-host-all \
  --batch-flutter --concurrency 4 --reporter failures-only
```

`core-host-all` is justified by a production migration/helper/repository boundary;
`feature-host-all` is justified by group and Settings production UI. Do not run full
`host-all` per plan. Plans 263-267 wave closure and final rollout/release closure own
that cadence.

### 5. Availability-bounded release device proof

Rediscover first and substitute one explicit available Android id. Flutter 3.41.4
rejects non-web `flutter drive --release` before build, so the implemented proof uses
Flutter's supported Android instrumentation path. The opt-in property selects the
release tested variant, includes/registers `integration_test` only in a disposable
proof package, and leaves ordinary application variants unchanged:

```bash
ANDROID_SERIAL=21071FDF600CSC ./android/gradlew -p android \
  :app:connectedReleaseAndroidTest --no-parallel \
  -PenableGroupExitReleaseDiagnosticsProof=true \
  -PdisableGoogleServicesForDisposableProof=true \
  -PandroidApplicationId=com.mknoon.app.pb266proof \
  -Ptarget="$PWD/integration_test/group_exit_release_diagnostics_sqlcipher_proof_test.dart" \
  -Ptarget-platform=android-arm64
```

The automated harness must create/upgrade through production SQLCipher callbacks,
inject a typed diagnostic through the production repository seam, close/reopen the
database, dispose/remount Settings, navigate through the ordinary production route,
assert `kDebugMode == false`, read the visible code, and prove hostile sentinels
absent. It does not claim an OS process restart.

Because v104 changes the terminal production version, run the two historical encrypted
migration proofs on the same explicit target after updating only their terminal-current
assumptions:

```bash
flutter test -d 21071FDF600CSC \
  integration_test/group_self_removed_marker_sqlcipher_proof_test.dart
flutter test -d 21071FDF600CSC \
  integration_test/group_exit_intents_sqlcipher_proof_test.dart
```

Extend the existing real Move Account SQLCipher capability fixture with an allowlisted
v104 diagnostic row and run its exact export -> transferred-key staged-open selector:

```bash
flutter test -d 21071FDF600CSC \
  integration_test/migration_database_sqlcipher_capability_test.dart \
  --plain-name 'PB266-05 real SQLCipher move export and staged open retain diagnostic row'
```

No manual taps, peer, relay, iPhone, or unavailable API-band leg is required. Record
all unavailable hardware legs as policy `N/A`, never as failed gates or environment
blockers.

### 6. Graph refresh after implementation only

```bash
./graphify-arch/refresh_arch_graph.sh --incremental
```

Do not refresh merely for this plan edit or while Plan 264 owns the moving graph.

## Device / Relay Proof Profile

- Boundary under proof: Flutter release compilation, production SQLCipher migration
  and persistence, database close/reopen, Settings dispose/remount, normal Settings
  reachability, and a real encrypted Move Account export/staged-open companion.
- Topology: one available Android target; no peer, account exchange, discovery, relay,
  or network transport is needed.
- Default current target: USB Pixel 6 `21071FDF600CSC`; execution rediscovery is
  authoritative. An available emulator may be used if no physical Android is present
  because the claim is database/release UI rather than hardware-specific behavior.
- Automation: pinned `connectedReleaseAndroidTest` with an AOT ARM64 release APK and
  disposable package; the harness owns setup, navigation, actions, database
  reopen/widget remount, assertions, and cleanup. No human interaction is evidence
  and no process-restart claim is made.
- Not claimed: Go-node restart, native leave success, two-peer convergence, relay
  delivery, background push, iOS parity, or any unavailable Android version.

## Proof Limits And Accepted Differences

- Host fakes prove exhaustive typed mapping, no extra side effects, recordability,
  presentation, and failure isolation. They do not prove a real native leave failure.
- Real SQLite proves schema/helper semantics; the Android release leg proves the
  production SQLCipher and normal-release UI boundary. Neither proves remote peers
  saw a leave notice.
- A database write failure cannot persist itself. The accepted behavior is to keep the
  public code visible in the current UI and never compromise exit authority; later
  Settings history is unavailable for that one event.
- A 12-hex SHA-256 prefix is a local encrypted correlation reference, not a group id or
  anonymity guarantee. It must never be joined to a displayed group name or included
  in support export/copy; it does remain inside an encrypted whole-database Move
  Account transfer.
- The non-displayed 24-hex intent reference prevents stale recovery projection; it is
  not an authorization token and Plan 264's exact intent/membership row remains the
  only action authority.
- The ring deliberately retains only the newest 20 observed events and Clear removes
  them. Older diagnostics are intentionally lost.
- A detached never-completing or failed write is deliberately unable to block exit
  authority. A process kill before its separate transaction commits can lose that
  diagnostic; the plan does not manufacture durability by coupling it to the exit
  transaction.
- EX08/EX09 can exist after a successful local leave because they describe degraded
  delivery/rotation, not failed local exit. The immediate success UX stays successful.
- The device proof demonstrates SQLCipher close/reopen and Settings remount inside one
  release test process, not an operating-system process relaunch.

## Completion Checklist

- [x] Plan 264's immutable handoff and Plan 265's final disposition are recorded; no
      overlapping session is active.
- [x] Actual vNext is reserved and migration/create/upgrade/rerun/SQLCipher proofs pass.
- [x] Every public code maps from one typed source; no string parser or raw detail
      crosses the diagnostic boundary.
- [x] Every foreground/background/runtime/rejoin/resume processor entry uses the one
      diagnosing decorator exactly once, outside Plan 264's keyed tail; widgets write
      no diagnostic rows.
- [x] Pre-intent foreground EX01/EX02 results use the disjoint action adapter with a
      null intent reference, zero processor/native calls, and no duplicate post-intent
      observation.
- [x] Every causal row has RED, GREEN, and mutation re-red (or an exact accepted
      equivalent mapping), with semantic assertions intact.
- [x] Complete 1..N outcome batches are atomic; rows survive cleanup, remain newest 20
      by id, scope recovery to exact intent, and linearize correctly with Clear.
- [x] Failure codes are shared across reachable surfaces; queued/restarted recovery and
      release Settings are readable; success/navigation/authority remain unchanged.
- [x] Privacy, en/ar/de, RTL isolates, semantics, 2x layout, and empty Settings layout
      pass.
- [x] Reachable exit-specific Dart flow events expose only code/phase/severity; same-
      v104 Move Account continuity and v103 mismatch refusal pass.
- [x] New tests are registered exactly once; focused, preservation, groups,
      `core-host-all`, and `feature-host-all` pass without per-plan full `host-all`.
- [x] One explicit available Android release/SQLCipher proof passes or is recorded as
      policy `N/A` because no target is available.
- [x] Scope Contract And Guard is respected and the architecture graph is refreshed
      incrementally once after implementation.

## Handoff

- First causal RED after immutable prerequisites:
  `flutter test --no-pub test/features/groups/application/group_exit_release_diagnostics_test.dart --plain-name 'PB266-01 allowlisted bridge and typed outcomes map without free-text parsing'`.
- Migration: expected v104 `group_exit_diagnostics`, empty backfill, no FK/cascade;
  actual vNext must be reserved after Plan 264.
- Manual registration: six new host test files plus the previously unregistered
  dissolved-delete causal file exactly once in `GROUP_TESTS`; existing self-removed,
  Orbit Settings, surface, and l10n files remain once; one explicit discovery record
  for the release device proof.
- Boundary closure: host application/database/widget + one availability-bounded
  release Android SQLCipher/UI proof. No Go/native/relay/two-peer claim.
- Resolved at execution: the accepted Plan-264 outcome/observer symbols and selectors,
  Plan-265 degradation facts/selectors, production reachability, and v104 reservation
  all matched the re-anchored preflight.

## Reviewer Findings

- Review date/profile: 2026-07-21, Graphify `review` profile followed by three
  independent read-only source/test/gate audits. The first broad query was refined to
  exact `_buildDebugSection`/`GroupExitIntentRunner` anchors; fingerprint
  `ba9346d8563d5ec7` remained stale at `lib/main.dart` because Plan 264 is active, so
  every blocking claim was verified directly and no transient API was frozen.
- Initial verdict: `plan-fixes-required`. Blocking counterexamples were raw-runner
  bypasses in queued/process-all/runtime/rejoin/resume paths; stale same-group history
  attaching to a new intent; partial EX08/EX09 persistence; a never-completing writer
  retaining authority; bridge-string wording that contradicted the structured string
  code; live exit flow-event leaks; incomplete terminal decorators; pair-only schema
  checks; contradictory Settings states/missing production wiring; absent full-chain
  and Move Account proof; and a one-process device test overclaiming process restart.
- Corrections applied in v3: one production-composed diagnosing processor outside the
  keyed tail plus a disjoint identity/snapshot/action adapter; presentation-only
  widgets; exact command/code adapter; opaque intent reference; atomic 1..N batches and clear race; complete tuple/timestamp checks with
  no AUTOINCREMENT residue; application terminal decorators; reachable Dart exit-flow
  scrubbing; inherited Plan-264 navigation matrix; explicit Settings discovery/clear
  states and all-path repository threading; full-chain/historical-version/Move Account
  gates; and a narrowed database-reopen/widget-remount release claim.
- The first correction re-audit found one residual pre-intent hole. The final pass
  added exact nullable EX01/EX02 tuples, Settings-only pre-intent history, full
  EX02/EX03 and EX01-EX10/EX99 presentation, and the real SQLCipher Move
  exporter/staged-open companion. All three reviewers then returned `READY` on the
  current file.
- Post-correction verdict: `ready` as a prerequisite-gated handoff/preflight plan, not
  ready for concurrent implementation. Execution must still stop and re-review if the
  immutable 264/265 outcome seam, navigation matrix, production reachability, or next
  database version differs from the recorded handoff.

## Execution Progress

| Time | Phase | Files | Last command / result | Current evidence | Decision / blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-21 | Immutable preflight | Plan 264/265 handoffs, migration registry, live devices, Graphify architecture graph | `HEAD=f9c2c597edb99d84972d8777844165520ade9cf9`; compact Graphify queries; `flutter devices --machine`; `adb devices`; `xcrun simctl list devices available` | Plan 264 and 265 accepted; v104 free; Pixel 6 `21071FDF600CSC`, Android emulators `emulator-5554`/`5556`, and iOS targets available | Entry guards satisfied; no concurrent owner | Capture literal RED |
| 2026-07-21 | Literal RED | `group_exit_release_diagnostics_test.dart` | PB266-01 exact command failed because the release diagnostic vocabulary/classifier file and symbols did not exist | Causal compile RED recorded before production implementation | Accepted RED | Implement typed boundary |
| 2026-07-21 | Typed application + persistence GREEN | Classifier/observer/decorators, v104 migration/helper/model/repository, production composition, terminal actions | Focused acceptance batch `+34`; full-chain PB266-05 `+1`; Move importer PB266-05 `+1`; historical v102/v103 host batch `+3` | Exact mapping, immutable/deduplicated batches, real keyed-tail/error replay, 20-row cap, clear linearization, cleanup survival, exact-intent scoping, and terminal diagnostics pass | GREEN | Prove presentation/preservation |
| 2026-07-21 | Presentation, Settings, l10n, privacy | Info/List/Orbit/recovery/conversation/Settings plus en/ar/de | Six-file presentation batch `+484`; l10n/privacy/Settings batch `+30`; seven exact PB264 selectors pass; PB264 application preservation `41/41`; PB265 preservation `40/40` | Existing navigation/container semantics preserved; EX01-EX10/EX99 visible; hostile details excluded; Settings production graph shares one repository | GREEN | Run family gates |
| 2026-07-21 | Registration + hygiene | Test gate registry, discovery registry, Dart sources | `flutter gen-l10n`; exact-once registration loop; discovery record; PB266-01..15 census; exact-file format check; `flutter analyze --no-pub`; `git diff --check` | Registration/discovery complete; formatter clean; analyzer initially zero issues | GREEN | Run curated/family gates |
| 2026-07-21 | Curated/family gates | Groups, core, feature | `groups`: 2,808 Flutter tests plus Go bridge/relay gates pass; `core-host-all`: initial legacy bridge telemetry assertion failed, exact assertion updated, rerun 2,728/2,728 across 345 paths plus renderer contract; `feature-host-all`: 8,478 pass, one declared skip, 820 paths | Only causal gate finding was stale expectation for the intentionally privacy-safe leave payload; production privacy sentinel remained green | GREEN after causal preservation fix; no per-plan `host-all` run | Run device proof |
| 2026-07-21 | Availability-bounded device proof | Release diagnostic integration target; v102/v103 SQLCipher proofs; Move Account SQLCipher fixture | Physical Pixel 6 `21071FDF600CSC`: `connectedReleaseAndroidTest` PB266-15 1/1; v102 1/1; v103 1/1; PB266-05 Move Account 1/1 | True signed ARM64 AOT release APK, real SQLCipher upgrade/reopen/wrong-key/downgrade, Settings remount, hostile-sentinel exclusion, historical boundary preservation, and transferred v104 row all pass | GREEN; `flutter drive --release` incompatibility replaced by supported release instrumentation | Final graph refresh and closure hygiene |
| 2026-07-21 | Closure | Final Dart/native hygiene and architecture graph | Four MainActivity/native source-contract files `+21`; renderer profile/release contract pass; PiP disposable test-APK contract pass; ordinary release excludes `integration_test`; final analyzer zero issues; `git diff --check`; `./graphify-arch/refresh_arch_graph.sh --incremental` | Graph refresh processed 28 changed code files and wrote 60,100 nodes / 91,625 edges; TDD overlay has 14,027 named tests and 1,076 production targets | All scoped acceptance evidence complete | Closed |
