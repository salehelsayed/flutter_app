# 267 - Group Invitation Send Lag

Status: evidence-gated (v3 reviewed 2026-07-21; Wave 0 harness work is ready,
production execution is `not-ready` pending the blockers below)
Type: Bug
Spec: free-text report from 2026-07-20: "I notice lagging in sending group
invitations, I don't know why."
Classification: evidence-gated
Closure tier: device (host causal proof plus paired-Android real bridge/relay
closure)

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-20 | Planner | `send_group_invite_use_case.dart`, `p2p_service_impl.dart`, `p2p_bridge_client.dart` | Current-build symptom retained; cause still hypothetical | Ground the complete UI/transport path |
| 2026-07-21 | Evidence Collector | Invite create/add/resend callers, P2P/bridge/Go timeout paths, invite receiver/dedup, tests, gates, Android device matrix | Confirmed an unbounded live-first tail and UI wait; refuted serial fanout; dominant real-device leg and duplicate-observability remain unresolved | Run the automated Wave 0 baseline before selecting H1/H2/H3/H4 |
| 2026-07-21 | Planner | Graph snapshot `ba9346d8563d5ec7`, current HEAD `19dc1ca3a792`, targeted host/Go sentinels | Plan is sufficient for evidence collection only; conditional fix contract is frozen below | Independent `$tdd-review` |
| 2026-07-21 | Reviewer | Review-profile graph query plus sender, receiver, native, runner, discovery, and device-boundary counterexamples | Verdict `not-ready`: Wave 0 contract tightened; production is blocked by late inbox-custody ambiguity, an unfrozen user-visible threshold, and mixed-version activation | Build and run Wave 0 only, record the evidence, then replan the selected production branch |

## Problem And Evidence

- Behavior to improve: creating a group with invitees or adding members from
  Group Info holds the foreground spinner while the complete invite batch
  settles. A slow recipient therefore makes invitation submission feel hung.
- Impact: the user cannot distinguish useful progress from a stalled send and
  may retry or abandon a group operation that has already committed membership.
- Confirmed structural cause/current gap:
  - `ContactPickerWired._inviteSelected` sets `_isInviting`, awaits
    `sendGroupInvitesInParallel`, records final attempts, and only then pops at
    `lib/features/groups/presentation/screens/contact_picker_wired.dart:284`,
    `:649`, `:664`, and `:687`; `ContactPickerScreen` renders an absorbing
    spinner at `contact_picker_screen.dart:97`.
  - `CreateGroupPickerWired._onStartGroup` similarly awaits
    `createGroupWithMembers` before navigation at
    `create_group_picker_wired.dart:176-204`; that use case awaits invite
    fanout and attempt persistence at
    `create_group_with_members_use_case.dart:345-380`.
  - Each target strictly awaits live `sendMessage` before inbox fallback at
    `send_group_invite_use_case.dart:385-445`. The Dart call supplies no
    timeout (`p2p_service_impl.dart:2355-2371`), so
    `callP2PMessageSend` is unbounded at
    `p2p_bridge_client.dart:1429-1445`; Go substitutes the 15-second background
    `SendTimeout` at `go-mknoon/node/config.go:32-38` and
    `go-mknoon/node/node.go:1602-1605`.
  - The 15 seconds is not one aggregate ceiling. Initial stream open, relay
    self-heal, retry open, and the post-open stream deadline can each consume
    time (`node.go:1531-1563`, `:1607-1633`).
  - Inbox fallback is also awaited and defaults to a 15-second Dart cap at
    `p2p_bridge_client.dart:738-767`.
- Existing coverage:
  - `sendGroupInvitesInParallel runs invites concurrently` proves a batch takes
    one slow-target interval rather than the sum; it passed on 2026-07-21.
  - `callP2PMessageSend ... returns BRIDGE_TIMEOUT ... (F5)` proves the existing
    non-null timeout seam; it passed on 2026-07-21.
  - `TestInteractiveAndBackgroundTimeoutProfilesRemainDistinct` and
    `TestConfig_TimeoutsMatchExecutedS1Verdict_NoRetime` lock the 3-second
    interactive send/inbox profile and passed on 2026-07-21.
  - Existing fallback coverage at
    `send_group_invite_use_case_test.dart:739-772` proves false live delivery
    uses the same encrypted envelope for inbox custody.
- Missing coverage: no current test makes a hung live invite fail for the UI
  contract; no correlated trace brackets pre-fanout, sign, encrypt, live,
  inbox, persistence, and UI settlement on both create and add-member paths;
  no test proves one recipient-visible event when a timed-out native send later
  overlaps inbox delivery.
- Refuted findings:
  - Multi-recipient invites are not serialized. The whole per-target
    sign/encrypt/send function is under `Future.wait` at
    `send_group_invite_use_case.dart:527-572`.
  - "Parallelize signing/encryption" is not a fix branch; those legs already run
    in parallel across targets.
  - Relay envelope-ID dedup does not prove UI/event dedup. Recipient storage is
    one replace/upsert row per group, but `group_invite_listener.dart:288-317`
    emits every successful store.
  - The unacknowledged-send behavior is not a HEAD defect:
    `P2PServiceImpl.sendMessage` already returns true only for an acknowledged
    send at `p2p_service_impl.dart:2367-2401`. TC-267-03 is therefore a
    transition sentinel for the proposed timeout-aware seam, not a causal RED.
  - The existing reliability runner does not register or run the proposed lag
    scenario: it parses only `-d`, ignores `--scenario` and `--baseline`, and
    hard-codes `MD004_SCENARIO=invite_reliability` at
    `run_invite_reliability_multi_device.dart:65-115`.
- Unresolved findings:
  - Which real leg dominates the reproduced current-build delay: pre-fanout
    membership/config work, crypto, live open/recovery/ACK, or inbox custody.
  - Whether a 3-second live budget preserves the observed online/cold success
    distribution.
  - Whether repeated same-ID processing produces duplicate user-visible
    notification/refresh behavior. This blocks any concurrent-custody or
    late-native-send strategy until TC-267-06 is GREEN.
  - A timed-out `storeInInbox` is not a confirmed failure. Account/wake-token
    work occurs before the bridge timeout, platform dispatch has no cancellation
    handle, and Go may continue to another relay candidate after Dart settles.
    The current attempt model cannot persist `unknown`, so a late successful
    custody can race a newly minted resend.
  - No product-approved user-visible create/add settlement threshold is frozen.
    The 3500 ms bridge cap is not an end-to-end UI budget.
  - A receiver-only same-ID guard shipped with concurrent sender delivery does
    not protect older recipients; activation/rollback ordering is unresolved.
- Affected production, test, and gate files:
  `send_group_invite_use_case.dart`,
  `record_group_invite_delivery_attempts.dart`,
  conditionally `handle_incoming_group_invite_use_case.dart` and
  `group_invite_listener.dart`, the invite host suites,
  `group_multi_device_real_harness.dart`,
  `run_invite_reliability_multi_device.dart`,
  `run_reliability_simulations.sh`, and `run_test_gates.sh`.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `ba9346d8563d5ec7`;
  `stale:lib/main.dart` (unrelated to the invite anchors).
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "267 group invitation send lag SendGroupInviteUseCase sendMessage callP2PMessageSend contact_picker_wired.dart delivery attempts GROUP_TESTS" --profile tdd --budget 700`.
- Anchors:
  `GROUP_TESTS -> scripts/run_test_gates.sh:348`;
  `contact_picker_wired.dart -> lib/features/groups/presentation/screens/contact_picker_wired.dart`;
  `callP2PMessageSend -> lib/core/bridge/p2p_bridge_client.dart:1408`.
- Surfaced proof/gate files:
  `contact_picker_wired_test.dart`,
  `contact_picker_multi_select_integration_test.dart`,
  `invite_round_trip_test.dart`, `run_test_gates.sh`, and
  `run_host_test_gates.sh`.
- Graph gaps requiring source search: the application use case, Go deadline
  accumulation, create/resend callers, receiver event dedup, and device runner
  scenario were verified directly because the compact result did not surface
  them.
- Reuse rule: anchors may be handed to review/execution; all conclusions still
  require current-source or command evidence.

## Scope Contract And Guard

In scope:
- Add phase-complete timing/discriminator evidence and a strictly parsed,
  artifact-validated `invite_send_latency` branch to the existing two-device
  invite runner.
- Replace the runner's shared-host-path assumption for Android with
  host-mediated per-device cache signal/artifact transfer, following the
  existing `adb shell run-as` pull/push precedent in
  `run_notification_sound_smoke.dart:193-289`.
- Run Wave 0 on the pinned Android pair before production edits.
- If and only if Wave 0 selects H1, stop for a scoped production replan that
  resolves TC-267-09 and freezes the user-visible caller threshold before any
  production RED or edit. The reviewed candidate must use ACK-aware live
  truth, one identical-envelope custody operation, first-positive rather than
  first-completion settlement, and an aggregate caller bound.
- Close authenticated-inner-ID, canonical-identical late-live/inbox event dedup
  before activating a sender design that can use both transports.

Must preserve:
- Acknowledged online direct delivery remains `success` and does not regress to
  `queued` -> TC-267-03.
- Fanout remains parallel and one slow target does not serialize the batch ->
  TC-267-04.
- Manual resend persists the exact newly minted invite ID and truthful status ->
  TC-267-05.
- Offline relay replay still decrypts and accepts the current rotated-epoch
  invite -> TC-267-08.
- A distinct newer invite ID for the same group still refreshes/replaces the
  pending invite; same-ID suppression must not suppress resend -> TC-267-06.

Hard `Do not`:
- Do not change global Go `SendTimeout`, `InboxTimeout`, wire envelopes, relay
  protocol, DB schema, or invite reuse policy in this plan.
- Do not treat `SendMessageResult.sent` as delivered without ACK/reply.
- Do not make navigation fire-and-forget before truthful delivery-attempt
  persistence; an attempt row is not a demonstrated delivery outbox.
- Do not claim serial fanout, exact-once notification, or native cancellation
  from a Dart `Future.timeout`.
- Do not map a timed-out inbox operation to confirmed non-delivery or allow a
  new-ID resend until the selected design has resolved/reconciled late native
  custody.
- Do not suppress all matching invite IDs: the existing same-ID but changed
  signed-metadata preview refresh must remain valid.
- Do not implement H1 when Wave 0 selects pre-fanout, crypto, or inbox
  dominance; stop and split the measured cause instead.

Deferred / accepted difference:
- H2 UI decoupling requires a crash-safe delivery outbox and revised optimistic
  copy/result semantics -> owner follow-up plan if Wave 0 selects pre-fanout/UI.
- H3 crypto warmup and H4 relay/server work -> separate owner plan only if the
  corresponding measured leg dominates.
- A third simultaneous recipient (`emulator-5556`) is optional confidence; it
  is not closure because host TC-267-04 proves mixed-batch parallelism.
- Existing delivered-vs-queued status may remain queued after a late native
  live success; accepted only if TC-267-06 proves one visible invite and the
  plan records the residual status semantics before GREEN.
- Process/app restart durability is not claimed by the current real harness;
  TC-267-07 proves a same-process node stop/restart with the same transport
  identity. A process-relaunch claim requires a durable pending repository and
  separate orchestration.

Dependencies:
- Existing timeout propagation and Dart settlement cap at
  `callP2PMessageSend`; existing 1:1 unknown-presence concurrent-inbox pattern
  at `send_chat_message_use_case.dart:801-951`; existing automated
  invite-reliability relay runner. These are precedents, not proof that inbox
  prework/native completion is aggregate-bounded or cancellable.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-267-01 | Wave 0 strictly runs five samples for every `create`/`add` × `online-warm`/`online-cold`/`offline` cell and attributes caller latency to correlated pre-fanout, sign, encrypt, live, inbox, persistence, and navigation settlement phases. | `test/integration/invite_reliability_runner_contract_test.dart::INV-267-R1 rejects unknown flags and validates the latency artifact`; `group_multi_device_real_harness.dart::MD-004 invite_send_latency baseline` | Host contract plus paired-device / real Go bridge, crypto, SQLCipher, and relay | HEAD ignores both new flags, hard-codes the old scenario, uses a non-shared host path on Android, and lacks complete phase evidence -> GREEN: strict parser plus host-mediated Android rendezvous produce a versioned artifact with scenario, mode, run ID, path/condition, operation/invite/recipient IDs, begin/end timestamps around each real await, connection state, envelope hash, ACK/transport, inbox count, attempt/pending IDs, caller settlement, and both role verdicts | Accept an unknown flag, omit/swap a phase delimiter, reuse another operation ID, skip either caller, or read target files directly through the host path -> host validator/device scenario red | Exact host test; `dart run integration_test/scripts/run_invite_reliability_multi_device.dart --scenario invite_send_latency --mode baseline -d 21071FDF600CSC,emulator-5554`; add host test to `GROUP_TESTS`; register the exact scenario in `run_reliability_simulations.sh` |
| TC-267-02 | Conditional only after the H1 replan: while live remains pending, exactly one identical-envelope custody operation starts; the first positive result can settle without releasing the other branch; every late loser is completed and cannot emit or persist a second terminal result. | `send_group_invite_use_case_test.dart::INV-267-01 hung live starts custody before live settlement and custody can win` | Application host / deterministic start barriers, completers, and virtual time | Causal RED: HEAD waits the unbounded live call before custody -> GREEN target is frozen only after TC-267-09 selects an ambiguity-safe outcome design | Move custody after even a bounded live result, create a second inbox future, release live to let the test proceed, or remove the one-settlement guard -> red | Exact direct test; `GROUP_TESTS` + AUTO `feature-host-all` after the H1 replan |
| TC-267-03 | ACK is wire-level success, not recipient persistence: live ACK first returns `success`; live unacked/negative waits for custody; custody negative waits for live; a confirmed custody positive returns `queued`; only the selected both-negative/expired contract may settle non-success. | `send_group_invite_use_case_test.dart::INV-267-02 delivery race settles first positive rather than first completion`; `::INV-267-03 acknowledged direct invite remains direct-only before the custody stagger` | Application host / captured `SendMessageResult` and custody fakes | The unacknowledged behavior is a GREEN HEAD sentinel because bool `sendMessage` is already ACK-aware; conditional race arms become GREEN only after the H1 replan | Decide from `.sent`, use naive `Future.any`, let a first false result win, or always deposit before a prompt ACK -> corresponding arm red | Same direct file commands; `GROUP_TESTS` + AUTO |
| TC-267-04 | Multi-target latency remains max-of-targets, not a sum, including one hung target. | `send_group_invite_use_case_test.dart::INV-267-04 batch deadline is one parallel bound, not N sequential bounds` | Application host / start barrier, completers, virtual time | GREEN sentinel for current `Future.wait` concurrency, while HEAD lacks bounded settlement -> GREEN: every target starts before release and the mixed batch settles in one logical aggregate budget | Replace `Future.wait` with sequential iteration or move crypto/send outside each mapped future -> red | Exact direct test; `GROUP_TESTS` + AUTO |
| TC-267-05 | Manual resend that receives confirmed custody persists `queued` with the exact envelope invite ID; an unresolved custody outcome cannot mint or send a replacement ID until TC-267-09 reconciliation permits it. | `resend_group_invite_use_case_test.dart::INV-267-05 confirmed custody persists exact id and unresolved custody blocks replacement` | Application host / in-memory repository and captured envelopes | HEAD can hang and has no unresolved-outcome contract -> GREEN target depends on TC-267-09; the confirmed-custody arm remains exact and null-error | Bypass `sendGroupInvite`, mint a second ID while unresolved, mismatch attempt/envelope IDs, or map confirmed queued to `needsResend` -> red | Exact direct test; add file to `GROUP_TESTS`; AUTO |
| TC-267-06 | Cross-transport replay of the same authenticated inner invite ID and canonical signed payload yields one pending row/event. The same ID with changed signed metadata and a distinct newer ID both refresh; an outer-ID collision/mismatch cannot suppress a different valid inner invite. | `group_invite_listener_test.dart::INV-267-06 canonical duplicate emits once while valid refreshes remain observable` | Host integration / serial listener queue, router, decrypt/verify, pending repository | Causal RED under overlap: HEAD saves/emits the canonical duplicate twice -> GREEN: comparison occurs only after decrypt/signature validation and suppresses canonical-identical payloads, not all equal IDs | Key on group ID, unauthenticated outer ID, or inner ID alone; remove the duplicate guard or either refresh arm -> red | Exact direct test; add file to `GROUP_TESTS` if overlap design selected; AUTO |
| TC-267-07 | After an absolute caller threshold is frozen, the paired-device closure proves: online wire ACK plus exact-ID recipient pending event; recipient node stopped before offline send, exact-ID confirmed custody, same-identity node restart/drain and one event; and a controlled delayed-live/inbox overlap followed by relay drain still emits once. | `group_multi_device_real_harness.dart::MD-004 invite_send_latency closure` | Paired-device / USB Pixel 6 + Android emulator, host-mediated signals, real bridge/crypto/relay | Device-only proof after TC-267-01 and the H1 replan; 3000 ms is a transport input, not the end-to-end oracle -> GREEN: every raw sample satisfies the separately frozen caller threshold plus tolerance and artifact invariants | Skip stopped-state proof, call an ACK application delivery, omit recipient ID/event, avoid inducing overlap, alter the ID, or replay a second event -> closure fails | `dart run integration_test/scripts/run_invite_reliability_multi_device.dart --scenario invite_send_latency --mode closure -d 21071FDF600CSC,emulator-5554`; exact registered scenario |
| TC-267-08 | Offline replay preserves current rotated-epoch invite acceptance. | `invite_round_trip_test.dart::offline removed member reconnects later from inbox-fallback re-invite on the rotated epoch` | GREEN sentinel / host integration fake relay | GREEN on HEAD -> remains GREEN after any selected scheduling/timeout change | Change fallback envelope bytes/key epoch or drop inbox replay -> red | Exact direct test; already in `GROUP_TESTS`; AUTO |
| TC-267-09 | A custody timeout cannot become a false terminal non-delivery that immediately authorizes a new-ID resend while native Go may still obtain relay custody. | Production replan must select and name either an aggregate cancellation/reconciliation proof or a persistable non-resendable `outcomeUnknown` proof, including late relay-candidate success | Application/core/native plus paired-device boundary as selected | BLOCKED: pre-bridge work is outside `timeoutMs`; Android/iOS work is non-cancellable; Go relay candidates consume separate budgets; persisted `unknown` is currently rejected -> no production GREEN target exists in this v3 plan | Let Dart timeout, persist ordinary `needsResend`, mint a new ID, then complete late custody successfully -> selected proof must red | New exact test(s), affected core/feature family gate, and device proof named by the required H1 replan |
| TC-267-10 | Concurrent sender activation is receiver-first and reversible: canonical dedup ships enabled before dual delivery; sender dual delivery remains disabled until an explicit mixed-version release decision, and rollback disables sender dual delivery without removing receiver dedup. | `send_group_invite_use_case_test.dart::INV-267-10 dual delivery obeys rollout gate`; release evidence records the accepted minimum-version/risk policy | Host policy sentinel plus release decision | BLOCKED: current/older receivers emit twice and no reviewed activation policy is selected -> production remains off | Enable sender race by default in the receiver-dedup release or couple rollback to removal of dedup -> red/release gate fails | Exact direct test after replan; release checklist; no wire/schema claim |

### Test Notes

- TC-267-01 records all five raw samples per cell plus median and max; no p95 is
  claimed from this small cohort. H1 is selected only when live is the largest
  exclusive phase in at least four of five repetitions of a reproduced slow
  cell and its median exceeds the existing 3000 ms interactive transport
  policy. Before a production RED, the evidence owner must append one absolute
  create/add caller-settlement threshold and scheduling tolerance; absence of
  that number keeps the production branch `not-ready`.
- TC-267-02/03/04 use completers, start barriers, and virtual time; a wall-clock
  `<N ms` host assertion is not causal proof. A bounded-but-serial live then
  inbox implementation must re-red TC-267-02.
- Direct success discriminator means wire ACK only. Application delivery is
  established separately by the exact-ID recipient pending-store/event in
  TC-267-07.
- TC-267-06 and the delayed-overlap leg are mandatory before any design that
  allows Dart settlement while native work can continue. The guard keys the
  authenticated decrypted payload, and relay dedup alone cannot satisfy it.
- TC-267-09 is a hard production stop, not an accepted flaky edge. `sendFailed`
  or `needsResend` may honestly mean "no confirmation", but neither may make a
  new-ID resend safe while late custody remains unreconciled.

## Evidence Decision Gate

1. Land only TC-267-01 instrumentation, strict runner/artifact validation,
   host-mediated Android rendezvous, and exact scenario registration. Preserve
   the existing `invite_reliability` scenario as its own registered row.
2. Preflight two live, distinct Android IDs and run all 30 baseline samples on
   current app/native/relay provenance. Append the artifact path, version/run
   ID, raw-sample digest, median/max table, and H1/H2/H3/H4 disposition here.
3. Select H1 only by the quantitative rule in Test Notes, with connection state
   recorded for each sample. Freeze an absolute create/add caller-settlement
   threshold and tolerance before writing a production RED.
4. An H1 disposition does not authorize production in this v3 plan. Replan
   TC-267-02/03/05/06/07/09/10 around an explicit late-custody outcome and
   mixed-version rollout decision; review that delta before production edits.
5. If pre-fanout work dominates, stop with H2; if sign/encrypt dominates, stop
   with H3; if inbox custody dominates, stop with H4. Split ownership instead
   of applying H1 rows.
6. If no slow cell reproduces and current HEAD satisfies the newly frozen
   user-visible contract, reclassify `stale-already-covered` and verify/close;
   do not fabricate production edits.

## Implementation Steps

1. Snapshot `git status --short` and preserve the existing unrelated Plans
   263-266/database/group work.
2. Write TC-267-R1 first. Extract strict runner argument parsing and versioned
   artifact validation into host-testable code; reject unknown flags and require
   scenario/mode compatibility. The host verdict must validate artifacts, not
   merely two process exit codes.
3. Add correlated create/add phase instrumentation around the actual awaits.
   Implement host-mediated per-device Android cache signal/artifact transfer,
   live/distinct-device preflight, and explicit node stop/restart signals.
4. Extend `run_reliability_simulations.sh` so both the preserved
   `invite_reliability` scenario and `invite_send_latency` are explicit rows;
   prove `path:invite_send_latency` is independently selectable in `--list`.
5. Run Wave 0 on the pinned Android pair and apply the Evidence Decision Gate.
   Stop after recording the disposition. Do not add a production timeout,
   race, receiver dedup, result state, or rollout flag in this v3 execution.
6. If H1 is selected, write the scoped replan required by TC-267-09/10. Only a
   newly reviewed plan may add the conditional host REDs and production edits.
   If another hypothesis is selected, split to that measured owner.

## Risks And Blind Spots

- A Dart timeout settles the caller but does not cancel Android/iOS native work
  -> TC-267-06/09 and the late-overlap device leg.
- Inbox prework is outside the bridge timeout and Go relay-candidate attempts
  are serial with per-candidate budgets; late confirmed custody after a sender
  timeout is the blocking counterexample, not an ordinary timeout failure.
- An aggressive deadline can convert a slow successful live ACK into custody ->
  Wave 0 online/cold distribution plus TC-267-03.
- A stale-connected peer can evade an unknown-presence-only policy -> Wave 0
  records structural connection and optional relay-presence state; the H1
  replan must own a stale-connected arm inside one aggregate caller budget.
- Inbox success can win while late live success leaves sender status `queued`
  -> accepted only with one visible recipient event and recorded residual
  semantics; no false `sent`.
- A wire ACK precedes invite decrypt/store; sender `sent` is not an
  application-delivery receipt -> exact-ID recipient evidence in TC-267-07.
- Lifecycle / derived-state durability: confirmed delivery-attempt state is
  persisted before caller settlement; unresolved custody cannot authorize
  resend; same-process node restart/drain is checked by TC-267-07.
- Same invite ID does not imply duplicate content: current same-ID changed
  metadata refreshes the preview -> canonical payload arms in TC-267-06.
- Mixed-version/rollback: older receivers do not suppress cross-transport
  repeats -> receiver-first disabled-sender rollout gate in TC-267-10.
- Sibling-surface consistency: create, add-member, and manual resend converge
  on `sendGroupInvite`; TC-267-01/05/07 cover the distinct callers.
- Harness portability: a host temp directory is not shared with USB/emulated
  Android targets -> host-mediated target-cache transfer in TC-267-01.
- Destructive-action side effects: N/A — no delete, cleanup, revoke, or cancel
  behavior changes.
- Invariant re-verification under new transitions: same-ID suppression
  re-verifies changed canonical content, a distinct newer resend ID, outer-ID
  mismatch, and exact invite ID in TC-267-05/06.

## Device/Relay Proof Profile

- Profile: paired-device.
- Wave 0 boundary: real Go bridge/crypto, relay custody, SQLCipher attempt
  persistence, connection provenance, and create/add caller settlement. Later
  production closure additionally owns native timeout settlement, node
  restart/drain, and cross-transport same-ID behavior.
- Live availability check:
  `flutter devices --machine`, `adb devices -l`, and
  `xcrun simctl list devices available` on 2026-07-21 found physical Pixel 6
  `21071FDF600CSC`, Android emulators `emulator-5554` (API 35) and
  `emulator-5556` (API 37), plus iOS targets. iOS is unnecessary because the
  behavior is not platform-specific.
- Required setup: sender = USB Pixel 6 `21071FDF600CSC`; recipient = Android
  emulator `emulator-5554`; existing real relay addresses; automated runner
  controls identity setup, node online/offline/restart, send, drain, and
  assertions with no user taps.
- Preflight: both exact IDs must be live, distinct, Android, and map to one USB
  physical device plus one emulator. Resolve again at execution time; an absent
  target is `N/A (target unavailable by project policy)`, never a request for an
  unavailable model/API band.
- Rendezvous: use target-local app cache paths and host-mediated `adb shell
  run-as` pull/push polling. Never pass one host temp path to both apps and
  assume target-side `dart:io` shares it.
- Two-peer default: the pinned physical Android + Android emulator pair above.
- Closure role: required closure evidence after the host causal rows.
- `FLUTTER_DEVICE_ID`: host selector only; the runner must receive both IDs.
- Registration: strictly parse `--scenario` and `--mode`; pass the selected
  values to the harness; retain `invite_reliability`; add both exact scenarios
  as rows in `run_reliability_simulations.sh`. Generic path classification by
  `check_reliability_simulation_discovery.sh` is necessary but insufficient.
- Discovery command:
  `./scripts/run_test_gates.sh reliability-sim group --list --only integration_test/scripts/run_invite_reliability_multi_device.dart:invite_send_latency`
  -> exactly the lag scenario is listed with exit 0.
- Baseline command:
  `dart run integration_test/scripts/run_invite_reliability_multi_device.dart --scenario invite_send_latency --mode baseline -d 21071FDF600CSC,emulator-5554`
  -> both roles exit 0 and the host validates all 30 samples plus a complete
  timing/disposition artifact.
- Closure command:
  `dart run integration_test/scripts/run_invite_reliability_multi_device.dart --scenario invite_send_latency --mode closure -d 21071FDF600CSC,emulator-5554`
  -> reserved for the reviewed production replan; both roles and host artifact
  validation must satisfy TC-267-07.
- Restart claim: node stop/start with the same transport identity only. The
  current harness's in-memory pending repository and teardown DB deletion do
  not prove app/process restart persistence.
- Deferred device work: optional `emulator-5556` third-peer mixed cohort; no
  unavailable version-specific target is a closure condition.

## Gate Cadence

- Wave 0 slice: exact runner-contract test, existing bridge/Go/concurrency
  sentinels, `./scripts/run_test_gates.sh groups`, exact reliability-scenario
  discovery, justified `feature-host-all` for app instrumentation, then the
  paired-device baseline. This may close evidence collection, not the bug.
- Later production closure: focused TC-267 tests named by the H1 replan,
  curated `groups`, the justified affected core/feature family sweep, and the
  paired-device closure. TC-267-09/10 must no longer be blocked.
- Do not run full `host-all` for this individual plan. Run
  `./scripts/run_host_test_gates.sh host-all` once after the Group Reliability
  Plans 263-267 dependency wave is complete, and once at final rollout/release
  closure.
- Shared tests outside feature/core globs: run the exact bridge and Go commands
  below; registration under later `host-all` does not make full `host-all` a
  per-plan obligation.

## Acceptance Gates

```bash
# Snapshot before Wave 0 or edits; record unrelated changes
git status --short

# Existing source-backed sentinels; expect exit 0 and zero failures
flutter test test/features/groups/application/send_group_invite_use_case_test.dart --plain-name 'runs invites concurrently'
flutter test test/core/bridge/p2p_bridge_client_test.dart --plain-name 'returns BRIDGE_TIMEOUT instead of hanging when the bridge never responds and a timeoutMs is set (F5)'
go -C go-mknoon test ./node -run 'TestInteractiveAndBackgroundTimeoutProfilesRemainDistinct|TestConfig_TimeoutsMatchExecutedS1Verdict_NoRetime' -count=1

# First Wave 0 causal RED on HEAD, then GREEN after runner/harness work
flutter test test/integration/invite_reliability_runner_contract_test.dart --plain-name 'INV-267-R1 rejects unknown flags and validates the latency artifact'

# Registration/discovery; expect the exact lag scenario, not the generic runner
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh reliability-sim group --list --only integration_test/scripts/run_invite_reliability_multi_device.dart:invite_send_latency

# Instrumentation/runner family preservation; expect exit 0 and zero failures
./scripts/run_host_test_gates.sh feature-host-all --batch-flutter --concurrency 4 --reporter failures-only

# Wave 0 only; expect two roles plus host validator exit 0 and all 30 samples
dart run integration_test/scripts/run_invite_reliability_multi_device.dart --scenario invite_send_latency --mode baseline -d 21071FDF600CSC,emulator-5554

# Existing preservation sentinel; expect exit 0
flutter test test/features/groups/integration/invite_round_trip_test.dart --plain-name 'offline removed member reconnects later from inbox-fallback re-invite on the rotated epoch'

# Production RED/GREEN and closure commands are intentionally N/A in v3.
# The reviewed H1/H2/H3/H4 replan must replace this note before production.

# Hygiene; expect no new analyzer issues and no whitespace errors
flutter analyze
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected Wave 0 RED: TC-267-R1 fails on HEAD because the runner ignores the
  scenario/mode flags, validates only role exit codes, lacks an artifact
  contract, and cannot rendezvous through one host path on Android.
- Deferred production RED: TC-267-02 would fail because `sendMessage` has no
  caller bound and custody cannot start while it is pending; TC-267-06 emits
  twice under overlap. Do not run/implement these until the required replan.
- Refuted RED: TC-267-03's unacknowledged arm is GREEN on HEAD production
  semantics because bool `sendMessage` already requires ACK.
- Green sentinel: acknowledged direct-only delivery, max-not-sum batch
  concurrency, bridge timeout propagation, Go timeout profile, and rotated
  offline replay.
- Pre-existing dirty tree / known failure: the 2026-07-21 tree already contains
  unrelated Plans 263-266, DB v102/v103, group reliability, integration harness,
  gate, and generated Graphify edits. A planning-time concurrent Flutter probe
  initially hit the shared startup/native-assets lock; the exact batch test
  passed when rerun alone. Neither is an expected RED.
- Environment blocker: none for the live matrix; both required Android targets
  exist. The current runner's filesystem/flag behavior is a code blocker owned
  by TC-267-01, not an unavailable-device waiver.
- Scope drift: any production timeout/race/dedup/result-state/rollout edit in
  this v3 Wave 0 slice, or any Go/global timeout, schema/wire, or UI
  fire-and-forget change, blocks completion and requires replanning.

- [ ] Strict runner/artifact RED, GREEN, and representative mutation re-red are
      recorded.
- [ ] Both exact scenarios remain registered and the lag row is independently
      selectable.
- [ ] All 30 Wave 0 samples, artifact digest, summaries, and H1/H2/H3/H4
      disposition are recorded.
- [ ] Existing sentinels plus curated/family/device Wave 0 gates pass.
- [ ] `flutter analyze` has no new issues; `git diff --check` is clean.
- [ ] No production delivery behavior changed in the Wave 0 slice.
- [ ] Bug closure remains unchecked until TC-267-09/10 are resolved by a
      reviewed production replan or evidence closes the report as stale.

## Handoff

- First causal RED command:
  `flutter test test/integration/invite_reliability_runner_contract_test.dart --plain-name 'INV-267-R1 rejects unknown flags and validates the latency artifact'`.
- First production RED: `N/A` in v3. If Wave 0 selects H1, the reviewed replan
  must name it after resolving TC-267-09/10 and freezing the caller threshold.
- Preservation command:
  `flutter test test/features/groups/integration/invite_round_trip_test.dart --plain-name 'offline removed member reconnects later from inbox-fallback re-invite on the rotated epoch'`.
- Manual registration: add the runner contract test to `GROUP_TESTS`; expand
  the reliability planner into preserved `invite_reliability` and new
  `invite_send_latency` rows. Host feature tests otherwise auto-glob.
- Migration: none for Wave 0. The production replan must decide whether the
  TC-267-09 outcome requires persistence/schema work; this plan does not grant
  that scope.
- Boundary evidence: paired Android real bridge/crypto/relay baseline on
  `21071FDF600CSC` + `emulator-5554`, fully automated through host-mediated
  target-cache signals.
- Unresolved evidence: dominant device leg, absolute caller threshold,
  late-inbox reconciliation, delayed-overlap device method, and mixed-version
  activation/rollback.

## Reviewer Findings

- Review verdict: `not-ready`.
- Disposition: `replan` after Wave 0; instrumentation/harness work only may
  proceed under this v3 plan.
- Review graph: profile `review`, fingerprint `ba9346d8563d5ec7`, freshness
  `stale:lib/main.dart` (unrelated to reviewed invite anchors).

| Lens | State | Durable finding |
|---|---|---|
| L1 Correctness / core bet | block | A Dart/inbox timeout cannot prove non-delivery; late native relay custody can follow a persisted failure and unsafe new-ID resend. |
| L2 Scope / design economy | tighten | The shared `sendGroupInvite` seam is narrow, but production must split/replan rather than widen this evidence slice into Go/global/UI changes. |
| L3 Causality / specificity | tighten | Phase evidence needs stable correlation, begin/end await brackets, both create/add callers, connection provenance, and a quantitative selection rule. |
| L4 Verification / counterexamples | block | The old scenario can satisfy ignored flags; generic discovery omits the lag row; a bounded-but-serial 6.5-second tail and naive `Future.any` can pass the old rows. |
| L5 Boundary / rollback | block | Host paths are not shared with Android targets; online ACK is not recipient persistence; offline restart and delayed overlap were unproven; older receivers duplicate events. |

Applied plan fixes:

- Reclassified TC-267-03's unacknowledged arm as a GREEN transition sentinel.
- Made runner parsing, artifact schema, Android host-mediated rendezvous,
  create/add sampling, exact scenario registration, and node-restart semantics
  explicit.
- Added first-positive/late-loser mutations, canonical authenticated invite
  dedup preservation arms, recipient exact-ID assertions, quantitative Wave 0
  sampling, and separate transport-policy versus UI-threshold language.
- Added hard production stops TC-267-09/10 for late custody and mixed-version
  activation instead of pretending the current result/rollout model is safe.

Refuted assumptions:

- Invite fanout is not serial; `Future.wait` already covers per-target work.
- Current bool `sendMessage` is not ACK-blind.
- Generic runner classification does not register `invite_send_latency`.
- The current host-temp rendezvous does not work across a USB Android and an
  emulator.
- Blanket same-ID suppression is invalid because same-ID changed signed
  metadata currently refreshes the pending preview.

Evergreen blind-spot hits: B-4 lifecycle/derived state, B-5 state-guarded
side effects, B-7 runtime topology, B-8 correlation/observability, and B-10
mixed-version/rollback. Destructive-action side effects are N/A.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-21 | planning/review | plan only | Existing invite concurrency, bridge timeout, and Go timeout-profile sentinels passed; reliability `--list` exposed only the generic runner | Source/host/device grounding complete; no device baseline run | Wave 0 code is planned; production is blocked by TC-267-09/10 and the unfrozen caller threshold | Implement TC-267-R1/instrumentation/runner registration, then capture Wave 0 |
