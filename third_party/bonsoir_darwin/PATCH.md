# Vendored `bonsoir_darwin` 5.1.3 — off-main DNS-SD broadcast patch

This directory is a **vendored fork** of the pub.dev package `bonsoir_darwin`
version **5.1.3** (sha256 `2d25c70f0d09260be1c2ab583b80dd89cbbfd59997579dadf789c5af00c7b2e4`,
the version pinned transitively by `bonsoir ^5.1.0` → `bonsoir 5.1.11`). It carries
**one surgical native patch** so the patch is durable and reviewable. Everything
else is byte-identical to upstream.

Plan of record: `Test-Flight-Improv/175-bonsoir-broadcast-off-main-thread-tdd-plan.md`.

> ## ⚠️ COMMIT AS A UNIT
> The root `pubspec.yaml`/`pubspec.lock` pin to `path: third_party/bonsoir_darwin`,
> but this **whole `third_party/bonsoir_darwin/` tree is the resolution target**.
> If `pubspec.yaml`/`pubspec.lock` are committed **without** this tree, every clean
> checkout / CI runner fails `flutter pub get` (path not found) and **silently
> loses the 0x8BADF00D watchdog fix**. Stage them together:
> ```bash
> git add third_party/bonsoir_darwin pubspec.yaml pubspec.lock
> git ls-files third_party/bonsoir_darwin | wc -l   # must be > 0 BEFORE committing
> ```
> Never `git commit -a` / `git add pubspec.*` for this change in isolation.

## Why this fork exists (bug 175)

On iPhone 11 / iOS 26.5 the app's Flutter main thread froze within ~1 s of launch
and, on the next background transition, iOS issued a `FRONTBOARD 0x8BADF00D`
"scene-update watchdog … exhausted 10.00 s" SIGKILL.

Step-0 symbolication of `/tmp/cv08/crash/Runner-2026-06-29-131147.ips` (faulting
thread 0 = `com.apple.main-thread`) confirmed the blocking frame:

```
__recvfrom_nocancel            (libsystem_kernel)
read_all                       (libsystem_dnssd)
DNSServiceProcessResult        (libsystem_dnssd)
BonsoirServiceBroadcast.start()        (bonsoir_darwin)   ← here
SwiftBonsoirPlugin.handle(_:result:)   (bonsoir_darwin)
FlutterMethodChannel handler block     (Flutter)
_dispatch_main_queue_drain     (libdispatch)
… UIApplicationMain → main
```

`BonsoirServiceBroadcast.start()` called **`DNSServiceProcessResult(sdRef)`
synchronously on the iOS main thread**. That is a blocking socket read until the
`mDNSResponder` daemon replies; when Local Network permission is pending/denied
or the daemon is contended, it blocks past the 10 s watchdog and the app is
killed. Every re-advertise (`restartAdvertising`, the 174 `updateLibp2pPorts`
re-publish, the periodic refresh timer) re-runs the same synchronous call, so any
one that stalls during a scene update kills the app.

Upstream's own 5.1.3 CHANGELOG says *"FIX(darwin): Fixed crashes in
DNSServiceProcessResult by using DispatchSourceRead"* — but they only applied
that fix to the **discovery resolve** path
(`Classes/Discovery/BonsoirServiceDiscovery.swift`), never to this **broadcast**
leg. This fork applies the same, proven pattern to the broadcast leg.

## The patch (the ONLY behavioral change)

File: `darwin/Classes/Broadcast/BonsoirServiceBroadcast.swift`

1. **`start()` drains off the main thread.** The synchronous
   `DNSServiceProcessResult(sdRef)` is replaced by a
   `DispatchSource.makeReadSource(fileDescriptor: DNSServiceRefSockFD(sdRef),
   queue: DispatchQueue.global(qos: .userInitiated))`. The read source's
   event handler calls `DNSServiceProcessResult` on that background queue, so the
   calling (main) thread is never blocked. This mirrors
   `BonsoirServiceDiscovery.resolveService` exactly.
2. **`sdRef` is freed race-free.** The read source's **cancel handler** calls
   `DNSServiceRefDeallocate(sdRef)`. libdispatch guarantees the cancel handler
   runs *after* the last event-handler invocation has returned, exactly once → no
   use-after-free / double-process. `dispose()` cancels the source (triggering
   that dealloc) and only direct-deallocates when `start()` failed before a
   source was created. `sdRef`/`dispatchSource` are nil'd after teardown so a
   double `dispose()` is a safe no-op (this is *safer* than the pristine code,
   which had a latent double-`DNSServiceRefDeallocate` exposure).
3. **`registerCallback` hops to main.** Because the C callback now fires on the
   background drain queue, and `FlutterEventSink` is main-thread-only, the
   `onSuccess`/`onError` work is wrapped in `DispatchQueue.main.async` — again
   mirroring `BonsoirServiceDiscovery.resolveCallback`. The C `name` pointer is
   copied to a Swift `String` *before* the async hop (it is only valid for the
   callback's duration).
4. **Test seam.** `static var processResult` defaults to the real
   `DNSServiceProcessResult` and is the function the drain calls. Tests inject a
   delayed/instrumented shim to assert the drain runs off the calling thread
   without a live `mDNSResponder`. Production behavior is unchanged.

The Dart side is **unchanged**: `bonsoir_discovery_service.dart`'s
`await _broadcast!.start()` only awaits the method-channel ack (see
`bonsoir_platform_interface .../actions/action.dart` `start()`), which now returns
immediately. The `broadcastStarted` event still arrives async over the separate
event channel; nothing awaits it before the `start()` Future completes.

## How it is wired (do not break)

Root `pubspec.yaml`:

```yaml
dependency_overrides:
  bonsoir_darwin:
    path: third_party/bonsoir_darwin
```

`flutter pub get` re-points `.flutter-plugins-dependencies` /
`.dart_tool/package_config.json` and `pubspec.lock` records
`bonsoir_darwin … source: path`. `pod install` (run in `ios/`) regenerates
`ios/.symlinks/plugins/bonsoir_darwin` → `third_party/bonsoir_darwin/` and points
`ios/Pods/Pods.xcodeproj` at the vendored Swift. After any
`flutter pub get` / `pod install`, re-verify:

```bash
readlink ios/.symlinks/plugins/bonsoir_darwin           # → …/third_party/bonsoir_darwin/
grep -c "DispatchSourceRead" \
  ios/.symlinks/plugins/bonsoir_darwin/darwin/Classes/Broadcast/BonsoirServiceBroadcast.swift  # ≥1
```

## Differences from pristine upstream 5.1.3

- `darwin/Classes/Broadcast/BonsoirServiceBroadcast.swift` — the off-main patch
  above (the only functional change).
- `pubspec.yaml` — removed the upstream monorepo-relative
  `dependency_overrides: bonsoir_platform_interface {path: ../bonsoir_platform_interface/}`.
  That path does not exist in this vendored layout, and pub honors
  `dependency_overrides` only from the **root** package, so a transitive
  package's overrides are ignored anyway. `bonsoir_platform_interface ^5.1.3`
  resolves normally from the root lock.
- `darwin/Tests/BonsoirServiceBroadcastOffMainTest.swift` — **added** (optional
  TC-01 falsifier). It is **excluded from the pod** by the podspec
  `source_files = 'Classes/**/*'` glob, so it never compiles into the shipping
  pod and cannot break the build.

## Maintenance / drift

- **Pin durability.** The `path:` override survives `flutter pub upgrade` (an
  override always wins). If you ever remove the override, the patch silently
  reverts to the pub.dev copy and the watchdog freeze returns — keep the override.
- **Re-applying on a deliberate upgrade.** To move to a newer `bonsoir_darwin`:
  re-vendor that version here, re-apply the four changes above to its
  `BonsoirServiceBroadcast.swift` (diff against this file), and confirm upstream
  has not already moved the broadcast drain off-main (check its CHANGELOG /
  `start()` — if it has, drop this fork and the override).
- **macOS parity.** `sharedDarwinSource: true` means the same Swift serves macOS;
  the patch covers macOS automatically once `macos/` pods are reinstalled. The
  app's primary target is iOS.

## Verification done at vendoring time

- `xcodebuild -project ios/Pods/Pods.xcodeproj -target bonsoir_darwin
  -sdk iphonesimulator build` → **BUILD SUCCEEDED** (the patched pod compiles,
  arm64 + x86_64).
- `flutter test test/core/local_discovery/` → all green (Dart contract +
  watchdog-gate + 174 self-heal sentinels unchanged).
- TC-01 structural assertion green; the device-proof TC-02 (CV-08-RESPONSIVE,
  two-phone) carries the mutation and is the closure gate.
