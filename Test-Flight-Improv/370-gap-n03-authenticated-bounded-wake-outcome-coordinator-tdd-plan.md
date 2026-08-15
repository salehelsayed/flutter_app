# 370 - GAP-N03 Authenticated Bounded Wake Outcome Coordinator

Status: **POST-EXECUTION AUDIT CLOSED / N03 WAKE OUTCOME COORDINATOR FOUNDATION CODE COMPLETE / N03 SLICE 2 OF 2 / HOST VERIFIED / DEFAULT-OFF / NOT N03-COMPLETE / LIVE-ACCEPTANCE-BLOCKED / NOT RELEASE-ELIGIBLE**
Type: Modification
Spec: `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2.md` §5.1, `WakeOutcomeAck`, race rules, A-13/A-24/A-26, and AC-04/AC-05; GAP-N03 / WP-03 in `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md`
Classification: implemented and post-execution-audited relay/protocol adopter; last N03-owned mechanism slice
Closure tier: deterministic Go/Dart host plus an independent-process Redis-protocol handoff fixture; no phone, live Redis/provider, full-host, deployment, activation, or release claim

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-15 | Evidence Collector | Plan-368 receipt; four relay adapters; direct/protected/group stores and ACKs; Redis backends; inbox stream auth; Go node/bridge fanout; Dart bridge and Plan-369 contract | All producers converge at one Plan-368 fixed-wake gateway. Delivery ACK deletes direct inbox rows, so a wake obligation cannot live on an inbox row. | Reuse one Redis authority and one gateway; add no payload queue. |
| 2026-08-15 | Planner using `$tdd-plan` | Graphify TDD context, capability defaults, route privacy, provider result handling, process-test and gate registration | A fixed 500 ms delay, one record family/due index/coordinator, one action, and one strict all-relay drain cover the causal boundary. | Wait for Plan 369's checksum-valid receipt, then author TC-370-01 RED. |
| 2026-08-15 | Independent reviewers using `$tdd-review` | Provider crash boundary, outcome-before-store order, route/capability races, mixed relays, restart ownership, drain composition, test discovery | Initial exact-once, absent-ACK, stored-route, any-success fanout, and real-Redis assumptions were unsound. | Replace them in this plan; do not add Plan 371. |
| 2026-08-15 | Prerequisite validator | Plan-369 receipt/checksum and machine identity fields; Plan-368 receipt/checksum | Plan 369's sibling checksum, exact completion marker, base HEAD, frozen tested tree, dirty snapshot, and Graphify fingerprint validate; Plan 368 remains checksum-valid. | TC-370-00 passes; begin TC-370-01 semantic RED against the frozen Plan-369 API. |
| 2026-08-15 | Post-execution auditor | Frozen 36-path source/test/script/runtime-root/Graph surface; exact causal, mutation, preservation, curated, relay, hygiene, analyzer, and graph receipts | The single paired default-false seam gates both capabilities, both producers, and the drainer; Redis is the durable owner, memory is immediate/terminal non-owner, and recovery is at-least-once. | Bind the final tested tree in `evidence/370`; leave full N03, live acceptance, activation, and release open. |

## Problem And Evidence

- Relay stores currently launch push immediately after a genuinely new durable
  event. There is no bounded interval in which the authenticated recipient can
  prove that the exact local effect completed.
- All four adapters converge through `sendSelectedPushThroughGateway` and
  `mailboxDirty` in `go-relay-server/inbox.go` and `opaque_wake.go`.
- `inboxRequest`/`HandleInboxStream` have no outcome action; `remotePeer` is
  already the authenticated subject.
- Delivery ACK may delete direct inbox rows. It must not cancel a distinct wake
  recovery obligation.
- `sendWithRetry` is currently void and the shared gateway returns success after
  attempting a provider regardless of accepted, permanent, unavailable, or
  exhausted-retry disposition. Redis therefore cannot make the external
  APNs/FCM submission exactly once.
- Direct delivery can complete before the corresponding relay store. Treating an
  absent outcome as a terminal no-op loses that race and causes a later needless
  wake.
- `RelaySelector.FanOut` has any-success semantics. Reusing it for outcome rows
  could delete local v116 authority while the relay that owns the obligation was
  unreachable.
- Plan 368 already owns provider bytes, collapse identifiers, route resolution,
  stale handling, revoke, and privacy. This plan extends that one gateway; it
  does not create a second push service.

Primary production/test/gate files:

- new `go-relay-server/wake_outcome.go`
- `go-relay-server/inbox.go`, `inbox_store.go`, `backend_redis.go`,
  `ack_custody.go`, `opaque_wake.go`, and `server_bootstrap.go`
- new relay closure and tagged independent-process tests
- `go-mknoon/node/inbox.go`, `node/relay_selector.go`, and
  `go-mknoon/bridge/bridge.go`
- `lib/core/bridge/p2p_bridge_client.dart`, `go_bridge_client.dart`, the
  Plan-369 repository, and the incumbent retry/lifecycle composition owner
- `test/shared/fixtures/wake_outcome_correlation_v1.json` from Plan 369
- new `test/core/notifications/notification_completed_outcome_drain_composition_test.dart`
- `lib/core/services/pending_message_retrier.dart`,
  `lib/app/bootstrap/production_application_bootstrap.dart`,
  `lib/app/lifecycle/handle_app_resumed.dart`, and
  `lib/app/application_root.dart`, plus their exact existing test owners
- focused Go/Dart tests and existing gate scripts

## Dependency Contract

Plan 370's two causal prerequisites are now checksum-valid:

1. Plan 368's N02 fixed opaque-wake gateway, receipt SHA-256 `0d6747b448a97103b750eaa275a37ded1cceeff096582b0fb05b15d1357ca5f1`; and
2. Plan 369's canonical local completed-outcome foundation, receipt SHA-256 `8d4229405b1b39ac26dd2304fa77455322be8b25c1b1f573a4903f0044d4873c`.

The verified Plan-369 receipt at
`Test-Flight-Improv/evidence/369/README.md` records:

```text
N03_DURABLE_LOCAL_OUTCOME_FOUNDATION_CODE_COMPLETE
Base HEAD: 8d86501e46f1a06e724daf8009cd3bf0f807578c
Frozen tested tree: 61e1b1935a022e7ad0f54d207549903a728e9b86
Dirty snapshot SHA-256: ff0c29a6e3ea5ed013aeb147b589c34de74b9131fce0d700e8c1f4d4b360f96b
Graphify fingerprint: ec9a45bfd76c0f40
```

Its sibling checksum binds the v116 migration, atomic direct/group completion,
physical/event correlation and identity qualification, account-transfer
exclusion, mutations, preservation/curated/account/core gates, analyzer,
format/diff hygiene, and Graphify refresh. Plan 369 correctly had no phone gate.
The executable checksum/marker/shape preflight remains below and is TC-370-00.

```bash
(
  set -euo pipefail
  cd Test-Flight-Improv/evidence/369
  shasum -a 256 -c README.md.sha256
  rg -x 'N03_DURABLE_LOCAL_OUTCOME_FOUNDATION_CODE_COMPLETE' README.md
  rg -q '^Base HEAD: [0-9a-f]{40}$' README.md
  rg -q '^Frozen tested tree: [0-9a-f]{40}$' README.md
  rg -q '^Dirty snapshot SHA-256: [0-9a-f]{64}$' README.md
  rg -q '^Graphify fingerprint: [0-9a-f]{16}$' README.md
)
(
  set -euo pipefail
  cd Test-Flight-Improv/evidence/368
  shasum -a 256 -c README.md.sha256
  rg -x 'N02_OPAQUE_WAKE_MECHANISM_CODE_COMPLETE' README.md
)
```

Plan 368 transitively binds Plan 367 and Plan 366/N01. Do not add duplicate
Plan-366/367 preflights. N01 live S2/B1b, N02 live migration/provider activation,
and release acceptance are not prerequisites.

## Graph Grounding Snapshot

- Planning/review fingerprint: `27ea9a664ebf98d9`; both compact review queries
  returned `confidence=anchored`, `freshness=current`.
- TDD query:
  `python3 graphify-arch/tdd_context.py query "N03 wake outcome relay debounce inbox store delivery ack all four push adapters Redis authenticated remotePeer bridge fanout" --profile tdd --budget 700`
- Review query:
  `python3 graphify-arch/tdd_context.py query "Plan 370 wake outcome counterexamples provider exact once outcome before store Redis route capability relay fanout" --profile review --budget 800`
- Anchors: `inboxRequest`, `HandleInboxStream`,
  `sendSelectedPushThroughGateway`, Redis store transactions, opaque route
  resolution, node relay selection, and bridge fanout.
- Targeted source inspection verified transaction/result/fanout semantics. The
  full fallback graph was unnecessary.

## Scope Contract And Guard

### Admission and fallback

- Add one exact capability, `wake_outcome_v1`. Delay is admitted only when the
  incumbent producer has already approved the recipient and an exact current
  route satisfies all of:
  - Plan 368's opaque classifier: non-empty encrypted handle plus
    `opaque_wake_v1`;
  - `wake_outcome_v1`;
  - the incumbent producer requirement (`none`, `direct_reaction_v1`, or
    `group_reaction_v1`);
  - stable Plan-369 correlation; and
  - durable Redis transaction support.
- The preflight route lease is WATCH/transaction-validated with the event row and
  obligation commit, including handle, generation, canonical capabilities, and
  directory source guard. If capability/route state changes before commit, retry
  selection once; if it no longer qualifies, commit the event without an
  obligation and run the exact incumbent immediate post-store behavior.
- Do not persist the private route `lookupKey`, provider token, or a provider
  target in the obligation. At due/retry time perform one fresh Plan-368 route
  selection. It must still satisfy the opaque classifier and incumbent reaction
  policy; `wake_outcome_v1` is no longer required once delay was durably
  admitted, because losing that capability should release the already-due fixed
  wake rather than postpone it. Loss of opaque/reaction eligibility, stale route,
  or provider unavailability requeues safely until bounded expiry; it never
  downgrades a delayed obligation to rich payload.
- One fixed debounce constant is 500 ms. It is not a config surface.

| Route/runtime at store | Exact behavior |
|---|---|
| neither new capability | incumbent immediate rich path |
| `opaque_wake_v1` only | incumbent immediate fixed wake |
| `wake_outcome_v1` only | incumbent immediate rich path; no delay |
| both on a legacy/empty-handle route | Plan-368 fail-closed selected-route behavior; no obligation |
| both but missing required reaction capability/authorization/nominated membership | incumbent ineligible behavior; no obligation |
| both + valid encrypted route + correlation + Redis | atomic event/obligation and 500 ms coordinator |
| memory backend or missing correlation | durable event through incumbent store plus incumbent immediate selected-route behavior |
| route preflight error | durable event remains authoritative; preserve incumbent route-error/no-provider behavior |
| obligation transaction error | store returns its existing persistence error; no pre-persistence provider call |
| per-recipient wake-state cap full | store the event without obligation and run the incumbent immediate fixed wake |
| duplicate event store | no new obligation and no refanout |
| old relay | it sends immediately and reports exact unsupported outcome action later |

One test must force a dual-capability preflight followed by capability removal
before commit. It must not leave a delayed obligation.

### One durable authority and coordinator

- Add one Redis record family keyed internally by
  `{authenticated recipient, correlation}` and one due ZSET. It is not an event
  payload queue. The record contains only state/revision, due/claim timestamps,
  claim token, retry count/backoff, expiry, and the finite producer route policy
  `none | direct_reaction_v1 | group_reaction_v1`.
- States are `pending`, `claimed`, and `completed`. `completed` is a bounded
  authenticated tombstone that closes outcome-before-store races. It is retained
  for the event replay horizon (seven days) and capped at 512 live records per
  recipient. Prune expired records first; if an absent-ACK tombstone cannot be
  retained at capacity, return a retryable capacity result so the device keeps
  v116. Never evict an unexpired record and claim success.
- A pending/claimed obligation expires at the earlier of its event-custody
  expiry and `storedAt + 7 days`; a completed tombstone uses the seven-day
  replay horizon.
- Direct, protected-direct/legacy-shadow, and group event rows plus each eligible
  recipient obligation commit in the same Redis MULTI/EXEC boundary. The
  existing bootstrap already supplies those owners the same Redis client/prefix.
- Atomic store rules:
  - existing `completed` -> store/dedupe the event but create no obligation;
  - absent -> store the event and create `pending` + due-index member;
  - existing pending/claimed or duplicate event -> create neither duplicate;
  - transaction/route-CAS failure -> no partial obligation.
- Authenticated outcome rules:
  - absent or pending -> `completed` tombstone;
  - completed -> idempotent OK;
  - claimed -> idempotent OK with no state change, because provider submission
    may already be in flight;
  - wrong peer changes only that peer's namespace and cannot affect the target.
- Coordinator rules:
  - due pending -> one claim token/lease;
  - accepted -> completed tombstone;
  - provider-permanent -> completed only when generation-safe
    `RevokeIfCurrent(route)` confirms that exact rejected route was still
    current and was revoked/terminalized;
  - revoke false/error or any intervening route generation change -> retryable,
    then fresh Plan-368 selection; a stale old-token rejection must never settle
    the wake owed to a new route;
  - retryable/unavailable/context-timeout/stale/ineligible route -> same record
    returns to pending with bounded backoff until expiry;
  - expired claim -> one CAS reclaim;
  - expired obligation -> remove without provider send and leave transport/event
    custody untouched.

### Honest provider boundary

- Refactor the existing shared gateway, not its four adapters, to return one
  coarse result: `accepted | permanent | retryable`. Existing immediate wrappers
  may ignore the value and must preserve Plan-368 bytes, retries, logs, and
  compare-revoke behavior; the coordinator consumes it.
- Use one fixed claim lease strictly longer than the fixed provider timeout plus
  complete retry budget. Do not add lease renewal. A blocked call must time out
  before the lease can admit another live claim owner.
- Redis guarantees one claim owner, not exactly-once APNs/FCM submission.
  Submission is at-least-once with Plan-368's fixed collapse identifiers. A crash
  after provider acceptance but before Redis completion can resubmit the same
  collapsed wake; never settle Redis before making the provider call. Tests and
  receipts must state this accepted ambiguity.

### Authenticated action and local drain

The only wire body is:

```json
{"action":"wake_outcome_v1","correlation":"<64 lowercase hex>","wakeNotRequired":true}
```

- Use an action-local strict decoder. Reject missing/false boolean, noncanonical
  or uppercase correlation, duplicate keys, `to`/`from`, and every unknown key.
  The shared permissive JSON decoder is not proof of this action's grammar.
- Namespace lookup exclusively under authenticated `remotePeer`. The action
  carries no recipient, route, event kind, conversation, reason, platform, or
  provider value. Add one store-side correlation extractor shared by all event
  stores and consume Plan 369's exact fixture: direct `messageId`; raw direct
  `reactionId`; group `logicalDeliveryId` with legacy-only absent-field fallback
  to exact authenticated `messageId`; raw group `notificationTransitionId`.
  Never reuse the incumbent generic `extractMessageId` for group aliases or a
  bounded local notification/reaction identity.
- Add one narrow node all-participants result; do not reuse or change
  `RelaySelector.FanOut` any-success semantics. It must retain success/failure per
  distinct configured relay. Exact authenticated `ERROR Unknown action:
  wake_outcome_v1` from an old relay is terminal unsupported because that binary
  cannot own a delayed obligation; network/malformed/new-relay failures remain
  retryable. Delete v116 only when every participant is OK/idempotent/unsupported.
- Add one bridge call and one public, in-flight-coalesced Dart drain method. The
  production bootstrap creates that single method/callback and shares it with:
  Plan-369's immediate post-commit kick; `PendingMessageRetrier.start`,
  `_retryIfNeeded`, `_flushUnackedOnNetworkRestored`, and its existing periodic
  tick; and `handleAppResumed` as invoked by `ApplicationRoot`. Do not add a
  timer/service. Reopen/partial-failure tests must exercise these production
  wiring owners, not manually invoke only a fake.
- One compile/test admission seam enables Plan-369 production append,
  `opaque_wake_v1`, `wake_outcome_v1`, and the drainer together. It defaults
  false. Do not add modality/platform flags.

### Must preserve

- Store-before-push and duplicate no-refanout for direct, protected direct,
  group, and both reactions.
- Delivery/strict-custody ACK never removes wake state. Outcome/tombstone never
  deletes inbox/event/blob custody or changes read state.
- Wake-token authorization, nominated group recipients, reaction capability,
  attempted/incapable counters, and synchronous group accounting.
- Plan-368 Android/iOS fixed bytes, legacy compatibility, route-stale handling,
  generation-safe revoke, provider collapse, and coarse logs.
- Default build advertises neither new capability and creates no obligation or
  outcome action.

### Hard `Do not`

- Do not add a second payload queue/service/provider adapter, per-adapter timer,
  reverse recipient index, Flutter DB migration, native writer, or worker.
- Do not persist or log sender/group/conversation/event/provider/private route
  material in wake state or protocol.
- Do not promise exact-once provider delivery, suppress a claimed send, use an
  any-success relay fanout, or treat absent outcome as a throwaway no-op.
- Do not activate capabilities or claim live/PRD/release acceptance.

### Deferred / accepted difference

- N04-N06 supply shared fresh lifecycle/final-effect/ledger authority before
  `inChat` or policy outcomes can become rollout-eligible.
- N07/N08 own native fixed-wake consumers and background outcome writers; N11
  owns adopted read/activation cleanup.
- WP-07 owns Redis deployment/migration operations, capability cohorting, live
  APNs/FCM, rollback, and release evidence.

No third N03-specific implementation/audit plan is warranted. Plans 369 and 370
complete the default-off N03-owned foundation; shared-wave eligibility closes
with the named downstream gaps, not a Plan 371.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-370-00 | Plan-369 and Plan-368 receipts are checksum/provenance valid | dependency command plus exact Plan-368 preservation | host receipts + SDK fakes | Plan 369 absent -> exact marker/identities and preserved N02 gateway | alter marker/tree -> preflight red | exact only |
| TC-370-01 | All four producers obey exact classifier, producer eligibility, memory/error/legacy fallback, and preflight-to-commit route CAS | `TestRelayNotificationClosure_WakeOutcomeCapabilityAndLegacyMatrix` | Go host / memory + Redis client fixture | immediate behavior -> delay only exact dual-capable rows | accept outcome-only, empty handle, missing reaction cap, or stale preflight -> red | relay closure prefix |
| TC-370-02 | Event/obligation/due commit atomically; duplicate/ACK separation holds; ACK-before-store tombstone suppresses later obligation; admission-cap overflow stores + sends immediate fixed, while absent-ACK tombstone-cap overflow is retryable and retains v116 | `TestRelayNotificationClosure_WakeOutcomeAtomicStoreAndDeliveryAckSeparation` | Go host / Redis protocol fixture | no wake authority -> one state family with both race orders and distinct cap fallbacks | split commit, let delivery ACK delete, discard absent ACK, reject an otherwise-storable event at cap, or evict live tombstone -> red | relay closure prefix |
| TC-370-03 | Strict authenticated action accepts exact grammar and implements absent/pending/completed/claimed/wrong-peer semantics | `TestRelayNotificationClosure_WakeOutcomeAuthenticatedProtocolAndIdempotence` | Go stream / authenticated peer | unknown action -> scoped tombstone/idempotence | trust body peer, accept extra key/false bool, or delete claimed -> red | relay closure prefix |
| TC-370-04 | Deadline and claim CAS are bounded; typed provider results settle/requeue honestly; blocked call, revoke-vs-token-rotation, and crash-after-accept ambiguity are explicit | `TestRelayNotificationClosure_WakeOutcomeDeadlineClaimRaceAndRecovery` | Go fake clock + race | immediate/void gateway -> one live claim owner and at-least-once recovery | map unavailable to accepted, settle before send, terminalize after revoke-CAS loss, or permit lease overlap -> red | exact race + prefix |
| TC-370-05 | Go/Dart vectors match; protocol/provider/log bytes are private; strict all-relay completion handles mixed old/new and partial failure | `TestRelayNotificationClosure_WakeOutcomeCorrelationPrivacyAndEligibility`, `TestInboxWakeOutcomeAllRelayCompletion`, `TestInboxWakeOutcomeBridgeStrictRequest`, and Dart `TC-370-05 opaque outcome uses strict all-relay completion` | Go/Dart host / real envelope + relay fakes | no action -> identical vectors and per-relay outcome | use bounded reaction/messageId, any-success fanout, or leak peer/event -> red | exact node/bridge/Dart |
| TC-370-06 | Process handoff covers pending-before-due and death-after-claim-before-provider-call as two distinct subcases; it does not pretend to prove post-provider atomicity | `TestRedisWakeOutcomeObligationSurvivesRelayProcessHandoff` | tagged child processes + shared miniredis protocol fixture | volatile owner loses work -> authoritative pending/claim recovery | omit due index/reclaim CAS -> red | exact now; one later host-all synthetic row |
| TC-370-07 | Default admission is zero; the one coalesced production drainer runs after commit, startup/reopen, online/reconnect, network-restored, periodic tick, and `handleAppResumed`, retaining partial failure without another scheduler | drain composition + `pending_message_retrier_test.dart` + `handle_app_resumed_phase2_continuation_wiring_test.dart` + production bootstrap contract, all named `TC-370-07` | Dart composition / persisted repository + relay fakes | no drain owner -> one shared method through every real trigger | advertise half-capability, wire only a helper, overlap drains, or delete partial failure -> red | focused; exact production wiring registration |

Exactly five relay-unit top-level tests (TC-370-01..05), one tagged process test,
five Dart tests (one TC-370-05 and four TC-370-07), one node test, and one bridge
test are selected.
Permutations stay inside those causal owners; zero selection or any skipped child
is a gate failure.

## Implementation Steps

1. Snapshot the inherited tree; validate/copy Plan-369 and Plan-368 receipt
   identities. Run the Plan-368 preservation bundle.
2. Author TC-370-01/02 semantic REDs. Add one optional durable wake-state
   interface, route-at-commit validation, event/obligation/tombstone transactions,
   finite reaction policy, and due index. Keep memory interfaces immediate.
3. Add one bootstrap-owned coordinator with injected clock and claim lease.
   Refactor only the incumbent gateway result to accepted/permanent/retryable;
   retain external at-least-once/collapse semantics.
4. Author TC-370-03/04 REDs. Add the strict action decoder, authenticated state
   transitions, bounded retry/expiry, provider-block and crash ambiguity tests.
5. Author TC-370-05/07 REDs. Port exact Plan-369 vectors, add strict
   all-participants node/bridge fanout, one in-flight-coalesced Dart drain method,
   and pass that same method through production bootstrap to Plan-369 commit,
   `PendingMessageRetrier`, and `handleAppResumed`/`ApplicationRoot` behind one
   paired default-off seam.
6. Add TC-370-06 by extending the existing tagged miniredis independent-process
   pattern. Cover pending handoff and claimed-owner death separately. Register it
   once for later wave `host-all`; require no local `redis-server` binary.
7. Run independent Go and Dart focused bundles concurrently. Then run race,
   mutations, exact preservation, the affected curated `groups` lane, one relay
   family, hygiene, analyzer, and one incremental Graphify refresh serially.
8. Append execution/audit to this plan and create checksum-bound
   `Test-Flight-Improv/evidence/370/README.md`. Do not run per-plan full
   `host-all`, phone, S2, or provider campaigns.

## Risks And Counterexamples

- ACK arrives before store -> completed tombstone consumed atomically by later
  store (TC-370-02).
- Route loses capability between preflight and commit -> exact route CAS falls
  back without obligation (TC-370-01).
- Provider accepts then relay crashes -> same collapsed fixed wake may be
  resubmitted; recovery is never lost (TC-370-04).
- Live owner blocks past lease -> fixed provider timeout + retry budget is
  strictly below the claim lease (TC-370-04).
- One relay succeeds while obligation owner is offline -> all-participant result
  retains v116 (TC-370-05).
- Old relay rejects action -> exact unsupported response is terminal only for
  that nonparticipating immediate relay (TC-370-05).
- Durable v116 row survives app death but no caller drains -> real composition
  startup/reconnect/resume trigger (TC-370-07).
- Native/background effect owners remain incomplete -> paired capability stays
  false; no N03 live/release claim.

## Gate Cadence

- Run focused Go/Dart owners concurrently; run mutations, race, process, curated,
  relay-family, and hygiene phases serially.
- Per-plan closure runs focused causal tests, exact Plan-368/store/ACK sentinels,
  one affected `groups` curated lane (which already invokes the relay closure),
  and the changed relay package family once. Exact direct/node/bridge tests avoid
  duplicating the same relay prefix through `1to1`.
- No `core-host-all`, `feature-host-all`, performance, phone, or native family is
  justified. No Flutter schema/UI/native/provider code changes here.
- Do not run full `host-all`. Run it once after the N03-N06 shared dependency
  wave and once at final rollout/release.

## Device/Relay Proof Profile

- Profile: host independent-process Redis-protocol proof.
- Boundary: atomic state, deadline, process death, claim recovery, and invocation
  of the existing fixed gateway.
- Fixture: parent-owned miniredis endpoint shared by two sequential child relay
  owners, following the existing Plan-367 process-test pattern. This proves the
  Go Redis client protocol/state owner without requiring an external daemon.
- Phone/two-peer: N/A — authenticated libp2p peers are deterministic host
  fixtures. Do not consume the available Android pair for a host protocol.
- Environment blocker: only missing Go toolchain/dependency or inability to
  launch the tagged child fixture. Missing S2/provider/local `redis-server` is
  irrelevant.
- Native Android/iOS adoption remains N08/N07.

## Acceptance Gates

```bash
# Baseline and prerequisites.
set -euo pipefail
git status --short
command -v jq >/dev/null
plan370_gate_dir="$(mktemp -d /tmp/plan370-gates.XXXXXX)"
(
  set -euo pipefail
  cd Test-Flight-Improv/evidence/369
  shasum -a 256 -c README.md.sha256
  rg -x 'N03_DURABLE_LOCAL_OUTCOME_FOUNDATION_CODE_COMPLETE' README.md
  rg -q '^Base HEAD: [0-9a-f]{40}$' README.md
  rg -q '^Frozen tested tree: [0-9a-f]{40}$' README.md
  rg -q '^Dirty snapshot SHA-256: [0-9a-f]{64}$' README.md
  rg -q '^Graphify fingerprint: [0-9a-f]{16}$' README.md
)
(
  set -euo pipefail
  cd Test-Flight-Improv/evidence/368
  shasum -a 256 -c README.md.sha256
  rg -x 'N02_OPAQUE_WAKE_MECHANISM_CODE_COMPLETE' README.md
)

# After authoring the exact named test, require discovery and a semantic RED.
(
  set -euo pipefail
  cd go-relay-server
  GOTOOLCHAIN=go1.25.0 go test . \
    -list '^TestRelayNotificationClosure_WakeOutcomeCapabilityAndLegacyMatrix$' |
    rg -x 'TestRelayNotificationClosure_WakeOutcomeCapabilityAndLegacyMatrix'
  set +e
  GOTOOLCHAIN=go1.25.0 go test . \
    -run '^TestRelayNotificationClosure_WakeOutcomeCapabilityAndLegacyMatrix$' \
    -count=1
  red_status=$?
  set -e
  test "$red_status" -ne 0
)

# Focused GREEN: independent Dart and Go owners run concurrently and are
# mechanically non-vacuous.
(
  set -uo pipefail
  dart_status=0
  go_status=0
  flutter test --concurrency=2 \
    test/core/bridge/p2p_bridge_client_wake_outcome_test.dart \
    test/core/notifications/notification_completed_outcome_drain_composition_test.dart \
    test/core/services/pending_message_retrier_test.dart \
    test/core/lifecycle/handle_app_resumed_phase2_continuation_wiring_test.dart \
    test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart \
    --name 'TC-370-(05|07)' \
    --file-reporter "json:$plan370_gate_dir/dart.json" &
  dart_pid=$!
  (
    set -euo pipefail
    cd go-relay-server
    relay_pattern='^TestRelayNotificationClosure_WakeOutcome(CapabilityAndLegacyMatrix|AtomicStoreAndDeliveryAckSeparation|AuthenticatedProtocolAndIdempotence|DeadlineClaimRaceAndRecovery|CorrelationPrivacyAndEligibility)$'
    GOTOOLCHAIN=go1.25.0 go test . -list "$relay_pattern" |
      rg '^TestRelayNotificationClosure_WakeOutcome' >"$plan370_gate_dir/relay.list"
    test "$(wc -l <"$plan370_gate_dir/relay.list" | tr -d ' ')" -eq 5
    GOTOOLCHAIN=go1.25.0 go test . -run "$relay_pattern" -count=1 -v |
      tee "$plan370_gate_dir/relay.log"
    test "$(rg -c '^--- PASS: TestRelayNotificationClosure_WakeOutcome' "$plan370_gate_dir/relay.log")" -eq 5
    ! rg -q '^[[:space:]]*--- SKIP: TestRelayNotificationClosure_WakeOutcome' "$plan370_gate_dir/relay.log"
  ) &
  go_pid=$!
  wait "$dart_pid" || dart_status=$?
  wait "$go_pid" || go_status=$?
  test "$dart_status" -eq 0
  test "$go_status" -eq 0
  test "$(jq -s '[.[] | select(.type == "testStart" and (.test.name | test("TC-370-(05|07)")))] | length' "$plan370_gate_dir/dart.json")" -eq 5
  test "$(jq -s '[.[] | select(.type == "testDone" and .skipped == true)] | length' "$plan370_gate_dir/dart.json")" -eq 0
)

# Race only the concurrency owner; require one PASS and no skipped child.
(
  set -euo pipefail
  cd go-relay-server
  race_pattern='^TestRelayNotificationClosure_WakeOutcomeDeadlineClaimRaceAndRecovery$'
  GOTOOLCHAIN=go1.25.0 go test -race . -run "$race_pattern" -count=1 -v |
    tee "$plan370_gate_dir/race.log"
  test "$(rg -c '^--- PASS: TestRelayNotificationClosure_WakeOutcomeDeadlineClaimRaceAndRecovery ' "$plan370_gate_dir/race.log")" -eq 1
  ! rg -q '^[[:space:]]*--- SKIP: TestRelayNotificationClosure_WakeOutcome' "$plan370_gate_dir/race.log"
)

# Exact node and bridge owners; one selected/pass in each package.
(
  set -euo pipefail
  cd go-mknoon
  for spec in \
    'node TestInboxWakeOutcomeAllRelayCompletion' \
    'bridge TestInboxWakeOutcomeBridgeStrictRequest'; do
    pkg="${spec%% *}"
    name="${spec#* }"
    GOTOOLCHAIN=go1.25.0 go test "./$pkg" -list "^$name$" | rg -x "$name"
    GOTOOLCHAIN=go1.25.0 go test "./$pkg" -run "^$name$" -count=1 -v |
      tee "$plan370_gate_dir/$pkg.log"
    test "$(rg -c "^--- PASS: $name " "$plan370_gate_dir/$pkg.log")" -eq 1
    ! rg -q "^[[:space:]]*--- SKIP: $name" "$plan370_gate_dir/$pkg.log"
  done
)

# Tagged independent-process handoff using a shared miniredis protocol fixture.
(
  set -euo pipefail
  cd go-relay-server
  process_name='TestRedisWakeOutcomeObligationSurvivesRelayProcessHandoff'
  GOTOOLCHAIN=go1.25.0 go test -tags integration . -list "^$process_name$" |
    rg -x "$process_name"
  GOTOOLCHAIN=go1.25.0 go test -tags integration . \
    -run "^$process_name$" -count=1 -v |
    tee "$plan370_gate_dir/process.log"
  test "$(rg -c "^--- PASS: $process_name " "$plan370_gate_dir/process.log")" -eq 1
  ! rg -q "^[[:space:]]*--- SKIP: $process_name" "$plan370_gate_dir/process.log"
)

# Twelve exact Plan-368/store/ACK preservation sentinels.
(
  set -euo pipefail
  cd go-relay-server
  preserve='^(TestRelayNotificationClosure_(OpaqueWakeRouteSelectionAndLegacyCompatibility|OpaqueWakeAndroidProviderRequest|OpaqueWakeIOSProviderRequest|OpaqueWakeFailureAndGenerationSafeRevoke|ProviderWakeLogsOmitPrivateValues|DirectStoreTriggersPushAfterPersistence|DirectDuplicateDoesNotRefanoutPush|DirectReactionDuplicateDoesNotRefanoutPush|AckCustodyBackendContract)|TestGIRD004GroupStoreDuplicateDoesNotAppendOrRefanoutPush|TestHandleInboxStream_(GroupStoreFansOutPushToRecipientsWithTokens|RetrievePendingAndAck))$'
  GOTOOLCHAIN=go1.25.0 go test . -list "$preserve" |
    rg '^(TestRelayNotificationClosure_|TestGIRD004|TestHandleInboxStream_)' >"$plan370_gate_dir/preserve.list"
  test "$(wc -l <"$plan370_gate_dir/preserve.list" | tr -d ' ')" -eq 12
  GOTOOLCHAIN=go1.25.0 go test . -run "$preserve" -count=1 -v |
    tee "$plan370_gate_dir/preserve.log"
  test "$(rg -c '^--- PASS: (TestRelayNotificationClosure_|TestGIRD004|TestHandleInboxStream_)' "$plan370_gate_dir/preserve.log")" -eq 12
  ! rg -q '^[[:space:]]*--- SKIP: (TestRelayNotificationClosure_|TestGIRD004|TestHandleInboxStream_)' "$plan370_gate_dir/preserve.log"
)

# One affected curated lane and one affected relay family.
./scripts/run_test_gates.sh groups
bash scripts/test/run_relay_all_go_309.sh

# Registration and hygiene.
bash scripts/test/host_test_gate_batch_contract_test.sh
bash -n scripts/run_test_gates.sh scripts/run_host_test_gates.sh
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go vet ./... && test -z "$(gofmt -l *.go)")
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go vet ./... && test -z "$(gofmt -l node/*.go bridge/*.go)")
plan369_tree="$(sed -n 's/^Frozen tested tree: //p' \
  Test-Flight-Improv/evidence/369/README.md)"
test -n "$plan369_tree"
while IFS= read -r path; do
  test -z "$path" || dart format --output=none --set-exit-if-changed "$path"
done < <(
  {
    git diff --name-only "$plan369_tree" -- '*.dart'
    git ls-files --others --exclude-standard -- '*.dart'
  } | sort -u
)
flutter analyze
git diff --check
./graphify-arch/refresh_arch_graph.sh --incremental
```

Run at least five sequential representative mutations: accept outcome-only,
split event/obligation transaction, discard an absent outcome, terminalize a
revoke-CAS loss, and reuse any-success fanout. Each must re-red
its named test; revert only that mutation before final gates.

## Execution Interpretation And Done Criteria

- Expected RED is recorded only after the exact TC-370-01 name is discovered and
  its assertion fails. The current repository's “no tests to run” exit zero is
  explicitly not RED evidence.
- Recorded execution chronology: the historical first discovery-guarded RED was
  not captured because the tests and implementation landed concurrently. This
  plan makes no retrospective first-RED claim. Later genuine causal REDs covered
  wrong due-type partial events, preflight double lookup/provider work,
  source-digest route CAS, stale-due head-of-line blocking, malformed scalar
  delay, memory retryable ownership, boundary `FEFF`, and protected near-expiry
  suppression before their final GREEN owners.
- Green sentinel: one exact dual-capable Redis store owns pending state; an
  outcome-before-store tombstone prevents later obligation; delivery ACK cannot
  suppress it; one live claimant consumes an honest provider result; restart
  preserves at-least-once recovery.
- Inherit the checksum-bound Plan-369 tree plus older user work. Freeze/hash it;
  do not require a broad source commit.
- Scope drift includes a second queue/service/scheduler, persisted rich payload,
  per-adapter coordinator, new DB/native/UI owner, exact-once promise, or
  default-on capability.

- [x] Plan-369 and Plan-368 checksum/identity preflights pass.
- [x] All seven causal rows and five representative mutations pass on the final tree.
- [x] Route-at-commit CAS, all producer eligibility, atomic event/state, and
      delivery-ACK separation are proven.
- [x] Both store-before-outcome and outcome-before-store orders are safe.
- [x] Provider recovery is documented/tested as at-least-once with one live claim
      owner and fixed collapse identifiers.
- [x] Strict authenticated grammar and all-participant mixed-relay fanout retain
      v116 on every retryable participant failure.
- [x] Production composition drains persisted rows after commit/reopen/reconnect/
      resume without a second scheduler.
- [x] Focused/race/process/preservation, curated `groups`, relay family,
      analyzer/vet/format/diff, and graph refresh pass; no phone/full-host run.
- [x] Combined admission remains false and no live/release claim is made.

## Handoff

- Completion marker: `N03_WAKE_OUTCOME_COORDINATOR_FOUNDATION_CODE_COMPLETE`.
- Closure receipt: `Test-Flight-Improv/evidence/370/README.md`, SHA-256
  `14af6bddc18cda365b1bda36bc69d1c0d23b5f7106dc6f9f72e04641eada0b04`;
  the sibling `README.md.sha256` validates canonically.
- TDD chronology: the historical first discovery-guarded RED was not captured
  because tests and implementation landed concurrently; no first-RED receipt is
  claimed. The later causal repairs and five isolated mutation REDs are recorded
  in the checksum-bound closure receipt.
- Registration: shared Dart paths are registered without adding a runner;
  untagged relay tests match the existing closure prefix; tagged process test
  gets one synthetic later-wave `host-all` row.
- Migration: none; consumes Plan-369 v116 and extends the incumbent Redis owner.
- Boundary closure: the two N03-owned default-off slices are code-complete. Full
  N03 PRD/A-control eligibility still consumes N04-N08/N11 and WP-07; that is
  shared-wave work, not a third N03 plan.
- Full-host cadence: once after the N03-N06 dependency wave, then at final
  rollout/release; never per this plan.

## Reviewer Findings

Independent `$tdd-review` passes found nine material counterexamples in the
initial draft: impossible exactly-once provider settlement, lost
outcome-before-store, incomplete stored route lease, reaction-capability
widening, old-relay rejection, fake claim-recovery wording, no production v116
drain trigger, permissive action decoding, and any-success relay fanout. They
also found vacuous test discovery and an unnecessary external Redis blocker.
Every item is resolved in the revised contract with one record family, one due
index, one coordinator, one return-bearing incumbent gateway, one strict action,
and one strict all-participant drain—without Plan 371.

## Arbiter Decision

**POST-EXECUTION AUDIT CLOSED.** Plan 369's checksum-bound handoff and Plan
368's fixed-wake receipt remain valid. The implemented surface is the reviewed
coherent minimum: one Redis authority/coordinator, one authenticated action,
one strict all-relay drain, and one paired default-false seam. The two N03-owned
slices are foundation-code-complete, while `N03_COMPLETE`, live acceptance,
activation, deployment, and release eligibility remain false/open.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-15 | TC-370-00 prerequisite | `evidence/369/README.md`, `README.md.sha256`; `evidence/368/README.md`, `README.md.sha256` | Both sibling checksum checks pass; both exact markers pass; Plan-369 base/tree/dirty/Graphify field shapes pass | Plan-369 receipt SHA-256 `8d4229405b1b39ac26dd2304fa77455322be8b25c1b1f573a4903f0044d4873c`; base `8d86501e46f1a06e724daf8009cd3bf0f807578c`; frozen tree `61e1b1935a022e7ad0f54d207549903a728e9b86`; dirty snapshot `ff0c29a6e3ea5ed013aeb147b589c34de74b9131fce0d700e8c1f4d4b360f96b`; Graphify `ec9a45bfd76c0f40` | **PASS; execution unblocked. No Plan-370 RED or implementation yet.** | TC-370-01 semantic RED |
| 2026-08-15 | Causal implementation and repair | Relay Redis owner/coordinator and four producers; strict action; node/bridge; Dart drainer and production lifecycle composition | Historical first RED not captured because tests/implementation landed concurrently; subsequent real REDs exposed wrong due type, double preflight, missing source-digest CAS, stale-due HOL, malformed scalar, memory ownership, `FEFF`, and near-expiry defects | Final contract has one Redis state family/due index, atomic event/obligation/tombstone behavior, strict authenticated action, typed provider result, all-participant drain, and one paired `false` seam | **GREEN after causal repairs; no exact-once, native, live-provider, live-Redis, activation, or release claim.** | Isolated mutations |
| 2026-08-15 | Five isolated semantic mutations | TC-370-01, TC-370-02, TC-370-04, and exact node owner | Outcome-only `eb98f031...`, split transaction `c9eb7773...`, discard absent tombstone `cbfce306...`, revoke-CAS loss `0cb3ec39...`, any-success node `b94205eb...`: each exact owner RED, then mutation reverted and owner GREEN | Full non-retained hashes are bound in `evidence/370/README.md` | **5/5 required mutation families RED then GREEN.** | Final focused and preservation gates |
| 2026-08-15 | Final causal and preservation gates | Five Dart owners; five relay owners; race TC-370-04; node; bridge; tagged process; twelve preservation sentinels | Dart 5/5, relay 5/5, race 1, node 1, bridge 1, process PASS with two subcases, preservation 12/12; zero skips; race emitted only the warning-class macOS linker message | Non-retained log/JSON hashes are bound in `evidence/370/README.md` | **PASS.** | Curated/family/hygiene closure |
| 2026-08-15 | Final proportional gates and frozen audit | Curated `groups`, relay-all, host-batch contract, shell syntax, Go vet/gofmt, changed Dart, analyzer, diff, Graphify | `groups` 4,262 Dart PASS plus bridge/node/relay; relay-all 309 PASS; host batch/syntax/vet/gofmt/14-file Dart format/full analyze/diff PASS; Graphify current/anchored at `1cd2db6f3341312b` (76,031 / 111,542; overlay 1,584 / 15,682 / 1,247) | Base `ddf4b1459187b074128213e72b8456bd44e39cef`; frozen tested tree `79664ab276372316833a03de0c90c3423c6129f4`; dirty snapshot `26f862323fe4242296c9a626ab5e3b23e5c1d6911ebdf5a9e66f6bbfe2b756ed` | **POST-EXECUTION AUDIT CLOSED. No phone, core/feature/full-host, live provider/Redis, deployment, activation, or release leg was run.** | Checksum-bind receipt and hand off shared-wave work |
| 2026-08-15 | Receipt and handoff | `evidence/370/README.md`, `README.md.sha256`; Plan/status/index/coverage closure | `shasum -a 256 -c README.md.sha256` PASS; exact marker and base/frozen/dirty/Graph identity regexes PASS | Receipt SHA-256 `14af6bddc18cda365b1bda36bc69d1c0d23b5f7106dc6f9f72e04641eada0b04` | **FOUNDATION CODE COMPLETE; `N03_COMPLETE=false`, live acceptance false, default-off, not release-eligible.** | N04-N08/N11 and WP-07; no Plan 371 |
