# 218 Review — Fix-List (apply against `218-sqlcipher-raw-key-coldstart-tdd-plan.md`)

Source: 7-agent review + orchestrator source-verification, 2026-07-06. Plan is **not execution-ready** as written;
core physics is verified sound. Apply the items below to 218, then re-run the sufficiency pass.

Decisions locked with the user:
- **Rollback safety = forward-compat opener FIRST** (two-release strategy; see §A).
- **SC-5 speed gate = ratio + absolute**: `raw_p50 ≤ passphrase_p50 / 5` AND `raw_p50 ≤ 15ms`, N≥5 median, measured on the
  2nd steady-state launch (marker=raw, no `DB_REKEY_TO_RAW_KEY`), from a newly-emitted `elapsedMs` field.

Verified facts this list relies on (checked against source):
- `encrypted_db_opener.dart:82` passphrase open; `_generateRandomKey :12-16` = full-entropy 64-hex. ✅
- Move `exportSnapshot({required Database sourceDb})` gets identity.db as an ALREADY-OPEN handle
  (`main.dart:2001 sourceDb: db` → `bundle_transfer.dart:207` → exporter `:92`). Move inherits raw-key for free. ✅
- 5th open site: `background_message_handler.dart:26` (`'db_encryption_key'`) + `:298-301`
  `openDatabase('$dbPath/identity.db', password: key, readOnly: true)` — direct, NOT via the opener. ✅
- Bundled engine SQLCipher 4.10.0; resolved plugin `sqflite_sqlcipher 3.4.0` (pubspec says `^3.1.0+1`). ✅

---

## §A — Rollback safety (NEW section; biggest un-raised risk)

The passphrase→raw rekey is ONE-WAY; a TestFlight rollback would brick migrated identities (identity.db holds the node
private key → account unrecoverable, not just chat history). Adopt the two-release forward-compat plan:

- **A1.** Split 218 into **218-pre (forward-compat opener)** and **218 (rekey)**:
  - **218-pre** ships FIRST and only makes every identity.db open site **read-tolerant**: try raw `x'<hex>'`, and on
    key-derivation failure fall back to passphrase (`password: key`). No rekey, no marker flip. This lets a build read
    BOTH modes, so a later rollback from 218 → 218-pre still opens a raw-keyed DB.
  - **218** (this plan) then performs the rekey + marker flip, gated on 218-pre being the installed floor.
- **A2.** Add **SC-R (device):** a passphrase-mode open of a rekeyed DB FAILS, but the 218-pre read-tolerant opener SUCCEEDS
  on both a passphrase DB and a rekeyed DB. Documents the one-way boundary AND proves the rollback path.
- **A3.** Add to Scope Guard: "Do not land 218 (rekey) until 218-pre (forward-compat read) is the shipped floor."
- **A4.** State in the goal/why (addresses the "why preserve data" gap): "Rekey (not fresh key) is mandatory because
  identity.db holds the node private key — regenerating it destroys the account identity irrecoverably."

---

## §B — Scope corrections (two verified errors that would break working features)

- **B1. DELETE the Move exporter/importer edits (step 4d + SC-7 as written).**
  ("**Move**" = the account-migration feature — transferring your account/identity from one phone to a new one,
  `lib/features/account_migration/`. `migration_database_snapshot_exporter.dart` = the old device exporting a transfer
  snapshot; `migration_database_import_staging.dart` = the new device importing it.)

  **Why identity.db already inherits raw-key with zero Move edits:** identity.db is opened ONCE by the main opener at
  `main.dart:481` and handed to Move as an **already-open handle** — `exportSnapshot({required Database sourceDb})`
  (`exporter:92`), fed by `main.dart:2001 sourceDb: db` → `bundle_transfer.dart:207`. Move reads identity.db *through*
  that handle and never re-opens it, so when identity.db goes raw-key, Move reads it correctly for free (same as the
  smoke callers). The lines the plan flagged (`:164/:253/:275` exporter, `:185` importer) do NOT open identity.db —
  they open OTHER, transient DBs:
  - `exporter:164` opens a **throwaway capability-probe DB** (`sqlcipher-capability-source.db`, `probeSqlCipherExportCapability` `:149-167`)
    with a hardcoded literal key `const key = 'mig004-capability-key'` (`:154`) — not the identity key, not 64-hex, so
    `x'mig004-capability-key'` would be a MALFORMED raw literal.
  - `exporter:253` (ATTACH) + `:275` (open exported) + `import_staging:185` key the **transfer SNAPSHOT** with
    `destinationKey`/`stagedKey`. That snapshot is a **cross-device, cross-VERSION wire format**: the sending and
    receiving phones may be on different app builds. It MUST stay **passphrase-mode on purpose** — a 218 phone writing a
    raw-key snapshot to a receiver still on a passphrase build (or the reverse) fails to import. So switching the snapshot's
    cipher mode is *itself* the break the plan claims to prevent.

  Actions:
  - Remove `:164/:253/:275/:185` from Root Cause (`:41`), Real Scope (`:50`), and Blind-Spot Sweep (`:114`); correct the
    plan's inverted framing ("all must switch to raw-key together or Move breaks" → "the Move snapshot stays passphrase;
    only the identity.db LOCAL open goes raw, and Move inherits that via the shared `sourceDb` handle").
  - Add to Scope Guard: "Do NOT touch exporter `:164/:253/:275` or importer `:185`; the Move transfer snapshot stays
    passphrase-mode ON PURPOSE for cross-device/cross-version compatibility."
  - **Re-scope SC-7** from an edit to a *regression sentinel*: "Move export/import round-trips UNCHANGED when identity.db
    is raw-keyed" (mutation: force the source open back to passphrase → SC-7 STILL passes, proving Move is decoupled from
    identity.db's cipher mode). Drop the false RED reason ("passphrase-only exporter fails to open a raw-keyed DB" — it
    never opens identity.db). This sentinel also guards against a future dev "helpfully" switching the snapshot to raw and
    silently breaking cross-version transfers.
  - Note: the kdf_iter-metadata worry is a NON-issue — `PRAGMA kdf_iter` reports the configured default (256000)
    regardless of key mode, and the snapshot is self-consistent passphrase. No re-scope to that path needed.

- **B2. ADD the 5th open site to scope.** `background_message_handler.dart:298-301` opens identity.db directly in
  passphrase mode (same `'db_encryption_key'` secret, `:26`) and does NOT inherit the opener change → Android
  background-FCM group-mute/eligibility path breaks after rekey (`background_local_state_unavailable`).
  - Add `lib/features/push/application/background_message_handler.dart:298` to Real Scope + the sibling-surface sweep.
  - Switch it to the read-tolerant open (§A1) in 218-pre; it needs no rekey logic (readOnly).
  - **Add SC-B (device):** after a rekey, the background-eligibility read still opens identity.db and returns state.
  - **Fix INV-5:** it is currently provably false. Make its grep-gate a **literal runnable shell command** over `lib/**`
    (incl. `lib/features/push/**`) asserting no `password: key` open of identity.db remains except the single
    legacy-passphrase-before-rekey site — not a Dart unit test (SC-6 can't grep the tree).

---

## §C — Compartmentalize the production edit (agile / tight buckets + checkpoints)

- **C1.** Split Step 4 (`:130`) into three slices, each RED→GREEN→**pause for review**→next; author each slice's RED
  just-in-time (not all SC-1..7 at once in Step 3):
  - **4a** fresh-install raw open + durable marker (gates SC-1/4/6). Lowest risk.
  - **4b** legacy atomic rekey + backup-swap (gates SC-2/3). The brick risk — reviewed in isolation.
  - **4c** Move regression sentinel (gates re-scoped SC-7).
- **C2.** Add an **early cold-start speed reading immediately after 4a** (fresh install, FDC_FLOW_LOG) so the payoff is
  observed at the earliest point, not deferred to the final step behind rekey/Move work it doesn't depend on.
- **C3.** Add a **GO/STOP signoff column** to the Execution Progress table (`:14-24`); require the SC-8 row to read GO
  before the implementation row may be filled. Give 4a/4b/4c their own rows.
- **C4.** State in Step 2 that the SC-8 probe is **self-contained** (candidate mechanism inlined in the test, zero
  production dependency) so it provably runs before any prod edit.

---

## §D — Speed gate + instrumentation (eval criteria "define good with precision")

- **D1.** Add an implementation step: wrap the `openDatabase` call in a `Stopwatch` and emit `ENCRYPTED_DB_OPEN_SUCCESS`
  with an **`elapsedMs`** field (mirror `posts_db_helpers.dart:8-15` / `go_bridge_client.dart:913-931`). The current SC-5
  gate greps `[FLOW] ENCRYPTED_DB_OPEN elapsed` which **matches nothing** (opener emits only START/SUCCESS with ISO `ts`).
- **D2.** Replace all three inconsistent targets ("single-digit ms" `:35/37`, "tens ms" `:23`, "≤~50ms" `:108/184`) with
  the ONE locked gate: **`raw_p50 ≤ passphrase_p50 / 5` AND `raw_p50 ≤ 15ms`**, N≥5 median, 2nd steady-state launch.
  Reconcile every occurrence.
- **D3.** Pin the measurement window: "measure only the 2nd cold start after install/upgrade; discard any launch whose log
  contains `DB_REKEY_TO_RAW_KEY`" (the rekey launch is SLOWER — measuring it yields a false FAIL). Bracket just the
  `openDatabase` call, not the whole function (which also includes secure-storage read + `cipher_version` query).
- **D4.** Add **Step 0: capture the pre-fix baseline** on HEAD, same device, N=10 cold starts, airplane mode + 30s settle;
  record open-delta p50. The current "~503ms" is a remembered number, not re-measured — the 10× claim is otherwise
  asserted, not proven.
- **D5.** Add a **partial-win STOP-if**: if the mechanism works but `raw_p50 > passphrase_p50/5` (or > 15ms), STOP and
  re-diagnose which fraction of the 503ms is actually PBKDF2 (don't ship a half-win as "done").

---

## §E — Rekey correctness: schema-version + atomicity (brick risks)

- **E1. `PRAGMA user_version`:** `sqlcipher_export` does NOT copy it, and the template `_encryptExistingDatabase` never
  sets it → the rekeyed DB can reopen at `user_version=0` and re-run ~95 migrations over live data. Rekey must explicitly
  `PRAGMA <target>.user_version = 95` (or copy it). **SC-2 must assert `user_version == 95` post-rekey.**
- **E2. Do NOT "model atomicity on `_encryptExistingDatabase`."** That template `deleteDatabase(fullPath)` at `:154`
  BEFORE the destination is proven openable (+ double-export). Specify the exact protocol instead:
  `export → side-path (identity.db.rekey-tmp, with sidecars) → verify it opens raw + round-trips a sentinel row + quick_check
  → back up original to identity.db.pre-raw.bak → close+evict ALL handles → File.rename tmp→identity.db → set marker →
  delete .bak on success`. On next launch, detect leftover `.tmp`/`.bak` and recover.
- **E3. `singleInstance` cache eviction:** the opener uses `openDatabase(..., singleInstance:true)` keyed by path; the
  in-call rekey opens/swaps the SAME path, so the final open can return a STALE cached passphrase handle. Explicitly close
  every intermediate handle AND `deleteDatabase(fullPath)` (or use `singleInstance:false` for rekey opens, like the
  migration sites already do at `exporter:166/277`, `import_staging:187`) before the raw reopen.
- **E4. Enumerate `-wal/-shm/-journal` sidecar handling** in the swap (the exporter's `_deleteIfExists` already does this
  for its artifacts; the rekey must too).

---

## §F — Tests that actually profile the goal

- **F1. Automated speed gate on the REAL path (not just synthetic SC-8):** add a device integration test that calls the
  real `openEncryptedDatabase(identity.db, v95)`, reopening once forced-passphrase and once raw (close between opens to
  force cold key-derivation), asserting the D2 ratio+absolute. Wrap the FULL opener (incl. marker read) so a hot-path
  regression is caught. Keep manual FDC_FLOW_LOG as end-to-end sanity, not the sole guard.
- **F2. Real-DB no-op discriminator:** in SC-2 (post-rekey) and SC-4 (fresh) assert the on-disk identity.db FAILS to open
  with the 64-hex as a passphrase AND SUCCEEDS raw. **Drop "cipher_version reports encrypted"** as raw-mode evidence —
  `PRAGMA cipher_version` returns the library version regardless of key mode (a rekey that no-ops to passphrase passes it).
- **F3. Full-DB preservation, not a 3-table sample:** SC-2 asserts (i) `user_version==95`, (ii) schema-hash unchanged via
  `MigrationDatabaseSchemaInventory`, (iii) full logical checksum via the existing
  `MigrationDatabaseImportStaging.computeDatabaseChecksumForTesting` (`import_staging.dart:131`) — identity.db has ~65
  tables, not 3.
- **F4. SC-3 real failure modes:** inject failure AT the swap boundary (raw copy written, rename interrupted) → next launch
  recovers openable; feed a truncated/corrupt raw copy → `quick_check` rejects it, intact passphrase original used;
  crash-after-swap-before-marker → recovery PROBES actual cipher mode (try raw, then passphrase), not blind marker-absence.
- **F5. SC-4 durability across a REAL restart:** don't rely on a same-process reopen (in-memory marker cache would mask a
  non-persistent marker). After run 1, read the persisted marker/sentinel directly; for "second launch" fully close +
  clear the marker cache (or fresh opener instance); install `debugSetFlowEventSink` to count `DB_REKEY_TO_RAW_KEY`
  deterministically.
- **F6. iOS parity as literal gates:** provide a concrete iPhone device id and the literal iOS build/run command
  (+ `flutter clean` prereq); schedule **SC-8, SC-2, SC-3, F1** on iOS explicitly. Treat a per-platform mechanism divergence
  (Android PRAGMA-key vs iOS FMDB setKey→sqlite3_key) as a first-class SC-8 outcome.
- **F7. Legacy plaintext→raw (SC-9, device):** a pre-encryption plaintext identity.db upgrades to raw-key with all rows +
  `user_version` preserved. Currently the plaintext path is named a sentinel (`:38/:50`) with no mapped gate; decide and
  document plaintext→raw sequencing (direct, vs plaintext→passphrase→raw two hops).
- **F8. SC-8(b) specificity:** assert the SPECIFIC "file is not a database" / HMAC error on passphrase-of-literal, not just
  that any exception was thrown (a bad-path failure would spuriously "prove" raw mode).

---

## §G — Marker specification (precision / anti-drift)

- **G1.** Commit ONE marker store — recommend a **sentinel co-located with the DB file** (shares the DB's backup/lifecycle
  domain; avoids the documented iOS-Keychain-survives-uninstall + device-restore cross-domain skew). Name the key/values.
  Alternative that adds ZERO extra cold-start read: fold the mode into the existing stored key record
  (`'raw:<hex>'` vs `'pass:<hex>'` under `db_encryption_key`).
- **G2.** Write the full decision table into SC-6: `(marker, dbExists)` → `(absent,T)→rekey`, `(absent,F)→create raw`,
  `(raw,T)→open raw`, `(raw,F)→create raw`. Add an SC-6 assertion for the `(raw, dbAbsent)` reinstall case.
- **G3.** If a separate marker store is chosen, account for its latency — memory notes Keychain reads are a measured
  cold-start cost (see 164 keychain-mirror). The F1 latency test must wrap the whole opener so any marker-read cost shows.

---

## §H — Mechanism / fallback corrections (domain-verified)

- **H1.** The plan's stated #1 risk ("`sqlite3_key` treats `x'...'` as a passphrase → still PBKDF2") is a MISCONCEPTION —
  `sqlite3_key` follows the same raw-key rules as `PRAGMA key` (Zetetic docs; `SqfliteSqlCipherPlugin.m:655`,
  67-char detection). The primary `password:"x'<hex>'"` mechanism is very likely sound. Down-rank this risk; SC-8 remains
  worthwhile as empirical Android-binding confirmation.
- **H2.** The documented `onConfigure PRAGMA key` fallback is **UNSOUND** — the native open validates with a keyed query
  BEFORE Dart's `onConfigure` runs (iOS `:659 SELECT COUNT(*) FROM sqlite_schema`; Android `Database.java:62`). On an
  encrypted DB the empty-key validate throws (onConfigure never runs); on a fresh DB it can create a PLAINTEXT file.
  **Replace the fallback** with: open identity.db via the already-bundled `sqlite3` package (`sqlcipher_flutter_libs`)
  where `PRAGMA key = x'...'` can be issued as the FIRST statement.
- **H3.** ATTACH-KEY raw format: the rekey's ATTACH destination must be rendered `KEY "x'<64hex>'"` (67-char blob literal),
  NOT `KEY '$key'` (the passphrase form the template uses) — else the dest is passphrase-keyed and the raw open fails.
- **H4.** Note the resolved plugin is **3.4.0** (engine SQLCipher 4.10.0), though pubspec pins `^3.1.0+1` — SC-8 analysis
  should reference the installed version.

---

## §I — Smaller precision fixes

- **I1.** Enumerate SC-1..SC-8 as a short numbered list, each one falsifiable sentence + pass condition; un-merge
  "SC-1/4 once-only" (`:107`) into separate rows/mutations.
- **I2.** Non-64-hex "fall back to passphrase" branch (`:138`) is a latent silent-no-op: emit a distinct event and treat a
  fired passphrase-fallback in production as a FAILING signal in SC-6, not a silent success.
- **I3.** onConfigure ordering (if the sqlite3-package fallback is used): `PRAGMA key` must be the FIRST statement, before
  the existing `busy_timeout` rawQuery (`:97`) and before onCreate/onUpgrade.

---

## Priority order to apply

1. **§A** (rollback — blocks the whole ship model) + **§B** (scope errors — would break Move + background push).
2. **§D + §E** (make the win verifiable and the rekey non-bricking).
3. **§C + §F** (slice the work; make tests guard the goal).
4. **§G + §H + §I** (marker spec, mechanism corrections, cleanup).
