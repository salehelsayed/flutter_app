import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';

const Duration recentRemoteNotificationTtl = Duration(seconds: 30);
const Duration recentRemoteNotificationMessageTtl = Duration(hours: 12);

const String _recentRemoteNotificationFileName =
    'mknoon_recent_remote_notifications.json';

// 04-P0 / SI-5: subdirectory of the SHARED app-group container where the
// out-of-process iOS NSE drops per-message "already shown" sidecar markers
// (filename = sha256 hex of the gate message key) for the Dart gate to consume.
const String _recentRemoteShownSidecarDirName = 'RecentRemoteShown';

RecentRemoteNotificationGate recentRemoteNotificationGate =
    RecentRemoteNotificationGate();

@visibleForTesting
void debugSetRecentRemoteNotificationGate(RecentRemoteNotificationGate gate) {
  recentRemoteNotificationGate = gate;
}

@visibleForTesting
void debugResetRecentRemoteNotificationGate() {
  recentRemoteNotificationGate = RecentRemoteNotificationGate();
}

void _defaultRecentRemoteGateLoadError(Object error, StackTrace stack) {
  // 04-P0 / QW-3: a wiped/corrupt gate file silently bypassed dedupe and the
  // 12h redelivery guard. Surface the decode failure instead of swallowing it.
  emitFlowEvent(
    layer: 'FL',
    event: 'RECENT_REMOTE_NOTIFICATION_GATE_DECODE_ERROR',
    details: {'error': error.runtimeType.toString()},
  );
}

class RecentRemoteNotificationGate {
  final String? _explicitFilePath;
  final Duration ttl;
  final Duration messageTtl;
  final DateTime Function() _now;
  final Future<Directory> Function() _supportDirectoryProvider;
  final void Function(Object error, StackTrace stack) _onLoadError;
  final bool _fallbackToSystemTempOnDirectoryError;

  // 04-P0 / SI-5: iOS-only provider for the SHARED app-group container the NSE
  // writes sidecar markers into. Null off-iOS / in tests that don't inject it,
  // in which case the gate behaves exactly as before (app-support JSON only).
  final Future<Directory> Function()? _appGroupSidecarDirProvider;

  // 04-P0 / SI-4: resolve the durable path once and cache the Future so
  // concurrent _loadEntries/_writeEntries/clear calls never re-resolve (and
  // never double-hit the platform channel).
  Future<String>? _resolvedPathFuture;

  // 04-P0 / SI-5: resolved-once app-group sidecar dir + a one-time stale-marker
  // prune so the dir cannot grow unbounded if the Dart isolate never consumes
  // an NSE-written marker.
  Future<String?>? _resolvedSidecarDirFuture;
  bool _sidecarPruneDone = false;

  RecentRemoteNotificationGate({
    String? filePath,
    Duration? ttl,
    Duration? messageTtl,
    DateTime Function()? now,
    Future<Directory> Function()? supportDirectoryProvider,
    void Function(Object error, StackTrace stack)? onLoadError,
    Future<Directory> Function()? appGroupSidecarDirProvider,
    bool fallbackToSystemTempOnDirectoryError = true,
  }) : _explicitFilePath = filePath,
       ttl = ttl ?? recentRemoteNotificationTtl,
       messageTtl = messageTtl ?? recentRemoteNotificationMessageTtl,
       _now = now ?? DateTime.now,
       _supportDirectoryProvider =
           supportDirectoryProvider ?? getApplicationSupportDirectory,
       _onLoadError = onLoadError ?? _defaultRecentRemoteGateLoadError,
       _fallbackToSystemTempOnDirectoryError =
           fallbackToSystemTempOnDirectoryError,
       _appGroupSidecarDirProvider = appGroupSidecarDirProvider;

  /// Synchronous view of the configured path. When an explicit [filePath] was
  /// provided (every test does) it is returned verbatim; otherwise the durable
  /// app-support path is resolved lazily on first IO and this returns the
  /// systemTemp fallback name. No production code reads this getter — IO uses
  /// the lazily-resolved path via [resolveFilePath].
  String get filePath =>
      _explicitFilePath ??
      '${Directory.systemTemp.path}/$_recentRemoteNotificationFileName';

  @visibleForTesting
  Future<String> resolveFilePath() => _resolveFilePath();

  Future<String> _resolveFilePath() async {
    final cached = _resolvedPathFuture;
    if (cached != null) {
      return cached;
    }
    final resolving = _doResolveFilePath();
    _resolvedPathFuture = resolving;
    try {
      return await resolving;
    } catch (_) {
      // App Group availability can race first-launch persistence. Do not pin a
      // failed resolution; the next mark/consume must retry the shared path.
      _resolvedPathFuture = null;
      rethrow;
    }
  }

  Future<String> _doResolveFilePath() async {
    final explicit = _explicitFilePath;
    if (explicit != null) {
      // Explicit path short-circuits before any platform-channel await so
      // tests (and the per-test isolation bootstrap) stay synchronous-pathed.
      return explicit;
    }
    try {
      final dir = await _supportDirectoryProvider();
      return '${dir.path}/$_recentRemoteNotificationFileName';
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RECENT_REMOTE_NOTIFICATION_GATE_DIR_FALLBACK',
        details: {'error': error.runtimeType.toString()},
      );
      if (!_fallbackToSystemTempOnDirectoryError) {
        rethrow;
      }
      return '${Directory.systemTemp.path}/$_recentRemoteNotificationFileName';
    }
  }

  Future<String?> _resolveSidecarDir() async {
    // 04-P0 / SI-5: memoize ONLY a successful (non-null) resolution. A null
    // means the shared app-group path is not available yet — most importantly
    // on first-ever launch, where the path is persisted by an UNAWAITED call in
    // main() and an early push can race ahead of it. Caching that transient null
    // via `??=` would pin it for the whole gate lifetime and silently disable
    // SI-5 cross-process dedupe for the entire session. Re-attempt on each
    // consume until it resolves, then cache the concrete dir.
    final cached = _resolvedSidecarDirFuture;
    if (cached != null) {
      return cached;
    }
    final dirPath = await _doResolveSidecarDir();
    if (dirPath != null) {
      _resolvedSidecarDirFuture = Future<String?>.value(dirPath);
    }
    return dirPath;
  }

  Future<String?> _doResolveSidecarDir() async {
    final provider = _appGroupSidecarDirProvider;
    if (provider == null) {
      return null;
    }
    try {
      final dir = await provider();
      return '${dir.path}/$_recentRemoteShownSidecarDirName';
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RECENT_REMOTE_NOTIFICATION_GATE_SIDECAR_DIR_FALLBACK',
        details: {'error': error.runtimeType.toString()},
      );
      return null;
    }
  }

  /// 04-P0 / SI-5: filesystem-safe marker name shared with the Swift NSE writer
  /// — sha256 hex of the exact gate message key, so both processes name the same
  /// file for the same (payload, messageId). Locked by the contract test.
  ///
  /// Known fail-open edge: for 1:1 the key's peer component is the live
  /// producer's `payload.senderPeerId`, while the NSE derives it from the relay
  /// push `sender_id` (= transport `entry.From`). In the rare case those differ
  /// (multi-device / relay-forward — flagged as TRANSPORT_SENDER_MISMATCH in
  /// handle_incoming_chat_message_use_case) the two filenames diverge and the
  /// duplicate banner is NOT suppressed. This is the SAME pre-existing equality
  /// the 118-era FCM-mark/live-consume dedupe already relied on; the worst case
  /// is one redundant local banner, never a lost or falsely-suppressed message.
  String sidecarMarkerName(String payload, String messageId) =>
      sha256.convert(utf8.encode(_messageKey(payload, messageId))).toString();

  /// 04-P0 / SI-5: cross-process dedupe fallback. When the Dart map missed, the
  /// out-of-process iOS NSE may already have shown this push and dropped a
  /// per-message marker into the shared app-group container. Honor it (and
  /// consume it) when present within the 12h message TTL, so the duplicate Dart
  /// banner is suppressed even though the Dart isolate never saw the push.
  Future<bool> _consumeSidecarMarker(String payload, String messageId) async {
    final dirPath = await _resolveSidecarDir();
    if (dirPath == null) {
      return false;
    }
    await _pruneStaleSidecarsOnce(dirPath);
    try {
      final file = File('$dirPath/${sidecarMarkerName(payload, messageId)}');
      if (!await file.exists()) {
        return false;
      }
      final ageMs =
          _now().millisecondsSinceEpoch -
          (await file.lastModified()).millisecondsSinceEpoch;
      await file.delete();
      return ageMs <= messageTtl.inMilliseconds;
    } catch (_) {
      return false;
    }
  }

  /// Reads exact NSE proof without deleting it. Durable notification owners
  /// use this before entering their ledger state machine and consume the
  /// marker only after the effect receipt and SQL custody handoff succeed.
  Future<bool> _hasRecentSidecarMarker(String payload, String messageId) async {
    return await _recentSidecarTimestamp(payload, messageId) != null;
  }

  Future<int?> _recentSidecarTimestamp(String payload, String messageId) async {
    final dirPath = await _resolveSidecarDir();
    if (dirPath == null) {
      return null;
    }
    await _pruneStaleSidecarsOnce(dirPath);
    try {
      final file = File('$dirPath/${sidecarMarkerName(payload, messageId)}');
      if (!await file.exists()) {
        return null;
      }
      final modifiedAtMs = (await file.lastModified()).millisecondsSinceEpoch;
      final ageMs = _now().millisecondsSinceEpoch - modifiedAtMs;
      if (ageMs <= messageTtl.inMilliseconds) {
        return modifiedAtMs;
      }
      await file.delete();
    } catch (_) {}
    return null;
  }

  /// iOS foreground arrivals are never presented (the FCM plugin completes
  /// willPresent with no presentation options), but the out-of-process NSE has
  /// already dropped its "shown" sidecar for the push. Discard that marker —
  /// without reporting a suppression hit and without touching the Dart-map
  /// entries — so the live/local materialization can present the one visible
  /// banner. Idempotent; a missing marker or unresolvable dir is a no-op.
  Future<void> discardSidecarMarker({
    required String payload,
    String? messageId,
  }) async {
    final normalizedPayload = _normalizePayload(payload);
    final normalizedMessageId = _normalizePayload(messageId);
    if (normalizedPayload == null || normalizedMessageId == null) {
      return;
    }
    final dirPath = await _resolveSidecarDir();
    if (dirPath == null) {
      return;
    }
    try {
      final file = File(
        '$dirPath/${sidecarMarkerName(normalizedPayload, normalizedMessageId)}',
      );
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<void> _pruneStaleSidecarsOnce(String dirPath) async {
    if (_sidecarPruneDone) {
      return;
    }
    _sidecarPruneDone = true;
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        return;
      }
      final cutoffMs =
          _now().millisecondsSinceEpoch - messageTtl.inMilliseconds;
      await for (final entity in dir.list()) {
        if (entity is! File) {
          continue;
        }
        try {
          if ((await entity.lastModified()).millisecondsSinceEpoch < cutoffMs) {
            await entity.delete();
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> markPayload(String payload) async {
    await markAnnouncement(payload: payload);
  }

  Future<void> markAnnouncement({
    required String payload,
    String? messageId,
  }) async {
    final normalizedPayload = _normalizePayload(payload);
    if (normalizedPayload == null) {
      return;
    }

    final entries = await _loadEntries();
    final timestamp = _now().millisecondsSinceEpoch;
    final normalizedMessageId = _normalizePayload(messageId);
    if (normalizedMessageId != null) {
      entries[_messageKey(normalizedPayload, normalizedMessageId)] = timestamp;
    } else {
      entries[_payloadKey(normalizedPayload)] = timestamp;
    }
    await _writeEntries(entries);
  }

  Future<bool> consumeIfRecentPayload(String payload) async {
    return consumeIfRecentAnnouncement(payload: payload);
  }

  Future<bool> hasRecentPayload(String payload) async {
    return hasRecentAnnouncement(payload: payload);
  }

  /// Non-destructively checks for an exact recent announcement.
  ///
  /// Unlike [consumeIfRecentAnnouncement], this preserves both the Dart-map
  /// entry and the NSE sidecar. Callers that are about to durably adopt an
  /// already-presented remote effect must keep that proof retryable until
  /// their ledger and SQL handoff are terminal.
  Future<bool> hasRecentAnnouncement({
    required String payload,
    String? messageId,
  }) async {
    final normalizedPayload = _normalizePayload(payload);
    if (normalizedPayload == null) {
      return false;
    }

    final entries = await _loadEntries();
    final normalizedMessageId = _normalizePayload(messageId);
    if (normalizedMessageId != null &&
        (entries.containsKey(
              _messageKey(normalizedPayload, normalizedMessageId),
            ) ||
            entries.containsKey(_payloadKey(normalizedPayload)))) {
      return true;
    }
    if (normalizedMessageId == null) {
      return entries.containsKey(_payloadKey(normalizedPayload));
    }
    return _hasRecentSidecarMarker(normalizedPayload, normalizedMessageId);
  }

  /// Non-destructively checks proof for exactly one message identity.
  ///
  /// This intentionally does not fall back to the legacy payload marker. A
  /// conversation-level marker cannot prove that a particular message was
  /// already presented, and must therefore never authorize durable adoption
  /// of a different message in the same chat.
  Future<bool> hasRecentExactAnnouncement({
    required String payload,
    required String messageId,
  }) async {
    final normalizedPayload = _normalizePayload(payload);
    final normalizedMessageId = _normalizePayload(messageId);
    if (normalizedPayload == null || normalizedMessageId == null) {
      return false;
    }

    final entries = await _loadEntries();
    if (entries.containsKey(
      _messageKey(normalizedPayload, normalizedMessageId),
    )) {
      return true;
    }
    return _hasRecentSidecarMarker(normalizedPayload, normalizedMessageId);
  }

  /// Consumes proof for exactly one message identity.
  ///
  /// Both the exact Dart-map key and its exact NSE sidecar are removed so the
  /// operation remains one-shot when both processes recorded the same remote
  /// presentation. Legacy payload-only proof is never read or modified.
  Future<bool> consumeIfRecentExactAnnouncement({
    required String payload,
    required String messageId,
  }) async {
    final normalizedPayload = _normalizePayload(payload);
    final normalizedMessageId = _normalizePayload(messageId);
    if (normalizedPayload == null || normalizedMessageId == null) {
      return false;
    }

    final entries = await _loadEntries();
    final timestamp = entries.remove(
      _messageKey(normalizedPayload, normalizedMessageId),
    );
    await _writeEntries(entries);
    final consumedSidecar = await _consumeSidecarMarker(
      normalizedPayload,
      normalizedMessageId,
    );
    return timestamp != null || consumedSidecar;
  }

  /// Copies one exact remote-presentation proof to a caller-proven canonical
  /// identity without deleting the source marker.
  ///
  /// This deliberately has no payload-only or same-conversation fallback: the
  /// caller must supply both sides of an alias mapping it has already proved.
  /// A failed target write is allowed to escape so durable owners retain their
  /// not-ready custody and can retry while the exact source proof still exists.
  Future<bool> promoteExactAnnouncementAlias({
    required String sourcePayload,
    required String sourceMessageId,
    required String targetPayload,
    required String targetMessageId,
  }) async {
    final normalizedSourcePayload = _normalizePayload(sourcePayload);
    final normalizedSourceMessageId = _normalizePayload(sourceMessageId);
    final normalizedTargetPayload = _normalizePayload(targetPayload);
    final normalizedTargetMessageId = _normalizePayload(targetMessageId);
    if (normalizedSourcePayload == null ||
        normalizedSourceMessageId == null ||
        normalizedTargetPayload == null ||
        normalizedTargetMessageId == null) {
      return false;
    }

    final entries = await _loadEntries();
    final sourceKey = _messageKey(
      normalizedSourcePayload,
      normalizedSourceMessageId,
    );
    final targetKey = _messageKey(
      normalizedTargetPayload,
      normalizedTargetMessageId,
    );
    final sourceTimestamp =
        entries[sourceKey] ??
        await _recentSidecarTimestamp(
          normalizedSourcePayload,
          normalizedSourceMessageId,
        );
    if (sourceTimestamp == null) {
      return false;
    }
    if (sourceKey == targetKey || entries.containsKey(targetKey)) {
      return true;
    }

    await _writeEntriesAtomicallyOrThrow(<String, int>{
      ...entries,
      targetKey: sourceTimestamp,
    });
    return true;
  }

  Future<bool> consumeIfRecentAnnouncement({
    required String payload,
    String? messageId,
  }) async {
    final normalizedPayload = _normalizePayload(payload);
    if (normalizedPayload == null) {
      return false;
    }

    final entries = await _loadEntries();
    final normalizedMessageId = _normalizePayload(messageId);
    int? timestamp;
    if (normalizedMessageId != null) {
      timestamp = entries.remove(
        _messageKey(normalizedPayload, normalizedMessageId),
      );
      if (timestamp != null) {
        entries.remove(_payloadKey(normalizedPayload));
      }
    }
    timestamp ??= entries.remove(_payloadKey(normalizedPayload));
    await _writeEntries(entries);
    if (timestamp != null) {
      return true;
    }
    // 04-P0 / SI-5: the Dart map missed — fall back to the NSE's cross-process
    // sidecar marker (shared app-group container on iOS) so a banner the
    // out-of-process NSE already showed still suppresses the duplicate Dart
    // banner, without depending on iOS having scheduled the Dart isolate.
    if (normalizedMessageId != null) {
      return _consumeSidecarMarker(normalizedPayload, normalizedMessageId);
    }
    return false;
  }

  Future<void> clear() async {
    try {
      final file = File(await _resolveFilePath());
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<Map<String, int>> _loadEntries() async {
    try {
      final file = File(await _resolveFilePath());
      if (!await file.exists()) {
        return <String, int>{};
      }

      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return <String, int>{};
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        // A corrupt-but-valid-JSON file (e.g. an array) is still a decode
        // failure — surface it rather than silently treating it as empty.
        _onLoadError(
          const FormatException(
            'recent-remote notification gate payload is not a JSON object',
          ),
          StackTrace.current,
        );
        return <String, int>{};
      }

      final entries = <String, int>{};
      for (final entry in decoded.entries) {
        final normalizedKey = _normalizeStoredKey(entry.key);
        final timestamp = _coerceTimestamp(entry.value);
        if (normalizedKey == null || timestamp == null) {
          continue;
        }
        final cutoff =
            _now().millisecondsSinceEpoch -
            _ttlForKey(normalizedKey).inMilliseconds;
        if (timestamp < cutoff) {
          continue;
        }
        entries[normalizedKey] = timestamp;
      }
      return entries;
    } catch (error, stack) {
      _onLoadError(error, stack);
      return <String, int>{};
    }
  }

  Future<void> _writeEntries(Map<String, int> entries) async {
    try {
      await _writeEntriesOrThrow(entries);
    } catch (_) {}
  }

  Future<void> _writeEntriesOrThrow(Map<String, int> entries) async {
    final file = File(await _resolveFilePath());
    if (entries.isEmpty) {
      if (await file.exists()) {
        await file.delete();
      }
      return;
    }

    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(entries), flush: true);
  }

  Future<void> _writeEntriesAtomicallyOrThrow(Map<String, int> entries) async {
    final file = File(await _resolveFilePath());
    await file.parent.create(recursive: true);
    final temporary = File(
      '${file.path}.alias-promotion-$pid-'
      '${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temporary.writeAsString(jsonEncode(entries), flush: true);
      await temporary.rename(file.path);
    } catch (_) {
      try {
        if (await temporary.exists()) {
          await temporary.delete();
        }
      } catch (_) {}
      rethrow;
    }
  }

  static String? _normalizePayload(String? payload) {
    final normalized = payload?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  static int? _coerceTimestamp(Object? rawValue) {
    if (rawValue is int) {
      return rawValue;
    }
    if (rawValue is num) {
      return rawValue.toInt();
    }
    if (rawValue is String) {
      return int.tryParse(rawValue);
    }
    return null;
  }

  Duration _ttlForKey(String key) {
    return key.startsWith(_messagePrefix) ? messageTtl : ttl;
  }

  static String _payloadKey(String payload) => '$_payloadPrefix$payload';

  static String _messageKey(String payload, String messageId) =>
      '$_messagePrefix$payload|$messageId';

  static String? _normalizeStoredKey(String? key) {
    final normalizedKey = _normalizePayload(key);
    if (normalizedKey == null) {
      return null;
    }
    if (normalizedKey.startsWith(_payloadPrefix) ||
        normalizedKey.startsWith(_messagePrefix)) {
      return normalizedKey;
    }
    return _payloadKey(normalizedKey);
  }
}

const _payloadPrefix = 'payload:';
const _messagePrefix = 'message:';
