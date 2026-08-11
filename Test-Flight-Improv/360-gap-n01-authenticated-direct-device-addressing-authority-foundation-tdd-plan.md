# 360 - GAP-N01 Authenticated Direct Linked-Device Addressing Foundation

Status: EXECUTION_COMPLETED / POST_EXECUTION_REVIEW_INCOMPLETE / default-off / not release-eligible
Type: Modification
Planning baseline: `6d3bc6ccd7a26b8a9d8cc94ad3c5eee148cc08d7` (clean committed Plan 359 bounded-repair closure, descended from execution HEAD `9c67b1272a869e3696cddca2a57a09e31f29d6c3`; lane-selector + ordinary settlement qualification precede encryption, and the shared storage predicate owns the empty-text/null-edit guards).
Spec: `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2.md` A-18 and OQ-04; GAP-N01 / WP-01 in `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md`; this linked-secondary authority remains distinct from the single-primary account-move MVP in `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`
Classification: identity, addressing, and explicit trust foundation only; no direct event or blob custody adopter
Closure tier: host behavior + v112 migration + fixed-vector peer-derivation proof + one availability-bounded Android two-target identity/trust scenario; no activation, release, iOS, or full-host claim

## Planning Progress

| Time | Role | Evidence inspected | Decision / blocker | Disposition |
|---|---|---|---|---|
| 2026-08-11 | Evidence collector / planner | Graphify TDD context; startup/restore; contacts and QR; group device admission; v108/v109/v111; relay authenticated-peer namespace; account Move | Production currently equates account, libp2p transport, contact, and mailbox peer IDs. Restored installations share one mailbox and cannot have independent custody. | Split the roadmap before writing a custody adopter. |
| 2026-08-11 | Architecture review | `start_node_use_case.dart`, `p2p_service_impl.dart`, `restore_identity_use_case.dart`, `contact_model.dart`, relay STORE/RETRIEVE/ACK, group trust | Identity/roster plus v108/v109 fanout would cross schema, crypto, network identity, every event sender/receiver, retry, and ACK completion. | Plan 360 owns only direct-device addressing; Plan 361 owns blob-free event fanout; Plan 362 owns media/voice/v111. |
| 2026-08-11 | Counterexample review | Group flag/admission, contact-request LAN/auth, account migration, contact SQLite replacement, startup side effects, safety number, device runner | Reusing the group flag or contact-request channel is unsafe. A DB-local role migrates, contact-request LAN is unauthenticated, and an unknown runner scenario can execute the wrong proof. | Use a direct-only flag, device-local role/credential, a dedicated dual-signed QR trust handoff, exact runner registration, and no FK cascade. |
| 2026-08-11 | Test/gate review | Existing migration/identity/QR/profile tests; 1:1/core inventories; Android reliability runner; DTR-18 pins | Five compact host bundles plus one device acceptance are sufficient. Current inventory is host 1:1=120 and core Dart=404; the two planned headline paths would make them 122/405. | One final concurrency-4 focused proof, one serial 1:1, one core c4 sweep, fixed-vector Dart peer derivation, and one registered Android scenario; no feature/full-host/iOS campaign. |
| 2026-08-11 | Plan 359 execution/source revalidation | Clean execution HEAD `9c67b1272a869e3696cddca2a57a09e31f29d6c3`; current Graphify fingerprint `7a7dc08f28bf4b4d`; exact Plan-359 seven-file production diff versus this plan's owners | No production/test overlap changes Plan 360's reviewed identity/roster/QR boundary, and its command paths plus 120/404 pre-registration inventories remain valid. The separate Plan-359 audit found a bounded disappearing-DFE capability/predicate defect, so the required audited closure SHA does not yet exist. | Source-overlap revalidation passed; execution remains prerequisite-blocked only on the bounded Plan-359 repair and targeted re-audit. |
| 2026-08-11 | Plan 359 repair closure and post-repair overlap | Plan-359 repair diff (`delete_message_use_case.dart`, `direct_reaction_inbox_custody_outbox_db_helpers.dart`, two existing test paths, one shared fixture flag); Graphify fingerprint `c83d9864200b15db`; host `1to1` 120/120 PASS | The repair touches only the direct deletion sender and the shared v109 storage predicate. It adds no identity, transport-peer, contact-roster, QR or migration surface, so Plan 360's reviewed boundary and its 120/404 pre-registration inventories are unchanged. Plan 359's addendum is closed, including a recorded deviation that deliberately leaves `_isExactOutgoingDisappearingLineage` broad. | Prerequisite satisfied. Pin the repair commit SHA as the planning baseline, re-run the one-query Graphify revalidation, then author RED. |
| 2026-08-11 | Final prerequisite release | Committed Plan-359 repair closure `6d3bc6ccd7a26b8a9d8cc94ad3c5eee148cc08d7`; one post-commit review-profile Graphify query, fingerprint `0c34708b5a8f68fa`; literal Plan-360 command paths/inventories | No identity/startup/P2P, v112/contact-roster, QR/trust, migration, bootstrap or runner owner changed. Existing inventories remain host 1:1=120 and core Dart=404 before the two planned headline registrations. | `EXECUTION_READY`; author only the per-owner semantic REDs below. |
| 2026-08-11 | Execution | All six TC-360 bundles authored and run; three representative mutations applied and reverted; DTR-18, completeness, curated and family gates | Two mutations initially FAILED to re-red and exposed real test-quality gaps, both fixed before proceeding: (a) the `preparing` snapshot in TC-360-01a carried a null credential, so the account-match guard masked the disposition guard under test; (b) no case exercised the transport-half signature alone, so removing that verification left the matrix green. | Both gaps closed, then all three mutations re-red independently and were reverted. `EXECUTION_COMPLETED`. |
| 2026-08-11 | Post-execution source and reachability audit | Current worktree, production composition roots, Move call sites, linked authority startup, QR stage transaction, runtime-root inventory, and a fresh Graphify review query | The candidate is not committed (`HEAD` remains the pre-implementation docs commit), several claimed production entry points are unreachable, both Move guards are not wired through the real journey, logical-account/transport qualification is incomplete at bootstrap/P2P boundaries, and blocked-contact admission is not rechecked in the stage transaction. | `POST_EXECUTION_REVIEW_INCOMPLETE`; preserve the execution receipts, apply the bounded repair below, commit it, refresh Graphify against that commit, and only then release Plan 361. |

## Problem And Source-Backed Evidence

- Production `startP2PNode` starts the node with the account Ed25519 private key and account peer ID. Mnemonic restore preserves that account identity and only re-mints ML-KEM, so two restored installations authenticate as one relay peer and share one inbox/ACK namespace.
- Direct contacts persist one account peer, signing public key, and ML-KEM key. There is no authenticated direct-device roster. Group device state is group-scoped and its own admission code says a user trust/admin wrapper is required; it is not a direct-contact authority.
- Relay custody can remain unchanged once installations have distinct authenticated transport peers, but current direct receive paths still equate transport and logical account. Plan 360 establishes the binding only; Plan 361 changes event envelopes/receive authentication.
- v108 helpers enforce one message owner, v109 authoring/completion is single-recipient despite its fanout-shaped key, and v111 is one attachment/recipient/incarnation. None can be safely widened here.
- The account-move MVP deliberately permits one active primary. A linked secondary is a separate, restricted role: it cannot be a Move source/destination, cannot enter normal messaging before Plan 361, and cannot silently fall back to the account transport.
- The existing contact-request transport is not suitable for device authority. Its LAN `from` is caller supplied, old receivers reject distinct transport/account identities, and its retry owner knows only contact ML-KEM exchange. A dedicated signed QR handoff for an already-known contact avoids a new network protocol and remains callable before Plan 361.
- Plan 359's bounded repair is committed at `6d3bc6ccd7a26b8a9d8cc94ad3c5eee148cc08d7`. It changes only the deletion sender and shared v109 storage predicate; it adds no identity, transport-peer, roster, QR or migration surface, so this foundation is unaffected.

Expected production surface after the Plan-359 revalidation:

- new direct-only default-off authoring selector under `lib/core/config/`; never widen `MKNOON_ENABLE_MULTI_DEVICE_SYNC`
- a narrow device-local linked-role/transport credential owner, `restore_identity_use_case.dart`, identity setup/startup routing, `start_node_use_case.dart`, and `p2p_service_impl.dart`
- one pure Dart Ed25519-public-key -> libp2p-peer-ID helper pinned to incumbent Go identity vectors; no Go/native/binding change
- `app_database_version.dart`, production migration registry, one v112 migration, exact direct-device helpers, the incumbent contact repository adapter, and transactional contact deletion
- dedicated direct-device QR build/parse use cases and their existing display/scanner wiring; no contact-request sender/handler/listener change
- the smallest existing contact profile/trust surface and `ContactSafetyNumber`
- migration secure-storage registry and source/destination Move preconditions; remote-contact roster migrates, installation role/secret does not
- one narrow role-aware deferred-runtime-start owner plus mandatory production-bootstrap wiring; `application_root.dart` keeps its incumbent unconditional callback unless its signature must change
- the existing reliability-simulation parser/runner/harness and their contract tests for one named Android scenario

Stop and re-review before touching chat/reaction/deletion senders or receivers, v108/v109/v110/v111, contact-request transport, relay/Redis custody, group repositories/flags, provider-token ownership, history sync, or an unlisted production boundary without a source-backed reason.

## Graph Grounding Snapshot

- Graph: `graphify-arch`, fingerprint `0c34708b5a8f68fa`; current at committed Plan 359 repair closure `6d3bc6ccd7a26b8a9d8cc94ad3c5eee148cc08d7`.
- Planning query: `python3 graphify-arch/tdd_context.py query "GAP-N01 Plan 360 direct authenticated linked-device recipient roster and per-device v108 v109 event custody; current sender recipient authority, linked devices, direct inbox fanout, ACK completion, ContactModel and direct inbox custody outboxes" --profile tdd --budget 700`.
- Review query: `python3 graphify-arch/tdd_context.py query "Review exact symbols startP2PNode restoreIdentityFromMnemonic ContactModel handleIncomingMessage direct_inbox_custody_outbox direct_reaction_inbox_custody_outbox GroupMemberDeviceIdentity pending_sibling_devices for Plan 360 linked device authority" --profile review --budget 800`.
- Confidence: anchored; load-bearing claims were verified in source.
- Revalidation: both the execution-HEAD pass and the final post-repair committed-tree query found no Plan-360 boundary change. The prerequisite is satisfied; any later direct-device authority or unlisted overlap returns this artifact to review before RED.

## Scope Contract

### Prerequisite and roadmap split

- Execute from committed Plan-359 repair closure `6d3bc6ccd7a26b8a9d8cc94ad3c5eee148cc08d7` or a descendant containing only the Plan-359 committed-closure receipt plus Plan-360 planning/index/status/coverage docs before RED; verify ancestry from `9c67b1272a869e3696cddca2a57a09e31f29d6c3`.
- Plan 360 establishes a production linked-secondary transport identity, a remote-contact device roster, explicit trust decisions, and a real QR producer/consumer. It does not adopt custody.
- Plan 361 is the immediate consumer: blob-free fresh text v108 plus supported v109 reaction/edit/deletion fanout and receive authentication. Plan 362 owns every media/voice/v111 obligation. `TC-345-09b` single-owner behavior remains unchanged through Plan 360.
- Record the maintained product arbitration: a linked secondary is not a second primary or an account-move target. It stays in a restricted setup/status/QR route until Plan 361. Generic recovery and Move remain single-primary.

### Direct-only selector and crash-safe installation authority

- Add `MKNOON_ENABLE_DIRECT_LINKED_DEVICES`, default false, with an injectable host seam. It gates only creation, QR authoring/scanning, and setup UI. It must not activate group multi-device code.
- Persist two device-local, non-exported secure-store records: an expected-linked-role marker and one versioned transport credential. Neither belongs in v112 or any migration bundle.
- Linked setup uses the existing canonical runtime installation ID as `deviceId`; do not mint a competing identifier. Bind its exact value into the credential. A missing/reset/mismatched runtime ID after activation refuses rather than rotating transport identity.
- Crash ordering is explicit: write expected-role first; create/adopt one credential in `preparing`; save the restored logical account identity and installation-local ML-KEM; transition that exact credential to `active` last. Marker-only may generate its first credential; once `preparing` exists, resume uses the same bytes. Every half-pair refuses normal startup and never falls back to account transport.
- Flag-off with no linked marker preserves primary startup byte-for-byte. Flag-off with an active linked credential still starts that exact transport: persisted authority is not disabled by authoring rollback. Missing/corrupt/cross-account/preparing authority is fail-closed.
- The linked credential contains logical account binding, canonical device ID, transport Ed25519 private/public key and derived peer ID. The transport signing key is that same Ed25519 key; do not create a second unexplained signing key. Raw secret material never enters SQLite/logs/analytics/receipts.
- Reuse bridge identity generation for a fresh transport credential, then prove private/public ownership with an existing sign/verify challenge. A pure Dart helper derives the libp2p peer ID from the Ed25519 public key and is pinned to fixed identity vectors produced by the incumbent Go implementation. Run it for BOTH account public -> logical account peer and transport public -> transport peer before node start or QR trust.

### Logical account versus transport startup

- Preserve the ordinary primary call path. For linked startup, the account-migration network gate receives the logical account peer while the bridge receives the transport private key/peer. The local identity projection records logical account, canonical device ID, and transport peer separately.
- Only after the offline key/peer checks pass does a linked start use the incumbent `autoRegister: true` node contract, preserving its renewable personal-rendezvous loop. It validates the returned peer (and hot-restart `node:status` peer) against the active credential before Dart warm/inbox/QR success; mismatch stops/refuses.
- Startup UI failure and network-start refusal remain distinct. A linked foundation mode may start only the exact node/status/QR owners; generic push registration, key-exchange/contact retry, group recovery, message retry/drain, and normal conversation/group/post/new-contact authoring stay stopped until Plan 361. TC-360-01a asserts zero calls.
- This restriction is decided before the router: the callback that `MyApp.initState` invokes delegates to a runtime-testable role-aware owner. Primary mode calls incumbent `startLiveServices`; linked-foundation mode starts only credential/peer/node/status/QR prerequisites and calls generic startup zero times. Partial linked authority starts neither. Later navigation is not accepted as a substitute for this pre-router gate.
- Explicit linked reset/logout deletes the expected-role marker, exact credential, and canonical runtime installation ID together through the incumbent local-reset authority. Partial deletion remains fail-closed until that exact reset completes.
- Account Move must reject a linked-secondary source and a destination that already has linked-role authority. Imported DB data cannot create/promote a local linked role. The two secure keys are registered `deviceLocal` and absent from exported/staged secure bundles.

### Direct-contact device authority at DB v112

- Add one `direct_contact_device_bindings` table plus one per-contact roster metadata table. Do not use group tables, JSON blobs, separate active/pending stores, or a fanout-generation ledger.
- A binding key is `(contact_account_peer_id, device_id)` and carries the immutable verified account signing public key, distinct transport peer ID, transport Ed25519 public key, device ML-KEM public key, immutable fingerprint, state (`pending`, `active`, `rejected`, `revoked`), and decision timestamps. Every row is linked, so require transport != account unconditionally; enforce one global transport owner and exact CHECKs.
- The immutable fingerprint is exactly account peer + verified account signing key + device ID + transport peer/public + ML-KEM public. QR issued-at and both signatures are excluded, so a fresh QR for the same credential is idempotent rather than contradictory.
- Do not materialize legacy canonical contact data as an immutable binding. Before explicit initialization, target resolution is the unchanged `ContactModel` peer/ML-KEM. Metadata records initialized plus legacy-active/revoked state; initialized resolution returns the dynamic legacy target when active plus exact active linked bindings. Missing legacy ML-KEM is nondeliverable. Initialized/all-revoked returns zero and never resurrects fallback.
- Exact binding replay wins before a fixed per-contact capacity of 16 and is idempotent in every state. Same device/transport with changed immutable material, duplicate transport, overflow, malformed key/peer, or crossed account refuses all-zero. There is no implicit eviction or automatic trust.
- Do not declare an FK cascade to `contacts`: ordinary contact upsert uses SQLite replacement semantics. The incumbent exact contact-deletion owner must transactionally delete roster metadata/bindings and then the contact; ordinary same-contact/key reannounce preserves roster rows.
- v111->v112 starts with empty remote rosters, preserves every contact/message/v108/v109/v110/v111 row, is run-twice idempotent, and advances `user_version` once. It is a one-way local floor. Remote-contact roster tables transfer through Move; installation role/credential never do.

### Dedicated dual-signed QR handoff

- Add a new, nested/versioned QR document with an exact purpose such as `direct_linked_device_binding`; do not add optional fields to the legacy contact QR. Old parsers therefore reject it without contact or ML-KEM mutation.
- The canonical body contains purpose/version, issued-at, logical account peer/public key, device ID, transport peer/public key, and device ML-KEM public key. It has exact key/field/length/total-size limits and the existing bounded QR age.
- The logical account Ed25519 key and the transport Ed25519 key independently sign the same domain-separated canonical body. Parse verifies both signatures and uses the pure Dart derivation helper to prove account public -> account peer and transport public -> claimed transport peer.
- Issued-at is canonical UTC and validated with an injected clock, an exact maximum age, and bounded future skew. Malformed, non-UTC, too-old, or too-far-future timestamps fail closed; do not inherit the legacy QR parser's permissive timestamp fallback.
- The builder is reachable only from the explicit linked setup/status route. The scanner is reachable only from the trust/profile flow for an existing contact.
- Scan requires the direct selector enabled, an existing non-blocked contact, and byte-equal stored account peer/public key. Unknown, blocked, stale/cross-account, expired, malformed, tampered, single-signed, peer/key-crossed, or legacy-looking input is all-zero.
- A valid scan stages/adopts one `pending` binding only. It never changes the contact, canonical ML-KEM, wake token, contact request, intro, network, or notification state. No LAN/contact-request/retry/listener owner is involved.

### Explicit trust and safety number

- Verify/Reject/Revoke re-read the current contact account key and exact full binding fingerprint/state in one DB transaction. Target resolution also requires the row's verified account key to equal the current contact key. Stale UI, contact-key drift, or a racing decision is all-zero/fail-closed.
- Verify activates only the exact pending binding and initializes metadata with legacy active by default. Reject records exact inactive authority and also initializes metadata with legacy active, so replay does not prompt again. Revoke affects one active linked binding; no decision auto-reactivates.
- `revokeLegacyTarget` is a separate exact transaction/action because legacy authority is dynamic rather than a binding row. It requires the expected current account signing key plus the exact current legacy peer/ML-KEM fingerprint before setting legacy revoked. This makes initialized/all-revoked reachable without fabricating a legacy binding.
- Contact profile shows exact account/device/transport fingerprints and owns Verify/Reject/Revoke. Production callers must supply the non-null trust capability so analyzer catches missing wiring; no source-substring wiring test is added.
- Safety number v1 stays byte-identical while no roster decision exists. `rosterInitialized` is explicit: initialized with sorted active/legacy device fingerprints uses v2, and initialized with zero active devices remains v2 rather than falling back to v1.

### Hard exclusions

- No v108/v109/v110/v111 change; no event/blob fanout, ACK aggregation, chat/event receive split, automatic contact/history hydration, or notification/provider-token fanout.
- No contact-request wire/handler/listener/retry/LAN change. No relay/Redis custody, Go, native, or generated-binding change.
- No group flag/roster/admission/UI change, no second scheduler/queue/owner, and no historical row promotion/backfill.
- No activation, A-18/GAP-N01 closure, release claim, full `host-all`, feature family, iOS, third device, performance, or broad group campaign.

## Test Contract

| Bundle | Causal behavior | Named proof and necessary paths | Current RED / mutation discriminator |
|---|---|---|---|
| TC-360-01a | Explicit linked setup is crash-safe; one exact credential is distinct and stable; flag-off honors persisted authority; partial/crossed state refuses. Account gate sees logical ID, bridge sees transport; fixed-vector/account+transport derivation and returned/hot peer must match before Dart warm/inbox/QR success. The real pre-router deferred-start owner calls generic runtime startup zero times in linked mode. Exact reset clears all three local authorities; ordinary primary remains exact. | `TC-360-01a linked-secondary transport identity is distinct stable and fail-closed` in existing key-conversion, restore, start-node, P2P service, identity-choice, startup-router, and production-bootstrap phase tests. | Current restore/start always uses account identity and bootstrap unconditionally starts full runtime services. Mutate to regenerate/fallback, skip the peer barrier, or bypass the role-aware runtime gate; the bundle re-reds. |
| TC-360-01b | v111->v112 preserves all durable rows/run-twice semantics; the remote roster moves, but marker/credential are device-local and linked source/destination Move is refused. | `TC-360-01b v112 remote roster migrates while linked installation authority cannot move` in the new migration test plus existing secure-registry, active-importer, and bundle/precondition tests. | Current v111 has no tables or secure keys. A DB-local role/exportable secret or missing Move precondition makes the bundle red. |
| TC-360-02a | Production QR builder -> scanner -> real repository stages one exact pending row for a known unblocked contact. Dual signatures, BOTH account/transport peer derivations, exact schema/size, canonical UTC/injected-clock age and future skew, replay-before-capacity, fresh-timestamp idempotency, tamper/unknown/blocked/crossed/overflow refusals, and zero contact/ML-KEM/network mutation are one compact matrix. | `TC-360-02a dual-signed linked-device QR stages only exact known-contact pending authority` in existing QR build/parse/display/scanner tests plus the new real-SQLite foundation test. | No device QR/roster exists. Mutate away account/device signature or peer binding; a negative stages and re-reds. |
| TC-360-03a | Real DB Verify/Reject/Revoke exact-CAS full authority; resolver compares the verified account key and keeps dynamic legacy fallback only while authorized; exact legacy revoke makes all-revoked reachable; stale key/UI/race, duplicate transport, and capacity fail closed. Contact upsert preserves rows; exact contact deletion removes only its roster. | `TC-360-03a direct-device trust owns exact admission revocation and legacy resolution` in the new real-SQLite foundation test. | No direct roster exists. Mutate exact-CAS/revocation fallback; stale or revoked authority becomes active and re-reds. |
| TC-360-03b | One open contact profile owns exact trust actions and refreshes safety number: v1 before initialization, order-independent v2 after activation, initialized-empty remains v2. | `TC-360-03b direct-device trust UI changes only the reviewed contact safety authority` in the existing profile screen test. | Current screen has no direct device capability/roster input. Missing exact callback or initialized-empty guard reds. |
| TC-360-04a | Registered availability-bounded Android pair: remote account B already knows account A; A's linked secondary uses real secure storage and bridge identity, starts with stable distinct transport, emits the dual-signed QR, B stages then explicitly verifies it, and one tampered QR is refused. Stop/start only; no chat/event/blob. | Host contract `TC-360-04a registered Android linked-device addressing scenario cannot fall through` plus exact reliability scenario `direct_linked_device_addressing`. | Parser/harness currently knows only existing scenarios and can fall into the wrong legacy branch. Unknown scenario must fail terminally. |

Test notes:

- Missing symbols are not RED receipts. Add only inert ports/types needed for a compile-clean test, then record per-owner behavioral REDs. TC-360-04a is acceptance, not a host RED.
- Keep five host functional bundles and one device bundle; do not create mode x state x platform cross-products. Each negative matrix uses one compact parameterized test.
- Real DB tests use isolated in-memory/temp databases so the final invocation is safe at concurrency 4.
- The pure Dart peer derivation is proved inside TC-360-01a against fixed account/transport vectors from the incumbent Go identity implementation; no Go/native/binding test or change is needed.
- Device proof uses production `FlutterSecureKeyStore` only for run-scoped linked marker/credential keys and deletes exactly those keys before/after. Other harness storage may remain fake. Raw keys never enter artifacts.
- Device topology is two targets, not three phones: target B is account A's linked secondary; target A is a different account with A's logical account already stored as a legacy contact fixture. The primary account-A device need not run.
- Preserve default-off group behavior, ordinary primary startup/contact QR, `TC-345-09b`, and single-primary Move through the curated lane rather than extra sentinel launches.
- Three mutations only: transport regeneration/fallback or peer-barrier removal; QR authentication/peer-binding bypass; trust exact-CAS/revoked-fallback bypass.

## Implementation Steps

1. **Satisfied.** Plan 359's bounded repair is committed at `6d3bc6ccd7a26b8a9d8cc94ad3c5eee148cc08d7`; the final review-profile Graphify query is current at fingerprint `0c34708b5a8f68fa`, and every listed owner plus the 120/404 pre-registration inventories remain valid.
2. Record the linked-secondary versus Move arbitration in maintained docs: restricted linked role, no second primary, Plan 361 immediate consumer.
3. Register the new direct selector and author per-owner compile-clean REDs for TC-360-01a through 03b. Author the host runner contract but do not treat the device leg as RED.
4. Add the two device-local secure records and crash-safe setup/resume owner. Keep primary recovery unchanged and gate linked source/destination Move.
5. Add the pure Dart peer-binding helper, linked startup separation, and role-aware pre-router deferred-runtime-start owner. Validate before node start, retain the incumbent renewable auto-register contract, then qualify the returned/hot peer before Dart warm/inbox/QR success. Preserve ordinary start and full-runtime startup byte-for-byte.
6. Add v112 metadata/binding tables and exact helpers. Wire transactional contact deletion without an FK cascade; preserve ordinary contact upsert.
7. Add the dedicated dual-signed QR build/parse/display/scan flow and stage only exact pending authority for an existing non-blocked contact.
8. Wire Verify/Reject/Revoke and deterministic resolver through the incumbent contact adapter/profile, including initialized-empty safety-number v2.
9. Register `direct_linked_device_addressing` in the reliability parser, expansion, explicit-ID/preflight, discovery contract, and harness. Add a scenario-specific ready artifact and make unknown scenarios terminal.
10. Run the one final concurrency-4 host proof, three mutation re-reds, the exact discovery contract, the DTR preflight, completeness, serial host 1:1, core c4, then one exact Android scenario.
11. Run analyzer, accepted-baseline/staged/unstaged format and diff hygiene, one incremental Graphify refresh, and update plan/index/status/coverage receipts without claiming fanout or GAP-N01 closure.

## Gate Cadence - Necessary Tests Only

- Inner loop: only the owning `--plain-name` row while implementing each bundle.
- Final focused: one Flutter invocation over the exact paths below, `--concurrency=4 --name 'TC-360-'`. Host tests inject selector false/true; do not compile the entire host bundle with the flag enabled.
- Exact non-Flutter proof: one reliability discovery shell contract. Peer derivation stays in the final Flutter host proof.
- DTR-18: production bootstrap necessarily changes, so run the two exact DTR contract files together once without a name filter before the core sweep. Repin only actually affected bootstrap/contact/identity hashes with adjacent Plan-360 rationale and unchanged assertions.
- Registration: two new headline test paths only (v112 migration and direct-device foundation), added to both 1:1 inventories; run completeness once. Planning counts then become host 1:1=122, core Dart=405, feature Dart=842, later host-all Dart=1341. Record live counts rather than forcing them.
- Curated: host `1to1` once; it is serial by script contract.
- Family: one dart-only `core-host-all` at concurrency 4 because v112/version/registry/secure-storage policy change. Omit feature family because final focused plus 1:1 cover every changed feature owner.
- Device: one registered physical-Android + Android-emulator scenario if available; otherwise `N/A (target unavailable by project policy)`. No iOS substitute or third device.
- Not run: non-host 1:1, full `host-all`, feature family, Go/relay/native/bindings, SQLCipher duplicate, group, performance, feed/posts, iOS, activation/release campaigns.

## Acceptance Commands

These commands are authorized from the pinned repair closure. Run each inner RED/GREEN only for its owning row, then run the final aggregate cadence once.

```bash
# Preflight after Plan 359 repair/audit. A committed Plan-360 doc/index may sit above the base.
PLAN360_ACCEPTED_BASE='6d3bc6ccd7a26b8a9d8cc94ad3c5eee148cc08d7'
test -z "$(git status --porcelain)"
git rev-parse --verify "${PLAN360_ACCEPTED_BASE}^{commit}"
git merge-base --is-ancestor "$PLAN360_ACCEPTED_BASE" HEAD
test -z "$(git diff --name-only "$PLAN360_ACCEPTED_BASE"...HEAD | grep -Ev '^(Test-Flight-Improv/359-gap-n01-disappearing-direct-media-delete-for-everyone-v109-custody-and-private-edit-disposition-tdd-plan.md|Test-Flight-Improv/360-gap-n01-authenticated-direct-device-addressing-authority-foundation-tdd-plan.md|Test-Flight-Improv/00-INDEX.md|STATUS.md|UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md)$' || true)"

# Per-owner compile-clean semantic RED, then the same command for its inner GREEN.
flutter test --concurrency=4 \
  test/core/utils/key_conversion_test.dart \
  test/core/services/p2p_service_impl_test.dart \
  test/features/identity/application/restore_identity_use_case_test.dart \
  test/features/p2p/application/start_node_use_case_test.dart \
  test/features/identity/presentation/screens/identity_choice_wired_test.dart \
  test/features/identity/presentation/screens/startup_router_test.dart \
  test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart \
  --plain-name 'TC-360-01a linked-secondary transport identity is distinct stable and fail-closed'

flutter test --concurrency=4 \
  test/core/database/migrations/112_direct_linked_device_addressing_test.dart \
  test/features/account_migration/application/migration_secure_storage_registry_test.dart \
  test/features/account_migration/application/migration_database_active_importer_test.dart \
  test/features/account_migration/application/migration_export_authorization_test.dart \
  test/features/account_migration/application/account_migration_import_precondition_test.dart \
  --plain-name 'TC-360-01b v112 remote roster migrates while linked installation authority cannot move'

flutter test --concurrency=4 \
  test/features/qr_code/application/build_qr_payload_use_case_test.dart \
  test/features/qr_code/application/parse_qr_payload_use_case_test.dart \
  test/features/qr_code/presentation/screens/qr_display_wired_test.dart \
  test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart \
  test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart \
  --plain-name 'TC-360-02a dual-signed linked-device QR stages only exact known-contact pending authority'

flutter test --concurrency=4 \
  test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart \
  --plain-name 'TC-360-03a direct-device trust owns exact admission revocation and legacy resolution'

flutter test --concurrency=4 \
  test/features/contact_profile/presentation/screens/contact_profile_screen_test.dart \
  --plain-name 'TC-360-03b direct-device trust UI changes only the reviewed contact safety authority'

# One final focused GREEN over every load-bearing host path.
flutter test --concurrency=4 \
  test/core/database/migrations/112_direct_linked_device_addressing_test.dart \
  test/core/utils/key_conversion_test.dart \
  test/core/services/p2p_service_impl_test.dart \
  test/features/identity/application/restore_identity_use_case_test.dart \
  test/features/p2p/application/start_node_use_case_test.dart \
  test/features/identity/presentation/screens/identity_choice_wired_test.dart \
  test/features/identity/presentation/screens/startup_router_test.dart \
  test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart \
  test/features/account_migration/application/migration_secure_storage_registry_test.dart \
  test/features/account_migration/application/migration_database_active_importer_test.dart \
  test/features/account_migration/application/migration_export_authorization_test.dart \
  test/features/account_migration/application/account_migration_import_precondition_test.dart \
  test/features/qr_code/application/build_qr_payload_use_case_test.dart \
  test/features/qr_code/application/parse_qr_payload_use_case_test.dart \
  test/features/qr_code/presentation/screens/qr_display_wired_test.dart \
  test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart \
  test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart \
  test/features/contact_profile/presentation/screens/contact_profile_screen_test.dart \
  test/integration/invite_reliability_runner_contract_test.dart \
  --name 'TC-360-'

# Exact scenario-registration contract.
bash scripts/test/reliability_simulation_discovery_contract_test.sh

# Expected DTR preflight before the expensive core sweep.
flutter test --concurrency=2 \
  test/unit/dtr18_placement_closure_contract_test.dart \
  test/unit/dtr18_layering_relocation_contract_test.dart

# New-path accounting, then affected curated/schema gates exactly once.
./scripts/run_test_gates.sh completeness-check
./scripts/run_host_test_gates.sh 1to1
./scripts/run_host_test_gates.sh core-host-all \
  --dart-only --batch-flutter --concurrency 4 --reporter failures-only

# One registered availability-bounded Android scenario, not a bare dart run.
flutter devices --machine
adb devices -l
RELIABILITY_MULTI_DEVICE_IDS='<USB_ANDROID_ID>,<ANDROID_EMULATOR_ID>' \
  ./scripts/run_test_gates.sh reliability-sim group --list \
  --only integration_test/scripts/run_invite_reliability_multi_device.dart:direct_linked_device_addressing
RELIABILITY_MULTI_DEVICE_IDS='<USB_ANDROID_ID>,<ANDROID_EMULATOR_ID>' \
  ./scripts/run_test_gates.sh reliability-sim group \
  --only integration_test/scripts/run_invite_reliability_multi_device.dart:direct_linked_device_addressing

# Final static/hygiene checks.
set -euo pipefail
plan360_base_ref='6d3bc6ccd7a26b8a9d8cc94ad3c5eee148cc08d7'
flutter analyze
plan360_dart_list="$(mktemp)"
trap 'rm -f "$plan360_dart_list"' EXIT
{
  git diff --name-only --diff-filter=ACMR "$plan360_base_ref"...HEAD -- '*.dart'
  git diff --name-only --diff-filter=ACMR -- '*.dart'
  git diff --cached --name-only --diff-filter=ACMR -- '*.dart'
  git ls-files --others --exclude-standard -- '*.dart'
} | sort -u > "$plan360_dart_list"
test ! -s "$plan360_dart_list" || \
  xargs dart format --output=none --set-exit-if-changed < "$plan360_dart_list"
rm -f "$plan360_dart_list"
trap - EXIT
git diff --check "$plan360_base_ref"...HEAD
git diff --check
git diff --cached --check
./graphify-arch/refresh_arch_graph.sh --incremental
git diff --check "$plan360_base_ref"...HEAD
git diff --check
git diff --cached --check
git status --short
```

The device runner must pass `--dart-define=MKNOON_ENABLE_DIRECT_LINKED_DEVICES=true` only to this scenario and leave `MKNOON_ENABLE_MULTI_DEVICE_SYNC` false. Its parser, expansion, explicit-ID preflight, discovery listing, ready artifact, and harness branch are part of TC-360-04a; unknown scenario is an error.

## Risks, Stops, And Reversibility

- Shared-mailbox fallback: any linked role that starts account transport is a correctness failure. Partial/corrupt authority refuses; it never regenerates/falls back.
- Trust laundering: account signature alone does not activate. Dual signature only stages pending; explicit local Verify owns admission.
- Contact replacement: FK cascade is forbidden because contact upsert uses replacement. Only exact contact deletion removes roster rows.
- Start ordering: offline account/transport key-to-peer proof is mandatory before linked `node:start`; returned/hot peer must match before Dart warm/inbox/QR success. Preserve Go's incumbent renewable auto-registration rather than replacing it with a one-shot register.
- Scope: needing chat/contact-request/group/v108-v111/relay changes proves the work has crossed into Plan 361/362.
- Rollback: no external rollout. Before v112 open, code rollback is normal; after open, older DB binaries fail closed. Secure credential and explicit trust decisions are durable. The direct authoring flag can stop new setup/QR activity but must not invalidate persisted authority.

## Done Criteria

- [x] Plan 359's bounded post-execution repair is committed and audited at `6d3bc6ccd7a26b8a9d8cc94ad3c5eee148cc08d7`; fresh Graphify fingerprint `0c34708b5a8f68fa` is pinned here. Execution HEAD `9c67b1272a869e3696cddca2a57a09e31f29d6c3` remains historical evidence only.
- [x] The maintained linked-secondary/Move arbitration and immediate Plan-361 consumer are recorded.
- [x] Five host bundles receive compile-clean behavioral REDs and one final concurrency-4 GREEN (`+18` over the 19 listed paths); TC-360-04a is a registered acceptance, not a fabricated host RED.
- [x] Three representative mutations re-red independently and are reverted. TWO initially did NOT re-red and exposed real test gaps (credential-less `preparing` fixture; no transport-half-only signature case); both gaps were closed first — see Execution Receipts.
- [x] Direct selector is default-off and group multi-device remains off; the device scenario passes `MKNOON_ENABLE_DIRECT_LINKED_DEVICES=true` only, and the runner emits no `MKNOON_ENABLE_MULTI_DEVICE_SYNC` define.
- [x] Linked credential is device-local, crash-safe, stable, account-bound, peer-qualified, Move-ineligible, and fail-closed.
- [x] v112 remote roster, dynamic legacy target, bounded pending authority, exact trust decisions, contact update/delete, and safety number converge.
- [x] Dedicated QR is dual-signed, peer-derived, known-contact-only, and has zero contact-request/network side effects.
- [x] v108/v109/v110/v111 and all event/blob paths remain single-recipient and unchanged.
- [x] Fixed-vector peer derivation, discovery contract, completeness, host 1:1 (122/122), core c4 (405 paths / 3,243 tests), analyzer/format/diff pass once.
- [x] One Android pair scenario PASSES on a physical Pixel 6 plus the Android emulator (`primaryExit=0 siblingExit=0`); no substitute platform matrix was used.
- [x] No activation, A-18/GAP-N01, fanout, history sync, release, or full-host closure is claimed.

## Execution Receipts

Executed from the accepted baseline `6d3bc6ccd7a26b8a9d8cc94ad3c5eee148cc08d7`. The
literal clean-tree preflight passed before RED.

### Production surface delivered

New owners:

- `lib/core/config/direct_linked_devices_flag.dart` — `MKNOON_ENABLE_DIRECT_LINKED_DEVICES`,
  default-off, plus the injectable `DirectLinkedDeviceSelector` host seam.
  `MKNOON_ENABLE_MULTI_DEVICE_SYNC` is untouched.
- `lib/features/identity/application/linked_installation_authority.dart` — the two
  device-local secure records, the versioned credential envelope, and the
  crash-safe classification (`primary` / `awaitingCredential` / `preparing` /
  `active` / `failClosed`).
- `lib/features/identity/application/linked_secondary_setup_use_case.dart` — the
  exact marker -> preparing -> restore -> activate ordering.
- `lib/app/bootstrap/role_aware_deferred_runtime_start.dart` — the pre-router
  role-aware deferred-start owner.
- `lib/core/database/migrations/112_direct_linked_device_addressing.dart` and
  `lib/core/database/helpers/direct_contact_device_bindings_db_helpers.dart` — the
  v112 roster, its exact CHECKs, and the stage/verify/reject/revoke/resolve helpers.
- `lib/features/qr_code/application/direct_linked_device_qr.dart` — the dedicated
  nested/versioned dual-signed document and its parser.
- `lib/features/contacts/application/direct_contact_device_trust.dart` — the trust
  capability, its real-database implementation, and the explicit inert variant.

Modified owners: `key_conversion.dart` (pure-Dart peer derivation),
`start_node_use_case.dart`, `p2p_service_impl.dart`, `startup_router.dart`,
`production_application_bootstrap.dart`, `application_root.dart`,
`identity_choice_screen.dart` / `_wired.dart`, `qr_display_wired.dart`,
`qr_scanner_wired.dart`, `scanned_qr_classifier.dart`, `contacts_db_helpers.dart`,
`contact_safety_number.dart`, `contact_profile_screen.dart`, `orbit_wired.dart`,
`conversation_wired.dart`, the three account-migration Move owners, and
`account_migration_journey_wired.dart`.

### Proofs

- Pure-Dart peer derivation is pinned to FOUR fixed vectors emitted by the real
  `go-mknoon/identity` implementation (`peer.IDFromPublicKey`) from BIP39 test
  mnemonics. No Go, native, or generated-binding change was made.
- Final focused GREEN: `18` TC-360 tests over the 19 listed paths at
  `--concurrency=4 --name 'TC-360-'`.
- Exact scenario-registration contract: `bash scripts/test/reliability_simulation_discovery_contract_test.sh`
  PASS, extended with the new row's selectability, its required explicit device
  pair (exit 64 without one), and terminal-unknown-scenario assertions on BOTH the
  host parser and the device harness.
- DTR-18: both contract files PASS. Two consumer digests were re-pinned with
  adjacent Plan-360 rationale and unchanged assertions
  (`_applicationRootNormalizedSha256`, `_productionBootstrapNormalizedSha256`).
- Completeness: `1439/1439` classified, PASS. The two new headline paths are
  registered in BOTH 1:1 inventories, taking host 1:1 from 120 to 122.

### Three mutations

Each was applied, re-red, and reverted. Two of them initially did NOT re-red and
exposed real gaps in the tests, both closed before the mutation was re-run:

1. **Transport fallback / peer-barrier removal** — disabling the `refusesStartup`
   guard in `startP2PNode`. First run stayed GREEN: the `preparing` fixture carried
   a null credential, so the account-match guard downstream masked the guard under
   test. Fixed by giving `preparing` its credential, exactly as
   `LinkedInstallationAuthority.load()` returns it. Then re-red.
2. **QR authentication bypass** — deleting the transport-half signature check.
   First run stayed GREEN: every negative in the matrix was caught by an earlier
   guard (distinctness, or the account-half check), so the transport verification
   was never exercised alone. Fixed by adding the two single-half forgery cases —
   account-valid/transport-forged and its mirror. Then re-red.
3. **Trust revoked-fallback bypass** — resurrecting a revoked legacy target once no
   active device remains. Re-red immediately.

### Deviations and accepted differences

- **`application_root.dart` was modified.** The plan preferred leaving it alone.
  One optional `directDeviceTrust` field was added to `MyApp` and threaded to the
  Orbit and Conversation hosts, because the contact profile's capability is
  REQUIRED and non-null and the composition root is the only place a real
  database-backed capability exists. Leaving it unwired would have shipped the
  trust UI unreachable. `ApplicationRoot` keeps its incumbent unconditional
  `deferredRuntimeStartup` callback and its exact signature; only what it delegates
  to changed. The DTR-18 digest was re-pinned accordingly.
- **The two wired host screens take an OPTIONAL capability.** Making it required
  there would have touched 301 construction sites. The requirement is enforced at
  the boundary the plan names — `ContactProfileScreen` — and the null case resolves
  to the explicit `UnavailableDirectContactDeviceTrust`, which reports an empty
  uninitialized roster and refuses every decision.
- **Curated lane.** Host `1to1` PASS at 122/122 paths measured live on the final
  settled tree, after the wiring fix below.
- **Core family.** `core-host-all --dart-only --batch-flutter --concurrency 4`
  PASS at 405 exact paths / 3,243 tests in one batched invocation.
- **Hygiene.** Analyzer clean, changed-Dart format clean, and all three
  `git diff --check` passes (baseline..HEAD, unstaged, staged) clean.
- **Graphify.** One incremental refresh: 71,479 nodes / 104,893 edges, overlay
  1,565 files / 15,348 named tests / 1,207 production targets, fingerprint
  `cd5da0facf62a050`.
- **Lane-staleness check.** The device-harness fixes landed after the curated
  and family lanes ran, so lane membership was re-derived rather than assumed:
  none of the changed paths are in the `1to1` set, and the only `test/core` and
  `test/unit` files that reference the harness
  (`media_repository_fixture_schema_inventory_test.dart`,
  `runtime_root_inventory_test.dart`) were re-run and pass. Both lane verdicts
  therefore still describe the committed tree.
- **A real production wiring gap was found late and fixed.** The
  transport-peer qualification was implemented and unit-proven on
  `P2PServiceImpl`, but the production composition root never passed
  `requiredTransportPeerId`, so it was DEAD in the real app — a linked
  secondary would have started without the barrier the plan requires. The
  in-flight `1to1` lane was STOPPED rather than certify a stale tree. The
  role-aware owner now publishes the resolved transport peer through a
  synchronous getter, production wires it via one forward reference, and
  `TC-360-01a` asserts both the publish/clear behavior and that exact wiring,
  so the seam cannot go dead again silently. Two more frozen fingerprints moved
  as a result (`_productionBootstrapNormalizedSha256`, and the conversation
  controller's direct API + handoff fingerprints for the one added optional
  widget field and the `onAvatarTap` pass-through); all were repinned with
  adjacent rationale and unchanged assertions.
- **The core family found four more owned failures, all fixed.** The first
  `core-host-all` run was `+3239 -4`; every failure was Plan 360's own:
  * `main_deferred_startup_wiring_test.dart` pinned
    `deferredRuntimeStartup: startLiveServicesIfAllowed,` literally. The
    properties it actually guards — ONE unconditional callback, no
    `isShareLaunch` ternary, and the retryable outcome wrapper owning primary
    startup — are all preserved, so the assertions were restated against the
    delegated shape (`roleAwareDeferredRuntimeStart.start` plus
    `startPrimaryRuntimeServices: startLiveServicesIfAllowed`) and a second
    negative was added so no share-launch ternary can return on the new
    callback either.
  * `runtime_root_inventory_test.dart` pinned the CURRENT schema floor as a
    preservation anchor (`currentIdentityDatabaseVersion = 111`), which
    advances with the floor, and flagged
    `linked_secondary_setup_use_case.dart` as an undeclared non-main-reachable
    source. That flag is ACCURATE and was not silenced: Plan 360 ships the
    restricted setup route entry and its default-off selector gate but no
    production builder, so the orchestrator's only current origin is
    `test/integration`. It is now declared `explained-root` with that exact
    reason and a condition requiring the declaration to be REMOVED — not
    retained — once Plan 361 supplies the setup surface.
- **Device-proof secure-state hygiene tightened before the run.** The first
  launch of the Android scenario was STOPPED because the harness wrote a THIRD
  secure key — the canonical runtime installation ID, which the authority reads
  and never mints — while the plan's test note sanctions run-scoped writes to
  the linked marker and credential only. The sibling role now captures whatever
  installation ID it found and restores it (or deletes it, if there was none)
  in `finally`, alongside deleting the two linked keys, so the proof leaves the
  device exactly as it found it.
- **Device acceptance PASSED on the fourth attempt**, on a real Pixel 6
  (`21071FDF600CSC`, linked-secondary/primary role) plus `emulator-5554`
  (account B/sibling role): `primaryExit=0 siblingExit=0`, "invite-reliability
  two-device proof completed successfully". The three preceding failures were
  ALL defects in this plan's own device harness, never in production and never
  in the devices, and each had a distinct cause:
  1. **Deadlock by construction.** The runner launches the PRIMARY first and
     starts the sibling only after the primary writes its readiness fixture
     (`alice_identity.json`). The scenario had account B on primary, waiting for
     a fixture only the linked secondary writes, so the sibling never launched
     and the primary timed out. No device could have passed it. Roles were
     swapped; `TC-360-04a` now pins the launch order and the readiness fixture,
     so this one fails at host-contract time.
  2. **Wrong peer.** `setupGroupMultiDeviceStack` already starts a node on the
     ACCOUNT identity, so the linked start hit `node:start` -> "already
     started" -> `node:status` resync and the service reported the account peer
     while believing it had started the transport. This is exactly the
     hot-restart hazard the production barrier exists for; production refuses
     it (`_qualifyLinkedTransportPeer` stops the node and fails the start),
     while the shared helper builds its service WITHOUT that qualifier, so only
     the explicit assertion caught it. The harness now stops the account node
     first and additionally asserts the started peer is not the account peer.
  3. **Lost artifact.** `flutter test` uninstalls the app when a role finishes,
     deleting the app-private signal dir, so an artifact written as a role's
     LAST action can be destroyed before the 500ms host sync pulls it — the
     sibling passed and the primary then waited 12 minutes for a file that no
     longer existed anywhere. Neither role now depends on the other's final
     action: the sibling signals completion early and waits to be released, and
     the linked side waits on that early signal before publishing its own
     artifact and releasing.

  Only (1) is guarded by a host-level contract; (2) and (3) are device-runtime
  properties no host test can observe.
- **The first Android run FAILED on a real harness defect, not the devices.**
  The runner launches the PRIMARY role first and only starts the sibling once
  the primary has written its readiness fixture (`alice_identity.json`). The
  original scenario put account B on primary, waiting for a fixture only the
  linked secondary writes — so the sibling was never launched and the primary
  timed out after 3 minutes (`Primary exited before readiness`). This
  deadlocked by construction; no device could have passed it. The roles are now
  swapped so the linked secondary IS the primary publisher, and `TC-360-04a`
  gained assertions that pin the launch order and the exact readiness fixture,
  so the same deadlock cannot be reintroduced silently.
- **Mechanical current-floor fan-out.** Advancing the schema floor to v112 required
  updating 22 test files that pin `currentIdentityDatabaseVersion`, the registry's
  last entry, or `registry.length - N` offsets, plus three frozen censuses: the v107
  historical-literal census in the v108 test (one offset moved), the frozen
  `idx_direct_*` index set in the v107 test (two v112 indexes added), and the
  P2P facade constructor/API fingerprint (one added optional parameter). All are
  repins with unchanged assertions.
- **`contacts_db_helpers_test.dart` fixture** now runs the v112 migration, because
  `dbDeleteContact` is the exact contact-deletion owner and legitimately requires
  the current schema.

## Post-Execution Audit Addendum (2026-08-11)

Verdict: `POST_EXECUTION_REVIEW_INCOMPLETE`. The execution receipts above remain
valid historical evidence, but they do not yet constitute a clean, callable
closure for Plan 361.

- **No auditable closure commit exists.** `HEAD` was still
  `67eca670b72de69994be7e8bd5ffe4ace3f9d372` when this audit ran, with the
  production, test, script, Graphify, plan and receipt changes unstaged in the
  shared worktree. The review graph fingerprint `b3f410251f97cbbb` describes
  that dirty candidate and MUST NOT be pinned as a committed closure
  fingerprint. **Resolved:** the implementation was committed as
  `6dc052573` while this audit was being written, and the bounded repair below
  is committed on top; see the Repair Closure section for the auditable SHA and
  the committed-tree fingerprint.
- **The setup and QR authority are not production-callable.** The main
  `StartupRouter` does not supply `IdentityChoiceWired.linkedDeviceSetupBuilder`;
  production QR display/scanner/profile composition does not supply the linked
  QR producer/scan callback; and `setUpLinkedSecondaryInstallation`,
  `parseDirectLinkedDeviceQr`, and `dbStageDirectContactDeviceBinding` have no
  production callers. The `runtime_roots.json` explained-root records the same
  test/integration-only reachability. Plan 361 must not silently inherit this
  setup/activation debt.
- **The two Move protections are not on the real journey.** The default export
  authorization does not receive `linkedInstallationAuthority`, and
  `evaluateAccountMigrationImportPrecondition` has no production caller. The
  tests prove injected helpers, not the shipping source/destination decisions.
- **Logical-account and trust requalification still have bypasses.** Production
  bootstrap loads linked authority without the expected current account peer;
  the P2P implementation can pass the transport peer to an account-migration
  side-effect gate; and QR parsing checks `contact.isBlocked` before the DB
  transaction while the stage transaction rechecks only the account key. A
  contact blocked between parse and stage can therefore still acquire a pending
  binding.

Bounded repair contract:

1. Wire the existing default-off linked setup, exact QR display source and
   known-contact scan action through the production composition roots; retain the
   restricted route and do not start messaging/event owners.
2. Inject the linked-installation authority into the real Move export decision
   and invoke the import precondition before destination import, including the
   explicit-erase path.
3. Bind bootstrap authority loading to the current account peer and keep the
   account-migration gate on the logical account while the bridge uses the
   transport peer.
4. Re-read nonblocked contact state and the current account key inside the same
   SQLite transaction that stages the pending binding.
5. Extend only the existing TC-360 owners with causal wiring/TOCTOU cases, run
   focused tests concurrently where supported, then run the affected curated
   `1to1` lane once. Do not repeat `core-host-all`, the Android pair, or any full
   host/device campaign unless the repair actually broadens their production
   boundary.
6. Commit the complete Plan-360 implementation and repair, require a clean tree,
   run one incremental Graphify refresh/review against that commit, and record
   the resulting SHA/fingerprint before Plan 361 revalidation.

## Repair Closure (2026-08-11)

All five bounded-repair items are implemented and proven. Every finding was
real; one of them — the Move guards — is the THIRD instance in this execution of
the same defect class: a guard implemented and proven against an injected helper
while the shipping call site never invoked it. The first two (the transport-peer
barrier, and the role-aware start's dead qualifier) were caught during
execution; this one was caught by review, after it had already been reported as
delivered. Every repair below is therefore asserted together with its WIRING,
not only its behavior.

1. **Setup and QR authority are production-callable.** A new restricted
   `LinkedDeviceSetupWired` route runs exactly the crash-safe setup use case and
   then shows the dedicated dual-signed QR; `StartupRouter` supplies its builder
   (`IdentityChoiceWired` still hides the entry unless the default-off selector
   allows authoring), and `OrbitWired` supplies the known-contact
   `onDirectLinkedDeviceQrScanned` action, which authenticates through the
   existing parser and stages PENDING authority through a new
   `stagePendingBinding` capability method. No messaging, event, group, push or
   retry owner is started.
2. **Both Move protections are on the real journey.** The shipping export
   decision in `account_migration_journey_wired.dart` now receives
   `linkedInstallationAuthority`, and production bootstrap wraps
   `accountMigrationStartReceiver` with the destination precondition — with the
   linked-role check ahead of the explicit-erase escape hatch, because erasing a
   migrated-out account does not retire linked authority.
3. **Logical-account qualification completed.** Bootstrap and the startup router
   load authority with `expectedAccountPeerId`, so a credential bound to a
   different logical account resolves `failClosed` instead of `active`; and
   `P2PServiceImpl` gained a `logicalAccountPeerId` seam so the
   account-migration side-effect gate is asked about the ACCOUNT peer, never the
   per-device transport peer it does not cover.
4. **Blocked-contact TOCTOU closed.** `_currentContactAuthority` reads
   `is_blocked` alongside the account key, and the staging transaction refuses a
   contact blocked between a successful parse and the write. The parser's own
   check cannot protect the write, because authentication and staging are
   separate operations.
5. **Gates.** Focused TC-360 `+18` at concurrency 4; host `1to1` PASS 122/122;
   completeness `1439/1439`; discovery contract PASS; all frozen contracts PASS
   with three digests repinned with adjacent rationale and unchanged assertions
   (production-bootstrap normalized sha, the P2P constructor parameter list, and
   the facade API fingerprint, for the one added optional parameter).
   `core-host-all` and the Android pair were deliberately NOT repeated: the
   repair widened no schema, no test-path registration and no device boundary.
6. **Auditable closure.** The implementation is committed as `6dc052573` and
   this bounded repair as `395accca5`, both descending from the accepted baseline
   `6d3bc6ccd7a26b8a9d8cc94ad3c5eee148cc08d7`. The tree is clean apart from a
   concurrent session's Plan-361 planning doc, deliberately excluded from both
   commits. One incremental Graphify refresh ran against that committed tree:
   71,512 nodes / 104,941 edges, overlay 1,565 files / 15,348 named tests /
   1,207 production targets, committed-tree fingerprint `55f4851041c517b5`. The earlier
   `cd5da0facf62a050` described the pre-repair tree and the audit's
   `b3f410251f97cbbb` described a dirty candidate; NEITHER is a closure
   fingerprint.

## Reviewer Findings

### Lens 1 - Claims and boundaries

- Tightened. The original direct event-fanout premise was not implementable as a loop over `ContactModel.peerId`; account and transport identity are currently one namespace.
- The group multi-device selector and contact-request channel were rejected as false reuse. The reviewed plan has a direct-only flag and protocol-free, explicit QR trust handoff.
- The account Move conflict is explicit: linked secondary is restricted and is neither a second primary nor an import/export endpoint.

### Lens 2 - Test completeness

- Tightened to five causal host bundles plus one registered device acceptance. Crash half-pairs, pre-register peer qualification, dual signatures, peer derivation, stale trust, capacity, contact replacement, initialized-empty safety, and Move isolation close the known bypasses.
- Three representative mutations are sufficient. No private event/blob behavior is fabricated in this foundation.

### Lens 3 - Alternate production paths

- Closed. Contact requests, LAN, retry, wake-token, group admission, and chat/event senders are out of scope. The only producer/consumer is linked setup QR -> known-contact scanner -> real roster repository -> explicit trust profile.
- Ordinary primary startup and legacy contact QR remain preservation paths; linked startup has an explicit logical-account/transport split and restricted route.

### Lens 4 - Gates and evidence

- Lean. One c4 focused proof, one discovery shell, one DTR preflight, completeness, one serial 1:1, one core c4, and one availability-bounded Android pair.
- `feature-host-all`, full `host-all`, broad Go/native/relay, SQLCipher duplicates, iOS, and performance are omitted. Scenario registration prevents a wrong legacy harness branch from false-greening.

### Lens 5 - Operability and reversibility

- Tightened. Local role/secret are non-exported secure authority; remote roster is v112. No FK cascade, implicit eviction, hidden fallback, auto-trust, or silent regeneration exists.
- The DB floor is one-way, but no external activation occurs. Plan 361 must consume the authority before any multi-device delivery claim.

## Arbiter Decision

`POST_EXECUTION_REVIEW_INCOMPLETE.` The architectural split remains sound, and
the recorded execution gates need not be discarded. The post-execution source
audit nevertheless found real production reachability, Move-wiring,
logical-account qualification and transactional trust defects, and there is no
committed candidate SHA. Plan 360 is therefore not audit-closed and cannot yet
serve as Plan 361's accepted baseline.

## Handoff

- Current state: implementation receipts exist in an uncommitted dirty candidate,
  but closure is `POST_EXECUTION_REVIEW_INCOMPLETE` and no accepted SHA exists.
- Next: implement the six bounded repair steps in the addendum, prove only their
  causal rows plus the affected curated lane, commit the whole Plan-360 closure,
  and refresh/review Graphify once against that commit.
- Plan 361 remains blocked. After the repair commit, revalidate its forward and
  reverse device authority, contact-delete transaction and restricted-runtime
  assumptions before replacing its baseline placeholder.
- Plan 362 still owns media/voice/v111 fanout; no activation, GAP-N01 or release
  claim is created by this repair.
