import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/notifications/canonical_runtime_lease.dart';
import 'package:flutter_app/core/notifications/bounded_posix_flock.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/secure_storage/flutter_secure_key_store.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/push/application/push_envelope_staging.dart';

const pendingConversationNotificationOverlayDirectoryName =
    'PendingConversationNotificationOverlay';

typedef PendingConversationNotificationOverlayBindingResolver =
    Future<String?> Function();

/// Immediate account-cutover seam. Implementations must retire prior-account
/// projection content before accepting a different opaque binding.
abstract interface class PendingConversationNotificationOverlayBindingPublisher {
  Future<void> rebind(String? opaqueBinding);
}

/// One ordinary-message projection that is visible from an authenticated push
/// but has not necessarily materialized in the canonical encrypted database.
///
/// [line] must already be privacy-normalized. Reactions deliberately have no
/// corresponding type and therefore cannot increment the unread count.
final class PendingConversationNotificationMessage {
  const PendingConversationNotificationMessage({
    required this.eventId,
    required this.line,
    required this.occurredAtMicros,
  });

  final String eventId;
  final String line;
  final int occurredAtMicros;
}

/// Cross-isolate, account-fenced overlay for ordinary push messages that beat
/// canonical inbox persistence.
///
/// The empty filesystem lock contains no projection content. The complete
/// bounded overlay blob, including privacy-normalized lines, lives only in
/// [SecureKeyStore] (Android EncryptedSharedPreferences/Keystore or iOS
/// Keychain). Conversation and event identities are SHA-256 keyed inside that
/// encrypted blob.
final class PendingConversationNotificationOverlayStore
    implements PendingConversationNotificationOverlayBindingPublisher {
  PendingConversationNotificationOverlayStore({
    required this.directory,
    required PendingConversationNotificationOverlayBindingResolver
    resolveBinding,
    required SecureKeyStore secureStore,
    DateTime Function()? now,
    this.ttl = const Duration(hours: 48),
    this.maxEntries = 256,
  }) : _resolveBinding = resolveBinding,
       _secureStore = secureStore,
       _now = now ?? DateTime.now {
    if (ttl <= Duration.zero) {
      throw ArgumentError.value(ttl, 'ttl', 'must be positive');
    }
    if (maxEntries <= 0) {
      throw ArgumentError.value(maxEntries, 'maxEntries', 'must be positive');
    }
  }

  static const int formatVersion = 1;
  static const String secureStorageKey =
      'pending_conversation_notification_overlay_v1';
  static const String lockFileName = '.projection.lock';
  static const int maxPersistedLineCodeUnits = 1024;

  final Directory directory;
  final PendingConversationNotificationOverlayBindingResolver _resolveBinding;
  final SecureKeyStore _secureStore;
  final DateTime Function() _now;
  final Duration ttl;
  final int maxEntries;

  static Future<PendingConversationNotificationOverlayStore> openDefault({
    PendingConversationNotificationOverlayBindingResolver? resolveBinding,
    DateTime Function()? now,
    Duration ttl = const Duration(hours: 48),
    int maxEntries = 256,
  }) async {
    final staging = await resolvePushEnvelopeStagingDirectory();
    final secureStore = FlutterSecureKeyStore();
    return PendingConversationNotificationOverlayStore(
      directory: Directory(
        '${staging.parent.path}${Platform.pathSeparator}'
        '$pendingConversationNotificationOverlayDirectoryName',
      ),
      resolveBinding:
          resolveBinding ??
          () => secureStore.read(canonicalRuntimeAccountBindingStorageKey),
      secureStore: secureStore,
      now: now,
      ttl: ttl,
      maxEntries: maxEntries,
    );
  }

  /// Atomically unions canonical unread state with still-unmaterialized push
  /// messages. Supplying no [currentMessage] is the reaction/read-only path.
  Future<ConversationNotificationSnapshot?> project({
    required String conversationKey,
    required ConversationNotificationSnapshot? canonicalSnapshot,
    PendingConversationNotificationMessage? currentMessage,
  }) async {
    final normalizedConversationKey = conversationKey.trim();
    if (normalizedConversationKey.isEmpty) {
      throw ArgumentError.value(
        conversationKey,
        'conversationKey',
        'must not be blank',
      );
    }
    final normalizedCurrent = _normalizeCurrentMessage(currentMessage);

    final binding = await _safeResolveBinding();
    if (binding == null) {
      // Without account authority, never reuse or create a persistent overlay.
      await rebind(null);
      return canonicalSnapshot;
    }

    return _withLock(() async {
      var state = await _readState();
      if (state.binding != binding) {
        state = _OverlayState(binding: binding);
      }
      final nowMicros = _now().toUtc().microsecondsSinceEpoch;
      _prune(state, nowMicros);

      final conversationHash = _digest(normalizedConversationKey);
      final entries = state.conversations.putIfAbsent(
        conversationHash,
        () => <_OverlayEntry>[],
      );
      final canonicalEventHashes = canonicalSnapshot?.canonicalEventIds
          .map(_digest)
          .toSet();
      if (canonicalEventHashes != null && canonicalEventHashes.isNotEmpty) {
        entries.removeWhere(
          (entry) => canonicalEventHashes.contains(entry.eventHash),
        );
      }

      if (normalizedCurrent != null) {
        final eventHash = _digest(normalizedCurrent.eventId);
        if (!(canonicalEventHashes?.contains(eventHash) ?? false)) {
          final existingIndex = entries.indexWhere(
            (entry) => entry.eventHash == eventHash,
          );
          final entry = _OverlayEntry(
            eventHash: eventHash,
            line: normalizedCurrent.line,
            occurredAtMicros: normalizedCurrent.occurredAtMicros,
            expiresAtMicros: nowMicros + ttl.inMicroseconds,
          );
          if (existingIndex < 0) {
            entries.add(entry);
          } else {
            // Preserve the first authenticated ordering decision across a
            // duplicate transport delivery while refreshing expiry/copy.
            entries[existingIndex] = entry.copyWith(
              occurredAtMicros: entries[existingIndex].occurredAtMicros,
            );
          }
        }
      }

      if (entries.isEmpty) {
        state.conversations.remove(conversationHash);
      }
      _prune(state, nowMicros);
      await _writeState(state);
      return _combine(
        canonicalSnapshot,
        state.conversations[conversationHash] ?? const <_OverlayEntry>[],
      );
    });
  }

  /// Explicit materialization hook for canonical ingestion paths that do not
  /// otherwise rebuild the stable card immediately.
  Future<void> retireMaterialized({
    required String conversationKey,
    required Iterable<String> eventIds,
  }) async {
    final binding = await _safeResolveBinding();
    if (binding == null) {
      await rebind(null);
      return;
    }
    final normalizedConversationKey = conversationKey.trim();
    if (normalizedConversationKey.isEmpty) return;
    final eventHashes = eventIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .map(_digest)
        .toSet();
    if (eventHashes.isEmpty) return;

    await _withLock(() async {
      var state = await _readState();
      if (state.binding != binding) {
        state = _OverlayState(binding: binding);
      }
      final conversationHash = _digest(normalizedConversationKey);
      final entries = state.conversations[conversationHash];
      entries?.removeWhere((entry) => eventHashes.contains(entry.eventHash));
      if (entries?.isEmpty ?? false) {
        state.conversations.remove(conversationHash);
      }
      _prune(state, _now().toUtc().microsecondsSinceEpoch);
      await _writeState(state);
    });
  }

  @override
  Future<void> rebind(String? opaqueBinding) async {
    final normalized = _normalizeBinding(opaqueBinding);
    await _withLock(() async {
      final current = await _readState();
      if (normalized != null && current.binding == normalized) {
        _prune(current, _now().toUtc().microsecondsSinceEpoch);
        await _writeState(current);
        return;
      }
      if (normalized == null) {
        await _secureStore.delete(secureStorageKey);
        if (await _secureStore.read(secureStorageKey) != null) {
          throw StateError('pending notification overlay deletion failed');
        }
        return;
      }
      await _writeState(_OverlayState(binding: normalized));
    });
  }

  Future<String?> _safeResolveBinding() async {
    try {
      return _normalizeBinding(await _resolveBinding());
    } catch (_) {
      return null;
    }
  }

  PendingConversationNotificationMessage? _normalizeCurrentMessage(
    PendingConversationNotificationMessage? message,
  ) {
    if (message == null) return null;
    final eventId = message.eventId.trim();
    final line = message.line.trim();
    if (eventId.isEmpty ||
        line.isEmpty ||
        line.length > maxPersistedLineCodeUnits) {
      return null;
    }
    final order = message.occurredAtMicros > 0
        ? message.occurredAtMicros
        : _now().toUtc().microsecondsSinceEpoch;
    return PendingConversationNotificationMessage(
      eventId: eventId,
      line: line,
      occurredAtMicros: order,
    );
  }

  ConversationNotificationSnapshot? _combine(
    ConversationNotificationSnapshot? canonical,
    List<_OverlayEntry> pending,
  ) {
    if ((canonical?.totalUnreadMessageCount ?? 0) == 0 && pending.isEmpty) {
      return null;
    }

    final history = <ConversationNotificationHistoryEntry>[];
    final orderedCanonical = canonical?.orderedHistory;
    if (orderedCanonical != null && orderedCanonical.isNotEmpty) {
      history.addAll(orderedCanonical);
    } else {
      final lines = canonical?.historyLines ?? const <String>[];
      for (var index = 0; index < lines.length; index++) {
        history.add(
          ConversationNotificationHistoryEntry(
            eventId: 'canonical-line-$index',
            line: lines[index],
            occurredAtMicros: index - lines.length,
          ),
        );
      }
    }
    history.addAll(
      pending.map(
        (entry) => ConversationNotificationHistoryEntry(
          eventId: entry.eventHash,
          line: entry.line,
          occurredAtMicros: entry.occurredAtMicros,
        ),
      ),
    );
    history.sort((left, right) {
      final order = left.occurredAtMicros.compareTo(right.occurredAtMicros);
      return order != 0 ? order : left.eventId.compareTo(right.eventId);
    });
    final rendered = history
        .skip(history.length > 5 ? history.length - 5 : 0)
        .toList(growable: false);
    return ConversationNotificationSnapshot(
      historyLines: rendered.map((entry) => entry.line),
      totalUnreadMessageCount:
          (canonical?.totalUnreadMessageCount ?? 0) + pending.length,
      canonicalEventIds: canonical?.canonicalEventIds ?? const <String>{},
      orderedHistory: rendered,
    );
  }

  void _prune(_OverlayState state, int nowMicros) {
    for (final conversation in state.conversations.values) {
      conversation.removeWhere(
        (entry) =>
            entry.expiresAtMicros <= nowMicros ||
            entry.line.isEmpty ||
            entry.line.length > maxPersistedLineCodeUnits,
      );
    }
    state.conversations.removeWhere((_, entries) => entries.isEmpty);

    final all = <({String conversationHash, _OverlayEntry entry})>[];
    state.conversations.forEach((conversationHash, entries) {
      for (final entry in entries) {
        all.add((conversationHash: conversationHash, entry: entry));
      }
    });
    if (all.length <= maxEntries) return;
    all.sort((left, right) {
      final order = left.entry.occurredAtMicros.compareTo(
        right.entry.occurredAtMicros,
      );
      return order != 0
          ? order
          : left.entry.eventHash.compareTo(right.entry.eventHash);
    });
    for (final expired in all.take(all.length - maxEntries)) {
      state.conversations[expired.conversationHash]?.remove(expired.entry);
    }
    state.conversations.removeWhere((_, entries) => entries.isEmpty);
  }

  Future<_OverlayState> _readState() async {
    try {
      final encoded = await _secureStore.read(secureStorageKey);
      if (encoded == null || encoded.trim().isEmpty) {
        return _OverlayState(binding: null);
      }
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic> ||
          decoded['version'] != formatVersion) {
        throw const FormatException('unsupported overlay state');
      }
      final binding = _normalizeBinding(decoded['binding']?.toString());
      final conversationsJson = decoded['conversations'];
      if (binding == null || conversationsJson is! Map) {
        throw const FormatException('malformed overlay state');
      }
      final state = _OverlayState(binding: binding);
      for (final conversation in conversationsJson.entries) {
        final conversationHash = conversation.key.toString();
        if (!_isDigest(conversationHash) || conversation.value is! List) {
          continue;
        }
        final entries = <_OverlayEntry>[];
        for (final raw in conversation.value as List) {
          if (raw is! Map) continue;
          final eventHash = raw['eventHash']?.toString() ?? '';
          final line = raw['line']?.toString().trim() ?? '';
          final occurredAtMicros = raw['occurredAtMicros'];
          final expiresAtMicros = raw['expiresAtMicros'];
          if (!_isDigest(eventHash) ||
              line.isEmpty ||
              line.length > maxPersistedLineCodeUnits ||
              occurredAtMicros is! num ||
              expiresAtMicros is! num) {
            continue;
          }
          entries.add(
            _OverlayEntry(
              eventHash: eventHash,
              line: line,
              occurredAtMicros: occurredAtMicros.toInt(),
              expiresAtMicros: expiresAtMicros.toInt(),
            ),
          );
        }
        if (entries.isNotEmpty) {
          state.conversations[conversationHash] = entries;
        }
      }
      return state;
    } catch (_) {
      // Corrupt state is never authoritative and never blocks notification
      // delivery. The next write replaces it atomically for the current bind.
      return _OverlayState(binding: null);
    }
  }

  Future<void> _writeState(_OverlayState state) async {
    final binding = _normalizeBinding(state.binding);
    if (binding == null) {
      await _secureStore.delete(secureStorageKey);
      return;
    }
    final json = <String, Object?>{
      'version': formatVersion,
      'binding': binding,
      'conversations': <String, Object?>{
        for (final conversation in state.conversations.entries)
          conversation.key: conversation.value
              .map(
                (entry) => <String, Object?>{
                  'eventHash': entry.eventHash,
                  'line': entry.line,
                  'occurredAtMicros': entry.occurredAtMicros,
                  'expiresAtMicros': entry.expiresAtMicros,
                },
              )
              .toList(growable: false),
      },
    };
    final encoded = jsonEncode(json);
    await _secureStore.write(secureStorageKey, encoded);
    if (await _secureStore.read(secureStorageKey) != encoded) {
      throw StateError(
        'pending notification overlay write verification failed',
      );
    }
  }

  Future<T> _withLock<T>(Future<T> Function() action) async {
    await directory.create(recursive: true);
    if (defaultTargetPlatform == TargetPlatform.android) {
      return BoundedPosixFlock.withExclusive(_lockFile, action);
    }
    final lock = await _lockFile.open(mode: FileMode.append);
    await lock.lock(FileLock.exclusive);
    try {
      return await action();
    } finally {
      await lock.unlock();
      await lock.close();
    }
  }

  File get _lockFile =>
      File('${directory.path}${Platform.pathSeparator}$lockFileName');

  static String _digest(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  static bool _isDigest(String value) =>
      RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

  static String? _normalizeBinding(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}

final class _OverlayState {
  _OverlayState({required this.binding});

  final String? binding;
  final Map<String, List<_OverlayEntry>> conversations =
      <String, List<_OverlayEntry>>{};
}

final class _OverlayEntry {
  const _OverlayEntry({
    required this.eventHash,
    required this.line,
    required this.occurredAtMicros,
    required this.expiresAtMicros,
  });

  final String eventHash;
  final String line;
  final int occurredAtMicros;
  final int expiresAtMicros;

  _OverlayEntry copyWith({int? occurredAtMicros}) => _OverlayEntry(
    eventHash: eventHash,
    line: line,
    occurredAtMicros: occurredAtMicros ?? this.occurredAtMicros,
    expiresAtMicros: expiresAtMicros,
  );
}
