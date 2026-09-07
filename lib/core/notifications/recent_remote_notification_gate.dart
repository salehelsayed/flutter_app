import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';

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
  final Lock _durableProofLock = Lock();
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

  // Native sidecars identify exact events and survive until their canonical
  // owner retires them. Recent compatibility checks must not delete pending
  // durable presentation proof merely because the app stayed closed.
  Future<String?>? _resolvedSidecarDirFuture;

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
  Future<bool> _consumeSidecarMarker(
    String payload,
    String messageId, {
    bool requireRecent = true,
  }) async {
    final dirPath = await _resolveSidecarDir();
    if (dirPath == null) {
      return false;
    }
    try {
      final file = File('$dirPath/${sidecarMarkerName(payload, messageId)}');
      if (!await file.exists()) {
        return false;
      }
      final ageMs =
          _now().millisecondsSinceEpoch -
          (await file.lastModified()).millisecondsSinceEpoch;
      if (requireRecent && ageMs > messageTtl.inMilliseconds) {
        return false;
      }
      await file.delete();
      return true;
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
    final timestamp = await _sidecarTimestamp(payload, messageId);
    if (timestamp == null ||
        _now().millisecondsSinceEpoch - timestamp > messageTtl.inMilliseconds) {
      return null;
    }
    return timestamp;
  }

  Future<int?> _sidecarTimestamp(String payload, String messageId) async {
    final dirPath = await _resolveSidecarDir();
    if (dirPath == null) {
      return null;
    }
    try {
      final file = File('$dirPath/${sidecarMarkerName(payload, messageId)}');
      if (!await file.exists()) {
        return null;
      }
      return (await file.lastModified()).millisecondsSinceEpoch;
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

  /// Reads exact native proof for an authenticated, canonically pending event.
  ///
  /// Only durable owners may use this age-independent path. The caller must
  /// validate the account, conversation and event against canonical custody,
  /// and retire the exact proof after durable settlement. Broad payload hints
  /// never establish this authority. Compatibility APIs retain their TTL.
  Future<bool> hasExactPendingAnnouncement({
    required String payload,
    required String messageId,
  }) async {
    final normalizedPayload = _normalizePayload(payload);
    final normalizedMessageId = _normalizePayload(messageId);
    if (normalizedPayload == null || normalizedMessageId == null) {
      return false;
    }
    final entries = await _loadEntries();
    return entries.containsKey(
          _messageKey(normalizedPayload, normalizedMessageId),
        ) ||
        await _sidecarTimestamp(normalizedPayload, normalizedMessageId) != null;
  }

  /// Retires only the exact proof whose canonical custody has settled.
  Future<bool> consumeExactPendingAnnouncement({
    required String payload,
    required String messageId,
  }) => _durableProofLock.synchronized(() async {
    final normalizedPayload = _normalizePayload(payload);
    final normalizedMessageId = _normalizePayload(messageId);
    if (normalizedPayload == null || normalizedMessageId == null) {
      return false;
    }
    final targetName = sidecarMarkerName(
      normalizedPayload,
      normalizedMessageId,
    );
    final aliases = await _aliasOrigins(targetName);
    final retiredNames = {targetName, ...aliases};
    final entries = await _loadEntries();
    final before = entries.length;
    entries.removeWhere(
      (key, _) =>
          retiredNames.contains(sha256.convert(utf8.encode(key)).toString()),
    );
    // Keep alias provenance until both storage representations have retired.
    // A failed deletion can then be retried by the canonically retired owner.
    await _writeEntriesOrThrow(entries);
    final directory = await _resolveSidecarDir();
    var consumedSidecar = false;
    if (_appGroupSidecarDirProvider != null && directory == null) {
      throw StateError('exact presentation proof directory is unavailable');
    }
    if (directory != null) {
      for (final name in retiredNames) {
        final marker = File('$directory/$name');
        if (await marker.exists()) {
          await marker.delete();
          consumedSidecar = true;
        }
      }
    }
    final aliasRoot = await _aliasRoot();
    for (final name in retiredNames) {
      final directory = Directory('${aliasRoot.path}/$name');
      if (await directory.exists()) await directory.delete(recursive: true);
    }
    return before != entries.length || consumedSidecar;
  });

  Future<Directory> _aliasRoot() async =>
      Directory('${await _resolveFilePath()}.aliases');

  Future<Set<String>> _aliasOrigins(String targetName) async {
    final root = await _aliasRoot();
    final origins = <String>{};
    final visited = <String>{};
    Future<void> visit(String name) async {
      if (!visited.add(name)) return;
      final directory = Directory('${root.path}/$name');
      if (!await directory.exists()) return;
      await for (final entry in directory.list(followLinks: false)) {
        final sourceName = entry.path.split(Platform.pathSeparator).last;
        if (entry is! File || !RegExp(r'^[a-f0-9]{64}$').hasMatch(sourceName)) {
          continue;
        }
        origins.add(sourceName);
        await visit(sourceName);
      }
    }

    await visit(targetName);
    origins.remove(targetName);
    return origins;
  }

  Future<void> _persistAliasOrigin(String sourceKey, String targetKey) async {
    final root = await _aliasRoot();
    final targetName = sha256.convert(utf8.encode(targetKey)).toString();
    final sourceName = sha256.convert(utf8.encode(sourceKey)).toString();
    final directory = Directory('${root.path}/$targetName');
    await directory.create(recursive: true);
    // One immutable, empty file per proven origin avoids lost updates when
    // separate gate instances promote different aliases to the same target.
    final origin = File('${directory.path}/$sourceName');
    await origin.writeAsString('', flush: true);
  }

  /// Consumes recent proof for exactly one message identity.
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
  }) => _durableProofLock.synchronized(() async {
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
        await _sidecarTimestamp(
          normalizedSourcePayload,
          normalizedSourceMessageId,
        );
    if (sourceTimestamp == null) {
      return false;
    }
    if (sourceKey == targetKey) {
      return true;
    }

    // Persist the origin before publishing target proof. If promotion or SQL
    // reconciliation is interrupted, a fresh gate can still retire both once
    // the canonical owner settles. The source remains usable until then.
    await _persistAliasOrigin(sourceKey, targetKey);
    await _persistExactSidecarAlias(
      normalizedTargetPayload,
      normalizedTargetMessageId,
      sourceTimestamp,
    );
    await _writeEntriesAtomicallyOrThrow(<String, int>{
      ...entries,
      targetKey: entries[targetKey] ?? sourceTimestamp,
    });
    return true;
  });

  Future<void> _persistExactSidecarAlias(
    String payload,
    String messageId,
    int timestamp,
  ) async {
    final directory = await _resolveSidecarDir();
    if (directory == null) return;
    final target = File('$directory/${sidecarMarkerName(payload, messageId)}');
    if (await target.exists()) return;
    await target.parent.create(recursive: true);
    final temporary = File(
      '$directory/.alias-$pid-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temporary.writeAsString('', flush: true);
      await temporary.setLastModified(
        DateTime.fromMillisecondsSinceEpoch(timestamp),
      );
      await temporary.rename(target.path);
    } catch (_) {
      try {
        if (await temporary.exists()) await temporary.delete();
      } catch (_) {}
      rethrow;
    }
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

  /// Reconciles retained proof with the canonical opaque account binding.
  /// An existing account's first upgrade preserves its pending native proof;
  /// subsequent account changes and no-account startup retire every old proof.
  /// Reset failures propagate so callers cannot publish a new account over
  /// stale proof. The companion binding makes retries survive process death.
  Future<void> rebindAccount(
    String? opaqueBinding,
  ) => _durableProofLock.synchronized(() async {
    final binding = opaqueBinding?.trim();
    if (binding != null && binding.isEmpty) {
      throw ArgumentError.value(opaqueBinding, 'opaqueBinding');
    }
    final path = await _resolveFilePath();
    final accountFile = File('$path.account');
    final hasPrevious = await accountFile.exists();
    String? previous;
    if (hasPrevious) {
      final decoded = jsonDecode(await accountFile.readAsString());
      if (decoded is! Map<String, dynamic> ||
          !decoded.containsKey('binding') ||
          (decoded['binding'] != null && decoded['binding'] is! String)) {
        throw const FormatException('invalid presentation proof account');
      }
      previous = decoded['binding'] as String?;
    }
    if (hasPrevious && previous == binding && binding != null) return;
    if (binding == null || (hasPrevious && previous != binding)) {
      final sidecarDirectory = await _resolveSidecarDir();
      if (_appGroupSidecarDirProvider != null && sidecarDirectory == null) {
        throw StateError('exact presentation proof directory is unavailable');
      }
      if (sidecarDirectory != null) {
        final directory = Directory(sidecarDirectory);
        if (await directory.exists()) await directory.delete(recursive: true);
      }
      final aliases = await _aliasRoot();
      if (await aliases.exists()) await aliases.delete(recursive: true);
      final entries = File(path);
      if (await entries.exists()) await entries.delete();
    }
    await accountFile.parent.create(recursive: true);
    final temporary = File(
      '$path.account-$pid-${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temporary.writeAsString(
        jsonEncode({'binding': binding}),
        flush: true,
      );
      await temporary.rename(accountFile.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  });

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
