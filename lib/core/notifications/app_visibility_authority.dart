import 'dart:async';

import 'package:flutter/services.dart';

import 'app_visibility_snapshot.dart';

const String appVisibilityPlatformChannelName = 'mknoon/app_visibility';
const String appVisibilityReadSnapshotMethod = 'readSnapshot';
const String appVisibilityPublishVisibleConversationMethod =
    'publishVisibleConversation';

/// One snapshot read paired with native monotonic time and boot identity.
/// Keeping the three values in one response avoids an incoherent two-call age
/// calculation across a native lifecycle transition.
final class AppVisibilityPlatformRead {
  const AppVisibilityPlatformRead({
    required this.snapshot,
    required this.currentMonotonicMs,
    required this.currentBootSession,
  });

  final AppVisibilitySnapshotV1 snapshot;
  final int currentMonotonicMs;
  final String currentBootSession;
}

/// Result of a native generation-CAS route/heartbeat projection.
final class AppVisibilityPlatformWrite {
  const AppVisibilityPlatformWrite({
    required this.committed,
    required this.snapshot,
    required this.currentMonotonicMs,
    required this.currentBootSession,
  });

  final bool committed;
  final AppVisibilitySnapshotV1? snapshot;
  final int currentMonotonicMs;
  final String currentBootSession;
}

abstract interface class AppVisibilityPlatformBridge {
  Future<AppVisibilityPlatformRead?> readSnapshot();

  Future<AppVisibilityPlatformWrite?> publishVisibleConversation({
    required String? visibleConversationDigest,
    required int lifecycleGeneration,
  });
}

/// Strict MethodChannel projection. Any missing plugin, platform failure, or
/// malformed response returns null so the authority fails toward notification.
final class MethodChannelAppVisibilityPlatformBridge
    implements AppVisibilityPlatformBridge {
  MethodChannelAppVisibilityPlatformBridge({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel(appVisibilityPlatformChannelName);

  final MethodChannel _channel;

  @override
  Future<AppVisibilityPlatformRead?> readSnapshot() async {
    try {
      final response = await _channel.invokeMethod<Object?>(
        appVisibilityReadSnapshotMethod,
      );
      final map = _exactMap(response, const <String>{
        'snapshot',
        'currentMonotonicMs',
        'currentBootSession',
      });
      if (map == null) return null;
      final snapshot = AppVisibilitySnapshotCodec.tryDecodePlatform(
        map['snapshot'],
      );
      final currentMonotonicMs = map['currentMonotonicMs'];
      final currentBootSession = map['currentBootSession'];
      if (snapshot == null ||
          !isNonnegativeAppVisibilityInt64(currentMonotonicMs) ||
          !isCanonicalAppVisibilityBootSession(currentBootSession)) {
        return null;
      }
      return AppVisibilityPlatformRead(
        snapshot: snapshot,
        currentMonotonicMs: currentMonotonicMs! as int,
        currentBootSession: currentBootSession! as String,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on Object {
      return null;
    }
  }

  @override
  Future<AppVisibilityPlatformWrite?> publishVisibleConversation({
    required String? visibleConversationDigest,
    required int lifecycleGeneration,
  }) async {
    if ((visibleConversationDigest != null &&
            !isCanonicalAppVisibilityDigest(visibleConversationDigest)) ||
        !isPositiveAppVisibilityInt64(lifecycleGeneration)) {
      return null;
    }
    try {
      final response = await _channel.invokeMethod<Object?>(
        appVisibilityPublishVisibleConversationMethod,
        <String, Object?>{
          'visibleConversationDigest': visibleConversationDigest,
          'lifecycleGeneration': lifecycleGeneration,
        },
      );
      final map = _exactMap(response, const <String>{
        'committed',
        'snapshot',
        'currentMonotonicMs',
        'currentBootSession',
      });
      if (map == null || map['committed'] is! bool) return null;
      final rawSnapshot = map['snapshot'];
      final snapshot = rawSnapshot == null
          ? null
          : AppVisibilitySnapshotCodec.tryDecodePlatform(rawSnapshot);
      final currentMonotonicMs = map['currentMonotonicMs'];
      final currentBootSession = map['currentBootSession'];
      if ((rawSnapshot != null && snapshot == null) ||
          !isNonnegativeAppVisibilityInt64(currentMonotonicMs) ||
          !isCanonicalAppVisibilityBootSession(currentBootSession)) {
        return null;
      }
      return AppVisibilityPlatformWrite(
        committed: map['committed']! as bool,
        snapshot: snapshot,
        currentMonotonicMs: currentMonotonicMs! as int,
        currentBootSession: currentBootSession! as String,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on Object {
      return null;
    }
  }
}

/// One coherent notification decision from one native snapshot read.
final class AppVisibilityEvaluation {
  const AppVisibilityEvaluation({
    required this.isForegroundActive,
    required this.maySuppress,
  });

  static const failNotify = AppVisibilityEvaluation(
    isForegroundActive: false,
    maySuppress: false,
  );

  final bool isForegroundActive;
  final bool maySuppress;
}

/// Small injection boundary used by notification presentation owners.
///
/// Implementations perform one read in [evaluate], returning both facts needed
/// by callers. Tests can extend this class and override only [evaluate].
abstract class AppVisibilitySuppressionReader {
  Future<AppVisibilityEvaluation> evaluate(
    AppVisibilityConversationIdentity? identity,
  );

  Future<bool> maySuppress(AppVisibilityConversationIdentity identity) async =>
      (await evaluate(identity)).maySuppress;

  Future<bool> isForegroundActive() async =>
      (await evaluate(null)).isForegroundActive;
}

/// The sole Dart owner of native visibility reads and route projections.
///
/// All bridge I/O is serialized. Synchronous lifecycle invalidation advances a
/// local epoch immediately, so an already-running or queued route write cannot
/// restore an eligible cached generation after pause/background/teardown.
final class AppVisibilityAuthority extends AppVisibilitySuppressionReader {
  AppVisibilityAuthority({required AppVisibilityPlatformBridge platformBridge})
    : _platformBridge = platformBridge;

  final AppVisibilityPlatformBridge _platformBridge;
  Future<void> _tail = Future<void>.value();
  int _invalidationEpoch = 0;
  bool _disposed = false;
  AppVisibilityPlatformRead? _currentRead;
  int? _ineligibleLifecycleGeneration;

  int? get lifecycleGeneration => _currentRead?.snapshot.lifecycleGeneration;

  String? get visibleConversationDigest =>
      _currentRead?.snapshot.visibleConversationDigest;

  bool get isDisposed => _disposed;

  /// Immediately makes the current process fail toward notification.
  void invalidateSynchronously() {
    _ineligibleLifecycleGeneration ??= lifecycleGeneration;
    _invalidationEpoch++;
    _currentRead = null;
  }

  /// Loads the native lifecycle generation before the current top route is
  /// republished. Returns false for inactive, stale, malformed, or failed state.
  Future<bool> synchronize() {
    final epoch = _invalidationEpoch;
    return _serialize(() async {
      if (!_canContinue(epoch)) return false;
      final read = await _safeRead();
      if (!_canContinue(epoch)) return false;
      return _adoptForegroundRead(read);
    });
  }

  @override
  Future<AppVisibilityEvaluation> evaluate(
    AppVisibilityConversationIdentity? identity,
  ) {
    final epoch = _invalidationEpoch;
    return _serialize(() async {
      if (!_canContinue(epoch)) return AppVisibilityEvaluation.failNotify;
      final read = await _safeRead();
      if (!_canContinue(epoch) || !_adoptForegroundRead(read)) {
        return AppVisibilityEvaluation.failNotify;
      }
      final current = _currentRead!;
      return AppVisibilityEvaluation(
        isForegroundActive: true,
        maySuppress:
            identity != null &&
            maySuppressAppVisibilityNotification(
              snapshot: current.snapshot,
              currentMonotonicMs: current.currentMonotonicMs,
              currentBootSession: current.currentBootSession,
              expectedConversationDigest: identity.digest,
            ),
      );
    });
  }

  Future<bool> publishVisibleConversation(
    AppVisibilityConversationIdentity identity,
  ) => _publishDigest(identity.digest);

  Future<bool> clearVisibleConversation() => _publishDigest(null);

  /// Renews the current digest through the incumbent presence heartbeat.
  Future<bool> refreshVisibleConversation() {
    final epoch = _invalidationEpoch;
    return _serialize(() async {
      if (!_canContinue(epoch)) return false;
      if (_currentRead == null) {
        final read = await _safeRead();
        if (!_canContinue(epoch) || !_adoptForegroundRead(read)) return false;
      }
      return _publishDigestSerialized(
        _currentRead!.snapshot.visibleConversationDigest,
        epoch,
      );
    });
  }

  Future<bool> _publishDigest(String? digest) {
    final epoch = _invalidationEpoch;
    return _serialize(() => _publishDigestSerialized(digest, epoch));
  }

  Future<bool> _publishDigestSerialized(String? digest, int epoch) async {
    if (!_canContinue(epoch)) return false;
    if (_currentRead == null) {
      final read = await _safeRead();
      if (!_canContinue(epoch) || !_adoptForegroundRead(read)) return false;
    }
    final generation = lifecycleGeneration;
    if (generation == null) return false;

    final write = await _safePublish(
      visibleConversationDigest: digest,
      lifecycleGeneration: generation,
    );
    if (!_canContinue(epoch) ||
        write == null ||
        !write.committed ||
        write.snapshot == null ||
        write.snapshot!.lifecycleGeneration != generation ||
        write.snapshot!.visibleConversationDigest != digest ||
        !_isForegroundWrite(write)) {
      if (_canContinue(epoch)) _markIneligible();
      return false;
    }
    _currentRead = AppVisibilityPlatformRead(
      snapshot: write.snapshot!,
      currentMonotonicMs: write.currentMonotonicMs,
      currentBootSession: write.currentBootSession,
    );
    _ineligibleLifecycleGeneration = null;
    return true;
  }

  Future<AppVisibilityPlatformRead?> _safeRead() async {
    try {
      return await _platformBridge.readSnapshot();
    } on Object {
      return null;
    }
  }

  Future<AppVisibilityPlatformWrite?> _safePublish({
    required String? visibleConversationDigest,
    required int lifecycleGeneration,
  }) async {
    try {
      return await _platformBridge.publishVisibleConversation(
        visibleConversationDigest: visibleConversationDigest,
        lifecycleGeneration: lifecycleGeneration,
      );
    } on Object {
      return null;
    }
  }

  bool _adoptForegroundRead(AppVisibilityPlatformRead? read) {
    if (read == null ||
        !isCurrentForegroundAppVisibilitySnapshot(
          snapshot: read.snapshot,
          currentMonotonicMs: read.currentMonotonicMs,
          currentBootSession: read.currentBootSession,
        )) {
      _markIneligible(generation: read?.snapshot.lifecycleGeneration);
      return false;
    }
    if (_ineligibleLifecycleGeneration == read.snapshot.lifecycleGeneration) {
      _currentRead = null;
      return false;
    }
    _ineligibleLifecycleGeneration = null;
    _currentRead = read;
    return true;
  }

  bool _isForegroundWrite(AppVisibilityPlatformWrite write) =>
      isCurrentForegroundAppVisibilitySnapshot(
        snapshot: write.snapshot,
        currentMonotonicMs: write.currentMonotonicMs,
        currentBootSession: write.currentBootSession,
      );

  bool _canContinue(int epoch) => !_disposed && epoch == _invalidationEpoch;

  void _markIneligible({int? generation}) {
    _ineligibleLifecycleGeneration ??= generation ?? lifecycleGeneration;
    _invalidationEpoch++;
    _currentRead = null;
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    invalidateSynchronously();
  }
}

Map<String, Object?>? _exactMap(Object? value, Set<String> expectedKeys) {
  if (value is! Map || value.length != expectedKeys.length) return null;
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String || !expectedKeys.contains(key)) return null;
    result[key] = entry.value;
  }
  return result.length == expectedKeys.length ? result : null;
}
