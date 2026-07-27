# 285 - Move Account Cutover-Window Recovery Hardening

Status: Implemented / host-tier closure (2026-07-26)
Type: Bug
Spec: free-text intent (no formal spec) — owner-directed scope, derived from the DTR-09
Move-completeness audit run in-session on 2026-07-26
Classification: implementation-complete — Items **A-0**, **A-1**, **B**, **C**, **D** carry the whole
executable scope. Item **A-2** (the user-asserted abort) is **deferred by owner decision**:
`DECISION-285-01` resolved to option (b) on 2026-07-26. No open decision remains.
Closure tier: host. The headline claim is bounded to host-proven receiver compatibility and
cutover recovery. Device rows are availability-bounded, automated follow-up confidence only;
they are not host-closure gates.
DTR ownership: none. DTR-09, Wave 3, and final rollout status are unchanged.

> **v5 — implementation and evidence closure, 2026-07-26.** Execution counterexamples required
> the replay-safe capability before `complete()` as well as in its response, so complete-response
> transport loss is retryable only after early negotiation. Duplicate completes now join the
> owner's settled result; semantic `cutover_rejected` proof responses receive the same single
> bounded retry as transport loss; pre-verification route revocation survives advertising-stop
> failure; and post-commit cleanup cannot revoke a proof. Full proof identity is table-tested on
> both endpoints, and blocked-authority confirmation performs one bounded fresh decision when the
> authority becomes active. These are necessary counterexample closures within the v3/v4 scope.

> **v4 — execution counterexample closure, 2026-07-26.** The post-GREEN audit made the retained
> route proof-only during finalization/grace, rejects same-session receiver replacement while a
> cutover is retained, validates the returned new-active proof's full session/account/device
> identity, and publishes `completeInFlight` before reading the complete body. It also makes a
> retryable live-service start resumable at per-side-effect checkpoints, keeps the parent-owned
> journey locked until route reset, resets even when projection refresh fails, moves reset
> ownership fully into the retained onboarding route, and suppresses erase when the authority
> re-read is unavailable or fail-closed. These are counterexample closures within A-0/A-1/B/C,
> not new feature scope.

> **v3 — revised 2026-07-26 after the execution-request `/tdd-review`.** The fresh review
> refuted one load-bearing v2 assumption: bundle-level replay safety is unreachable after the
> runtime route is removed. v3 moves proof single-flight/replay ownership to the runtime session,
> retains a bounded committed-proof routing tombstone, capability-gates sender retries for
> mixed-version safety, defers stop while `complete()` is in flight, and makes post-commit cleanup
> incapable of revoking a committed proof. It also extracts a single-flight runtime-startup latch,
> adds a receiver-level iOS → iOS preservation sentinel, makes Item C copy-only because the
> existing erase callback does not clear unfinished-move residue, locks the verified new-phone
> route against identity replacement, corrects rollback claims, and replaces stale/manual
> tool/device instructions with availability-bounded automation.

> **v2 — revised 2026-07-26 after `/tdd-review`** (4-worker audit `wf_c265881f-048`: factual,
> counterexample, boundary/reversibility, domain-bet; verdict `plan-fixes-required`, 12 blockers,
> every linchpin re-verified in source by the lead before acceptance). The review changed the
> plan's shape, not just its wording. Four things v1 got wrong are corrected below and marked
> **[v2]**: (1) v1 named the un-retried old-block-proof POST as root cause A and then never fixed
> it — a bounded retry is now Item A-0 and is the *primary* mitigation; (2) v1 claimed the abort
> was a strict improvement — source shows the dominant interrupt is the one where the new phone
> **has** committed, so a wrong abort causes silent permanent message loss; (3) v1 declared the
> runtime re-arm host-unobservable — it is injected and testable; (4) v1's Rollback justification
> for Item D was factually wrong (the mirrors do **not** regenerate on Android) even though its
> conclusion holds for a different, verified reason.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-26 | Evidence Collector | DTR-09 roadmap, full `lib/features/account_migration/**` | DTR-09's manifest islands carry zero payload; the real defects are in the cutover window | Scope the owner's four items |
| 2026-07-26 | Evidence Collector (26-agent verify→refute `wf_187364b4-662`) | coordinator, runtime, bundle transfer, blocked screen, staging, `main.dart`, `startup_router.dart` | 7 gaps survived adversarial verification, 13 refuted | Ground the fix seams |
| 2026-07-26 | Planner (8-agent ground→refute `wf_4d4e566f-90c`) | as above plus `startup_decision.dart`, checkpoint store, `journey_wired.dart`, gate scripts | Item B seam refuted as zero-delta; Item A seam moved off `decideStartupRoute`; Item D reduced to one predicate | Emit v1 |
| 2026-07-26 | Reviewer (`/tdd-review`, 4-worker `wf_c265881f-048` + lead source verification) | `main.dart:4788-4816/:4994-5000/:6048-6070`, `bundle_transfer.dart:1676-1706/:1915-1945/:2117-2132`, `identity_repository_impl.dart:213-225`, `group_repository_impl.dart:2038-2050`, staging test | 12 blockers; abort is unsafe without A-0; re-arm is deterministic and host-testable; Item D's stated reason refuted | Emit v2 (this revision) |

## Problem And Evidence

- Behavior to improve: a Move Account transfer interrupted **after** the old phone writes its
  cutover block currently strands one or both phones, and the only affordance offered is
  irreversible account destruction. Separately, the host receiver rejects an iOS-sourced bundle
  on destinations without an iOS shared access-group store; real iOS → Android completion remains
  a separate availability-bounded device confidence claim.
- Impact: the old phone goes silently offline the instant the block is written; the new phone can
  hold a fully-transferred account it can never promote; the sole escape deletes
  `db_encryption_key`, `identity_private_key`, `identity_mnemonic12`, and
  `identity_ml_kem_secret_key`. Identity is recoverable from the 12-word phrase; message history,
  contacts, and media rows are not.

### Confirmed root causes (each survived two adversarial passes)

- **A. The old-block-proof POST is issued exactly once, and the block is written first.**
  `markOldNetworkBlocked` persists `migrationCutoverPendingBlocked` at
  `migration_cutover_coordinator.dart:126-131` **before** the POST at
  `account_migration_local_transfer_runtime.dart:943` → `:966-981`. `on _MigrationPostException`
  at `:982-987` returns `localTransferTimedOut` immediately — no retry, no authority revert.
  `restoreActiveAfterExportInterrupted` returns false for every state except
  `migrationExportingNetworkPaused` (`coordinator:94-100`), and `markExportingNetworkPaused`
  throws `StateError` from the blocked state (`coordinator:65-75`), so the journey screen's
  "try again" is structurally incapable of succeeding. `MigrationCutoverCoordinator.recover()`
  (`:445-475`) has **zero production callers**.
  **[v2] The single POST is the actual defect.** At the moment it fails, the new phone's
  `_receiverSessions[sessionId]` (`runtime:200`, written `:281`) is still populated and the
  `wsServer` started at `:277` is still listening — `stopNewPhoneReceiver` (`:309-318`) never
  stops the server. A bounded retry is therefore reachable in-session and eliminates most of the
  interrupted population. **[v3]** The retry is safe only when the receiver advertises the
  additive `old_block_proof_replay_safe` capability in the transcript and `complete` responses.
  Without that
  capability (new sender → prior receiver), the sender performs exactly one proof POST.
- **B. The new phone's verified import is process-local.** `_sessions` is an in-memory map
  (`account_migration_bundle_transfer.dart:1008`); `verifiedImport` is set at `:1608`;
  `acceptOldBlockProof` returns null without it (`:1644-1651`); `importVerifiedStagedDatabase` +
  secure promotion run **only** inside `acceptOldBlockProof` (`:1665-1673`). Beyond process
  death this is user-triggerable: `_handleClose` and `dispose()` both call `_stopActiveReceiver()`
  unconditionally (`account_migration_journey_wired.dart:602, :624, :634-637`).
- **C. The blocked screen is unparameterized.** It takes only `onEraseAccount` (`:6`), renders one
  hardcoded title (`:98`) and one action (`:119-137`), at exactly one construction site
  (`startup_router.dart:386-390`), for **every** blocking authority state.
  `allowsNormalStartup` = `{noAccount, active, migrationFailedActiveRestored}`
  (`account_migration_authority_state.dart:28-35`), so both `migrationCutoverPendingBlocked`
  (old phone) and `migrationVerifiedWaitingForCutover` (new phone — 3 production writers:
  `bundle_transfer.dart:1620`, `coordinator:181`, `coordinator:241`) land there. The new phone,
  holding the only verified import, is shown `app_en.arb:1736-1737`: *"Account moved to another
  phone… Erase the local copy only when you are sure the new phone works."* — factually inverted.
- **D. Shared-scope staging has no availability guard.** The export side already skips
  `iosSharedAccessGroup` entries when `sharedStore == null`
  (`account_migration_bundle_transfer.dart:336-339` — **[v2]** v1 cited `:335-338`, off by one);
  the staging side does not. `complete()` stages every metadata entry with no scope filter
  (`:1562-1571`), `MigrationSecureStorageStaging._storeFor` throws `StateError` (`:185-196`,
  throw at `:191-193`), and the whole body is `on Object catch → return false` (`:1626-1629`),
  which the runtime maps to `reason: 'bundle_verification_failed'` (`runtime:1903-1912`).
  `sharedPushKeyStore` is null on Android **and** on iOS under the SIMS group-media disposable
  profile (`main.dart:537-540`, profile flag `:367-370`).

### **[v2/v3]** Root cause E — a post-self-heal dead runtime is deterministic, not a race

`startLiveServices` returns at the network-gate check **before** setting `liveServicesStarted`:

```
if (!await allowsAccountRuntimeNetworkSideEffects('live_services_start')) { return; }   // main.dart:4808-4810
liveServicesStarted = true;                                                             // main.dart:4811
```

`_ensureRuntimeServicesReady` then caches the completed future unconditionally
(`main.dart:6050-6068`, `_runtimeServicesReady = startup`), and `deferredRuntimeStartup:
startLiveServices` is injected at `main.dart:4998`. Because the blocked screen is reachable
**only** from the cold-start route (`startup_router.dart:342` → `decideStartupRoute` `:355` →
`case accountMigrationBlocked` `:380-390`) with an already-persisted blocking authority, the gate
read *cannot* precede the block — the early return is **deterministic**. Any device unblocked
in-session therefore comes up with `bridge.initialize()`, `notificationService.initialize()`,
every listener and every retrier un-run until the next cold start. v1 called this an ordering
race and closed it on an owner-manual row; both halves were wrong.

### Existing coverage

- `migration_cutover_coordinator_test.dart` — 20 tests including 7 direct `recover()` cases
  (`:169-212, :573-613, :664`). Decision logic is well covered; nothing calls it and no exit
  transition exists.
- `startup_decision_test.dart:250-284` — asserts `migrationCutoverPendingBlocked →
  accountMigrationBlocked` in a state loop. Already one of the five hardcoded `move-feature`
  paths (`run_host_test_gates.sh:414-419`).
- `account_migration_blocked_screen_test.dart` — 2 widget tests (`:13`, `:52`).
- `migration_secure_storage_staging_test.dart` — **[v2] 3 tests, not 4**: `:23` *stages values
  under session-scoped non-active keys*, `:69` *promotion refuses missing critical staged keys
  before active writes*, `:88` *promotion writes active keys deterministically and can roll them
  back*. **Every one supplies a non-null `sharedStore`** (`:16-19`).
- `account_migration_bundle_transfer_test.dart:1425-1433` — pins `complete()`'s five-stage
  telemetry contract.
- `startup_router_recovery_test.dart:150-192` — already pumps `StartupRouter` with a
  `saveAuthority` helper; this is the seam the new router-tier rows reuse.

### Missing coverage

- No test constructs `MigrationSecureStorageStaging` with `sharedStore: null`.
- `migrationVerifiedWaitingForCutover` is absent from `startup_decision_test.dart:255-260`'s
  blocked-state loop **and** from `startup_router_recovery_test.dart`.
- No test asserts any transition out of `migrationCutoverPendingBlocked` (none exists), any retry
  of the old-block-proof POST, or replay-safety of `acceptOldBlockProof`.

### Refuted findings (do NOT re-introduce)

- **Receiver-side disk rehydration of `_sessions` is zero-delta.** The receiver is constructed
  inline inside the runtime constructor (`main.dart:2994` → `:3014-3027`), so both session maps
  share one lifetime. `_sessions` has exactly one write (`:1109`) and **no removal anywhere**;
  `_ReceiverSession.manifest` has one write (`runtime:1564`) reached only when `acceptManifest`
  returned true. Across a restart the POST 404s `unknown_session` (`runtime:367-376`) before the
  receiver is consulted.
- **Wiring `recover()` into `decideStartupRoute` unblocks nothing.** For the blocked state
  `recover()` is a constant `waitForOldBlockProof` (traced `coordinator:448/452/457/461/470-471`),
  and none of its six decisions restores active authority.
- **`migrationImportStaging` is not a live blocked state** — no production writer
  (`rg -n 'migrationImportStaging' lib` → enum decl `:6` and the `isImportStaging` getter `:40`
  only). Author no copy for it; keep a defensive default arm.
- **Group state and queued background work transfer correctly** (DTR-09 audit) — the DB snapshot
  is a dynamic `sqlite_master` enumeration (`migration_database_schema_inventory.dart:23`) and
  group key material is staged by the wired `MigrationSecureStorageReferenceCollector` (`:6-58`).
- **[v2] "The dropped shared-scope mirrors regenerate on the Android destination" is REFUTED.**
  `_mirrorMlKemSecretForPush` early-returns on a null store
  (`identity_repository_impl.dart:215-219`) and `_mirrorGroupKeyForPush` does the same
  (`group_repository_impl.dart:2040-2047`). On Android **nothing regenerates**. Item D is still
  sound, for a different verified reason — see the corrected Rollback section.

### Unresolved findings

- **`UNRESOLVED-285-01` [v2, materially revised] — a wrong abort is the LIKELY case, not the edge
  case, and its consequence is silent permanent loss.** The old-block-proof POST carries
  `budgetScaleBytes: manifest.importValidationBytes` (`runtime:973-981`) capped at
  `maxCommandTimeout` = 120 s (`runtime:2081-2089`, `:245`), and the receiver runs the **entire**
  active-DB import plus secure promotion inside that budget (`bundle_transfer.dart:1665-1673`)
  before `commitNewActive` writes authority `active` (`coordinator:263-268`) and before the
  HTTP 200 is flushed (`runtime:2028-2031`). So the dominant interrupt is a budget timeout in
  which the new phone **has** committed and already promoted `identity_private_key` /
  `db_encryption_key` into its live store. In that limb today, exactly **one** device is blocked
  and the account works. A wrong abort converts that into two devices sharing one identity —
  `accountPeerId == deviceId == transportPeerId == identity.peerId`
  (`identity_repository_impl.dart:88-90, :163-166`) — both draining and ACK-deleting one relay
  inbox, with the rescued phone re-registering an FCM token for the same peer id
  (`register_push_token_use_case.dart:63-77`) and stealing push delivery. That loss is silent,
  permanent, and invisible to both parties. **v1's claim that "today's behavior is strictly worse
  (both devices bricked)" is false for this limb and has been removed.**
- **`UNRESOLVED-285-02` [v2, downgraded to a specified edit]** — the post-abort dead runtime is
  root cause E above. It is deterministic and host-observable, so it is no longer "unresolved":
  it is Item A-1 with host row TC-16a. What remains genuinely device-only is end-to-end message
  flow after an abort (TC-16).

### Affected production / test / gate files

Production: `account_migration_local_transfer_runtime.dart`, `account_migration_bundle_transfer.dart`,
`migration_secure_storage_staging.dart`, `account_migration_runtime_network_gate.dart`,
`account_migration_blocked_screen.dart`, `account_migration_journey_wired.dart`,
`startup_router.dart`, **`lib/main.dart` [v2 — omitted from v1's list while an implementation step
required editing it]**, `lib/l10n/app_{en,ar,de}.arb` + regenerated `app_localizations*.dart`.
**Not** `migration_cutover_coordinator.dart` — that file belongs to the deferred Item A-2 and must
stay untouched (`DECISION-285-01` option (b)).
Test: `account_migration_local_transfer_runtime_test.dart`, `account_migration_bundle_transfer_test.dart`,
`migration_cutover_coordinator_test.dart`, `migration_secure_storage_staging_test.dart`,
`account_migration_runtime_network_gate_test.dart`, `account_migration_blocked_screen_test.dart`,
`account_migration_journey_screen_test.dart`, `startup_router_recovery_test.dart`,
`test/core/lifecycle/main_deferred_startup_wiring_test.dart`,
`test/l10n/l10n_integrity_test.dart`.
Gate: `scripts/run_host_test_gates.sh:414-419` (one added path).

## Graph Grounding Snapshot
- Graph fingerprint / freshness: `d3c748f7a3cdec3b`; **fresh at Plan-285 closure** —
  `./graphify-arch/refresh_arch_graph.sh --incremental` completed with 62,511 nodes, 94,148 edges,
  and a deterministic overlay covering 1,450 files / 14,192 named tests / 1,087 production
  targets; `graphify-arch/.needs_incremental_refresh` is absent.
- Query / profile: planning
  `python3 graphify-arch/tdd_context.py query "account migration cutover coordinator recover startup decision blocked screen secure storage staging shared scope" --profile tdd --budget 700`;
  review counterexample pass
  `… query "abortInterruptedCutover MigrationCutoverCoordinator AccountMigrationBlockedScreen stopNewPhoneReceiver supportsScope counterexample callers" --profile review --budget 800`
  (`confidence=anchored`); execution impact:
  `python3 graphify-arch/tdd_context.py affected <eight changed production files> --budget 600`.
- Anchors: `stopNewPhoneReceiver` → `account_migration_local_transfer_runtime.dart:309`;
  `AccountMigrationBlockedScreen` → `account_migration_blocked_screen.dart:5`;
  `MigrationCutoverCoordinator` → `migration_cutover_coordinator.dart:33`.
- Surfaced proof/gate files: `migration_secure_storage_staging_test.dart:23`, `:69`
  (`AUTO_FEATURE_HOST`, proof traits `crypto`).
- Graph gaps that required raw source search: the `main.dart` composition root and the
  `_ensureRuntimeServicesReady` cache, `journey_wired.dart` teardown, the receiver session
  lifecycle, and the whole gate topology in `run_host_test_gates.sh` — all established by direct
  source reads and grep.
- Reuse rule: anchors are search starting points for review/execution; every conclusion above
  carries its own current-source evidence.

## Scope Contract And Guard

**In scope, in dependency order:**

- **Item A-0 [v3 — primary fix].** The HTTP-routing session, not the private bundle session, owns
  the cutover lifecycle. Extend runtime `_ReceiverSession` with an explicit phase,
  `stopRequested`, one in-flight proof future, one stored committed proof, one activation-emitted
  latch, and a replay-expiry timer. Valid duplicate proofs join the same future; a committed proof
  is replayed without re-import or a second activation. The transcript advertises additive boolean
  capability `old_block_proof_replay_safe`, and `complete()` repeats it. Only that early
  negotiation permits a second `complete` transport attempt; only the completed response permits
  exactly two proof attempts with one injected 250 ms backoff. Prior receivers receive one
  `complete` attempt and one proof attempt. Keep the runtime route for a default five-minute
  committed-proof grace window while
  stopping advertising immediately; expire to 404 afterwards. In the bundle receiver, once
  `commitNewActive` returns a valid committed proof, cleanup failure is telemetry/residue, never a
  `null` cutover result. **[v4]** Retained phases command-gate the route: proof-in-flight and
  committed sessions are proof-only, with no transcript/manifest/segment/chunk/status mutation
  reaching the bundle receiver. Reject same-session receiver replacement while finalization or
  grace is retained. Publish `completeInFlight` before awaiting the request body, and validate the
  returned proof's session, account, new-phone role, and expected ephemeral device id on both
  receiver and sender. No manifest/blob/schema version changes.
- **Item A-1 [v3].** Preserve startup single-flight while allowing a gated no-start to retry.
  Extract `AccountMigrationRuntimeStartupLatch`: publish the in-flight future synchronously,
  clear it on `false` or error, and retain it only after completed success. Keep the existing
  `Future<void> startLiveServices()` signature for source sentinels; add a boolean outcome wrapper
  and inject that wrapper into `MyApp`. **[v4]** Route each fallible one-time initializer,
  listener/retrier start, and forwarding-subscription install through a persistent completed-step
  ledger so a late error resumes without replaying prior side effects. This fixes export-pause
  self-heal without a new `StartupRouter` parameter.
- **Item B [v3].** Treat `completeInFlight`, `verifiedWaiting`, `proofInFlight`, and
  `committedReplayable` as retained runtime phases. A stop during `complete()` records
  `stopRequested`; successful completion keeps the proof route, failed completion honors the
  deferred stop and removes it. On the new-phone UI, `importingBundle` / `importVerified` makes
  the journey non-poppable (close button and system back) through parent-owned activation and
  route reset (or process restart), so the user cannot generate/restore an identity while a late
  proof can replace the active DB.
  Add an activation listener on the onboarding-route owner above the journey widget; it survives
  journey disposal, invokes stop (which starts/keeps the replay grace), runs cache/projection
  refresh, and resets the route exactly once. **[v4]** The retained owner captures the restart
  router and refresh dependency before the prior `StartupRouter` is replaced; refresh failure is
  telemetry, not permission to strand or unlock onboarding. The journey keeps its progress
  subscription.
- **Item C.** Pass the loaded `AccountMigrationAuthorityRecord?` to `AccountMigrationBlockedScreen`
  and branch title/message on it (`isFailClosed` **first**), with today's strings as the default
  arm. **[v3]** For `migrationVerifiedWaitingForCutover`, render accurate new-phone copy but no
  erase action. The existing callback clears active registry keys and authority only
  (`startup_router.dart:856-867`); it does not clear staged values/directories, bundle session,
  pairing/cutover residue, or the promotion journal, so relabelling it "clear unfinished copy"
  would be false and unsafe. **[v4]** A null/unreadable or fail-closed re-read also suppresses
  erase; positively loaded non-waiting states retain existing default/migrated-out behavior.
  The hardcoded button label is replaced by the existing localized key.
- **Item D.** An availability-conditional shared-scope filter applied **once** in the receiver.
**Out of scope by owner decision — Item A-2 (the user-asserted abort).** `DECISION-285-01`
resolved to option (b) on 2026-07-26: ship A-0/A-1/B/C/D and leave the residual blocked state
as-is. Rationale of record: with A-0's retry landing first, the population that still reaches the
blocked state is small, and for that remainder the old phone cannot distinguish "never committed"
from "response lost" — and per `UNRESOLVED-285-01` the *likely* interrupt is the one where the new
phone **did** commit, where a wrong abort causes silent permanent message loss. Taking zero
split-brain risk is preferred over rescuing the remainder. The designed-but-unbuilt abort and its
contract rows are preserved below under `DEFER-285-03` for a future plan.

**Must preserve:**
- iOS → iOS receiver completion still promotes
  `iosSharedAccessGroup:identity_ml_kem_secret_key` and emits no drop event → TC-03; the existing
  direct staging promotion/rollback sentinel remains TC-03a.
- `_storeFor`'s `StateError` remains a loud tripwire for future callers → TC-04.
- `complete()`'s five-stage telemetry contract (`bundle_transfer_test.dart:1425-1433`) stays
  byte-identical → TC-05.
- `migratedOut` copy and the erase confirmation flow are unchanged → TC-10.
- A completed cutover stops advertising immediately, remains replay-routable only for the bounded
  grace window, then tears the runtime route down → TC-18b.
- `decideStartupRoute`'s four-value `StartupDecision` return type → TC-11b.

**Hard `Do not`:**
- Do **not** wire, modify, or delete the DTR-09 group / pending-work manifest islands
  (`DTR09-AUTH-01`); the audit established they carry zero payload.
- Do **not** add receiver-side disk rehydration of `_sessions`, and do **not** inject a cutover
  repository or a `recover()` closure into `decideStartupRoute` (both refuted).
- Do **not** author blocked-screen copy for `migrationImportStaging` (no production writer) or
  `migrationExportingNetworkPaused` (self-healed at `startup_decision.dart:43-62` before the block
  check).
- Do **not** edit `MigrationSecureStorageCleanup._storeFor` — its throw is **unreachable in
  production on every platform**, because `startup_router.dart:857-859` passes
  `sharedStore: widget.secureKeyStore` (non-null always). See `DEFER-285-02`.
- Do **not** implement Item A-2 in this plan. `DECISION-285-01` is resolved to option (b); adding
  `abortInterruptedCutover`, the reactivate affordance, or the cutover `failureCode` write here is
  scope drift. `migration_cutover_coordinator.dart` is **not** edited by this plan.
- Do **not** change the QR, manifest, metadata blob `version`, entry-kind set, or any DB schema.
  The sole wire delta is the additive, backward-compatible response capability
  `old_block_proof_replay_safe`, advertised in transcript and `complete`; old senders ignore it
  and new senders do not retry when absent.

**Deferred / accepted difference:**
- `DEFER-285-01` — durable process-restart resume of a verified import. Correct design is to
  replay the persisted `newActiveCommitted` cutover record rather than re-import. Owner: a
  follow-up plan. The refuted receiver-rehydration seam must not be substituted for it.
- `DEFER-285-02` — `eraseAccount` shared-scope and residue gaps (pre-existing G1 from
  `03-relay-free-move-gap-audit.md`): on iOS, erase deletes `identity_ml_kem_secret_key` from the
  *primary* store under `iosSharedAccessGroup` scope and never touches the real access group
  (`startup_router.dart:857-864`); `account_migration_cutover:v1` is absent from
  `MigrationSecureStorageRegistry._fixedKeys`; staging-prefixed values and the staging directory
  survive erase. Owner: a follow-up plan. **[v3]** Item C does not misrepresent this incomplete
  cleanup as a new-phone recovery action, and Item B prevents interactive identity replacement
  during verified finalization.
- **`DECISION-285-01` — RESOLVED 2026-07-26, option (b).** The owner elected to ship
  A-0/A-1/B/C/D and leave the residual blocked state as-is, taking zero split-brain risk. Recorded
  in full under "Out of scope by owner decision" above. No open decision remains in this plan.
- `DEFER-285-03` — the user-asserted abort (Item A-2), designed and contract-drafted here but not
  built. Owner: a future plan, to be reopened only if field evidence shows the post-A-0 residual
  population is material. Any such plan must first resolve `UNRESOLVED-285-01` — ideally by making
  the commit state *observable* (a durable, authority-backed answer on the existing `status`
  command at `account_migration_local_transfer_runtime.dart:32`) rather than by asking the user to
  assert it.

**Dependencies:** A-0 → B (shares the retained runtime phases). A-1, C, and D are independent of everything
else and of each other.

## Test Contract

Zero empty cells. `HEAD state` is one of `causal RED` · `GREEN sentinel` · optional
availability-bounded device confidence.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD state → GREEN | Mutation that re-reds | Gate / registration |
|---|---|---|---|---|---|---|
| TC-01 | An iOS-sourced bundle completes on a destination with no shared access-group store | `test/features/account_migration/application/account_migration_bundle_transfer_test.dart::complete accepts an iOS-sourced bundle on a destination without a shared access-group store` | unit/application host; fakes; receiver built with `MigrationSecureStorageStaging(sharedStore: null)` | causal RED (`complete()` returns **false**; `…COMPLETE_FAILED` carries `stage: 'secureStaging'`) → returns true; exactly one `…SHARED_SCOPE_ENTRIES_DROPPED` carries the session id, `scope: iosSharedAccessGroup`, and exact seeded `droppedCount`; `…COMPLETE_FAILED` absent | revert the `stageableEntries` filter → TC-01 red | `flutter test test/features/account_migration/application/account_migration_bundle_transfer_test.dart`; AUTO (glob) |
| TC-02 | The staging class reports scope availability instead of only throwing | `test/features/account_migration/application/migration_secure_storage_staging_test.dart::supportsScope is false only for iosSharedAccessGroup when sharedStore is null` | unit host; `RecordingSecureKeyStore` + a second instance with `sharedStore: null` | causal RED (compile-RED — `supportsScope` does not exist; the missing symbol *is* the contract) → true for primary always, false for shared scope only when `sharedStore == null` | make `supportsScope` return `true` unconditionally → TC-02 red | `flutter test test/features/account_migration/application/migration_secure_storage_staging_test.dart`; AUTO (glob) |
| TC-03 | iOS → iOS receiver completion still carries the shared ML-KEM mirror | `account_migration_bundle_transfer_test.dart::complete and cutover preserve shared mirrors when the destination supports shared scope` | unit/application host; non-null source and destination shared stores | **GREEN sentinel added on HEAD** → shared ML-KEM mirror is promoted, seeded shared group mirror is preserved, and no `…SHARED_SCOPE_ENTRIES_DROPPED` event is emitted | make the receiver filter scope-unconditional → TC-03 red | same command as TC-01; AUTO (glob) |
| TC-03a | Raw shared-store promotion/rollback remains intact | `migration_secure_storage_staging_test.dart::promotion writes active keys deterministically and can roll them back` (existing, `:88-140`) | unit host; non-null `sharedStore` | **GREEN sentinel** → still passes | route shared scope into primary or remove rollback deletion → TC-03a red | same command as TC-02; AUTO (glob) |
| TC-04 | The raw `_storeFor` throw survives as a tripwire | `migration_secure_storage_staging_test.dart::stageValue still throws when a shared-scope key reaches an unavailable store directly` | unit host; `sharedStore: null`, direct `stageValue` bypassing the receiver filter | **GREEN sentinel** (the throw exists on HEAD) → still throws `StateError` | replace the throw with a silent primary-store fallback → TC-04 red | same command as TC-02; AUTO (glob) |
| TC-05 | One exact primary projection feeds staging, promotion, and cleanup on a shared-scope-less destination, and post-commit cleanup cannot revoke proof | `account_migration_bundle_transfer_test.dart::cutover promotes and cleans exactly the primary projection without shared-scope residue`; `::post-commit secure-staging cleanup failure preserves the committed proof` | unit/application host; recording staging/store fakes; includes critical, optional, and dynamic group primary entries; throwing cleanup fake | causal RED (HEAD fails during complete) → recorded stage/promote/delete inputs equal the positive sorted primary projection; every seeded primary staging key is absent after proof; no shared-scope access occurs; injected cleanup failure still returns the committed proof | leave promotion unfiltered → cutover returns null at shared-store read; leave cleanup unfiltered → primary staging residue assertion reds; return null after committed cleanup failure → committed-proof assertion reds | same command as TC-01; AUTO (glob) |
| TC-06 | A new phone stranded before cutover sees new-phone copy | `test/features/account_migration/presentation/account_migration_blocked_screen_test.dart::shows unfinished-move copy for migrationVerifiedWaitingForCutover` | widget; key `account-migration-blocked-title` | causal RED (compile-RED — no record param; then the copy assertion) → renders the new-phone title/message | revert the `switch` on `record.state` → TC-06 red | `flutter test test/features/account_migration/presentation/account_migration_blocked_screen_test.dart`; AUTO (glob) |
| TC-06b **[v3]** | The new-phone waiting arm does not offer the incomplete generic erase callback as “clear unfinished copy” | `account_migration_blocked_screen_test.dart::new-phone waiting arm hides the erase action` | widget; explicit waiting record plus erase spy | causal RED (HEAD renders the action for every state) → keyed erase action absent and spy remains zero | render the generic erase action for the waiting state → TC-06b red | same command as TC-06; AUTO (glob) |
| TC-07 | The router actually supplies the record | `test/features/identity/presentation/screens/startup_router_recovery_test.dart::blocked route passes the loaded authority record to the blocked screen` | widget/router; fake secure key store seeded with `migrationVerifiedWaitingForCutover` | causal RED (HEAD constructs the screen with `onEraseAccount` only) → new-phone title rendered from a real routing pass | drop the `record:` argument at `startup_router.dart:387` → TC-07 red | `flutter test test/features/identity/presentation/screens/startup_router_recovery_test.dart`; **MANUAL — add this path to the `move-feature` printf list at `scripts/run_host_test_gates.sh:414-419` (grep-verify)** |
| TC-08 | Fail-closed and normal-start records never authorize erase | `account_migration_blocked_screen_test.dart::fail-closed record falls back to default copy`; `::normal-start authority never exposes account erasure` | widget; fail-closed plus `noAccount`, `active`, and `migrationFailedActiveRestored` records | causal RED (branching on `state` alone renders import-failed copy — `failClosed()` synthesizes `migrationFailedCleanupRequired` identically to `coordinator:215-220`) → default copy and no erase action for fail-closed; no erase action for every normal-start authority | branch on `state` before `isFailClosed`, or offer erase without a positive blocked record → TC-08 red | same command as TC-06; AUTO (glob) |
| TC-09 | Blocked-authority confirmation fails closed on read error and safely re-decides once if authority became active | `startup_router_recovery_test.dart::authority re-read failure still renders the blocked screen`; `::authority becoming active during blocked confirmation reroutes safely` | widget/router; key-scoped fake throws exactly on the second authority-key read; second fake changes waiting → active on confirmation | causal RED (HEAD performs one authority read) → read failure renders default blocked copy with no erase; waiting → active triggers one bounded fresh startup decision and reaches Feed | remove the local re-read catch, pass erase eligibility through the null arm, or render the stale block after active confirmation → TC-09 red | same command as TC-07; **MANUAL (same path)** |
| TC-10 | Existing `migratedOut` copy and erase confirmation flow are untouched | `account_migration_blocked_screen_test.dart::migratedOut blocks normal account UI and requires confirmation to erase` | widget; explicit `migratedOut` record | **GREEN sentinel after fixture correction** → default copy and one confirmed erase callback | make explicit `migratedOut` render waiting-state copy or hide its erase action → TC-10 red | same command as TC-06; AUTO (glob) |
| TC-11 | New strings exist in en/ar/de with matching placeholders | `test/l10n/l10n_integrity_test.dart` (existing suite) | host; ARB parity + hardcoded-literal scan | **GREEN sentinel** → still passes with the new keys in all three ARBs | omit the `ar` key, or add copy as a bare `Text('…')` in `lib/features/**` → TC-11 red | **`flutter test test/l10n/l10n_integrity_test.dart`** — `test/l10n` is host-all-only, outside both feature and core globs, so this direct command is mandatory; no registration edit |
| TC-11b | `decideStartupRoute`'s contract is unchanged | `test/features/identity/application/startup_decision_test.dart::non-active migration authority blocks normal startup before contacts` (existing, `:250-284`) | unit host; fakes | **GREEN sentinel** → still passes | change `decideStartupRoute`'s signature or return type → TC-11b red | `./scripts/run_test_gates.sh move-feature` (already a hardcoded path); no registration edit |
| TC-16 **[v3, optional device confidence]** | A phone that self-heals from an interrupted export handles messages in the same session | Availability-bounded automated two-peer harness: physical Android `21071FDF600CSC` + Android emulator `emulator-5554`, both re-resolved/pinned at execution; harness drives interruption, relaunch, send, receive, and assertions with no manual taps | device confidence, not host closure | if both targets are available, messages send/arrive without a second restart; otherwise `N/A (target unavailable by project policy)` | N/A — device row; host causal owner is TC-16a | Separate optional device run |
| TC-16b **[v3, optional iOS-specific confidence]** | iOS → Android Move completes across real platform stores | Availability-bounded automated iOS-specific leg using a discovered pinned iOS target plus physical Android `21071FDF600CSC`; no manual taps | device confidence, not host closure; host claim is receiver compatibility only | when targets/harness are available, feed, contacts, messages, groups, and group decrypt succeed; otherwise N/A by policy | N/A — device row; host owners TC-01/03/05 | Separate optional device run |
| TC-16a **[v3/v4]** | Concurrent readiness callers coalesce, false/error clears the latch, and late failure resumes without replaying completed side effects | `account_migration_runtime_network_gate_test.dart::runtime startup latch coalesces in flight then retries after a no-start`; `::runtime startup steps resume after failure without replaying completed work`; plus `main_deferred_startup_wiring_test.dart::migration-gated deferred startup uses retryable outcome latch` | unit host; blocked completer, false/error then true outcomes, three-step partial failure; source wiring sentinel | causal RED (no latch; MyApp caches false forever) → concurrent callers invoke once, false/error clears, completed step A is not replayed after B fails, and successful result stays cached | cache false/error, publish only after true, or start listeners outside the step ledger → exact call counts red | account-migration unit command + exact core wiring command; account-migration AUTO |
| TC-17 | Stop during receiver `complete()` cannot delete a successful proof route, but failed owner/duplicate completion removes it consistently | `account_migration_local_transfer_runtime_test.dart::stop during complete defers removal and a successful complete remains cutover-routable`; `::stop while complete body is still arriving preserves the proof route`; `::stop during in-flight complete settling {false,error} removes the route`; `::duplicate complete joins an owner settling {false,error} even when its body finishes later` | real LocalWsServer; pausable receiver, streaming request body, false/throw completion table | causal RED (HEAD removes runtime session while complete awaits) → `completeInFlight` is published before body read; successful completion remains routable; a stopped failed owner removes the route; delayed duplicates receive the owner's failure and do not call `complete()` twice | publish the phase after body drain, let a duplicate infer success from its body, or omit failed-settlement cleanup → exact status/call-count/404 assertions red | runtime test file; AUTO |
| TC-17a | A verified/finalizing new-phone route cannot return to identity generation or restore before route reset | `account_migration_journey_screen_test.dart::verified new-phone finalization disables close and system back`; `startup_router_recovery_test.dart::committed activation stays locked until the startup route reset finishes` | widget/router; importing/importVerified/activated events plus blocked refresh completer | causal RED (close/back always enabled; first implementation unlocked on activation) → route remains mounted and identity-choice actions stay unreachable through refresh/reset | unlock on activation, re-enable close, or omit PopScope → TC-17a red | journey/router test files; AUTO + registered router path |
| TC-18 | Ordinary pre-verification teardown removes routing even when advertising cleanup throws | `account_migration_local_transfer_runtime_test.dart::stopNewPhoneReceiver rejects a later proof for a pre-verification session`; `::pre-verification stop revokes the route when advertising cleanup throws` | real route/fakes; throwing discovery cleanup | **GREEN sentinel plus causal closure** → later proof/transcript is 404 `unknown_session`; the cleanup error may propagate only after route revocation | retain every session unconditionally or remove the route after awaited advertising cleanup → TC-18 red | runtime test file; AUTO |
| TC-18b | A committed proof is replayable only through a proof-only bounded grace window | `account_migration_local_transfer_runtime_test.dart::committed proof stops advertising, replays during grace, then expires to unknown_session`; `::committed proof tombstone rejects manifest mutation without reaching receiver`; `::same-session restart during committed grace preserves replay proof` | real LocalWsServer; short injected grace; recording receiver | causal RED (HEAD removes immediately; first implementation retained a full mutable route) → identical proof replays once, manifest mutation conflicts without receiver access, same-session restart cannot replace it, and expiry becomes 404 | allow non-proof commands, replace retained session, remove immediately, or never expire → assertions red | runtime test file; AUTO |
| TC-19 | Capability-enabled response loss retries safely through the real runtime route | `account_migration_local_transfer_runtime_test.dart::response-lost committed proof retries once without duplicate import or activation` | two runtimes + real LocalWsServer; first proof response times out; 1 ms injected backoff | causal RED (one POST and immediate route removal) → success, exactly two sender attempts, one receiver cutover invocation, one activation | remove retry, single-flight, capability, or grace → result/count assertions red | runtime test file; AUTO |
| TC-19b | Proof retry is exactly bounded, mixed-version safe, and covers transport plus semantic receiver rejection | `account_migration_local_transfer_runtime_test.dart::old-block retry exhausts at two attempts and is disabled without receiver capability`; `::replay-safe proof retries one {null,error} receiver rejection without stranding cutover` | command-targeted failing client/receiver; recording delay; null/throw receiver table producing HTTP 400 `cutover_rejected` | causal RED → capability true yields exactly two attempts + one 250 ms requested delay for transport or semantic rejection; capability absent yields exactly one attempt; successful retry emits one activation | tight/infinite retry, retry against old receiver, or treating `cutover_rejected` as terminal → exact counts/results red | runtime test file; AUTO |
| TC-19c | Complete-response transport loss is retryable only after early replay-safe negotiation | `account_migration_local_transfer_runtime_test.dart::complete response loss retries once after early replay-safe negotiation`; `::complete transport loss is not retried without early replay capability` | two runtimes + real LocalWsServer; first complete response times out; prior-receiver handler omits transcript capability | causal RED → early capability yields exactly two complete POSTs but one receiver `complete()` settlement; absent capability yields exactly one complete POST and timeout | advertise capability only after complete, retry all receivers, or re-run receiver completion for a duplicate → attempt/call-count assertions red | runtime test file; AUTO |
| TC-20 | Concurrent valid duplicate proofs join one identity-bound destructive cutover | `account_migration_local_transfer_runtime_test.dart::concurrent old-block proofs single-flight one receiver cutover and one activation`; table-driven `::receiver rejects new-active proof with invalid {sessionId,accountPeerId,role,devicePeerId} identity without activation`; table-driven `::sender rejects new-active proof with invalid {sessionId,accountPeerId,role,devicePeerId} identity without migrated-out commit` | real runtime route; blocked cutover completer; per-field proof mutation fakes | causal RED (handlers overlap; first implementation trusted committed flags alone) → duplicates join once, in-flight manifest mutation conflicts, and every invalid identity field activates neither endpoint nor commits old migrated-out | remove in-flight future, command gate, or any proof-identity field validation → counts/status/activation assertions red | runtime test file; AUTO |
| TC-21 | Activation ownership survives journey disposal and finalizes once even when refresh fails | `startup_router_recovery_test.dart::off-screen receiver activation stops the retained session and resets the route once`; `::receiver activation reset survives projection refresh failure exactly once` | widget/router; retained onboarding owner; duplicate activation; throwing refresh callback | causal RED (journey is sole subscriber; first implementation awaited uncaught refresh) → stop once, refresh telemetry on error, and one route reset to imported account; duplicate activation ignored | retain callback/reset on replaced StartupRouter state, journey-only, omit dedupe/stop, or let refresh error suppress reset → TC-21 red | router recovery test; **MANUAL path registration** |

### Test Notes
- **TC-01/TC-05/TC-20 fixture trap.** To simulate an iOS *source* you must seed **every**
  shared-scope value the collector demands: `iosSharedAccessGroup:identity_ml_kem_secret_key` is
  `criticality: critical`, so a non-null `sharedStore` missing it makes `_collectSecureEntries`
  throw `AccountMigrationBundleAssemblyException('missing critical secure value: …')`
  (`bundle_transfer.dart:342-348`) — an **export-side** failure that would masquerade as the
  receiver bug under test.
- **TC-05 vacuity trap [v2].** `_promotionKeysForSecureEntries` (`:1918-1942`) deliberately
  **excludes** `dbEncryptionKey` and appends `secretsMigrated` plus every `clearRegenerate` fixed
  key. A negative-only assertion ("no shared-scope keys promoted") is therefore satisfied by an
  implementation that drops *every* entry except `db_encryption_key` — `complete()` would still
  return true because the staged DB key is present, and `_validateRequiredStagedValues` passes
  vacuously because its list is derived from the same shrunken entries. Only the positive equality
  discriminates.
- **TC-06/TC-06b finder trap.** Assert the waiting arm's keyed erase action is absent. For the
  explicit `migratedOut` sentinel, drive the existing action/confirm through
  `account-migration-erase-action` and `account-migration-erase-confirm`, never an ambiguous text
  finder.
- **TC-19/20 response-loss trap [v3].** A `.timeout` does not cancel receiver work. The causal
  fixture must let the first proof continue after the sender times out, trigger stop from the
  activation event, and send the retry through the same runtime HTTP route. A direct bundle
  receiver call cannot prove routing grace, capability negotiation, or one activation.

### Deferred contract — Item A-2 (`DEFER-285-03`, NOT executed under `DECISION-285-01` option (b))

These six rows were drafted and review-hardened for the user-asserted abort. They are preserved
verbatim so a future plan does not re-derive them, and they are **not** part of this plan's
acceptance. Their production edits (`abortInterruptedCutover`, the reactivate affordance, the
cutover `failureCode` write) are explicitly forbidden by the Scope Contract above.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD state → GREEN | Mutation that re-reds | Gate / registration |
|---|---|---|---|---|---|---|
| TC-07b **[v2]** | Tapping reactivate persists the transition **and** leaves the blocked screen | `startup_router_recovery_test.dart::reactivating an interrupted old phone restores active authority and re-routes` | widget/router; seeded `migrationCutoverPendingBlocked` + the eligible `failureCode`; reuses the existing `saveAuthority` helper at `:150-192` | causal RED (no affordance exists) → persisted authority becomes `migrationFailedActiveRestored` AND the blocked screen is gone | wire the affordance to a no-op → TC-07b red | same command as TC-07; **MANUAL (same single path as TC-07)** |
| TC-12 | The new transition exits the cutover block only from the eligible record, and refuses every other state | `test/features/account_migration/application/migration_cutover_coordinator_test.dart::abortInterruptedCutover restores active authority only from an eligible interrupted cutover` | unit host; in-memory authority + cutover repos already in that file | causal RED (compile-RED — method absent) → writes `migrationFailedActiveRestored` for `migrationCutoverPendingBlocked` **with `failureCode == 'old_block_proof_post_failed'` [v2]**; returns false and writes nothing for `active`, `migratedOut`, `migrationVerifiedWaitingForCutover`, `migrationFailedCleanupRequired`, any fail-closed record, **and any blocked record lacking that failureCode** | widen the guard to accept any state, or drop the failureCode precondition → the refusal assertions red | `flutter test test/features/account_migration/application/migration_cutover_coordinator_test.dart`; AUTO (glob) |
| TC-13 | After abort, every invariant the blocked state justified is re-verified | `migration_cutover_coordinator_test.dart::an aborted old phone can start a new export` | unit host; sequence `markOldNetworkBlocked → abortInterruptedCutover → markExportingNetworkPaused` | causal RED (compile-RED via TC-12; on HEAD `markExportingNetworkPaused` throws from the blocked state, `coordinator:65-75`) → succeeds; the resulting record is a fresh session; the lease-cleanup flags are asserted in full | make abort write `active` instead of `migrationFailedActiveRestored` → `recover()` flips to `retryLeaseCleanup` (`coordinator:461-467`) and the lease assertion reds | same command as TC-12; AUTO (glob) |
| TC-14 | The affordance is offered for the eligible old-phone state **only**, and is genuinely enabled | `account_migration_blocked_screen_test.dart::reactivate action is offered and enabled only for the eligible interrupted old-phone state` | widget; key presence for the eligible record, **absence** for `migrationVerifiedWaitingForCutover`, `migratedOut`, `migrationFailedCleanupRequired`; **plus `tester.widget<FilledButton>(…).onPressed, isNotNull` [v2]** | causal RED (compile-RED — no affordance) → present+enabled / absent exactly as above | offer it unconditionally, or render it permanently disabled (the pattern already on this screen at `:120-131`) → TC-14 red | same command as TC-06; AUTO (glob) |
| TC-14b **[v2]** | Tapping the affordance actually invokes the abort | `account_migration_blocked_screen_test.dart::tapping reactivate invokes the abort callback exactly once` | widget; injected `onReactivate` spy; `tester.tap(find.byKey(ValueKey('account-migration-reactivate-action')))` | causal RED (no affordance) → spy fired exactly once | ship the affordance with `onPressed: null` → TC-14b red | same command as TC-06; AUTO (glob) |
| TC-15 | Aborting is non-destructive | `account_migration_blocked_screen_test.dart::reactivating does not erase identity material` | widget; recording secure key store asserting zero `delete` calls and that `onEraseAccount` was never invoked | causal RED (no affordance) → zero deletes; erase callback untouched | wire the affordance to `onEraseAccount` → TC-15 red | same command as TC-06; AUTO (glob) |

Reopening note: a future plan should not ship these as drafted. `UNRESOLVED-285-01` is better
solved by making the new phone's commit state *observable* — a durable, authority-backed answer on
the existing `status` command (`account_migration_local_transfer_runtime.dart:32`) — than by
asking the user to assert it. If that lands, the abort stops being user-asserted and TC-12's
`failureCode` gate is replaced by a positive proof of non-commit.

## Implementation Steps

1. Snapshot `git status --short`. The tree is known-dirty with unrelated DTR documentation,
   Graphify output, and a test-only TCP-port assertion correction; record the baseline.
2. **Item A-0/B runtime state machine.** Write TC-17/18/18b/19/19b/20 and confirm the REDs.
   Add runtime phases `receiving`, `completeInFlight`, `verifiedWaiting`, `proofInFlight`,
   `committedReplayable`; `stopRequested`; a proof future; committed proof; activation latch; and
   expiry timer. Publish `completeInFlight` before body read and settle duplicate responses from
   the owner future. Validate each proof
   before replay/join, single-flight valid proofs, emit activation once, stop advertising on stop,
   retain committed routing for five minutes by default, then expire it. Add
   `old_block_proof_replay_safe: true` to transcript and successful `complete`; use the early
   negotiation for at most two complete transport attempts, then thread the completed response
   capability to cutover and perform at most two proof attempts with one injected 250 ms delay
   for transport loss or semantic `cutover_rejected` only when true.
   `bundle_transfer.dart` — after a valid `commitNewActive`, return that proof even if subsequent
   best-effort cleanup fails.
   Stop-if: a committed response-loss retry can receive 404, two concurrent requests call the
   receiver twice, a duplicate complete diverges from its failed owner, an invalid proof joins a
   valid in-flight request, advertising cleanup leaves a route behind, or an absent capability
   causes more than one POST.
3. **Item A-1.** Write TC-16a and confirm the RED. Add
   `AccountMigrationRuntimeStartupLatch` in `account_migration_runtime_network_gate.dart`;
   synchronously publish the in-flight future, clear on false/error, retain completed success.
   Keep `Future<void> startLiveServices()` unchanged, add `startLiveServicesIfAllowed()` returning
   `liveServicesStarted`, inject the wrapper, and delegate `_ensureRuntimeServicesReady` to the
   latch.
   Stop-if: concurrent callers start twice, a false result remains cached, or a new
   `StartupRouter` parameter is introduced.
4. **Item D.** Write TC-02/01/03/05, add and run GREEN sentinels TC-03a/04, then:
   `migration_secure_storage_staging.dart` — add
   `bool supportsScope(MigrationSecureStoreScope scope) => scope != MigrationSecureStoreScope.iosSharedAccessGroup || sharedStore != null;`
   and **leave `_storeFor`'s `StateError` in place**.
   `account_migration_bundle_transfer.dart` — after `:1563` derive `stageableEntries` and use it at
   `:1564`, `:1611`, `:1613`; emit `…SHARED_SCOPE_ENTRIES_DROPPED` with the dropped count and scope.
   Stop-if: `_validateRequiredStagedValues` still throws `missing staged critical keys` — that
   means `:1611`/`:1613` were not switched; fix the call sites, never weaken the guard.
5. **Item C.** Write TC-06/06b/07/08/09, correct and run TC-10/11 sentinels, then parameterize
   the screen (`isFailClosed` first, then `record.state`; today's strings as the default arm; the
   new-phone arm hides the incomplete generic erase action), hoist the repository at
   `startup_router.dart:358-361` into a
   local and re-read it inside `case StartupDecision.accountMigrationBlocked:` wrapped in
   `try { … } catch (_) { record = null; }`. Import the enum from
   `domain/models/account_migration_authority_state.dart`. Hide the erase action for the waiting
   state and use the existing localized erase label elsewhere. Add only the new title/message
   keys in en/ar/de and regenerate with **`flutter gen-l10n`** after the version preflight
   (`flutter` resolves to 3.41.4 at review time; generated files are tracked).
   Stop-if: `l10n_integrity_test.dart` flags a hardcoded literal — route it through
   `AppLocalizations`; do not suppress.
6. **Item B UI ownership.** Write TC-17a/21 and confirm RED. Lock close/system back from
   `importingBundle` onward. Add a lifecycle-safe activation listener on the onboarding route
   above the journey; keep journey progress listening. On activation it calls stop with the
   session id and invokes the existing cache/projection refresh + route reset exactly once.
   Stop-if: the owner is `_StartupRouterState.initState` (that state is push-replaced), identity
   generation/restore is reachable after verification, or off-screen activation does not call
   stop.
7. Perform the single manual harness registration (the `startup_router_recovery_test.dart` path)
   and grep-verify it.
8. Run focused GREEN → preservation sentinels → the `move-feature` gate → the direct l10n
   command → `completeness-check`.
9. Record TC-16/16b only if an automated harness is run against re-resolved pinned targets.
   They are optional device-confidence rows, not host gates; unavailable targets are N/A by
   project policy and an unrun optional row does not block host closure.

There is no Item A-2 step. `DECISION-285-01` resolved to option (b), so
`migration_cutover_coordinator.dart` is not edited by this plan and no abort affordance ships.

## Risks And Blind Spots

- **Split-brain (two devices on one peer id)** → **eliminated by scope**, not merely mitigated:
  `DECISION-285-01` option (b) means no code path in this plan ever un-blocks a device that might
  be superseded. Item A-0 additionally shrinks the population that reaches the blocked state at
  all. The residual — a small number of transfers still stranded after the retry window — is
  accepted and owned by `DEFER-285-03`.
- **Dead runtime after an authority self-heal** → Item A-1, host-proven by TC-16a, device-confirmed
  by TC-16. Note this is reachable **today** via the export-pause self-heal
  (`startup_decision.dart:43-62`), independently of any abort, so A-1 fixes a live defect rather
  than one this plan would have introduced.
- **Lifecycle / derived-state durability:** TC-17/18/18b cover stop-during-complete, ordinary
  removal, committed replay grace, and expiry; TC-19/20 cover response loss and concurrency.
  TC-17a prevents user-driven identity replacement during verified finalization, and TC-21 owns
  off-screen activation above the journey. TC-16a covers the retryable startup latch.
  Process-restart durability of a verified import remains `DEFER-285-01`.
- **Sibling-surface consistency:** the scope predicate gates five verbs — stage / read / promote /
  delete / rollback — covered transitively by the receiver-level filter: `promote()` is called
  only from `acceptOldBlockProof` with the already-filtered `promotionKeys`, and
  `_deleteStagingValuesBestEffort` consumes `stagedKeys`. TC-05 asserts that relationship rather
  than three independent passes.
- **Destructive-action side effects:** TC-17a/20/21 plus the step-6 stop-if — the destructive act this
  plan must not enable is an off-screen cutover running `importVerifiedStagedDatabase`, which
  `txn.delete`s **every** table of the live active database
  (`migration_database_active_importer.dart:69-83`). `DEFER-285-02` erase residue is named with an
  owner and is neither widened nor narrowed here.
- **Invariant re-verification under new transitions:** runtime phases are explicit. TC-17 proves
  `completeInFlight → verifiedWaiting`, TC-20 proves one `proofInFlight`, and TC-18b proves
  `committedReplayable → expired`; each transition re-evaluates deferred stop and routing.
  (The authority-state transition that would have needed this treatment belongs to the deferred
  Item A-2.)
- **Construction / call-site census (re-derived at review, not inherited):** `_storeFor` — 7 call
  sites (`:42, :51, :75, :80, :99, :111, :153`) plus the declaration `:185`; `secureStorageEntries`
  receiver-side — exactly 3 (`:1564, :1611, :1613`); `AccountMigrationBlockedScreen` — 1
  construction (`startup_router.dart:387`); `decideStartupRoute` — 1 caller (`:355`);
  `MigrationSecureStorageStaging(` — 2 productions (`main.dart:2978`, `startup_router.dart:857`);
  `stopNewPhoneReceiver` — 1 definition + 1 wiring (`main.dart:4988`). **Re-run every grep at
  execution; these counts drift and must not be trusted as a fixed list.**
- **Fake side-effect fidelity:** the Android shape must be a genuinely `null` `sharedStore`, not a
  fake that silently accepts shared-scope writes. TC-19/20 count receiver/import invocations and
  activation events, not merely returned values.
- **Composite-node / relationship assertions:** TC-05 asserts one exact observable projection
  across stage/promote/delete; TC-18b asserts both sides of a timed state transition; TC-21
  asserts the same activation event causes stop, refresh, and route reset once.
- **Build-artifact provenance:** N/A — no native or plugin artifact is added or relied upon.
- **Permission / ACL verb symmetry:** N/A — no ACL or permission verb changes; the scope predicate
  is an availability check, covered under sibling surfaces.

## Gate Cadence

- **Per-plan closure:** the focused causal tests and sentinels above, plus
   `./scripts/run_test_gates.sh move-feature`, the direct
  `flutter test test/core/lifecycle/main_deferred_startup_wiring_test.dart`,
  `flutter test test/l10n/l10n_integrity_test.dart`, and
  `./scripts/run_test_gates.sh completeness-check`.
- **`1to1` and `groups` are deliberately NOT claimed** — justification, not omission: the plan
  introduces no new authority state. `migrationFailedActiveRestored` is already in
  `allowsRuntimeNetworkSideEffects` (`account_migration_runtime_network_gate.dart:57-64`) and in
  `allowsNormalStartup` (`account_migration_authority_state.dart:28-35`), so messaging surfaces
  see no new state.
- **Registration membership is grep-verified.** Curated family gates swallow
  `--list` and begin executing, and `completeness-check` **cannot** detect a
  missing lane registration — `classify_path` ends in a feature-local fallback
  glob that matches any `test/features/*/presentation/**_test.dart`, so it
  passes either way. The registered startup-router file subsequently executed
  inside the recorded 50-command `move-feature` gate.
- **Full `host-all` was not a per-plan gate and is not claimed here.** Any
  later aggregate or release run must explicitly include the Plan-285
  commit/range; this plan does not confer DTR-wave or rollout acceptance.
- Shared tests outside the feature glob: the exact core wiring and l10n commands above. No
  `test/unit`, `test/integration`, or `test/shared` paths are touched.
- Any later broad sweep runs
  `./scripts/run_host_test_gates.sh <scope> --batch-flutter --concurrency 4 --reporter failures-only`.

## Acceptance Gates  (literal — copy/paste)
```bash
# Dirty-tree snapshot before execution
git status --short
command -v flutter
flutter --version   # expect Flutter 3.41.4-compatible toolchain

# --- Representative causal REDs before production edits ---
flutter test test/features/account_migration/application/account_migration_bundle_transfer_test.dart \
  --plain-name 'complete accepts an iOS-sourced bundle on a destination without a shared access-group store'
flutter test test/features/account_migration/application/account_migration_local_transfer_runtime_test.dart \
  --plain-name 'response-lost committed proof retries once without duplicate import or activation'
flutter test test/features/account_migration/application/account_migration_local_transfer_runtime_test.dart \
  --plain-name 'stop during complete defers removal and a successful complete remains cutover-routable'
flutter test test/features/account_migration/application/account_migration_runtime_network_gate_test.dart \
  --plain-name 'runtime startup latch coalesces in flight then retries after a no-start'
flutter test test/features/account_migration/application/migration_secure_storage_staging_test.dart \
  --plain-name 'supportsScope is false only for iosSharedAccessGroup when sharedStore is null'
flutter test test/features/account_migration/presentation/account_migration_blocked_screen_test.dart \
  --plain-name 'shows unfinished-move copy for migrationVerifiedWaitingForCutover'
flutter test test/features/account_migration/presentation/account_migration_journey_screen_test.dart \
  --plain-name 'verified new-phone finalization disables close and system back'
flutter test test/features/identity/presentation/screens/startup_router_recovery_test.dart \
  --plain-name 'off-screen receiver activation stops the retained session and resets the route once'

# --- New/existing HEAD preservation sentinels — PASS before production edits ---
flutter test test/features/account_migration/application/account_migration_bundle_transfer_test.dart \
  --plain-name 'complete and cutover preserve shared mirrors when the destination supports shared scope'
flutter test test/features/account_migration/application/migration_secure_storage_staging_test.dart \
  --plain-name 'stageValue still throws when a shared-scope key reaches an unavailable store directly'

# --- Focused GREEN (after the fix) — exit 0, zero failures ---
flutter test test/features/account_migration/application/migration_secure_storage_staging_test.dart
flutter test test/features/account_migration/application/account_migration_bundle_transfer_test.dart
flutter test test/features/account_migration/application/account_migration_local_transfer_runtime_test.dart
flutter test test/features/account_migration/application/account_migration_runtime_network_gate_test.dart
flutter test test/features/account_migration/presentation/account_migration_blocked_screen_test.dart
flutter test test/features/account_migration/presentation/account_migration_journey_screen_test.dart
flutter test test/features/identity/presentation/screens/startup_router_recovery_test.dart
flutter test test/core/lifecycle/main_deferred_startup_wiring_test.dart

# Scope proof: this plan must NOT touch the cutover coordinator (DECISION-285-01 option (b))
git diff --name-only | grep -c 'migration_cutover_coordinator.dart'   # expect: 0

# --- Shared test outside the feature/core globs — exit 0 ---
flutter test test/l10n/l10n_integrity_test.dart

# --- Affected lane gate — exit 0, zero failures ---
./scripts/run_test_gates.sh move-feature

# --- Registration is grep-verified, never run-verified ---
grep -c 'startup_router_recovery_test.dart' scripts/run_host_test_gates.sh   # expect: 1 (registered once)
./scripts/run_test_gates.sh completeness-check                              # expect: PASS, 0 unmatched
                                                                            # NOTE: this does NOT prove lane registration

# --- Hygiene ---
flutter analyze      # 0 new issues; the suppression ratchet stays at its 3 generated l10n identities
git diff --check
```

Semantic outcomes: every RED must fail **for the documented mechanism** — not a compile error in
an unrelated file, and never `throwsA` on a `StateError` that `complete()` swallows. Every GREEN
and gate command exits 0 with zero failures; `grep -c` returns exactly 1; `completeness-check`
reports zero unmatched paths; `flutter analyze` adds no new issues.

## Execution Interpretation And Done Criteria

- **Expected RED:** runtime has no completion phase, proof single-flight, replay grace, capability,
  or bounded retry; readiness caches a no-start; staging lacks `supportsScope`; receiver complete
  rejects null shared store; screen has no record branch; journey remains poppable; journey is the
  sole activation owner.
- **GREEN sentinels:** TC-03a, TC-04, TC-10, TC-11, TC-11b, TC-18.
- **Pre-existing dirty tree:** unrelated DTR documentation, new plans 277/278/281–284,
  `graphify-out` artifacts, and a test-only TCP-port assertion correction in
  `account_migration_local_transfer_runtime_test.dart`. Do not revert them.
- **Environment blocker (NOT a product blocker):** none expected; the plan closes at host tier.
  TC-16/16b are optional automated device confidence only. Resolve targets live; unavailable legs
  are N/A by project policy.
- **Scope drift (BLOCKING):** any failure in the DTR-09 manifest islands, any wire-format or
  schema change beyond the one additive capability field, any edit to
  `MigrationSecureStorageCleanup`, any receiver-side disk rehydration,
  or **any edit to `migration_cutover_coordinator.dart` / any abort affordance** (deferred Item
  A-2 under `DECISION-285-01` option (b)).

- [x] Every in-scope behavior has a named test or a justified proof.
- [x] Causal RED, focused GREEN, and representative counterexample re-red are recorded.
- [x] Preservation sentinels and named gates pass with semantic outcomes.
- [x] Harness registration is implemented AND grep-verified.
- [x] `git diff --name-only | grep -c 'migration_cutover_coordinator.dart'` is 0.
- [x] `flutter analyze` has no new issues; `git diff --check` is clean.
- [x] The Scope Contract And Guard is respected.

## Rollback

- **Reversible by:** `git revert` of the plan's commits. Every edit is additive at the source
  level — runtime-only phases/latches/timers, an additive response capability, one retry loop, one
  scope predicate, screen/route guards, two ARB keys, and regenerated l10n.
- **Prior-build compatibility:** no new persisted format, key kind, authority enum, schema, or
  blob version is introduced (`currentVersion` remains 1). Item D makes a formerly failing path
  reach existing staging keys and `migrationVerifiedWaitingForCutover`; prior builds understand
  those bytes but cannot resume the process-local import. A new sender retries only when the new
  receiver's additive capability is present, so a prior receiver receives one proof POST.
- **Operational irreversibility:** reverting code cannot undo a Move whose old phone has already
  committed `migratedOut`, nor reconstruct user data erased by the pre-existing erase action. The
  code/data formats are backward-readable; the completed ownership transfer itself is one-way.
  **[v2/v3 — corrected justification]** v1 claimed the
  dropped shared-scope mirrors "regenerate on the destination". That is **false**:
  `_mirrorMlKemSecretForPush` early-returns on a null store
  (`identity_repository_impl.dart:215-219`) and `_mirrorGroupKeyForPush` does the same
  (`group_repository_impl.dart:2040-2047`), so on Android nothing regenerates. Item D is safe for
  a different, verified reason: **no reader exists there.** Every `iosSharedAccessGroup` reader is
  null-gated off on Android (`main.dart:537-546, :635, :1870, :2980, :3008`), and the only raw
  reader is the iOS notification-service extension
  (`ios/NotificationService/NotificationPreviewResolver.swift`), which does not exist on Android.
  The primary-scope counterparts travel independently in the same bundle — primary group-key
  material lives under a different name (`group_key_material:` vs `group_key:`). On a later
  Android → iPhone move, identity activation re-mirrors the identity key immediately; group
  mirrors are restored by the pre-existing next-cold-launch backfill, not by in-session activation.
- **Staging:** land directly. There is no forward-compat window to manage and no one-way boundary
  to stage behind.

## Reviewer Findings — v5 implementation audit

The execution counterexample audit found no remaining production blocker after the v5 closures.
It specifically re-tested complete/proof response loss, false/throw settlement, proof identity on
both endpoints, route revocation when advertising cleanup throws, post-commit cleanup failure,
blocked-authority TOCTOU, retained activation ownership, and startup step replay. The final
integrated review found no issue in the eight-file production scope. Verdict:
**`implemented`** · disposition **`close-host-tier`**. Optional availability-bounded device rows
TC-16/16b were not required or run and are recorded as N/A for this host closure.

## Reviewer Findings — v3 execution-request audit

`$tdd-review` 2026-07-26 — fresh factual, boundary/reversibility, and secure-storage passes with
lead verification in current source. Initial verdict: **`plan-fixes-required`**, core direction
confirmed, disposition `apply-plan-fixes`. Required deltas applied in this v3 revision:

1. runtime routing grace now makes committed-proof replay reachable after activation;
2. proof requests single-flight, so timeout/retry cannot overlap the destructive import;
3. stop during `complete()` is deferred and settled by the completion result;
4. retry is capability-gated for new-sender/prior-receiver safety and exactly bounded;
5. runtime startup preserves in-flight coalescing while clearing a gated no-start;
6. Item D has a receiver-level iOS → iOS sentinel and observable cleanup assertions;
7. new-phone verified finalization is non-poppable, with activation owned above the journey;
8. the blocked waiting arm is copy-only because generic erase does not clear unfinished residue;
9. rollback now distinguishes format compatibility from irreversible completed ownership transfer;
10. tool/device commands follow the live, availability-bounded project policy.

After these edits, the five lenses re-sweep as: L1 `clear`; L2 `clear` with the new
response-loss/concurrency/mixed-version rows; L3 `clear` with runtime phase and onboarding-owner
guards; L4 `clear` with corrected literal Flutter commands/registrations; L5 `clear` for host
closure, with process-restart resume and full unfinished-copy cleanup still explicitly deferred.
Verdict after revision: **`ready`** · disposition `execute`.

Blind-spot hits resolved: B-2/B-4/B-5/B-6/B-7/B-9/B-10. B-1 is limited to the pre-existing
one-way completed cutover and is stated honestly; B-3 is clear; B-8 is N/A to host closure and
kept only as availability-bounded optional device confidence.

## Reviewer Findings (v2 historical)

`/tdd-review` 2026-07-26 — 4-worker audit `wf_c265881f-048` (factual, counterexample,
boundary/reversibility, domain-bet), lead source-verification of every promoted linchpin.
**Verdict `plan-fixes-required` · disposition `apply-plan-fixes` · core bet (Item D) `confirmed`
for a corrected reason.** All 12 blockers are resolved in this v2 revision:

| # | Blocker | Resolution in v2 |
|---|---|---|
| 1 | v1 never fixed the un-retried POST it named as root cause A | Item A-0 retry; TC-19 |
| 2 | `acceptOldBlockProof` is not replay-safe, so any retry can reject a successful commit | `cutoverCommitted` flag; TC-20 |
| 3 | "today is strictly worse (both bricked)" is false for the committed-but-response-lost limb, which is the *dominant* interrupt | `UNRESOLVED-285-01` rewritten; `DECISION-285-01` re-scoped with option (b) as a complete, safe subset |
| 4 | Post-abort dead runtime is deterministic, not a race | Root cause E added |
| 5 | The re-arm seam as written is unreachable (`_runtimeServicesReady` is `_MyAppState`-private) | Item A-1 redesigned as "don't cache a run that didn't start services" |
| 6 | "No host tier can observe" the re-arm — refuted; `deferredRuntimeStartup` is injected at `main.dart:4998` | TC-16a added; TC-16 narrowed to device end-to-end |
| 7 | TC-05's negative-only assertions pass an implementation that drops every entry but `db_encryption_key` | TC-05 rewritten as a positive exact equality; vacuity trap documented |
| 8 | Item A could ship inert — a permanently disabled button passes TC-14 | TC-14 asserts enabled; TC-14b taps; TC-07b asserts persistence + re-route |
| 9 | TC-17/TC-18 jointly pass an implementation that never removes any session | TC-18 rewritten as a 404 `unknown_session` routing assertion |
| 10 | The Item B guard never releases after a successful move (`verifiedImport` is never nulled) | Guard keyed on `!cutoverCommitted`; TC-18b |
| 11 | Item B creates a completion path with no completion handler | Activation subscription moved above the journey widget; TC-21; step-6 stop-if |
| 12 | Item D's Rollback justification is factually wrong (mirrors do not regenerate on Android) | Corrected to the verified "no reader exists there" argument |

Also corrected: `main.dart` added to affected production files; export guard cited at `:336-339`
(was `:335-338`); TC-03 renamed to the test that actually exists; staging test count corrected to
3; `completeness-check` explicitly noted as unable to prove lane registration.

Confirmed sound and kept unchanged: the refuted-findings section (receiver rehydration is
zero-delta; `recover()` is constant for the blocked state; `migrationImportStaging` has no
production writer), the receiver-filter seam over route-to-primary (routing shared ML-KEM into
primary would collide with the primary entry of the same `activeKey` and silently overwrite it),
the `_storeFor` tripwire, the gate-cadence justification for omitting `1to1`/`groups`, and every
re-derived census count.

## Arbiter Decision

`DECISION-285-01` — **resolved 2026-07-26 by the project owner: option (b).** Ship
A-0/A-1/B/C/D; do not build the user-asserted abort. Consequences applied throughout this
revision: Item A-2 and its six contract rows moved to the deferred block (`DEFER-285-03`);
`migration_cutover_coordinator.dart` removed from the affected-files list and added to the
scope-drift guard with a `git diff --name-only` proof; the split-brain risk reclassified from
"mitigated" to **eliminated by scope**; the Rollback section simplified to "no new persisted value
of any kind"; TC-16 re-pointed from the (now unbuilt) abort path to the export-pause self-heal,
which is reachable on HEAD today; TC-16b added for the owner's iOS → Android device run.

At the pre-execution arbiter decision, the plan moved from `evidence-gated`
with one open decision to `implementation-ready` with none.

## Execution Progress
| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-26 | `$tdd-review` | plan + grounded production/test seams | initial `plan-fixes-required`; v3/v4 contract repairs applied | factual, counterexample, boundary, reversibility, and domain passes | none | execute |
| 2026-07-26 | causal implementation | runtime, staging/bundle, startup, blocked/router/journey, l10n, tests/gate | focused RED→GREEN cycles | runtime/state, cleanup, TOCTOU, and startup-ledger counterexamples covered | none | integrated verification |
| 2026-07-26 | final host verification | 9 focused test files + affected lane | 173/173 focused; all 50 `move-feature` commands; startup wiring 4/4; l10n 4/4; completeness 1349/1349 | `flutter analyze`: no issues; registration count 1 | TC-16/16b N/A (optional device confidence) | refresh graph |
| 2026-07-26 | graph/scope closure | 8 changed production files + plan | incremental graph refresh; affected query; scoped diff checks | fingerprint `d3c748f7a3cdec3b`; coordinator untouched | none | complete |
