# 218 - SQLCipher raw-key mode: kill the ~503ms cold-start PBKDF2 DB open  (Feature Improvement / Perf)

Status: awaiting-review (v3 — v2 re-audited by /tdd-review (workflow wf_2b86d6a6-5cd, 8 agents + orchestrator source-verification, 2026-07-06); the 5 material residuals it found are now closed in this doc: INV-5 gate rewritten to a comment-marker convention, §H2 fallback DROPPED (primary-only, SC-8-gated), SC-9 sequencing DECIDED, SC-5 baseline instrument-first, marker value-set reconciled)
Spec: free-text intent (no formal spec) — device-measured cold-start budget (memory `project_cold_start_budget_and_reducibility_2026_07_06`, workflow wf_9e765278-b33) + review fix-list.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-06 | Evidence Collector | encrypted_db_opener.dart, main.dart:481/:2001, migration_database_snapshot_exporter.dart, migration_database_import_staging.dart, background_message_handler.dart:284-303, sqflite_sqlcipher 3.4.0 native (SqfliteSqlCipherPlugin.m/FMDatabase.m), sqlite3 3.1.4 | Cipher DEVICE-ONLY; mechanism SOUND (down-ranked); rollback-brick + 5th site + user_version = the real risks | build matrix |
| 2026-07-06 | Reviewer (7-agent) | fix-list `218-review-fixlist.md` | v1 NOT execution-ready; §A rollback + §B scope + §E user_version = blockers | rewrite (this doc) |
| 2026-07-06 | Verifier | workflow wf_b5c4c901-4e9 (4 agents) | B1/B2/E1/E3 CONFIRMED; H1/H2 CONFIRMED (mechanism sound) | emit v2 |
| 2026-07-06 | Re-Reviewer (/tdd-review, wf_2b86d6a6-5cd, 8 agents) | INV-5 gate (opener:85/bg:300), pubspec.lock:1108 (sqlite3 transitive), opener:120/:209 (no elapsedMs, has ts) | v2 NOT execution-ready: 33/39 fix-list items closed but INV-5 gate provably non-functional + §H2 fallback ships plaintext + SC-9 undecided + SC-5 baseline field + marker/table mismatch | emit v3 (this doc) |
| 2026-07-06 | Arbiter | — | v3 closes the 5 residuals; core bet verified sound | hand off to execution |

## Execution Progress (GO/STOP signoff required)
| Time | Phase | Files touched | Command/evidence | GO/STOP | Next |
|---|---|---|---|---|---|
| 2026-07-06 | Step 0a: land elapsedMs instrumentation (behavior-neutral) | encrypted_db_opener.dart | opener emits elapsedMs on SUCCESS (Stopwatch brackets open only); device FLOW log confirms `elapsedMs`=262 (pass) / 19 (raw) | ✅ DONE | |
| 2026-07-06 | Step 0b: pre-fix baseline (N=10) | — | DEFERRED — field is landed & device-capturable; full N=10 airplane-mode baseline is the SC-5 denominator, captured with the Phase-B raw numerator | pending (Phase B era) | |
| 2026-07-06 | SC-8 feasibility (device, self-contained) | db_raw_key_migration_proof_test.dart | **Pixel: pass 290ms→raw 12ms (~24×). iPhone: pass 136ms→raw 1ms (~136×).** Both "All tests passed!" | **GO (both platforms)** | Phase A |
| 2026-07-06 | Phase A / 218-pre RED | SC-R(c)/SC-8(b) inline-encode the mutation (passphrase-only open of raw DB FAILS); INV-5 RED-flagged all 7 sites on HEAD | impl-before-test (devices live); mutation-sensitivity proven inline + FLOW log shows raw branch taken (no fallback event, 19ms) vs passphrase (fallback event, 262ms) | — | |
| 2026-07-06 | Phase A impl (read-tolerant opener + 5th site + markers) | encrypted_db_opener.dart (read-only `_isRawKeyDatabase` probe), background_message_handler.dart (+`openBackgroundIdentityDbReadTolerant` seam), migration exporter/import_staging (markers), check_reliability_simulation_discovery.sh | INV-5 gate CLEAN (9 opens classified); flutter analyze 0 new; **SC-8/R/B GREEN on Pixel AND iPhone** (SC-R raw open ~9ms Android / ~2ms iOS vs ~244ms/~164ms passphrase, through the real opener) | ✅ DONE (device-green both platforms) | ship gate |
| 2026-07-06 | Phase A iOS fix (device-caught) | encrypted_db_opener.dart | **iOS FMDB brick caught by SC-R**: a wrong-key read-WRITE open leaves a dangling `BEGIN EXCLUSIVE` → the immediate passphrase re-open fails "out of memory" (would brick EVERY iOS cold start). SC-B (read-only) was clean → root cause = read-write mode detection. Fix: detect mode via a throwaway **read-only, singleInstance:false probe** (`_isRawKeyDatabase`), then a single real open with the correct key. Re-run GREEN both platforms | ✅ FIXED | |
| 2026-07-06 | **Ship-model DECISION (user)** | — | Soak is a ROLLOUT-sequencing policy, not a dev/test gate. User has a CONTROLLED 3-phone fleet (fresh passphrase identities) + iOS sims → develop + device-prove Phase B now; rollout stays A-before-B ("install A, then B; never downgrade below the read-raw build"). No TestFlight user-soak required for the controlled fleet | **GO to build Phase B** | 4a |
| 2026-07-06 | 4a raw-on-create + durable marker (SC-1/4/6) | encrypted_db_opener.dart (marker seam `parseCipherKeyRecord`/`decideCipherOpenAction`/`isValid256BitHexKey`), db_raw_key_migration_proof_test.dart, encrypted_db_opener_mode_selection_test.dart | **SC-6 host 10/10**; **SC-1/SC-4 GREEN Pixel+iPhone**; fresh install creates raw + `raw:` marker (persisted BEFORE create → crash-safe); 2nd launch (raw,exists)→openRaw direct ~2-17ms | ✅ DONE | 4b |
| 2026-07-06 | 4b atomic rekey (SC-2/3) + plaintext→raw (SC-9) | encrypted_db_opener.dart (`_exportToRawAtomic`, `_recoverInterruptedRekey` keyPersisted-aware, fault-injection hook) | **SC-2/SC-3/SC-9 GREEN Pixel+iPhone**: §E2 side-path→verify→atomic-rename; user_version==95 preserved; all 3 interrupted-swap faults recover openable+intact; plaintext→raw direct (1 export, version preserved). ATTACH `KEY "x'<hex>'"` device-verified | ✅ DONE | 4c |
| 2026-07-06 | 4c Move regression sentinel (SC-7) | (no Move edits) | **account_migration_scale_benchmark_test GREEN on Pixel** — Move decoupled from identity.db cipher mode (shared handle; snapshot stays passphrase) | ✅ DONE (green) | |
| 2026-07-06 | Host gates | — | `flutter test test/core/database/` **641 GREEN** (schema migrations + SC-6 + helpers); INV-5 marker gate CLEAN; flutter analyze 0 new | ✅ DONE | |
| | speed device-proof (SC-5, both platforms) | — | STRONG proxy already: real-opener FLOW `elapsedMs` raw ~2-17ms vs passphrase ~136-289ms (ratio + <15ms met). Formal full-app cold-start SC-5 on the real ~65-table identity.db = launch the app on the 3 phones (FDC_FLOW_LOG) — the real rekey fires on 1st launch | PENDING (real-app run) | |
| | QA (independent) | | | | verdict |

## Source Of Truth
- Intent: memory `project_cold_start_budget_and_reducibility_2026_07_06` + `218-review-fixlist.md`
- Gate defs: `scripts/run_test_gates.sh` / `scripts/run_host_test_gates.sh`; sim discovery: `scripts/check_reliability_simulation_discovery.sh`
- Numbering: `Test-Flight-Improv/00-INDEX.md` (#218)

## Session Classification
implementation-ready — **two-release ship model** (§A): Phase A (forward-compat read) ships FIRST as the floor; Phase B (rekey) ships only after. Gated on the SC-8 feasibility GO.

## Exact Problem Statement
Cold start spends **~503ms** opening `identity.db` every launch (`ENCRYPTED_DB_OPEN_START`→`SUCCESS`; **re-measure in Step 0** — the 503ms is a remembered figure, not re-verified). It is ~1/3 of the ~1.47s launch→online budget and the single biggest reducible cost (network/relay is only ~249ms). The cost is SQLCipher's 256,000-iteration **PBKDF2**, incurred because `openDatabase(..., password: key)` (`encrypted_db_opener.dart:82`) uses **passphrase mode**. The stored key is already a **256-bit CSPRNG value** (64 hex, `_generateRandomKey:12-16`), so PBKDF2 adds **zero** security.

**What must improve:** open identity.db in **raw-key mode** (`x'<64hex>'`) → PBKDF2 skipped → open collapses to **≤15ms (the locked SC-5 gate: `raw_p50 ≤ passphrase_p50/5` AND `≤15ms`)**. Existing installs rekey once (atomically, data-preserving).
**Why a REKEY (not a fresh key) — and why rollback-safe (§A4):** identity.db holds the **node private key**; a fresh key would destroy the account identity irrecoverably (not just chat history). And the rekey is **one-way** — a TestFlight rollback to a build that only reads passphrase mode would brick every migrated identity. Hence the two-release forward-compat model below.
**What must stay unchanged (→ sentinels):** every repository still opens identity.db (~65 tables); the account-migration **Move** export/import round-trip (the transfer **snapshot stays passphrase-mode ON PURPOSE** — cross-device/cross-version wire format, §B1); the legacy plaintext→encrypted path; identity.db stays **version 95** (cipher-param change, **NOT** a schema change — NO DB v##).

## Root Cause (verify → refute confirmed; workflow wf_b5c4c901-4e9)
`encrypted_db_opener.dart:82-85` opens `password: key` = passphrase mode → 256k-iter PBKDF2. Serial + most-blocking: `main.dart:481` `await` blocks first frame AND node-start (node-start reads identity.privateKey from this DB).

**identity.db open sites (all must be raw-key-aware — the corrected census):**
1. `encrypted_db_opener.dart:82` (via `openEncryptedDatabase`) — `main.dart:481` (identity.db, production) + `smoke_test_{main,restore,messages}` (inherit).
2. **`background_message_handler.dart:298-303`** — opens identity.db **directly** (`openDatabase('$dbPath/identity.db', password: key, readOnly: true, singleInstance: false)`, key from `'db_encryption_key'` :26/:290), **bypassing the opener** (`_resolveGroupMessageNotificationDisplayEligibilityFromEncryptedDb:284`). Android background-FCM group-mute/eligibility. **CONFIRMED 5th site — v1 missed it.**

**NOT an identity.db open (do NOT touch — §B1, CONFIRMED):** Move exporter `:164` (throwaway capability-probe DB, literal key `'mig004-capability-key'`), exporter `:253` ATTACH + `:275` open + importer `:185` — these key the **transfer SNAPSHOT** (a cross-device/cross-VERSION wire format that MUST stay passphrase). identity.db is opened ONCE (`main.dart:481`) and threaded into Move as an already-open handle (`main.dart:2001 sourceDb: db` → `bundle_transfer.dart:207` → `exporter:92 exportSnapshot({required Database sourceDb})`), so Move **inherits raw-key for free**.

**All `password:` opens in `lib` (7 total) + their INV-5 classification marker** (a corrected gate classifies, it does not trip on the legitimate ones): `encrypted_db_opener.dart:85` (production identity.db — `RAW_KEY` on the raw try, `LEGACY_PASSPHRASE_FALLBACK` on the passphrase fallback branch), `:157/:162` (plaintext-migration temp `.encrypted` file, NOT identity.db — `PLAINTEXT_MIGRATION`), `background_message_handler.dart:300` (5th site — `RAW_KEY`/`LEGACY_PASSPHRASE_FALLBACK`), `migration_database_snapshot_exporter.dart:164` (capability probe) + `:275` (open exported snapshot) + `migration_database_import_staging.dart:185` (staged snapshot) — all `SNAPSHOT_PASSPHRASE`. On HEAD none are marked, so the corrected INV-5 gate RED-flags all 7 (the required RED-before-fix). After Phase A/B every open self-classifies; a future UNMARKED `password:` open trips the gate.

**Refuted / do-NOT-re-introduce:**
- "PBKDF2 protects the key." **False** — full-entropy 256-bit key; PBKDF2 only hardens weak passphrases.
- "Needs a DB v## bump." **False** — cipher-param, not schema. Gate on a durable **cipher-mode marker**, not the version.
- "Host migration tests prove the cipher." **False** — `test/core/database/migrations/*` use plain `sqflite_common_ffi` (no cipher). Cipher is **device-only** (`integration_test/migration_database_sqlcipher_capability_test.dart`).
- "Move exporter/importer must switch to raw-key together or Move breaks." **INVERTED (refuted, §B1)** — the snapshot must STAY passphrase; switching it is *itself* the cross-version break. Move inherits identity.db's mode via the shared `sourceDb` handle.
- "`sqlite3_key` treats `x'…'` as a passphrase → still PBKDF2." **Down-ranked to LIKELY-SOUND (§H1, CONFIRMED)** — `password:"x'<64hex>'"` → `[db setKey:]` → `sqlite3_key(67 bytes)` follows the SAME raw-key rules as `PRAGMA key` (SQLCipher core `sqlite3.c` 67-char blob-literal detection; both derive via `sqlcipher_codec_ctx_set_pass`). The primary mechanism is sound; SC-8 remains as empirical Android+iOS binding confirmation.
- "Model atomicity on `_encryptExistingDatabase`." **Refuted (§E2)** — that template `deleteDatabase` BEFORE the dest is proven openable; use the explicit protocol in §E2 instead.
- "`onConfigure PRAGMA key` fallback." **Refuted (§H2)** — the native open runs a keyed validate BEFORE Dart `onConfigure`, so that fallback is unsound.
- "A secondary `sqlite3`-package fallback opener is the safety net." **DROPPED (re-review decision 2026-07-06).** The `sqlite3` package is **transitive-only** (`pubspec.lock:1108 dependency: transitive`, absent from `pubspec.yaml`) with **zero** `open.overrideFor`/`openCipherOnAndroid` binding anywhere in `lib`; a naive `sqlite3.open()` + `PRAGMA key` would run against the **non-cipher** system `libsqlite3` and silently write/read a **PLAINTEXT** identity.db (the file holds the node private key). Since the primary `password:"x'<64hex>'"` mechanism is verified-sound (§H1), there is **no fallback**: SC-8 is the sole go/no-go — a failing SC-8 is a **STOP-and-re-diagnose**, never a fall-back to a second opener.

## Real Scope
**Phase A / 218-pre (ships FIRST, the floor):** make every identity.db open site **read-tolerant** — try raw `x'<hex>'`, on key-derivation failure fall back to `password: key`. No rekey, no marker flip. Sites: `encrypted_db_opener.dart:82` + `background_message_handler.dart:298`. Lets a build read BOTH modes so a rollback from Phase B still opens a raw DB.
**Phase B / 218 (ships after A is the floor):** the one-time atomic passphrase→raw **rekey** + durable **cipher-mode marker** in `encrypted_db_opener.dart`; new installs create raw from the start.
**Out of scope (Scope Guard):** the Move exporter (`:164/:253/:275`) + importer (`:185`) — snapshot stays passphrase ON PURPOSE. Change 2 (de-serialize node:start, the other ~0.5s) — separate plan. Any schema/version change.

## Files To Inspect Next
Production: `encrypted_db_opener.dart` (:82/:85 open, legacy plaintext `_encryptExistingDatabase:132-178` incl. temp opens :157/:162, key gen :12-16); `main.dart:481` (+ :2001 Move handle threading, do-not-edit context); `background_message_handler.dart:26/:284-303` (5th site, :300 open); the marker (fold into the `db_encryption_key` record — §G1). **Every `password:` open in `lib` carries a trailing classification marker** (`RAW_KEY` / `LEGACY_PASSPHRASE_FALLBACK` / `SNAPSHOT_PASSPHRASE` / `PLAINTEXT_MIGRATION`) so the INV-5 gate can enforce "no UNMARKED passphrase open" — see INV-5. **No secondary `sqlite3`-package fallback opener (§H2 DROPPED).**
Tests: `integration_test/migration_database_sqlcipher_capability_test.dart` (device SQLCipher harness), `integration_test/account_migration_scale_benchmark_test.dart` (Move sentinel), `MigrationDatabaseImportStaging.computeDatabaseChecksumForTesting` (`import_staging.dart:131`) + `MigrationDatabaseSchemaInventory` (full-DB checksum/schema-hash, §F3).

## Existing Tests Covering This Area
- `integration_test/migration_database_sqlcipher_capability_test.dart` — real-SQLCipher device harness to model on (**exists**).
- `test/core/database/migrations/*` — schema migrations on plain FFI (**exists**; cipher-agnostic, NOT usable for cipher).
- `integration_test/account_migration_scale_benchmark_test.dart`, `*_db_proof_test.dart` — real-SQLCipher Move + db-proof sentinels (**exist**).
- `MigrationDatabaseImportStaging.computeDatabaseChecksumForTesting` (`import_staging.dart:131`), `MigrationDatabaseSchemaInventory` — reusable full-DB integrity assertions.
- **MISSING:** raw-key open, read-tolerant open, rekey+user_version preservation, atomicity/recovery, marker durability, the open-speed delta, the 5th-site read, plaintext→raw. This plan fills all of it.
- Registration: cipher/db-proof integration tests → `classify_path()` in `check_reliability_simulation_discovery.sh` (not auto-glob).

## Spec Cases (enumerated, falsifiable — §I1)
- **SC-8** (device, PHASE 0, self-contained): raw-key open (`password:"x'<hex>'"`) skips PBKDF2 (latency ≪ passphrase) and round-trips data, on **Android AND iOS**. **SC-8(b):** the same 64-hex as a plain passphrase fails with the SPECIFIC "file is not a database"/HMAC error (not just any exception, §F8). Treat per-platform mechanism divergence (Android vs iOS FMDB) as a first-class SC-8 outcome (§F6).
- **SC-R** (device, PHASE A): the read-tolerant opener SUCCEEDS on both a passphrase DB and a raw DB; a *passphrase-only* open of a raw DB FAILS (documents the one-way boundary + proves the rollback-read path).
- **SC-1** (device): fresh install creates identity.db raw-key + marker=raw. **No-op discriminator on the on-disk fresh DB (§F2):** the created identity.db FAILS to open with the 64-hex as a plain passphrase AND SUCCEEDS raw (NOT `cipher_version`) — proves the create path really wrote raw mode, not a passphrase DB that no-ops the speed check.
- **SC-2** (device): legacy passphrase DB rekeys to raw with **full** preservation — `user_version==95` (§E1), schema-hash unchanged (`MigrationDatabaseSchemaInventory`), full logical checksum (`computeDatabaseChecksumForTesting`) across all ~65 tables (§F3). Opens raw; passphrase-of-64hex FAILS (§F2, NOT `cipher_version`).
- **SC-3** (device): rekey ATOMIC — via a `@visibleForTesting` fault-injection hook in the swap (throws right before/after `File.rename`) so the interrupted-rename branch is driven **deterministically**, not by manual file surgery: inject failure at the swap boundary → next launch recovers an openable DB; truncated/corrupt raw copy → `quick_check` rejects it, intact passphrase original used; crash-after-swap-before-marker → recovery **probes actual cipher mode** (try raw, then passphrase), not blind marker-absence (§F4).
- **SC-4** (device): marker durable across a **REAL restart** (close+evict cache / fresh opener; read persisted marker directly); second launch opens raw directly, `DB_REKEY_TO_RAW_KEY` count == 0 via `debugSetFlowEventSink` (§F5).
- **SC-5** (device-proof, PROD-CRITICAL): **`raw_p50 ≤ passphrase_p50/5` AND `raw_p50 ≤ 15ms`**, N≥5 median, measured on the **2nd steady-state launch** (marker=raw, NO `DB_REKEY_TO_RAW_KEY`), from the `elapsedMs` field bracketing only the `openDatabase` call (§D). The field is **landed in Step 0a FIRST** so both the baseline (denominator) and the fix (numerator) read the *same* field. Extraction is **two ops, not a single regex**: grep the `ENCRYPTED_DB_OPEN_SUCCESS` line, then read `details.elapsedMs` (e.g. `jq '.details.elapsedMs'`) — the two tokens are non-adjacent JSON (`emitFlowEvent` renders `[FLOW] {"ts":…,"event":"ENCRYPTED_DB_OPEN_SUCCESS",…,"details":{"dbName":…,"elapsedMs":N}}`, `flow_event_emitter.dart:208-218`).
- **SC-6** (host, seam-spy): the marker is a **prefix on the `db_encryption_key` record with a two-value domain `{absent, raw}`** — `raw:<hex>` after rekey, and **bare/unprefixed `<hex>` == the `absent` state == legacy-passphrase-not-yet-rekeyed** (the current code writes the key bare at `encrypted_db_opener.dart:77`, so no migration of existing records is needed and **there is NO `pass:` value**). Decision table `(marker,dbExists)` → `(absent,T)→rekey`, `(absent,F)→create raw`, `(raw,T)→open raw`, `(raw,F)→create raw` (§G2); formats key as `x'<hex>'`; a non-64-hex key (after stripping the prefix) emits a DISTINCT event and is a FAILING signal, never a silent passphrase-fallback (§I2).
- **SC-7** (device, **regression SENTINEL — re-scoped §B1**): Move export/import round-trips **UNCHANGED** when identity.db is raw-keyed. Mutation: force the identity.db source open back to passphrase → SC-7 STILL passes (proves Move is decoupled from identity.db's cipher mode; the snapshot is independent). NO exporter/importer edits.
- **SC-9** (device, §F7): a pre-encryption **plaintext** identity.db upgrades to raw-key with all rows + `user_version==95` preserved. **Sequencing DECIDED: direct plaintext→raw** (one `sqlcipher_export` with the destination keyed `KEY "x'<64hex>'"` (67-char blob literal, §H3), NOT `KEY '$key'` — the current template's passphrase form at `encrypted_db_opener.dart:141/:164`), following the §E2 atomic protocol (side-path tmp → verify raw-open + `quick_check` + `user_version==95` → swap). The rejected alternative (plaintext→passphrase→raw) is refused: it would pay PBKDF2 once for nothing. RED reason: HEAD `_encryptExistingDatabase` produces a **passphrase** DB (`KEY '$key'`), so the on-disk result FAILS a raw open. Mutation: revert the ATTACH KEY to the passphrase form → SC-9 RED.
- **SC-B** (device, §B2, **Phase A**): `background_message_handler`'s eligibility read opens a **raw-keyed** identity.db (read-tolerant) and returns state (no `background_local_state_unavailable`). Testable in Phase A by manufacturing a raw DB fixture (like SC-R) — the bg site's read-tolerant change is Phase A; no real Phase-B rekey is needed to prove it reads raw.
- **F1** (device): automated speed gate on the **real** `openEncryptedDatabase` path (not just synthetic SC-8) — reopen once forced-passphrase, once raw (close between to force cold derivation), assert the SC-5 ratio+absolute, wrapping the FULL opener (incl. marker read) so a hot-path regression is caught.
- **INV-5** (literal shell grep-gate, §B2 — **REWRITTEN v3; the v2 co-located grep was provably non-functional**): the v2 form (`grep "password:" … | grep identity`) matched NOTHING because in every multi-line `openDatabase(...)` the `password: key` argument sits on its own line, never sharing a line with `identity.db`/`db_encryption_key` (`encrypted_db_opener.dart:85` vs `:83`; `background_message_handler.dart:300` vs `:299`) → it false-passed over the very 5th site it guards. **v3 gate: a comment-marker convention.** Every `password:` open in `lib` carries a trailing classification marker; the gate fails on any **UNMARKED** `password:` open:
  ```bash
  ! grep -rn "password:" lib --include="*.dart" \
    | grep -vE "RAW_KEY|LEGACY_PASSPHRASE_FALLBACK|SNAPSHOT_PASSPHRASE|PLAINTEXT_MIGRATION"
  ```
  (glob **quoted** so zsh does not pre-glob `*.dart` and error.) Markers: `RAW_KEY` = raw `x'<hex>'` opens; `LEGACY_PASSPHRASE_FALLBACK` = the read-tolerant opener's passphrase branch (`opener:85`, `bg:300`); `SNAPSHOT_PASSPHRASE` = Move snapshot/probe opens (`exporter:164/:275`, `import_staging:185`); `PLAINTEXT_MIGRATION` = plaintext-temp opens (`opener:157/:162`). **RED-before-fix acceptance:** on HEAD (no markers) the gate MUST flag all 7 sites; after Phase A/B it passes; a future unmarked `password:` open re-trips it. Shell gate, not a Dart test (SC-6 can't grep the tree).

## Test Coverage Matrix (zero empty cells)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| SC-8 feasibility | real cipher, mechanism | device | `db_raw_key_migration_proof_test.dart::SC-8` | no raw path; passphrase-of-literal not distinguished | revert to `password:key` → latency/mode RED | `flutter test integration_test/db_raw_key_migration_proof_test.dart -d <dev>` | classify_path() |
| SC-R read-tolerant | dual-mode read | device | `…::SC-R` | opener reads only passphrase | drop raw-try branch | same | classify_path() |
| SC-1 fresh raw | create-mode | device | `…::SC-1` | fresh DB is passphrase | force passphrase create | same | classify_path() |
| SC-2 rekey preserves | data durability (full) | device | `…::SC-2` | HEAD never rekeys | revert rekey / drop user_version set | same | classify_path() |
| SC-3 atomic/no-brick | destructive-action safety | device | `…::SC-3` | no backup/recovery | remove backup-swap | same | classify_path() |
| SC-4 marker durable | lifecycle/derived-state | device | `…::SC-4` | no marker; re-rekeys | non-persistent marker | same | classify_path() |
| SC-5 speed | perf (**PROD-CRITICAL**) | device-proof | manual FDC_FLOW_LOG `elapsedMs` | ~passphrase p50 on HEAD | revert raw open | build `--dart-define=FDC_FLOW_LOG=1`; raw_p50≤pass/5 & ≤15ms | manual device-proof |
| SC-6 wiring | decision logic (seam) | host | `encrypted_db_opener_mode_selection_test.dart::SC-6` | passphrase unconditional | hardcode passphrase branch | `flutter test test/core/database/encrypted_db_opener_mode_selection_test.dart` | AUTO (`test/core/**`) |
| SC-7 Move sentinel | sibling-surface (decoupling) | device | `…::SC-7` | (GREEN — sentinel; RED only if a dev switches snapshot to raw) | force source→passphrase → STILL passes | `flutter test integration_test/account_migration_scale_benchmark_test.dart -d <dev>` | classify_path() |
| SC-9 plaintext→raw | legacy upgrade | device | `…::SC-9` | HEAD template writes passphrase DB → raw open fails | revert ATTACH KEY to passphrase form | same | classify_path() |
| SC-B 5th site | OS-boundary (bg push) | device | `…::SC-B` | :298 passphrase-only; breaks post-rekey | revert :298 to passphrase | same | classify_path() |
| F1 real-path speed | perf regression guard | device | `…::F1` | no raw path | revert raw open | same | classify_path() |
| INV-5 grep-gate | scope completeness | shell gate | `scripts/*` grep over lib/** | HEAD: all 7 `password:` opens UNMARKED → gate RED | remove a marker from any intentional open → RED | `! grep -rn "password:" lib --include="*.dart" \| grep -vE "RAW_KEY\|LEGACY_PASSPHRASE_FALLBACK\|SNAPSHOT_PASSPHRASE\|PLAINTEXT_MIGRATION"` | add to a run_test_gates step |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** the cipher-mode marker MUST survive a real process restart → **SC-4** (real-restart, persisted-marker read) + **SC-6** decision table incl. `(raw, dbAbsent)` reinstall (§G2).
- **Sibling-surface consistency:** ALL identity.db open sites raw-aware — opener (:82/:85) + 3 smoke (inherit) + **background_message_handler:300 (SC-B)** + Move via shared handle (SC-7 sentinel, NO edit). Enforced by the **rewritten INV-5 comment-marker shell gate** (fails on any UNMARKED `password:` open — the v2 co-located grep was provably false; not a Dart test).
- **Destructive-action side-effects:** the rekey swaps the identity.db file — **SC-3** asserts the explicit protocol (§E2): side-path tmp → verify openable+`quick_check`+sentinel-row → back up original `.pre-raw.bak` → close+evict ALL handles + sidecars (`-wal/-shm/-journal`, §E4) → `File.rename` → set marker → delete `.bak`; leftover `.tmp/.bak` recovered next launch.
- **Invariant re-verification under new transitions:** the rekey preserves the FULL DB — **SC-2** asserts `user_version==95` (§E1) + schema-hash + full checksum (~65 tables, §F3), and the DB still opens for every repository post-rekey.

## Invariants (locked by tests)
- INV-1: identity.db opens raw-key, PBKDF2 skipped → SC-8 + SC-5.
- INV-2: rekey preserves ALL data incl. `user_version==95` → SC-2.
- INV-3: rekey atomic — failure never bricks → SC-3.
- INV-4: marker durable; rekey once-only → SC-4/SC-6.
- INV-5: every identity.db open site raw-aware (incl. bg :300) → comment-marker shell gate (no UNMARKED `password:` open) + SC-B.
- INV-6: Move snapshot stays passphrase; Move decoupled from identity.db mode → SC-7 sentinel.
- INV-7: rollback-safe — a Phase-A build reads both modes → SC-R.
- INV-RED-FIRST + INV-MUTATION-VERIFIED apply; **SC-8 GO gates the prod edit.**

## Step-By-Step Implementation Plan
0. **(0a) Instrument FIRST (§D1):** wrap the `openDatabase` call in a `Stopwatch` and emit `elapsedMs` on `ENCRYPTED_DB_OPEN_SUCCESS` (behavior-neutral; mirror `posts_db_helpers.dart:6-19`). This lands BEFORE the baseline so the passphrase baseline (denominator) and the raw fix (numerator) read the **same** `elapsedMs` field — v2's Step-0 command greps a field HEAD did not emit. **(0b) Baseline (§D4):** on the instrumented pre-fix build, same devices, N=10 cold starts (airplane mode + 30s settle), record passphrase open-delta p50 (prove the ~503ms, not assert it — extract `details.elapsedMs` via `jq`, tokens are non-adjacent JSON). Snapshot `git status --short` (dirty baseline: startup_router/first_time_experience prior-session, graph files — do NOT revert).
1. **SC-8 FIRST** (device, self-contained — mechanism inlined, zero prod dep, §C4): confirm `password:"x'<hex>'"` skips PBKDF2 on Android AND iOS (mechanism is verified-sound but bind-confirm empirically). **Must read GO** before any prod edit. If neither mechanism skips PBKDF2 → STOP.
2. **Phase A / 218-pre** — make `encrypted_db_opener.dart:82` and `background_message_handler.dart:298` **read-tolerant** (try raw, fall back to passphrase; no rekey, no marker). RED: SC-R, SC-B. Ship this as the floor. Scope Guard: do not land Phase B until A is shipped.
3. **Phase B**, sliced RED→GREEN→**pause for review**→next (§C1), author each slice's RED just-in-time:
   - **4a** fresh-install raw create + durable marker (SC-1/4/6). Lowest risk. **Take the early speed reading here** (§C2, fresh install, FDC_FLOW_LOG).
   - **4b** legacy **atomic rekey** + backup-swap (SC-2/3) — the brick risk, reviewed in isolation: set `user_version=95` explicitly (§E1); protocol per §E2 (with a `@visibleForTesting` fault-injection hook so SC-3's interrupted-rename branch is driven deterministically, not by manual file surgery); `singleInstance:false` for rekey opens + close/evict (§E3); sidecars (§E4); guard against a concurrent background-isolate read during the swap (bg:300 reader tolerates `ENOENT` + retries; the `:340` catch already degrades gracefully); marker written as `raw:<hex>` in the `db_encryption_key` record (bare/unprefixed = legacy `absent`; **NO `pass:` value** — §G1/SC-6). **Must read GO.**
   - **4c** Move regression sentinel (SC-7) — no exporter/importer edits.
4. Mechanism (**primary only — NO fallback, §H2 DROPPED**): `password:"x'<64hex>'"` for both the read-tolerant open and the raw create; rekey/plaintext ATTACH dest rendered `KEY "x'<64hex>'"` (67-char blob literal, §H3), never the passphrase `KEY '$key'` form. A failing SC-8 is a **STOP**, not a fall-back.
5. Markers (INV-5): add a trailing classification marker to **every** `password:` open in `lib` — `RAW_KEY` / `LEGACY_PASSPHRASE_FALLBACK` (opener:85, bg:300) / `SNAPSHOT_PASSPHRASE` (exporter:164/:275, import_staging:185) / `PLAINTEXT_MIGRATION` (opener:157/:162). Prove the gate RED-flags all 7 on HEAD before Phase A.
6. Rerun all SC (device) + host SC-6 GREEN. Preservation: Move sentinel, capability test, schema migrations GREEN. SC-5 on Pixel AND iPhone (§F6, iOS via `flutter clean &&`). `flutter analyze` 0 new; `git diff --check`; INV-5 marker gate clean (fails on any UNMARKED `password:`). Graph hygiene.

## Risks And Edge Cases
- **Rollback bricks identity (top risk, §A):** two-release forward-compat floor + SC-R.
- **user_version=0 re-runs migrations (§E1):** explicit set + SC-2 assertion.
- **Bricking on failed rekey (§E2):** side-path + verify-before-swap + `.bak` + recovery.
- **Stale singleInstance handle (§E3):** `singleInstance:false` for rekey opens + evict.
- **Partial win (§D5):** if mechanism works but `raw_p50 > passphrase_p50/5` (or >15ms), STOP and re-diagnose which fraction of the 503ms is actually PBKDF2 — don't ship a half-win as done.
- **iOS/Android divergence (§F6):** SC-8/2/3/F1 on BOTH (iOS via `flutter clean &&`); per-platform key path a first-class SC-8 outcome. **No `sqlite3`-package fallback exists to have a divergent iOS story (§H2 DROPPED).**
- **Non-64-hex legacy key (§I2):** distinct event, FAILING signal in SC-6.
- **Background-isolate reads identity.db mid-swap (re-review, un-raised in v2):** `background_message_handler.dart:300` opens identity.db in a **separate Android background process**; an FCM push during Phase B's `File.rename` swap window can hit a half-renamed/absent file. `singleInstance:false` does not guard a cross-process rename. Mitigation: same-directory atomic rename + the bg reader tolerates `ENOENT` and retries; the `:340` catch already degrades to a suppressed push (blast radius = one push during a one-time sub-second window). Add a concurrent-bg-read-during-swap test case.
- **Storage during rekey (re-review):** the §E2 protocol holds THREE copies (original + `.rekey-tmp` + `.pre-raw.bak`) simultaneously and the `sqlcipher_export` time is unbounded on a large identity.db (~65 tables). Pre-flight a free-space check; on failure, **abort the rekey and stay passphrase** (read-tolerant floor still opens it), retry next launch.
- **Baseline field timing (re-review, §D1):** `elapsedMs` is instrumented in Step 0a FIRST so the HEAD passphrase baseline is actually capturable (v2 greps a field HEAD did not emit).
- **Marker/decision-table consistency (re-review):** marker domain is `{absent(=bare legacy), raw}` only — there is **no `pass:` value**; `(pass,*)` states do not exist (SC-6).

## Device/Relay Proof Profile
**Requires device — cipher is device-only.** Closure = the `db_raw_key_migration_proof_test.dart` suite + SC-5 speed device-proof on **Pixel 6 (`21071FDF600CSC`) AND an iPhone** (`00008030-001A6D2801BB802E`; iOS build needs `flutter clean` per `feedback_ios_build_clean`). PROD-CRITICAL = SC-5 + SC-2. No relay/network.

## Acceptance Gates (literal)
```bash
# Step 0a instrument FIRST (behavior-neutral) + 0b baseline (N=10) — prove the ~503ms
flutter build apk --release --dart-define=FDC_FLOW_LOG=1   # instrumented pre-fix build; extract details.elapsedMs via jq from ENCRYPTED_DB_OPEN_SUCCESS lines (NOT a single-regex grep — tokens are non-adjacent JSON); discard launches with DB_REKEY_TO_RAW_KEY

# SC-8 feasibility GATE — FIRST, both platforms, before any prod edit
flutter test integration_test/db_raw_key_migration_proof_test.dart -d 21071FDF600CSC --plain-name 'SC-8'
flutter clean && flutter test integration_test/db_raw_key_migration_proof_test.dart -d 00008030-001A6D2801BB802E --plain-name 'SC-8'   # iOS build needs flutter clean (feedback_ios_build_clean)

# RED (before edits) — device suite + host SC-6 must FAIL for documented reasons
flutter test integration_test/db_raw_key_migration_proof_test.dart -d 21071FDF600CSC
flutter test test/core/database/encrypted_db_opener_mode_selection_test.dart

# Direct GREEN (after fix) — device + host
flutter test integration_test/db_raw_key_migration_proof_test.dart -d 21071FDF600CSC
flutter clean && flutter test integration_test/db_raw_key_migration_proof_test.dart -d 00008030-001A6D2801BB802E   # iOS: runs SC-8/SC-2/SC-3/F1 on iPhone; flutter clean prereq
flutter test test/core/database/encrypted_db_opener_mode_selection_test.dart

# Preservation sentinels
flutter test integration_test/migration_database_sqlcipher_capability_test.dart -d 21071FDF600CSC
flutter test integration_test/account_migration_scale_benchmark_test.dart -d 21071FDF600CSC   # SC-7 Move sentinel
./scripts/run_host_test_gates.sh core-host-all      # schema migrations + SC-6

# INV-5 scope gate (comment-marker convention — FAILS on any UNMARKED password: open; glob quoted so zsh does not pre-glob)
#   on HEAD this MUST flag all 7 password: sites (none marked yet); after Phase A/B it returns clean
! grep -rn "password:" lib --include="*.dart" | grep -vE "RAW_KEY|LEGACY_PASSPHRASE_FALLBACK|SNAPSHOT_PASSPHRASE|PLAINTEXT_MIGRATION"

# Speed device-proof (SC-5) — both platforms, 2nd steady launch, N>=5
#   two ops (tokens are non-adjacent JSON): grep ENCRYPTED_DB_OPEN_SUCCESS lines, then jq '.details.elapsedMs'; discard any launch with DB_REKEY_TO_RAW_KEY
#   PASS iff raw_p50 <= passphrase_p50/5 AND raw_p50 <= 15ms

# Discovery + hygiene
./scripts/check_reliability_simulation_discovery.sh   # new device test MUST list
flutter analyze            # 0 new
git diff --check
```

## Known-Failure Interpretation
- Expected RED: SC-1..9/R/B before the fix; SC-8 also *informs* the mechanism.
- SC-7 is GREEN-by-design (sentinel) — it reds only if a dev switches the snapshot to raw.
- Pre-existing dirty: startup_router / first_time_experience (prior session) — do NOT revert.
- Environment blocker (NOT product): no device → device suite unrunnable; host SC-6 gates wiring, but **device closure is MANDATORY** (cipher is device-only; host-green-only is NOT sufficient).
- Scope drift (BLOCKING): touching the Move snapshot cipher mode, node-start ordering, or any schema/version bump.

## Done Criteria
- [ ] Step 0a elapsedMs instrumented FIRST; Step 0b baseline captured; SC-8 GO on Android AND iOS (or STOP).
- [ ] Phase A (read-tolerant, incl. 5th site) **shipped + soaked** as the floor before Phase B (the Phase-A-RELEASED GO row).
- [ ] RED first, mutation-verified; device suite GREEN on Pixel AND iPhone; host SC-6 green.
- [ ] SC-2 asserts `user_version==95` + schema-hash + full checksum; SC-3 atomic recovery proven.
- [ ] SC-5: `raw_p50 ≤ passphrase_p50/5` AND `≤15ms`, both platforms; SC-7 Move sentinel green; SC-B bg-push green.
- [ ] INV-5 marker gate: RED-flags all 7 `password:` sites on HEAD (proven), clean after Phase A/B; no UNMARKED `password:` open; no secondary fallback opener; no schema/version change; marker durable (`{absent, raw}`).
- [ ] flutter analyze 0 new; git diff --check clean; graphs refreshed.

## Scope Guard (hard "Do not")
- Do NOT land Phase B (rekey) until Phase A (forward-compat read) is the shipped floor (§A3).
- Do NOT touch Move exporter `:164/:253/:275` or importer `:185` — the transfer snapshot stays passphrase-mode ON PURPOSE for cross-device/cross-version compatibility (§B1).
- Do NOT model atomicity on `_encryptExistingDatabase` (deletes original before dest proven) — use the §E2 protocol.
- Do NOT add ANY secondary opener fallback — neither the `onConfigure PRAGMA key` form (native validates first) NOR the `sqlite3` package (transitive-only, no cipher-lib binding → would write a PLAINTEXT identity.db). The primary `password:"x'<64hex>'"` is the SOLE mechanism, gated by SC-8: a failing SC-8 = **STOP-and-re-diagnose**, never fall-back (§H2 DROPPED, re-review 2026-07-06).
- Do NOT bump identity.db schema version / add a DB v## (cipher-param only).
- Do NOT touch node-start ordering / Firebase / mlkem (Change 2, separate plan).
- Do NOT delete the passphrase original until the raw copy is proven openable.

## Accepted Differences / Intentionally Out Of Scope
- Change 2 (de-serialize node:start, the other ~0.5s) — separate plan.
- Relay-proximity / edge-PoP (the ~249ms network floor) — infra, not app.
- Phase A and Phase B MAY be filed as separate NNs (218-pre / 218) if the team prefers per-release docs; kept here as one coherent plan with the ship gate.

## Dependency Impact
- None outward; repositories' identity.db contract unchanged. Faster cold start every launch; Move + background push preserved.

## Reviewer Findings
- **v1 → v2:** 7-agent review `218-review-fixlist.md` (v1 NOT execution-ready) — §A rollback / §B scope / §E user_version / §H mechanism source-verified (wf_b5c4c901-4e9) and applied.
- **v2 → v3 (this doc):** /tdd-review re-audit (wf_2b86d6a6-5cd, 8 agents + orchestrator source-verification, 2026-07-06). Verdict: v2 correctly closed the heavyweight structural fixes (33/39 fix-list items) but was **NOT execution-ready** — 5 material residuals. Scores: D1 82 / D2 88 / D3 76 / D4 89 / D5 80; core bet **verified sound**. The 5 residuals, now closed in v3:
  1. **INV-5 gate provably non-functional** (both v2 grep forms matched nothing on HEAD — `password:` never shares a line with the identity/key tokens) → rewritten to a **comment-marker convention** with a RED-on-HEAD acceptance.
  2. **§H2 `sqlite3` fallback** unimplementable (transitive-only, no cipher-lib binding) and could silently ship a PLAINTEXT identity.db → **fallback DROPPED** (user decision); primary-only, SC-8 is the sole go/no-go.
  3. **SC-9 plaintext→raw sequencing** was an undecided fork → **DECIDED direct plaintext→raw** with the raw-literal ATTACH KEY.
  4. **SC-5 baseline field** un-capturable on HEAD (elapsedMs added only in Step 4) → **instrument in Step 0a FIRST**; two-op `jq` extraction.
  5. **Marker value-set** (`raw:`/`pass:`) contradicted its `{absent, raw}` decision table → **`pass:` dropped**; bare/legacy = `absent`.
  Plus tightening: Phase-A-RELEASED checkpoint row, SC-1 on-disk discriminator, SC-3 fault-injection seam, background-isolate/rename-race guard, storage-window abort, iOS `flutter clean`, `single-digit ms` reconciled.

## Arbiter Decision
v3 closes all 5 material residuals + the tightening items; core bet verified sound. **READY for execution** (SC-8 GO gates the prod edit; Phase A must be the shipped floor before Phase B). Remaining sub-tasks are execution-time, not planning gaps.

## Final Execution Verdict
<pending execution>
