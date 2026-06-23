# 142 - Relay FCM push exceeds 4 KB for media envelopes → offline recipient gets NO notification  (Bug)

Status: awaiting-review
Spec: free-text intent (no formal spec) — production incident 2026-06-22, EC2-relay journal forensics. Companion: Bug 1 = `141-notif-open-inbox-drain-not-started-tdd-plan.md` (Dart client, separate). Codebase: **Go relay** (`go-relay-server/`), package `main`.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-22 | Evidence Collector | relay journal (`Failed to send push … Message is too large. The maximum is 4K (4096 bytes)` ×2, after large blob uploads); `inbox.go` push build | Mechanism = full ciphertext embedded in FCM data; media ciphertext > 4 KB | — |
| 2026-06-22 | Planner | `inbox.go:274-480` (buildPushMessage/buildCiphertextOnlyPushMessage/addChat+GroupEncryptedPushData), `inbox_test.go` push tests, `Makefile` | No size cap exists; RC survives refute | RED catalog + matrix (Go) |
| 2026-06-22 | Reviewer (sufficiency) | this doc | see Reviewer Findings | — |
| 2026-06-22 | Arbiter | this doc | see Arbiter Decision | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-06-22 | contract extraction (git status --short) | — | relay tree clean; `inbox.go`/`inbox_test.go` not in `new-feed` churn | scope confirmed | RED |
| 2026-06-22 | RED tests added (TC-01/02/03/04) | inbox_test.go | `go test -run 'Oversized\|PushDataSize\|SmallCiphertext'` → compile-fail `undefined: pushDataSize/maxPushDataBytes` | RED for expected reason | impl |
| 2026-06-22 | implementation | inbox.go (`maxPushDataBytes=4000`, `pushDataSize`, `buildOversizedFallbackPushMessage`, 2 guards) | — | scoped files only (no metrics.go — reused `pushSentCounter`) | GREEN |
| 2026-06-22 | direct GREEN | — | TC-01..04 all PASS | reds now green | mutate |
| 2026-06-22 | mutation-verified | inbox.go (revert each) | 4 mutations re-red (6586/5139 B; over-trim; off-by-one→3999) then reverted | each fix pinned | review |
| 2026-06-22 | adversarial review (12-agent workflow) | — | 5 confirmed (1 high code, 4 test), 3 protocol refuted | fix #1 + harden tests | fix |
| 2026-06-22 | review fixes (TC-05/06) | inbox.go (message_id clamp), inbox_test.go (clamp test + MutableContent/CustomData asserts) | clamp test RED→GREEN (4563→under-budget), mutation-verified; MutableContent assert mutation-verified | INV-1 now unconditional | full-suite |
| 2026-06-22 | full-suite GREEN | — | `go test ./...` ok 11.6s; `go vet` clean; `gofmt -l .` empty; diff = inbox.go+inbox_test.go only (314 ins, 0 del) | host floor done | deploy |
| 2026-06-22 | deploy (EC2) | `/usr/local/bin/relay-server` (sha256 `2f91646f…` = local build, verified equal) | built linux/amd64 from HEAD; backed up old v1.5.1 → `relay-server.bak-v1.5.1-pre142`; `systemctl restart` → `active (running)`, clean startup (Firebase init, 212 profiles, listeners up, Push enabled, no panic) | DEPLOYED & healthy | observe TC-05 |
| | TC-05 on-device observation | — | send MEDIA to an OFFLINE recipient → journal `[PUSH] Notification sent` (not `Message is too large`) + `relay_push_sent_total{result="oversized_fallback"}` increments | **PENDING — needs a real media send to an offline device** | close |
| | QA (independent) | | | blocking: none/list | verdict |

## Source Of Truth
- Spec / intent: inline below + memory `project_relay_notif_open_drain_race_2026_06_22` (secondary-finding section), `reference_ec2_relay_inbox_access`.
- Build/test: `go test ./...` inside `go-relay-server/` (auto-discovers `*_test.go` in package `main`); `Makefile` has only `build`/`run`/`tidy`/`clean` (no test target).
- Deploy: EC2 `ubuntu@mknoun.xyz` (key `se.pem` at repo root), systemd `relay-server.service`, binary `/usr/local/bin/relay-server` (currently v1.5.1).
- Numbering: `Test-Flight-Improv/00-INDEX.md` (real max `139`; `140`=Orbit3, `141`=Bug 1) → this is `142`.

## Session Classification
implementation-ready (Go host floor mandatory; EC2 redeploy + on-device observation is the closure/PROD-CRITICAL leg).

## Exact Problem Statement
When a user sends a **media** message and the recipient is **offline**, the relay's FCM push is rejected by the Firebase Admin SDK with `Message is too large. The maximum is 4K (4096 bytes)` on all 3 attempts (relay journal, 2026-06-20T11:11:54Z and 2026-06-22T14:10:30Z, each right after a `[MEDIA] Uploaded blob … (4657634 / 1211030 bytes)` + `[INBOX] Stored message …`). Result: the offline recipient receives **no notification at all** for that media message and only learns of it when they next open the app for another reason. (When the recipient is online the message is fetched live, so the failed push goes unnoticed — which is why this stayed latent.)

Mechanism (source-confirmed): `new_message` pushes are deliberately **silent, ciphertext-only data pushes** — `buildPushMessage` (`inbox.go:274`) calls `addChatEncryptedPushData` (`:428`) which copies the **entire** `encrypted.kem` + `encrypted.ciphertext` + `encrypted.nonce` of the message envelope into the FCM `data` map (`:442-444`), then `buildCiphertextOnlyPushMessage` (`:387`) sends it with **no `Notification` block** (the client decrypts the ciphertext and renders the notification locally). For a **text** message the ciphertext is a few hundred bytes (fine). For a **media** message the envelope's `encrypted.ciphertext` is the encrypted media descriptor (keys/blob-ids/metadata), which together with the ~1.4 KB base64 ML-KEM `kem` pushes the FCM `data` map past the **4096-byte** limit → hard rejection. The group path is identical (`addGroupEncryptedPushData` `:462-463` → `buildCiphertextOnlyPushMessage`). **There is no payload-size guard anywhere in the relay source** (verified: the only `too large` guards are inbox-frame `maxFrameLen` `:1290/1301` and media-blob limits `media.go:27`).

What must improve: an oversized (media) envelope must still produce a **visible fallback notification** under 4 KB so the offline recipient is alerted; the client fetches the real message from the inbox on open.
What must stay unchanged (→ preserved sentinels): the small-text ciphertext-only silent push (local-decrypt preview), inbox storage/custody, the media blob path, route metadata for intros/contact_request/group_invite, and the existing push tests.

## Root Cause (verify → refute confirmed)
Survived refute (direct source read; graphify-arch excludes the Go relay):
- `inbox.go:442-444` (`addChatEncryptedPushData`) and `:462-463` (`addGroupEncryptedPushData`) embed the full `ciphertext` (and `kem`) into the FCM `data` map with **no size cap**.
- `inbox.go:387` (`buildCiphertextOnlyPushMessage`) sends a `Notification`-less silent data push; the only fallback alert is APNS-side (`:392-395`), but a >4 KB `data` map is rejected **before** anything is delivered (FCM rejects the whole message).
- `inbox.go:179-223` (`sendWithRetry`) logs the exact observed strings; the `Message is too large` error is not an invalid-token error, so it retries 3× and gives up (`:208-222`) — no notification sent.
- No budget constant exists (`grep` for `maxPushData`/`4096`/`4000`/`3500` in non-test `.go` → none).

Refuted / do-NOT-re-introduce:
- **"Already fixed / a size cap exists."** REFUTED — no payload-size guard in source; ciphertext is embedded unconditionally.
- **"It's the media blob itself in the push."** REFUTED — the blob goes via the media store (`media.go`); the push carries only the *message envelope* ciphertext (the encrypted media *descriptor*), which is what exceeds 4 KB.
- **Build-skew.** REFUTED — HEAD `inbox.go` matches deployed v1.5.1 behavior; the error is in production logs from the running binary.

## Real Scope
In scope (`go-relay-server/inbox.go` only):
- Add `maxPushDataBytes` const + `pushDataSize(data map[string]string) int` helper (sum of key+value bytes).
- In `buildPushMessage` (new_message branch, after `addChatEncryptedPushData`) and `buildGroupPushMessage` (after `addGroupEncryptedPushData`): if `pushDataSize(data) > maxPushDataBytes`, drop the oversized fields (`ciphertext`, `kem`, `nonce`) and build a **visible generic fallback** message (a `Notification` + Android `Notification` + APNS `Alert`, like the non-ciphertext default branch `:340-371`) carrying only minimal routing (`type`, `sender_id`/`groupId`, `message_id`, `preview_unavailable="1"`). Net: offline media recipient gets a generic "New message" alert instead of nothing.
- Emit a metric label for observability (`pushSentCounter.WithLabelValues("oversized_fallback")` or similar) so the fallback is countable.

Out of scope (owning work):
- Bug 1 (Dart notif-open drain) → `141-…`.
- Shrinking the media *envelope* itself / not encrypting the descriptor (client-side; separate).
- Changing the silent ciphertext-only design for normal-size messages, inbox custody, or the media blob transfer.

## Files To Inspect Next
Production: `go-relay-server/inbox.go` (`buildPushMessage` 274, `buildGroupPushMessage` 374, `buildCiphertextOnlyPushMessage` 387, `addChatEncryptedPushData` 428, `addGroupEncryptedPushData` 448, `addTrimmedData` 482, `sendWithRetry` 170).
Direct tests: `go-relay-server/inbox_test.go` (`recordingPushSender` 22-68; `TestBuildChatPushMessage_CarriesEncryptedDataWithoutPlaintextPreview` 636; `TestBuildGroupPushMessage_CarriesEncryptedDataWithoutPlaintextPreview` 883; `TestGIRD006BuildGroupImagePushMessageUsesCanonicalDataOnlyIdentity` 1016).
Dependency-only context: `go-relay-server/main.go` (push wiring), `metrics.go` (`pushSentCounter`).

## Existing Tests Covering This Area
- `TestBuildChatPushMessage_CarriesEncryptedDataWithoutPlaintextPreview` (inbox_test.go:636) — small encrypted chat → asserts `data["kem"/"ciphertext"/"nonce"]` embedded, APNS custom data. **PRESERVATION sentinel** (small path must stay ciphertext-only). Uses tiny ciphertext `"c"` → never exercises >4 K.
- `TestBuildChatPushMessage_LegacyPlaintextEnvelopeEmitsOnlyFallbackAndRouteData` (:568) — legacy plaintext fallback route data.
- `TestBuildGroupPushMessage_CarriesEncryptedDataWithoutPlaintextPreview` (:883) + `TestGIRD006BuildGroupImagePushMessageUsesCanonicalDataOnlyIdentity` (:1016) — small group/image ciphertext (`"gc"`). PRESERVATION sentinels.
Missing coverage gap: **no test builds an oversized (media-scale) ciphertext**, so the >4 KB rejection path is entirely uncovered. No payload-size assertion exists anywhere.
Curated family arrays: N/A (Go; `go test ./...` auto-discovers all `*_test.go` in package `main` — no `run_test_gates.sh` involvement).

## RED Test Catalog (add BEFORE any production code — INV-RED-FIRST)
1. `go-relay-server/inbox_test.go`::`TestBuildChatPushMessage_OversizedCiphertextFallsBackUnder4K`
   - Tier: Go unit (package `main`, direct call to `buildPushMessage`).
   - Shape/setup: construct a 1:1 envelope `{"type":"chat_message","version":"2","id":"m-media","senderUsername":"Alice","encrypted":{"kem":"<~1500 B>","ciphertext":"<~5000 B base64>","nonce":"n"}}` (ciphertext sized like an encrypted media descriptor). Call `msg := buildPushMessage(token, fromPeerId, envelope)`. Assert: `pushDataSize(msg.Data) <= maxPushDataBytes` (≤ ~4000), `msg.Data["ciphertext"] == ""` and `msg.Data["kem"] == ""` (dropped), `msg.Notification != nil` (visible fallback present), `msg.Data["preview_unavailable"] == "1"`, and routing kept (`msg.Data["type"]=="new_message"`, `msg.Data["sender_id"]==fromPeerId`, `msg.Data["message_id"]=="m-media"`).
   - RED on HEAD because: today `buildPushMessage` embeds the full ciphertext (`pushDataSize > 4096`), `Notification` is nil (`buildCiphertextOnlyPushMessage`), and `preview_unavailable` doesn't exist → every assertion fails (and `pushDataSize`/`maxPushDataBytes` don't compile until added).
   - GREEN after fix asserts: oversized → trimmed, under-budget, visible fallback.
   - Mutation that re-reds: revert the size-check/fallback in `buildPushMessage` → ciphertext re-embedded, `pushDataSize > 4096`, `Notification` nil → RED.
   - Distinct-event discriminator: `preview_unavailable=="1"` AND `ciphertext==""` (fallback) vs. TC-03-preservation's `ciphertext!=""` AND no `preview_unavailable` (normal silent push) — distinguishes the two build paths.
2. `go-relay-server/inbox_test.go`::`TestBuildGroupPushMessage_OversizedCiphertextFallsBackUnder4K`
   - Tier: Go unit (`buildGroupPushMessage`).
   - Shape/setup: group envelope `{"kind":"group_offline_replay","version":1,"payloadType":"group_message","keyEpoch":7,"messageId":"g-media","ciphertext":"<~5000 B>","nonce":"gn"}`. Assert the same budget/fallback invariants (`pushDataSize<=max`, `ciphertext==""`, `Notification!=nil`, `preview_unavailable=="1"`, `groupId`/`message_id` kept).
   - RED on HEAD because: group path also embeds full ciphertext via `buildCiphertextOnlyPushMessage` → >4 KB, no Notification.
   - GREEN: group fallback parity.
   - Mutation that re-reds: revert the group-path size-check → RED.
3. `go-relay-server/inbox_test.go`::`TestBuildChatPushMessage_SmallCiphertextStaysCiphertextOnly` (preservation — may reuse/extend existing :636)
   - Tier: Go unit.
   - Shape/setup: small ciphertext (`"c"`). Assert UNCHANGED behavior: `msg.Data["ciphertext"]=="c"`, `msg.Data["kem"]=="k"`, `msg.Notification == nil` (silent ciphertext-only), `msg.Data["preview_unavailable"]` absent, `pushDataSize <= maxPushDataBytes`.
   - RED on HEAD because: passes today — authored to FAIL if the fix wrongly trims/added a Notification to SMALL messages (over-trigger).
   - GREEN: small path untouched.
   - Mutation that re-reds: make the size check always-true (trim unconditionally) → small message loses ciphertext / gains Notification → RED.
4. `go-relay-server/inbox_test.go`::`TestPushDataSize_BoundaryAtBudget`
   - Tier: Go unit (helper).
   - Shape/setup: table test — a `data` map exactly at `maxPushDataBytes` stays as-is; one byte over triggers `pushDataSize > maxPushDataBytes`. Asserts the helper counts key+value bytes correctly.
   - RED on HEAD because: `pushDataSize`/`maxPushDataBytes` don't exist → compile failure.
   - GREEN: helper boundary correct.
   - Mutation that re-reds: off-by-one in `pushDataSize` (e.g. value-only) → boundary assertion RED.

## Test Coverage Matrix (ZERO empty cells in tier / mutation / gate / registration)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-01 1:1 oversized → fallback <4K | pure build logic (Go) | Go unit | `inbox_test.go::TestBuildChatPushMessage_OversizedCiphertextFallsBackUnder4K` | ciphertext embedded → `pushDataSize>4096`, `Notification` nil, no `preview_unavailable` (+ won't compile w/o helper) | revert size-check in `buildPushMessage` → RED | `cd go-relay-server && go test ./... -run TestBuildChatPushMessage_OversizedCiphertextFallsBackUnder4K -count=1` | **AUTO** (`go test ./...` discovers `*_test.go` in package main) |
| TC-02 group oversized → fallback <4K | pure build logic | Go unit | `inbox_test.go::TestBuildGroupPushMessage_OversizedCiphertextFallsBackUnder4K` | group path embeds ciphertext → >4 KB | revert size-check in `buildGroupPushMessage` → RED | `cd go-relay-server && go test ./... -run TestBuildGroupPushMessage_OversizedCiphertextFallsBackUnder4K -count=1` | AUTO |
| TC-03 small text unchanged | preservation | Go unit | `inbox_test.go::TestBuildChatPushMessage_SmallCiphertextStaysCiphertextOnly` (+ existing :636/:883/:1016) | passes today; fails if fix over-trims small msgs | make size-check always-true → small msg trimmed → RED | `cd go-relay-server && go test ./... -run 'TestBuildChatPushMessage|TestBuildGroupPushMessage' -count=1` | AUTO |
| TC-04 budget helper boundary | pure helper | Go unit | `inbox_test.go::TestPushDataSize_BoundaryAtBudget` | helper/const don't exist → compile fail | off-by-one in `pushDataSize` → RED | `cd go-relay-server && go test ./... -run TestPushDataSize_BoundaryAtBudget -count=1` | AUTO |
| TC-05 media push delivered offline (PROD-CRITICAL) | real FCM 4K acceptance, on device | deploy/device observation | EC2 `journalctl -u relay-server` shows `[PUSH] Notification sent` (not `Failed … too large`) for an offline media recipient | revert fix + redeploy → `too large` returns | (manual) build+scp+restart, then observe journal | **MANUAL: EC2 redeploy + on-device send to offline recipient** (no host test can prove FCM acceptance) |

## Invariants (locked by tests)
- INV-1: Any push whose assembled `data` would exceed `maxPushDataBytes` is rebuilt as a visible, under-budget fallback (ciphertext/kem dropped, `Notification` set, `preview_unavailable="1"`). → TC-01, TC-02.
- INV-2: Small (text-scale) ciphertext pushes are UNCHANGED — ciphertext-only silent push, no Notification, no trim. → TC-03.
- INV-3: `pushDataSize` counts key+value bytes; budget boundary is exact. → TC-04.
- INV-4 (PROD-CRITICAL): a media message to an offline recipient actually delivers a notification (FCM accepts the <4 KB message). → TC-05 (device).
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. `git status --short` snapshot. Add RED tests TC-01..TC-04; `go test ./... -run 'Oversized|PushDataSize' -count=1` → confirm RED (compile failure until helper exists is acceptable RED; then real assertion RED once helper stubbed).
2. `inbox.go`: add `const maxPushDataBytes = 4000` (headroom under FCM's 4096) + `func pushDataSize(data map[string]string) int`.
3. `inbox.go` `buildPushMessage` new_message branch (after `addChatEncryptedPushData` `:284`): if `pushDataSize(data) > maxPushDataBytes`, delete `ciphertext`/`kem`/`nonce`, set `data["preview_unavailable"]="1"`, and return a **visible** message (reuse the default-branch shape `:340-371`: generic `Notification`/Android `Notification`/APNS `Alert`) instead of `buildCiphertextOnlyPushMessage`. Stop-if: dropping fields still leaves >budget → also drop any other non-routing field; keep only `type`/`sender_id`/`message_id`/`preview_unavailable`.
4. `inbox.go` `buildGroupPushMessage` (after `addGroupEncryptedPushData` `:382`): same trim+visible-fallback (keep `type`/`groupId`/`message_id`/`preview_unavailable`).
5. `metrics.go`/inline: add `pushSentCounter.WithLabelValues("oversized_fallback").Inc()` at the fallback (observability).
6. `go test ./...` full suite green; `go vet ./...`; `gofmt -l .` empty.
7. Deploy to EC2 (below) and observe TC-05.

## Risks And Edge Cases
- **iOS NSE expects ciphertext to decrypt+mutate the alert.** Dropping ciphertext means the NSE can't enrich — but the fallback provides a visible generic `Alert`, so iOS still shows "New message". Pinned by TC-01 (`Notification!=nil`); device-confirmed by TC-05.
- **Android silent-data handler builds the notification from ciphertext.** Without ciphertext it can't — so the fallback MUST include an Android `Notification` block (visible). Pinned by TC-01 (assert `msg.Android.Notification != nil`).
- **Budget headroom:** FCM's 4096 applies to the `data` payload; choose `maxPushDataBytes=4000` to leave margin for SDK overhead. Documented in TC-04.
- **Over-trigger on borderline text:** a long-but-legitimate text could trip the budget and lose its local-decrypt preview (degrades to generic alert). Acceptable (still delivered); INV-2/TC-03 ensures normal text is untouched.

## Device/Relay Proof Profile
host-only for TC-01..TC-04; **requires EC2 redeploy + on-device send-to-offline-recipient for TC-05 (PROD-CRITICAL closure)**.
Closure observation: relay journal shows `[PUSH] Notification sent to <peer>` (not `Failed … Message is too large`) for a media message whose recipient is offline; recipient device shows a generic notification.
Deploy/closure commands:
```bash
cd go-relay-server
GOOS=linux GOARCH=amd64 go build -o relay-server-linux-amd64 .
scp -i ../se.pem relay-server-linux-amd64 ubuntu@mknoun.xyz:/tmp/relay-server
ssh -i ../se.pem ubuntu@mknoun.xyz \
  'sudo install /tmp/relay-server /usr/local/bin/relay-server && sudo systemctl restart relay-server && systemctl is-active relay-server && /usr/local/bin/relay-server version'
# Then: send a media message to an OFFLINE recipient; on EC2:
ssh -i ../se.pem ubuntu@mknoun.xyz 'journalctl -u relay-server -n 60 --no-pager | grep PUSH'
```

## Acceptance Gates (literal — copy/paste)
```bash
cd go-relay-server

# RED (before production edits) — must FAIL/NOT COMPILE for the documented reason
go test ./... -run 'TestBuildChatPushMessage_OversizedCiphertextFallsBackUnder4K' -count=1   # RED
go test ./... -run 'TestBuildGroupPushMessage_OversizedCiphertextFallsBackUnder4K' -count=1  # RED

# Direct GREEN (after fix)
go test ./... -run 'Oversized|TestPushDataSize_BoundaryAtBudget' -count=1

# Preservation (small/text/group/image push paths unchanged)
go test ./... -run 'TestBuildChatPushMessage|TestBuildGroupPushMessage|TestGIRD006' -count=1

# Full relay suite + hygiene
go test ./... -count=1
go vet ./...
gofmt -l .            # expect: no output (all formatted)

# Deploy + on-device closure (TC-05) — see Device/Relay Proof Profile
```

## Known-Failure Interpretation
- Expected RED: TC-01, TC-02, TC-04 before the fix (and compile failure until `pushDataSize`/`maxPushDataBytes` exist).
- Pre-existing dirty: large uncommitted `new-feed` tree — Go relay files are not part of that churn; `git diff` should show only `go-relay-server/inbox.go` (+ optional `metrics.go`) and `inbox_test.go`.
- Environment blocker (NOT product): TC-05 needs EC2 deploy access + a second device offline; absence defers closure, not host correctness.
- Scope drift (BLOCKING): any change to inbox storage/custody, media blob path, or non-`new_message` route metadata.

## Done Criteria
- [x] RED added first (TC-01/02/04), failed for the expected reason (compile-fail on missing helper/const).
- [x] Mutation-verified (each fix has a re-red revert) — 4 plan mutations + clamp-drop + MutableContent assert, all re-red then reverted.
- [x] `go test ./...` green (11.6s); `go vet` clean; `gofmt -l .` empty.
- [x] Preservation push tests (text/group/image/native-v3 small ciphertext) green; diff purely additive (0 deletions) so existing routes/tests byte-unchanged.
- [ ] EC2 redeploy done; relay journal shows `Notification sent` (not `too large`) for an offline media recipient (TC-05). **PENDING — env-gated (needs deploy access + 2nd device offline).**
- [x] `git diff` limited to `go-relay-server/` (only `inbox.go` + `inbox_test.go`; no Dart/Scope-Guard violations).

### Review-surfaced hardening (beyond original plan)
- Adversarial review found INV-1 was NOT unconditional: the routing-only fallback kept `message_id`, which is copied from the **remote-supplied envelope** (`id`/`messageId`). A pathologically large id keeps even the fallback >4 KB and re-triggers the FCM rejection. Added a defensive clamp in `buildOversizedFallbackPushMessage` (drops `message_id` if the fallback is still over budget) — implements the plan's Step-3 "Stop-if". Pinned by `TestBuildChatPushMessage_OversizedFallbackDropsPathologicalMessageIDUnderBudget` (RED→GREEN, mutation-verified).
- Hardened TC-01/TC-02: assert `MutableContent==false` (no ciphertext to decrypt → no NSE signal; mutation-verified live) and assert APNS `CustomData` routing mirror.
- Refuted (no change): iOS CustomData-with-visible-Alert is valid; Android `Notification` block displays without a Data mirror; `ContentAvailable:true` alongside an Alert does not suppress it (matches the proven non-ciphertext default branch).

## Scope Guard (hard "Do not")
- Do not change inbox storage, custody (`stage→ack→replay`), or the media blob transfer/store.
- Do not alter non-`new_message` route metadata (intros/contact_request/group_invite) — those branches already build visible messages.
- Do not touch the Flutter client (Bug 1, `141-…`).

## Accepted Differences / Intentionally Out Of Scope
- Oversized messages lose the local-decrypt notification preview and show a generic "New message" — acceptable (delivery > preview). A future enhancement could send a short server-side teaser, but the relay cannot read encrypted content, so generic is correct.
- Reducing the media-envelope ciphertext size itself is a client-side change (separate).

## Dependency Impact
- None. Complements Bug 1 (`141-…`): 141 ensures the message surfaces on open; 142 ensures the *notification fires* for offline media recipients. Both are independent and can land/deploy separately.

## Reviewer Findings
Sufficiency: every TC has tier+file+name+RED-reason+mutation+gate+registration (zero empty cells). INV-1..INV-4 locked. PROD-CRITICAL leg (TC-05, real FCM 4K acceptance) named + marked non-host-provable with the redeploy procedure. Preservation sentinels are the existing small-ciphertext push tests (cited by name+line). Go harness-registration correctly stated (auto-discovery; no curated array; no migration). Refuted alternatives (already-fixed / blob-in-push / build-skew) recorded.

## Arbiter Decision
Structural blockers: none. Deferred details: TC-05 EC2 deploy + offline-device observation (environment-gated; host TC-01/02 prove the <4 KB invariant). Accepted differences: generic fallback preview. Verdict: structurally sufficient — hand off to execution.

## Final Execution Verdict
Verdict: **host floor COMPLETE & host-green** (TC-05 EC2/on-device closure pending, env-gated) | Files changed: `go-relay-server/inbox.go` (+`maxPushDataBytes`/`pushDataSize`/`buildOversizedFallbackPushMessage`/2 budget guards/defensive message_id clamp), `go-relay-server/inbox_test.go` (TC-01..04 + TC-06 clamp + TC-01/02 hardening); 314 insertions, 0 deletions | Tests run (+counts): full relay suite `go test ./...` green (~11.6s); 5 new tests PASS; preservation (`TestBuildChatPushMessage*`/`TestBuildGroupPushMessage*`/`TestGIRD006`/native-v3) green; `go vet` clean; `gofmt -l .` empty | Mutation-verified: 6 mutations (4 plan + clamp-drop + MutableContent) each re-red then reverted | Blocking: TC-05 only (relay redeploy to EC2 `ubuntu@mknoun.xyz` + send media to an offline recipient; observe journal `Notification sent` not `Message is too large`) | QA verdict: 12-agent adversarial review = 5 confirmed (1 high code defect FIXED via clamp, 4 test-strengthening DONE), 3 protocol findings refuted | Non-blocking follow-ups (owner): server-side teaser preview (future); coordinate redeploy with any other pending relay changes.
