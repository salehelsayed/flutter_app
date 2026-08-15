# 368 - GAP-N02 Fixed Mailbox-Dirty Wake And Provider Privacy Closure

Status: **POST-EXECUTION AUDIT CLOSED / N02 OPAQUE WAKE MECHANISM CODE COMPLETE / N02 SLICE 2 OF 2 / HOST VERIFIED / N02-WAVE HOST-ALL GREEN / LIVE-ACCEPTANCE-BLOCKED / DEFAULT-OFF CAPABILITY / NOT RELEASE-ELIGIBLE**
Type: Modification
Spec: `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2.md` privacy contract, target architecture requirement 4, platform payloads, and AC-11; GAP-N02 / WP-02 in `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md`
Classification: fixed provider-request convergence at the Plan-367 route gateway; last N02 mechanism slice
Closure tier: relay host + captured Firebase Admin SDK requests + one N02 wave; no device or deployment leg

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-15 | Evidence Collector | PRD/GAP-N02; Plan 367 contract; all four relay adapters; rich/oversized builders; reaction capability and observability; permanent-error tests; Firebase Go SDK; APNs bundle/topic fixtures; gate scripts | All producer kinds converge through four adapters and one `PushService`; a platform split or producer-by-producer plan series would duplicate the same invariant. | Define one fixed request per platform at the private route gateway. |
| 2026-08-15 | Planner using `$tdd-plan` | Graphify review context; provider-capture precedent; official Firebase/Apple request contracts; Plan 327 | Keep legacy rich payloads only as a capability-bounded mixed-version path. Add no mobile consumer in WP-02 and do not turn log sanitation into broad GAP-N10 work. | Wait for Plan 367's exact marker, then execute TC-368-01 RED. |
| 2026-08-15 | Independent reviewers using `$tdd-review` | Dependency proof; selection/error matrices; Android/APNs wire shapes; producer census; logs/counters; preservation and wave gates | Incorporated unknown-platform refusal, deletion/no-notify controls, advertisement ownership, exact no-downgrade, owned-log scope, child-skip guards and removal of duplicate curated/full-relay runs. Five causal owners are sufficient. | Arbiter confirms contract-ready while Plan 367 remains unexecuted. |
| 2026-08-15 | Arbiter | Corrected plan plus scope, proof-boundary and delivery-economy reviews | CONTRACT READY. Execution remains blocked only on Plan 367's checksum-valid final receipt; no Plan 369 or device leg is added. | Validate TC-368-00 after Plan 367, then begin TC-368-02 RED. |

## Problem And Evidence

The relay currently derives provider payloads from event content:

- direct builders include route, sender, message, and ciphertext fields at
  `go-relay-server/inbox.go:427-555`;
- group builders include group/sender/message/ciphertext fields at
  `go-relay-server/inbox.go:556-692`;
- reaction builders add event/target/reactor/group correlators in
  `go-relay-server/reaction_push.go`;
- oversized fallbacks deliberately retain routing identifiers in
  `go-relay-server/inbox.go:693-842`;
- four notification adapters select token/capability and send at
  `go-relay-server/inbox.go:161-249`;
- direct and group reaction paths perform separate upstream capability lookups
  at `go-relay-server/inbox.go:1584-1587` and `:1862-1869`;
- retry/fallback/permanent-error logs currently receive peer, push-kind, group,
  transition, and raw error context at `go-relay-server/inbox.go:268-404` and
  related reaction paths.

GAP-N02 requires the provider to receive the same small generic shape for every
event kind. Provider token and send timing remain necessarily visible; sender,
recipient application identity, conversation/group, message/event/reaction,
media, content, route, relay, deep-link, and stable analytics values must not.

Plan 368 reuses Plan 367's opaque, generation-bearing route gateway. The
gateway resolves the provider token privately and emits a fixed mailbox-dirty
request. The opaque handle itself is **not** sent to APNs/FCM.

## Dependency Contract

Plan 368 is authored now but execution is blocked until Plan 367's
post-execution current-source audit records exactly:

```text
N02_OPAQUE_HANDLE_FOUNDATION_CODE_COMPLETE
```

The marker alone is insufficient. Validate
`Test-Flight-Improv/evidence/367/README.md` against its sibling
`README.md.sha256`, then copy the receipt's exact frozen tested tree, dirty
snapshot hash, Graphify fingerprint, focused/race/tagged-process/preservation/
curated/full-relay results, and current-source audit identity into this plan's
first Execution Progress row. If the receipt or any required field is missing,
TC-368-00 remains blocked.

```bash
(
  set -euo pipefail
  cd Test-Flight-Improv/evidence/367
  shasum -a 256 -c README.md.sha256
  rg -x 'N02_OPAQUE_HANDLE_FOUNDATION_CODE_COMPLETE' README.md
)
```

Before the first RED, verify Plan 367's seven focused tests are present and
green:

```bash
(
  set -euo pipefail
  cd go-relay-server
  plan367_prerequisite_log="$(mktemp /tmp/plan367-prerequisite.XXXXXX)"
  trap 'rm -f "$plan367_prerequisite_log"' EXIT
  plan367_tests="$(
    GOTOOLCHAIN=go1.25.0 go test . -list \
      '^TestRelayNotificationClosure_PushRoute(LegacyCoexistenceAndMigrationAdmission|DirectoryCiphertextAndGenerationContract|MigrationRevisionFenceConvergesWithoutWriteDowntime|EncryptedResolutionFeedsEveryRichSender|PermanentErrorCompareRevokesExactLease|ExplicitUnregisterAcknowledgesOnlyAtomicDelete|ExplicitLegacyCleanupIsIdempotent)$'
  )"
  test "$(printf '%s\n' "$plan367_tests" | rg -c '^TestRelayNotificationClosure_')" -eq 7
  GOTOOLCHAIN=go1.25.0 go test . \
    -run '^TestRelayNotificationClosure_PushRoute(LegacyCoexistenceAndMigrationAdmission|DirectoryCiphertextAndGenerationContract|MigrationRevisionFenceConvergesWithoutWriteDowntime|EncryptedResolutionFeedsEveryRichSender|PermanentErrorCompareRevokesExactLease|ExplicitUnregisterAcknowledgesOnlyAtomicDelete|ExplicitLegacyCleanupIsIdempotent)$' \
    -count=1 -v | tee "$plan367_prerequisite_log"
  test "$(rg -c '^--- PASS: TestRelayNotificationClosure_PushRoute' "$plan367_prerequisite_log")" -eq 7
  ! rg -q '^[[:space:]]*--- SKIP: TestRelayNotificationClosure_PushRoute' "$plan367_prerequisite_log"
)
```

Plan 368 preserves `pushRouteLease`, `ResolveRoute`,
`RevokeIfCurrent`, encrypted-state admission, and generation/source-digest
semantics. Its conceptual fixed-send entry is:

```go
mailboxDirty(ctx context.Context, route pushRouteLease) error
```

A bare `handle string` is insufficient because provider failure must compare
and revoke the immutable handle **and generation**. The route contains no event,
provider-token, or provider-visible social field. Its private `lookupKey` may
contain legacy backend lookup material, but remains unexported, gateway-only,
never serialized or logged, and source-guarded; passing the lease does not
widen the provider boundary.

N01 live/S2/B1b acceptance is not a dependency. Plan 327 remains superseded;
do not add its per-event routing map.

## Graph Grounding

- Compact planning/review queries were anchored on `tokenEntry`, `PushService`,
  the four send adapters, `sendWithRetry`, `recipientSupportsCapability`, rich
  builders, provider-capture tests, and gate registration.
- Planning fingerprint inherited from the current final-N01 graph:
  `19e306d1432ccbf1`.
- Direct source verification owns Go/Firebase serialization details and the
  Xcode bundle identifier.
- Existing reuse anchors:
  - provider request capture and error classification:
    `go-relay-server/push_permanent_error_closure_test.go`;
  - all-producer projection table:
    `go-relay-server/ordinary_push_projection_test.go`;
  - store-before-push and duplicate suppression: `go-relay-server/inbox_test.go`
    and `direct_reaction_custody_dedupe_test.go`;
  - reaction eligibility/capability/counters:
    `go-relay-server/inbox_test.go`, `group_reaction_push_test.go`, and
    `reaction_wake_observability_test.go`;
  - bundle/topic truth: `ios/Runner.xcodeproj/project.pbxproj:1436,1464` and
    `integration_test/scripts/ios_notification_provider_adapter.py:33`.

## Scope Contract And Guard

### In scope

- exact capability `opaque_wake_v1`, absent from current Dart registration
  defaults and therefore default-off;
- one new production helper file, `go-relay-server/opaque_wake.go`, containing
  fixed payload construction, trusted APNs topic, one five-minute lifetime
  constant, and an injected clock seam;
- one route/capability decision in each of the four current adapters;
- fixed Android and iOS Firebase Admin SDK messages, proven at captured provider
  request bytes;
- generation-safe retry/revoke via Plan 367's route contract;
- preservation of Plan 367's removal of duplicate upstream reaction capability
  lookups;
- provider-facing log sanitation only on registration/init/send/retry/revoke and
  group-reaction-wake lines touched by this change;
- one legacy rich compatibility path for incapable clients, preserving current
  request behavior and provider-size fallback;
- registration of the existing `scripts/test/run_relay_all_go_309.sh` as one
  synthetic non-Dart `host-all` tail, alongside Plan 367's tagged process tail;
- combined Plans 367-368 audit and the one N02-wave `host-all`.

### Out of scope

- Dart/native consumer implementation or advertising `opaque_wake_v1` (WP-04
  iOS and WP-05 Android);
- changing localization resources, notification presentation, tap routing,
  inbox fetch/reconciliation, ledger/outcome ownership, or OS-extension code;
- broad log/analytics cleanup across the app (GAP-N10);
- provider-token vault/migration redesign (Plan 367);
- activation, production deployment, cohorting, retirement of rich payloads,
  device acceptance, S2/B1b, or release closure (WP-06/WP-07);
- a new service, provider adapter, config layer, queue, scheduler, worker,
  protocol action, or separate platform plan.

Hard scope stop: if a mobile consumer, localization change, new gateway service,
or third N02 implementation plan appears necessary, stop and re-review. N02
mechanism closure here is default-off and host-proven; later work consumes it.

## Route Selection And Compatibility Contract

Each of the four adapters—direct, direct reaction, group reaction, and group—
performs exactly one `LookupRoute(recipient)` on the happy path:

| Route snapshot | Result |
|---|---|
| `opaque_wake_v1` present and handle nonempty | call fixed `mailboxDirty(ctx, route)`; never build rich event payload |
| `opaque_wake_v1` present but legacy/empty handle | fail closed; do not use another legacy capability and do not send rich |
| `opaque_wake_v1` absent | preserve current rich builder and exact reaction capability/eligibility behavior |
| non-stale lookup, marker, crypto, or resolve error | terminate this attempt; no alternate lookup and no downgrade |

After private resolution, canonicalize only known `android` and `ios` platform
values. An empty or unknown platform is a coarse fixed-send error: send nothing,
do not revoke a token that the provider never rejected, and never fall back to
rich. No third platform payload or configuration layer is introduced.

The route-only private gateway returns `ErrPushRouteStale` to its caller. The
shared outer selection helper then performs exactly one fresh lookup/selection.
It rechecks every capability; a second stale result terminates. Once the original snapshot
selected opaque wake, the bounded retry may remain opaque or terminate; it must
never downgrade that attempt to rich.

The counterexample is exact: if capability changes while handle/generation stay
the same, original opaque followed by a fresh rich/empty snapshot terminates;
original rich followed by a fresh opaque snapshot upgrades to the fixed path.
There is exactly one complete relookup/reselection after explicit stale, and
reaction capability is rechecked on that fresh snapshot. This exception lives
once in the shared selection helper, not independently in four adapters.

Preserve Plan 367's deletion of `recipientSupportsCapability` and its two
upstream uses. Reaction eligibility, duplicate suppression, attempted/incapable
metrics, and store-before-push ordering stay owned by the adapter's one route
snapshot. Group reaction keeps the snapshot and incapable/attempted accounting
at the existing synchronous pre-goroutine point, then passes the immutable route
into the goroutine; scheduling order cannot redefine the counter identity.
Asynchronous metric tests wait for all expected deltas rather than assuming
sibling goroutine completion order.

`sendWithRetry` accepts the resolved immutable route plus provider message. A
permanent provider error calls only `RevokeIfCurrent(resolved.Route)`. Generic
errors never switch an opaque request to rich. The strict size fallback remains
only for the incapable legacy-rich request; the fixed request is not routed
through that fallback.

## Fixed Provider Request Contract

Official contracts establish that Android collapse key groups replaceable
messages and Android priority is `high` or `normal`; APNs requires an accurate
push type, uses the app bundle ID as topic for alerts, accepts an epoch
expiration, and coalesces equal collapse IDs. Apple also defines localized alert,
sound, category, and `mutable-content` keys. The implementation proof remains
the pinned Go Firebase SDK's actual captured HTTP request, not a hand-written
JSON approximation.

Use exactly one constant:

```go
const opaqueWakeAPNSTopic = "com.mknoon.app"
```

Do not put topic in registration, route, vault, or a new environment layer. The
existing Debug and Release bundle IDs and provider fixture already agree.

With `now` from an injected clock and one duration constant of five minutes:

### Android

```text
token: resolved privately
data: {"v":"1","w":"1"}
android.priority: "high"
android.ttl: 300 seconds (captured SDK wire: "300s")
android.collapse_key: "mailbox"
```

There is no top-level notification, APNS config, Android notification, or extra
data key.

### iOS/APNs through Firebase

```text
token: resolved privately
apns.headers.apns-push-type: "alert"
apns.headers.apns-priority: "10"
apns.headers.apns-topic: "com.mknoon.app"
apns.headers.apns-expiration: decimal Unix(now + 300 seconds)
apns.headers.apns-collapse-id: "mailbox"
aps.alert.title-loc-key: "NEW_MESSAGE_TITLE"
aps.alert.loc-key: "NEW_MESSAGE_BODY"
aps.mutable-content: 1
aps.sound: "default"
aps.category: "MESSAGE_WAKE"
custom payload: {"v":"1"}
```

There is no top-level data, Android config, Firebase notification, badge,
`content-available`, thread ID, plaintext title/body, sender, peer, recipient
application identity, mailbox/handle, conversation/group, message/event/reaction,
media, URL, deep link, relay, ciphertext, KEM, nonce, or analytics label.

The iOS request is an alert wake, not a silent/background push; therefore
priority 10 and `apns-push-type=alert` are intentional. The test captures
relay-to-Firebase serialization. It does not falsely claim to capture the
downstream Firebase-to-APNs hop.

Provider references:

- [Firebase AndroidConfig](https://firebase.google.com/docs/reference/admin/node/firebase-admin.messaging.androidconfig)
- [Apple APNs request headers](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns)
- [Apple payload key reference](https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/PayloadKeyReference.html)

## Producer And Event Coverage

Both platform request tests table every currently implemented relay producer so
shape equality cannot pass by sampling only chat text:

| Family | Fixtures whose provider request must be identical within a platform |
|---|---|
| Direct ordinary eligible | chat text, media/image, voice, private/disappearing and edit shapes; introduction send/accept/pass; non-retry contact request; group invite; oversized eligible chat ciphertext |
| Direct ordinary zero-wake controls | direct deletion, `key_exchange_retry`, malformed/unrecognized envelope, and every current `ShouldNotify == false` branch |
| Direct reaction | eligible authorized ADD; REMOVE, ineligible, unauthorized and duplicate are zero-wake controls |
| Group discussion/announcement | text, media, voice, quote, forward and oversized rows only where the real group store currently admits a notification; deletion/system/ineligible rows remain zero-wake unless current source proves otherwise |
| Group reaction | eligible authorized ADD; empty nomination, duplicate, incapable and ineligible rows remain zero-wake controls |

The table asserts eligibility and zero-wake controls separately from shape.
Zero-wake rows invoke the real store/fanout eligibility seam; they must not call
the adapter directly and manufacture a wake the production store would never
request.
A first-class mention event is N/A because no such producer exists; do not invent
one for test completeness.

## Provider Log Contract

Replace the conflicting existing
`TestRelayNotificationClosure_WakeLinesCarryTransitionId` contract rather than
adding a second contradictory test. For touched provider/init/registration/send/
retry/revoke/group-reaction-wake lines:

- allow fixed event name, coarse outcome/reason enum, and bounded attempt count;
- forbid peer, sender, recipient, group, conversation, message, event,
  transition, reaction, handle, token, platform payload, ciphertext, raw provider
  body, and raw error string;
- keep aggregate counters and existing finite outcome labels;
- never place forbidden values in structured keys **or** formatted message text.

The test captures every owned `[PUSH]`, `[REDIS][PUSH]`, and touched
`[GROUP_REACTION_WAKE]` record, while ignoring unrelated inbox/group prefixes
that remain GAP-N10 work. No new logger or repository-wide journal assertion is
introduced.

This closes only the provider-facing portion coupled to GAP-N02. It does not
claim the repository-wide A-19/GAP-N10 audit.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-368-00 | Plan 367's checksum-valid durable receipt, frozen-tree/Graph identities, marker, seven tests, one resolver gateway, encrypted-state route API, and exact compare-revoke semantics exist before payload work | Plan-367 receipt/marker plus prerequisite commands above and current-source audit | dependency / durable receipt + current source | blocked on unexecuted Plan 367 -> provenance-bound prerequisite without API guessing | remove/alter receipt, marker or test, or reintroduce production `LookupToken` -> prerequisite fails | exact checksum and seven-test commands; no duplicate test owner |
| TC-368-01 | All four adapters use one happy-path route snapshot; opaque wins over rich capabilities; empty opaque handle, unknown platform, and non-stale lookup/resolve errors fail closed; legacy-incapable route preserves exact rich behavior; one stale retry may upgrade rich to opaque but never downgrade opaque | `TestRelayNotificationClosure_OpaqueWakeRouteSelectionAndLegacyCompatibility` | Go host / four-adapter capability/platform table + captured calls | HEAD has no opaque capability and duplicate reaction lookups -> one deterministic selection matrix | restore second happy-path lookup, admit an unknown platform, or allow opaque-to-rich downgrade -> adapter table/source guard fails | focused five-test bundle; existing relay-notification gate |
| TC-368-02 | Every eligible event produces the exact fixed Android Firebase request and no forbidden key/value; zero-wake events remain zero | `TestRelayNotificationClosure_OpaqueWakeAndroidProviderRequest` | Go host / real Firebase Admin SDK + httptest HTTP capture + event table | HEAD provider body varies by event and carries rich data -> exact token/data/Android config only | add one event field or omit priority/TTL/collapse -> byte-shape test fails | focused five-test bundle; existing gate |
| TC-368-03 | Every eligible event produces the exact fixed iOS Firebase request and no forbidden key/value; clock controls expiration | `TestRelayNotificationClosure_OpaqueWakeIOSProviderRequest` | Go host / real Firebase Admin SDK + httptest HTTP capture + injected clock/event table | HEAD APNs payload varies and carries routing/ciphertext/thread fields -> exact headers/localized APS/custom version only | restore thread/group/event field or change topic/expiry -> byte-shape test fails | focused five-test bundle; existing gate |
| TC-368-04 | Transient/permanent/size/stale failures preserve bounded retry; permanent failures compare-revoke exact generation; opaque never falls back rich; rich size fallback remains legacy-only | `TestRelayNotificationClosure_OpaqueWakeFailureAndGenerationSafeRevoke` | Go host / Firebase typed and captured errors + token-refresh interleavings | HEAD retries by peer/push-kind and can unregister current token -> immutable route retry and exact revoke | make revoke unconditional or map generic error to rich fallback -> error matrix fails | focused five-test bundle; existing gate |
| TC-368-05 | Touched provider logs/counters reveal no private value in key or message while finite outcomes/attempts remain diagnosable | `TestRelayNotificationClosure_ProviderWakeLogsOmitPrivateValues` replacing `TestRelayNotificationClosure_WakeLinesCarryTransitionId` | Go host / sentinel canaries through registration, init, all send/retry/revoke paths | HEAD intentionally logs transition/stable context -> fixed vocabulary without private values or raw errors | reinsert any canary into structured or formatted log -> forbidden-value test fails | focused five-test bundle; existing gate |

## Implementation

1. Verify TC-368-00 against Plan 367's final source and receipts. If the route
   API/marker differs, stop: update this plan by factual re-review rather than
   creating an adapter shim or third plan.
2. Add TC-368-02 first and record a semantic RED showing the captured Android
   request contains rich/event-varying data. Then add the other four tests with
   minimal compile-safe scaffolding.
3. Add `opaque_wake.go` with capability, fixed Android/APNs construction,
   trusted topic, one five-minute constant, and injected clock. Keep Firebase
   SDK request generation in the incumbent `PushService`.
4. Refactor the four adapters to the single-snapshot selection matrix. Keep
   Plan 367's upstream `recipientSupportsCapability` removal intact; preserve
   authorization, nomination, duplicate, store-before-push, and counters.
5. Refactor `sendWithRetry` to immutable resolved route/message. Apply the fixed
   message only on opaque selection, exact compare-revoke on permanent errors,
   and no opaque-to-rich fallback. Preserve strict size fallback only inside the
   incapable rich branch.
6. Replace the transition-ID log test with the provider-wake privacy test and
   sanitize only the touched log sites. Do not begin broad Dart/native/runtime
   logging work.
7. Run six serial mutation families: opaque precedence/second lookup/unknown
   platform; Android leaked
   event or wrong shape; iOS leaked event or wrong shape; generic-error rich
   fallback; unconditional revoke; log canary. Require the owning test to red,
   revert, and restore focused GREEN each time.
8. Register the existing unfiltered relay script as one synthetic non-Dart path
   in `scripts/run_host_test_gates.sh`, using the incumbent print/run dispatch;
   preserve Plan 367's tagged process synthetic. Add no wrapper. Run exact
   preservation sentinels, curated `groups`, hygiene, and one
   Graphify refresh. Then audit the combined Plans-367/368 final source and run
   the one N02-wave `host-all`, whose registered relay tail owns the final
   full-module sweep.

## Risks And Counterexamples

- **Capability downgrade leaks:** an opaque route that later errors must not
  silently use rich payload. TC-368-01/04 own precedence and stale retry.
- **Unsupported platform leakage:** current rich projection tolerates unknown
  platform strings. The opaque branch instead sends nothing; TC-368-01/04 own
  that refusal without adding a third adapter.
- **Sampled AC-11 proof:** testing only text would miss reaction/group/oversize
  builders. The platform event tables own every current producer.
- **Hand-built fixture false green:** assertions against a local struct can
  diverge from Firebase wire serialization. TC-368-02/03 capture the real pinned
  SDK HTTP request.
- **iOS silent/alert mismatch:** `mutable-content` plus localized alert is an
  alert push, not `content-available`. Exact headers/APS fields own this.
- **Lost reaction accounting:** removing the second lookup changes timing.
  Existing eligibility/counter sentinels remain, with async tests waiting for
  all expected deltas.
- **ABA revocation:** Plan 367 route/generation must survive the retry refactor.
  TC-368-04 and Plan-367 preservation tests own it.
- **Log-scope explosion:** only provider-coupled lines are sanitized. GAP-N10
  retains the cross-runtime inventory, preventing this plan from becoming a
  general logging redesign.
- **Default-off honesty:** current Dart clients advertise only incumbent
  reaction capabilities. Host tests register `opaque_wake_v1` directly; no
  production activation or client-readiness claim follows.

## Gate Cadence

### Focused discovery and GREEN

Exactly five Plan-368 tests must be discoverable and run without skips:

```bash
(
  set -euo pipefail
  cd go-relay-server
  plan368_focused_log="$(mktemp /tmp/plan368-focused.XXXXXX)"
  trap 'rm -f "$plan368_focused_log"' EXIT
  plan368_tests="$(
    GOTOOLCHAIN=go1.25.0 go test . -list \
      '^TestRelayNotificationClosure_(OpaqueWake(RouteSelectionAndLegacyCompatibility|AndroidProviderRequest|IOSProviderRequest|FailureAndGenerationSafeRevoke)|ProviderWakeLogsOmitPrivateValues)$'
  )"
  test "$(printf '%s\n' "$plan368_tests" | rg -c '^TestRelayNotificationClosure_')" -eq 5
  GOTOOLCHAIN=go1.25.0 go test . \
    -run '^TestRelayNotificationClosure_(OpaqueWake(RouteSelectionAndLegacyCompatibility|AndroidProviderRequest|IOSProviderRequest|FailureAndGenerationSafeRevoke)|ProviderWakeLogsOmitPrivateValues)$' \
    -count=1 -v | tee "$plan368_focused_log"
  test "$(rg -c '^--- PASS: TestRelayNotificationClosure_(OpaqueWake|ProviderWake)' "$plan368_focused_log")" -eq 5
  ! rg -q '^[[:space:]]*--- SKIP: TestRelayNotificationClosure_(OpaqueWake|ProviderWake)' "$plan368_focused_log"
)
```

### Exact preservation sentinels

```bash
(
  set -euo pipefail
  cd go-relay-server
  plan368_preservation_re='^(TestRelayNotificationClosure_DirectStoreTriggersPushAfterPersistence|TestRelayNotificationClosure_DirectDuplicateDoesNotRefanoutPush|TestRelayNotificationClosure_DirectReactionDuplicateDoesNotRefanoutPush|TestInboxStore_ReactionAddRequiresCapabilityAndAuthorization|TestInboxStore_ReactionNonAddOrIneligibleNeverSendsPush|TestInboxStore_ReactionCapabilityRolloutAndRollback|TestGroupReactionCapabilityRolloutAndRollback|TestRelayNotificationClosure_GroupReactionWakeEmptyNominationCounted|TestRelayNotificationClosure_GroupReactionWakeIncapableSkipCounted|TestRelayNotificationClosure_SilentWakeGuardsAreCounted|TestRelayNotificationClosure_WakeOutcomeLabelsRemainCompatible|TestRelayNotificationClosure_OrdinaryPushAndroidProjectionStripsApns|TestRelayNotificationClosure_OrdinaryPushIosProjectionDropsDuplicateData|TestRelayNotificationClosure_PermanentTokenErrorEvictsWithoutRetry|TestRelayNotificationClosure_TransientErrorKeepsRetryLadderAndToken)$'
  plan368_preservation_log="$(mktemp /tmp/plan368-preservation.XXXXXX)"
  trap 'rm -f "$plan368_preservation_log"' EXIT
  test "$(GOTOOLCHAIN=go1.25.0 go test . -list "$plan368_preservation_re" | rg -c '^Test')" -eq 15
  GOTOOLCHAIN=go1.25.0 go test . -run "$plan368_preservation_re" \
    -count=1 -v | tee "$plan368_preservation_log"
  test "$(rg -c '^--- PASS: Test' "$plan368_preservation_log")" -eq 15
  ! rg -q '^[[:space:]]*--- SKIP: Test' "$plan368_preservation_log"
)
```

The ordinary rich projection assertions remain exact for an incapable route;
they are compatibility tests, not the opaque-path target. Any existing test
that universally requires rich data must be narrowed explicitly to that legacy
fixture or replaced by the fixed provider-capture test—never silently deleted.

### Affected plan gates

```bash
(
  set -euo pipefail
  bash scripts/run_test_gates.sh groups
  (cd go-relay-server && GOTOOLCHAIN=go1.25.0 go vet ./...)
  test -z "$(rg --files go-relay-server -g '*.go' -0 | xargs -0 gofmt -l)"
  git diff --check
  ./graphify-arch/refresh_arch_graph.sh --incremental
)
```

Curated gates run only `^TestRelayNotificationClosure_`. The new synthetic
`host-all` path invokes the already-existing
`scripts/test/run_relay_all_go_309.sh`, so the complete relay module runs exactly
once on the final Plan-368/N02-wave tree without a new wrapper or a duplicate
per-plan sweep.
Plan 367 already owns the N02 batch's curated `1to1` run; repeating it here
would execute the same relay closure family again. Plan 368 keeps only curated
`groups` because its final adapter/counter change includes group paths.

### One N02-wave gate

After the combined current-source audit proves Plans 367 and 368 are both on
that tree, run exactly once:

```bash
./scripts/run_host_test_gates.sh host-all
```

This is the dependency-wave gate, not a default per-plan repetition. Do not add
a third closure/audit plan or another `host-all`; record audit and wave receipts
inside Plan 368's execution section. Its non-Dart tails must include the
unfiltered relay module and Plan 367's exact tagged process-handoff test.

No phone is required or useful for this Go provider-contract slice. WP-04/WP-05
own native consumption. If a later mobile proof is justified, project policy
uses the discovered USB Android plus Android emulator by default; unavailable
hardware is never a blocker.

## Acceptance

- [x] TC-368-00 verifies Plan 367's checksum-valid durable receipt, frozen-tree
  and Graph identities, exact marker, seven focused tests, gateway, and
  compare-revoke contract before any RED.
- [x] Exactly five causal tests are discoverable, non-skipped, and green.
- [x] Every implemented eligible event fixture produces the identical captured
  Android request and the identical captured iOS request within its platform.
- [x] Both captured requests match the exact allow-list and contain none of the
  PRD-forbidden fields or values; the opaque handle never reaches the provider.
- [x] All four adapters use one happy-path route snapshot; opaque precedence, empty-handle
  refusal, error refusal, stale retry, and no-downgrade behavior are proven.
- [x] Legacy incapable clients retain current rich behavior, authorization,
  reaction capabilities, store-before-push, dedupe, metrics, retry, and strict
  size fallback.
- [x] Permanent provider errors revoke only the exact generation; generic
  failures never trigger rich fallback for opaque requests.
- [x] Provider-coupled logs use fixed coarse fields and reveal no canary private
  value or raw error; no broad GAP-N10 claim is made.
- [x] Six mutations re-red their owning tests and are reverted.
- [x] Focused, preservation, curated `groups`, full relay, vet/format/diff,
  and one Graphify refresh pass on the final tree.
- [x] Combined Plans-367/368 audit and one N02-wave `host-all` pass; no third
  plan, device leg, deployment, activation, or release claim is added.

## Done

All acceptance items, the combined current-source audit, and the single
complete N02-wave gate passed. The closure receipt records:

```text
N02_OPAQUE_WAKE_MECHANISM_CODE_COMPLETE
```

This closes the default-off GAP-N02 host mechanism and captured provider-shape
contract. Current production clients still do not advertise `opaque_wake_v1`;
therefore this marker does not claim universal provider privacy, live migration,
mixed-version retirement, native presentation, S2 acceptance, A-control PRD
acceptance, or release eligibility.

## Handoff

- WP-04 iOS and WP-05 Android implement and prove consumer readiness but do
  **not** advertise the capability.
- WP-06/07 alone enable capability advertisement after encrypted-marker/route
  availability, rollback prerequisites and mixed-version observation pass;
  they also own rich-path
  retirement, token-vault live migration/cleanup, deployment/rollback, device
  evidence, and release closure.
- GAP-N10 owns unrelated runtime logs; preserve the provider-wake sanitation
  established here.
- No Plan 369 is required for N02. Any review/audit receipt is appended here,
  not promoted into another implementation slice.

## Reviewer Findings

`READY WHEN PREREQUISITE PASSES`; no remaining contract defect.

- **L1 behavior:** every eligible producer converges to one fixed request per
  known platform; incapable clients alone retain the rich compatibility path.
  Empty handles, unknown platforms and non-stale lookup/crypto/resolve errors
  send nothing, while explicit stale has one shared re-selection with an exact
  no-downgrade rule.
- **L2 implementation:** one `opaque_wake.go` helper under the incumbent
  `PushService` is enough. The four adapters keep authorization, persistence,
  dedupe and counters; no platform service, config layer, queue or client code
  is introduced.
- **L3 proof:** five causal tests cover selection, Android bytes, iOS bytes,
  generation-safe failure and owned logs. Real Firebase SDK capture, complete
  eligible/zero-wake tables, 15 preservation sentinels, six mutations, exact
  counts and child-skip rejection prevent fixture-only or vacuous green.
- **L4 integration:** dependency evidence is checksum/frozen-tree/Graph-bound;
  WP-04/05 implement consumers but do not advertise before WP-06/07 admission.
  Plan 367 owns curated `1to1`; this plan owns curated `groups`, the combined
  audit and one N02-wave `host-all` with the full relay registered once.
- **L5 operation:** `opaque_wake_v1` remains absent from production defaults.
  Provider-facing log sanitation is restricted to owned/touched prefixes;
  unrelated GAP-N10 work, deployment, migration and rich retirement remain
  outside this slice.

Evergreen blind spots are explicit: provider capture proves the relay request,
not native presentation; native readiness/advertising belongs to later WPs;
unavailable phone versions cannot gate this Go-only plan; and the legacy path
cannot be retired from host evidence alone.

## Arbiter Decision

`prerequisite-blocked / contract-ready`. The reviewed five-owner test structure
is coherent and sufficient. Keep the shared, exactly-once explicit-stale
re-selection inherited from Plan 367; it neither creates a second gateway nor
permits opaque-to-rich downgrade. Do not split Android, iOS, producers, logs or
final audit into more plans. The combined audit and wave receipt live in this
artifact, so N02 has exactly two implementation plans.

## Execution Progress

| Time | Stage | Evidence | Verdict / next action |
|---|---|---|---|
| 2026-08-15 12:21 CEST | TC-368-00 prerequisite | `evidence/367/README.md.sha256` verified `README.md: OK`; receipt SHA-256 `b0253505ed8bdb2ca3cb352e6179edf85e6290d16503667c5d3949c2e5f61a89`; exact marker present; frozen tested tree `9ec76e3f99e222ba446801f2e5e1281725bdc05b`; frozen snapshot SHA-256 `3473c3919085622bc9b9dabc9780a682789a3371858e641e2aa1648157075ff8`; Graphify `76c930dc8afc22a2`; 86 scoped frozen blobs matched current source; all seven exact prerequisite tests discovered and passed with zero skips. | **PASS.** The checksum-bound Plan 367 API is the implementation base; no shim or third plan is needed. |
| 2026-08-15 12:23 CEST | TC-368-02 semantic RED | A real Firebase Admin SDK request for an Android route advertising literal `opaque_wake_v1` still serialized `sender_id`, `message_id`, `kem`, `ciphertext`, `nonce`, `type`, and `envelope_version`, and omitted fixed `ttl` / `collapse_key`. `TestRelayNotificationClosure_OpaqueWakeAndroidProviderRequest` failed on exact request-map inequality. | **EXPECTED RED.** The test exercised the incumbent rich provider boundary rather than failing on compile scaffolding. |
| 2026-08-15 12:31 CEST | First production GREEN + preservation checkpoint | The same real-SDK Android request matched token + `data={v:1,w:1}` + Android high/300s/mailbox exactly. Plan 367's single-resolver/stale source guard and the exact 15 Plan 368 preservation sentinels passed; `go vet ./...` and scoped diff hygiene passed. | **INTERIM GREEN.** Complete the remaining causal owners, mutations, final gates, Graphify refresh, combined audit, and single N02-wave `host-all` before closure. |
| 2026-08-15 final proof audit | Late independent counterexample audit and repair | A provisional `host-all` was stopped at row 83 and was not counted after the audit found proof gaps in the exact producer census, real-store group fixtures/zero controls, stale transition matrix, typed Firebase permanent-error fixture, runtime log-path coverage, and platform canonicalization. The repaired tests pin 22 exact source-eligible producer names, real store/fanout behavior, opaque-to-fresh-opaque and terminate transitions, mixed-case/whitespace known platforms, real typed SDK errors, and all promised provider log paths. | **PASS AFTER REPAIR.** The stopped run is diagnostic history; only the later complete final-tree wave run is authoritative. |
| 2026-08-15 final focused proof | TC-368-01 through TC-368-05 | Exactly five tests discovered (SHA-256 `9f8f6c790334c3e4b76540f6c364f5fa739ca3afbdba4148926c229718de0e1d`) and 5/5 passed with zero skips (run SHA-256 `c53b8a16a2b623fc33f79e199d5420311a90fb009e5d2ff9471d8e28e3f4906b`). The shared 22-fixture source-eligible producer census generated 22 real Firebase SDK HTTP captures on Android plus 22 on iOS: 44 exact fixed requests. Ineligible, unauthorized, duplicate, malformed, and no-notify controls traversed real stores/fanout seams and emitted zero requests; ordinary group deletion/system truth follows current source rather than a manufactured zero. | **PASS.** Fixed Android/iOS shapes, route selection, exact revoke/no-rich fallback, legacy preservation, counters, and all 35 owned provider log sites are causally owned. |
| 2026-08-15 final mutation/preservation proof | Six mutation families plus exact sentinels | Opaque precedence/second lookup/unknown platform, Android leak/wrong shape, iOS leak/wrong shape, generic-error rich fallback, unconditional revoke, and provider-log canary each produced the required RED alone, were reverted, and restored owner GREEN. Raw mutation logs were not retained and no hashes are invented. Preservation discovery found exactly 15 tests (SHA-256 `850e88deccdc99f7556efa4d69471f6352c6a3f605a235399605a865af9b2fd6`); 15/15 passed, zero skips (run SHA-256 `0e56c1418d4a00fca8ead4b057b119493c3fdaba83a868970f5cef4a3bac3863`). Final Plan-367 revalidation also passed 7/7, zero skips (run SHA-256 `c8176f3b0c279a9a1f5d6bf62b9ca9b76b6ee9629b7f91dd853733c07c1b82ee`). | **PASS.** No `PLAN368 MUTATION` marker remains; route custody, rich compatibility, eligibility, dedupe, accounting, retry, and generation safety are preserved. |
| 2026-08-15 final affected gates | Curated lane, static hygiene, and host registration | `bash scripts/run_test_gates.sh groups` passed 4,199 Flutter tests plus registered Go bridge/node/relay tails (log SHA-256 `84966e1f76ebd0f781ff634ecdf9bfeb38b7956a7c9cd93f975910beb6ac7222`). `go vet ./...` and `gofmt -l` emitted nothing; `git diff --check` was clean; changed scripts passed `bash -n`. The batched-host contract passed with 10 synthetic rows / 11 Go calls (log SHA-256 `02bd1fce20bfdc96f6eb19133b590015169d7e0dc978db1a1555ae897be0bf50`). | **PASS.** Plan 367's tagged process and the existing unfiltered relay script are each registered exactly once. |
| 2026-08-15 final Graph/audit | Incremental Graphify refresh and combined current-source audit | Freshness/confidence `current`/`anchored`; fingerprint `27ea9a664ebf98d9`; 75,606 nodes / 110,505 edges; overlay 1,575 files / 15,658 named tests / 1,241 targets. SHA-256: graph `e88b91497ad79a456f47d5e772b9086b9e4b76cd01b66c4b577ee3e8efb79876`, manifest `28a41854a3a7ab789d0ffb9d1f8c94fc1db704f5b4f4ea6cdfec39c598c7d209`, overlay `40e472253c6806895359a6b664e5d1f97de7b795685253009c68ca15723b6087`. Production audit: `LookupToken` 0; `LookupRoute` 1; `ResolveRoute` 1; selector calls 7; selected-send definition+callers 5; private gateway definition+callers 3; token injection 1; `mailboxDirty` call 1; removed capability helper 0; owned provider logs 35; production capability advertisement 0; mutation markers 0. | **PASS.** One resolver/token boundary and one bounded shared reselect remain; fixed builders/log vocabulary/default-off ownership have no counterexample. |
| 2026-08-15 N02-wave closure | Complete `host-all`, final freeze, and durable receipt | The authoritative `host-all` passed exactly 1,357/1,357 rows with 0 skipped/failed (log SHA-256 `b0132cb137865dd2b5de50207aeaf243894590054c7f9daa1679e4850f2f6da3`): Flutter rows 1-1,347, incumbent/Plan-367 Go rows 1,348-1,356, tagged process exactly once at #1,356, and the full relay exactly once at #1,357 (`21.785s`). Alternate-index capture at `2026-08-15T15:09:40+0200` froze tested tree `924e8f64ebc7c9dca2de83890ecad144fefbdaf2` on unchanged HEAD/base `3865aa9b8b8b000ecaf871a839d1fbdecaa0d86c`; porcelain snapshot SHA-256 `d15109f11a37cda022fd90e44526d5bf15b03091578d3dd3ccf71738d5676428` (244 records). Receipt: `evidence/368/README.md` plus sibling checksum. | **CLOSED AT THE HOST-MECHANISM TIER.** No commit, deployment, device leg, key/migration action, capability activation, rich retirement, A-control acceptance, or release occurred. |

Execution is closed with exact marker
`N02_OPAQUE_WAKE_MECHANISM_CODE_COMPLETE`. `N02_COMPLETE=false` and live
acceptance remains false: production capability advertisement and migration are
default-off, the mixed-version rich path remains reachable, and native/device,
A-control, deployment, activation, and release work remain with later work
packages. The checksum-bound durable details are in
`Test-Flight-Improv/evidence/368/README.md`, SHA-256
`0d6747b448a97103b750eaa275a37ded1cceeff096582b0fb05b15d1357ca5f1`.
