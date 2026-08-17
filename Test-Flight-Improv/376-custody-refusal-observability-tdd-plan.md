# 376 - Custody Refusal Must Be Observable, Never Silently Absorbed

Status: evidence-gated
Type: Bug
Spec: free-text intent (no formal spec) — live diagnosis 2026-08-16, three physical phones vs production relay v1.8.0
Classification: evidence-gated
Closure tier: device

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-16 23:0x | Evidence Collector | `go-relay-server/ack_custody.go`, `media_custody.go`, `inbox.go`, `go-mknoon/node/inbox.go`, `go-mknoon/integration/ack_custody_mixed_relay_test.go`, `lib/features/conversation/presentation/widgets/letter_card.dart`, `lib/core/services/inbox_store_outcome.dart`, `lib/core/database/helpers/messages_db_helpers.dart` | Item 3 **refuted** as framed (no-legacy-fallback is test-locked); Items 1/2 confirmed with two unresolved sub-questions | Emit contract with U1/U2 as gating evidence rows |

## Problem And Evidence

- **Behavior to improve:** when a relay refuses ACK-custody admission, the sender silently absorbs the refusal. The message never becomes durable, no wake push is generated, the recipient gets nothing, and the sender's UI still shows an inbox glyph. Experienced by anyone running a post-Plan-344 build against a relay with custody admission off.
- **Impact:** total loss of offline 1:1 delivery with no user-visible and no operator-visible signal. Observed live 2026-08-16: 218 refusals accumulated while three phones exchanged nothing; diagnosis required reading a Prometheus counter because **no log line exists on the refusal path**.

### Confirmed root cause / current gap

- **C1 — inbox custody refusal returns before storing, logs nothing.** `StoreAckCustody` at `go-relay-server/ack_custody.go:981-984` returns `errAckCustodyAdmissionDisabled` before any durable write. The only store log site is `recordStoredWithoutPush` (`go-relay-server/inbox.go:2068-2078`), which fires exclusively on a genuinely new durable row. Journal therefore shows only `Incoming stream → Stream closed → handled in 126µs`. Signal is metric-only: `relay_inbox_custody_store_total{result="disabled"}`.
- **C2 — the client HAS the typed signal and discards its meaning.** `go-mknoon/node/inbox.go:249` maps wire code `CUSTODY_ADMISSION_DISABLED` → `ErrInboxCustodyAdmissionDisabled`. But `InboxStoreStatus` (`lib/core/services/inbox_store_outcome.dart:1`) is `{ stored, duplicate, rejectedFull, failed }` — it has **no member representing a refusal**, so an admission refusal is indistinguishable from a transient network failure at the Dart boundary. This is the load-bearing gap for Items 2 and 3.
- **C3 — media custody refuses NEW uploads while draining existing state.** `go-relay-server/media_custody.go:768-774` returns `mediaCustodyFailure{code: mediaCustodyErrorAdmissionOff, storeStatus: mediaCustodyStoreDisabled}`. Test-locked at `go-relay-server/media_custody_rollout_test.go:17` (`…AdmissionOffDrains`): with admission off, duplicates/downloads/ACKs still succeed but a new upload is rejected. Unlike C1 this refusal is **explicitly typed on the wire** (`MEDIA_CUSTODY_ADMISSION_DISABLED`, `storeStatus="disabled"`), and the client knows the constant (`go-mknoon/node/media.go:61`). 1:1 media rides this path via `lib/features/conversation/application/prepared_direct_media_blob_custody_coordinator.dart:2421-2422`.
- **C4 — the inbox glyph conflates durable and non-durable states.** `letter_card.dart:1132-1138` renders `Icons.inbox_rounded` for `'delivered' || 'queued' || 'inboxed'`. The in-source comment concedes the conflation: *"'inboxed' (doc-115 relay custody), 'delivered' (receiver confirmed), and legacy 'queued' all render the inbox glyph."* `'inboxed'` is a settlement status requiring `transport == 'inbox'` (`messages_db_helpers.dart:2314-2315`); `'queued'` carries no durability guarantee. One glyph, two very different truths.

### Refuted findings (do NOT re-introduce)

- **R1 — "add a fallback to the legacy store when the relay refuses custody" is REFUTED as a fix.** `go-mknoon/integration/ack_custody_mixed_relay_test.go:331` — *"new sender never legacy-stores on old-only relay"* — drives a strict sender against an old relay and calls `t.Fatalf("strict sender legacy-fell back: …")` if any `store` action reaches it. The no-downgrade rule is **deliberate and test-locked**: the legacy lane carries no ack-or-expiry contract, so falling back would silently convert a durable obligation into an unacknowledged one — reintroducing the very false-durability class this plan exists to remove. **The intended degradation strategy is relay SELECTION, not lane downgrade** (`:347` "old-first store selects upgraded relay", `:383` "direct mutation kind selects upgraded relay without legacy fallback"). Any implementation that makes a strict sender legacy-store must be rejected in review.
- **R2 — "the v1.8.0 relay deploy caused the outage" is REFUTED.** The superseded 2026-08-13 binary logged `admission_enabled=false` identically; the flag is default-off in both. Causation is version skew: Plan 344 landed 2026-08-07, after the phones' prior build (`366885c71`, Aug 6).
- **R3 — "notifications post to the wrong (silent) channel" is REFUTED.** Device telemetry tallies `"silent":false ×1` + `"silent":true ×4`, matching the operator-observed single banner+sound with silent follow-ups. Alert-once is correct behavior; do not plan a channel fix.

### Unresolved findings (these are what make this plan `evidence-gated`)

- **U1 — which status actually backs the observed glyph.** C4 proves the glyph is reachable from `'queued'`, but the live device evidence did not capture the message row's status at the moment the operator saw the inbox icon. TC-01 is written to fail on the *conflation itself*, which holds either way; but the **UI copy/state decision** for Item 2 (does a refused message show a distinct pending-glyph, or an error glyph?) must not be finalized until the row status is read. Closing evidence: `adb shell run-as com.mknoon.app` sqlite read of `messages.status`/`transport` for a refused row, or a `MESSAGE_STATUS_SETTLED` flow event captured during TC-09.
- **U2 — whether 1:1 media actually dead-ends end-to-end today.** C3 proves the relay refuses new uploads and that the 1:1 coordinator uses the custody contract. It does **not** prove the user-visible symptom, because the media send may abort earlier (upload/reservation) or surface an existing error affordance. Closing evidence: TC-09 leg B on a real device with `DIRECT_MEDIA_BLOB_CUSTODY_ADMISSION_ENABLED=false`. **Do not implement Item-1 client changes before this leg runs** — if media already fails loudly, Item 1 collapses to the ops flip plus TC-08 observability only.

### Existing coverage

- `go-mknoon/integration/ack_custody_mixed_relay_test.go:331` proves no-legacy-fallback (the R1 invariant) — reused here as a preservation sentinel.
- `go-relay-server/media_custody_rollout_test.go:17` proves media admission parsing + drain-existing/refuse-new.
- `go-mknoon/node/inbox_ack_custody_test.go:247` already exercises an `admission disabled` reply at the Go parse layer.
- `test/features/conversation/application/drain_direct_inbox_custody_outbox_use_case_test.dart` (registered `ONE_TO_ONE_TESTS`, `scripts/run_test_gates.sh:245`) covers drain mechanics.
- `test/features/conversation/presentation/widgets/letter_card_test.dart` covers glyph rendering (auto-globbed).

### Missing coverage

No test anywhere asserts that a custody **refusal** is distinguishable from a transient failure, that it is logged by the relay, or that it is rendered differently from durable custody. Every existing test stops at the Go error boundary.

### Affected files

Production: `lib/core/services/inbox_store_outcome.dart`, `lib/core/services/p2p_impl/p2p_inbox_coordinator.dart`, `lib/features/conversation/application/drain_direct_inbox_custody_outbox_use_case.dart`, `lib/features/conversation/presentation/widgets/letter_card.dart`, `go-mknoon/node/inbox.go`, `go-relay-server/ack_custody.go`.
Tests/gates: `scripts/run_test_gates.sh` (`ONE_TO_ONE_TESTS`), the five test files named in the contract.

## Graph Grounding Snapshot
- Graph fingerprint / freshness: `ae095e50673d1067`; `freshness=current` (arch graph refreshed via `/claude-host-bin/host-run bash ./graphify-arch/refresh_arch_graph.sh --incremental` after the `.needs_incremental_refresh` backstop fired).
- Query / profile: `python3 graphify-arch/tdd_context.py query "direct inbox custody outbox drain store status stored icon durability send_chat_message_use_case custody refused fallback legacy store" --profile tdd --budget 700`
- Anchors: `background_push_notification_fallback.dart:593`; `notification_completed_outcome_drainer.dart:147`; `send_group_invite_use_case.dart:984`.
- Surfaced proof/gate files: `test/features/push/application/background_push_notification_fallback_test.dart:103` (gates `AUTO_FEATURE_HOST`, `GROUP_TESTS`, `INTRO_TESTS`, `ONE_TO_ONE_TESTS`).
- Graph gaps that required raw source search: **substantial.** The query returned `confidence=broad` and anchored on the *push notification* fallback rather than the custody store path; every load-bearing anchor in this plan (C1–C4, R1) came from direct `grep`/source reading of Go relay, Go bridge, and Dart UI code. The Go modules (`go-relay-server/`, `go-mknoon/`) are outside the app-owned arch graph entirely.
- Reuse rule: anchors are search starting points; every conclusion above cites current source and must be re-verified at execution.

## Scope Contract And Guard

**In scope:**
- Give a custody refusal a distinct, typed representation end-to-end: relay log → wire code → Go bridge → `InboxStoreStatus` → drain outcome → flow event → glyph.
- Add the missing relay-side log line on the inbox admission-off path (C1).
- Split the `letter_card` glyph so non-durable states cannot render as durable custody (C4).
- Determine, on a real device, whether 1:1 media dead-ends the same way (U2).

**Must preserve:**
- Strict senders never legacy-store on a custody-less relay → `go-mknoon/integration/ack_custody_mixed_relay_test.go::TestAckCustodyMixedVersionMatrix/new_sender_never_legacy-stores_on_old-only_relay` (GREEN sentinel, TC-06).
- Media admission-off still drains existing custody state → `go-relay-server/media_custody_rollout_test.go::TestRelayNotificationClosure_DirectMediaBlobCustodyAdmissionOffDrains` (GREEN sentinel, TC-07).
- `'inboxed'` and `'delivered'` keep rendering the durable inbox glyph → TC-05.
- Pre-344 clients keep using the legacy store path unchanged → no edit to `parseInboxStoreResponse`'s legacy branch (`go-mknoon/node/inbox.go:176`) in this plan.

**Hard `Do not`:**
- **Do not** add any legacy-store fallback for a strict sender (R1).
- **Do not** "fix" the notification channel selection (R3).
- **Do not** change `parseInboxStoreResponse`'s optimistic `store_status → "stored"` synthesis for the LEGACY lane here. It is a real latent defect but it belongs to pre-344 compatibility and would regress old-relay senders; deferred below.
- **Do not** flip `DIRECT_MEDIA_BLOB_CUSTODY_ADMISSION_ENABLED` in production as part of *implementation* — that is an ops decision gated on TC-09 leg B.

**Deferred / accepted difference:**
- Legacy-lane optimistic `"stored"` synthesis (`go-mknoon/node/inbox.go:176`) → owner: a follow-up plan scoped to pre-344 compatibility, because changing it here would alter behavior for clients this plan does not test. Guarded meanwhile by TC-02 asserting the strict lane never routes through it.
- Group-lane equivalent of the same refusal-absorption (`group_inbox.go:190-192`, the known empty-recipient silent success) → owner: existing group custody work; out of scope here.

**Dependencies:**
- `DIRECT_INBOX_ACK_CUSTODY_ADMISSION_ENABLED=true` is now live in production (applied 2026-08-16T22:42:51Z). TC-09 leg A must therefore explicitly set it **off** in its harness relay to reproduce; it can no longer be reproduced by pointing at prod.

## Test Contract

Zero empty cells. `HEAD state` is one of `causal RED` · `GREEN sentinel` · `manual/device-only proof`.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD state → GREEN | Mutation that re-reds | Gate / registration |
|---|---|---|---|---|---|---|
| TC-01 | A custody refusal is representable and distinct from a transient failure | `test/core/services/inbox_store_outcome_test.dart::refusal is distinct from generic failure` (**NEW FILE** — verified absent on HEAD) | unit host / no fixture | causal RED (`InboxStoreStatus` has only `{stored,duplicate,rejectedFull,failed}`; the new member does not compile) → refusal maps to its own member, `!= InboxStoreStatus.failed` | delete the new enum member → TC-01 red | `flutter test test/core/services/inbox_store_outcome_test.dart`; AUTO (`test/core/**`) |
| TC-02 | The Go bridge surfaces `CUSTODY_ADMISSION_DISABLED` as the refusal status, never as generic failure, and never via the legacy synthesis | `go-mknoon/node/inbox_ack_custody_test.go::TestAckCustodyAdmissionDisabledSurfacesRefusal` | Go unit / table-driven wire replies | causal RED (today `ErrInboxCustodyAdmissionDisabled` collapses to a generic failed outcome at the Dart boundary) → outcome carries the refusal discriminator AND `parseInboxStoreResponse` is not invoked | revert the mapping → TC-02 red | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 SKIP_LIVE_TESTS=1 go test ./node/ -run AckCustodyAdmissionDisabled`; AUTO (Go package) |
| TC-03 | The drain use case marks a refused row NOT durable and emits a distinct flow event | `test/features/conversation/application/drain_direct_inbox_custody_outbox_use_case_test.dart::refused custody does not settle as durable` | unit/application host / `test/core/services/fake_p2p_service.dart` | causal RED (refusal is absorbed as generic failure; row is not distinguishable) → row stays undelivered AND `INBOX_CUSTODY_REFUSED` emitted AND `INBOX_CUSTODY_SETTLED` absent | make the refusal fall through to the generic failure branch → TC-03 red | `./scripts/run_test_gates.sh 1to1`; already in `ONE_TO_ONE_TESTS` (`run_test_gates.sh:245`) — grep-verify count |
| TC-04 | A non-durable status must not render the durable inbox glyph | `test/features/conversation/presentation/widgets/letter_card_test.dart::queued does not render the durable inbox glyph` | widget / `WidgetTester` + `MaterialApp` | causal RED (`letter_card.dart:1132` returns `Icons.inbox_rounded` for `'queued'`) → `'queued'` renders the non-durable glyph; `'inboxed'` still renders `Icons.inbox_rounded` — **asserted on the same rendered node**, not two independent finds | restore `'queued'` to the durable branch → TC-04 red | `flutter test test/features/conversation/presentation/widgets/letter_card_test.dart`; AUTO (glob) |
| TC-05 | Durable states keep their glyph (no over-correction) | `test/features/conversation/presentation/widgets/letter_card_test.dart::inboxed and delivered still render the durable inbox glyph` | widget / `WidgetTester` | GREEN sentinel (passes today) → still passes | post-fix: remove `'inboxed'` from the durable branch → TC-05 red | same as TC-04; AUTO (glob) |
| TC-06 | Strict senders still never legacy-store on a custody-less relay (R1 invariant) | `go-mknoon/integration/ack_custody_mixed_relay_test.go::TestAckCustodyMixedVersionMatrix/new_sender_never_legacy-stores_on_old-only_relay` | Go integration / in-process matrix relay | GREEN sentinel (passes today) → still passes | post-fix: make the refusal branch call the legacy store → TC-06 red with `strict sender legacy-fell back` | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 SKIP_LIVE_TESTS=1 go test ./integration/ -run TestAckCustodyMixedVersionMatrix`; AUTO (Go package) |
| TC-07 | Media admission-off still drains existing state while refusing new uploads | `go-relay-server/media_custody_rollout_test.go::TestRelayNotificationClosure_DirectMediaBlobCustodyAdmissionOffDrains` | Go unit / `setupTestEnv` | GREEN sentinel (passes today) → still passes | post-fix: make the admission gate reject duplicates/downloads too → TC-07 red | `cd go-relay-server && GOTOOLCHAIN=go1.25.0 SKIP_LIVE_TESTS=1 go test ./ -run DirectMediaBlobCustodyAdmissionOffDrains`; AUTO (Go package) |
| TC-08 | The relay LOGS an inbox custody refusal (operator observability) | `go-relay-server/ack_custody_closure_test.go::TestAckCustodyAdmissionDisabledIsLogged` (**NEW FILE** — verified absent on HEAD; follow `push_envelope_guard_test.go` sibling style) | Go unit / captured `log` output | causal RED (`ack_custody.go:981-984` returns with no log; journal is silent — this is what forced metric-only diagnosis) → one line naming the recipient prefix and `reason=admission_disabled` | delete the log line → TC-08 red | `cd go-relay-server && GOTOOLCHAIN=go1.25.0 SKIP_LIVE_TESTS=1 go test ./ -run AckCustodyAdmissionDisabledIsLogged`; AUTO (Go package) |
| TC-09 | End-to-end: sending to a DOZING recipient against a custody-refusing relay leaves the message visibly undelivered (leg A, text) and reveals the real media behavior (leg B, U2) | `integration_test/custody_refusal_offline_delivery_proof_test.dart::custody refusal leaves the send visibly undelivered` | device proof / physical Android + Android emulator, harness relay with admission env forced | manual/device-only proof → sender shows a non-durable indicator, no wake push is dispatched, and leg B records the observed media behavior (closes U2) | disable the new refusal mapping → sender shows the durable glyph again | `.claude/skills/sims/scripts/run_with_devices.sh major --only <stable-capability-id>`; `classify_path` `record "1to1" "<path>" "test" "custody refusal device proof"` + orchestrator `--scenario` |

### Test Notes
- **TC-03 discriminator:** the refused and transient-failure paths both leave a row un-settled, so a status assertion alone is vacuous. Assert `INBOX_CUSTODY_REFUSED` present **AND** `INBOX_CUSTODY_SETTLED` absent on the same drain pass.
- **TC-04 relationship:** assert glyph and status on the *same* rendered `LetterCard` node. Two independent `find.byIcon` calls prove nothing about which message owns which glyph.
- **TC-09 fixture:** the recipient must reach real Doze (`adb shell dumpsys deviceidle force-idle`), because the failure only appears once the recipient's relay connection drops — the live 2026-08-16 capture showed a reachable-looking recipient (`[RENDEZVOUS] Discovered 1 peers`) whose dial then failed with `no good addresses`.
- **Fake fidelity (TC-03):** `fake_p2p_service.dart` must return the refusal *outcome shape* the real bridge returns, not merely a thrown error — otherwise the test proves a path production never takes.

## Implementation Steps

1. Snapshot `git status --short`. **Note the tree is already dirty** from the 2026-08-16 relay work (`go-relay-server/main.go` version bump to 1.8.0, `docker-ws/group-reaction-staging-manifest-315.json` sha, new `docker-ws/capture_iphone_console.sh`). Do not revert these.
2. Write TC-01…TC-04 and TC-08 as REDs before any production edit (INV-RED-FIRST). Record each failure message.
3. **Run TC-09 leg B first** to close U2. If media already fails loudly, delete the Item-1 client work from scope and keep only TC-07 + the ops recommendation. Stop-if: leg B cannot reach Doze — replan the topology, do not substitute a host fake.
4. Add the refusal member to `InboxStoreStatus` and map it in `go-mknoon/node/inbox.go` (TC-01, TC-02). Stop-if: the member cannot be added without touching the legacy branch — replan, do not widen scope into pre-344 compatibility.
5. Thread the refusal through the drain use case with its flow event (TC-03).
6. Split the `letter_card` glyph branch (TC-04), preserving `'inboxed'`/`'delivered'` (TC-05). Use U1's captured status to choose the non-durable glyph.
7. Add the relay refusal log line (TC-08).
8. Perform the TC-09 registration (`classify_path` + orchestrator scenario).
9. Run focused GREEN → sentinels → graph-affected → `1to1` lane → Go suites → device proof.

## Risks And Blind Spots

- **Over-correcting the glyph** so genuinely durable messages look pending → guarded by TC-05.
- **Reintroducing the legacy downgrade** while "improving degradation" → guarded by TC-06 (the R1 sentinel).
- Lifecycle / derived-state durability: the refusal state must survive app restart — a refused row that reads as pending after relaunch but never retries is the same bug in a new costume → **add to TC-03 a reopen assertion** using `sqflite_common_ffi`; the drain row is persisted, so the derived UI must reconstruct from it.
- Sibling-surface consistency: the same refusal reaches **reactions** and **mutations** (`CustodyKindDirectReactionV109`, `CustodyKindDirectMutationV109` — `inbox_store_outcome.dart:9-11`) and their own drains (`drain_direct_reaction_inbox_custody_outbox_use_case.dart`). TC-03 covers the text lane only → the reaction/mutation lanes are an **explicit accepted gap owned by this plan's step 5**; if step 5 cannot cover them, they become a named follow-up rather than a silent asymmetry.
- Destructive-action side effects: N/A — this plan adds no delete/cleanup path; the drain's existing retirement semantics are untouched.
- Invariant re-verification under new transitions: the new refusal status is a *new transition* into the settlement validator `_validOrdinarySettlementCandidate` (`messages_db_helpers.dart:2285-2320`), whose allow-set is `{delivered, inboxed, sent, failed}`. If the refusal ever reaches settlement it will be silently rejected → TC-03 must assert the refused row does **not** enter settlement at all.
- Construction / call-site census: **`grep -rn 'InboxStoreStatus\.' lib --include=*.dart | grep -v test | wc -l` → 40 sites as of 2026-08-16.** This is the single largest execution risk in the plan: adding an enum member produces compile-REDs at every exhaustive `switch`, which is *desirable* (it forces each site to be considered) but each one must be reviewed individually. **Do not add a blanket `default:`/`_ =>` arm to silence them** — that would re-absorb the refusal into whatever the fallthrough does and reinstate the exact bug. Re-run the census at execution; the count drifts. The landmine is any site that treats `!= stored` as "retry later" and would now loop forever on a permanent refusal.
- Build-artifact provenance: N/A — no native/plugin artifact changes.
- Permission / ACL verb symmetry: N/A — admission is a single-verb store gate; download/ack verbs are deliberately unaffected (TC-07 locks that).
- Composite-node / relationship assertions: covered by the TC-04 same-node rule.

## Gate Cadence

- **Per-plan closure:** TC-01…TC-05 focused runs + the `1to1` curated lane + the three Go suites + TC-09 device proof. No `core-host-all`/`feature-host-all` sweep: this plan changes one widget, one enum, one use case, and two Go files — all covered by the focused gates and the `1to1` lane.
- **Graph-affected first:** after the production edits and BEFORE the curated lane, run `tdd_context.py affected` on the changed Dart files and run the test files it names directly. Note the Go files have **no arch-graph coverage** (Go modules are outside the app-owned graph), so the Go suites are the only dependent signal there.
- **Full `host-all` is not a per-plan gate.** It is owned by the notification/custody dependency wave that already owns plans 372–375, and again at final rollout closure.
- Shared tests outside the feature/core globs: **N/A** — no `test/unit`, `test/integration`, `test/shared`, or `test/l10n` file is touched. (`test/core/services/inbox_store_outcome_test.dart` is under `test/core/**` and is auto-globbed by `core-host-all`.)

## Acceptance Gates  (literal — copy/paste)

```bash
# Dirty-tree snapshot — expect the 2026-08-16 relay-deploy files; do not revert them
git status --short

# Causal REDs (before production edits) — each must FAIL for its documented reason
flutter test test/core/services/inbox_store_outcome_test.dart --plain-name 'refusal is distinct from generic failure'
flutter test test/features/conversation/presentation/widgets/letter_card_test.dart --plain-name 'queued does not render the durable inbox glyph'
cd go-mknoon && GOTOOLCHAIN=go1.25.0 SKIP_LIVE_TESTS=1 go test ./node/ -run AckCustodyAdmissionDisabledSurfacesRefusal; cd ..
cd go-relay-server && GOTOOLCHAIN=go1.25.0 SKIP_LIVE_TESTS=1 go test ./ -run AckCustodyAdmissionDisabledIsLogged; cd ..

# Focused GREEN (after the fix) — exit 0, zero failures
flutter test test/core/services/inbox_store_outcome_test.dart
flutter test test/features/conversation/presentation/widgets/letter_card_test.dart
flutter test test/features/conversation/application/drain_direct_inbox_custody_outbox_use_case_test.dart

# Preservation sentinels — exit 0 (R1 invariant + media drain)
cd go-mknoon && GOTOOLCHAIN=go1.25.0 SKIP_LIVE_TESTS=1 go test ./integration/ -run TestAckCustodyMixedVersionMatrix; cd ..
cd go-relay-server && GOTOOLCHAIN=go1.25.0 SKIP_LIVE_TESTS=1 go test ./ -run DirectMediaBlobCustodyAdmissionOffDrains; cd ..

# Graph-affected dependents BEFORE the curated lane
python3 graphify-arch/tdd_context.py affected \
  lib/core/services/inbox_store_outcome.dart \
  lib/features/conversation/presentation/widgets/letter_card.dart \
  lib/features/conversation/application/drain_direct_inbox_custody_outbox_use_case.dart \
  --budget 600
# then: flutter test <exact files it names>

# Affected curated lane — exit 0
./scripts/run_test_gates.sh 1to1

# Full Go suites — exit 0 (GOTOOLCHAIN pin is mandatory; a bare go1.26 build panics in quic-go)
cd go-relay-server && GOTOOLCHAIN=go1.25.0 SKIP_LIVE_TESTS=1 go test ./...; cd ..
cd go-mknoon && GOTOOLCHAIN=go1.25.0 SKIP_LIVE_TESTS=1 go test ./...; cd ..

# Registration — grep-verified, never run-verified (family gates swallow --list)
grep -c 'drain_direct_inbox_custody_outbox_use_case_test.dart' scripts/run_test_gates.sh   # expect: >=1 (already at :245)
grep -c 'custody_refusal_offline_delivery_proof_test.dart' scripts/check_reliability_simulation_discovery.sh  # expect: >=1
./scripts/run_test_gates.sh completeness-check    # expect: PASS, 0 unmatched

# Device proof discovery + run
./scripts/check_reliability_simulation_discovery.sh
.claude/skills/sims/scripts/run_with_devices.sh major --list
.claude/skills/sims/scripts/run_with_devices.sh major --only <stable-capability-id>

# Hygiene
flutter analyze          # 0 new issues
git diff --check
```

## Execution Interpretation And Done Criteria

- **Expected RED:** TC-01 fails to compile (enum member absent); TC-04 fails because `'queued'` returns `Icons.inbox_rounded`; TC-02/TC-08 fail on the Go side for the documented mechanisms.
- **GREEN sentinel:** TC-05, TC-06, TC-07 pass before and after.
- **Pre-existing dirty tree:** `go-relay-server/main.go` (v1.8.0 bump), `docker-ws/group-reaction-staging-manifest-315.json`, `docker-ws/capture_iphone_console.sh` — all from the 2026-08-16 relay deploy. Baseline, not scope drift.
- **Known pre-existing failures:** per prior lane experience there are integration/perf reds unrelated to this plan; treat only `1to1`-lane and named-file failures as this plan's.
- **Environment blocker (NOT a product blocker):** if no physical Android + emulator pair is attached at execution time, TC-09 is `N/A (target unavailable by project policy)` and the plan closes at `evidence-gated` with U1/U2 still open — it does **not** close as green.
- **Scope drift (BLOCKING):** any change to the legacy `parseInboxStoreResponse` branch, any legacy-fallback introduction (R1), or any notification-channel edit (R3).

- [ ] Every behavior has a named test or a justified proof.
- [ ] Causal RED, focused GREEN, and mutation re-red recorded.
- [ ] Preservation sentinels and named gates pass with semantic outcomes.
- [ ] Harness registration implemented AND grep-verified.
- [ ] Device proof passes, or is explicitly recorded as target-unavailable with U1/U2 left open.
- [ ] `flutter analyze` clean; `git diff --check` clean.
- [ ] Scope Contract And Guard respected.

## Device/Relay Proof Profile

- **Profile:** paired-device + controlled-relay.
- **Boundary being proven:** a recipient in real Doze loses its relay connection, and the sender's behavior against a *refusing* relay cannot be reproduced at any host tier — the live failure only appeared once the recipient's dial failed with `no good addresses` while rendezvous still advertised it as present.
- **Live availability check:** `flutter devices --machine`, `adb devices` → observed 2026-08-16: physical Pixel 6 `21071FDF600CSC` and emulator `emulator-5554`.
- **Pinned targets:** physical Android `21071FDF600CSC` (recipient — real Doze, the stated physical-topology reason an emulator cannot reproduce) + Android emulator `emulator-5554` (sender). This is the two-peer default; no iOS leg is required because nothing here is iOS-specific.
- **Automation:** every step harness-driven — install, Doze forcing (`dumpsys deviceidle force-idle`), send, assertion. No user taps.
- **Closure role:** required closure evidence for U2; supporting evidence for U1.
- **`FLUTTER_DEVICE_ID`:** host selector only — set it to the emulator, but the physical serial must still be pinned explicitly (and per prior experience, set it whenever several devices are attached or the lane picks the wrong target).
- **Relay:** a locally-run relay binary with the admission env forced off. **Do NOT point this proof at production** — admission is now enabled there, so the refusal is no longer reproducible against prod.
- **Registration:** `classify_path` `record "1to1" "integration_test/custody_refusal_offline_delivery_proof_test.dart" "test" "custody refusal device proof"` + orchestrator `--scenario`.
- **Discovery command:** `.claude/skills/sims/scripts/run_with_devices.sh major --list` → the capability must be listed (`--only` takes a stable capability ID, never a numeric position).
- **Deferred device work:** iOS parity for the same refusal — owner: a follow-up, because the Dart/Go seam under test is platform-neutral.

## Rollback

- **Reversible by:** `git revert` of the implementation commit. The enum member addition is source-only; no schema, no wire-format, no key material.
- **What a PRIOR shipped build does with post-change data:** unaffected. No persisted representation changes — the refusal lives in an in-memory outcome and a flow event; the drain row schema is untouched.
- **NOT recoverable once landed:** nothing.
- **Wire-format note:** this plan adds **no** new wire code. It consumes the existing `CUSTODY_ADMISSION_DISABLED` / `MEDIA_CUSTODY_ADMISSION_DISABLED` codes the relay already emits, so old relays and new clients stay compatible in both directions.
- **Ops rollback (separate from code):** `DIRECT_INBOX_ACK_CUSTODY_ADMISSION_ENABLED` was appended to `/etc/mknoon/relay-server.env` on 2026-08-16; backup at `/etc/mknoon/relay-server.env.pre-custody-20260816T224251Z`. Reverting it re-breaks offline delivery for post-344 clients — do not revert it to "test" this plan; use the local harness relay instead.

## Handoff

- **First causal RED command:** `flutter test test/features/conversation/presentation/widgets/letter_card_test.dart --plain-name 'queued does not render the durable inbox glyph'`
- **Preservation command:** `cd go-mknoon && GOTOOLCHAIN=go1.25.0 SKIP_LIVE_TESTS=1 go test ./integration/ -run TestAckCustodyMixedVersionMatrix`
- **Manual registration:** TC-09 only (`classify_path` record + orchestrator `--scenario`). TC-03's file is already in `ONE_TO_ONE_TESTS`.
- **Migration:** none — no schema change.
- **Boundary closure:** device proof TC-09 on the pinned Android pair against a locally-run refusing relay.
- **Unresolved evidence:** U1 (status backing the observed glyph), U2 (whether 1:1 media dead-ends end-to-end). Both close in TC-09. **Run TC-09 leg B before implementing Item-1 client changes.**

## Execution Progress
| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | - | awaiting accepted plan | contract extraction |
