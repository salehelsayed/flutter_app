# 373 - GAP-N07 iOS NSE Opaque Mailbox-Wake Adoption

Status: **PREREQUISITE_BLOCKED / CONTRACT_READY / INDEPENDENTLY REVIEWED / ONE N07-OWNED ADAPTER SLICE / DEFAULT-OFF / IOS EVIDENCE DEFERRED / NOT LIVE-ACCEPTED / NOT RELEASE-ELIGIBLE**
Type: Modification
Spec inputs: `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2.md` §§6, 8 and 9; GAP-N07 and WP-04 in `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md`
Classification: prerequisite-blocked iOS native-consumer vertical slice
Closure tier: host Go/Swift/Dart plus available iPhone-simulator XCTest; physical APNs and Apple lifecycle evidence remain N12/WP-07

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-15 | Planner using `$tdd-plan` | N07 PRD/coverage; Plan 368 fixed provider request; Go inbox/bridge; `NotificationService`, preview resolver and iOS recovery; Plan-371 visibility work; Plan-372 contract | N07 has one real rollback boundary: an admitted fixed Apple wake is either enriched by one bounded authenticated native attempt or delivered as the untouched generic alert. Split foundation/adoption or modality plans would leave an unusable primitive. | Keep one Plan 373; do not create Plan 374. |
| 2026-08-15 | Protocol/identity verifier | `/mknoon/inbox/1.0.0`, ACK-custody retrieval, primary/linked transport authority, Keychain projections | The current bridge retrieval requires the Runner singleton and cannot work in an NSE. Mailbox access also requires the exact physical transport private key, which is not currently shared. | Add one narrow stateless Go retrieval export and one versioned read-only-to-NSE credential projection; no new relay protocol or store. |
| 2026-08-15 | Native boundary verifier | fixed APNs grammar, completion gate, resolver, App-Group ledger/visibility, privacy manifests and Xcode membership | Operational failure currently sanitizes unresolved content to blank/passive. A fixed wake must instead preserve Apple's localized generic content exactly. | Separate fixed-wake orchestration from the incumbent rich path and freeze exactly-once completion/fallback behavior. |
| 2026-08-15 | Gate verifier | Go/Swift/Dart tests, gomobile build, host runner, device policy | Plan 372 owns the one N03-N06 wave `host-all`. N07 needs focused Go/native/Dart proof and one registered synthetic host item only. | Pin non-vacuous exact tests, dynamic simulator availability, no phone campaign or full-host rerun. |
| 2026-08-16 | Independent reviewers using `$tdd-review` | Full Plan-373 draft; direct-device trust and group authority mutations; iOS recovery and paged inbox drain; fixed/rich/NSE/Go boundaries; literal gates | Review found real stale-sender, relay-to-SQL ambiguity, identity-less generic replay and false-green/duplicate-gate counterexamples. Each was repaired in place using incumbent authorities and one standard native runner. | PASS after bounded corrections; do not add Plan 374, another protocol/store/service, or a broad gate. |
| 2026-08-16 | Planner/arbiter | Latest plan bytes and five review lenses | Physical/logical sender binding, retire-before-mutation projections, page-wise silent lease continuation, no-ACK custody, default-off linked readiness and exact non-vacuous gates now agree. Plan 372's future receipt remains the only execution blocker. | Mark contract-ready/prerequisite-blocked and preserve the one-plan N07 boundary. |

## Problem And Evidence

- Behavior to improve: an iOS Notification Service Extension receiving the
  fixed mailbox-dirty APNs request must perform one bounded headless inbox read,
  authenticate/decrypt one eligible event and enrich the notification through
  the shared visibility/final-effect/ledger authority. Every incomplete or
  operational failure must still deliver the original localized generic alert.
- Current fixed provider contract is already exact in
  `go-relay-server/opaque_wake.go`: APNs alert, priority 10, five-minute expiry,
  collapse ID `mailbox`, localized title/body, `mutable-content=1`, default
  sound, category `MESSAGE_WAKE`, and the sole app-owned custom field
  `"v":"1"`. Android's `"w":"1"` is not part of the iOS grammar.
- Current NSE coverage is real but rich-payload-only:
  `ios/NotificationService/NotificationService.swift` stages provider-carried
  envelope fields and `NotificationPreviewResolver.swift` uses stateless
  GoMknoon decrypt exports. It has no inbox client or Runner Flutter engine.
- Current operational fallback is unsafe for the fixed request:
  `sanitizeNotificationContentForUnresolvedExpiry` clears visible metadata.
  That behavior may remain for authenticated terminal/private-rich decisions,
  but a fixed mailbox wake whose fetch/key/network/ledger work fails must keep
  the provider's generic title, body, category and sound unchanged.
- `BridgeInboxRetrievePendingWithParams` requires an initialized, started
  process-global Node. Starting the full Node inside the extension would add
  listeners, NAT/AutoRelay, GossipSub and lifecycle state far beyond a bounded
  fetch and would create teardown/concurrency hazards.
- Relay inbox access is authenticated by the libp2p stream's remote peer, not a
  request `to`, bearer token or logical account ID. Primary and active linked
  installations may have different physical transport identities. The NSE
  currently has no shared-Keychain projection of the selected transport key.
- The existing strict retrieval already negotiates protected
  `retrieve_custody_pending_v1` with `ack_or_expiry_v1`, falls back to legacy
  `retrieve_pending` on the same old relay, exact-coalesces rows, FIFO sorts and
  reports `hasMore`. Reuse it; do not add another action or protocol.
- Honest source limitation: legacy group inboxes are keyed by group ID, while
  the fixed wake intentionally carries no group ID. N07 cannot enumerate them.
  A protected `group_content_v1` row that is already in the per-device inbox is
  eligible; a legacy group-only wake with no direct inbox row remains generic.
- Unresolved dependency: Plan 372 has not executed and its Swift ledger/store/
  final-effect APIs do not yet exist. Plan 373 cannot claim execution readiness
  from Plan-372 planning prose.

## Dependency Contract

Plan 373 executes only after Plan 372 has produced a checksum-bound, committed
receipt for the combined N05+N06 contract. Plan 372 transitively binds Plan 371
and the N03/N02/N01 mechanism chain; do not replay every earlier receipt.

Required future artifacts and invariants:

- `Test-Flight-Improv/evidence/372/README.md` and sibling
  `README.md.sha256` are tracked and their committed bytes equal the workspace;
- exact marker `N05_N06_FINAL_EFFECT_LEDGER_MECHANISM_CODE_COMPLETE`;
- valid base/frozen-tree/dirty-snapshot/Graphify identities and a frozen tree
  object;
- DB version remains 116;
- exact `local_notification_ledger_v1.json` fixture/store and one
  `NotificationConversationIds/.coordination.lock` effect boundary exist;
- exact phase-preserving `RELAY_VERIFIED_UNACKED -> SQL_READY` transition
  exists: matching SQL materialization changes only custody/revisions; a
  `PUBLISHING` row remains ambiguous, and only `EFFECT_TERMINAL` may replay
  SQL/v116 and settle;
- `IOS_NSE` is a reserved owner in the shared state machine, but no NSE effect
  adopter is falsely claimed by Plan 372;
- the paired `opaque_wake_v1`/`wake_outcome_v1` admission remains default false;
- Plan-372's receipt records its one N03-N06 aggregate `host-all`; Plan 373 does
  not repeat that sweep.

Run before authoring any TC-373 RED. Today the missing Plan-372 receipt is the
expected blocker:

```bash
(
  set -euo pipefail
  receipt='Test-Flight-Improv/evidence/372/README.md'
  checksum='Test-Flight-Improv/evidence/372/README.md.sha256'
  test -f "$receipt"
  test -f "$checksum"
  (cd Test-Flight-Improv/evidence/372 && shasum -a 256 -c README.md.sha256)
  rg -Fqx 'N05_N06_FINAL_EFFECT_LEDGER_MECHANISM_CODE_COMPLETE' "$receipt"

  base="$(awk -F'`' '/\| (Base( and unchanged)? HEAD|Base HEAD) \|/ {print $2; exit}' "$receipt")"
  frozen="$(awk -F'`' '/\| Frozen tested tree \|/ {print $2; exit}' "$receipt")"
  dirty="$(awk -F'`' '/\| (Porcelain-v2 workspace snapshot|Dirty snapshot) SHA-256 \|/ {print $2; exit}' "$receipt")"
  graph="$(awk -F'`' '/\| (Graphify )?[Ff]ingerprint \|/ {print $2; exit}' "$receipt")"
  [[ "$base" =~ ^[0-9a-f]{40}$ ]]
  [[ "$frozen" =~ ^[0-9a-f]{40}$ ]]
  [[ "$dirty" =~ ^[0-9a-f]{64}$ ]]
  [[ "$graph" =~ ^[0-9a-f]{16}$ ]]
  git cat-file -e "${base}^{commit}"
  git cat-file -e "${frozen}^{tree}"

  receipt_commit="$(git log -n 1 --format=%H -- "$receipt")"
  test -n "$receipt_commit"
  git merge-base --is-ancestor "$base" "$receipt_commit"
  cmp -s <(git show "${receipt_commit}:${receipt}") "$receipt"
  cmp -s <(git show "${receipt_commit}:${checksum}") "$checksum"

  rg -Fq 'local_notification_ledger_v1.json' "$receipt"
  rg -Fq 'NotificationConversationIds/.coordination.lock' "$receipt"
  rg -Fq 'IOS_NSE' "$receipt"
  rg -Fq 'RELAY_VERIFIED_UNACKED' "$receipt"
  rg -Fq 'phase-preserving' "$receipt"
  rg -Fq 'DB v116' "$receipt"
  rg -Fq 'default-off' "$receipt"

  # Closure after the tested tree may contain only durable evidence/planning
  # documents. Re-pin this allowlist to the accepted receipt layout.
  while IFS= read -r changed; do
    test -z "$changed" && continue
    case "$changed" in
      STATUS.md|\
      Test-Flight-Improv/00-INDEX.md|\
      Test-Flight-Improv/372-gap-n05-n06-*|\
      Test-Flight-Improv/373-gap-n07-*|\
      Test-Flight-Improv/evidence/372/*|\
      UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md) ;;
      *) printf 'Unexpected post-372 drift: %s\n' "$changed" >&2; exit 1 ;;
    esac
  done < <(git diff --name-only "$frozen" "$receipt_commit")

  # Exact provider grammar and incumbent bridge limitation remain true.
  (cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . \
    -run '^(TestRelayNotificationClosure_OpaqueWakeIOSProviderRequest|TestRelayNotificationClosure_AckCustodyRolloutContract|TestRelayNotificationClosure_DirectMediaBlobCustodyAdmissionOffDrains)$' \
    -count=1)
  (cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge \
    -run '^TestInboxRetrievePending_NodeNotInitialized$' -count=1)
)
```

If the accepted receipt headings differ while binding the same identities,
align the parser mechanically and record the exact format. Do not weaken a
missing identity. If Plan 372 changes the ledger lock, owner or fixture
semantics, stop and re-review Plan 373 rather than adapting silently.

## Graph Grounding Snapshot

- Graph fingerprint/freshness: `e9251661e571efe3`; anchored but stale while
  Plan 371 is actively being implemented. Re-run after Plan 372 closes.
- Query/profile:
  `python3 graphify-arch/tdd_context.py query "Plan 373 GAP-N07 iOS NotificationServiceExtension fixed mailbox dirty APNs bounded authenticated inbox retrieval decrypt generic fallback LocalNotificationRecord AppVisibilitySnapshot final effect contentHandler NotificationService NotificationPreviewResolver IosNotificationRecovery" --profile tdd --budget 700`.
- Independent review also used the review profile at fingerprint
  `3c1aa59babe873f4`. It was broad/stale while Plan 371 was moving, so every
  promoted counterexample was verified against current source; execution must
  still re-run one focused query against Plan 372's accepted tree.
- Anchors: `NotificationService.swift`, `NotificationPreviewResolver.swift`,
  `IosNotificationRecovery.swift`, `go-mknoon/node/inbox.go`,
  `go-mknoon/bridge/bridge.go`, and Plan-370 capability composition.
- Graph gap: active Plan-371 files and future Plan-372 ledger APIs are not a
  stable accepted baseline. The dependency preflight plus a refreshed TDD
  query is mandatory before implementation.

## Delivery Structure Decision

This is exactly one N07 implementation plan:

1. The main app projects one already-qualified physical transport credential
   and exact installation binding for extension use.
2. One narrow stateless Go export performs the authenticated non-destructive
   inbox read under an absolute deadline.
3. One Swift coordinator classifies the fixed wake, validates/decrypts a
   candidate, consumes the Plan-371/372 authorities and completes once.

These parts have no independent rollout value. A credential/fetch foundation
without the NSE adopter is dead sensitive state; a Swift-only plan cannot
authenticate the mailbox. Splitting direct/group, message/reaction, Go/Swift,
or capability/wiring would reproduce partial authorities. Do not create Plan
374 for audit, migration or platform evidence.

## Protocol, Identity And Effect Contract

### Exact fixed-wake discriminator and fallback

- Recognize only the exact iOS app-owned grammar: `v` is the String `"1"`;
  `aps.category == MESSAGE_WAKE`; the localized generic alert,
  `mutable-content=1` and default sound are present; and no rich app-owned
  routing/event/cipher fields occur.
- Reject numeric `v`, Android `w`, unknown app-owned keys and mixed fixed/rich
  shapes. Provider/OS-reserved metadata may coexist but is never event
  authority.
- Rich payloads remain on the incumbent resolver/staging/recovery path. An old
  rich payload must not enter the new inbox coordinator.
- Before asynchronous work, retain one immutable mutable-copy of the incoming
  generic content as the completion candidate. Missing/locked credentials,
  binding mismatch, relay/timeout/proof/decrypt/policy/ledger/visibility error,
  no candidate, `hasMore`, cancellation or extension expiry finishes with that
  content field-equivalent and exactly once.
- Only a positively authenticated terminal read/deleted/expired/policy/current-
  visible/duplicate decision may choose Plan-372's no-effect/passive result.
  N04 unknown/stale visibility fails toward the generic notification.

### One physical-transport projection

Add one versioned shared-Keychain document, for example
`nse_inbox_transport_v1`, containing only:

```text
schemaVersion: 1
opaqueBinding: exact Plan-372 `v1:<64-lowercase-hex>`
logicalAccountPeerId: exact current account binding
transportPeerId: exact current physical libp2p peer
transportPrivateKeyBase64: canonical base64 of the exact private-key bytes for that physical peer
relayMultiaddrs: bounded order-preserving canonical/deduped exact current runtime relay addresses
projectionRevision: positive signed Int64
```

- Primary selects the already-qualified `IdentityModel.privateKey/peerId`.
  In today's identity model that one Ed25519 key is intentionally dual-use as
  the primary account-signing and physical transport key; admitting N07 on a
  primary therefore consciously expands that exact key to the same-team NSE.
  Do not disguise this as a separate transport credential. If product/security
  policy rejects the expansion, stop for an upstream scoped-primary-transport
  design rather than minting one inside N07.
  Active linked secondary selects
  `LinkedInstallationAuthoritySnapshot.credential.transportPrivateKey` and
  `.transportPeerId`. Awaiting/preparing/fail-closed/partial/cross-account
  linked states project nothing; never fall back to the logical account key.
- A dedicated main-app owner writes, rereads and byte/authority-verifies the
  document only after the incumbent node-start selector has returned and
  qualified the exact physical peer and identity, binding and effective runtime
  relay configuration are current. Preserve the byte-equivalent configured
  relay failover order that `node:start` received while removing only exact
  duplicates; the one total deadline makes that order semantically relevant.
  Environment relay overrides must not be sorted or replaced with compiled
  defaults. It publishes only while the one incumbent
  admission is enabled on iOS; default-off/non-iOS retires the exact item, so a
  stale fixed wake cannot fetch. It also retires/suspends before logout/account
  switch/migration and refreshes on primary identity save/load, linked-role
  transition and relay change; never use `deleteAll`.
- The NSE is read-only. It compares the separately current projected binding;
  Go derives the peer from the private key and rejects any mismatch before a
  dial. Future/corrupt/locked/before-first-unlock bytes are immutable and cause
  generic fallback.
- Use the existing entitled shared Keychain and
  `first_unlock_this_device` protection. Never project mnemonic, SQLCipher key,
  any additional account signing key, contacts, groups or tokens. The primary
  dual-use exception above and linked transport-only key are the entire private-
  key surface; never log the document, peer, relays, key or raw Go error.

### One stateless bounded Go retrieval export

Add one action-local Go export `NSEInboxRetrievePending(paramsJSON)` (exposed
by gomobile to Swift as `BridgeNSEInboxRetrievePending`) and a small node helper.
Freeze it to the existing protocol and policy:

- strict input contains only bounded base64 private-key/expected-peer/relay
  material and a clamped total timeout; custody action, fallback order,
  `limit=1` and frame caps are hard-coded, not caller-selectable;
- accept at most eight canonical relay multiaddrs, at most 512 UTF-8 bytes each
  and 8 KiB total; clamp the Go absolute budget to 250--3000 ms and keep the
  Swift completion deadline outside it with a fixed safety margin;
- derive and exact-match the expected transport peer before networking;
- construct an ephemeral no-listen libp2p host, reuse the incumbent per-relay
  protected-first/same-peer-legacy-fallback/proof/coalescing/FIFO logic,
  recomputing remaining time from one absolute deadline before every relay
  address and strict/fallback attempt, and close on every path;
- return at most one existing inbox row plus `hasMore` and the exact custody
  contract. `hasMore=true` is an incomplete view and therefore returns generic;
  Swift never fetches another page inside the NSE;
- never initialize or mutate the bridge singleton; never create listeners,
  GossipSub, rendezvous, AutoRelay, callbacks or persistent extension state;
- never ACK. The main app later re-retrieves, stages into durable SQL custody,
  ACKs and completes Plan-372's SQL/v116 handoff.

The exported API is not a new inbox protocol, service or queue. If a genuinely
no-listen, deadline-bounded authenticated host cannot be built by refactoring
the incumbent helper, stop for focused re-review. Do not substitute full
`BridgeInitialize`/`BridgeStartNode` inside the extension.

### Candidate authentication and honest group boundary

- Direct v2 candidates exact-parse the authenticated `from`, encrypted fields
  and event identity before using existing stateless decrypt primitives. The
  relay row/outer sender is a physical transport while decrypted direct sender
  identity is logical. Extend the incumbent `direct_reaction_contacts_v1`
  projection with one bounded canonical set of currently authorized transport
  peer IDs per logical contact; do not create another contact store. Require a
  unique physical-to-logical mapping, outer `from` equality and decrypted-inner
  logical equality. Explicit legacy physical-equals-logical remains valid;
  revoked, ambiguous or cross-contact transport mappings stay generic.
- Bind that direct authorization field to the real
  `DatabaseDirectContactDeviceTrust` commit boundary, not `ContactModel` display
  state. Retire the affected contact's projected authorization before verify,
  reject, device/legacy revoke or account-key mutation; after the DB commit,
  rebuild and atomically republish only from committed DB readback. Startup
  backfill also reads that trust authority. Retirement plus readback is a
  precondition to the authority mutation; failure returns retryable rather than
  committing while stale bytes remain eligible. A post-commit read/republish
  failure leaves the already-retired authorization absent and therefore generic.
- Node retrieval returns a raw encrypted `message`, not the rich provider route
  dictionary expected by `NotificationPreviewResolver`. Add one small strict
  raw-envelope-to-existing-route adapter for the supported direct-v2 and
  protected-group shapes; do not feed raw inbox JSON directly to the resolver
  or port the Dart inbox state machine.
- Protected group content must validate its strict signed outer replay shape,
  canonical signature/hash, recipient set, authenticated sender transport,
  custody kind and event-key parity before trusting group/sender/event fields.
  After decrypt, use the authenticated logical-delivery identity required by
  Plan 369/372 correlation; never guess it from the relay entry ID.
- Extend only the incumbent group notification projection with a bounded SET of
  paired current-authority sender tuples
  `(logicalSender, deviceId, transportPeerId, signingPublicKey)` under one exact
  `(authorityEventAt, authorityEventId, keyEpoch)` generation. Source it only
  from committed, currently verified group authority—not the ordinary
  `GroupModel` mirror. Retire the group authorization before membership/device/
  role/key/authority mutation, then atomically republish the whole set after
  committed-authority readback. Retirement/readback failure makes that mutation
  retryable; a post-commit republish failure leaves the retired projection
  generic. Startup does the same. The Swift adapter may
  enrich only when the signed envelope matches one tuple in that exact current
  generation. Removed/revoked/historical/stale/missing/ambiguous authority or a
  read/write failure remains generic; do not project authority history or port
  membership convergence into the NSE.
- Reject legacy plaintext, direct mutation/delete/history-repair,
  `group_bootstrap_v1`, `group_authority_v1`, malformed/future schemas and
  unsupported candidates. Only signed `group_content_v1` message/reaction may
  enrich. Group media/voice may use only an already authenticated text-safe
  descriptor; the NSE never downloads, decrypts or promotes a blob. Any
  unsupported row or `hasMore=true` remains generic and un-ACKed.
- Make the single Swift `NseInboxCandidateAdapter` the content-validation
  owner. Freeze its real canonical producer bytes and credential/relay vectors
  in exactly one repository fixture,
  `test/shared/fixtures/ios_nse_mailbox_v1.json`, generated from the incumbent
  Dart direct/group producers and byte-compared with the RunnerTests resource.
  Include sender-signing-public-key versus authenticated transport-peer
  mismatch, recipient removal/addition, signature/hash/event-key mutation,
  direct linked/legacy/revoked/ambiguous mappings, current-versus-historical
  group authority, relay-order override and future-schema attackers.
  CryptoKit plus the incumbent stateless Go decrypt primitives are allowed;
  no second Dart state machine or unnamed Go validator is implied.
- Do not call legacy `GroupInboxRetrieve`, scan known groups, add a group cursor
  or infer a group ID from APNs. A legacy group fixed wake whose per-device
  inbox is empty remains generic. Universal group source-to-wake enrichment is
  an activation/producer-pairing concern, not hidden N07 scope.

### Shared visibility/ledger effect and completion order

- Consume Plan 371's exact visibility reader and Plan 372's exact fixture,
  state machine, stable notification key/content generation and one
  `NotificationConversationIds/.coordination.lock`; do not add an NSE ledger,
  lock, queue, ID allocator or recovery store.
- Use owner `IOS_NSE`. Main/NSE racing the same correlation/revision yields one
  effect owner. The loser returns the generic or authenticated terminal result
  dictated by the winner/current state and cannot issue a second sound/effect.
- Lock order is the finalized Plan-372 ledger/effect boundary before the
  incumbent iOS request-recovery lock. No path may acquire recovery and then
  enter the ledger.
- The generic candidate is installed before work. At success, the verified
  still-relay-owned row is the NSE event-materialization authority. Perform the
  last current binding/visibility/ledger revision check at Plan-372's final
  effect boundary, then use the existing renderer and one completion-gate
  generation. Timeout/expiry winning first cancels/invalidates late work; a
  late result mutates no ledger/recovery/content.
- Keep `IosNotificationRecovery` as a compatibility projection: prepared before
  the handler and committed after its exact invocation. It is not the ledger.
- At exact fixed-branch entry, before fetch/decrypt work, extend the incumbent
  `IosNotificationRecovery` state with one optional, bounded mailbox-alert
  lease rather than inventing a ledger event. The lease
  carries only account/binding hashes, Apple request identifier, recovery
  generation/sequence and `PREPARED | PUBLISHING | AUDIBLE_AMBIGUOUS`; it is
  capped by the incumbent 512-row/request watermark and expires when superseded,
  account/binding mismatches, or its one complete reconciliation opportunity is
  consumed. Persist `PREPARED` before any asynchronous work, `PUBLISHING`
  immediately before invoking a generic handler and `AUDIBLE_AMBIGUOUS` after
  return. A crash at or after `PUBLISHING`, or an extension exit holding
  `PREPARED`, is conservatively audible-ambiguous because Apple may deliver the
  original. A positively authenticated correlated success transfers ownership
  to the exact Plan-372 record/recovery identity and retires the mailbox lease
  only after the handler invocation; it does not leave two recovery owners.
- Wire the existing Runner MethodChannel and Dart inbox coordinator to claim/
  read the lease at one incumbent drain-generation start, using its exact
  recovery generation/watermark. The current drain stages and replays each page
  before it can fetch/ACK the next, so pass a silent-effect context through that
  generation: every exact correlation durably materialized and replayed on each
  page enters the Plan-372 effect owner as a silent repair immediately. Consume/
  settle the lease only when that fixed-point drain succeeds with
  `hasMore == false`. On a partial page, transport failure or crash after a
  silent page but before consumption, keep the lease active/unconsumed; already
  replayed rows remain conservatively silent and continuation/retry under that
  lease silences the remaining pages. A mismatched, superseded or consumed
  lease authorizes nothing. This intentionally prefers bounded under-alerting
  to a duplicate audible alert for a collapsed mailbox wake and preserves the
  incumbent page/stage/ACK order. Do not mint a synthetic correlation, call
  `cancelAll`, add a store, or delay page ACK merely to collect a batch. The
  first authenticated event still creates its normal Plan-372 record and owns
  subsequent exact transitions.
- NSE success does not delete relay custody or mint SQL/v116 completion. A
  native effect ambiguity remains Plan-372 `PUBLISHING`; repair is silent and
  same-ID, never an audible retry.
- The extension lacks the filtering entitlement. Do not claim physical drop/
  suppression of a remote notification; an authenticated no-effect result may
  only use the existing privacy-clean passive handoff until N12 proves a
  platform mechanism.
- The NSE has no SQL canonical-row reader. Its exact authority is Plan 372's
  checksum-bound `RELAY_VERIFIED_UNACKED` state; it must not fake SQL facts or
  create a second native inbox journal.

### Capability and rollback

- Keep the one incumbent `MKNOON_ENABLE_WAKE_OUTCOME_COORDINATOR` seam default
  false and keep the wire pair `opaque_wake_v1` + `wake_outcome_v1`; add no new
  relay capability or caller-injected override.
- iOS advertises the pair only when that seam is enabled and the exact current
  credential/binding projection has passed read-back. Android remains
  consumer-unready until N08; production composition must pass effective false
  on Android even when a build test turns the shared seam on.
- Apply that platform/readiness predicate in production composition before the
  existing bridge registration call. Preserve TC-370's function-level injected
  seam test and its half-capability rejection; do not infer production readiness
  from `platform` alone or add a second capability input.
- Name that one production composition owner
  `OpaqueWakePlatformConsumerReadiness`: it resolves the current platform's
  independently supplied, binding-qualified read-back and returns false for a
  missing platform. Plan 373 supplies only the iOS reader and freezes Android
  false. Plan 375 adds the Android reader to this same owner; neither platform
  may create a sibling readiness predicate or persist an admission boolean.
- Default-off or stale fixed wakes do no fetch and deliver the generic content.
  Old clients omit capabilities and remain on rich delivery. Old relays ignore
  additive capability strings and remain rich. New admitted clients receiving
  old rich payloads retain the incumbent resolver.
- Behavioral rollback may disable/remove the projection writer and new fixed
  branch, but must retain the existing privacy manifests, rich resolver,
  recovery files and legacy projections while their APIs remain in use.
- The mailbox-alert lease is an optional `decodeIfPresent` member of the
  incumbent recovery document, not a schema/store fork. Old code may ignore or
  drop it only after the opaque-capable route has been replaced/revoked; new
  code treats missing bytes as no suppression authority.
- Future WP-07 rollback must first re-register or revoke the paired-capability
  token route and verify its replacement generation, then disable/remove the
  fixed branch/projection. Plan 373 performs none of that while default-off; an
  old binary must never be deployed behind a still-opaque route.
- A fresh active linked iOS secondary also needs a provider-token route under
  its physical transport. After node returned-peer qualification, reuse
  `ensureFirebaseReady` and exactly one incumbent
  `PushRegistrationCoordinator.ensureStarted` owner. In linked mode, explicitly
  role-gate Firebase's on-ready composition so it may arm only the incumbent
  push-listener seam needed by this route; it must not start the generic
  router/key/contact/pending-message live-service fleet. The coordinator's one
  long-lived token-refresh subscription and bounded registration retry are
  intentional; never invoke its raw register-token closure in parallel. Repeat
  startup is idempotent, partial/preparing/fail-closed authority calls neither
  owner, and Android linked startup remains unchanged for N08. Gate the entire
  new linked-iOS projection/registration hook on the incumbent default-false
  admission: while false it performs zero new registration or listener work.
  When true, iOS must first publish and reread the exact projection before the
  same coordinator registers the paired opaque/outcome capabilities.

## Scope Contract And Guard

In scope:

- exact fixed iOS wake classifier and immutable generic fallback;
- one versioned account/installation-bound physical transport projection;
- one stateless authenticated no-listen Go inbox retrieval export;
- strict direct/protected-group candidate validation/decrypt and deterministic
  one-candidate selection;
- bounded current direct-transport and group-sender-authority fields in the
  incumbent notification projections, with no authority history/new store;
- Plan-371 visibility and Plan-372 ledger/final-effect adoption by the NSE;
- one bounded mailbox-alert lease inside incumbent iOS recovery plus one silent
  context threaded through the existing paged Dart drain generation;
- default-off paired-capability readiness, rollback and narrow private-log
  hygiene on the touched path;
- the one iOS-only active-linked physical push-registration hook through the
  incumbent coordinator, with the unrelated live-service fleet role-gated;
- regenerated/verified iOS GoMknoon binding and focused host/native proof.

Must preserve:

- fixed provider bytes and rich compatibility behavior;
- relay custody until main-app durable persistence/ACK;
- shared ledger revision/content-generation semantics and legacy iOS recovery;
- exact primary versus linked physical transport ownership;
- generic content on every operational/incomplete path;
- privacy manifests and extension-safe build/link configuration.

Hard `Do not`:

- Do not add a relay action/protocol/backend, bearer token, group scan/cursor,
  App-Group inbox journal, SQL migration, queue, worker, scheduler, Flutter
  engine, second ledger/lock/recovery store or stable-ID allocator.
- Do not ACK from the NSE or claim inbox durability from a preview.
- Do not buffer/reorder the incumbent main-app paged stage/replay/ACK drain to
  wait for a complete batch; the lease context follows the existing generation.
- Do not split by modality/platform, run full Node services in the NSE, or add
  Plan 374 for audit/evidence.
- Do not implement Android N08, global N10 logging, N11 read/mute/activation,
  capability deployment, rich retirement or N12/WP-07 live acceptance.
- Do not require a physical iPhone, real APNs, lock/force-quit campaign, Android
  target, two-peer topology, per-plan full `host-all`, `core-host-all` or
  `feature-host-all`.

Deferred/accepted difference:

- legacy group-only inbox with no direct row -> exact generic fallback;
- mailbox page reports `hasMore` or otherwise exceeds the one-row complete view
  -> exact generic fallback; Plan 373 claims enrichment only for a complete
  singleton mailbox view and adds no pagination;
- Android FCM/WorkManager consumer -> N08;
- activation, mixed-version cohort, provider/relay deployment and universal
  source pairing -> WP-07;
- physical Apple lifecycle/lock/before-first-unlock/force-quit evidence and
  actual OS suppression behavior -> N12;
- full notification read/mute/activation cleanup -> N11.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-373-00 | Plan 372 is receipt-bound and default-off; fixed provider bytes and prior admissions remain exact | dependency preflight; `TestRelayNotificationClosure_OpaqueWakeIOSProviderRequest`; `TC-370-05 opaque outcome uses strict all-relay completion`; `TestRelayNotificationClosure_AckCustodyRolloutContract`; `TestRelayNotificationClosure_DirectMediaBlobCustodyAdmissionOffDrains` | Host Git/Go/Dart | BLOCKED today -> committed receipt/marker/tree plus default-false composition pass; Plan 373 changes no N01 server admission | Remove marker, alter fixed APNs custom keys, advertise without exact iOS readiness/on Android, or enable an ACK/media admission -> red | Literal preflight and exact tests; no live relay-state probe |
| TC-373-01 | Stateless retrieval authenticates the physical peer, negotiates strict/fallback per relay, obeys one total deadline and never ACKs/starts singleton services | `go-mknoon/node/nse_inbox_test.go::{TestNSEInboxOneShotAuthenticatesPeerAndRetrievesProtectedPage,TestNSEInboxOneShotBoundsDeadlineClosesHostAndNeverAcknowledges}`; `go-mknoon/bridge/nse_inbox_test.go::{TestNSEInboxBridgeRejectsIdentityMismatchAndDoesNotUseSingleton,TestNSEInboxBridgeReturnsStrictBoundedPage}` | Host Go / real local libp2p relays, primary+linked keys, fake clock/close hooks | Current singleton API is unusable -> exact peer A reads A only; protected and old-relay legs coalesce; hard-coded one-row result/hasMore; conflict/partial/timeout fail generic; host closes; a second one-shot reads the same stable row/backend count | Skip peer derivation, reset deadline per address, accept partial empty, ACK, create listener/pubsub or touch singleton -> red | Focused node/bridge, exact discovery/PASS/no-skip and `-race`; later synthetic host row |
| TC-373-02 | One shared-Keychain projection and incumbent registration owner follow exact primary/active-linked authority and binding lifecycle | `test/core/notifications/ios_nse_inbox_projection_test.dart::TC-373-02 exact physical transport projection gates paired iOS capability`; same file `::TC-373-02c committed direct and group authority mutations retire before exact republish`; `production_application_bootstrap_phase_contract_test.dart::TC-373-02b active linked iOS registers its exact physical paired route without starting unrelated live services`; Swift credential rows in TC-373-04 | Host Dart + Swift fakes / real direct-device-trust and current-group-authority repositories plus `test/shared/fixtures/ios_nse_mailbox_v1.json` | No transport-key projection and linked foundation has no fresh token owner -> admission-on iOS exact post-start write/readback; default-off/non-iOS zero new projection/registration/listener work; linked key not logical key; relay override order is preserved; direct verify/reject/revoke/account-key and group member/device/role/key/authority mutations require retirement readback before commit, then republish only committed authority; pre-retire failure aborts/retries and post-commit write failure stays absent; logout/switch/migration/rotation retire first; one idempotent coordinator owns initial registration plus refresh/retry; unrelated linked live services stay off; Android/unready omit caps | Use account key for linked, sort/replace runtime relays, project ContactModel/GroupModel alone, keep revoked/crossed/stale tuples, publish before commit, commit after failed retirement, retain stale bytes on republish failure, publish/register before returned-peer qualification/readback or while off, start a second registration owner, or advertise paired caps -> red | Exact Dart focused tests plus affected curated `1to1` lane |
| TC-373-03 | Fixed-v1 grammar is distinct from rich payloads and never becomes a fake staged envelope | `IosNseMailboxWakeCoordinatorTests.testTC37303ExactFixedGrammarAndRichCompatibility` | Available simulator XCTest / table fixture | Fixed currently follows rich resolver/sanitizer -> string-v1 exact branch fetches once; numeric-v/w/rich/mixed do not; incumbent rich direct/group fixtures remain byte-equivalent | Accept Android `w`, numeric v or private extra; stage fixed as rich; route rich into fetch -> red | One table-driven XCTest class in synthetic runner |
| TC-373-04 | Every incomplete/error/expiry/concurrency path preserves exact generic content and completes once; later canonical materialization cannot play a second sound | same class `.testTC37304OperationalFailureAndExpiryPreserveGenericOnce`; `test/core/notifications/ios_notification_recovery_wiring_test.dart::TC-373-04b one drain generation silences every page and consumes its mailbox alert lease only at fixed point` | XCTest + host Dart / fake bridge, Keychain statuses, Plan-371/372 stores, real paged inbox coordinator, iOS recovery MethodChannel and controlled completion generations | Current unresolved expiry blanks metadata and identity-less recovery is untracked -> original localized title/body/category/sound survive empty/hasMore/key/binding/network/proof/decrypt/policy-unknown/ledger busy/timeout; late callback loses; page one replays silently before ACK, partial/failed continuation keeps the lease, resumed pages stay silent, and only successful `hasMore == false` consumes it | Call sanitizer on operational failure, mutate generic candidate, allow two handlers/late ledger write, replay a partial page audibly, consume before fixed point, lose lease across crash/continuation, drop lease phase/generation, or replay sound -> red | Same focused XCTest plus one Dart production-wiring test; replace old unresolved-expiry expectation intentionally |
| TC-373-05 | Direct message/reaction and fetchable protected group content authenticate/decrypt and race main app through the one ledger/effect owner | same class `.testTC37305AuthenticatedCandidatesShareOneFinalEffectOwner`; `test/shared/fixtures/ios_nse_mailbox_v1.json` | XCTest / real incumbent-producer encrypted/signed direct and group bytes plus the Plan-372 shared ledger fixture | NSE cannot fetch/adopt -> exact from/recipient/signing-key-to-transport/signature/hash/event/logical-delivery/correlation parity; only signed group message/reaction enriches; media/voice uses descriptor only and performs zero blob work; one main/NSE winner/effect; loser no sound; relay row remains pending | Trust relay entry ID/APNs, cross sender signing key and transport peer, skip strict outer signature/recipient, mint wrong correlation, fetch blob, add second lock/store, ACK after preview -> red | Swift focused; TC-373-01 separately pins opaque Go retrieval; process-global/flock cases serial |
| TC-373-06 | Non-enumerable legacy group wakes and unsupported rows remain honestly generic | same class `.testTC37306LegacyGroupAndUnsupportedRowsDoNotInventAuthority` | XCTest / legacy group store/direct-empty; bootstrap/authority/mutation/delete/history/malformed/future and one-row/hasMore fixtures | Tempting group scan/guess -> zero scan/cursor/second fetch; direct-empty legacy group, every control/unsupported row and `hasMore=true` stay generic/un-ACKed; eligible protected direct row can enrich | Derive group ID from content/APNs, loop on hasMore, accept control/plaintext/unknown schema or promote blob -> red | Same table file; no new modality suite |
| TC-373-07 | Production wiring, rollback, privacy and build have one adapter/bridge/ledger path and no hidden alternate | `test/core/notifications/ios_nse_inbox_projection_test.dart::TC-373-07 one default-off projection and native adapter own fixed wakes`; native script/build/source sentinels | Host Dart/source-AST + Go header + Xcode embedded NSE | No path today -> one classifier/coordinator/export; no Flutter/ACK/new store/private log; future bytes read-only; rich/recovery preserved | Bypass ledger, add raw log, advertise on stale projection, omit binding symbol, add second host row or second store -> red | Exact Dart plus one synthetic `run_ios_nse_native_373.sh` host item |

### Test Notes

- TC-373-01's first RED is semantic: author the test and a minimal compiling
  inert API shell, then prove the exact peer-isolation/no-singleton assertion
  fails. Missing symbols, package compile, tool or teardown failure are not RED.
- TC-373-03 through 06 live in one table-driven XCTest file, not per-modality
  files. Direct/group and message/reaction are rows over one coordinator.
- TC-373-04 compares the original fixed generic content fields, not a sanitized
  approximation. An authenticated terminal policy row is a separate expected
  passive result.
- TC-373-05 proves the protected group row is in the per-device inbox. TC-373-06
  separately proves no legacy group enumeration is invented.
- TC-373-07 regenerates the final caller/capability/log census from the accepted
  Plan-372 tree. The active-linked iOS registration hook is the sole reason for
  the `1to1` curated lane; no group lane is implied by native fixture coverage.

## Implementation Steps

1. Run TC-373-00. Record the Plan-372 receipt SHA, commit, base/frozen/dirty/
   Graphify identities and exact finalized Swift ledger/visibility/effect APIs.
   Stop while the receipt is absent or its closure contains product drift.
2. Refresh Graphify TDD context and regenerate the fixed/rich NSE path, bridge
   retrieval, transport-authority, capability and logging census from the
   accepted source tree. Pin explicit rich/generic/group-only exceptions before
   editing production.
3. Add the Go TC-373-01 test and only a minimal compiling inert one-shot API
   shell. Record one peer-isolation/no-singleton semantic RED. Then refactor the
   incumbent strict per-relay retrieval into a host-parameterized bounded helper
   without changing the existing main-app wrapper's behavior.
4. Implement the no-listen one-shot host/export with exact peer derivation,
   bounded relay/address/one-row/frame/deadline inputs, protected-first same-peer
   legacy fallback, exact close-on-return and privacy-safe error codes. Do not
   ACK, persist, touch the singleton or start full Node services.
5. Add the single versioned transport projection and shared fixture. Reuse the
   exact qualified primary/active-linked selection after returned-peer-verified
   node startup; compose save/load/role/effective-relay refresh and retire-
   before-logout/switch/migration. Reread the projection before allowing iOS
   capability registration. On active linked iOS only, role-gate Firebase's
   on-ready composition, then call exactly one incumbent
   `PushRegistrationCoordinator.ensureStarted` after that read-back. Preserve
   its refresh/retry ownership, never call the raw registration closure in
   parallel and start no unrelated live-service fleet. The whole new hook is
   inert while the admission seam is false. Keep Android unready until N08.
6. Add strict direct and protected-group candidate validation around the
   incumbent Go decrypt primitives. Add only the bounded direct authorized-
   transport set and current group sender-authority tuple to the incumbent
   notification projections; no new authority store/history. Freeze real
   producer bytes in `ios_nse_mailbox_v1.json`, bind raw authenticated producer
   identity to Plan-369/372 event correlation and reject unsupported/control/
   plaintext/future rows. Select at most one deterministic eligible candidate
   from the one bounded row; never follow `hasMore`.
7. Add one `NseMailboxWakeCoordinator` and fixed classifier. Preserve a generic
   content copy before work, inject one clamped internal deadline and use the
   existing completion generation gate. Keep current rich staging/resolver
   behavior unchanged.
8. Consume the exact Plan-371 visibility reader and Plan-372 Swift ledger/effect
   API with owner `IOS_NSE`. Put the last binding/visibility/ledger-revision
   check at the shared final-effect boundary; honor the finalized lock order;
   evolve iOS recovery only with the bounded mailbox-alert lease, and wire the
   existing Runner/Dart paged-drain generation to replay every page silently and
   consume only at a successful no-more-pages fixed point. Preserve incumbent
   stage/replay/ACK ordering. Do not ACK or settle SQL/v116 in the extension and
   do not add a recovery store.
9. Regenerate the iOS GoMknoon binding using the incumbent digest script and
   verify the new export in simulator/device slices. Add no hand-edited binding
   or second generated framework.
10. Add one table-driven XCTest class, exact Dart projection/bootstrap/wiring tests and
    the single synthetic native host runner. Preserve exact rich resolver,
    completion, recovery, provider grammar, bridge and custody sentinels.
11. Run focused Go/Dart legs concurrently where they do not share artifacts.
    Run gomobile regeneration before Xcode; serialize Xcode/ledger-flock legs.
    Execute the registered synthetic host item once and the affected `1to1`
    curated lane once. Add no other curated/full/family sweep or device campaign.
12. Refresh Graphify, run analyzer/format/diff/privacy hygiene and a final
    `$tdd-review` bypass/rollback audit. Create a checksum-bound Plan-373 receipt
    only after every selected test is non-vacuously green.

## Risks And Blind Spots

- Wrong physical mailbox on linked installs -> reuse the already-qualified
  startup key selection; Go independently derives and matches the peer before
  any dial; TC-373-01/02 cover role and binding transitions.
- Revoked direct/group sender remains projected -> retire authorization before
  the authoritative DB mutation and republish only from committed trust/current-
  authority readback; crash or projection failure leaves generic fallback.
- NSE work exceeds Apple's budget -> one total clamped deadline, one bounded
  row, no `hasMore` loop, cancellable completion generation and generic winner
  on expiry.
- Operational failure becomes a blank alert -> immutable original generic
  candidate and TC-373-04 field-equivalence matrix; sanitizer is terminal-only.
- Rich/fixed mixed-version regression -> exact fixed grammar, separate path and
  retained rich direct/group fixture sentinels.
- Preview treated as durable receipt -> NSE never ACKs; main app re-retrieves and
  persists before relay deletion or v116 settlement.
- Identity-less generic fallback followed by canonical replay -> incumbent iOS
  request-recovery custody carries only the Apple request identifier plus
  recovery generation/sequence; the existing paged drain propagates one silent
  context until fixed point and never fabricates event identity or adds a
  mailbox queue.
- Group overclaim -> only protected content already present in the per-device
  inbox can enrich; legacy group-only/direct-empty is an explicit generic test.
- Relay/parser trust leap -> mailbox authentication is not content authority;
  strict direct/group outer validation precedes decrypt/render/correlation.
- Duplicate main/NSE effect -> one Plan-372 revision/content-generation owner,
  exact lock order and controlled cross-owner barrier.
- Late timeout callback mutates state -> completion generation invalidates work
  before generic completion; late results cannot write ledger/recovery/content.
- Sensitive projection/log leakage -> one minimal Keychain document, first-
  unlock-only access, exact field/source guard and no raw peer/relay/key/error
  logs on the touched path. Primary dual-use key expansion is explicit and
  admission-bounded; a policy rejection is a stop, not a hidden key redesign.
- Gomobile artifact drift -> deterministic input digest, regenerated framework,
  header/slice symbol and Xcode-link verification.
- Capability rollback hazard -> no new capability; paired registration remains
  default false and additionally requires exact iOS projection read-back.

## Gate Cadence

- Per-plan: dependency preflight; focused semantic Go RED/GREEN; exact Dart
  projection/wiring; one table-driven Swift adapter suite; exact Go/Swift/Dart
  preservation; gomobile verification; one Runner simulator build with embedded
  NSE assertions; analyzer/format/privacy/diff/Graphify.
- Parallelism: after Go production is green, independent focused Go and Dart
  tests may run concurrently with isolated logs. The iOS binding is regenerated
  once before Swift/Xcode. Xcode builds/tests and process-global ledger/flock
  cases run serially.
- Synthetic host item: register exactly one
  `scripts/test/run_ios_nse_native_373.sh` path through the host runner's
  inventory, predicate, printed-command and execution dispatch branches.
  Execute only that registered row during Plan 373. Later wave/final host-all
  will rediscover it once.
- Curated lanes: run `1to1` once because the required active-linked iOS hook
  changes shared startup/push-registration composition. Do not also run
  `groups`; protected group candidates use the same per-device inbox/native
  adapter and have exact Go/Swift coverage. If final implementation does not
  need that hook after re-grounding, remove the lane with the hook rather than
  retaining a ritual sweep.
- No `host-all`, `core-host-all` or `feature-host-all`: Plan 372 already owns the
  N03-N06 wave run; WP-07 owns final closure.
- Device policy: record `flutter devices --machine` and available simulators.
  Use one explicitly rediscovered iPhone simulator for one build-and-XCTest
  invocation when available; otherwise record
  `N/A (target unavailable by project policy)` and run one generic simulator
  `build-for-testing` so RunnerTests and the embedded NSE still compile. Do not
  duplicate that with a standalone NSE build. No USB iPhone, Android, two-peer
  or APNs campaign is a Plan-373 gate.

## Acceptance Gates

```bash
# 0. Snapshot only. Plan-371 implementation and later Plan-372 execution are
# user-owned; do not clean, stage or rewrite them.
set -euo pipefail
git status --short

# 1. Run the exact Dependency Contract subshell above. It must pass before RED.

# 2. After authoring the Go test and minimal compiling inert API shell, prove
# one selected semantic assertion RED. Package/tool/teardown failure is invalid.
plan373_gate_dir="$(mktemp -d "${TMPDIR:-/tmp}/plan373-gates.XXXXXX")"
set +e
(
  cd go-mknoon
  GOTOOLCHAIN=go1.25.0 go test ./node \
    -run '^TestNSEInboxOneShotAuthenticatesPeerAndRetrievesProtectedPage$' \
    -count=1 -v
) >"$plan373_gate_dir/red.log" 2>&1
red_status=$?
set -e
test "$red_status" -ne 0
test "$(rg -c '^=== RUN[[:space:]]+TestNSEInboxOneShotAuthenticatesPeerAndRetrievesProtectedPage$' "$plan373_gate_dir/red.log")" -eq 1
test "$(rg -c '^--- FAIL: TestNSEInboxOneShotAuthenticatesPeerAndRetrievesProtectedPage ' "$plan373_gate_dir/red.log")" -eq 1
rg -Fq 'NSE one-shot must isolate the physical mailbox without the global singleton' \
  "$plan373_gate_dir/red.log"
! rg -q 'panic:|build failed|no tests to run|^[[:space:]]*--- SKIP:' "$plan373_gate_dir/red.log"

# 3. Exact Dart projection/bootstrap/recovery wiring. Five selected IDs, five matched
# successes, zero skips. After binding regeneration, this independent leg may
# run concurrently with the registered native item in Step 5.
flutter test --concurrency=2 --machine \
  test/core/notifications/ios_nse_inbox_projection_test.dart \
  test/core/notifications/ios_notification_recovery_wiring_test.dart \
  test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart \
  --name 'TC-373-(02|04b|07)' >"$plan373_gate_dir/dart.json"
jq -c 'select(type == "object")' "$plan373_gate_dir/dart.json" \
  >"$plan373_gate_dir/dart-events.json"
dart_names=(
  'TC-373-02 exact physical transport projection gates paired iOS capability'
  'TC-373-02c committed direct and group authority mutations retire before exact republish'
  'TC-373-02b active linked iOS registers its exact physical paired route without starting unrelated live services'
  'TC-373-04b one drain generation silences every page and consumes its mailbox alert lease only at fixed point'
  'TC-373-07 one default-off projection and native adapter own fixed wakes'
)
for name in "${dart_names[@]}"; do
  test "$(jq -s --arg name "$name" '[.[] | select(.type == "testStart" and (.test.name | contains($name)))] | length' "$plan373_gate_dir/dart-events.json")" -eq 1
done
test "$(jq -s '([.[] | select(.type == "testStart" and (.test.name | contains("TC-373-"))) | .test.id]) as $ids | [$ids[] as $id | if ([.[] | select(.type == "testDone" and .testID == $id and .result == "success" and .skipped == false)] | length) == 1 then empty else $id end] | length' "$plan373_gate_dir/dart-events.json")" -eq 0
test "$(jq -s '[.[] | select(.type == "testStart" and (.test.name | contains("TC-373-")))] | length' "$plan373_gate_dir/dart-events.json")" -eq 5
test "$(jq -s '[.[] | select(.type == "testDone" and .skipped == true)] | length' "$plan373_gate_dir/dart-events.json")" -eq 0

# 4. Exact Dart physical-identity/default-off preservation.
flutter test --concurrency=2 --machine \
  test/features/p2p/application/start_node_use_case_test.dart \
  test/core/services/p2p_service_impl_test.dart \
  --plain-name 'TC-360-01a linked-secondary transport identity is distinct stable and fail-closed' \
  >"$plan373_gate_dir/dart-identity.json"
jq -c 'select(type == "object")' "$plan373_gate_dir/dart-identity.json" \
  >"$plan373_gate_dir/dart-identity-events.json"
test "$(jq -s '[.[] | select(.type == "testStart" and .test.url != null)] | length' "$plan373_gate_dir/dart-identity-events.json")" -eq 2
test "$(jq -s '([.[] | select(.type == "testStart" and .test.url != null) | .test.id]) as $ids | [.[] | select(.type == "testDone" and (.testID as $id | ($ids | index($id)) != null) and .result == "success" and .skipped == false)] | length' "$plan373_gate_dir/dart-identity-events.json")" -eq 2
test "$(jq -s '[.[] | select(.type == "testDone" and .skipped == true)] | length' "$plan373_gate_dir/dart-identity-events.json")" -eq 0
flutter test --concurrency=2 \
  test/core/bridge/p2p_bridge_client_wake_outcome_test.dart \
  --plain-name 'TC-370-05 opaque outcome uses strict all-relay completion'
flutter test --concurrency=2 \
  test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart \
  --plain-name 'TC-370-07 production composes one default-off outcome admission and one shared drain callback'

# 5. Regenerate/verify the binding once, then execute the one registered native
# item. It is the sole GREEN owner for the four new focused Go tests and their
# race run, and it also executes four exact node/bridge preservation tests,
# Swift causal/preservation tests, the embedded NSE build, symbol/entitlement/
# privacy checks and availability-bounded simulator choice. The four new Go
# roots are not rerun elsewhere; two incumbent preservers intentionally repeat
# in the required `1to1` lane as documented in the native-runner contract.
./scripts/ensure_go_ios_bindings.sh
PLAN373_NATIVE_RESULT_DIR="$plan373_gate_dir/native" \
  ./scripts/run_host_test_gates.sh host-all \
    --only scripts/test/run_ios_nse_native_373.sh

# 6. Registration is exact: one host-all row, bash in print and execution
# dispatch, absent from dart-only. Do not count only a path/comment occurrence.
host_discovery="$plan373_gate_dir/host-discovery.log"
./scripts/run_host_test_gates.sh host-all --dry-run \
  --only scripts/test/run_ios_nse_native_373.sh | tee "$host_discovery"
test "$(rg -c '^[[:space:]]*[0-9]+\. bash scripts/test/run_ios_nse_native_373\.sh$' "$host_discovery")" -eq 1
dart_only_discovery="$plan373_gate_dir/host-dart-only-discovery.log"
./scripts/run_host_test_gates.sh host-all --dart-only --dry-run \
  >"$dart_only_discovery"
! rg -Fq 'run_ios_nse_native_373.sh' "$dart_only_discovery"
host_script='scripts/test/run_ios_nse_native_373.sh'
rg -Fq 'readonly IOS_NSE_NATIVE_373=' scripts/run_host_test_gates.sh
rg -Fq 'is_ios_nse_native_373' scripts/run_host_test_gates.sh
rg -Fq "printf 'bash %s' \"\$IOS_NSE_NATIVE_373\"" scripts/run_host_test_gates.sh
rg -Fq 'bash "$IOS_NSE_NATIVE_373"' scripts/run_host_test_gates.sh
rg -Fq 'fifteen non-Dart tails' scripts/run_host_test_gates.sh
test -f "$host_script"
bash -n "$host_script"

# 7. The native script must retain a machine-readable disposition and exact
# non-vacuity itself. Simulator XCTest may be policy N/A; generic build may not.
test -s "$plan373_gate_dir/native/ios-xctest-disposition.txt"
test "$(wc -l <"$plan373_gate_dir/native/ios-xctest-disposition.txt" | tr -d ' ')" -eq 1
rg -x 'PASS: 16/16 on [0-9A-Fa-f-]{36}|N/A \(target unavailable by project policy\): no available iPhone simulator' \
  "$plan373_gate_dir/native/ios-xctest-disposition.txt"
test -s "$plan373_gate_dir/native/runner-simulator-build.log"
test -s "$plan373_gate_dir/native/flutter-devices.json"
test -s "$plan373_gate_dir/native/ios-simulators.json"
test -s "$plan373_gate_dir/native/go-focused.log"
test -s "$plan373_gate_dir/native/go-preservation.log"
test -s "$plan373_gate_dir/native/binding-contract.log"
test -s "$plan373_gate_dir/native/fixture-membership.log"
test -s "$plan373_gate_dir/native/privacy-manifests.log"

# 8. The active-linked iOS registration hook changes shared startup
# composition, so run only the affected 1to1 lane. Do not run groups or a host
# family/full sweep.
./scripts/run_test_gates.sh 1to1

# 9. Hygiene. Include tracked, staged and untracked nonignored Dart/Swift/Go.
changed_dart="$plan373_gate_dir/changed-dart.txt"
{
  git diff --name-only -- '*.dart'
  git diff --cached --name-only -- '*.dart'
  git ls-files --others --exclude-standard -- '*.dart'
} | sort -u >"$changed_dart"
if test -s "$changed_dart"; then
  xargs dart format --output=none --set-exit-if-changed <"$changed_dart"
fi
changed_go="$plan373_gate_dir/changed-go.txt"
{
  git diff --name-only -- '*.go'
  git diff --cached --name-only -- '*.go'
  git ls-files --others --exclude-standard -- '*.go'
} | sort -u >"$changed_go"
if test -s "$changed_go"; then
  xargs gofmt -d <"$changed_go" | tee "$plan373_gate_dir/gofmt.diff"
  test ! -s "$plan373_gate_dir/gofmt.diff"
fi
flutter analyze
git diff --check
plutil -lint ios/Runner/PrivacyInfo.xcprivacy
plutil -lint ios/NotificationService/PrivacyInfo.xcprivacy
./graphify-arch/refresh_arch_graph.sh --incremental
python3 graphify-arch/tdd_context.py query \
  'Plan 373 final GAP-N07 iOS NSE fixed wake one-shot inbox generic fallback ledger bypass rollback tests' \
  --profile review --budget 800 --ensure-fresh
```

The native runner must:

- be the one final GREEN execution owner for the four exact TC-373-01 Go root
  tests (plus `-race`); the four incumbent roots
  `TestInboxAckCustodyReceiveFanoutContract`,
  `TestTC364GroupContentProtectedCustody`,
  `TestDispatchInboxAckCustodyContract` and
  `TestBridgeExportedHandlersUseSharedEntrypoint`. It must run `-list` discovery
  first, require 4/4 root PASS lines and zero indented/root skips, and retain
  `go-focused.log` and `go-preservation.log`. The four new roots run nowhere
  else. Two incumbent preservers (`TestInboxAckCustodyReceiveFanoutContract`
  and `TestDispatchInboxAckCustodyContract`) intentionally run again in the
  affected curated `1to1` lane; keeping that standard lane intact is simpler
  and safer than conditional evidence reuse. The other two do not repeat. The
  three relay sentinels run once in the dependency preflight and are preserved
  after the change by the required curated lane; the native runner does not
  duplicate them;
- pin these exact RunnerTests Sources memberships once each:
  `ios/NotificationService/NseMailboxWakeCoordinator.swift`,
  `ios/NotificationService/NseInboxCandidateAdapter.swift`,
  `ios/NotificationService/NseInboxCredential.swift`, and
  `ios/RunnerTests/IosNseMailboxWakeCoordinatorTests.swift`. Production files
  remain auto-members of the filesystem-synchronized NotificationService
  target, but that does not make them RunnerTests members;
- pin these exact RunnerTests Resources memberships once each:
  `test/shared/fixtures/ios_nse_mailbox_v1.json` and
  `test/shared/fixtures/local_notification_ledger_v1.json`. After build,
  byte-compare both resources in `RunnerTests.xctest` with their single
  repository sources; do not create a copied second fixture;
- record `flutter devices --machine` as `flutter-devices.json` and
  `xcrun simctl list devices available -j` as `ios-simulators.json`. Select only
  an `available` iPhone simulator UDID from the latter;
- discover an available iPhone simulator dynamically, pin its UDID, and run
  exactly these 16 methods in one non-parallel XCTest invocation:
  - `IosNseMailboxWakeCoordinatorTests/testTC37303ExactFixedGrammarAndRichCompatibility`;
  - `IosNseMailboxWakeCoordinatorTests/testTC37304OperationalFailureAndExpiryPreserveGenericOnce`;
  - `IosNseMailboxWakeCoordinatorTests/testTC37305AuthenticatedCandidatesShareOneFinalEffectOwner`;
  - `IosNseMailboxWakeCoordinatorTests/testTC37306LegacyGroupAndUnsupportedRowsDoNotInventAuthority`;
  - `NotificationPreviewResolverTests/testDecryptsOneToOneFixturePreview`;
  - `NotificationPreviewResolverTests/testDecryptsGroupFixturePreview`;
  - `NotificationPreviewResolverTests/testGroupReactionUsesProjectedContextAndClaimsOnlyAfterExactParity`;
  - `NotificationPreviewResolverTests/testNotificationServiceCompletionGateExpiryBeforeResolutionRejectsPublisher`;
  - `NotificationPreviewResolverTests/testNotificationServiceCompletionGateRejectsStaleRequestGeneration`;
  - `NotificationPreviewResolverTests/testRejectedNormalAuthMuteDedupeMalformedAndOversizedSanitizeProviderMetadata`;
  - `NotificationPreviewResolverTests/testKeychainReaderUsesEntitledAccessGroupAndRealSecurityQueryKeys`;
  - `NotificationServiceConfigurationTests/testRunnerAndNotificationServiceEntitlementsShareAppGroupAndKeychainGroup`;
  - `NotificationServiceConfigurationTests/testNotificationServiceInfoPlistUsesUserNotificationsServicePoint`;
  - `IosNotificationRecoveryTests/testProductionHandoffSeamClaimsBeforeHandlerAndCommitsAfter`;
  - `IosAppVisibilitySnapshotTests/testTC37106AtomicSnapshotLifecycleAndPrivacyContract`;
  - `IosAppVisibilitySnapshotTests/testTC37106DuplicateUIApplicationAndUISceneActiveDoesNotClearInterleavedRouteCAS`;
- parse the result bundle with `xcresulttool` and require the exact method set,
  16 passes, zero failures and zero skips; or record exactly one policy N/A
  line. Retain exactly `PASS: 16/16 on <UDID>` or
  `N/A (target unavailable by project policy): no available iPhone simulator`;
- with a simulator, use the single exact Runner test invocation to build and
  verify the embedded `NotificationService.appex`; without one, use one generic
  Runner `build-for-testing`. In either branch verify GoMknoon export/linkage,
  extension point, entitlements and bundled privacy manifest. Do not add a
  redundant standalone NotificationService build;
- require both
  `ios/Runner/GoMknoon.xcframework/ios-arm64/GoMknoon.framework/Headers/Bridge.objc.h`
  and
  `ios/Runner/GoMknoon.xcframework/ios-arm64_x86_64-simulator/GoMknoon.framework/Headers/Bridge.objc.h`
  to contain exactly one `BridgeNSEInboxRetrievePending` declaration; recompute
  `gomobile_binding_input_digest ... ios` and exact-match
  `ios/Runner/GoMknoon.inputs.sha256`. The Xcode phase must be a digest no-op;
  never hand-edit or rebuild a second framework;
- update the host-runner help inventory from fourteen to fifteen non-Dart tails
  when registering this one row, and source-check that exact count wording;
- preserve `SystemBootTime:35F9.1` and `FileTimestamp:C617.1`, empty collected
  data and tracking false; add no speculative Keychain/network privacy category;
- run no physical device, APNs, Android or full host gate.

## Execution Interpretation And Done Criteria

- Expected RED: exactly one selected Go TC-373-01 assertion fails because the
  inert one-shot API cannot preserve peer isolation/no-singleton behavior.
  Missing symbol/package/tool/teardown failure is not accepted.
- Green sentinel: four new Go tests and five Dart tests pass exactly once; the
  four Swift causal methods pass with zero skips when a simulator is available;
  exact original generic fields survive every operational failure.
- Prerequisite blocker: missing Plan-372 receipt is expected until Plan 372
  executes. It is not evidence that N05/N06 failed.
- Environment policy: unavailable iPhone simulator is N/A only for XCTest;
  generic simulator build, Go/Dart and source/privacy checks remain mandatory.
- Scope drift: full Node startup, new protocol/group scan/ACK/store/queue, DB
  migration, second ledger/lock, physical device campaign, capability
  activation or full-host sweep stops execution for review.
- Native-authority stop: if the accepted Plan-372 API cannot treat a verified,
  still-relay-owned row as NSE materialization authority, or the incumbent iOS
  recovery/paged-drain seams cannot carry the bounded mailbox-alert lease and
  silent-generation handoff, stop. Do not add a second ledger/journal or claim
  N07/A-15 closure.

- [ ] TC-373-00 validates the committed Plan-372 receipt/tree and default-off
      paired admission.
- [ ] TC-373-01 through TC-373-07 each have a named causal proof and at least
      one representative mutation re-reds before reversion.
- [ ] The NSE uses the exact physical primary/linked transport key and binding;
      linked never falls back to the logical-account key, the primary dual-use
      key exception is explicit/admission-bounded, and no sensitive log exists.
- [ ] Direct/group sender authorization retires before authoritative mutation
      and republishes only committed current trust/authority readback; stale,
      crossed, removed or failed projections remain generic.
- [ ] Fixed-v1 failure/expiry returns the untouched generic content exactly once;
      rich payload behavior is preserved.
- [ ] One bounded protected-first/legacy-fallback row is fetched under one
      deadline, with no singleton/listener/ACK/loop/persistence side effect.
- [ ] Direct and fetchable protected-group candidates validate complete event
      authority; legacy group-only/direct-empty remains generic.
- [ ] Main/NSE races use one Plan-372 owner/revision/effect lock and relay custody
      remains pending until main-app persistence.
- [ ] A mailbox-alert lease makes every page in one existing drain generation
      silent, survives partial/crash continuation and is consumed only at the
      successful no-more-pages fixed point.
- [ ] The one synthetic native row executes through the host runner and is
      absent from dart-only; no full/family host sweep runs.
- [ ] Binding/header/framework, embedded NSE, entitlements, privacy, analyzer,
      format/diff and refreshed Graphify gates are clean.
- [ ] No physical iPhone/APNs/activation/rich-retirement/N08/N11/N12/release
      claim is made.

## Handoff

- First causal RED: TC-373-01 after its test and minimal compiling inert Go API
  shell are authored.
- Manual registration: one synthetic
  `scripts/test/run_ios_nse_native_373.sh` row in every required host-runner
  branch. The active-linked hook runs existing curated `1to1` once; no new
  shared Dart curated registration and no full host run.
- Migration: no SQL migration, relay migration or new durable inbox. One
  additive versioned Keychain projection is installation/account bound,
  retire-before-switch and ignored by old builds.
- Preservation: exact provider request, four Go bridge/node contracts, rich
  direct/group resolver, completion-gate races, recovery handoff, entitlement/
  extension-point and privacy/build sentinels.
- Success marker after execution/audit only:
  `N07_IOS_NSE_OPAQUE_WAKE_ADAPTER_CODE_COMPLETE_IOS_EVIDENCE_DEFERRED`.
- Write that marker once as a standalone raw receipt line so downstream exact
  `rg -Fqx` dependency checks cannot accept a prose-only near match.
- Receipt: create `Test-Flight-Improv/evidence/373/README.md` plus sibling
  checksum. Bind Plan-372 receipt, base/frozen/dirty/Graphify identities, exact
  focused/preservation/native results, generated-binding digest, simulator
  disposition, generic-fallback proof,
  `OpaqueWakePlatformConsumerReadiness`, and default-off/no-ACK/no-full-host
  facts.
- Meaning: the N07 iOS adapter mechanism is code-complete against host/simulator
  evidence. It does not claim physical APNs/lifecycle/lock/force-quit evidence,
  capability activation, universal legacy-group enrichment, full GAP-N07/PRD
  acceptance or release eligibility.
- Next: N08 adopts the same shared authority for Android; N11 composes read/
  mute/activation semantics; N12/WP-07 owns live Apple and rollout closure.

## Reviewer Findings

Independent `$tdd-review` result: **PASS after bounded in-place corrections**.

- Dependency and state truth: PASS. Plan 373 requires the checksum-bound
  phase-preserving Plan-372 native-source transition. SQL materialization cannot
  terminalize an ambiguous `PUBLISHING` effect, and the NSE never fabricates
  SQL/read authority.
- Identity and content authority: PASS. Primary dual-use key exposure is
  explicit and admission-bounded; linked identity never falls back to the
  account key. Direct trust and the bounded current group sender set retire
  before authoritative mutation and republish only committed readback. Crossed,
  revoked, stale or failed projections remain generic.
- Fallback, custody and races: PASS. Fixed-wake operational failure preserves
  the immutable generic candidate. The incumbent recovery document carries one
  bounded mailbox-alert lease through the existing page-wise drain generation;
  partial/crash continuation stays silent and only a fixed point consumes it.
  NSE retrieval never ACKs or creates a second inbox/ledger.
- Gate integrity: PASS. Machine JSON is normalized before assertions; five Dart
  IDs, four new Go roots plus exact preservation/race, and 16 Swift methods are
  discovered and counted non-vacuously. One registered native row and one
  affected `1to1` lane replace broad/family/full-host repetition; two incumbent
  Go preservers intentionally overlap that standard lane and are documented.
- Reversibility and economy: PASS. The exact fixed/rich discriminator, ordered
  relay list, current projections, optional recovery member and generated
  binding are additive/default-off. There is no new relay protocol, backend,
  DB, worker, Flutter engine, authority history, second lock/store, device
  campaign or audit plan.

Rejected expansions: Plan 374, full Node startup in the NSE, group enumeration,
authority-history projection, a mailbox journal, scoped relay protocol, DB
migration, standalone evidence plan, per-modality tests, physical-iPhone gate,
or another host-family sweep.

## Arbiter Decision

Proceed with exactly one N07 implementation plan after Plan 372's committed
receipt validates. Plan 373 owns only the default-off iOS NSE adapter vertical:
one qualified credential projection, one bounded stateless Go read, one Swift
coordinator/validator, thin incumbent authority projections and one recovery
lease consumer. If the accepted Plan-372 API or primary-key security policy
invalidates those exact prerequisites, stop and re-review; do not hide the
change in another N07 plan. Success may emit only
`N07_IOS_NSE_OPAQUE_WAKE_ADAPTER_CODE_COMPLETE_IOS_EVIDENCE_DEFERRED`, never
live/GAP-N07/PRD/release acceptance.

## Execution Progress

Not started. Plan 373 remains prerequisite-blocked until Plan 372's committed
receipt validates. No RED, production edit, binding regeneration, native test,
device evidence or activation is claimed by this planning artifact.
