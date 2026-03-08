# TDD Plan: App Share Target (Receive Shared Content)

## Goal

Make mknoon appear in the OS share sheet (like WhatsApp/Signal) so users can
share links, text, images, and videos from other apps (Instagram, TikTok, etc.)
into mknoon and send them to a contact or group.

## Architecture Overview

```
External App (Instagram, TikTok, Safari)
    │
    ▼ OS Share Sheet
    │
    ├── Android: ACTION_SEND intent → receive_sharing_intent plugin (automatic)
    │
    └── iOS: Share Extension (RSIShareViewController) → App Group → plugin
    │
    ▼ Flutter
    │
ShareIntentService (wraps ReceiveSharingIntent.instance)
    │
    ▼
StartupRouter (buffers intent until identity + contacts exist)
    │
    ▼
ShareTargetPickerWired (contact/group picker → processes media on selection)
    │
    ├── Select Contact → ConversationWired(initialAttachments, initialText)
    └── Select Group → GroupConversationWired(initialAttachments, initialText)
```

## Package Choice

Use `receive_sharing_intent` package — mature, well-maintained, handles both
platforms automatically. The plugin provides its own MethodChannel bridge,
Android intent handling, and iOS `RSIShareViewController` base class.
No custom native MethodChannel code is needed.

Source: https://pub.dev/packages/receive_sharing_intent

---

## Phase 1: Dart Domain Layer — Share Intent Model & Service

### Goal
Define the shared content model and a service that wraps
`ReceiveSharingIntent.instance` for stream/initial/reset access.

### Tests (RED)

**File:** `test/core/services/share_intent_service_test.dart`

| # | Test | What it proves |
|---|------|----------------|
| 1a | `ShareIntent.text creates text intent` | Model construction |
| 1b | `ShareIntent.files creates file intent` | Model with file list |
| 1c | `ShareIntent.mixed creates intent with text and files` | Combined content |
| 1d | `ShareIntentService emits intent on stream when platform sends data` | Stream wiring |
| 1e | `ShareIntentService handles initial intent (cold start)` | App launched from share |
| 1f | `ShareIntentService handles subsequent intents (warm start)` | App already running |
| 1g | `ShareIntentService ignores empty/null intents` | Edge case |
| 1h | `ShareIntentService.reset() clears handled intent so it does not re-trigger on resume` | Prevents duplicate handling |
| 1i | `bufferIntent copies shared files to app cache dir and returns intent with updated filePaths` | File durability: OS temp paths survive long onboarding |
| 1i2 | `bufferIntent with text-only intent (no files) stores without file I/O` | No unnecessary I/O when there are no files |
| 1i3 | `bufferIntent preserves original file names in cache dir` | File names stay recognizable (e.g. `IMG_1234.jpg`) |
| 1i4 | `bufferIntent gracefully falls back to original paths if file copy throws` | Degraded but not broken |
| 1j | `consumePendingIntent returns and clears buffered intent` | One-shot consume |
| 1k | `consumePendingIntent returns null when no intent buffered` | No false trigger |
| 1l | `isSettled defaults to false` | App starts in onboarding state |
| 1m | `isSettled can be set to true and warm-start handler reads it` | Settled flag is observable |

### Production Files (GREEN)

**File:** `lib/core/services/share_intent_model.dart`

```dart
enum ShareIntentType { text, files, mixed }

class ShareIntent {
  final ShareIntentType type;
  final String? text;          // Shared text or URL
  final List<String> filePaths; // Local file paths (images, videos)

  const ShareIntent({required this.type, this.text, this.filePaths = const []});

  bool get hasText => text != null && text!.isNotEmpty;
  bool get hasFiles => filePaths.isNotEmpty;

  /// Returns a copy with updated filePaths (used after cache-dir copy).
  ShareIntent copyWith({List<String>? filePaths}) => ShareIntent(
    type: type,
    text: text,
    filePaths: filePaths ?? this.filePaths,
  );
}
```

**File:** `lib/core/services/share_intent_service.dart`

```dart
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Injectable typedef so tests can supply a fake cache directory.
typedef GetCacheDirectoryFn = Future<Directory> Function();

/// Wraps ReceiveSharingIntent.instance — no custom platform channels.
class ShareIntentService {
  /// Injectable cache-directory provider. Defaults to path_provider's
  /// getTemporaryDirectory(). Tests pass a function returning an
  /// in-memory or temp-test directory.
  final GetCacheDirectoryFn _getCacheDirectory;

  ShareIntentService({
    GetCacheDirectoryFn? getCacheDirectory,
  }) : _getCacheDirectory = getCacheDirectory ?? getTemporaryDirectory;

  /// Whether the app has reached a "settled" state (FeedWired mounted after
  /// identity + contacts exist). Set to `true` by StartupRouter after
  /// `hasIdentityWithContacts`, or by FTE/QR after the first contact is added.
  /// The warm-start handler checks this to decide whether to push the picker
  /// or buffer the intent.
  bool isSettled = false;

  /// Stream of share intents from warm-start (app already running).
  /// Wraps ReceiveSharingIntent.instance.getMediaStream().
  Stream<ShareIntent> get intentStream;

  /// Initial intent from cold-start (app launched from share).
  /// Wraps ReceiveSharingIntent.instance.getInitialMedia().
  Future<ShareIntent?> getInitialIntent();

  /// Clear the handled intent so it does not re-trigger on app resume.
  /// Delegates to ReceiveSharingIntent.instance.reset().
  void reset();

  /// Buffer a share intent for deferred handling during onboarding.
  ///
  /// If the intent has files, copies them from the OS-provided temporary
  /// paths to the app's cache directory (`getTemporaryDirectory()/share_cache/`)
  /// so they survive while the user completes onboarding. The buffered
  /// intent's filePaths are updated to point to the cache copies.
  ///
  /// Text-only intents are stored immediately with no file I/O.
  /// If any individual file copy fails, the original path is kept for
  /// that file (best-effort — the file may still be available).
  ShareIntent? _pendingIntent;

  Future<void> bufferIntent(ShareIntent intent) async {
    if (!intent.hasFiles) {
      _pendingIntent = intent;
      return;
    }

    final cacheDir = await _getCacheDirectory();
    final shareCache = Directory(p.join(cacheDir.path, 'share_cache'));
    if (!shareCache.existsSync()) {
      shareCache.createSync(recursive: true);
    }

    final cachedPaths = <String>[];
    for (final originalPath in intent.filePaths) {
      try {
        final fileName = p.basename(originalPath);
        final destPath = p.join(shareCache.path, fileName);
        await File(originalPath).copy(destPath);
        cachedPaths.add(destPath);
      } catch (_) {
        // Graceful fallback: keep the original path if copy fails.
        cachedPaths.add(originalPath);
      }
    }

    _pendingIntent = intent.copyWith(filePaths: cachedPaths);
  }

  ShareIntent? consumePendingIntent() {
    final intent = _pendingIntent;
    _pendingIntent = null;
    return intent;
  }
  bool get hasPendingIntent => _pendingIntent != null;

  void dispose();
}
```

### Run
```bash
flutter test test/core/services/share_intent_service_test.dart
```

---

## Phase 2: Share Target Picker UI

### Goal
Build a picker screen where the user selects a contact or group to share
content with. Reuses the existing contact list pattern from
`ContactPickerScreen`. Media processing happens here (once) on target selection.

### Tests (RED)

**File:** `test/features/share/presentation/share_target_picker_screen_test.dart`

| # | Test | What it proves |
|---|------|----------------|
| 2a | `renders shared text preview` | Shows what's being shared |
| 2b | `renders shared image thumbnails` | File preview |
| 2c | `renders contact list` | Contacts loaded and displayed |
| 2d | `renders group list` | Groups loaded and displayed |
| 2e | `tapping contact calls onContactSelected` | Selection callback |
| 2f | `tapping group calls onGroupSelected` | Selection callback |
| 2g | `search filters both contacts and groups` | Search functionality |
| 2h | `cancel button calls onCancel` | Dismissal |
| 2i | `empty contacts/groups shows empty state` | Edge case |

**File:** `test/features/share/presentation/share_target_picker_wired_test.dart`

| # | Test | What it proves |
|---|------|----------------|
| 2j | `loads contacts and groups on init` | Data loading |
| 2k | `selecting contact navigates to ConversationWired with shared files` | 1:1 flow |
| 2l | `selecting group navigates to GroupConversationWired with shared files` | Group flow |
| 2m | `shared text is passed as initialText to conversation` | Text handling |
| 2n | `shared URL is passed as initialText to conversation` | URL handling |
| 2o | `shared images are processed via ImageProcessor on target selection` | Media processing (single place) |
| 2p | `cancel pops back to previous screen` | Navigation |
| 2q | `announcement group where user is member (not admin) is excluded from picker` | Read-only groups filtered out |
| 2r | `archived contact is excluded from picker` | Archived contacts not shareable |
| 2s | `archived group is excluded from picker` | Archived groups not shareable |

### Production Files (GREEN)

**File:** `lib/features/share/presentation/screens/share_target_picker_screen.dart`

Pure StatefulWidget (stateful for search filter):
- Header: "Share with..." + cancel button
- Preview strip: shows shared text/images/URLs
- Two sections: "Contacts" and "Groups" (or combined sorted by recency)
- Each row: avatar + name + tap handler
- Search field at top

**File:** `lib/features/share/presentation/screens/share_target_picker_wired.dart`

Wired StatefulWidget:
- Loads contacts via `contactRepository.getActiveContacts()` (excludes archived)
- Loads groups via `groupRepository.getActiveGroups()`, filtering out groups
  where the user cannot write (announcement groups where `myRole != admin`)
- On contact selected:
  1. Process shared media via `ImageProcessor` (EXIF strip, compress)
  2. Navigate to `ConversationWired(initialAttachments: processedFiles, initialText: text)`
- On group selected:
  1. Process shared media via `ImageProcessor`
  2. Navigate to `GroupConversationWired(initialAttachments: processedFiles, initialText: text)`
- For shared text/URLs: pass as `initialText` param (new, see Phase 7)

### Run
```bash
flutter test test/features/share/presentation/
```

---

## Phase 3: Android Share Target Configuration

### Goal
Make the app appear in Android's share sheet for text, images, and videos.
The `receive_sharing_intent` plugin handles all MethodChannel and intent
extraction automatically — no changes to `MainActivity.kt` needed.

### Tests (RED)

**File:** `test/core/services/share_intent_android_test.dart`

| # | Test | What it proves |
|---|------|----------------|
| 3a | `parses ACTION_SEND text/plain intent` | Text share from browser |
| 3b | `parses ACTION_SEND image/* intent` | Single image share |
| 3c | `parses ACTION_SEND video/* intent` | Single video share |
| 3d | `parses ACTION_SEND_MULTIPLE image/* intent` | Multi-image share |
| 3e | `parses mixed intent with text + image` | Instagram link + preview |
| 3f | `ignores intent with unsupported MIME type` | Edge case |

### Production Files (GREEN)

**File:** `android/app/src/main/AndroidManifest.xml`

Add intent filters inside the `<activity>` tag and `READ_EXTERNAL_STORAGE`
permission. Change `launchMode` to `singleTask` (required by the plugin):

```xml
<!-- Permission for reading shared files -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />

<!-- In <activity>, change launchMode: -->
android:launchMode="singleTask"

<!-- Add inside <activity>, after existing MAIN intent-filter: -->

<!-- Share text (URLs, links, plain text) -->
<intent-filter>
    <action android:name="android.intent.action.SEND" />
    <category android:name="android.intent.category.DEFAULT" />
    <data android:mimeType="text/plain" />
</intent-filter>

<!-- Share single image -->
<intent-filter>
    <action android:name="android.intent.action.SEND" />
    <category android:name="android.intent.category.DEFAULT" />
    <data android:mimeType="image/*" />
</intent-filter>

<!-- Share single video -->
<intent-filter>
    <action android:name="android.intent.action.SEND" />
    <category android:name="android.intent.category.DEFAULT" />
    <data android:mimeType="video/*" />
</intent-filter>

<!-- Share multiple images/videos -->
<intent-filter>
    <action android:name="android.intent.action.SEND_MULTIPLE" />
    <category android:name="android.intent.category.DEFAULT" />
    <data android:mimeType="image/*" />
    <data android:mimeType="video/*" />
</intent-filter>
```

**No changes to `MainActivity.kt`.** The plugin handles intent extraction
and MethodChannel communication automatically.

### Run
```bash
cd android && ./gradlew assembleDebug
flutter test test/core/services/share_intent_android_test.dart
```

---

## Phase 4: iOS Share Extension

### Goal
Configure the iOS Share Extension using the `receive_sharing_intent` plugin's
`RSIShareViewController` base class. No custom Swift IPC code needed.

### Tests (RED)

**File:** `test/core/services/share_intent_ios_test.dart`

| # | Test | What it proves |
|---|------|----------------|
| 4a | `parses shared URL from iOS extension` | URL share from Safari |
| 4b | `parses shared image from iOS extension` | Single image |
| 4c | `parses shared video from iOS extension` | Single video |
| 4d | `parses multiple shared images` | Multi-image share |
| 4e | `handles extension data via App Group UserDefaults` | IPC mechanism |

### Production Steps (GREEN)

**Step 1: Create Share Extension target in Xcode**
- File → New → Target → Share Extension
- Product name: `Share Extension`
- Language: Swift
- Embed in application: Runner

**Step 2: Create `ios/Share Extension/ShareViewController.swift`**

```swift
import receive_sharing_intent

class ShareViewController: RSIShareViewController {
    override func shouldAutoRedirect() -> Bool {
        return false
    }
}
```

(6 lines — all IPC, file copying, and UserDefaults are handled by the parent class)

**Step 3: Share Extension Info.plist** (`ios/Share Extension/Info.plist`)
- Set `AppGroupId` key to `group.com.example.flutterApp.share`
- Set `NSExtension` → `NSExtensionAttributes`:
  - `NSExtensionActivationSupportsText` = YES
  - `NSExtensionActivationSupportsWebURLWithMaxCount` = 10
  - `NSExtensionActivationSupportsImageWithMaxCount` = 10
  - `NSExtensionActivationSupportsMovieWithMaxCount` = 5
- Set `PHSupportedMediaTypes` for photo/video access

**Step 4: Runner Info.plist additions**
- Add `AppGroupId` = `group.com.example.flutterApp.share`
- Add URL scheme: `ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)`
- Add `NSPhotoLibraryUsageDescription` (if not already present)

**Step 5: Podfile addition**
```ruby
target 'Share Extension' do
  inherit! :search_paths
end
```

**Step 6: App Groups capability**
- Add App Groups capability to both Runner and Share Extension targets
- Use container ID: `group.com.example.flutterApp.share`
- Add `CUSTOM_GROUP_ID` user-defined build setting on both targets

**Step 7: Build Phases**
- Move "Embed Foundation Extensions" build phase above "Thin Binary"

**No changes to `AppDelegate.swift`.** The plugin handles URL scheme
handling automatically.

### Run
```bash
cd ios && pod install && xcodebuild -workspace Runner.xcworkspace -scheme Runner build
flutter test test/core/services/share_intent_ios_test.dart
```

---

## Phase 5: Main App Integration — Routing Shared Content

### Goal
Wire the ShareIntentService into the main app. Handle cold-start (app launched
from share) safely through the async StartupRouter, and warm-start (app in
background) by pushing the picker on top.

### Startup Decision Matrix

| Startup Decision | Share intent? | Behavior |
|---|---|---|
| `hasIdentityWithContacts` | Yes | Navigate to FeedWired, then push ShareTargetPickerWired on top |
| `hasIdentityNoContacts` | Yes | Navigate to FirstTimeExperienceWired (with ShareIntentService). Intent stays buffered. Consumed at the two first-contact exits that bypass StartupRouter: `first_time_experience_wired.dart:_acceptRequest` (contact request accept) and `qr_scanner_wired.dart:_showSuccessDialog` (QR scan OK button) |
| `needsIdentity` | Yes | Navigate to IdentityChoiceWired. Intent stays buffered through entire onboarding. After identity creation, StartupRouter navigates to FirstTimeExperienceWired (with ShareIntentService). Consumed at the same two first-contact exits described above |
| Any | No | Normal startup, no change |

Key rules:
- Never show the share picker before the user has both an identity AND at least
  one contact.
- Never discard a share intent silently.
- Copy shared files to the app's cache directory immediately upon buffering,
  before the OS can reclaim temporary paths during a long onboarding flow.
- Warm-start shares check `shareIntentService.isSettled`: if `true` (app
  has reached FeedWired with identity + contacts), push the picker directly.
  If `false` (still onboarding — no identity or no contacts yet), buffer the
  intent for later consumption.

### Tests (RED)

**File:** `test/features/share/application/handle_share_intent_use_case_test.dart`

| # | Test | What it proves |
|---|------|----------------|
| 5a | `cold start + hasIdentityWithContacts: picker shown after FeedWired mounts` | Happy-path cold start |
| 5b | `warm start with isSettled=true pushes picker directly` | Background → share on settled app |
| 5b2 | `warm start with isSettled=true (conversation open) pushes picker directly` | Background → share on conversation screen |
| 5c | `text-only share intent passes raw text to picker (no media processing)` | No premature processing |
| 5d | `image share intent passes raw file paths to picker` | No premature processing |
| 5e | `video share intent passes raw file paths to picker` | No premature processing |
| 5f | `picker cancel returns to previous screen` | Navigation |
| 5g | `picker contact selection opens ConversationWired` | 1:1 route |
| 5h | `picker group selection opens GroupConversationWired` | Group route |
| 5i | `share intent clears after handling via ShareIntentService.reset()` | No re-trigger on resume |
| 5j | `cold start + needsIdentity: intent is buffered, picker not shown` | No premature picker |
| 5k | `cold start + hasIdentityNoContacts: intent buffered until first contact added` | Deferred share |
| 5l | `cold start + needsIdentity: buffered intent filePaths point to cache dir, not OS temp dir` | Integration proof that bufferIntent's file copy is wired in |
| 5m | `warm start share with isSettled=false (no identity yet): intent is buffered, picker not shown` | No picker before identity exists |
| 5m2 | `warm start share with isSettled=false (no contacts yet): intent is buffered, picker not shown` | No picker before contacts exist |
| 5n | `FTE accept contact request with buffered intent: navigates to FeedWired then pushes picker` | Deferred consume at FTE _acceptRequest exit |
| 5o | `FTE accept contact request without buffered intent: navigates to FeedWired only (no picker)` | No false trigger when no intent buffered |
| 5p | `QR scan success with buffered intent: navigates to FeedWired then pushes picker` | Deferred consume at QR _showSuccessDialog exit |
| 5q | `QR scan success without buffered intent: navigates to FeedWired only (no picker)` | No false trigger when no intent buffered |
| 5r | `FTE accept notPending result with buffered intent: still consumes and pushes picker` | notPending is treated same as success for contact-exists |
| 5s | `needsIdentity full flow: intent buffered at startup, survives identity creation, consumed after first QR scan contact` | End-to-end deferred through full onboarding |

### Production Files (GREEN)

**File:** `lib/features/share/application/handle_share_intent_use_case.dart`

```dart
Future<void> handleShareIntent({
  required ShareIntent intent,
  required BuildContext context,
  // ... all DI deps needed for ShareTargetPickerWired
})
```

1. Build `ShareTargetPickerWired` with raw file paths + text
2. Push picker screen onto navigator
3. Picker handles target selection → processes media → navigates to conversation

(Media processing happens in the picker wired on target selection, NOT here.)

**File:** `lib/main.dart` — Thread `ShareIntentService` through DI chain:

`ShareIntentService` is created in `main()` alongside other DI dependencies
and threaded through `MyApp` → `StartupRouter` (follows the project's
established DI pattern).

```dart
// In _MyAppState.initState():
@override
void initState() {
  super.initState();
  // ... existing setup ...

  // Warm-start: app already running, share arrives via stream
  widget.shareIntentService.intentStream.listen(_handleIncomingShareIntent);

  // Cold-start: buffer the initial intent for StartupRouter to consume
  _bufferInitialShareIntent();
}

Future<void> _bufferInitialShareIntent() async {
  final intent = await widget.shareIntentService.getInitialIntent();
  if (intent != null) {
    // bufferIntent is async — copies files to cache dir before storing.
    await widget.shareIntentService.bufferIntent(intent);
  }
}

void _handleIncomingShareIntent(ShareIntent intent) {
  // Warm start: check whether the app has completed onboarding.
  // isSettled is set to true when the app reaches FeedWired with
  // identity + contacts (by StartupRouter, FTE, or QR scanner).
  if (!widget.shareIntentService.isSettled) {
    // Still onboarding — buffer for later consumption.
    // bufferIntent is async — fire-and-forget is OK here because
    // the intent will not be consumed until onboarding completes.
    widget.shareIntentService.bufferIntent(intent);
    return;
  }
  // App is on a settled screen (FeedWired, conversation, etc.)
  _navigateToSharePicker(intent);
  widget.shareIntentService.reset();
}
```

**File:** `lib/features/identity/presentation/startup_router.dart` — Consume
buffered intent after successful startup:

`StartupRouter` receives `ShareIntentService` as a constructor parameter.
After `hasIdentityWithContacts` branch completes its navigation, it checks
for a pending intent:

```dart
case StartupDecision.hasIdentityWithContacts:
  // ... existing FeedWired navigation ...
  _startP2PInBackground();
  widget.shareIntentService.isSettled = true; // NEW — app is ready for shares
  _consumePendingShareIntent(); // NEW

case StartupDecision.hasIdentityNoContacts:
  // Intent stays buffered. FTE consumes it after first contact is added.
  // isSettled remains false — no contacts yet.

case StartupDecision.needsIdentity:
  // Intent stays buffered through onboarding + FTE.
  // isSettled remains false — no identity yet.
```

```dart
void _consumePendingShareIntent() {
  final intent = widget.shareIntentService.consumePendingIntent();
  if (intent == null) return;
  widget.shareIntentService.reset();

  WidgetsBinding.instance.addPostFrameCallback((_) {
    final navigator = MyApp.navigatorKey.currentState;
    if (navigator == null) return;
    navigator.push(MaterialPageRoute(
      builder: (_) => ShareTargetPickerWired(shareIntent: intent, ...),
    ));
  });
}
```

The `addPostFrameCallback` is safe here because it fires AFTER
`_pushStartupReplacement` has already completed and the destination route
(FeedWired) is mounted.

**File:** `lib/features/identity/presentation/startup_router.dart` — Thread
ShareIntentService to FTE and QR scanner:

`StartupRouter` also threads `ShareIntentService` into every
`FirstTimeExperienceWired(...)` constructor call (there are three sites:
`hasIdentityNoContacts` branch, `needsIdentity` branch's `onNavigateToMain`
callback, and the helper `_navigateToFirstTime`). This follows the project's
established DI threading pattern.

**File:** `lib/features/home/presentation/screens/first_time_experience_wired.dart`
— Consume buffered intent after first contact is added:

`FirstTimeExperienceWired` accepts `ShareIntentService?` as an optional
constructor parameter. It passes the service through to `QRScannerWired`.

In `_acceptRequest`, after the contact is successfully added (result ==
`success` or `notPending`), and just before navigating to FeedWired, it
consumes the buffered intent and pushes the picker on top of FeedWired:

```dart
// In _acceptRequest, after Navigator.of(context).pushReplacement to FeedWired:
if (result == AcceptContactRequestResult.success ||
    result == AcceptContactRequestResult.notPending) {
  Navigator.of(context).pushReplacement(
    buildFeedSlideUpRoute(builder: (_) => FeedWired(...)),
  );
  // Mark settled — first contact now exists, app is ready for shares
  widget.shareIntentService?.isSettled = true;
  // Consume buffered share intent (if any) after first contact added
  _consumePendingShareIntent();
}

void _consumePendingShareIntent() {
  final shareService = widget.shareIntentService;
  if (shareService == null) return;
  final intent = shareService.consumePendingIntent();
  if (intent == null) return;
  shareService.reset();

  WidgetsBinding.instance.addPostFrameCallback((_) {
    final navigator = MyApp.navigatorKey.currentState;
    if (navigator == null) return;
    navigator.push(MaterialPageRoute(
      builder: (_) => ShareTargetPickerWired(shareIntent: intent, ...),
    ));
  });
}
```

The `addPostFrameCallback` ensures the picker is pushed AFTER FeedWired's
`pushReplacement` animation completes and the route is mounted.

**File:** `lib/features/qr_code/presentation/screens/qr_scanner_wired.dart`
— Consume buffered intent after QR-scan first contact added:

`QRScannerWired` accepts `ShareIntentService?` as an optional constructor
parameter. In `_showSuccessDialog`, the OK button's `onPressed` handler
navigates to FeedWired via `pushAndRemoveUntil`. After that navigation call,
it consumes the buffered intent:

```dart
// In _showSuccessDialog, inside the OK button onPressed:
onPressed: () {
  Navigator.of(ctx).pushAndRemoveUntil(
    buildFeedSlideUpRoute(builder: (_) => FeedWired(...)),
    (route) => false,
  );
  // Mark settled — first contact now exists, app is ready for shares
  shareIntentService?.isSettled = true;
  // Consume buffered share intent (if any) after first contact added
  _consumePendingShareIntent();
},

void _consumePendingShareIntent() {
  final shareService = shareIntentService;
  if (shareService == null) return;
  final intent = shareService.consumePendingIntent();
  if (intent == null) return;
  shareService.reset();

  WidgetsBinding.instance.addPostFrameCallback((_) {
    final navigator = MyApp.navigatorKey.currentState;
    if (navigator == null) return;
    navigator.push(MaterialPageRoute(
      builder: (_) => ShareTargetPickerWired(shareIntent: intent, ...),
    ));
  });
}
```

Both consume points use the same pattern as `_consumePendingShareIntent` in
`startup_router.dart`. The `addPostFrameCallback` ensures the picker is
pushed after FeedWired is mounted.

### Run
```bash
flutter test test/features/share/application/
flutter test test/features/share/
```

---

## Phase 6: Integration & Smoke Tests

### Goal
End-to-end tests proving the full share flow works.

### Tests

**File:** `test/features/share/integration/share_to_contact_smoke_test.dart`

| # | Test | What it proves |
|---|------|----------------|
| 6a | `share text to 1:1 contact: text appears in compose area` | Full 1:1 text flow |
| 6b | `share image to 1:1 contact: image in pending attachments` | Full 1:1 media flow |
| 6c | `share text to group: text appears in compose area` | Full group text flow |
| 6d | `share image to group: image in pending attachments` | Full group media flow |
| 6e | `share URL: URL text in compose area` | URL handling |
| 6f | `share multiple images: all in pending attachments` | Multi-file |
| 6g | `share from cold start (has identity + contacts): picker shown after FeedWired mounts` | Cold start happy path |
| 6g2 | `share from cold start (needs identity): picker shown only after onboarding + first contact` | Full onboarding |
| 6g3 | `share from cold start (has identity, no contacts): picker shown only after first contact added` | Partial onboarding |
| 6h | `share when no contacts: empty state shown` | Edge case |
| 6i | `announcement group where user is not admin is excluded from picker` | Read-only groups filtered out |

### Run
```bash
flutter test test/features/share/
```

---

## Phase 7: ComposeArea + Conversation Screens — Initial Text Support

### Goal
Both conversation screens already accept `initialAttachments` (files). Add
`initialText` parameter so shared text/URLs pre-fill the compose area.

The `TextEditingController` lives inside `ComposeArea` (compose_area.dart:44),
NOT in the screen widgets. The `initialText` param must be threaded through
three layers: Wired → Screen → ComposeArea.

### Tests (RED)

**File:** `test/features/conversation/presentation/widgets/compose_area_test.dart` (extend)

| # | Test | What it proves |
|---|------|----------------|
| 7a | `ComposeArea initialText seeds the text controller` | Controller pre-population |
| 7b | `ComposeArea without initialText starts empty` | No regression |

**File:** `test/features/conversation/presentation/conversation_wired_test.dart` (extend)

| # | Test | What it proves |
|---|------|----------------|
| 7c | `initialText pre-fills compose area in 1:1 conversation` | End-to-end threading |
| 7d | `initialText with initialAttachments shows both` | Combined share |

**File:** `test/features/groups/presentation/group_conversation_wired_test.dart` (extend)

| # | Test | What it proves |
|---|------|----------------|
| 7e | `initialText pre-fills compose area in group conversation` | Group text pre-population |

### Production Files (GREEN)

1. **`lib/features/conversation/presentation/widgets/compose_area.dart`**
   — Add `initialText` constructor param; seed `_controller.text = initialText`
   in `initState()`. This is where the `TextEditingController` lives (line 44).

2. **`lib/features/conversation/presentation/screens/conversation_screen.dart`**
   — Add `initialText` param; forward to `ComposeArea(initialText: initialText)`
   at the instantiation site (line 242).

3. **`lib/features/groups/presentation/screens/group_conversation_screen.dart`**
   — Add `initialText` param; forward to `ComposeArea(initialText: initialText)`
   at the instantiation site (line 134).

4. **`lib/features/conversation/presentation/screens/conversation_wired.dart`**
   — Add `initialText` constructor param; forward to `ConversationScreen`.

5. **`lib/features/groups/presentation/screens/group_conversation_wired.dart`**
   — Add `initialText` constructor param; forward to `GroupConversationScreen`.

Note: `group_compose_area.dart` exists but is dead code — `GroupConversationScreen`
uses the shared `ComposeArea` from the conversation feature. No changes needed.

### Run
```bash
flutter test test/features/conversation/presentation/widgets/compose_area_test.dart
flutter test test/features/conversation/presentation/conversation_wired_test.dart
flutter test test/features/groups/presentation/group_conversation_wired_test.dart
```

---

## Dependency Graph

```
Phase 1 (model + service + buffering)
    │
    ├──────────────┐
    ▼              ▼
Phase 2         Phase 7
(picker UI)     (ComposeArea initialText)
    │              │
    ├──────────────┘
    │
    ├──────────────┐
    ▼              ▼
Phase 3         Phase 4
(Android cfg)   (iOS extension cfg)
    │              │
    └──────┬───────┘
           ▼
    Phase 5 (main app routing + StartupRouter integration)
           │
           ▼
    Phase 6 (integration tests)
```

---

## Complete File Inventory

### New Files to Create

| File | Phase |
|------|-------|
| `lib/core/services/share_intent_model.dart` | 1 |
| `lib/core/services/share_intent_service.dart` | 1 |
| `lib/features/share/presentation/screens/share_target_picker_screen.dart` | 2 |
| `lib/features/share/presentation/screens/share_target_picker_wired.dart` | 2 |
| `lib/features/share/application/handle_share_intent_use_case.dart` | 5 |
| `ios/Share Extension/ShareViewController.swift` | 4 |
| `ios/Share Extension/Info.plist` | 4 |
| `test/core/services/share_intent_service_test.dart` | 1 |
| `test/features/share/presentation/share_target_picker_screen_test.dart` | 2 |
| `test/features/share/presentation/share_target_picker_wired_test.dart` | 2 |
| `test/features/share/application/handle_share_intent_use_case_test.dart` | 5 |
| `test/features/share/integration/share_to_contact_smoke_test.dart` | 6 |

### Existing Files to Modify

| File | Phase | Change |
|------|-------|--------|
| `pubspec.yaml` | 1 | Add `receive_sharing_intent` and `path_provider` packages (`path` is already a transitive dep) |
| `android/app/src/main/AndroidManifest.xml` | 3 | Add ACTION_SEND intent filters, `READ_EXTERNAL_STORAGE` permission, change `launchMode` to `singleTask` |
| `ios/Runner/Info.plist` | 4 | Add `AppGroupId`, URL scheme `ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)`, `NSPhotoLibraryUsageDescription` |
| `ios/Runner.xcodeproj/project.pbxproj` | 4 | Add Share Extension target, App Groups capability |
| `ios/Podfile` | 4 | Add `target 'Share Extension' do inherit! :search_paths end` |
| `lib/main.dart` | 5 | Create ShareIntentService in DI chain, thread through MyApp → StartupRouter |
| `lib/features/identity/presentation/startup_router.dart` | 5 | Accept ShareIntentService, consume pending intent after `hasIdentityWithContacts` startup, thread ShareIntentService to FTE and QR scanner via all FirstTimeExperienceWired constructor sites |
| `lib/features/home/presentation/screens/first_time_experience_wired.dart` | 5 | Accept `ShareIntentService?`, pass to QRScannerWired, consume buffered intent after contact request accepted (`_acceptRequest` navigates to FeedWired at line ~177, bypassing StartupRouter) |
| `lib/features/qr_code/presentation/screens/qr_scanner_wired.dart` | 5 | Accept `ShareIntentService?`, consume buffered intent after QR-scan success dialog OK (`_showSuccessDialog` navigates to FeedWired at line ~309, bypassing StartupRouter) |
| `lib/features/conversation/presentation/widgets/compose_area.dart` | 7 | Add `initialText` param, seed `_controller.text` in `initState()` |
| `lib/features/conversation/presentation/screens/conversation_screen.dart` | 7 | Add `initialText` param, forward to ComposeArea |
| `lib/features/groups/presentation/screens/group_conversation_screen.dart` | 7 | Add `initialText` param, forward to ComposeArea |
| `lib/features/conversation/presentation/screens/conversation_wired.dart` | 7 | Add `initialText` param, forward to ConversationScreen |
| `lib/features/groups/presentation/screens/group_conversation_wired.dart` | 7 | Add `initialText` param, forward to GroupConversationScreen |

---

## Implementation Order

1. Add `receive_sharing_intent` and `path_provider` to pubspec.yaml
2. Create share intent model + service with buffering (Phase 1)
3. Add `initialText` to ComposeArea + conversation screens (Phase 7)
4. Create share target picker UI with group filtering (Phase 2)
5. Configure Android intent filters (no native Kotlin code needed) (Phase 3)
6. Configure iOS share extension with RSIShareViewController (no custom Swift IPC needed) (Phase 4)
7. Wire into main.dart + StartupRouter startup flow with buffering (Phase 5)
8. Integration smoke tests (Phase 6)

## Commit Boundaries

| # | Commit | Phases |
|---|--------|--------|
| 1 | Share intent model, service (with buffering), and ComposeArea initialText | 1, 7 |
| 2 | Share target picker UI with announce group filtering | 2 |
| 3 | Android share target configuration | 3 |
| 4 | iOS share extension configuration | 4 |
| 5 | Main app + StartupRouter routing, buffered intent handling, integration tests | 5, 6 |

## Run Order (Full Suite)

```bash
flutter test test/core/services/share_intent_service_test.dart
flutter test test/features/conversation/presentation/widgets/compose_area_test.dart
flutter test test/features/share/presentation/
flutter test test/features/share/application/
flutter test test/features/share/integration/
flutter test test/features/conversation/presentation/conversation_wired_test.dart
flutter test test/features/groups/presentation/group_conversation_wired_test.dart
# Existing regression:
flutter test test/features/feed/
flutter test test/features/groups/application/
flutter test test/features/conversation/integration/
```

## Acceptance Criteria

- [ ] mknoon appears in Android share sheet for text, images, and videos
- [ ] mknoon appears in iOS share sheet for text, images, and videos
- [ ] Share picker shows only active (non-archived) contacts and active writable groups (archived and announcement-for-non-admin groups excluded)
- [ ] Shared text/URL pre-fills the compose area via ComposeArea.initialText
- [ ] Shared images are processed (EXIF stripped, compressed) once on target selection in picker
- [ ] Shared videos are processed once on target selection in picker
- [ ] Multiple shared files are all attached
- [ ] Cold start + has identity + contacts → picker shown after FeedWired mounts
- [ ] Cold start + needs identity → intent buffered through onboarding, picker after first contact
- [ ] Cold start + no contacts → intent buffered, picker after first contact added
- [ ] Warm start on settled screen (feed/conversation) → share picker overlays current screen
- [ ] Warm start on onboarding screen → intent buffered, picker shown only after identity + first contact
- [ ] ShareIntentService.reset() called after handling to prevent re-trigger on resume
- [ ] Shared file paths copied to `getTemporaryDirectory()/share_cache/` when buffered during onboarding (via `ShareIntentService.bufferIntent`)
- [ ] After sharing, user can navigate normally
- [ ] Existing app functionality is not affected
- [ ] All existing tests remain green
