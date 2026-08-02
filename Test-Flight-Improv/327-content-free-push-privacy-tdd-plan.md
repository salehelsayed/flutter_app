# 327 - Content-Free Push (notification-metadata privacy)

Status: planning-draft — **PLANNED, NOT EXECUTED** (user decision 2026-08-02)
Type: Feature Improvement (privacy hardening)
Spec: free-text intent; successor to the closed content concern in `74-privacy-preserving-notification-previews.md`
Classification: **evidence-gated** — Stage A is implementation-ready, Stage B is implementation-ready pending one product decision, Stage C is **prerequisite-blocked** on a feasibility spike
Closure tier: relay deploy + host + iOS NSE boundary (per stage; see Gate Cadence)

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-02 | Evidence Collector | `go-relay-server/inbox.go`, `reaction_push.go`, `ios/NotificationService/*.swift`, `background_message_handler.dart` | Content does NOT leak; metadata + display names DO | Census the exposure precisely |
| 2026-08-02 | Planner | `74-privacy-preserving-notification-previews.md`, `148-minimum-parity-encrypted-push-spool-tdd-plan.md`, `173-…:39` | 74's concern is closed; 148 is in direct tension; a reduced-payload path already ships | Stage the work by threat-model delta |

## Problem And Evidence

- **Behavior to improve:** every push we send hands Apple (APNs) and Google (FCM) a structured description of who is talking to whom, in which group, when, and about what kind of event — plus display names. Message *content* is safe; the social graph and activity timeline are not.
- **Impact:** a push provider (or anyone who compromises our APNs key / FCM service account) can reconstruct a per-user contact graph, group membership, and activity times without ever decrypting a message.
- **Confirmed current exposure (this is a census, not a bug):**

  | Field | Where built | What it reveals |
  |---|---|---|
  | `type` | `inbox.go:422`, `:435`, `:485`, `:545`; `reaction_push.go:420`, `:526` | activity class — `new_message` / `group_message` / `group_reaction` / `message_reaction` / `group_invite` / `contact_request` / `intros` |
  | `sender_id` | `inbox.go:423`, `:490` | the 1:1 counterparty |
  | `groupId` | `inbox.go:493`, `:546` | which group |
  | `sender_transport_peer_id` | `inbox.go:547` | the group sender |
  | `message_id` | `inbox.go:426`, `:496`, `:550` | per-message correlator |
  | `event_id`, `target_message_id`, `reactor_peer_id`, `reactor_transport_peer_id`, `base_envelope_hash`, `notification_extension` | `reaction_push.go:418-432`, `:524-534` | who reacted to whose message |
  | `sender_username` / `senderUsername` | `inbox.go:498-500` | **display name in clear** |
  | group name | `inbox.go:458-459`, `:1109` | **group name in clear**, inside invite title/body |
  | `kem` / `ciphertext` / `nonce` | `addChatEncryptedPushData` `inbox.go:860-878`; `addGroupEncryptedPushData` `:880+` | encrypted content — safe, but its presence and size are observable |

- **Content does NOT leak — state this plainly and do not overclaim.** The visible-alert path (`inbox.go:447-500`) sets `title`/`body` from fixed templates only; `metadata.Body` is assigned solely at `:1031`, `:1054`, `:1080` (`"<username> wants to connect"`), `:1109`/`:1111` (`"<username> invited you to <groupName>"`). Group message pushes carry no title/body at all (`:544-551`). So this is a **metadata + display-name** exposure.
- **Prior art reconciled (the skill requires this — do not duplicate):**
  - `74-privacy-preserving-notification-previews.md` targeted **cleartext preview text** in group push payloads. That concern is **closed**: group message pushes are ciphertext-only plus routing (`inbox.go:544-551`), and previews are resolved on-device (iOS NSE `BridgePushDecryptor`; Android fallback). 327 is its **successor**, scoped to metadata, not content.
  - `148-minimum-parity-encrypted-push-spool-tdd-plan.md` is a **latency** plan that wants a *richer* push payload spooled for a fast notification-tap render. It is **BLOCKED on its own Phase-0 evidence gate** and never executed. **327 and 148 are in direct tension** — 327 shrinks what 148 wants to spool. Whichever is executed first constrains the other; this must be an explicit decision, not an accident.
  - `173-…:39` records that a **reduced-payload path already ships**: when `pushDataSize(data) > maxPushDataBytes` (4000), `buildOversizedFallbackPushMessage` sends only `type`, `sender_id`, `preview_unavailable=1`, `[message_id]`. **The client already handles an envelope-less push.** That is a proven mechanism Stage A/B can reuse rather than invent.
- **Refuted findings (do NOT re-introduce):**
  - *"A contentless wake improves delivery reliability."* — **refuted by construction.** If the push is lost, an empty wake is lost identically. Signal's resilience comes from a persistent connection while the app is alive, not from the payload being empty. 327 must never be sold as a reliability fix; the reliability wave (315/316/319/320/322) owns that.
  - *"Just adopt Signal's model."* — **prerequisite-blocked, not refuted.** Signal's presenter is its NSE, and Signal's NSE fetches from the server. Ours cannot today: `ios/NotificationService/` contains only `NotificationService.swift` (143 lines) and `NotificationPreviewResolver.swift` (3029 lines), and a grep for `URLSession`/`WebSocket`/`http` returns **zero**. It is a purely local resolver (keychain keys, push-carried envelope decrypt, App Group stores). Android is the same shape — `background_message_handler.dart:378`: *"local notification shown if routable; inbox drain on next resume."*
- **Unresolved findings (these are what make the plan evidence-gated):**
  - **U1 — can the NSE fetch at all?** Unknown whether relay I/O + ML-KEM decrypt + inbox-cursor state fit the extension's ~24MB budget, without opening SQLCipher (a standing project rule). Needs a spike; blocks Stage C.
  - **U2 — display-name resolution coverage.** Stage A removes `sender_username`. The client can usually resolve a name locally, but not for a `contact_request` or `group_invite` from a peer it has never seen. The resulting copy is a product decision.
  - **U3 — relay-held token mapping.** Stage B's threat model is APNs/FCM specifically; the relay already knows sender/group/message because it routes them. So the relay *may* hold the token↔identity mapping without weakening anything. Needs an explicit threat-model sign-off before it is treated as settled.
- **Affected files (per stage):** `go-relay-server/inbox.go`, `reaction_push.go`; `lib/features/push/application/background_message_handler.dart`, `background_push_notification_fallback.dart`, `push_decrypt_preview.dart`; `ios/NotificationService/NotificationPreviewResolver.swift`.

## Graph Grounding Snapshot
- Graph fingerprint / freshness: arch graph refreshed 2026-08-02 (`REFRESH_EXIT=0`). The relay (Go) and the iOS NSE (Swift) are **outside** the arch graph by design, so the majority of this plan is grounded by direct source reads.
- Query / profile: N/A for the Go/Swift surfaces; the Dart push surfaces were reached from the plan-322/323 grounding pass.
- Anchors: `buildPushMessage`, `addChatEncryptedPushData`, `addGroupEncryptedPushData`, `buildGroupReactionPushMessage`, `buildOversizedFallbackPushMessage`, `NotificationPreviewResolver`.
- Surfaced proof/gate files: `go-relay-server/ordinary_push_projection_test.go`, `group_reaction_push_test.go`, `ios/RunnerTests/NotificationPreviewResolverTests.swift`.
- Graph gaps that required raw source search: the entire payload census (Go), and the NSE capability question (Swift).
- Reuse rule: anchors are search starting points; every conclusion above is re-verified in current source.

## Scope Contract And Guard

In scope — **staged, each stage independently shippable**:
- **Stage A — strip display names.** Remove `sender_username`/`senderUsername` (`inbox.go:498-500`) and group names from invite titles/bodies (`:458-459`, `:1109`) from provider-visible data; resolve them on-device where the client already can. Threat-model delta: removes the direct identity-to-name mapping. Cost: lowest. Relay deploy + client copy.
- **Stage B — opaque routing tokens.** Replace `sender_id`, `groupId`, `message_id`, and the reaction correlators with per-event opaque tokens the client resolves locally. Threat-model delta: breaks the provider's ability to build a stable contact/group graph across events — the largest real win. Cost: relay mints and stores the mapping; client resolves. See U3.
- **Stage C — Signal model (NSE fetches).** Payload becomes a bare wake; the extension retrieves and decrypts. Threat-model delta: provider sees only "this device has something". **Blocked on U1.**

Must preserve:
- The existing oversized-fallback path keeps working (`buildOversizedFallbackPushMessage`, `inbox.go:434-442`) → GREEN sentinel.
- Notification dedupe identity survives any payload change — `boundedReactionEventIdentity` parity across relay/NSE/Android (`deterministic_notification_id.dart:27-34`, `NotificationPreviewResolver.swift:1911-1915`) → this is the single highest-risk coupling; a token change that breaks it double-alerts every reaction.
- Tap routing still resolves a conversation (`NotificationRouteTarget`).
- The reliability wave's guarantees are untouched — no change to wake semantics, claim, or tone lease.

Hard `Do not`:
- Do not sell or gate this as a reliability improvement (refuted above).
- Do not start Stage C before U1's spike returns.
- Do not execute 327 and 148 concurrently — they pull the payload in opposite directions.
- Do not reduce payload without a matching client release: legacy clients must still render. Mixed-version rollout is a hard constraint (see Rollback).

Deferred / accepted difference:
- Push *timing and frequency* remain observable to the provider under all three stages. No stage claims to fix traffic analysis.
- Payload *size* remains a weak signal (envelope present vs absent). Stage C removes it; A and B do not.

Dependencies:
- Conflicts with plan 148 (see Prior art). One must be chosen.

## Test Contract
Zero empty cells. Rows are grouped by stage; **only Stage A + the cross-cutting rows are execution-ready today.**

| Case | Behavior | Named test/proof | Tier / fixture | HEAD state → GREEN | Mutation that re-reds | Gate / registration |
|---|---|---|---|---|---|---|
| TC-327-01 | No provider-visible field carries a display name (Stage A) | `go-relay-server/push_privacy_census_test.go::TestPushDataCarriesNoDisplayName` | Go host / table-driven over every push builder | causal RED (HEAD sets `sender_username`/`senderUsername` at `inbox.go:498-500`) → every builder's data map is asserted against an allow-list containing no name field | re-add `sender_username` to the map → TC-327-01 red | `cd go-relay-server && go test ./...`; AUTO (Go package) |
| TC-327-02 | Invite copy carries no group name (Stage A) | `go-relay-server/push_privacy_census_test.go::TestInviteCopyOmitsGroupName` | Go host | causal RED (`inbox.go:458-459`, `:1109` embed it) → templated copy only | restore the interpolated group name → TC-327-02 red | same |
| TC-327-03 | The client still renders a usable alert without the name (Stage A) | `background_push_notification_fallback_test.dart::327 resolves sender display name locally when the push omits it` | unit / fakes | causal RED (no local-resolution path exists for the name-absent case) → resolved name shown when known; documented generic copy when not | remove the local resolution → TC-327-03 red | `flutter test test/features/push/application/…`; AUTO (`test/features` glob) — confirm `ONE_TO_ONE_TESTS` registration by grep |
| TC-327-04 | The iOS NSE renders the same alert without the name (Stage A) | `ios/RunnerTests/NotificationPreviewResolverTests.swift::testResolvesDisplayNameWhenPushOmitsIt` | Swift XCTest / App Group fixtures | causal RED (resolver reads the name from `userInfo`) → resolves from the App Group projection instead | make the resolver fall back to `userInfo` → TC-327-04 red | `scripts/test/run_runner_tests_321.sh -only-testing:RunnerTests/NotificationPreviewResolverTests` |
| TC-327-05 | Reaction dedupe identity is unchanged by any payload change (cross-cutting) | `go-relay-server/push_privacy_census_test.go::TestReactionEventIdentityUnchanged` + `NotificationPreviewResolverTests.swift` parity test | Go host + Swift XCTest | GREEN sentinel (parity holds today: `reaction_push.go:422` ↔ `deterministic_notification_id.dart:27-34` ↔ `NotificationPreviewResolver.swift:1911-1915`) → still identical after the payload change | change the relay's `event_id` source → the parity test reds | both gates above |
| TC-327-06 | The oversized fallback still ships a renderable push (cross-cutting) | `go-relay-server/ordinary_push_projection_test.go` (existing oversized tests) | Go host | GREEN sentinel → unchanged | delete the fallback branch (`inbox.go:434-442`) → existing test reds | `cd go-relay-server && go test ./...` |
| TC-327-07 | A legacy client still renders a Stage-A push (mixed-version rollout) | `background_push_notification_fallback_test.dart::327 a payload without sender_username still routes and renders` | unit / fakes simulating the pre-327 client contract | causal RED (today's client reads the name from the payload) → routes and renders with generic copy | make the client require the name → TC-327-07 red | same as TC-327-03 |
| TC-327-08 | Provider-visible payload matches a pinned allow-list (freeze) | `go-relay-server/push_privacy_census_test.go::TestPushDataFieldAllowList` | Go host / explicit allow-list per push type | causal RED (HEAD's field set exceeds the Stage-A allow-list) → every builder's key set ⊆ allow-list | add any new field to a builder without amending the list → TC-327-08 red | same |
| TC-327-09 *(Stage B, not yet executable)* | Routing identifiers are opaque per-event tokens | `go-relay-server/push_token_privacy_test.go::TestRoutingIdentifiersAreOpaque` | Go host | **BLOCKED on U3 sign-off** — contract written, not runnable until the token design is accepted | N/A until designed | same |
| TC-327-10 *(Stage C, not yet executable)* | NSE fetches and presents without a payload | `integration_test/…` device proof, iOS | **BLOCKED on U1 spike** — the NSE has no network capability today | N/A until the spike returns | device proof; scenario TBD |

### Test Notes
- **TC-327-08 is the row that keeps this honest over time.** Without a pinned allow-list, a future push field silently re-widens the exposure and nothing goes red. Model it on the repo's existing census/freeze tests.
- **TC-327-05 is the highest-risk coupling in the plan.** The reaction dedupe identity is shared across the relay, the Android isolate, and the Swift NSE. Any payload change that perturbs `event_id` produces duplicate banners on every reaction — the exact class plan 320 spent a deploy closing.
- TC-327-09/10 are written now deliberately, as contract-with-a-blocker rather than omitted, so the staged shape is reviewable. They are **not** counted as executable coverage.

## Implementation Steps
**Do not start any stage before the user picks one and resolves its gate.**
1. *(Stage A)* Snapshot `git status --short`. Add TC-327-01/02/03/04/07/08; confirm 01/02/03/07/08 red for the documented reasons and 05/06 green.
2. *(Stage A)* Remove the name fields from the relay's push builders; add the allow-list census.
3. *(Stage A)* Add local display-name resolution to the Android fallback and the iOS NSE resolver. Stop-if: the NSE cannot resolve a name for a first-contact `contact_request` without new App Group state → stop and take U2 back to the user rather than inventing copy.
4. *(Stage A)* Relay build with the pinned toolchain, verify `go version <binary>`, backup, deploy, 90s window.
5. *(Stage B)* Requires U3 sign-off first. Then design the token mint/resolve contract and re-plan.
6. *(Stage C)* Requires the U1 spike first: a throwaway branch proving the NSE can perform one authenticated relay fetch and one ML-KEM decrypt inside the memory budget, without SQLCipher. If the spike fails, Stage C is closed and this plan tops out at Stage B.

## Risks And Blind Spots
- **Mixed-version rollout is the dominant risk.** A shrunk payload reaches clients that still expect the old fields. Guarded by TC-327-07 and the Rollback contract below.
- **Dedupe identity coupling** across three runtimes → TC-327-05.
- **UX regression** — losing the sender name in the banner is a real product cost, especially for first-contact events (U2). Not a code risk; a decision.
- Lifecycle / derived-state durability: N/A for Stage A — no persisted state changes.
- Sibling-surface consistency: every push builder must change together, or one lane keeps leaking → TC-327-08's allow-list covers all builders in one table.
- Destructive-action side effects: N/A — no deletion, no migration.
- Invariant re-verification under new transitions: the notification claim/tone invariants must survive → TC-327-05, TC-327-06.
- Construction/call-site census: `grep -n 'data := map\[string\]string{' go-relay-server/*.go` → re-derive at execution; five builders known today (`inbox.go:421`, `:434`, `:484`, `:544`; `reaction_push.go:418`, `:524`).
- Build-artifact provenance: relay binary must be toolchain-verified before upload (plan 320's deploy contract).
- Permission/ACL verb symmetry: N/A — no ACL change.

## Rollback
- **Stage A is wire-visible and mixed-version sensitive.** Rollback = redeploy the previous relay binary from the `relay-server.pre-327-<stamp>` backup; clients tolerate the *richer* payload unconditionally (they read fields they no longer need), so a relay-only rollback is safe and sufficient.
- Forward-compat rule: ship the **client** tolerance for missing fields (TC-327-07) in a release that is broadly adopted **before** the relay stops sending them. This is the ordering constraint that makes Stage A safe; violating it produces unrenderable notifications on un-updated clients.
- Stage B and C rollback contracts are deferred with their stages.

## Gate Cadence
- Per-plan closure (Stage A): TC-327-01..08 + `cd go-relay-server && go test ./...` + the Swift `NotificationPreviewResolverTests` + the `1to1` curated lane (the push fallback surfaces live there) + a live post-deploy verification.
- Graph-affected first: after the Dart edits, run `tdd_context.py affected lib/features/push/application/… --budget 600` and run the named files directly. The Go and Swift halves have no arch-graph edges.
- Full `host-all` is **not** a per-plan gate; owned by final release closure.
- Shared tests outside the feature/core globs: N/A.

## Acceptance Gates  (literal — copy/paste, Stage A only)
```bash
git status --short

# Causal RED (before edits)
cd go-relay-server && go test ./... -run TestPushDataCarriesNoDisplayName

# Focused GREEN (after edits)
cd go-relay-server && go test ./...

# Swift NSE boundary
bash scripts/test/run_runner_tests_321.sh -only-testing:RunnerTests/NotificationPreviewResolverTests

# Dart client tolerance
flutter test test/features/push/application/

# Graph-affected dependents BEFORE the lane
python3 graphify-arch/tdd_context.py affected \
  lib/features/push/application/background_push_notification_fallback.dart \
  lib/features/push/application/background_message_handler.dart --budget 600

# Curated lane
./scripts/run_test_gates.sh 1to1

# Registration is grep-verified, never run-verified
./scripts/run_test_gates.sh completeness-check   # expect: PASS, 0 unmatched

# Relay build + toolchain proof + deploy (see plan 320's contract)
cd go-relay-server && GOTOOLCHAIN=go1.25.0 GOOS=linux GOARCH=amd64 go build -o relay-server .
go version relay-server          # expect: go1.25.0

# Hygiene
flutter analyze
cd go-relay-server && gofmt -l .  # expect: empty
git diff --check
```

## Execution Interpretation And Done Criteria
- Expected RED (Stage A): TC-327-01/02 (relay still emits names), TC-327-03/07 (client has no name-absent path), TC-327-08 (field set exceeds the allow-list).
- GREEN sentinel: TC-327-05 (dedupe identity parity), TC-327-06 (oversized fallback intact).
- Pre-existing dirty tree / known failure: the three user-owned claude-docker files — never staged.
- Environment blocker (NOT a product blocker): Stage C's spike needs a device; Stage A needs the production relay for its live leg.
- Scope drift (BLOCKING): any reliability claim; any Stage B/C work before its gate resolves; concurrent execution with plan 148.

- [ ] Every behavior has a named test or a justified proof.
- [ ] Causal RED, focused GREEN, and representative mutation re-red are recorded (Stage A).
- [ ] Preservation sentinels and named gates pass with semantic outcomes.
- [ ] Harness registration is implemented AND verified.
- [ ] Client forward-compat shipped and adopted BEFORE the relay payload shrinks.
- [ ] `flutter analyze` clean; `gofmt -l .` empty; `git diff --check` clean.
- [ ] The Scope Contract And Guard is respected.

## Handoff
- First causal RED command: `cd go-relay-server && go test ./... -run TestPushDataCarriesNoDisplayName`.
- Preservation command: `bash scripts/test/run_runner_tests_321.sh -only-testing:RunnerTests/NotificationPreviewResolverTests`.
- Manual registration: new Dart push tests → verify `ONE_TO_ONE_TESTS` by grep; Go tests are AUTO by package.
- Migration: none.
- Boundary closure: relay deploy + iOS NSE XCTest for Stage A; device proof only if Stage C ever unblocks.
- **Unresolved evidence: U1 (NSE fetch feasibility — blocks Stage C), U2 (first-contact display-name copy — product decision), U3 (relay-held token mapping threat-model sign-off — blocks Stage B).**

## Device/Relay Proof Profile
- Profile: relay (single production box, no staging twin) + iOS simulator for the NSE XCTest.
- Boundary being proven: that a real push with the reduced payload still renders and routes on a real device.
- Live availability check: relay reachable per `docker-ws/` deploy scripts; active iOS fleet is iPhone 11 (`00008030…`) + iPhone 13 (`00008110…`).
- Rollback: `relay-server.pre-327-<stamp>` backup; relay-only rollback is safe once client tolerance has shipped.

## Execution Progress
| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started (planned only, user decision 2026-08-02) | - | - | - | Stage A awaits go-ahead; Stage B awaits U3; Stage C awaits U1 spike | user picks a stage |

## User Decisions (2026-08-02)

- **U3 RESOLVED — the relay may hold the token↔identity mapping.** Rationale accepted: the relay already knows sender, group and message because it routes them, so holding the codebook reveals nothing new to it while hiding the social graph from APNs/FCM, which is the actual threat model. **Stage B is therefore UNBLOCKED** and needs a design pass (token mint/resolve contract, rotation policy, and what happens when a client sees a token it cannot resolve).
- **PRIVACY WINS over tap latency.** Plan 148 (minimum-parity encrypted push spool) is **CLOSED — superseded by 327**. It wanted a richer push payload for instant tap render; 327 shrinks the payload. The two are mutually exclusive and 148 was never executed (it stayed blocked on its own Phase-0 evidence gate), so nothing is discarded. Do not revive 148 without explicitly reopening this decision — reviving it would silently undo Stage A and Stage B.
- **U1 (Stage C / NSE fetch) remains open.** Unaffected by the above; still needs a feasibility spike.
- **U2 (first-contact display-name copy) remains open** — a product decision on what a `contact_request` or `group_invite` banner says when the name is not locally resolvable.

Execution order now: **Stage A → Stage B → (Stage C only if U1's spike succeeds).**
