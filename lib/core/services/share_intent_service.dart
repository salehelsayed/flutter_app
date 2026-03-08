import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'share_intent_model.dart';

/// Injectable typedef so tests can supply a fake cache directory.
typedef GetCacheDirectoryFn = Future<Directory> Function();

/// Wraps `ReceiveSharingIntent.instance` — no custom platform channels.
///
/// Converts plugin `SharedMediaFile` objects into app-domain `ShareIntent`
/// objects, and provides buffering + cache-copy for deferred handling
/// during onboarding.
class ShareIntentService {
  final GetCacheDirectoryFn _getCacheDirectory;

  /// Whether the app has reached a "settled" state (FeedWired mounted
  /// after identity + contacts exist). Set to `true` by StartupRouter
  /// after `hasIdentityWithContacts`, or by FTE/QR after the first
  /// contact is added.
  bool isSettled = false;

  ShareIntentService({
    GetCacheDirectoryFn? getCacheDirectory,
  }) : _getCacheDirectory = getCacheDirectory ?? getTemporaryDirectory;

  /// Stream of share intents from warm-start (app already running).
  Stream<ShareIntent> get intentStream {
    return ReceiveSharingIntent.instance
        .getMediaStream()
        .map(_convertMediaList)
        .where((intent) => intent != null)
        .cast<ShareIntent>();
  }

  /// Initial intent from cold-start (app launched from share).
  Future<ShareIntent?> getInitialIntent() async {
    final media = await ReceiveSharingIntent.instance.getInitialMedia();
    return _convertMediaList(media);
  }

  /// Clear the handled intent so it does not re-trigger on app resume.
  void reset() {
    ReceiveSharingIntent.instance.reset();
  }

  /// Buffer a share intent for deferred handling during onboarding.
  ///
  /// If the intent has files, copies them from OS-provided temporary
  /// paths to the app's cache directory so they survive while the user
  /// completes onboarding.
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
        cachedPaths.add(originalPath);
      }
    }

    _pendingIntent = intent.copyWith(filePaths: cachedPaths);
  }

  /// Consume and clear the buffered intent (one-shot).
  ShareIntent? consumePendingIntent() {
    final intent = _pendingIntent;
    _pendingIntent = null;
    return intent;
  }

  /// Whether there is a buffered intent waiting.
  bool get hasPendingIntent => _pendingIntent != null;

  void dispose() {
    // No-op — the plugin manages its own resources.
  }

  /// Converts plugin media list to domain model.
  static ShareIntent? _convertMediaList(List<SharedMediaFile> media) {
    if (media.isEmpty) return null;

    final textItems = <String>[];
    final filePaths = <String>[];

    for (final item in media) {
      if (item.type == SharedMediaType.url ||
          item.type == SharedMediaType.text) {
        if (item.path.isNotEmpty) textItems.add(item.path);
      } else {
        if (item.path.isNotEmpty) filePaths.add(item.path);
      }
    }

    if (textItems.isEmpty && filePaths.isEmpty) return null;

    final text = textItems.isNotEmpty ? textItems.join('\n') : null;
    final ShareIntentType type;
    if (text != null && filePaths.isNotEmpty) {
      type = ShareIntentType.mixed;
    } else if (filePaths.isNotEmpty) {
      type = ShareIntentType.files;
    } else {
      type = ShareIntentType.text;
    }

    return ShareIntent(type: type, text: text, filePaths: filePaths);
  }
}
