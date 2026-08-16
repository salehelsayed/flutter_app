# Plan 374 Final-Tree Production Headless Canonical Recovery Receipt

Date: 2026-08-16 (Europe/Berlin)

This receipt binds the Plan 374 production headless canonical recovery
transaction — the seven connected Plan-331 safety seams in one
acquisition-to-ACK boundary — to its tested source tree. It records host,
focused Android-native, curated-lane and one automated no-Activity Android
device proof. It does not claim fixed `{v,w}` FCM ingress, opaque-wake or
outcome capability activation, live FCM/provider/relay/Doze/OEM evidence,
MessagingStyle presentation, N11 policy, full GAP-N08/PRD acceptance,
deployment or release eligibility.

## Verdict

**POST-EXECUTION AUDIT CLOSED / N08 PRODUCTION HEADLESS CANONICAL RECOVERY
CODE COMPLETE / N08 SLICE 1 OF 2 / HOST+NATIVE+AVAILABLE-ANDROID VERIFIED /
RECOVERY-WORK CODE-READY / FIXED-WAKE ADMISSION DEFAULT-OFF / NOT
LIVE-ACCEPTED / NOT RELEASE-ELIGIBLE**

N08_PRODUCTION_HEADLESS_CANONICAL_RECOVERY_CODE_COMPLETE

The incumbent deleted-batch and periodic recovery reasons now reach a real
UI-neutral production graph; the paired `opaque_wake_v1`/`wake_outcome_v1`
admission remains false and uninjected. Plan 375 alone owns fixed FCM ingress
and Android consumer readiness.

## Dependency provenance

The Plan 372 checksum-bound receipt was validated at execution start and
revalidated on the final tree
(`build/plan374/final/tc-374-00-revalidation.txt`, PASS). The revalidation ran
every TC-374-00 check except the clean-worktree line, which is unsatisfiable
mid-execution by definition; the execution baseline and dirty snapshot below
are the honest provenance for that difference.

| Dependency identity | Accepted value |
|---|---|
| Plan-372 receipt SHA-256 | `9da08053f6a6034b002376ccc348834ca2576b0761e77be72386e5ec1dec4a62` |
| Plan-372 receipt/implementation commit | `650f8cbe68dfed52a5c66fc53da35915bca53f02` |
| Plan-372 receipt tree | `9d4b46d37a205ea7da1a858dcde8c6f365b29917` |
| Plan-372 base | `434d31d16efc506b3a57b1cdec4ebb2f15fcf66a` |
| Plan-372 frozen tree | `71ab5f0ddcfa5e682f50f1bc36ebb891567b78b2` |
| Plan-372 workspace snapshot | `45e68aab0c0a79750102ccbccd1e010f663dea20a50ea5221cffa1e9278357ed` |
| Plan-372 graph identity | `8c428eb87b960e70` |

DB remains v116. Exactly one production `local_notification_ledger_v1.json`
owner exists under `NotificationConversationIds/.coordination.lock`; the four
registry APIs (`runFinalEffect`, `settleSqlReadyEffect`,
`listSqlReadyEffectTerminals`, `upgradeRelayCustodyToSqlReady`), both
`INBOX_RECONCILER`/`ANDROID_PUSH_SERVICE` owners and phase-preserving
`RELAY_VERIFIED_UNACKED -> SQL_READY` semantics validate; TC-372-01/05/06,
TC-371-01, TC-370-05 and TC-370-07 each re-pass 1/1; the paired
`kWakeOutcomeCoordinatorAdmissionEnabled` seam remains `defaultValue: false`.

## Implemented contract

### One UI-neutral production graph

- `lib/app/bootstrap/production_headless_canonical_recovery.dart` composes a
  production `CanonicalRecoverySession` from the same repositories, crypto,
  inbox parsers, ledger/effect owner and P2P implementation as the foreground
  bootstrap, through shared extracted composition helpers
  (`production_canonical_inbox_projection_composition.dart`,
  `production_canonical_direct_replay_composition.dart`,
  `production_canonical_group_replay_composition.dart`,
  `production_canonical_direct_projection_composition.dart`). No UI, `runApp`,
  `ApplicationRoot`, router, presence, notification-open listener, generic
  Firebase listener, retry timer or implicit plugin registrant exists in the
  headless graph.
- The encrypted opener gained an existing-only mode (`requireExisting`);
  missing key or database retries and never creates a key, database or
  account. Post-open identity is a passive DB-row plus secure-secret snapshot;
  the side-effecting `IdentityRepositoryImpl.loadIdentity` path is not called.
  Binding is re-derived and compared; linked authority is loaded against the
  DB account peer; the exact primary or active-linked physical credential is
  selected and a linked role never falls back to the account key.
- One `ProductionHeadlessCanonicalRecoveryRunner` owns the exact partial graph
  from first lease acquisition through returned session; `runRecovery` and
  `emergencyShutdown` address the same instance and reported
  `databaseClosed`/`leaseReleased` facts come from that instance.

### One acquisition-to-ACK transaction

- Order: parse/re-read binding+generation; coarse migration/role refusal;
  sole runtime lease; SQLCipher v116 existing-only open; passive identity/
  binding/linked qualification; recovery-only node core (no warm/LAN
  discovery, push restore, presence or timers); full typed direct drain
  (chat/text-mutation, reaction, introduction, contact request, deletion);
  full group drain (legacy plus protected bootstrap/authority/content);
  preliminary settlement; seal all Dart admission and await every admitted
  callback; stop `GroupMessageListener`; authoritative post-fence settlement
  over all four SQL custody totals plus the Plan-372 ledger; dispose owners;
  quiesce Go; close SQLCipher; release the lease; re-read binding, marker,
  migration/role and linked-credential fingerprint; compare-ACK only the exact
  deleted-batch marker. Periodic sweep neither fabricates nor consumes a
  marker.
- Post-seal offers are synchronously refused into durable retry with no
  handler/effect/direct-confirm/relay ACK; any non-converged page, nonzero
  custody total, pending ledger work, quiesce/close/release failure retains
  the marker and returns retry; a retained DRAINING owner blocks successors.
- Plan 374 materializes SQL ledger work only as `INBOX_RECONCILER`; it never
  originates `ANDROID_PUSH_SERVICE` or `RELAY_VERIFIED_UNACKED`.

### Readiness, rollback and the deleted-batch seam

- `recoveryWorkEnabled` now reflects code-ready supported-account composition
  through the typed native publication result; enablement requires the exact
  echoed binding plus flag (`exactlyMatches`), reconciled idempotently by the
  normal bootstrap. Same-binding rollback disables/cancels while preserving
  marker/ledger/SQL custody; logout/account switch rotates the binding through
  the incumbent native transaction. The paired opaque/outcome admission stays
  false and uninjected.
- `ProductionDeletedBatchRecovery` is the one shared deleted-batch
  commit/schedule seam used by `MknoonFirebaseMessagingService` and the
  debug-only H0 proof receiver; the receiver cannot write the marker or
  enqueue WorkManager directly (source contracts enforced by the device
  runner and the Kotlin source test).

## TDD chronology and causal evidence

| Stage | Result | Retained evidence |
|---|---|---|
| TC-374-00 preflight | PASS at execution start from committed planning baseline; revalidated on the final tree minus the mid-execution clean-tree line | `build/plan374/final/tc-374-00-revalidation.txt` |
| First TC-374-01 RED | 1 selected / 1 semantic assertion failure (`ProductionHeadlessExistingDatabaseUnavailable('missing_encryption_key')` matcher; no compile/load/tool failure accepted) | machine SHA-256 `c945cfdfaab78daa48f342b3250de742731a18c1286d23f1e74891b4ae478a75`; events SHA-256 `001792c140d3f50d5877c9cba95f663665fd2c727360d53e0d6c5a6c2073d7d6` |
| First TC-374-01 GREEN | 1 selected / 1 pass | machine SHA-256 `e46f4a060a9769b4e855b25fdd6d414a622fe91ff43d9f142442d44d705ac7e5`; events SHA-256 `5f9746a460f0267c0495324d4b0dc5c7d158984cd79c5eb69d33fe4152ed1281` |
| Final focused pure (concurrency 4) | TC-374-03/05/07 each selected 1 / passed 1; zero skips | `build/plan374/final/focused-pure-final.*.jsonl` |
| Final focused serial (concurrency 1) | TC-374-01/02/04/06 and TC-372-05/05b/06 each selected 1 / passed 1; zero skips | `build/plan374/final/focused-serial-final.*.jsonl` |
| Final preservation | all ten exact incumbent selectors selected 1 / passed 1; zero skips | `build/plan374/final/preservation-final.*.jsonl` |
| Focused Android native | 9 exact classes / 62 methods, zero failures/errors/skips; JUnit XML method manifest enforced in-script; compile + merged-manifest + source contracts | `build/plan374/final/native-final-post-device.txt` (host-all row 1382) |
| TC-374-08 device proof | PASS on discovered `emulator-5554` | result JSON SHA-256 `37c3f812e88604748943d6c7c158e11585b71f0bf156d579d504bc7e461fe98d` |

### Required mutation protocol (5/5)

Each mutation was applied alone on the otherwise-green final tree, required
its exact named owner to fail as a semantic assertion (1 selected / 1
failure, zero passes), and was reverted with byte-identical restoration
(pre/post file SHA-256 equality machine-checked) before the exact owner
returned GREEN (1 selected / 1 pass). Full records (command, changed line,
counts, hashes) are in `build/plan374/mutations-final/mutation-report.json`.

| # | Mutation (single site) | Owner | RED artifact SHA-256 | Restored-GREEN artifact SHA-256 |
|---|---|---|---|---|
| 1 | `production_headless_canonical_recovery.dart`: `requireExisting: true` -> `false` (permit missing-key/DB creation) | TC-374-01 | `79eeb41e6f1160fd1cc25f54f9fb7bfee8cf62892bd7449280609835d28b8521` | `d4bf096ec50970d1ae722803c2e096a5114e20ea65c656aa0ff716cdb460256d` |
| 2 | `production_canonical_inbox_projection_composition.dart`: typed protected group-content handler binding -> `null` | TC-374-02 | `995d07be1fa84c9b6b0da926f51cd2aa1a716f14890d79038775f697175546f5` | `26f59ddcb5d0d43fc25b1ea3f1ffc6d0b516bae3f7d9bc39a90a318cb1c5106e` |
| 3 | `canonical_recovery_runtime.dart`: post-teardown `finalMarker != startingMarker` guard disabled (trust initial generation) | TC-374-03 | `db5de423e144ada670e792fc34036bfc7891e0983380e5b132e65611d401c2b7` | `960cd90dfd98dcc3a4ad8ea9dbcafeee80f3cb855d2e5ad4b77a7b5c55dea48b` |
| 4 | `production_headless_canonical_recovery.dart`: authoritative pass predicate `_settlementPass++ > 0` -> `< 0` (omit post-seal settlement) | TC-374-04 | `741abb0b85fc9ae40c697725b2a2c247f8ff2af096cb92992909b35d4a215b73` | `1a8f2fc38ece9efeedf5eeab4b991d84985011e7c7836a7baab8946ac5716dbe` |
| 5 | `canonical_runtime_lease.dart`: readiness `exactlyMatches(binding+enabled)` -> bool-only comparison | TC-374-05 | `21ff6745833c529ce89d3b822a8a20f3597aa770de68717e0299adbfbb274e92` | `14cb447a553860d336a1a8ba92733e89477a3ab90f83d63876b6f0c48f0074b3` |

TC-374-06/07/08 remain causal GREEN/race/source/device proofs; no additional
RED or mutation count is claimed.

## Availability-bounded Android proof

One immutable disposable APK was built via the plan `--build-only` command on
the final product tree, then one explicitly discovered target ran the full
automated no-Activity scenario (emulator preferred by plan policy; USB Pixel 6
remains optional parity and was not required):

| Fact | Value |
|---|---|
| Target | `emulator-5554` (`Google sdk_gphone16k_arm64`, API 37) |
| APK SHA-256 | `7e1d437a1e0aed77dd2dab011e33b637b0d62f3bb8fd8e1989e56b02aeae8ac6` |
| Bound source manifest (9 runner-pinned files) SHA-256 | `f2ea8877d70d8a70f331926bc25e65474f7b8cc58c15afb8991e4059ed8c9a20` |
| Run nonce | `dd1392fb5954417b8a92a2222312afc3` |
| Scenario count | 1 (production deleted-batch seam -> WorkManager -> process death -> resume -> exact ACK) |
| Seed | existing SQLCipher v116 (`4.10.0 community`), all four custody stores pre-loaded, ledger empty, `recoveryWorkEnabled` true via typed readiness |
| Deleted batch | committed generation 1 through `ProductionDeletedBatchRecovery` (service seam; probe cannot seed/enqueue directly) |
| Process death | first attempt pid 27972 consumed the armed barrier and was killed (`run-as kill -9`); resumed attempt pid 28068 completed `SUCCESS` (distinct process, runAttemptCount 1) |
| Convergence | direct display/reconciliation and group display/reconciliation totals all 0; ledger exactly 2 records (`direct_message` + `group_message`), each `SQL_READY` / `INBOX_RECONCILER` / `OS_POSTED` / `SETTLED` |
| Cards | both exact private message cards posted (category `msg`, visibility private, silent channel); `matchingCardCount` 2; `privateMessageCardCount` 2; app-posted cards 2 with 0 unexpected; 1 system-created silent-section autogroup summary (`FLAG_AUTOGROUP_SUMMARY`) recorded and excluded from app-card exactness |
| Marker | exact deleted-batch compare-ACK; `pendingGeneration` null after success; DB `quick_check` ok |
| Purity | Activity launch count 0; `applicationRootConstructed` false; manual taps 0; skips 0; headless engine not retained; lease and Go both `RELEASED` |
| Cleanup | disposable package uninstalled after the run (0 matching packages remain) |

Iteration history (honest provenance): earlier device attempts exposed and
were fixed by — owner consolidation; a stale-cleanup generation race; a stale
direct-correlation product defect (now guarded by the registered
`production_canonical_direct_projection_composition_test.dart` regression
owner); an `am kill` that could not terminate the barrier-held worker
(replaced by the pinned package-UID `run-as kill -9` plus a registered-job
force-drive); an API-37 `Registered N jobs:` JobScheduler dump-header parse
mismatch in the runner; and the Android silent-section autogroup summary
classification. Archived under `build/plan374/device-*` and
`build/plan374/final/device-*.txt`. WorkManager reschedule churn during the
post-kill backoff window is recorded verbatim in the run's
`workmanager-resume.txt` audit.

## Final gates

| Gate | Final result / evidence |
|---|---|
| Baseline registration (2a) | `production_headless_canonical_recovery_test.dart` exactly once in `BASELINE_TESTS` and exactly once in the runner source; the new device-found regression owner `production_canonical_direct_projection_composition_test.dart` is additionally registered exactly once |
| Native registration (3) | exactly one later-wave host item; absent from `--dart-only`; `bash -n` clean; executed via `host-all --only` (row 1382) |
| Completeness | `1464/1464` test files classified |
| Curated `baseline` | final-tree rerun green: flutter batch +196 plus pinned-device integration files +6 and +1 on `emulator-5554`, zero failures (`baseline-final-tree.txt`) |
| Curated `1to1` | 3,340 pass / 10 declared skips plus all relay/toolchain Go tails (`1to1-post-device-final.txt`) |
| Curated `groups` | 4,345 pass / 0 skips plus bridge/node/relay Go tails (`groups-post-device-final.txt`) |
| Full analyzer | No issues found (99.4s), with the documented `build/**` analyzer exclusion for native-gate fixture copies |
| Formatting | every changed + untracked Dart file format-clean (`--set-exit-if-changed` sweep) |
| Shell syntax / diff hygiene | `bash -n` on both gate runners and both Plan-374 scripts; `git diff --check` clean |
| Graphify | incremental refresh 7 changed / 3,267 unchanged / 0 deleted; 78,599 nodes / 115,965 edges; TDD overlay 1,600 files / 15,790 named tests / 1,262 production targets; review query current/anchored, fingerprint `1072905b3c92a723` |
| Broad sweep policy | no per-plan `host-all`, `core-host-all`, `feature-host-all` or credential-dependent real-FCM campaign was run or implied; Plan 375 owns the N07+N08 adapter-wave `host-all` |

## Frozen tested state

An alternate Git index captured the accepted Plan 374 implementation without
changing the shared index. Closure documentation and evidence are absent from
the frozen tree.

| Identity | Value |
|---|---|
| Capture date | `2026-08-16` (Europe/Berlin) |
| Branch | `protected-view` |
| Base HEAD | `ffe37b71af5759320e677fab5495b5635bd661ea` |
| Base/HEAD tree | `eb03307e533ca33242ff4fb5dedf205334a0e588` |
| Frozen tested tree | `220f71b36ef7617c3b8c0760df99836d185819a1` |
| Porcelain-v2 workspace snapshot SHA-256 | `943eb5fa86eb41f416bd4c59a80bff3a8eeef883f8df42da383f43315486b3ef` |
| Porcelain-v2 status lines / records / bytes | `64` / `64` / `9,839` |
| Compressed snapshot SHA-256 | `bb520c51ff42885456fa9a8a8dcd6e45da9ddf6198199c928fcee0e5c16fc2af` |
| Frozen paths / added / modified / deleted | `64` / `14` / `50` / `0` |
| Frozen paths SHA-256 | `a371f9ec52e5633bf1f30284520bda1b115576c6197f666376df4476415421b8` |
| Frozen name-status SHA-256 | `5eafa1c12a790587c219ee328da7ec22c4b173546fab44c06da20a87c646bae3` |
| Frozen numstat SHA-256 | `9691a3e15aa4f3bd0e77468bb893bd9db3909aa1af8f21bdea39c0c3b08c9ae2` |
| Shared-index entries / bytes / SHA-256 | `6,474` / `919,138` / `2b042a3a20226a565ddb0ac22994b18fb916008a6bc9f3720682789f206a9b31` |
| Shared-index staged entries | `0` |
| Alternate-index entries / bytes / SHA-256 | `6,488` / `920,995` / `f09952fb7946d16bf775d9e34f343c3148f9562d07ae2ffc06f7f94d622d7672` |
| Graphify fingerprint | `1072905b3c92a723` |

Machine-readable identities:

```text
Base HEAD: ffe37b71af5759320e677fab5495b5635bd661ea
Frozen tested tree: 220f71b36ef7617c3b8c0760df99836d185819a1
Dirty snapshot SHA-256: 943eb5fa86eb41f416bd4c59a80bff3a8eeef883f8df42da383f43315486b3ef
Graphify fingerprint: 1072905b3c92a723
```

`workspace-porcelain-v2.txt.gz` decompresses byte-exactly to the snapshot
whose SHA-256 is recorded above. `graphify-fingerprint.txt` contains the
exact 16-hex graph identity. Both files, this README and its sibling checksum
are successor-verifiable committed evidence.

This README, checksum, archive, fingerprint file and the final
plan/status/index/coverage closure necessarily postdate and are absent from
the frozen tested tree. They add no production, test, native, fixture,
gate-runner, device-runner or Graphify-source change after the accepted gates.

## Residual boundaries

- Fixed `{v:"1",w:"1"}` FCM classification, the generic fallback card,
  fixed-wake scheduling, capability readiness and token re-registration are
  Plan 375; live FCM/provider/relay/Doze/OEM campaigns, activation, cohort
  operations, telemetry, A-control acceptance and release are WP-07/N12.
- The paired `opaque_wake_v1`/`wake_outcome_v1` admission remains default-off
  and uninjected; enabling incumbent recovery work is independent of that
  seam by construction and by TC-374-05.
- N09 MessagingStyle/Person styling and N11 read/mute/cleanup policy are
  untouched.

## Handoff

Plan 375 may start only from this committed checksum receipt. It consumes the
frozen production factory/session, exact role-correct identity selection, the
marker/scheduler extension point, Plan-372 ledger settlement and this device
proof. It must not reopen the production graph, create another
worker/store/lock, or synthesize `ANDROID_PUSH_SERVICE`,
`RELAY_VERIFIED_UNACKED`, correlation, SQL or relay-ACK authority from the
identity-free fixed wake; Plan 374 remains the materializing
`INBOX_RECONCILER`. Plan 375 may count the N07+N08 adapter-wave `host-all`
only after both this receipt and the checksum-valid Plan-373 receipt validate.

N08_PRODUCTION_HEADLESS_CANONICAL_RECOVERY_CODE_COMPLETE appears exactly once
above as the standalone raw marker line.
