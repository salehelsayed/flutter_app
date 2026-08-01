# 316 - Ordinary Push Platform Projection: Stop Dual-Copy Payloads From Tripping FCM's 4096-Byte Limit

Status: execution-ready (v2 — `/tdd-review` deltas applied 2026-08-01)
Type: Bug
Spec: free-text intent (no formal spec) — grounded in live production forensics (2026-07-31 relay journal: three `provider rejected chat payload size` strict-fallback rescues; artifact `docker-ws/relay_push_diagnostics_309_result.txt`)
Classification: implementation-ready
Closure tier: host (Go host) for the projection + rescue logic; the operational leg (real FCM acceptance of the mid-band and the iOS decrypted-preview outcome) closes only after a v1.7.2 PRODUCTION deploy via the named post-deploy checks

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-31 | Evidence Collector (live forensics) | relay journal 24h window | Three `[PUSH] Strict routing fallback sent to … after provider rejected chat payload size` events (19:18:25Z, 19:21:35Z, 19:22:35Z) — the pre-check passed while FCM rejected the send | Source grounding |
| 2026-08-01 | Planner | `go-relay-server/inbox.go`, `reaction_push.go`, `metrics.go`, `main.go` | The reaction lane already contains the per-platform projection with an in-source rationale naming this exact failure | Emit plan v1 |
| 2026-08-01 | `/tdd-review` (3 workers: factual, counterexample, FCM-domain — workflow `wf_d52e9be5-720`) + lead self-verification of every blocker linchpin | Same + `push_payload_closure_test.go`, `inbox_test.go`, vendored firebase-admin-go v4.15.1, `AppDelegate.swift`, register_push_token_use_case.dart | **3 blockers**: (R1) the ios projection nulls the only input the provider-rejection rescue reads — a still-rejected ios push would ship NOTHING instead of today's generic banner; (R2) the plan's own gate-reachable test (`push_payload_closure_test.go:277`, ios fixture) reds under the change — v1's TC-07 "sentinel" was actually a causal RED; (R3) five existing ios-fixture tests assert on `Data` of sent messages — unbudgeted REDs. Plus 12 plan-fixes. Lead REJECTED one worker delta (projecting inside `sendWithRetry`) in favor of the smaller CustomData routing-source fix | Plan v2 (this document) — all surviving deltas applied |

## Problem And Evidence

- **Behavior to improve:** a 1:1 or group message whose encrypted envelope is mid-sized (each platform leg within the relay's own budgets, yet rejected by FCM at send time) loses its decrypted preview: the provider rejects the first send and the strict routing-only rescue delivers a **generic "New Message" banner** after a wasted round-trip. Media envelopes are the dominant victims — the confirmed mechanism behind the 2026-07-31 "media notifications not successful" symptom, whose preview loss is felt most on iOS (the NSE renders previews from the push payload).
- **Impact:** three live provider rejections in one test evening on the 1:1 lane alone.

### Confirmed root cause

**The ordinary push builders ship BOTH platform payload copies in one FCM request, and the relay's size pre-check measures each leg separately while FCM's server-side 4096-byte enforcement spans a quantity that includes both copies.**
- `buildCiphertextOnlyPushMessage` (`go-relay-server/inbox.go:559-590`) puts the ciphertext in the FCM `Data` map AND duplicates it into `APNS.Payload.CustomData` (`:586` via `apnsCustomDataFromPushData:791-797`). The oversized-fallback shape does the same (`newOversizedFallbackPushMessage:688-721`, CustomData at `:716`), as does the 1:1 reaction builder (`reaction_push.go:559-577`, CustomData at `:574`).
- The pre-check `messageFitsProviderBudgets` (`inbox.go:643-648`) asserts each marshalled leg ≤3800 separately (`providerEquivalentPayloadSize:614-641`). The live rejections happened with the pre-check PASSING (a pre-check failure would have sent the `preview_unavailable` fallback with no provider rejection), so the enforced quantity exceeds any single leg. **Review-verified at dependency source: firebase-admin-go v4.15.1 performs NO client-side size validation** (`messaging.go:937` calls only `validateMessage`; `messaging_utils.go:31-66` checks shape, never bytes) — the 4096 rule is 100% FCM-server-side, and its exact accounting is undocumented; the projection — not budget arithmetic — is therefore the only lever, and the fix is correct under every accounting hypothesis (a projected message carries one leg ≤3800).
- **The repo already contains the fix on one lane:** `projectGroupReactionPushMessageForPlatform` (`reaction_push.go:497-513`), whose comment (`:491-496`) names this exact failure; shipped since the cross-platform-delivery commit `491ad6d91` (2026-07-13). The un-projected send sites are `SendNotification:157-168` (chat, all 1:1 types), `SendGroupNotification:218-243`, and `SendReactionNotification:178-195`; only `SendGroupReactionNotification:197-216` projects (`:214`).
- **Review blocker R1 (resolved in this v2): the projection alone regresses the rescue path.** `buildStrictMinimalFallbackPushMessage` (`inbox.go:745-772`) derives its routing exclusively from `msg.Data` (`:749-758`); with an ios-projected message (`Data == nil`), a still-rejected push takes the `strict == nil` branch (`:308-313` — `payload_too_large` + `[PUSH] Refusing oversized`) and **nothing is sent** — today's generic-banner rescue becomes a silent drop. The reaction lanes can NEVER reach this rescue (the type switch handles only `new_message`/`group_message`, `:750-757`), so the v1.6.0 group-reaction precedent never exercised this interaction — the chat/group lanes are the first to combine ios projection with the rescue, and TC-09 owns it.

### The #1 technical bet (named, with evidence and fallback)
**iOS deliveries with `APNS.Payload.CustomData` present do not need the top-level `Data` map, and iOS deliveries WITHOUT CustomData (visible-copy routes) DO need `Data` kept (FCM merges top-level data keys into the APNs payload).**
- Leg A (CustomData authoritative): the group-reaction lane has shipped ios CustomData-only since `491ad6d91` (2026-07-13) and the iOS NSE resolves those pushes from `userInfo` (`NotificationService.swift:32`, `NotificationPreviewResolver.swift:346-352/:701`). No iOS consumer reads the FCM `Data` copy on any CustomData-bearing path (review-swept).
- Leg B (data-merge on visible routes): the visible branch (`inbox.go:489-521`) carries tap-routing keys ONLY in `Data` (`:471/:478-480`; APNS has `Aps.Alert`, no CustomData), and iOS tap-routing works in production today (`AppDelegate.swift:828,846` reads them from `userInfo`) — production-empirical; FCM docs do not state the merge rule explicitly.
- Leg C (server-side combined enforcement): settled at dependency source (above).
- **Fallback if Leg A were wrong** (it is not, per production evidence): keep `Data` on iOS in all cases — **a containment, not a fix**: android sends are repaired, but the iOS mid-band request is byte-identical to today's, so the iOS symptom (rejection → generic banner) remains and must be paired with a follow-up.

### Existing coverage — and the existing tests this change BREAKS as written (review R2/R3; budget them, do not "fix" them by weakening fixtures)
- **Causal-RED-by-existing-test (R2):** `push_payload_closure_test.go:277` "announcement fallback keeps authenticated group route" — ios token (`:278`), too-large error on first send (`:283-287`), asserts `SendCallCount()==2` (`:299-301`) and the rebuilt `strict.Data` routing (`:302-307`). Under projection-only it reds at `:301`; the R1 rescue fix (CustomData routing-source) turns it green **with the test unchanged**. Gate-reachable (parent matches `^TestRelayNotificationClosure_`). **Stop-if: if this test is ever made green by changing `"ios"` to `"android"` at `:278`, the fix is wrong — revert.**
- **Existing tests to update (R3)** — ios fixtures asserting the sent message's `Data`/`Android`, which legitimately change shape; update the assertions to the APNs CustomData copy (helper `assertAPNSCustomString` exists):
  1. `inbox_test.go:1769` (`:1776` ios token; `:1808` asserts `msg.Data["groupId"]`),
  2. `inbox_test.go:1814` (`:1829-1831` ios tokens; `:1896-1911` asserts Data type/groupId/message_id/ciphertext/nonce),
  3. `inbox_test.go:2740` (`:2702-2707` ios; `:2766` asserts `msg.Android` shape; `:2769-2776` full wantData),
  4. `inbox_test.go:2786` (`:2798` ios; `:2819` asserts `msg.Data["sender_id"]`).
- Un-touched sentinels: `push_payload_closure_test.go:20/:74` (builder-level, un-projected), `:243` android subtests, the plan-315 wake tests. The filtered gate now runs **11** `TestRelayNotificationClosure_*` functions (8 in `push_payload_closure_test.go` + 3 in `reaction_wake_observability_test.go`).
- v1's claim "no test anywhere asserts the ordinary lanes' sent-message platform shape" was **false** for Data content — corrected by the list above.

### Missing coverage
- No test for: android/ios projected shapes at the send sites; the mid-band emitted-size class; the ios-projected-rejection rescue (TC-09); the ios reaction routing set surviving in CustomData (TC-10); the visible-route Data preservation; mixed-case platform normalization.

### Refuted findings (do NOT re-introduce)
| Finding | Why refuted |
|---|---|
| "Raise the relay budgets instead" | The enforced limit is FCM's server-side rule over a quantity spanning both copies; per-leg arithmetic cannot fix a doubled payload. |
| "Project inside the builders" | Builders are platform-agnostic; `entry.Platform` is known at the send sites — the precedent projects there (`inbox.go:214`). |
| "Project inside `sendWithRetry`/`ps.send` (review-worker alternative for R1)" | Rejected by the lead: it threads platform through the retry loop and double-projects the rescue rebuild; the CustomData routing-source fix is ~8 lines, keeps the rescue's tiny dual-copy shape (safe — routing-only), and leaves the retry loop untouched. The rescue send at `:316` is then the ONE deliberately un-projected send — recorded in the census. |
| "The strict fallback makes the bug harmless" | It downgrades previews to generic banners after a wasted round-trip — the symptom, not a fix; and reaction lanes never reach it at all (`:750-757`). |
| "The in-source data-only 4096 model (`inbox.go:53-61` comment)" | The live rejections happened with `pushDataSize` ≤4000 and both marshalled legs ≤3800; the comment's model is refuted and MUST be rewritten in the same commit (see Step 6) or the file contradicts itself. |

### Unresolved findings
- The exact FCM accounting (which serialization the server sums) is undocumented; the fix is invariant across hypotheses, TC-03 asserts the emitted `json.Marshal(msg)` ≤4096 (the precedent's units, `group_reaction_push_test.go:193-214`), and TC-08 captures one post-deploy provider error text (newly logged, Step 7) to confirm/deny the model empirically.

### Affected production / test / gate files
- `go-relay-server/inbox.go` (generalized projector; three send-site calls; `buildStrictMinimalFallbackPushMessage` CustomData routing-source; fallback-log `%v`; `:53-66` comment rewrite), `go-relay-server/reaction_push.go` (delegate the group projector; add the missing `messageFitsProviderBudgets` gate to the 1:1 reaction builder `:540`), `go-relay-server/main.go` (version 1.7.2)
- Tests: new `go-relay-server/ordinary_push_projection_test.go` (`TestRelayNotificationClosure_OrdinaryPush*`); FOUR `inbox_test.go` updates (list above); `push_payload_closure_test.go:277` untouched (R2 causal RED); existing sentinels
- Gates: none to edit

## Graph Grounding Snapshot
- Fingerprint `b48488348e21c95f`, current — the surface is `go-relay-server` (outside the arch graph); every anchor is a direct source read; runtime evidence from the journal artifact; dependency evidence from vendored firebase-admin-go v4.15.1 (go.mod/go.sum pinned).
- Census (review-verified complete, record verbatim): **5 message constructors** (`inbox.go:489/:573/:703`, `reaction_push.go:470/:559`), **4 public send entry points** (`inbox.go:157/:178/:197/:218` with hand-offs `:167/:194/:215/:242`), **5 provider hand-offs** (the four above + the strict-rescue direct `ps.send` at `:316` — post-fix the one deliberately un-projected send).
- Reuse rule: anchors are search starting points; conclusions carry current-source evidence.

## Scope Contract And Guard

**In scope:**
- `projectPushMessageForPlatform(msg, platform)` in `inbox.go`: normalize `strings.ToLower(strings.TrimSpace(platform))`; `android` ⇒ `APNS = nil`; `ios` ⇒ `Android = nil`, and `Data = nil` **only when** `msg.APNS != nil && msg.APNS.Payload != nil && len(msg.APNS.Payload.CustomData) > 0`; any other value ⇒ unchanged (fail-open guard branch — production cannot register an empty platform, `inbox.go:2184`).
- Apply it at the three un-projected send sites (`SendNotification`, `SendGroupNotification`, `SendReactionNotification`), mirroring `:214`.
- **R1 fix:** `buildStrictMinimalFallbackPushMessage` sources its four routing keys from `msg.Data`, and when `len(msg.Data)==0`, from `msg.APNS.Payload.CustomData` (string type-asserts) — ~8 lines, no signature change. The rebuilt rescue keeps its current dual-copy shape (routing-only, tiny) and is sent un-projected at `:316` by design.
- Add the missing per-leg budget gate to the 1:1 reaction builder: `reaction_push.go:540` gains `|| !messageFitsProviderBudgets(pushMessage)` (rejects via the existing `reaction_invalid` counter) — without it, a data-cap-4000 reaction yields an ios-projected single leg ≈4200 > 4096.
- Append the provider error to the strict-fallback success log (`inbox.go:317-323` gains `: %v`) so post-deploy occurrences carry the provider's own text; the `[PUSH] Strict routing fallback sent to` prefix stays intact.
- Re-point `projectGroupReactionPushMessageForPlatform` to delegate to the generalized function (byte-identical semantics; Stop-if: any reaction-projection test needs a behavioral change ⇒ the generalization is NOT identical — keep the lanes separate and file the divergence).
- Rewrite the stale `inbox.go:53-66` comment block to the corrected model (server-side 4096 across the request including both platform copies; per-leg budgets necessary but not sufficient; the send sites project per platform).
- `const version` `"1.7.1"` → **`"1.7.2"`** (`main.go:25`).

**Must preserve:**
- Group-reaction projection semantics → existing `group_reaction_push_test.go:145` (unfiltered run).
- Visible-copy routes keep `Data` on iOS → TC-04 (with the `Aps.Alert != nil` co-assertion).
- The provider-rejection rescue still sends for ios-projected messages → **R2's existing test `push_payload_closure_test.go:277` unchanged** + TC-09.
- The oversized `preview_unavailable` band unchanged; android subtests (`:243`) unchanged; plan-315 wake counters/lines and the `[PUSH] Notification sent to` literal byte-identical.
- Unknown-platform entries keep dual-copy (guard branch) → TC-06.

**Hard `Do not`:**
- Do not change builder signatures, any Dart/client surface, `go-mknoon`, or any wire format.
- Do not strip `Data` for iOS when CustomData is absent (TC-04's mutation).
- Do not green `push_payload_closure_test.go:277` by editing its fixture platform (the R2 stop-if).
- Do not deploy without `GOTOOLCHAIN=go1.25.0` + the embedded-toolchain check + the 90s stability window (the go1.26 quic-go crash-loop is live-verified).

**Deferred / accepted difference:**
- Consolidating visible routes onto CustomData — cosmetic; no owner scheduled.
- The exact FCM accounting model — empirically observed post-deploy (TC-08), not blocking.

**Dependencies:** v1.7.2 PRODUCTION deploy under the pinned-toolchain procedure; independently revertible (v1.7.1 backup).

## Test Contract

Zero empty cells. `HEAD state` is one of `causal RED` · `GREEN sentinel` · `manual/device-only proof`.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD state → GREEN | Mutation that re-reds | Gate / registration |
|---|---|---|---|---|---|---|
| TC-01 | Android-token chat/group ciphertext push sends with NO APNS config and a byte-identical FCM leg | `ordinary_push_projection_test.go::TestRelayNotificationClosure_OrdinaryPushAndroidProjectionStripsApns` | Go host / captured `ps.sender`; android entry; through `SendNotification` AND `SendGroupNotification` | causal RED (HEAD: APNS non-nil) → `APNS == nil`, `Data` marshal-equal to the un-projected build's | remove either send-site projection → red | `(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -run '^TestRelayNotificationClosure_' -count=1)` (matches the groups-gate filter, `run_test_gates.sh:1038`; suite now = 11 existing + new functions) |
| TC-02 | ios-token ciphertext push sends with NO Android config and NO duplicate `Data` (CustomData present, marshal-equal) | same file`::TestRelayNotificationClosure_OrdinaryPushIosProjectionDropsDuplicateData` | Go host / ios entry, ciphertext envelope | causal RED (HEAD: Android + Data non-nil) → `Android == nil`, `Data == nil`, CustomData intact | revert the ios branch → red | same |
| TC-03 | Mid-band emitted-shape: an envelope whose un-projected legs each pass ≤3800 while `json.Marshal` of the whole un-projected message exceeds 4096 is EMITTED as a single-platform request with `json.Marshal(msg) ≤ 4096` (the precedent's units, `group_reaction_push_test.go:193-214`; host-tier proof of the emitted shape ONLY — provider acceptance is TC-08's alone) | same file`::TestRelayNotificationClosure_OrdinaryPushMidBandFitsCombinedLimit` | Go host / fixture premise asserted explicitly: per-leg ≤3800 AND whole-marshal >4096 pre-projection | causal RED (HEAD: captured whole-marshal >4096) → ≤4096, `preview_unavailable` absent | remove the projection → red | same |
| TC-04 | Visible-copy routes keep `Data` on iOS (tap-routing keys) while `Aps.Alert` survives | same file`::TestRelayNotificationClosure_OrdinaryPushIosVisibleRouteKeepsData` | Go host / ios entry, `group_invite` envelope (fixture literal precedent `inbox_test.go:1013-1015`) | GREEN sentinel (new) → `Data["type"]/["groupId"]` present, `Android == nil`, `APNS.Payload.Aps.Alert != nil` | strip `Data` whenever `APNS != nil` (CustomData-blind) → red | same |
| TC-05 | 1:1 reaction lane projects per platform AND its builder now enforces the per-leg provider budget | same file`::TestRelayNotificationClosure_OrdinaryPushDirectReactionProjected` | Go host / capability android + ios entries; plus an over-budget reaction envelope (data ≤4000, marshalled leg >3800) | causal RED (HEAD: dual-copy both platforms; over-budget envelope still builds) → android `APNS==nil`; ios `Android==nil, Data==nil`; over-budget envelope → nil build (`reaction_invalid`) | remove the projection call or the new budget gate → red | same |
| TC-06 | Platform-string robustness: `"iOS"`/`" ANDROID "` normalize and PROJECT; `"web"`/`""` keep dual-copy (fail-open guard; `""` unreachable in production, `inbox.go:2184`) | same file`::TestRelayNotificationClosure_OrdinaryPushPlatformNormalization` | Go host / four entries | causal RED for the mixed-case half (HEAD has no projection at all; post-fix a non-normalizing switch also reds) → projected; `web`/`""` deep-equal dual-copy | drop the `ToLower`/`TrimSpace` normalization → red | same |
| TC-07 | The R2 existing test stays UNCHANGED and turns green via the R1 rescue fix: ios-projected group push + provider size rejection still emits the strict routing fallback | existing `push_payload_closure_test.go:277` (ios fixture `:278`, `SendCallCount()==2` `:299-301`, rebuilt `strict.Data` `:302-307`) | Go host (existing) | causal RED **under projection-only** (SendCallCount==1) → green with the CustomData routing-source fix, test untouched | re-point the rescue back to `msg.Data`-only → red; **greening it by editing `:278` to "android" is the forbidden wrong fix (Stop-if)** | same (gate-reachable today) |
| TC-08 | PROD-CRITICAL operational leg (deploy-only): mid-band pushes stop tripping the provider AND the iOS decrypted preview renders | post-deploy: `journalctl | grep -c "Refusing oversized"` **== 0 (primary — this is the regression signature under R1)**; `relay_push_sent_total{result="payload_too_large"}` flat; `payload_too_large_fallback` trend to zero; capture one provider error text via the newly-logged `%v` if any occurs; PLUS one device observation — send a mid-band media 1:1 to a backgrounded iOS phone and confirm the DECRYPTED preview (not the generic banner) renders (the only observation that can falsify Leg A) | production relay + one iOS device | manual/device-only proof | N/A — observational; regression re-manifests as `Refusing oversized`/`payload_too_large` returning | deploy-only commands in Acceptance Gates |
| TC-09 | ios-projected CHAT push + provider size rejection still rescues (the 1:1 twin of TC-07) | `ordinary_push_projection_test.go::TestRelayNotificationClosure_OrdinaryPushIosProjectedRejectionStillRescues` | Go host / ios entry via `SendNotification`, `onSend` errors too-large on call 1 | causal RED under projection-only (SendCallCount==1, `payload_too_large`) → SendCallCount==2, strict fallback carries `type/sender_id/preview_unavailable` | remove the CustomData routing-source → red | same as TC-01 |
| TC-10 | ios reaction push still carries the FULL routing set — now in `APNS.Payload.CustomData` (the four `inbox_test.go` updates' pinned invariant) | same file`::TestRelayNotificationClosure_OrdinaryPushIosReactionRoutingInCustomData` + the four updated `inbox_test.go` sites (`:1769/:1814/:2740/:2786` — assertions moved to CustomData via `assertAPNSCustomString`) | Go host | causal RED (new test: HEAD carries the set in Data too, but the row's assertion set targets CustomData-only post-shape… asserted as: CustomData contains every key the old Data assertions pinned) → holds; the four updated tests green | drop a routing key from CustomData projection (impossible without touching builders — mutation: null CustomData in the ios branch) → red | same |

### Test Notes
- **Marshal-equality assertions** (TC-01/02): compare against a second un-projected build of the same envelope.
- **TC-03 units**: `json.Marshal` of the entire captured `*messaging.Message` (Token included) — matching `group_reaction_push_test.go:193/202/214` so this row and the `:145` sentinel report the same numbers.
- **TC-05 budget sub-case**: the reaction builder's new gate must fire BEFORE the projection question arises (nil build, `reaction_invalid` counter delta via `prometheus/testutil`).
- **R3 updates are assertion-relocations, not weakenings**: every key previously pinned on `Data` must be pinned on CustomData for ios paths; the android paths keep their Data assertions.
- The rescue rebuild keeps dual-copy (tiny, routing-only) and is deliberately un-projected (`:316`) — recorded in the census; do not "optimize" it.

## Implementation Steps
1. Snapshot `git status --short`. Author TC-01..06, TC-09, TC-10 REDs + run the untouched `:277` to record its projection-only RED **after** step 3 lands in a scratch run (INV-RED-FIRST for the new rows; `:277` is the existing causal RED — record its red under projection-only, then its green after step 4).
2. `projectPushMessageForPlatform` (normalized switch; ios shape-aware CustomData rule; default unchanged).
3. Apply at the three send sites.
4. **R1:** CustomData routing-source in `buildStrictMinimalFallbackPushMessage` (Data first; CustomData string-asserts when `len(msg.Data)==0`).
5. Reaction lane: delegate the group projector; add `|| !messageFitsProviderBudgets(pushMessage)` at `reaction_push.go:540`.
6. Rewrite the `inbox.go:53-66` comment block (corrected FCM model); append `: %v` + `err` to the strict-fallback success log (`:317-323`).
7. Update the four `inbox_test.go` ios assertion sites (R3 list) to CustomData.
8. Bump `main.go` version to `1.7.2`.
9. Run: focused GREEN → filtered suite → unfiltered suite → hygiene.
10. Deploy (pinned toolchain, embedded-version check, backup, 90s stability window) and run TC-08.

## Risks And Blind Spots
- **ios rescue regression** → TC-07 (existing, untouched) + TC-09; the forbidden fixture-weakening is a named Stop-if.
- **Visible-route Data strip** → TC-04 (+`Aps.Alert` co-assert).
- **Reaction single-leg overflow post-projection** → TC-05's budget sub-case (`reaction_push.go:540` gate).
- Sibling/census: 5 constructors / 4 entry points / 5 hand-offs recorded verbatim (Graph Grounding); the `:316` rescue send is the one deliberately un-projected hand-off. Re-derive at execution.
- Existing-test blast radius: the FIVE ios sites are budgeted (R2 untouched-red→green; R3 four relocations); android subtests + builder-level tests unaffected (verified).
- Fake fidelity: the `ps.sender` capture is the production hand-off; provider semantics owned honestly by TC-08 (incl. the iOS device preview observation).
- Build-artifact provenance: pinned-toolchain rule + `go version <binary>` check + journal `v1.7.2`.
- Lifecycle/destructive/ACL/migration/composite classes: N/A — stateless request shaping; no ACL, schema, or deletion surface (TC rows bind premise+outcome on the same captured message).
- Hygiene gate corrected: `(cd go-relay-server && test -z "$(gofmt -l .)")` — exit-code-honest (v1's `; true` form always passed).

## Gate Cadence
- Per-plan closure: focused rows → filtered relay suite (now 11+new `TestRelayNotificationClosure_*`) → one unfiltered relay run (`:145` + the four updated `inbox_test.go` suites) → hygiene. No Dart surface; no graph-affected step (Go is outside the arch graph). Full `host-all` stays with the group-notification wave.

## Acceptance Gates  (literal — copy/paste)
```bash
git status --short

# --- Causal REDs (new rows, before production edits) ---
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... \
  -run '^TestRelayNotificationClosure_OrdinaryPush' -count=1)
# `go test -run` with zero matches exits 0 — confirm all eight new test names exist first.

# --- R2's projection-only RED (record after step 3, before step 4) ---
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... \
  -run '^TestRelayNotificationClosure_ProviderTooLargeGetsOneStrictFallback$' -count=1)   # RED at :301, then GREEN after step 4

# --- Focused GREEN + suites ---
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -run '^TestRelayNotificationClosure_' -count=1)
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -count=1)

# --- Hygiene (exit-code honest) ---
(cd go-relay-server && test -z "$(gofmt -l .)")
git diff --check

# --- Deploy-only (v1.7.2; pinned toolchain MANDATORY; embedded check; 90s window) ---
ssh <relay> 'sudo journalctl -u relay-server -n 20 | grep "Starting relay-server v1.7.2"'
ssh <relay> 'sudo journalctl -u relay-server --since "-24 hours" | grep -c "Refusing oversized"'      # PRIMARY: expect 0
ssh <relay> 'curl -s localhost:2112/metrics | grep -E "payload_too_large"'                            # flat vs pre-deploy baseline
# plus the iOS device observation: mid-band media 1:1 to a backgrounded iPhone → decrypted preview renders
```
**Semantic outcomes.** New-row REDs fail on shape assertions; `:277` reds only in the projection-only window and greens with the rescue fix untouched; both suites exit 0; hygiene exits 0. Deploy-only gates run after the deploy decision executes; a green Go suite on an undeployed relay does not close TC-08.

## Execution Interpretation And Done Criteria
- Expected RED: TC-01/02/03/05/06(mixed-case)/09/10 (new), `:277` (projection-only window).
- GREEN sentinel: TC-04, TC-06 (web/empty half), `:145`, `:243` android subtests, plan-315 wake tests, the four relocated `inbox_test.go` suites post-update.
- Scope drift (BLOCKING): builder signatures, Dart/client, go-mknoon, wire formats, the `:278` fixture platform, the `[PUSH] Notification sent to` literal, plan-315 counters.
- [ ] All rows closed; `:277` red→green recorded with the test untouched.
- [ ] Filtered + unfiltered suites green; hygiene exit-code green.
- [ ] Version 1.7.2; deploy provenance + TC-08 recorded when the deploy runs.

## Rollback
- `git revert` + redeploy the v1.7.1 backup (drill live-verified 2026-07-31). Nothing persisted changes; request shaping only. NOT recoverable: nothing.

## Handoff
- First causal RED: the `OrdinaryPush` run above (after authoring the eight tests).
- Preservation: the unfiltered relay run.
- Registration: none (name filter).
- Boundary closure: host for projection+rescue; TC-08 post-deploy (journal-primary + iOS preview observation).

## Reviewer Findings

`/tdd-review`, 2026-08-01 — 3 workers (factual, counterexample, FCM-domain) + lead self-verification of every blocker linchpin. Verdict on v1: **plan-fixes-required**. All surviving deltas applied above.

**Blockers (3):** R1 ios-projection kills the rescue (`inbox.go:745-772` reads only `msg.Data`; nil-map reads → nil fallback → `Refusing oversized`) → CustomData routing-source + TC-09; the worker's alternative (project in `sendWithRetry`) REJECTED by the lead for diff size and double-projection risk — decision recorded in Refuted. R2 the plan's own gate-reachable test `push_payload_closure_test.go:277` (ios) reds under projection-only — reclassified as the causal RED the rescue fix must green untouched, with the fixture-weakening Stop-if. R3 four `inbox_test.go` ios sites assert sent-`Data` — budgeted as assertion relocations + TC-10; v1's "no test asserts sent shape" claim corrected.

**Plan-fixes (12):** TC-08's primary signal inverted (the regression signature is `Refusing oversized` + `payload_too_large`, NOT the fallback line, which only prints on SUCCESSFUL rescue); reaction lanes can never reach the rescue (`:750-757`) so the v1.6.0 precedent never covered the interaction; TC-03 re-worded to emitted-shape honesty with `json.Marshal(msg)` units matching the `:193` precedent; stale `inbox.go:53-66` data-only comment must be rewritten in-commit; bet-fallback re-worded as containment-not-fix; 1:1 reaction builder lacks `messageFitsProviderBudgets` (`reaction_push.go:540`) → gate added + TC-05 sub-case; provider error text never logged on the rescued path → `%v` appended; TC-06 re-fixtured (`"web"`/`""` fail-open + mixed-case MUST project; `""` production-unreachable per `inbox.go:2184`); TC-04 gains the `Aps.Alert` co-assert + fixture literal cite; suite count corrected to 11; gofmt gate made exit-code-honest; census recorded verbatim (5/4/5, `:316` = the deliberate un-projected hand-off).

**Confirmed sound:** Leg C settled at dependency source (firebase-admin-go v4.15.1 does NO client-side size validation — `messaging.go:937`/`messaging_utils.go:31-66`); Leg A production-proven since `491ad6d91` with no iOS Data-reader on CustomData paths; Leg B production-empirical (`AppDelegate.swift:828,846`); the lane census is complete (no forgotten send path); shallow-copy safety verified; fail-open unknown-platform branch is a guard, not a production path.

## Execution Progress
| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-01 | causal REDs | `ordinary_push_projection_test.go` (8 tests) | `-run '^TestRelayNotificationClosure_OrdinaryPush'` → 6 REDs on the documented shape mechanisms (APNS/Android non-nil; whole marshal 6381>4096; "iOS" dual-copy); TC-09/TC-10 pre-green per the plan's sequencing | genuine causal REDs | stage-1 projection |
| 2026-08-01 | stage-1 projection + R2 RED | `inbox.go` (projector + 3 send sites) | `:277` REDs projection-only: `announcement provider send calls = 1` + live `Refusing oversized group push` — the exact R1 regression reproduced | R2's prediction confirmed byte-for-byte | stage-2 rescue |
| 2026-08-01 | stage-2 full implementation | `inbox.go` (rescue CustomData routing-source, `:53-66` comment rewrite, fallback-log `%v`), `reaction_push.go` (projector delegation + per-leg budget gate), `main.go` (1.7.2) | filtered suite → `ok` (all `TestRelayNotificationClosure_*` incl. `:277` UNTOUCHED) | rescue fix greens R2 without fixture edits (Stop-if honored) | R3 relocations |
| 2026-08-01 | R3 + full closure | `inbox_test.go` ×4 (assertions relocated to APNs CustomData via new `sentRoutingString`/`apnsCustomDataAsStringMap` helpers) | unfiltered `go test ./... -count=1` → `ok` (exit 0); mutation re-red recorded (removing the chat-lane projection reds TC-01+TC-02, restored, re-green); `gofmt` clean; `git diff --check` clean | the only unfiltered failures were EXACTLY the four predicted R3 sites — zero collateral | v1.7.2 deploy (pinned toolchain) + TC-08 |
| 2026-08-01 | v1.7.2 PRODUCTION deploy | relay binary (sha `21c8956494a1…`, embedded go1.25.0 verified pre-upload) | `Starting relay-server v1.7.2` 23:18:33Z; active with NRestarts=0 through the 92s window; zero panics; backup `relay-server.pre-316-*` kept | TC-08 baselines: `Refusing oversized`=0 (pre + must stay 0), the three 2026-07-31 `after provider rejected` events are the only history, no `payload_too_large` counters. **Bonus (plan-315 task-4 evidence): six `outcome=attempted` reaction wakes + two `duplicate_suppressed` with full `[GROUP_REACTION_WAKE]` journal attribution in the 35 min v1.7.1 was live — real users, three groups: the first observable reaction pushes in the app's history** | TC-08 residual: the observation window under normal traffic + the iOS decrypted-preview device check (mid-band media 1:1 to a backgrounded iPhone) — needs the user awake or a UI-driving session | monitor + iOS preview check |
| 2026-08-01 ~10:50Z | TC-08 observation window CLOSED | relay (read-only) | ~35.5h production window since v1.7.2: `Refusing oversized`=0 (PRIMARY), `payload_too_large` counter never incremented, `payload_too_large_fallback`=0 — evidence `docker-ws/tc08_relay_window_317_result.txt`. Bonus: wake counters now attempted=24 / duplicate_suppressed=11 / **no_wake_recipients=2 (first-ever observed empty-nomination outcomes)** | journal-primary leg green | **Device-preview leg blocked on user-owned inputs**: no drivable sender shares a 1:1 with an app-carrying iPhone (Pixel=Bob↔Alice=emulator only; iPhone 13/11 rosters unknown, 17 Pro Max has no app); devicectl lacks screenshots; `idevicesyslog` exits on attach; XCUITest channel needs an xctestrun/signing session; provider-driver path needs the user's APNs `.p8` + signing identity AND bypasses the real relay→FCM leg. NSE discriminator pre-identified for whenever it runs: `PUSH_NSE_CONTENT_HANDOFF authorized=true` vs `PUSH_NSE_TIMEOUT`/`authorized=false` | user decision: real-usage glance vs seeding session vs accept journal-primary |
