# 367 - GAP-N02 Opaque Push Handle And Encrypted Token Vault Migration

Status: **POST-EXECUTION AUDIT CLOSED / N02 OPAQUE HANDLE FOUNDATION CODE COMPLETE / N02 SLICE 1 OF 2 / DEFAULT-OFF MIGRATION / NOT N02-COMPLETE / NOT RELEASE-ELIGIBLE**
Type: Modification
Spec: `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2.md` privacy contract and target architecture requirements 4-5; GAP-N02 / WP-02 in `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md`
Classification: additive relay storage/routing foundation; preserves the incumbent rich provider payload until Plan 368
Closure tier: relay host + tagged Redis process handoff; no device or deployment leg

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-15 | Evidence Collector | Plan 366 final receipt; PRD and GAP-N02; `PushTokenBackend`; memory/Redis token stores; bootstrap; all four push senders; registration/unregister handlers; provider retry/revoke tests; gate scripts | N01's mechanism dependency is provenance-bound and green. Current relay storage exposes plaintext provider tokens through a peer-keyed interface and permanently deletes by peer after provider errors. | Define one opaque route lease and one encrypted Redis migration boundary. |
| 2026-08-15 | Planner using `$tdd-plan` | Current source, Graphify architecture/TDD context, Plan 327, Firebase Admin SDK dependency and Redis integration precedent | Split N02 at its two real rollback boundaries: Plan 367 owns token custody/migration and Plan 368 owns fixed provider payloads. Do not split by platform or producer. | Obtain independent `$tdd-review`, then execute TC-367-01 RED. |
| 2026-08-15 | Independent reviewers using `$tdd-review` | Route API; Redis states/AAD; refresh, revoke and cleanup races; all four senders; exact tests and gates; Plan-366 receipt | Review findings were incorporated: complete AAD, atomic no-orphan rotation including provider environment, migrated-source invalidation, synchronous group accounting, non-vacuous counts/child-skip guards, durable successor receipts and proportional wave gates. No third plan or new runtime owner is justified. | Arbiter decides the sole stale-route policy dispute. |
| 2026-08-15 | Arbiter | Corrected plan plus scope, proof-boundary and delivery-economy reviews | READY. Retain one shared, exactly-once re-selection on explicit stale; it closes the lookup-to-resolve refresh race without exposing identity or duplicating policy across adapters. | Execute TC-367-01 RED from the receipt-bound dependency. |

## Problem And Evidence

The relay currently exposes provider material too early:

- `PushTokenBackend` returns `*tokenEntry` directly from
  `go-relay-server/inbox_store.go:40-56`.
- the memory backend maps peer ID to token entry in
  `go-relay-server/push_token_store.go`;
- Redis uses a peer-derived key and plaintext JSON token entry at
  `go-relay-server/backend_redis.go:1454-1539`;
- direct, direct-reaction, group-reaction, and group send paths call
  `LookupToken` before building/sending provider messages at
  `go-relay-server/inbox.go:161-249`;
- permanent provider failures unregister the peer-wide current row at
  `go-relay-server/inbox.go:310-350`, so a delayed failure can erase a newer
  registration;
- explicit unregister is void and its stream handler acknowledges without a
  durable-delete result at `go-relay-server/inbox.go:2651-2673`.

This contradicts the PRD boundary in which message code carries only an opaque
push handle while a private gateway resolves an encrypted provider token. It
also makes safe token/environment rotation and mixed-binary migration
impossible.

Plan 367 deliberately does **not** change the rich provider payload. It makes
all four incumbent senders real adopters of the new private resolution gateway
so the storage boundary cannot be dead code. Plan 368 then replaces the rich
message at that same gateway with the fixed mailbox-dirty request.

## Dependency And Provenance

The N01 dependency is exactly:

- receipt: `Test-Flight-Improv/evidence/366/README.md`;
- receipt SHA-256: `5c3843a5f4059652b83a58e57909ab8bcf3a99c78ba5587a5efd6ccdfda5753b`;
- frozen tested tree: `0765646f6c60140424e5320552d38ed0e5a2fce8`;
- Graphify fingerprint: `19e306d1432ccbf1`;
- marker: `N01_MECHANISM_CODE_COMPLETE`.

No clean source commit, S2 authorization, relay deployment, cumulative B1b, or
`N01_LIVE_ACCEPTANCE_PROVEN` is a Plan-367 prerequisite. Those remain later
WP-07 acceptance/release work.

Plan 327 is historical and unexecuted. Its per-event routing-token stages are
superseded by PRD v1.2's stable opaque **push-handle** gateway and the two-plan
367/368 delivery. Do not implement Plan 327 alongside this plan.

## Graph Grounding

- Compact planning queries were anchored on `PushTokenBackend`,
  `redisPushTokenBackend`, `tokenEntry`, `PushService`, registration handlers,
  all four notification senders, and the registered relay gate.
- Planning architecture graph fingerprint: `19e306d1432ccbf1`; the refreshed
  final-source identity is recorded in the execution receipt.
- Direct source verification remains authoritative for the Go relay because
  Graphify's app-owned graph is a shortlist, not a substitute for Go symbol
  reads.
- Reuse anchors:
  - interface: `go-relay-server/inbox_store.go`;
  - memory implementation: `go-relay-server/push_token_store.go`;
  - Redis implementation: `go-relay-server/backend_redis.go`;
  - composition: `go-relay-server/server_bootstrap.go` and existing main CLI;
  - provider gateway/adopters: `go-relay-server/inbox.go` and
    `reaction_push.go`;
  - real Firebase SDK request capture:
    `go-relay-server/push_permanent_error_closure_test.go`;
  - multi-process/miniredis precedent:
    `go-relay-server/redis_failover_integration_test.go`;
  - gate registration: `scripts/run_test_gates.sh`.

## Scope Contract And Guard

### In scope

- one package-private route lease that contains an opaque handle, generation,
  copied capabilities, and private compare/revoke material—but no provider
  token or platform;
- one private provider gateway inside `PushService`; it is the only production
  caller allowed to resolve a route into token/platform;
- AES-256-GCM encryption of Redis provider-token records using Go standard
  library primitives, random nonces, a file-backed keyring, active/retained
  key IDs, and trusted provider-environment binding;
- disjoint Redis legacy, migration-marker, directory, and vault namespaces;
- one three-state, revision-fenced, crash-resumable migration protocol with no
  write downtime;
- generation-safe permanent-error revocation and error-bearing explicit
  unregister;
- the memory backend implementing the same route/generation contract while
  keeping its token only in process memory;
- all four existing rich senders using the gateway with byte-equivalent
  provider messages until Plan 368;
- one explicit migration/cleanup CLI family and one tagged process-handoff
  proof, run exactly during this plan and registered as one exact synthetic
  tail for later wave-level `host-all`.

### Out of scope

- fixed or content-free APNs/FCM payloads, provider-log sanitation, and AC-11
  closure (Plan 368);
- Dart/native consumer changes, capability advertisement, localization, phone
  tests, or iOS builds (WP-04/WP-05 and later acceptance);
- live Redis migration, production key provisioning, deployment, fleet
  provenance collection, legacy cleanup execution, activation, or rollback
  drills (WP-07);
- a new service/package/provider adapter, queue, daemon, goroutine, scheduler,
  admin HTTP endpoint, general migration framework, reverse-token index, or
  second token backend.

Hard scope stop: if correctness requires any durable owner beyond the four
namespaces below, or a background worker to converge migration/rotation, stop
and re-review. The expected production addition is one helper file,
`go-relay-server/push_token_vault.go`, plus edits to existing owners.

## Canonical Route And Gateway Contract

The implementation may adjust names mechanically, but not weaken this shape:

```go
type pushRouteLease struct {
	Handle       string
	Generation   uint64
	Capabilities []string

	lookupKey    string
	legacyDigest [32]byte
}

type resolvedPushTarget struct {
	Route    pushRouteLease
	Token    string
	Platform string
}

type PushTokenBackend interface {
	RegisterToken(peer, token, platform string, capabilities ...string) error
	UnregisterToken(peer string) error
	LookupRoute(peer string) (*pushRouteLease, error)
	ResolveRoute(route pushRouteLease) (*resolvedPushTarget, error)
	RevokeIfCurrent(route pushRouteLease) (bool, error)
	TokenCount() int
	PlatformCounts() map[string]int
}
```

Contract rules:

- `LookupRoute` returns `(nil, nil)` only when no registration exists. Storage,
  crypto, marker, or integrity faults are errors.
- `Capabilities` is a defensive copy. `pushRouteLease` has no `Token`,
  `Platform`, `Entry`, or `UpdatedAt` field.
- empty handle/generation zero is allowed only for absent/migrating legacy
  compatibility. Encrypted state requires a nonempty random opaque handle and
  positive generation.
- `legacyDigest` hashes the exact persisted legacy row—not just its token—so a
  token, platform, capability, or refresh change invalidates the lease.
- `ResolveRoute` returns `ErrPushRouteStale` for a changed or missing exact
  lease. `mailboxDirty`/provider resolution itself remains route-only and
  returns that error to its caller. The
  shared outer selection helper, called by the adapter that already owns the
  authenticated recipient peer for its initial lookup, restarts selection
  exactly once and must recheck capabilities; it
  never adds an exported/raw peer field or provider-visible peer value. The
  private `lookupKey` may carry the exact backend lookup material needed to
  resolve/revoke legacy storage without a scan or reverse index, and a source
  guard prevents it from leaving the gateway. Happy path performs one lookup;
  explicit stale performs exactly one additional full selection and a second
  stale result terminates. This exception is implemented once in the shared
  selection helper, not copied into four adapters.
- `resolvedPushTarget.Route` equals the exact input lease. A permanent initial
  or strict-fallback provider failure passes that route to `RevokeIfCurrent`.
- a legacy route resolved just before migration CAS remains conditionally
  revocable through the migrated row's retained source digest; a concurrent
  registration refresh makes it a no-op.
- `UnregisterToken` remains the authenticated unconditional user action and
  may be acknowledged only after its atomic durable deletion succeeds.
- production `LookupToken` is removed. Only the private gateway calls
  `ResolveRoute`; event-specific code sees route/capabilities, not token. The
  outer selection helper handles the returned stale error and is the only
  production owner allowed to repeat `LookupRoute`.

## Storage, Crypto, Migration, And Rollback Contract

### Minimal configuration

- `PUSH_TOKEN_KEYRING_FILE`: trusted local keyring file;
- `PUSH_TOKEN_ACTIVE_KEY_ID`: active encryption key;
- `PUSH_PROVIDER_ENVIRONMENT`: trusted deployment environment included in AAD.

The keyring is one exact versioned JSON object,
`{"version":1,"keys":{"<key-id>":"<base64-32-byte-key>"}}`; no alternate
formats or embedded active-key selector are introduced. Key IDs and the
environment are nonempty bounded ASCII identifiers. Keys are exactly 32 bytes
after strict base64 decoding. Missing, duplicated, malformed, unknown, or
ambiguous key IDs fail startup when migrating/encrypted state is in use; absent
legacy mode does not become unavailable merely because vault configuration is
not yet present. New vault/config/migration/CLI code never logs key material,
provider tokens, plaintext records, nonces, peer IDs, handles, or ciphertext;
Plan 368 separately sanitizes incumbent provider send/retry logs.

### Redis namespaces

- legacy: `<prefix>push:<peer-component>` (existing exact bytes);
- marker: `<prefix>push-token-state`;
- directory: `<prefix>push-token-directory:<peer-component>`;
- vault: `<prefix>push-token-vault:<opaque-handle>`.

The directory stores only handle, generation, platform classification,
capabilities, provider environment, and source legacy digest. The vault value
stores only `{schema,key_id,nonce,ciphertext}`; its key/value contains no peer
or plaintext token. AES-GCM AAD binds schema, a peer digest, handle, generation,
platform, canonical sorted-unique capabilities, retained source legacy digest,
provider environment, and key ID. Tamper, capability promotion/removal,
source-digest substitution, cross-environment replay, row swapping, or unknown
key ID fails closed.

### Exactly three states

1. **Absent**: marker missing. Old/new binaries coexist against the exact legacy
   bytes. Merely configuring a keyring changes nothing. A Plan-367 writer WATCHes
   the marker before a legacy mutation so the migration CAS cannot race it.
2. **Migrating**: entered only by an explicit CLI after a syntactically valid
   64-hex operator-supplied fleet-receipt identifier is supplied. Legacy remains read/write
   authority; every register, unregister, and compare-revoke atomically mutates
   legacy and increments the same marker revision. The migrator reads a
   revision, scans/reconciles an exact legacy-to-directory/vault bijection,
   verifies every row decrypts and matches, repeats after revision drift, and
   CASes that exact revision to encrypted.
3. **Encrypted**: directory/vault only. There is no legacy fallback or legacy
   write. The old namespace is removed only by a separate explicit idempotent
   cleanup command after this marker exists.

There is no fourth `clean` state, dual-write epoch, or background migration.
The only CLI family is:

```text
push-token-vault migrate --fleet-receipt-sha256 <64hex>
push-token-vault cleanup-legacy
```

Plan 367 implements and host-tests these commands but does not run them against
a live environment. The CLI validates and persists only the identifier's exact
syntax; it cannot authenticate the referenced receipt or grant admission.
WP-07 must independently validate the receipt, authorization and compatible
fleet before invoking the command.

Rollback is explicit:

- old and Plan-367 binaries may coexist only while the marker is absent;
- entering migrating requires WP-07's independently validated all-frontends
  Plan-367 receipt and authorization, because a pre-367 writer cannot increment
  the shared revision;
- after either migrating or encrypted is recorded, only Plan-367-compatible
  binaries with the required retained keys may serve traffic; a failed
  migration is resumed from its marker rather than demoted to absent;
- a pre-367 binary is a valid rollback only before the migrating marker exists;
- legacy cleanup is a later, explicit, idempotent operation and never an
  automatic side effect of migration.

Key rotation uses active plus retained keys. Resolve/register may lazily CAS
rewrap an exact unchanged row under the active key without changing generation.
No mass-rewrap worker exists. A destination token, platform, or trusted provider
environment change atomically creates the new handle/generation directory+vault
pair and deletes the prior vault row in the same transaction. A registration in
the new trusted environment may replace the old directory pair without
decrypting the old-environment token; the old row never resolves under the new
environment. Capability change retains handle/generation
but atomically reseals the vault because capabilities are AAD; timestamp
normalization or key rewrap also retains generation. Explicit unregister and
successful compare-revoke atomically delete the directory and its exact current
vault row. No refresh, unregister, or revoke may leave an orphan vault row.
The retained source legacy digest exists only on the row created by migration.
Every successful post-cutover `RegisterToken`—including an exact same-token,
same-platform, same-capability refresh—atomically clears it and reseals the row,
so a pre-CAS legacy lease can no longer revoke after that refresh.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-367-01 | Absent/migrating/encrypted admission is explicit; keyring alone is inert; missing/malformed fleet-receipt SHA changes nothing; an exact 64-hex identifier is persisted without being treated as authorization; absent writes fence marker changes | `TestRelayNotificationClosure_PushRouteLegacyCoexistenceAndMigrationAdmission` | Go host / miniredis + bootstrap/CLI fixture | HEAD has only unmarked peer-keyed plaintext -> exact three-state admission with legacy coexistence, receipt-identifier syntax/persistence, and startup refusal matrix | remove marker WATCH/revision check -> concurrent migration row fails | focused seven-test bundle; registered by existing relay-notification gate |
| TC-367-02 | Directory/vault separation, complete AES-GCM AAD/environment isolation, route field privacy, token/platform/environment handle+generation rotation, retained-key decrypt/lazy rewrap, and zero orphan vault rows are exact | `TestRelayNotificationClosure_PushRouteDirectoryCiphertextAndGenerationContract` | Go host / miniredis + reflection + deterministic keys/random source | HEAD Redis contains plaintext token and route exposes `tokenEntry` -> no raw token/social identity in vault; capability/source-digest tamper, swap, env/key faults close; refresh deletes prior vault atomically; authenticated re-registration in a changed trusted environment leaves one new pair and the old row never resolves | store plaintext, omit an AAD authority field, or retain the prior vault on refresh/environment rotation -> ciphertext/privacy/cardinality matrix fails | focused seven-test bundle; existing gate |
| TC-367-03 | Revision-fenced migration converges during register, unregister and compare-revoke without write downtime or resurrection | `TestRelayNotificationClosure_PushRouteMigrationRevisionFenceConvergesWithoutWriteDowntime` | Go host / miniredis interleaving hooks | HEAD has no migration -> exact bijection at one stable revision then CAS; crash/retry is idempotent | stop incrementing revision on one mutation -> crossed interleaving fails | focused seven-test bundle plus `-race`; existing gate |
| TC-367-04 | Direct, direct-reaction, group-reaction and group rich senders receive only a route; the single gateway resolves/injects token/platform; happy path is one snapshot; explicit-stale retry is bounded and rechecks capability | `TestRelayNotificationClosure_PushRouteEncryptedResolutionFeedsEveryRichSender` | Go host / table of all four send adapters + captured provider messages | HEAD calls `LookupToken` in each sender -> one lookup/gateway resolution and byte-equivalent incumbent provider request; group capability outcome remains at its synchronous pre-goroutine point and passes one immutable route inward | restore an upstream token lookup/second resolver caller or move group accounting behind the goroutine -> table/source/counter guard fails | focused seven-test bundle; existing gate |
| TC-367-05 | Permanent initial and strict-fallback errors revoke only the exact lease across refresh, ABA and legacy-to-encrypted cutover, deleting its directory+vault pair without orphaning | `TestRelayNotificationClosure_PushRoutePermanentErrorCompareRevokesExactLease` | Go host / real Firebase SDK httptest + memory/miniredis | HEAD peer-wide unregister can erase a fresh token -> exact-generation compare-revoke and exact pair deletion; stale lease is no-op; every post-cutover registration clears retained legacy digest | replace compare-revoke with peer delete, retain its vault, or retain source digest after refresh -> refresh/cutover/cardinality rows fail | focused seven-test bundle; existing gate |
| TC-367-06 | Authenticated explicit unregister acknowledges only after atomic directory+vault deletion and propagates backend failure | `TestRelayNotificationClosure_PushRouteExplicitUnregisterAcknowledgesOnlyAtomicDelete` | Go host / libp2p stream + failing memory/Redis backend | HEAD void unregister always returns OK -> success only after durable pair deletion with zero orphan; finite error otherwise | send OK before backend result or split the pair deletion -> failure/cardinality fixture catches false ACK | focused seven-test bundle; existing gate |
| TC-367-07 | Legacy cleanup is allowed only after encrypted marker, removes only legacy namespace, and is idempotent | `TestRelayNotificationClosure_PushRouteExplicitLegacyCleanupIsIdempotent` | Go host / miniredis mixed unrelated keys | HEAD has no bounded cleanup -> pre-marker refusal and exact post-marker cleanup | permit premature or prefix-wide deletion -> preservation rows fail | focused seven-test bundle; existing gate |
| TC-367-08 | Encrypted directory/vault state, generation and retained-key resolution survive independent relay processes | `TestRedisPushRouteVaultEncryptedStateSurvivesProcessHandoff` | tagged Go integration / miniredis + helper subprocess | HEAD process fixture knows only plaintext token rows -> process B resolves process A's encrypted row; stale process lease cannot revoke refresh | fall back to process memory or omit persisted generation -> handoff fails | exact `-tags integration` command now; one synthetic later-wave `host-all` registration; no curated-gate repetition |

## Implementation

1. Snapshot source/provenance and verify the Plan-366 receipt checksum. Record
   current `HEAD`, dirty baseline, Go toolchain, Graphify fingerprint, and the
   current legacy Redis bytes.
2. Add TC-367-01 first. Its initial RED must be semantic (the only Redis token
   value is readable plaintext and no state marker exists), not a vacuous
   compile failure. Add the remaining causal contracts with the minimum inert
   scaffolding needed to keep the package compiling.
3. Introduce `pushRouteLease`, `resolvedPushTarget`, `ErrPushRouteStale`, and the
   revised `PushTokenBackend`; adapt memory storage first and keep its semantics
   generation-safe.
4. Implement `push_token_vault.go`: strict keyring/config parsing, AES-GCM
   seal/open, AAD, namespaced row codecs, exact integrity checks, and the three
   marker states. Use `crypto/rand`; tests inject deterministic entropy/clock.
5. Implement Redis absent/migrating/encrypted operations using WATCH/MULTI or
   the smallest equivalent atomic primitive already used in this backend.
   Implement the two explicit CLI subcommands; add no service endpoint or
   worker.
6. Make one private `PushService` gateway the sole `ResolveRoute` caller. Move
   token injection and platform projection there; make all four current rich
   senders route-only. Remove production `LookupToken`. Remove the
   group-reaction builder's nonempty-token prerequisite so construction remains
   token-free until the gateway. Eliminate the two upstream
   `recipientSupportsCapability` lookups at `go-relay-server/inbox.go:1584` and
   `:1862`; capability/eligibility accounting moves to the adapter's one route
   snapshot, with no second happy-path or preflight backend lookup;
   `ErrPushRouteStale` is the sole bounded exception. Preserve group reaction's
   current
   synchronous pre-goroutine incapable/attempted accounting: take the immutable
   route snapshot there and pass it into the goroutine/gateway rather than
   moving the lookup behind asynchronous scheduling.
7. Change permanent provider failure to `RevokeIfCurrent(target.Route)` on both
   initial and strict-fallback sends. Change explicit unregister to return and
   propagate errors before the stream ACK.
8. Extend the tagged Redis helper/process fixture and run the one named
   process-handoff test only by its exact command in this plan. Add that same
   list/run/PASS/no-skip command as one synthetic non-Dart path in
   `scripts/run_host_test_gates.sh` for later wave `host-all`; use the incumbent
   host script's print/run dispatch and add no wrapper or curated-gate entry.
9. Run six serial semantic mutation families: marker revision removed;
   plaintext/AAD authority omitted or prior refresh vault retained; legacy
   fallback enabled after encrypted marker; peer-wide
   revoke restored; unregister ACK moved before delete; cleanup admitted early.
   Require the owning test to red, then revert each mutation and restore GREEN.
10. Run focused, race, preservation, curated, full-relay, hygiene, and one
    incremental Graphify refresh in the cadence below. Perform a current-source
    audit before recording the completion marker.

## Risks And Counterexamples

- **Migration lost update:** marker state without a shared revision lets a
  register/unregister race disappear. TC-367-01/03 own it.
- **ABA token deletion:** delayed provider error removes a refreshed token.
  Route generation plus exact source digest and TC-367-05 own it.
- **Cutover rollback trap:** an old binary after encrypted CAS cannot read the
  new namespace. The state/rollback contract forbids that deployment.
- **Ciphertext without context:** encryption alone does not prevent row swaps or
  environment confusion. Complete AAD and TC-367-02 own it.
- **Dead abstraction:** a vault with no production adopter gives false comfort.
  All four rich senders and a single resolver source guard make it live.
- **Unbounded repair machinery:** no scanner, scheduler, dual-write epoch, or
  reverse index is permitted. Revision-fenced explicit CLI convergence is the
  complete mechanism.
- **Metrics exposure:** existing `TokenCount`/`PlatformCounts` stay aggregate;
  new vault/config/migration telemetry admits no peer, handle, token, or
  environment value. Plan 368 owns incumbent provider-send log sanitation.
- **Historical compatibility:** exact legacy bytes remain authoritative until
  encrypted CAS; unknown or unmatched rows fail loudly and are never silently
  re-imported after cutover.

## Gate Cadence

### Focused discovery and GREEN

Exactly seven closure tests must be discoverable, with no skip:

```bash
(
  set -euo pipefail
  cd go-relay-server
  plan367_focused_log="$(mktemp /tmp/plan367-focused.XXXXXX)"
  trap 'rm -f "$plan367_focused_log"' EXIT
  plan367_tests="$(
    GOTOOLCHAIN=go1.25.0 go test . -list \
      '^TestRelayNotificationClosure_PushRoute(LegacyCoexistenceAndMigrationAdmission|DirectoryCiphertextAndGenerationContract|MigrationRevisionFenceConvergesWithoutWriteDowntime|EncryptedResolutionFeedsEveryRichSender|PermanentErrorCompareRevokesExactLease|ExplicitUnregisterAcknowledgesOnlyAtomicDelete|ExplicitLegacyCleanupIsIdempotent)$'
  )"
  test "$(printf '%s\n' "$plan367_tests" | rg -c '^TestRelayNotificationClosure_')" -eq 7
  GOTOOLCHAIN=go1.25.0 go test . \
    -run '^TestRelayNotificationClosure_PushRoute(LegacyCoexistenceAndMigrationAdmission|DirectoryCiphertextAndGenerationContract|MigrationRevisionFenceConvergesWithoutWriteDowntime|EncryptedResolutionFeedsEveryRichSender|PermanentErrorCompareRevokesExactLease|ExplicitUnregisterAcknowledgesOnlyAtomicDelete|ExplicitLegacyCleanupIsIdempotent)$' \
    -count=1 -v | tee "$plan367_focused_log"
  test "$(rg -c '^--- PASS: TestRelayNotificationClosure_PushRoute' "$plan367_focused_log")" -eq 7
  ! rg -q '^[[:space:]]*--- SKIP: TestRelayNotificationClosure_PushRoute' "$plan367_focused_log"
)
```

Run the concurrency owner with the race detector:

```bash
(
  cd go-relay-server
  GOTOOLCHAIN=go1.25.0 go test -race . \
    -run '^TestRelayNotificationClosure_PushRouteMigrationRevisionFenceConvergesWithoutWriteDowntime$' \
    -count=1
)
```

Run and register the exact process proof:

```bash
(
  set -euo pipefail
  cd go-relay-server
  plan367_process_log="$(mktemp /tmp/plan367-process.XXXXXX)"
  trap 'rm -f "$plan367_process_log"' EXIT
  GOTOOLCHAIN=go1.25.0 go test -tags integration . \
    -list '^TestRedisPushRouteVaultEncryptedStateSurvivesProcessHandoff$' |
    rg -x 'TestRedisPushRouteVaultEncryptedStateSurvivesProcessHandoff'
  GOTOOLCHAIN=go1.25.0 go test -tags integration . \
    -run '^TestRedisPushRouteVaultEncryptedStateSurvivesProcessHandoff$' \
    -count=1 -v | tee "$plan367_process_log"
  test "$(rg -c '^--- PASS: TestRedisPushRouteVaultEncryptedStateSurvivesProcessHandoff ' "$plan367_process_log")" -eq 1
  ! rg -q '^[[:space:]]*--- SKIP: TestRedisPushRouteVaultEncryptedStateSurvivesProcessHandoff' "$plan367_process_log"
)
```

The same non-vacuous command remains registered as one synthetic non-Dart
`host-all` tail. It is not executed by Plan 367's per-plan `host-all` because no
such gate runs here; Plan 368's final N02 wave consumes the registration.

### Exact preservation sentinels

```bash
(
  set -euo pipefail
  cd go-relay-server
  plan367_preservation_re='^(TestInboxStore_RegisterTokenVisibleAcrossInstances|TestInboxStore_PushTokenSurvivesServerRestart|TestRedisPushTokenBackend_SurvivesAcrossClients|TestRedisPushTokenBackend_PreservesReactionCapabilityAcrossClients|TestPushServiceRegisterTokenPropagatesBackendPersistenceFailure|TestHandleInboxStreamRegisterTokenAcknowledgesOnlyPersistedWrite|TestRelayNotificationClosure_DirectStoreTriggersPushAfterPersistence|TestRelayNotificationClosure_DirectDuplicateDoesNotRefanoutPush|TestRelayNotificationClosure_DirectReactionDuplicateDoesNotRefanoutPush|TestRelayNotificationClosure_OrdinaryPushAndroidProjectionStripsApns|TestRelayNotificationClosure_OrdinaryPushIosProjectionDropsDuplicateData|TestRelayNotificationClosure_PermanentTokenErrorEvictsWithoutRetry|TestRelayNotificationClosure_TransientErrorKeepsRetryLadderAndToken)$'
  plan367_preservation_log="$(mktemp /tmp/plan367-preservation.XXXXXX)"
  trap 'rm -f "$plan367_preservation_log"' EXIT
  test "$(GOTOOLCHAIN=go1.25.0 go test . -list "$plan367_preservation_re" | rg -c '^Test')" -eq 13
  GOTOOLCHAIN=go1.25.0 go test . -run "$plan367_preservation_re" \
    -count=1 -v | tee "$plan367_preservation_log"
  test "$(rg -c '^--- PASS: Test' "$plan367_preservation_log")" -eq 13
  ! rg -q '^[[:space:]]*--- SKIP: Test' "$plan367_preservation_log"
)
```

Adapt assertions to the route/resolve test helper where the old tests directly
read `LookupToken`; do not weaken their registration, capability, persistence,
provider-request, retry, or deletion outcomes.

### Affected gates and hygiene

```bash
(
  set -euo pipefail
  bash scripts/run_test_gates.sh 1to1
  (cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -count=1)
  (cd go-relay-server && GOTOOLCHAIN=go1.25.0 go vet ./...)
  test -z "$(rg --files go-relay-server -g '*.go' -0 | xargs -0 gofmt -l)"
  git diff --check
  ./graphify-arch/refresh_arch_graph.sh --incremental
)
```

The curated `groups` gate is omitted here because it would rerun the same relay
closure family without a changed group client surface. Full `host-all` is also
omitted per repository cadence. Plan 368 owns the one N02-wave `host-all` after
both relay slices and their combined current-source audit.

No phone is justified: this plan changes only Go relay storage/gateway code and
uses a tagged multi-process Redis proof. If later scope crosses a mobile OS
boundary, the available USB Android plus Android emulator policy applies.

## Acceptance

- [x] Plan-366 receipt checksum and frozen-tree dependency are verified.
- [x] All eight test-contract rows have causal or preservation evidence; seven
  focused tests and one tagged process test are non-vacuously discoverable.
- [x] Redis never stores a plaintext provider token in encrypted state, and
  directory/vault rows are context-bound and integrity-checked.
- [x] Absent, migrating, and encrypted are the only states; migration is
  revision-fenced, crash-resumable, write-available, and explicitly admitted.
- [x] Handle/generation, exact legacy digest, rotation, stale resolve, and
  compare-revoke rules pass under race/cutover counterexamples.
- [x] Exactly one private production gateway resolves provider token/platform;
  all four rich senders are route-only before that seam.
- [x] Explicit unregister returns a durable result and stream ACK ordering is
  correct.
- [x] The two CLI subcommands exist, but no live migration/cleanup/deployment is
  claimed or performed.
- [x] Focused, race, tagged process, preservation, curated `1to1`, full relay,
  vet/format/diff, and graph refresh pass on one final source tree.
- [x] No new service, package, queue, scheduler, daemon, admin endpoint, reverse
  index, device code, or payload privacy claim is introduced.

## Done

After the acceptance list and post-execution current-source audit pass, record:

```text
N02_OPAQUE_HANDLE_FOUNDATION_CODE_COMPLETE
```

This marker means the encrypted opaque-route foundation is host code-complete
and default-off. It does **not** mean GAP-N02, AC-11, live migration, activation,
release eligibility, or universal provider privacy is complete.

The marker is dependency-bearing only with
`Test-Flight-Improv/evidence/367/README.md` and its external sibling
`README.md.sha256`. That receipt records the exact final frozen tree/dirty
snapshot, Graphify fingerprint, seven focused no-skip results, race result,
tagged process PASS, preservation count, curated `1to1`, full relay, hygiene,
current-source audit, and the marker above. Create the checksum only after the
README is final; no source commit or tag is inferred.

## Handoff

Plan 368 may begin only after validating that receipt checksum and copying its
exact frozen-tree and Graphify identities into Plan 368's execution record. It
must preserve the exact route API, retained-key/cutover semantics, and
compare-revoke tests. Its fixed gateway entry accepts the immutable
generation-bearing `pushRouteLease`, not a bare handle, because provider failure
must still revoke only that exact registration.

Actual migration requires WP-07 to supply all-frontends provenance, trusted
keys/environment, compatible binaries, observation, rollback, and explicit
legacy cleanup authority. None is inferred from this plan.

## Reviewer Findings

`READY` after correction.

- **L1 behavior:** the route lease prevents event code from receiving provider
  tokens and compare-revoke prevents delayed provider errors from deleting a
  newer registration. Legacy coexistence is restricted to marker-absent state.
- **L2 implementation:** the three-state protocol, complete AAD, trusted
  environment, retained-key rotation, atomic directory/vault lifecycle and
  exact migrated-source digest close the reviewed tamper, refresh, crash and
  orphan counterexamples. One helper and the incumbent backends/gateway are
  sufficient; no worker, reverse index or migration framework is needed.
- **L3 proof:** seven causal tests, one exact tagged process proof, race owner,
  13 preservation sentinels and six semantic mutations are count-checked and
  reject parent or child skips. The process proof is registered once for the
  later wave rather than duplicated in a curated gate.
- **L4 integration:** all four production adapters use one happy-path route
  snapshot; group reaction keeps capability accounting synchronously before
  its goroutine. Plan 368 must consume a checksum-valid Plan-367 receipt, not a
  prose marker alone.
- **L5 operation:** migration and cleanup remain explicit/default-off CLI
  actions. The fleet receipt is an operator-supplied identifier, not locally
  manufactured authorization. Live keys, deployment, cutover, rollback and
  cleanup remain WP-07 work.

Evergreen blind spots are bounded rather than hidden: old binaries are allowed
only before migration admission; unknown keys/environments fail closed; no
phone can prove this relay-storage boundary; and live fleet provenance is not
claimed by host tests.

## Arbiter Decision

`ready`. Accept every verified review correction. Reject the proposal to make
all explicit-stale results immediately terminal: one exactly-once re-selection
inside a shared outer helper is the smaller reliable contract because a normal
registration refresh can race the lookup-to-resolve interval. The helper
already has the authenticated recipient used for the first lookup, never sends
that value to a provider, rechecks capabilities, forbids opaque-to-rich
downgrade, and terminates after a second stale result. This adds neither a
service nor four adapter-specific retry owners.

## Execution Progress

- **2026-08-15 10:33-11:34 +02:00 — RED/GREEN and audit:** TC-367-01 first
  exposed the incumbent plaintext-row boundary. Its draft absent-state
  assertion was rejected because absent state must preserve exact legacy bytes;
  the counted contract enters migration/encrypted state before asserting no
  plaintext. All eight contract rows were then implemented. An independent
  counterexample audit drove strict-codec, migration-snapshot, resolver-race,
  startup-under-traffic, exact-digest, environment-rotation, compare-revoke and
  atomic-unregister fixes and closed with no remaining semantic blocker.
- **2026-08-15 11:37-11:43 +02:00 — mutation proof:** all six serial semantic
  mutations produced the owning RED (revision increment, complete AAD,
  post-cutover legacy fallback, exact compare-revoke, delete-before-ACK and
  cleanup admission), and each owning test returned GREEN after its mutation
  was reverted. Exact log hashes and failure assertions are in the receipt.
- **2026-08-15 11:43-11:47 +02:00 — final gates:** exact focused discovery/run
  was 7/7 with zero skips; the migration owner passed under `-race`; the tagged
  process proof was 1/1 with zero skips; preservation was 13/13 with zero
  skips. Curated `1to1`, full relay, vet, Go formatting, diff hygiene, the shared
  host-gate contract and the exact synthetic host dispatch all passed. Per
  repository cadence, full `host-all` remains Plan 368's N02-wave gate.
- **2026-08-15 11:47 +02:00 — source/graph/freeze:** the source audit found zero
  production `LookupToken` references, one `LookupRoute` call, one
  `ResolveRoute` call, four gateway adapters and one provider-token/platform
  injection site. One incremental architecture-graph refresh produced
  fingerprint `76c930dc8afc22a2`. The dirty shared worktree was captured without
  touching its index as frozen tested tree
  `9ec76e3f99e222ba446801f2e5e1281725bdc05b` with porcelain-v2 SHA-256
  `3473c3919085622bc9b9dabc9780a682789a3371858e641e2aa1648157075ff8`.
- **Completion marker:** `N02_OPAQUE_HANDLE_FOUNDATION_CODE_COMPLETE`.
  Dependency-bearing evidence is `Test-Flight-Improv/evidence/367/README.md`
  plus `README.md.sha256`; final README SHA-256 is
  `b0253505ed8bdb2ca3cb352e6179edf85e6290d16503667c5d3949c2e5f61a89`.
