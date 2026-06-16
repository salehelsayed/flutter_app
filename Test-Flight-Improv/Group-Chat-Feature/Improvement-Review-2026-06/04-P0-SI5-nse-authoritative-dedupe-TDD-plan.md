> Part of the **[Group Chat Improvement Review](./README.md)** · Priority **P0** · Slice-2 native track of **[04-P0 notifications](./04-P0-notifications-respect-settings-and-membership.md)** · companion to **[04-…-TDD-plan.md](./04-P0-notifications-respect-settings-and-membership-TDD-plan.md)**

---

# TDD Plan — SI-5: NSE-authoritative dedupe (cross-process recent-remote marker)

**Status: PLAN ONLY.** Decomposed for TDD execution. Verified against HEAD `124-harness-refactor` by a graph-first recon (4-agent `/workflow`: Swift NSE/dedupe, Dart gate post-SI-4, platform-channel, sim-test infra). Includes a **simulator-test strategy** (Swift XCTest + `flutter test` + on-sim `integration_test`) — see §6.

> This is the one deferred item from the 04 Slice-2 NSE track. The Slice-1 Dart-only work shipped; **SI-1 (NSE mute) and the SI-2 security core (removed-member can't decrypt) are implemented + simulator-green.** SI-5 was deferred because it needs (a) a new Dart↔native channel for the app-group container path, and (b) coordination with the already-landed SI-4. This plan resolves both.

---

## 0. What SI-5 fixes (problem statement)

On iOS a single FCM push can produce **two banners**: the out-of-process **NSE** mutates+shows the decrypted preview, and—if iOS later schedules the Dart isolate (foreground or `firebaseMessagingBackgroundHandler`)—the **Dart producer** can show its own banner for the same message.

The Dart side already has a dedupe gate: `RecentRemoteNotificationGate` (`show_notification_use_case.dart:105-128` calls `consumeIfRecentAnnouncement(payload, messageId)` and, on a hit, emits `NOTIFICATION_SUPPRESSED` and returns). **But the gate's file lives in the app's *private* container** (`getApplicationSupportDirectory()`, post-SI-4), which the NSE **cannot write to**. So the NSE banner is invisible to the Dart gate → the Dart copy is only suppressed if the *Dart isolate itself* previously marked the message. **SI-5 makes the NSE an authoritative writer of the dedupe marker**, in the shared app-group container, so the Dart copy is suppressed even when the Dart isolate never ran for that FCM copy.

---

## 1. Resolution verification (still open?)

**Yes — open, and confirmed feasible.** The recon found the two blockers from the parent plan are real but tractable:
- The NSE already reaches the shared container: `AppGroupPushDedupeStore` (`NotificationPreviewResolver.swift:419-455`) resolves `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.mknoon.app.share")` and writes atomic `O_CREAT|O_EXCL` lockfiles under `NotificationServiceDedupe/`. **The app-group entitlement is present on BOTH `Runner.entitlements` and `NotificationService.entitlements`** (verified).
- The Dart gate is in-process-only and has **no API for the app-group path** — `getApplicationSupportDirectory()` returns the private sandbox, not the shared container. This is the channel gap SI-5 fills.
- **SI-4 is NOT in conflict** (corrects the parent plan's framing): SI-4 moved the gate off OS-evictable `systemTemp` for durability. The app-group container is *also* durable, and §3's union-read design leaves SI-4's app-support file untouched. SI-5 only *adds* an iOS-only read source.

---

## 2. The dedupe contract (the #1 risk — byte-exact key parity)

The NSE and Dart must agree on the **exact key string**, or dedupe silently no-ops (green unit tests on each side, zero suppression in prod). From `show_notification_use_case.dart:111` (`remoteAnnouncementPayload = routePayload ?? contactPeerId`) and `RecentRemoteNotificationGate._messageKey` (`= 'message:$payload|$messageId'`):

| Kind | `payload` (Dart) | gate key the NSE must reproduce |
|---|---|---|
| 1:1 | `<peerId>` (bare; `routeTarget.conversation.toPayload`) | `message:<peerId>\|<messageId>` |
| group | `group:<groupId>\|message:<messageId>` (`routeTarget.group(gid, messageId).toPayload`) | `message:group:<groupId>\|message:<messageId>\|<messageId>` ← **double `message:` segment** |

NSE-side inputs (`NotificationPreviewResolver`): `threadIdentifier` = `<peerId>` for 1:1 / `<groupId>` for group; `messageId` = `PushRouteData.messageId` (aliases `message_id`/`messageId`/`id`/`msgId`/**`m`**). **Caveat:** the NSE accepts the `m` alias but Dart `remoteNotificationMessageIdFromData` does **not** — a push carrying only `m` yields divergent ids → non-matching keys. The contract test (§5 S4) must lock this.

**Mandate:** a single **shared fixture** drives both a Swift XCTest and a `flutter test`, asserting the NSE-computed key == the Dart-computed key for 1:1 and group. No divergence is allowed to ship.

---

## 3. Design decisions (resolve the recon's open questions before coding)

1. **Per-message sidecar markers, NOT a shared JSON map.** The NSE writes an atomic per-message file; it never read-modify-writes the gate's JSON. **Why:** NSE + Dart-bg-isolate + Dart-live-isolate concurrently rewriting one JSON map = lost writes / torn file, which *reopens the exact silent-dedupe-bypass window SI-4 closed*. Per-message files (atomic `O_CREAT|O_EXCL`, like the existing `claim`) have no shared mutable state.
2. **Union read — keep SI-4's app-support JSON, ADD an iOS-only app-group sidecar read.** The gate keeps reading/writing its app-support `mknoon_recent_remote_notifications.json` (Dart-written markers, SI-4 durability intact). On iOS it *additionally* checks `<app-group>/RecentRemoteShown/` for NSE-written markers. **Why:** avoids a prod-path migration (old private-container entries stay valid) AND keeps Dart's writer off the shared dir. No SI-4 conflict.
3. **Sidecar filename = stable hash of the exact gate key; TTL via file mtime.** Filename = `sha256("message:<payload>|<messageId>")` (hex; filesystem-safe, collision-free, computed identically both sides). No timestamp embedded — the gate treats `now - file.mtime` against the **12h `messageTtl`** (matching the `message:` prefix bucket). The gate prunes sidecars older than 12h on read.
4. **App-group path via a new channel, resolved-once-and-persisted (bg-isolate safe).** Add `MethodChannel('mknoon/app_group_path')` → `appGroupContainerPath` (mirror `diskSpaceChannel`, `AppDelegate.swift:407`). **The FCM bg isolate runs a separate `FlutterEngine`; a hand-rolled channel may not be registered there** (unlike federated `path_provider`). So: resolve the path **once in the foreground** (`main.dart`, after Firebase init) and **persist it** to a small file under app-support; the gate reads the persisted path (works in any isolate). Missing path → no sidecar read (fall back to current behavior; emit telemetry; never silently drop SI-4 durability).
5. **Coexist with the existing `NotificationServiceDedupe/` lockfiles.** Those are NSE-internal (dedupe the NSE seeing one push twice) and keyed `<type>-<messageId>`. SI-5 adds a *separate* `RecentRemoteShown/` dir keyed by the Dart gate key — the contract is owned by Dart, so Dart matches its own key without reconstructing the NSE's `type`. Two small writes per push; acceptable.

---

## 4. Scope & ordering

Four TDD sessions, landed in order (each gate-able):
- **S1 — app-group path channel + persisted path** (Dart + Swift + sim integration_test). Foundation for the gate's iOS provider.
- **S2 — NSE sidecar marker writer** (Swift XCTest). Independent of S1/S3 (injected dir).
- **S3 — Dart gate union-read of the sidecar dir** (`flutter test`). Independent of S2 (writes the marker shape directly).
- **S4 — wire-up + the shared-fixture contract test** (Dart + Swift + on-sim integration). Joins S1's path into the gate and locks key parity.

No DB migration. iOS-only behavior; Android/desktop/tests unchanged (channel returns null off-iOS → gate keeps the app-support path).

---

## 5. Sessions (RED first, then minimal GREEN)

### Session 1 — `mknoon/app_group_path` channel + persisted path
**RED**
- `test/core/notifications/app_group_path_channel_test.dart`: with `TestDefaultBinaryMessengerBinding…setMockMethodCallHandler(MethodChannel('mknoon/app_group_path'), …)` returning a fake path → assert `AppGroupPathChannel().appGroupContainerPath()` returns it; handler throws `PlatformException` / `MissingPluginException` → assert graceful `null` (off-iOS contract). Mirror the `disk_space` injectable-invoker style so it's also testable without the binding.
- `integration_test/app_group_path_simulator_test.dart` (sim): `testWidgets` calls `appGroupContainerPath()` → assert non-empty, `Directory(path).existsSync()`, and the path resolves the real container (write+read a temp file under it).

**GREEN**
- Dart: new `lib/core/notifications/app_group_path_channel.dart` (`channelName='mknoon/app_group_path'`, `Future<String?> appGroupContainerPath()`, injectable invoker; null off-iOS / on `MissingPluginException`).
- Swift `ios/Runner/AppDelegate.swift`: clone `setupDiskSpaceBridge` (`:275-287`) → `setupAppGroupPathBridge`, handler `case "appGroupContainerPath": result(FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: mknoonSharedAppGroupIdentifier)?.path)` (`FlutterError('app_group_unavailable')` if nil). **Wire in BOTH** registration sites (`didInitializeImplicitFlutterEngine:147` + `configureIosNotificationOpenBridgeFromRootViewController:272`), each with the existing `if x != nil { return }` idempotency guard. No new entitlement (already granted).
- Persist: in `main.dart` (after Firebase init) resolve the path once and write it to `<app-support>/mknoon_app_group_path`. (Reusing the SI-1 `pushSharedKeyStore`/Keychain to carry the path is an acceptable alternative if a file feels heavy.)

### Session 2 — NSE sidecar marker writer (Swift)
**RED** — `ios/RunnerTests/NotificationPreviewResolverTests.swift`:
- Construct the new writer with a **test-injected temp directory** (not the real container — hermetic). Call it for `type='new_message', threadIdentifier='peer-alice', messageId='msg-1'`. Assert: a file exists at `<dir>/RecentRemoteShown/<sha256("message:peer-alice|msg-1")>`; idempotent second write doesn't error / leaves exactly one marker; **no leftover temp/partial file** (atomicity). Add a group case asserting the double-`message:` key (`message:group:g-1|message:m-9|m-9`).
- Bonus (closes an existing coverage gap): inject the temp dir into `AppGroupPushDedupeStore` and lock `claim()` `O_EXCL` first-wins/second-loses on a real filesystem.

**GREEN**
- `NotificationPreviewResolver.swift`: add a `RecentRemoteShownMarkerStore` (sibling of `AppGroupPushDedupeStore`; ctor takes an overridable directory URL, default `containerURL.appendingPathComponent("RecentRemoteShown")`) with `mark(payload:messageId:)` that computes the **exact Dart key**, hashes it (sha256 hex), and atomically creates the empty marker (`O_CREAT|O_EXCL` or `Data().write(to:options:.atomic)`).
- `NotificationService.didReceive`: after `previewResolver.resolve(...)` and before `contentHandler(...)` (≈`:48`), call the writer with the resolved `threadIdentifier` + `PushRouteData.messageId`. Write **only for the message actually rendered** (guard on a real messageId; reuse the same key canonicalization as the dedupe `claim` site `:131-141`).

### Session 3 — Dart gate union-read of the sidecar dir
**RED** — `test/core/notifications/recent_remote_notification_gate_test.dart` (mirror the SI-4 durability group):
- Inject an `appGroupSidecarDirProvider` (or explicit path) → create `<dir>/RecentRemoteShown/<sha256("message:peer-123|msg-7")>` with `now` mtime. Assert `consumeIfRecentAnnouncement(payload:'peer-123', messageId:'msg-7')` is **true** without any prior `markAnnouncement` (simulates NSE wrote it, Dart reads it); a second call is **false** (consumed/cleaned).
- Group parity: `<sha256("message:group:g-1|message:m-9|m-9")>` → `consumeIfRecentAnnouncement(payload:'group:g-1|message:m-9', messageId:'m-9')` true.
- TTL: marker with mtime `now-13h` → false; `now-11h` → true (rides the 12h `messageTtl`). Use the `now` seam + set the file mtime.
- Pruning + non-iOS: with no sidecar provider, behavior is byte-identical to today (no regression).

**GREEN** — `recent_remote_notification_gate.dart`:
- Add an optional `appGroupSidecarDirProvider` seam (parallel to `supportDirectoryProvider`). In `consumeIfRecentAnnouncement`, after the JSON-map miss, compute `sha256(_messageKey(payload, messageId))`, check `<sidecar>/<hash>` exists with `now - mtime < messageTtl` → hit (delete the file to consume). Prune `mtime`-expired sidecars opportunistically. Keep the whole path async/cached like SI-4; guard everything behind the provider being non-null so non-iOS/tests are unaffected.

### Session 4 — wire-up + shared-fixture contract test
**GREEN (wiring)** — `main.dart` gate construction (iOS only): supply the persisted app-group path as the `appGroupSidecarDirProvider`; keep `supportDirectoryProvider`=app-support for the JSON. Fallback + `..._DIR_FALLBACK`/telemetry if the path is unavailable.

**Contract test (the load-bearing guard):** a shared fixture (e.g. `test_fixtures/si5_dedupe_keys.json`: `[ {kind, peerId|groupId, messageId, expectedKey} ]`) consumed by BOTH:
- Swift XCTest: `RecentRemoteShownMarkerStore.key(forThreadIdentifier:messageId:type:)` == `expectedKey`.
- `flutter test`: `RecentRemoteNotificationGate`'s `_messageKey(payload, messageId)` (via `markRemoteNotificationOpenAsRecentAnnouncement` shape) == `expectedKey`.
Any drift fails both. This is the only thing standing between "works" and "silently never dedupes."

---

## 6. Simulator test strategy (required) — what's sim-provable vs device-only

> **`simctl push` does NOT invoke the NSE on the simulator.** The true out-of-process round-trip (real NSE process writes → real app process reads) is **device-only**. Everything else below runs on a booted simulator and covers all the *logic*.

**Layer A — Swift XCTest (NSE write), runs on the sim** via the hosted `RunnerTests` target:
```
flutter build ios --config-only --debug --simulator   # fix the shared Generated.xcconfig first (multi-session hazard)
cd ios && xcodebuild test -workspace Runner.xcworkspace -scheme Runner \
  -destination 'platform=iOS Simulator,id=<booted-udid>' \
  -only-testing:RunnerTests/NotificationPreviewResolverTests
```
Proves: the marker writer lands the **correct key** at the **correct path**, **atomically**, idempotently (S2). Hermetic via temp-dir injection. (Same harness that just landed SI-1/SI-2 green.)

**Layer B — `flutter test` (Dart read + channel), host VM:**
- `recent_remote_notification_gate_test.dart` — gate consumes an NSE-shaped sidecar marker, honors 12h TTL, prunes, non-iOS no-op (S3).
- `app_group_path_channel_test.dart` — mocked channel returns/throws (S1).
- the **shared-fixture contract test** — key parity (S4).

**Layer C — on-sim `integration_test` (channel on real iOS + one-process round-trip):**
- `integration_test/app_group_path_simulator_test.dart` — `appGroupContainerPath()` returns a real existing app-group dir; then **write a marker at the channel-returned path and read it back through the gate** (proves the path + sidecar format align in one process):
```
flutter test integration_test/app_group_path_simulator_test.dart -d <booted-sim-udid>
```

**Device-only (Phase B, TestFlight):** the genuine NSE-process→app-process round-trip — push arrives, NSE shows + writes the marker, app later reads it and suppresses the duplicate. Add to `Test-Flight-Improv/52-notification-journey-test-matrix.md` (e.g. RG-006 dedupe row).

**Gate sweeps:** `test/core/notifications/` + `test/features/push/` green; `flutter analyze` 0 new; the XCTest class green on the sim. Run iOS builds in a **flutter-quiet window** (a concurrent `flutter test` clobbers the shared `Generated.xcconfig` → kernel_snapshot failure; regenerate with `--config-only`).

---

## 7. Risks, trade-offs & rollout

| Risk | Mitigation |
|---|---|
| **Key-parity drift** (group double-`message:`, the `m` alias) silently disables dedupe | the §5-S4 shared-fixture contract test, asserted on both sides; normalize the `m` alias in `remoteNotificationMessageIdFromData` if a push can carry only `m` |
| Cross-process JSON corruption | design §3.1 — NSE writes per-message atomic sidecars, never the gate's JSON |
| bg-isolate channel not registered | design §3.4 — resolve-once-and-persist; gate reads the persisted path, not the channel, at notify time |
| Path switch / migration | union read (§3.2) keeps the app-support file; no migration, no dedupe gap at the version boundary |
| Sidecar dir grows unbounded if Dart never runs | gate prunes `mtime`-expired (>12h) sidecars on read; bounded by per-message + 12h |
| Over-suppression of a later distinct message | keys are `messageId`-scoped + NSE writes only for the rendered message |
| app-group path unavailable at startup | fall back to app-support (SI-4 durable) + `..._DIR_FALLBACK` telemetry; **never** systemTemp |

**Rollout:** land S1→S2→S3→S4 (each host/sim-green), then the device round-trip on TestFlight before trusting NSE-authoritative suppression. Behind no flag is fine (additive read; absent marker = today's behavior), but watch the `NOTIFICATION_SUPPRESSED reason=recent_remote_push` rate for an unexpected spike (would indicate over-suppression / a key collision).

---

## 8. Effort estimate

| Session | Effort | Notes |
|---|---|---|
| S1 channel + persisted path | **M** | Dart channel + 2 AppDelegate sites + persist + sim integration_test; bg-isolate persistence is the fiddly bit |
| S2 NSE marker writer | **S–M** | one Swift store + 1 call site; XCTest with injected dir |
| S3 gate union-read | **M** | sidecar seam + sha256 + mtime-TTL + prune, all behind the provider guard |
| S4 wire + contract test | **S–M** | gate construction + the shared-fixture parity test (highest value) |
| **Total** | **Medium** | iOS-only, no migration; needs a native build + the sim XCTest harness (already proven by SI-1/SI-2) |

---

## 9. Implementation outcome (2026-06-16)

**Status: IMPLEMENTED + sim-validated (all 3 simulator-provable layers green).** A 4-reviewer adversarial review was run on the diff; 2 real code bugs found and fixed, 1 documented.

| Layer | Proves | Result |
|---|---|---|
| A — Swift `RunnerTests/NotificationPreviewResolverTests` | NSE writer lands the exact `sha256(gateKey)` marker (atomic `O_EXCL`, 0600), reproduces the literal 1:1 `message:peer-alice|msg-1` and group `message:group:g-1|message:m-9|m-9` keys | ✅ sim-green |
| B — `flutter test` (gate + wiring + channel) | union-read (SI-4 JSON ∪ SI-5 sidecar), 12h mtime-TTL, prune, channel null-handling, persist/read round-trip | ✅ green (0 analyze) |
| C — on-sim `integration_test/app_group_path_simulator_test.dart` | **real** AppDelegate `mknoon/app_group_path` channel resolves the shared container + sidecar round-trips through the gate in one process | ✅ green |

Not sim-provable: the genuine out-of-process **NSE→app** round-trip (`simctl push` does not invoke the NSE) — device/TestFlight only.

### Review findings & disposition
- **MEDIUM — negative-cache (FIXED).** `_resolveSidecarDir` used `??=`, which pinned a *completed-null* Future if the first consume lost the race to main()'s unawaited path-persist on first-ever launch → SI-5 silently off for the whole session. Fix: memoize only a **non-null** resolution; retry on null. Regression test `re-resolves the sidecar dir after a transient first-launch failure` is **mutation-verified** (RED under the old `??=`).
- **LOW — muted-marker leak (FIXED).** NSE wrote a marker even when the preview was suppressed (muted group), but the Dart `isMuted` gate never consumes it → orphan inodes until the next cold-start prune. Fix: `if !preview.suppress { mark() }` in `NotificationService.didReceive` — a suppressed push was never surfaced, so there is nothing to dedupe.
- **LOW — 1:1 transport-sender-mismatch (DOCUMENTED, fail-open).** The 1:1 key's peer component is the live producer's `payload.senderPeerId` vs the NSE's relay `sender_id` (= `entry.From`). When they differ (multi-device / relay-forward, flagged `TRANSPORT_SENDER_MISMATCH`) the marker filenames diverge and the dup banner is not suppressed. This is the **same pre-existing equality** the 118-era dedupe already relied on; worst case is one redundant local banner, never a loss or false-suppress. Documented at `sidecarMarkerName`.
- **Non-bugs (deferred, by design):** prune-once-per-process (bounded, self-heals on cold start); SI-5 inert on the pure-background path (bg handler marks-not-consumes; the foreground live-listener benefit lands) — broader bg-consume dedupe deliberately out of SI-5 scope.
