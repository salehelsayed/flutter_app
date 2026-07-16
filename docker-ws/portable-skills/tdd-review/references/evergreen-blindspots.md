# Evergreen Blind-Spot Sweep (read in Step 2/4 — force these into the critic; sweep EVERY plan)

These are the material blockers review keeps finding **after the fact** — they are rarely named by the plan itself, so the dimension agents can score a plan "adequate" while one of these sits unaddressed. Sweep **every** plan for all of them regardless of what it enumerates. For each: state **hit** (with `file:line` proof + fix) or **clear / N-A** (with a one-line reason). Never skip silently.

Each class carries a condensed real-world example (from a database re-keying migration audit) so the pattern is concrete.

---

## B-1. One-way / irreversible change → rollback / downgrade brick
**The class:** the plan performs an irreversible data/format migration, but the currently-shipped (prior) build only understands the OLD format. A routine rollback (hotfix revert, store rollback) then meets migrated data the old build can't read.
**Why it's missed:** the plan guards the *forward* migration ("atomic, no brick during conversion") and never considers the *backward* direction.
**Detect:** Is the change one-way? What does the *prior shipped build* do when it opens post-migration data? Is there a reverse path, a kill-switch, a staged/canary rollout, or a forward-compat-read release shipped FIRST? Is the migrated data recoverable if lost (does it hold keys/identity/user records)?
**Example:** a passphrase→raw-key DB conversion was one-way; the prior build could only open passphrase-mode DBs; a rollback would have bricked every migrated install (the DB held the account's private key → unrecoverable). Fix chosen: ship a forward-compat "read both formats" opener in a PRIOR release, then convert in the next.

## B-2. Undercounted callers / sibling open-sites (the one that does NOT inherit)
**The class:** the plan says "N callers inherit this change automatically." The real count is higher, and at least one site does the operation *directly* (not through the shared seam) so it does NOT inherit — and breaks post-change.
**Why it's missed:** the plan greps for the wrapper function and stops; it misses direct/duplicated call sites and background/OS-entrypoint paths (push handlers, background workers, secondary processes, CLI tools).
**Detect:** grep EVERY call site of the operation across the whole codebase — including background handlers, secondary entrypoints, and scripts — AND direct raw calls that bypass the wrapper. The site that uses the same secret/resource but a different entry is the landmine.
**Example:** the plan said "4 callers"; the real count was ~11, and a background message handler opened the DB via a DIRECT raw call using the same secret — it would have broken background processing after the conversion; the plan's invariant "all sites use the new mode" was provably false.

## B-3. Off-target line numbers (precise-but-wrong is worse than vague)
**The class:** the plan cites exact `file:line` targets to edit, but those lines don't do what the plan claims — they operate on a different object/resource/key. Editing them is unnecessary and often actively breaks something.
**Why it's missed:** the line numbers *look* authoritative, so they're trusted without reading them.
**Detect:** read every cited line. Confirm it operates on the object the plan says. Be especially suspicious of "**these must all change together or X breaks**" framings — often the object is a shared wire-format/transient artifact where changing it is *itself* the break.
**Example:** the plan told the executor to convert four cited lines in an export/import path — but the resource entered that path as an already-open handle (inheriting the change for free), and the cited lines actually keyed a capability-probe and a cross-version transfer snapshot. Converting them would have BROKEN cross-version transfers. The correct action was to delete those edits from the plan.

## B-4. Un-verifiable goal/perf gate (green without the real win)
**The class:** the metric the plan exists to move has no crisp, runnable, automated gate — so an executor can declare "done" without proving it, and a silent regression later ships undetected.
**Why it's missed:** perf is treated as a manual "eyeball the log once" at the end.
**Detect, four sub-checks:**
- **Field exists?** Does the acceptance command grep a log field the code actually emits? (Often it greps `elapsed` while the code emits only `START`/`SUCCESS` timestamps → matches nothing.)
- **Right run?** Is the measured run the steady-state one, not the (legitimately slower) one-time migration run that yields a false FAIL?
- **Baseline captured?** Is the "was ~Xms" re-measured on the same build/environment/N/percentile, or just remembered?
- **Automated regression gate?** Is there a standing test that fails if the win silently reverts — or only a human re-grep?
**Example:** a plan carried three inconsistent targets; its gate grepped an `elapsed` field the opener never emitted; it measured the (slower) migration launch; the baseline was a remembered "~500ms"; there was no automated gate. Fix: emit a real timing field, commit one hard number (`new_p50 ≤ old_p50/5` AND `≤15ms`), measure the second launch, and add a standing real-path assertion.

## B-5. Migration atomicity + derived-state preservation
**The class:** a DB/file migration loses a derived property (schema version, WAL/journal sidecars, a header field) or isn't crash-atomic, so it corrupts or bricks on interruption.
**Why it's missed:** "copy the data" is assumed to copy everything; the failure test injects the safe case.
**Detect:** Does the copy/export preserve the schema-version marker (else the reopened DB re-runs all migrations over live data)? Are sidecar files (`-wal`/`-shm`/`-journal`, lock files) handled? Is the swap **verify-then-swap** (build side-file → integrity-check → back up original → atomic rename → set marker), or delete-then-rewrite? Is there a connection/handle cache that can hand back a stale handle after the swap? Does the atomicity test inject failure **at the swap boundary** (and truncated-copy, and crash-after-swap-before-marker), not just before anything is touched? Beware "**model on existing code X**" when X is itself non-atomic.
**Example:** the engine's export primitive didn't copy the schema-version pragma; the "model on this" template deleted the original before the destination was proven and exported twice; the plan's only failure test faulted the pre-swap (safe) case; a singleton connection cache could return a stale pre-swap handle.

## B-6. Durable-marker / flag survival across restart · reinstall · restore
**The class:** the plan gates behavior on an "already done" flag whose durability isn't specified, so it re-runs every launch, mis-selects a branch, or desyncs from the data it describes.
**Why it's missed:** the flag is treated as trivially persistent; tests reopen in the same process.
**Detect:** Where is the flag stored, and does it share the **backup/lifecycle domain** of the data it describes? (A keystore/keychain flag can survive uninstall while the data file it describes is wiped or restored — they desync.) Is durability tested across a REAL process restart (not a same-process reopen an in-memory cache can fool)? Is the full `(flag × data-exists)` decision table written down? Does reading the flag add latency on the very hot path being optimized?
**Example:** the marker's storage was never committed ("secure-storage key OR sentinel file") — the fix was to co-locate a sentinel WITH the data file so they share a lifecycle, and to require a real-restart durability test.

## B-7. The plan's own stated #1 risk — domain-verify it (and its fallback)
**The class:** the plan names a top technical risk and a fallback. Both deserve independent domain verification: the stated risk is often a **misconception** (good news — de-risks the plan), and the documented **fallback is often unsound** (false comfort that could ship something broken).
**Why it's missed:** the plan's risk framing is taken at face value; nobody reads the dependency/native source.
**Detect:** WebSearch the domain claim AND read the actual library/dependency/native source. Does the mechanism behave as feared? Does the fallback actually work given the real call ordering (e.g. does a validation query run before the callback that would have configured the key)?
**Example:** the plan's feared library behavior turned out to be a MISCONCEPTION (primary mechanism sound — good news), but its documented fallback was UNSOUND: the native open path validated with a keyed query before the app-level callback ran, so the fallback would throw on real data — or worse, create a plaintext file. The fallback had to be replaced, not the mechanism.

## B-8. PROD-CRITICAL leg proven only manually / only fast-tests-green
**The class:** the single path that proves the deliverable (the wire/transport/crypto/OS-boundary leg) has no standing automated guard, or is "proven" by fast tests that can't exercise the real boundary.
**Detect:** Is the PROD-CRITICAL leg named? Is it guarded by a real E2E/environment test, or a one-time manual observation? For crypto/OS-boundary/external-system claims, is "fast tests green" being treated as closure when those tests use a fake (an in-memory stand-in, not the real engine; a stub client, not the real service)?
**Example:** the real performance win was guarded only by a one-time manual log eyeball; the automated test measured a synthetic fixture, not the real production opener → a full revert of the change would still have passed every automated test.

## B-9. "What stays unchanged / accepted difference" = untested assumption
**The class:** a "these stay green" / "accepted difference" / "out of scope, unaffected" claim is asserted but no test guards it — exactly where latent bugs hide. (Same ethos as `tdd-plan`'s blind-spot sweep.)
**Detect:** For each "unchanged"/"unaffected" claim, is there a named preservation sentinel (suite + gate cmd + expected count) that would go red if it were violated? A documented-but-unverified invariant is a gap.

## B-10. Cross-platform / cross-version parity asserted in prose, not run
**The class:** "works on the other platform too" / "compatible with the old build" stated but not exercised, when the underlying path or the persisted/wire format actually diverges.
**Detect:** Is there a concrete target id + literal command for each platform/environment leg? Is a per-platform mechanism divergence treated as a first-class outcome? For any persisted or cross-process format, is there a new-build↔old-build round-trip case?
**Example:** "both platforms" was asserted in the Done-criteria but every literal gate hardcoded one platform's device — while the two platforms routed the key through different native code paths.

---

**Sweep output shape** (feed to the report): a short table — `class | hit? | evidence (file:line) | fix`. Any B-class **hit** that is a brick/silent-break/un-verifiable-done is a **material blocker**, ranked in Step 4.
