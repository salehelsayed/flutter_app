# 320 - Permanent Push-Error Classification, Dead-Token Eviction Durability, and Wake Measurability (F5 part 1)

Status: execution-ready (v2, /tdd-review applied 2026-08-01 — 3-worker audit `wf_d14e6eae-e53`, **2 blockers** both closed below; the #1 bet is half-confirmed: the relay does NOT wrap the SDK error (typed predicates are reachable), but `NotRegistered` is FCM's *message string*, not the errorCode the predicates read)
Type: Bug
Spec: free-text intent — F5 deferred from plan 315; scope narrowed by live production evidence + a 10-agent verify→refute pass (`wf_c500330c-980`)
Classification: implementation-ready
Closure tier: host (Go host + Dart host); relay binary ships v1.7.5 under the standing deploy authorization

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-01 | Evidence Collector (live relay journal + 10-agent workflow `wf_c500330c-980`) | go-relay-server `inbox.go`/`metrics.go`/`reaction_push.go`/backends, `p2p_service_impl.dart`, push registration coordinator, drain paths | C1/C2/C4 confirmed; **C3 REFUTED — my "production shows zero lost wakes" inference is structurally invalid** | narrow scope |
| 2026-08-01 | Planner (+ host SDK probe `scripts/test/probe_fcm_error_predicates_320.sh`) | `firebase.google.com/go/v4@v4.15.1/messaging/messaging.go` read on the host | the review's "classifier unspecifiable in this tree" blocker is CLEARED — typed predicates confirmed | emit plan, /tdd-review |

## Problem And Evidence

Three confirmed defects, all on the group/1:1 reaction push path. **Re-fan-out-on-duplicate is explicitly OUT (user decision 2026-08-01)** — see Deferred.

- **P1 — a PERMANENT FCM error is treated as transient, and the dead token is never evicted.** `isInvalidTokenError` (go-relay-server/inbox.go:1121-1126) is a hand-rolled, **case-sensitive, two-literal substring test** for `registration-token-not-registered` / `invalid-registration-token` (helpers `contains`/`containsImpl` :1128-1139, no `ToLower`). Production emits the SDK's `NotRegistered`, which matches **neither** — so `sendWithRetry` (:262-387) skips its invalid-token branch (:297-305), walks the transient ladder (250ms → 1s, `retryDelays` :71-76), and ends at the generic `[PUSH] Failed to send push to … after 3 attempt(s)` (:344-358) with **no eviction**. Live evidence (2026-08-01 journal): `[PUSH] Push to 12D3KooWQAhMvhX1wBp7 failed on attempt 1/3: NotRegistered; retrying in 250ms` … `attempt 2/3 … retrying in 1s`, twice, then 2× `Failed to send push to`. A repo-wide grep for `NotRegistered|Unregistered|InvalidRegistration|MismatchSenderId` over every `go-relay-server/*.go` returns **zero** hits. The pinned SDK **does** expose typed predicates (host probe against `firebase.google.com/go/v4@v4.15.1/messaging/messaging.go`): `IsUnregistered` → `hasMessagingErrorCode(err, unregistered)` (:1012-1014), `IsSenderIDMismatch` → `SENDER_ID_MISMATCH` (:47, :998-1000), `IsRegistrationTokenNotRegistered` deprecated-delegating to `IsUnregistered` (:1006-1008), plus `IsInvalidArgument`/`IsQuotaExceeded`/`IsUnavailable`/`IsInternal`/`IsThirdPartyAuthError`.
- **P2 — eviction is undone by the client.** Even a correct eviction is reversed on the next relay-health transition: `_reregisterStoredPushTokenIfAvailable` (lib/core/services/p2p_service_impl.dart:2610-2618, fired at :2246/:2448/:2547) re-sends the **cached** `_lastFcmToken` restored from disk (:2640-2652) and never re-reads the live FCM token, so the relay's token store is re-populated with the same dead token. Relay-side registration is an unconditional whole-entry overwrite (push_token_store.go:30-35, backend_redis.go:964-978), with no TTL (`Set` expiration 0, :975) and no staleness sweeper — `tokenEntry.UpdatedAt` (inbox.go:91) is written and never read.
- **P3 — the wake path is unmeasurable, which is why F5's population is unknown.** The wake lines carry no transition id: `duplicate_suppressed` prints only `group=` + `from=` (inbox.go:1555-1561) and `attempted` only `group=` + `recipient=` (:1613-1619). Worse, `attempted` is incremented **before** the goroutine dispatch (`go s.push.SendGroupReactionNotification(...)`, :1620) — it counts dispatches, not deliveries, and the goroutine's outcome never returns to any wake counter. Two decline paths are **entirely silent**: recognized-but-invalid / `action != "add"` / flag-off (:1567-1570) and push-service-nil (:1589).
- Impact: P1 wastes two retry round-trips per push to every dead token and leaves it in the store forever, where it also makes the recipient look `incapable_skipped` (a token **lookup** backs the capability filter, inbox.go:1605 → :173-179) — indistinguishable from a genuine capability mismatch. P2 guarantees P1's fix decays. P3 means no one — including me — can tell whether F5's lost-wake population is zero or large.
- **Harm bound (C4 confirmed):** custody is written at inbox.go:1550, strictly **before** every wake decision (Duplicate :1554-1564, silent guard :1567-1570, fan-out :1571, nil-push :1589, empty nomination :1592-1598, capability skip :1604-1612). A missed wake therefore costs **notification latency, not the reaction** — the recipient drains it on next foreground within the 7-day `groupMessageTTL` (inbox.go:34, 500-row cap :33, hourly Prune main.go:143-148). The refuter's strongest attack confirmed rather than broke this: a signed replay set that was a strict subset of the request set *would* be permanent data loss, but `reaction_push.go:192-197` rejects the whole extension unless the sets are exactly equal (`stringSlicesEqual` :194).
- **Refuted (do NOT re-introduce): "production evidence shows zero lost wakes."** My own inference, killed structurally: no wake line carries the transitionId, so the observed `attempted,attempted,duplicate_suppressed` per-group pattern **cannot** establish that a duplicate followed an attempt for the *same transition*; and `attempted` is a dispatch counter, so even a matched pair would not prove delivery. The journal is *incapable* of exhibiting a lost wake — silence is not absence. This is exactly what P3 fixes.
- **Also refuted:** "the client mints a fresh transitionId on every decline, so a byte-identical re-store never happens" — the retrier re-sends `current.inboxRetryPayload` **verbatim** (retry_failed_group_inbox_stores_use_case.dart:413), which is what makes the Duplicate short-circuit reachable.
- Existing coverage: the eviction path has exactly one test injecting the *exact* literal (`inbox_test.go:1717`); `GROUP_REACTION_PUSH_ENABLED` default-off is locked (group_reaction_push_test.go:524-527); wake counters exist (metrics.go:199-202); `pushSentCounter` has no lane label (:194-197). **No test asserts FCM error classification, retry-ladder behavior for permanent errors, eviction durability across re-registration, or wake-line content.**
- Affected files: `go-relay-server/inbox.go` (classifier + sendWithRetry branches + wake log lines + silent-guard counter), `go-relay-server/metrics.go` (one new outcome label), `lib/core/services/p2p_service_impl.dart` (P2); tests: `go-relay-server/inbox_test.go`, new `go-relay-server/push_permanent_error_closure_test.go`, `test/features/p2p/…` host test for P2; no schema, no migration.

## Graph Grounding Snapshot
- Graph fingerprint / freshness: `64da5303c97663d0`, `confidence=broad` on the first query (the relay is Go — outside the app-owned arch graph by design), refined by direct source reads; the marker was present and the graph is app-Dart-only, so **all** relay evidence is raw-source.
- Query / profile: `python3 graphify-arch/tdd_context.py query "group reaction wake fan-out duplicate short-circuit StoreWithPushRecipients relay inbox custody once-per-transitionId" --profile tdd --budget 700`.
- Anchors: none usable for Go; the Dart anchor set (`p2p_service_impl`, push coordinator) came from raw grep.
- Graph gaps that required raw source search: the entire relay seam, the Firebase SDK (host module cache via `scripts/test/probe_fcm_error_predicates_320.sh`), and the client re-registration path.
- Reuse rule: anchors are starting points; every conclusion here carries file:line or a live-journal quote.

## Scope Contract And Guard

**In scope:**
- **P1 fix (review-corrected — BLOCKER 1):** `isPermanentPushError(err)` = `messaging.IsUnregistered(err) || messaging.IsSenderIDMismatch(err)` **OR a case-insensitive literal set covering the OBSERVED production text**. Rationale: `hasMessagingErrorCode` type-asserts `*internal.FirebaseError` and compares `Ext["messagingErrorCode"]` against the uppercase constants `UNREGISTERED`/`SENDER_ID_MISMATCH` (messaging.go:1077-1085, :41-42) — but the production journal's `NotRegistered` is FCM's `error.message` **string** (`FirebaseError.Error()` returns `fe.String` from `gcpError.Error.Message`, internal/errors.go:94-96/:145-147); the literal appears nowhere in the SDK. Whether `IsUnregistered` fires depends on an `details[].errorCode == UNREGISTERED` entry the log line cannot show, and the message field is provably unstable (the SAME dead peer logged `Requested entity was not found.` on Jul 10 and `NotRegistered` on Jul 18). Typed-predicates-only would ship v1.7.5 **all-green with byte-identical production behaviour**. So: typed predicates FIRST, then `containsFold` over `notregistered` / `requested entity was not found` / the two legacy hyphenated literals — and **log which arm fired** (`reason=typed_unregistered|typed_sender_mismatch|literal_<x>`) so the post-deploy evidence is attributable. Permanent ⇒ evict + return immediately, no retry; transient ⇒ unchanged ladder.
- **Do-not-wrap guard:** add a comment at inbox.go:250 recording that `messaging.Is*` uses a **bare type assertion, not `errors.As`** — one future `fmt.Errorf("…: %w", err)` in `ps.send` would silently revert the typed arm (TC-320-01's real-client row is the standing detector).
- **P2 fix:** `_reregisterStoredPushTokenIfAvailable` must not resurrect a token the provider has retired — re-read the live token before re-registering (fall back to the cached value only when the live read is unavailable), so a relay-side eviction is not undone by the next relay-health transition.
- **P3 fix (measurability, the prerequisite F5 actually needed):** add `transition=` to BOTH wake log lines so they correlate per transition; emit counted outcomes for the **THREE** (review-corrected — the plan said two) silent decline paths: the recognized-but-invalid / `action != "add"` / flag-off guard (:1568-1570, `invalid_or_disabled`), push-service-nil (:1589-1591, `push_unavailable`), and **the self/empty skip inside the fan-out loop (:1601-1603) — the one that breaks the accounting identity**; and make dispatch-vs-delivery explicit by renaming the pre-dispatch **log token** to `outcome=dispatched` **while keeping the `attempted` counter label** (dashboards depend on it).

**Must preserve:**
- `GROUP_REACTION_PUSH_ENABLED` default-off (group_reaction_push_test.go:524-527, untouched) → GREEN sentinel.
- No duplicate re-fan-out: `inbox_test.go:1930/1935` forbid it (ordinary-envelope-only fixtures) — this plan adds **no** fan-out path → those tests stay green as the guard.
- The payload-too-large single-rebuild branch (inbox.go:307-342) and its strict-minimal rescue (plan 316) → GREEN sentinel.
- Transient errors keep the 3-attempt ladder with 250ms/1s backoff.
- Existing eviction call sites (inbox.go:298, :332, and client-initiated `unregister_token` :155/:2255-2258) keep working.
- The wake counter label set stays backward-compatible (`attempted`/`duplicate_suppressed`/`no_wake_recipients`/`incapable_skipped` all still emitted).

**Hard `Do not`:**
- **Do not build re-fan-out-on-duplicate** (user decision 2026-08-01) — and do not add durable per-(transitionId, recipient) wake-outcome state, which it would require.
- **Do not add `messaging.IsInvalidArgument` to the permanent set (review add).** FCM returns `INVALID_ARGUMENT` for **oversized payloads** too, and the invalid-token branch runs BEFORE the payload-too-large branch (inbox.go:297 vs :307) — including it would swallow plan 316's strict-minimal rescue AND evict live tokens.
- Do not change the Duplicate short-circuit, custody ordering, the signed-replay-set replacement (inbox.go:1542-1549), or the exact-equality guard (reaction_push.go:192-197).
- Do not add a token TTL or staleness sweeper (separate concern; eviction-on-permanent-error is the targeted fix).
- Do not touch the 1:1 lane's fail-closed wake-token authorization (inbox.go:1340-1346).

**Deferred / accepted difference:**
- **Re-fan-out on duplicate (F5's original premise) — DEFERRED by explicit user decision.** Reason recorded honestly: *not* "production proved it unnecessary" (that inference was refuted) but (a) the population is unmeasurable until P3 lands, and (b) a safe design needs durable per-(transitionId, recipient) wake outcome that does not exist today. Owner: revisit after P3 has produced correlated data.
- 1:1 lane has no `relay_direct_reaction_wake_total` analogue and its two suppressions log nothing (inbox.go:1334-1350) — same measurability gap, deliberately out of scope this plan; noted for the wave.
- Token staleness (no TTL, `UpdatedAt` never read) → separate item.
- Rollback: relay-only binary swap + a client-side change; no schema, no wire format. See `## Rollback`.

**Dependencies:** Go legs run host-side (no in-container toolchain); relay build pinned `GOTOOLCHAIN=go1.25.0` with `go version <binary>` verified pre-upload.

## Test Contract

Go rows land in a NEW `go-relay-server/push_permanent_error_closure_test.go` whose test names carry the `TestRelayNotificationClosure_` prefix (the ONLY filter the groups lane's relay tail applies, run_test_gates.sh:1038) — grep-verified. Dart row is auto-globbed.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD state → GREEN | Mutation that re-reds | Gate / registration |
|---|---|---|---|---|---|---|
| TC-320-01 | **HEADLINE (P1), typed arm**: a real SDK `UNREGISTERED` error evicts and does **NOT** retry — exactly one send attempt | `push_permanent_error_closure_test.go::TestRelayNotificationClosure_PermanentTokenErrorEvictsWithoutRetry` | Go host — **review-corrected fixture (BLOCKER 2): `internal` is NOT importable from go-relay-server (proven by compile) and messaging exports no error constructor**, so stand up an `httptest.Server` returning FCM v1 error JSON with `details[].errorCode = UNREGISTERED`, build a real client via `firebase.NewApp(ctx, &firebase.Config{ProjectID:"test-project"}, option.WithEndpoint(srv.URL), option.WithoutAuthentication())`, and count server hits | causal RED (HEAD: substring classifier misses it → 3 attempts, no eviction) → server hit exactly once, token evicted, `invalid_token` counted, `reason=typed_unregistered` logged | restore the substring-only classifier → red; **also reds if anyone wraps the error in `ps.send`** (the bare type assertion has no Unwrap) | new file; **name matches `^TestRelayNotificationClosure_` (grep-verify)**; groups lane relay tail |
| TC-320-01b | **P1 literal arm (BLOCKER 1)**: an error whose text is the OBSERVED production string (`NotRegistered`, and separately `Requested entity was not found.`) with NO typed errorCode still evicts without retry | same file `::TestRelayNotificationClosure_ObservedPermanentTextEvictsWithoutRetry` | Go host / `ps.sender` stub returning a plain error with that text | causal RED (HEAD: neither hyphenated literal matches → full ladder, no eviction) → 1 attempt, evicted, `reason=literal_notregistered` | drop the literal set → red (this is the row that proves the fix is not inert in production) | same |
| TC-320-02 | `SENDER_ID_MISMATCH` is also permanent: evict, no retry | same file `::TestRelayNotificationClosure_SenderIdMismatchIsPermanent` | Go host / same fixture | causal RED (HEAD retries it) → 1 attempt + eviction | drop `IsSenderIDMismatch` from the permanent set → red | same |
| TC-320-03 | Transient errors are unchanged: still walks the full 3-attempt ladder and does **not** evict | same file `::TestRelayNotificationClosure_TransientErrorKeepsRetryLadderAndToken` | Go host — **stays on the `ps.sender` stub seam (review-pinned)**: the SDK layers its OWN 4-retry/503 ladder under `ps.send` (internal/http_client.go:77-90), so a real-client fixture would be slow and its attempt count would not mean what the row says | GREEN sentinel (HEAD behaviour) | classify transient as permanent → red (attempt count + token presence) | same |
| TC-320-04 | The legacy literals still evict (belt-and-braces for non-SDK-wrapped errors) | same file `::TestRelayNotificationClosure_LegacyInvalidTokenLiteralsStillEvict` | Go host | GREEN sentinel (existing `inbox_test.go:1717` shape, re-asserted at the new seam) | delete the literal fallback → red | same |
| TC-320-05 | **P3**: both wake lines carry `transition=`, so `attempted` and `duplicate_suppressed` are correlatable for the same transitionId | same file `::TestRelayNotificationClosure_WakeLinesCarryTransitionId` | Go host / capture `log` output around a store + byte-identical re-store | causal RED (HEAD lines have no transition token) → both lines contain the same `transition=<id-prefix>` | drop the field from either line → red | same |
| TC-320-06 | **P3**: all THREE silent decline paths emit counted outcomes (review-corrected), AND the accounting identity holds — for one transition the emitted outcome count equals `len(NotificationRecipientTransportPeerIDs)` | same file `::TestRelayNotificationClosure_SilentWakeGuardsAreCounted` | Go host / flag-off + non-add + a self/empty-recipient fixture hitting the in-loop skip (:1601-1603) | causal RED (HEAD returns silently at :1568-1570, :1589-1591 and :1601-1603) → counters + log lines present; identity holds | remove any one emission → red (the identity assertion catches the in-loop one) | same |
| TC-320-07 | Wake counter label set stays backward compatible (all four legacy outcomes still emittable) | same file `::TestRelayNotificationClosure_WakeOutcomeLabelsRemainCompatible` | Go host / metrics registry read | GREEN sentinel | rename `attempted` → red | same |
| TC-320-08 | **P2**: on relay-health re-registration the client re-reads the live push token instead of replaying the cached one | `test/features/p2p/push_token_reregistration_test.dart::relay reconnect re-reads the live token before re-registering` | Dart host / fake token source whose live value differs from the cached one | causal RED (HEAD re-registers the cached value) → the live token is registered | revert to `_lastFcmToken` → red | `flutter test <path>`; AUTO (`test/features/**`) + completeness |
| TC-320-09 | P2 fallback: when the live read fails, the cached token is still re-registered (no regression to zero-token) | same file `::falls back to the cached token when the live read fails` | Dart host | causal RED (new behaviour) → cached token registered, one diagnostic emitted | remove the fallback → red | same |
| TC-320-10 | Duplicate re-fan-out is still forbidden (the deferral is test-locked, not just prose) | existing `inbox_test.go:1930/1935` | Go host | GREEN sentinel | add any fan-out below the Duplicate return → red | unfiltered relay run |
| TC-320-11 | `GROUP_REACTION_PUSH_ENABLED` stays default-off | existing `group_reaction_push_test.go:524-527` | Go host | GREEN sentinel | flip the default → red | groups lane relay tail |
| TC-320-12 | Deploy provenance: the running binary is the new build | `journalctl \| grep "Starting relay-server v1.7.5"` + `relay-server version` | production relay | manual/deploy-only proof | N/A — observational; regression re-manifests as a stale version string | deploy-only gate below |
| TC-320-13 | Post-deploy behavioural proof, **made deterministic (review-corrected: a passive grep would read green whether or not P1 works, since the triggering event is rare)**: register a synthetic known-dead FCM token for a scratch peer, trigger exactly one push, and assert BOTH `[PUSH] Removed invalid token for <peer> … reason=<arm>` appears AND **no** `retrying in` line follows for that peer | `docker-ws/verify_permanent_token_eviction_320.sh` → result file | production relay | manual/deploy-only proof | N/A — guarded causally by TC-320-01/01b/02 | deploy-only gate below |

### Test Notes
- TC-320-01/02 need an SDK-shaped error. The predicates read a **typed** messaging error (`hasMessagingErrorCode`), so the fixture must construct the error the way the SDK does rather than a bare `errors.New("NotRegistered")` — the belt-and-braces literal path (TC-320-04) covers the untyped shape separately. If the SDK offers no exported constructor, inject at the `ps.send` seam with a stub whose error satisfies the predicate, and record which shape each row exercises.
- TC-320-05's assertion is a **relationship**: the SAME transition id must appear on both lines, captured from one store + one byte-identical re-store — not two independent greps.
- P3 keeps the `attempted` **counter label** (dashboards) while the log token becomes `dispatched`; TC-320-07 pins the counter compatibility so the rename cannot leak into metrics.

## Implementation Steps
0. **E0 (review add — the gates invoke scripts that do not exist yet):** author `scripts/test/run_permanent_push_error_go_320.sh` (host Go runner for the new test file, `cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . -run '^TestRelayNotificationClosure_' -count=1 -v`) BEFORE capturing the causal RED; and later `docker-ws/deploy_relay_v175.sh` (from `deploy_relay_v174.sh`) plus `docker-ws/verify_permanent_token_eviction_320.sh` for TC-320-13.
1. `git status --short`. Write TC-320-01 + TC-320-01b first and capture their RED (3 attempts + no eviction on HEAD).
2. E1 — `inbox.go`: import the messaging predicates; replace `isInvalidTokenError` with `isPermanentPushError(err)` = `messaging.IsUnregistered(err) || messaging.IsSenderIDMismatch(err) || <legacy literals>`; keep the eviction branch position (before the ladder) at :297-305 and :332. Stop-if: the predicates are not importable at the call site's package boundary → replan the seam, do not re-hand-roll substrings.
3. E2 — `inbox.go` wake lines: add `transition=` to :1557-1561 and :1613-1619; emit `invalid_or_disabled` at :1567-1570 and `push_unavailable` at :1589; log token `attempted` → `dispatched` with the counter label unchanged.
4. E3 — `p2p_service_impl.dart`: live-token re-read with cached fallback in `_reregisterStoredPushTokenIfAvailable` (:2610-2618).
5. E4 — tests per contract; grep-verify the Go test-name prefix and the Dart path's completeness classification.
6. E5 — gates ladder; then build + deploy relay **v1.7.5** (bump `const version`, pinned toolchain, `go version <binary>`, backup, 90s stability window), then TC-320-12/13.

## Risks And Blind Spots
- Lifecycle/derived-state: P2 is exactly this class — the cached token is derived state that outlived its validity; TC-320-08/09 assert reconstruction from the live source with a safe fallback.
- Sibling-surface consistency: `sendWithRetry` is shared by ordinary group pushes, group reactions, and 1:1 reactions — one classifier fix covers all three lanes (verified single implementation); the 1:1 **wake observability** gap is deferred and named.
- Destructive-action side effects: eviction deletes a token row (push_token_store.go:39-43, backend_redis.go:983-987) — TC-320-03 pins that a transient error never evicts, and TC-320-09 pins that the client can still re-register.
- Invariant re-verification: the new permanent branch returns before the ladder; TC-320-01/02 assert `sendCalls == 1` (not merely "evicted") so an implementation that evicts *and* keeps retrying still reds.
- Construction/call-site census: `isInvalidTokenError` has exactly 2 call sites (inbox.go:297, :332) — both migrate; grep gate in acceptance. `_reregisterStoredPushTokenIfAvailable` has 3 callers (:2246, :2448, :2547) — all inherit E3 via the single function.
- Build-artifact provenance: TC-320-12's version string is the discriminator; a green Go suite on an undeployed relay closes nothing.
- Permission/ACL: N/A — no ACL surface touched.
- Fake side-effect fidelity: the recording token backend must actually delete on `UnregisterToken` (mirroring both real backends), else TC-320-01 could pass without eviction.
- Composite/relationship: TC-320-05 (same transition id on both lines).

## Gate Cadence
- Per-plan closure: focused Go rows (new file) + the Dart rows + the curated `groups` lane (owns the relay tail via the name prefix) + one **unfiltered** relay run for TC-320-10 (those tests do not match the prefix).
- Graph-affected first: `python3 graphify-arch/tdd_context.py affected lib/core/services/p2p_service_impl.dart --budget 600`, then run the named files directly (relay Go has no graph edges — covered by the two Go commands).
- Full `host-all`: owned by the notification-reliability wave closure (after C3-plan + D4 + the 318 deferrals) and final release closure — not this plan.
- Shared tests outside feature/core globs: none.

## Acceptance Gates  (literal — copy/paste)
```bash
git status --short

# Causal RED (before E1) — must FAIL: HEAD retries the permanent error and never evicts
/claude-host-bin/host-run bash scripts/test/run_permanent_push_error_go_320.sh

# Focused GREEN (after E1-E4)
/claude-host-bin/host-run bash scripts/test/run_permanent_push_error_go_320.sh      # expect: ok
flutter test test/features/p2p/push_token_reregistration_test.dart                   # expect: exit 0

# Classifier census — the hand-rolled matcher is retired at BOTH call sites
grep -n 'isInvalidTokenError' go-relay-server/*.go                                   # expect: no matches
# (review fix: a single `grep -c A\|B` counts LINES and reds a correct impl — split it)
grep -c 'messaging.IsUnregistered' go-relay-server/inbox.go                          # expect: >=1
grep -c 'messaging.IsSenderIDMismatch' go-relay-server/inbox.go                      # expect: >=1
grep -c 'containsFold' go-relay-server/inbox.go                                      # expect: >=1  (literal arm present)
grep -c 'IsInvalidArgument' go-relay-server/inbox.go                                 # expect: 0    (forbidden — would swallow 316's rescue)

# Registration — the Go tests must match the lane's ONLY relay filter
grep -c 'TestRelayNotificationClosure_' go-relay-server/push_permanent_error_closure_test.go   # expect: 7
grep -n '\^TestRelayNotificationClosure_' scripts/run_test_gates.sh                  # expect: :1041 filter unchanged (review: 1038 is the function header)
./scripts/run_test_gates.sh completeness-check                                       # expect: PASS

# Unfiltered relay run (TC-320-10 lives outside the prefix)
/claude-host-bin/host-run bash scripts/test/run_relay_all_go_309.sh                  # expect: ok

# Graph-affected + curated lane (single reaped run; do not touch the tree or load the host while it runs)
python3 graphify-arch/tdd_context.py affected lib/core/services/p2p_service_impl.dart --budget 600
/claude-host-bin/host-run bash docker-ws/launch_groups_lane_318.sh                   # then wait for LANE_EXIT=0

# Hygiene
flutter analyze
git diff --check

# Deploy (standing authorization) — pinned toolchain, backup, stability window
/claude-host-bin/host-run bash docker-ws/deploy_relay_v175.sh
# TC-320-12/13 semantic outcomes: journal shows "Starting relay-server v1.7.5"; active with
# NRestarts unchanged through the 90s window; zero panics; and in the observation window no
# "NotRegistered" line is followed by a "retrying in" line for the same peer.
```

## Rollback
- Reversible by: `git revert` of the 320 commit + redeploy the retained `relay-server.pre-320-*` backup (`sudo install -m0755 <backup> /usr/local/bin/relay-server && sudo systemctl restart relay-server`) — the drill is verified live and restart is non-disruptive (peer id derives from the same key file).
- What a PRIOR shipped build does with post-change state: nothing to migrate — the only durable effect is *fewer* dead tokens in the store, which an old build handles identically (it just re-registers on next client start). No wire/schema change.
- NOT recoverable once landed: nothing. Evicted tokens are re-registered by the client on next launch/health transition.
- Staging: none needed beyond the standard window; the client change ships with the ordinary app rollout and is independent of the relay change (either can land first).

## Execution Interpretation And Done Criteria
- Expected RED: TC-320-01/02 (retry+no-eviction on HEAD), TC-320-05/06 (missing wake fields/outcome), TC-320-08/09 (cached-token re-registration).
- GREEN sentinel: TC-320-03/04/07/10/11.
- Environment blocker (NOT product): Go legs are host-only; that is expected, not a gap.
- Scope drift (BLOCKING): any re-fan-out path, any durable wake-outcome state, any TTL/sweeper, any change to the Duplicate short-circuit or custody ordering.

- [ ] All 13 rows closed; three defects fixed; re-fan-out absent and test-locked.
- [ ] Causal REDs + revert mutations recorded.
- [ ] Lane green on a single reaped run; unfiltered relay run ok; completeness PASS; analyzer/diff clean.
- [ ] v1.7.5 deployed with provenance + stability evidence; post-deploy journal shows no retry ladder on permanent errors.

## Handoff
- First causal RED command: `/claude-host-bin/host-run bash scripts/test/run_permanent_push_error_go_320.sh` (written before E1).
- Preservation command: the unfiltered relay run + the curated lane.
- Manual registration: none (Go name prefix + Dart auto-glob), both grep-verified.
- Migration: none. Deploy: relay v1.7.5 under standing authorization.
- Boundary closure: host for the logic; the deploy rows close the operational leg.
- Unresolved evidence: the lost-wake population remains unknown **by design** — P3 is what makes it measurable; revisit re-fan-out only with that data.

## Reviewer Findings (2026-08-01, `/tdd-review`, 3-worker audit `wf_d14e6eae-e53`)

Verdict on v1: **plan-fixes-required** × apply-plan-fixes, **2 blockers** — both would have shipped an INERT fix or an unimplementable test:
1. **The typed predicates may never fire on the observed error.** `NotRegistered` is FCM's `error.message` string, not the errorCode `hasMessagingErrorCode` reads (`Ext["messagingErrorCode"] == "UNREGISTERED"`, messaging.go:1077-1085/:41-42; `FirebaseError.Error()` returns `fe.String` from `gcpError.Error.Message`, internal/errors.go:94-96/:145-147; the literal appears nowhere in the SDK). The same dead peer logged `Requested entity was not found.` (Jul 10) and `NotRegistered` (Jul 18) — the message field is unstable. Typed-only ⇒ v1.7.5 ships all-green with byte-identical behaviour. → literal arm + per-arm `reason=` logging + new TC-320-01b.
2. **The fixture strategy was unimplementable**: `firebase.google.com/go/v4/internal` is not importable from go-relay-server (proven by compiling) and messaging exports no error constructor. → `httptest.Server` + real client via `option.WithEndpoint`.

Also folded in: **do NOT add `IsInvalidArgument`** to the permanent set (FCM uses it for oversized payloads and the invalid-token branch precedes the payload-too-large branch — it would swallow plan 316's rescue and evict live tokens); **three** silent decline paths, not two (the in-loop self/empty skip at :1601-1603 breaks the accounting identity) with an identity assertion added; TC-320-13 made deterministic (a passive grep reads green whether or not P1 works); TC-320-03 pinned to the `ps.sender` stub (the SDK layers its own 4-retry ladder underneath, so real transient cost is up to 15 HTTP requests); the `grep -c 'A\|B'` census gate replaced (it counts lines and reds a correct impl); E0 added to author the three scripts the gates invoke; a do-not-wrap comment at inbox.go:250 (the predicates use a bare type assertion, not `errors.As`); line refs corrected (`run_test_gates.sh:1041`, `p2p_service_impl.dart:2645-2653`).

**Confirmed sound (good news):** the relay does NOT wrap the SDK error — `ps.send` returns `client.Send`'s error verbatim (inbox.go:250-260), so the typed arm is reachable; `sendWithRetry` is the single retry implementation for all four push kinds (chat/reaction/group_reaction/group — census of 4 callers); the relay uses only unary `Send` (no batch path); P3 is implementable (transition id in scope at both sites); and **P1's premise is real — 30 days of production journal contain ZERO `[PUSH] Removed invalid token for` lines**, i.e. the eviction branch has never once fired.

## Execution Progress
| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | - | awaiting accepted plan | contract extraction |
