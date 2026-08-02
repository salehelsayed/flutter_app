# 328 - Group Media Push Notification Integrity

Status: execution-ready (Fix A + Fix C) — **PLANNED, NOT EXECUTED**
Type: Bug (Fix A) + Modification (Fix C)
Spec: free-text intent from the group-notification coverage audit (`wf_97f4ca24-ca3`); no formal spec
Classification: implementation-ready for **Fix A and Fix C**; **Fix B is NOT buildable as proposed** — see Refuted, and the user-owned decision
Closure tier: relay deploy (Go) + host (Dart) + iOS NSE (Swift XCTest)

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-02 | Evidence Collector | coverage audit `wf_97f4ca24-ca3` across `inbox.go`, `NotificationPreviewResolver.swift`, `push_decrypt_preview.dart` | Media-type notification quality never examined by plans 318-327 | Verify each gap in source |
| 2026-08-02 | Planner (lead) | `addGroupEncryptedPushData` (`inbox.go:880-912`) | **Fix B refuted at planning time** — the relay cannot see a media type; it is inside the ciphertext | Re-scope to A + C; surface B as a decision |

## Problem And Evidence

The stated goal is reliable group notifications for **text, images, videos, voice messages and reactions**. Plans 318-327 fixed custody and delivery; none examined what a media message actually renders. Two defects and one inconsistency were found.

### Fix A — contentless pushes render NOTHING (confirmed, highest severity)
- `addGroupEncryptedPushData` returns `false` when the envelope cannot yield key material: `return data["keyEpoch"] != "" && data["ciphertext"] != "" && data["nonce"] != ""` (`go-relay-server/inbox.go:909-911`), or earlier on unmarshal failure (`:882-883`).
- **`inbox.go:552` calls it as a bare statement and discards the result.** The 1:1 path does the same with `addChatEncryptedPushData` at `:428`.
- ⇒ The push ships with no ciphertext **and no `preview_unavailable` flag**, so neither degraded-render branch fires: iOS takes `missing_group_decrypt_input` → `suppressOrdinary` → blanked card (`NotificationPreviewResolver.swift:1070-1091`, `:1253-1270`, `:148-172`); Android throws at `push_decrypt_preview.dart:788`, caught at `background_message_handler.dart:642`, and shows **nothing**.
- **The correct pattern already exists in-repo one file away:** `if (!addGroupEncryptedPushData(data, message)) {` (`reaction_push.go:433`). The reaction lane guards it; the message lanes do not.
- This is a genuine **notification-loss** path, not a quality issue.

### Fix C — degraded-push copy diverges across platforms (confirmed)
On the `preview_unavailable` path iOS keeps the sender prefix — `"\(sender.username): New message"` (`NotificationPreviewResolver.swift:1058-1067`) — while Android's `trustedFallback` drops the sender entirely and shows a bare `Message` (`push_decrypt_preview.dart:739-743`). Same event, two different notifications. Client-side only; no wire change.

### Size cliff (context for both, NOT itself in scope)
The binding constraint is `maxProviderPayloadBytes = 3800` (`inbox.go:68`), not the 4000-byte `maxPushDataBytes`. Measured against the real builders, the degraded path triggers at **2 voice notes, 5 images, 5 videos, or ~2011 ASCII characters** — while the composer allows 10 attachments (`group_conversation_wired.dart:465`) and text allows 10,000 characters (`text_sanitizer.dart:2`). So ordinary user actions cross it routinely. This plan does **not** change the limits or trim the envelope.

## Refuted (do NOT re-introduce)

- **Fix B as originally proposed — "add a `media_type` hint to the fallback routing, ~10 bytes, no content" — is REFUTED.** The relay cannot derive it. `addGroupEncryptedPushData` (`inbox.go:880-912`) enumerates every plaintext envelope field the relay can read: `kind`, `version`, `payloadType`, `keyEpoch`, `ciphertext`, `nonce`, `messageId`, `groupId`. **The media type is inside the encrypted payload**, and the relay holds no key. Emitting `media_type` would require the sending client to publish a **new plaintext field on the wire**, which is (a) a wire-format change with mixed-version rollout, and (b) a real privacy regression — it would tell the relay *and* APNs/FCM that this is a voice note, directly against plan 327, where the user chose privacy and closed plan 148. Recorded as a user-owned decision below, not built.

## Scope Contract And Guard

In scope:
- **A** — check the return of `addGroupEncryptedPushData` at `inbox.go:552` and of `addChatEncryptedPushData` at `:428`; on failure fall through to `buildOversizedFallbackPushMessage` (`:675+`) so a routing-only push with `preview_unavailable` is still sent.
- **C** — Android degraded-push copy gains the sender prefix, matching iOS.

Must preserve:
- The oversized path itself is unchanged → existing oversized tests stay green (TC-328-05 sentinel).
- The reaction lane's existing guard is untouched → `reaction_push.go:433` unchanged (TC-328-06 sentinel).
- Un-updated clients keep working: Fix A only *adds* `preview_unavailable` where nothing renderable was sent before, and that flag is already understood by both shipped presenters.

Hard `Do not`:
- Do not add `media_type` or any new plaintext field to the push (refuted above; needs the user's decision).
- Do not change `maxProviderPayloadBytes`/`maxMessagesPerGroup`, and do not trim the encrypted envelope.
- Do not claim this improves delivery reliability — Fix A closes one true loss path; the rest is what gets rendered.

Deferred / accepted difference:
- **`file` attachments are structurally dead in groups and an arriving one is silently destroyed.** `group_media_mime_policy.dart:15-27` allows no document MIME and the composer has no document picker, so an incoming `file` descriptor is rejected as `disallowed_mime` → `handle_incoming_group_message_use_case.dart:198-210` returns `ignored()` → **no row and no notification**, while both presenters already rendered "sender: File" from the wire array. Owner: needs its own plan (decide block-at-sender vs allow end-to-end).
- GIF renders as "GIF" in-app but "Photo" on both push presenters; an `unsupported` private policy is silent in-app but shows "New private media" on push. Both are copy inconsistencies, deferred.
- The size cliff itself (2 voice notes / 5 images) stays open — closing it means trimming the envelope (the per-attachment `waveform` list alone is ~1000 bytes, `media_attachment.dart:257`), which is its own plan.

Dependencies:
- **Rides plan 324's relay deploy.** Fix A is a relay change; 324 is already queued as a relay change. They should ship as one deploy (v1.7.6), not two.

## Test Contract
| Case | Behavior | Named test/proof | Tier / fixture | HEAD state → GREEN | Mutation that re-reds | Gate / registration |
|---|---|---|---|---|---|---|
| TC-328-01 | A group envelope with unusable key material still yields a renderable push | `go-relay-server/push_envelope_guard_test.go::TestGroupPushFallsBackWhenEnvelopeUnusable` | Go host / envelope missing `nonce` | causal RED (HEAD returns a push with no ciphertext AND no `preview_unavailable`) → returned message carries `preview_unavailable="1"` and required routing | revert the `if !addGroupEncryptedPushData` guard at `:552` → TC-328-01 red | `cd go-relay-server && go test ./...`; AUTO (Go package) |
| TC-328-02 | Same for the 1:1 lane | `go-relay-server/push_envelope_guard_test.go::TestChatPushFallsBackWhenEnvelopeUnusable` | Go host / envelope missing `ciphertext` | causal RED (same shape at `:428`) → `preview_unavailable="1"` present | revert the `:428` guard → TC-328-02 red | same |
| TC-328-03 | iOS renders the degraded card rather than blanking | `ios/RunnerTests/NotificationPreviewResolverTests.swift::testGroupUnusableEnvelopeRendersDegradedCard` | Swift XCTest / userInfo with routing + `preview_unavailable`, no ciphertext | GREEN sentinel (the `preview_unavailable` branch already works, `:1047-1067`) → `"sender: New message"` shown, not suppressed | delete the `preview_unavailable` branch → TC-328-03 red | `bash scripts/test/run_runner_tests_321.sh -only-testing:RunnerTests/NotificationPreviewResolverTests` |
| TC-328-04 | Android degraded copy carries the sender prefix (Fix C) | `push_decrypt_preview_test.dart::328 degraded group push keeps the sender prefix` | unit / fakes | causal RED (HEAD shows bare `Message`, `:739-743`) → `"sender: New message"`, matching iOS | revert the copy change → TC-328-04 red | `flutter test test/features/push/application/push_decrypt_preview_test.dart`; grep-verify `ONE_TO_ONE_TESTS` registration |
| TC-328-05 | The ordinary oversized path is unchanged | `go-relay-server/ordinary_push_projection_test.go` (existing oversized tests) | Go host | GREEN sentinel → unchanged | delete the size check at `:554` → existing tests red | `cd go-relay-server && go test ./...` |
| TC-328-06 | The reaction lane's existing guard is untouched | `go-relay-server/group_reaction_push_test.go` (existing) | Go host | GREEN sentinel → unchanged | remove the guard at `reaction_push.go:433` → existing reaction tests red | same |
| TC-328-07 | Live relay still notifies after deploy | `docker-ws/verify_push_envelope_guard_328.sh` | manual/relay proof against production | manual proof → a real group media send produces a visible notification on the active fleet; zero blanked cards | N/A — deploy-time verification | run inside the 90s stability window, with plan 324 |

### Test Notes
- TC-328-01/02's fixture must make extraction fail for a **realistic** reason (a missing `nonce` or `keyEpoch`), not malformed JSON, so the test exercises `:909-911` rather than the unmarshal guard at `:882-883`.
- TC-328-03 is a sentinel because the iOS branch already handles `preview_unavailable` correctly — Fix A's value is that the flag now *gets set*. The causal weight is on TC-328-01/02.
- TC-328-04 must assert the exact rendered string, not merely that something was shown, or the parity claim is unproven.

## Implementation Steps
1. Snapshot `git status --short`. Add TC-328-01/02/04; confirm all three red for the documented reasons.
2. **Fix A** — at `inbox.go:552` and `:428`, guard the return and fall through to the oversized fallback, mirroring `reaction_push.go:433`. Stop-if: the fallback builder refuses the send for missing required routing (`hasRequiredFallbackRouting`, `:677-679`) → then the correct behaviour is to send nothing and emit a counter, not to ship a blank card; record which.
3. **Fix C** — Android `trustedFallback` gains the sender prefix (`push_decrypt_preview.dart:739-743`).
4. Run Go tests → Swift NSE test → Dart focused → graph-affected → `1to1` lane.
5. Deploy **with plan 324** as relay v1.7.6; run TC-328-07.

## Risks And Blind Spots
- **Deploy risk dominates** — production relay, no staging twin. Mitigated by riding 324's single deploy, toolchain-verified binary, backup, 90s window, live TC-328-07.
- Fix A could turn a silent no-notification into a *visible generic* notification for envelopes that are malformed for a reason we would rather not surface — acceptable, and strictly better than silence, but worth watching the `oversized_fallback` counter after deploy.
- Sibling-surface consistency: three push builders exist (`:428` chat, `:552` group, `reaction_push.go:433` reaction); after this plan all three guard the return → TC-328-01/02/06.
- Destructive-action side effects: none — no deletion, no schema, no wire-format change.
- Build-artifact provenance: `GOTOOLCHAIN=go1.25.0` pinned; verify `go version <binary>` before upload.
- Fake side-effect fidelity: TC-328-04 uses the real copy-derivation path, not a stubbed string.
- Permission/ACL verb symmetry: N/A — no ACL change.

## Rollback
Relay-only for Fix A: redeploy the previous binary from the `relay-server.pre-328-<stamp>` backup. Clients tolerate both shapes unconditionally (the `preview_unavailable` flag is already understood by shipped presenters, and its absence is today's behaviour). Fix C is client-only: `git revert`.

## Gate Cadence
- Per-plan closure: TC-328-01..06 + `cd go-relay-server && go test ./...` + the Swift NSE test + the `1to1` curated lane (the push fallback surfaces live there) + TC-328-07 live.
- Graph-affected first: after the Dart edit, run `tdd_context.py affected lib/features/push/application/push_decrypt_preview.dart --budget 600` and run the named files directly. Go and Swift have no arch-graph edges.
- Full `host-all` is **not** a per-plan gate; owned by the notification-reliability wave closure and final release closure.

## Acceptance Gates  (literal — copy/paste)
```bash
git status --short

# Causal RED (before edits)
cd go-relay-server && go test ./... -run TestGroupPushFallsBackWhenEnvelopeUnusable

# Focused GREEN (after)
cd go-relay-server && go test ./...
flutter test test/features/push/application/push_decrypt_preview_test.dart
bash scripts/test/run_runner_tests_321.sh -only-testing:RunnerTests/NotificationPreviewResolverTests

# Graph-affected dependents BEFORE the lane
python3 graphify-arch/tdd_context.py affected \
  lib/features/push/application/push_decrypt_preview.dart --budget 600

# Curated lane
./scripts/run_test_gates.sh 1to1

# Registration is grep-verified, never run-verified
grep -c 'test/features/push/application/push_decrypt_preview_test.dart' scripts/run_test_gates.sh
./scripts/run_test_gates.sh completeness-check   # expect: PASS, 0 unmatched

# Build with the pinned toolchain, prove it, then deploy WITH plan 324
cd go-relay-server && GOTOOLCHAIN=go1.25.0 GOOS=linux GOARCH=amd64 go build -o relay-server .
go version relay-server        # expect: go1.25.0
bash docker-ws/verify_push_envelope_guard_328.sh

# Hygiene
flutter analyze
cd go-relay-server && gofmt -l .   # expect: empty
git diff --check
```

## Execution Interpretation And Done Criteria
- Expected RED: TC-328-01/02 (HEAD ships a push with neither ciphertext nor `preview_unavailable`), TC-328-04 (Android shows a bare `Message`).
- GREEN sentinel: TC-328-03 (iOS degraded branch), TC-328-05 (oversized path), TC-328-06 (reaction guard).
- Pre-existing dirty tree: the three user-owned claude-docker files — never staged.
- Scope drift (BLOCKING): any new plaintext push field; any change to size limits or the envelope; any separate relay deploy rather than riding 324.

- [ ] Every behavior has a named test or a justified proof.
- [ ] Causal RED, focused GREEN, and mutation re-red recorded.
- [ ] Preservation sentinels and named gates pass.
- [ ] Harness registration implemented AND grep-verified.
- [ ] Relay deploy proof (TC-328-07) passes inside the stability window, shipped with 324.
- [ ] `flutter analyze` clean; `gofmt -l .` empty; `git diff --check` clean.

## Handoff
- First causal RED command: `cd go-relay-server && go test ./... -run TestGroupPushFallsBackWhenEnvelopeUnusable`.
- Preservation command: `cd go-relay-server && go test ./...`.
- Manual registration: the new Dart test needs `ONE_TO_ONE_TESTS` (grep-verify); Go tests are AUTO by package.
- Migration: none.
- Boundary closure: relay deploy (with 324) + iOS NSE XCTest + live TC-328-07.
- **Unresolved / user-owned: whether to publish a plaintext `media_type` hint** so degraded pushes can say "Alice: Video" instead of "Alice: New message". It cannot be derived at the relay (refuted above) and would require a new plaintext wire field, telling the relay and APNs/FCM the media type. That trades directly against plan 327. Not defaulted; the user decides.

## Device/Relay Proof Profile
- Profile: relay (single production box, no staging twin) + iOS simulator for the NSE XCTest.
- Boundary being proven: a real group media send produces a visible notification rather than a blanked card.
- Live availability check: active fleet is iPhone 11 (`00008030…`) + iPhone 13 (`00008110…`) + the Pixel.
- Rollback: `relay-server.pre-328-<stamp>` backup; relay-only rollback is safe.

## Execution Progress
| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | - | awaiting go-ahead; ships with 324 | contract extraction |
