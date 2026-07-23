import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter_app/core/debug/group_media_ios_disposable_profile.dart';
import 'package:flutter_app/core/notifications/app_group_path_channel.dart';
import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/notifications/recent_remote_gate_ios_wiring.dart';

typedef ActiveNotificationIdsResolver = Future<Iterable<Object?>> Function();
typedef NotificationIdCandidateGenerator =
    int Function(String normalizedConversationKey, int probe);

/// A private-safe failure to prove a unique local-notification id.
///
/// The exception deliberately retains only the failed operation and runtime
/// error type. Conversation keys and their hashed registry owners never cross
/// this boundary into telemetry or logs.
final class NotificationIdAllocationException implements Exception {
  const NotificationIdAllocationException({
    required this.operation,
    required this.errorType,
  });

  final String operation;
  final String errorType;

  @override
  String toString() =>
      'NotificationIdAllocationException(operation: $operation, '
      'errorType: $errorType)';
}

/// Persistent collision registry for conversation-scoped local notifications.
///
/// Each numeric `<id>.owner` filename is an irrevocably occupied slot. Valid
/// files contain only SHA-256 of the normalized conversation key. Malformed or
/// unreadable files remain occupied tombstones, which is safer than reusing an
/// id whose active OS card may still carry another conversation's tap payload.
///
/// Allocation is serialized in-isolate and with BSD `flock`, covering the main
/// Flutter isolate, Firebase headless isolates, and separate app processes.
final class DurableConversationNotificationIdRegistry {
  DurableConversationNotificationIdRegistry({
    required this.directory,
    this.maxProbeAttempts = 128,
    NotificationIdCandidateGenerator? candidateGenerator,
  }) : _candidateGenerator =
           candidateGenerator ?? _defaultNotificationIdCandidate;

  final Directory directory;
  final int maxProbeAttempts;
  final NotificationIdCandidateGenerator _candidateGenerator;

  static const directoryName = 'NotificationConversationIds';
  static const coordinationLockFileName = '.coordination.lock';
  static const ownerFileSuffix = '.owner';
  static const _opaqueActiveOwner = 'opaque-active';
  static const _maxNotificationId = 0x7fffffff;
  static final RegExp _ownerFilePattern = RegExp(r'^(\d+)\.owner$');
  static final Map<String, Future<void>> _isolateTails =
      <String, Future<void>>{};

  static Future<DurableConversationNotificationIdRegistry> openDefault({
    AppGroupPathChannel? appGroupPathChannel,
    Future<Directory> Function()? supportDirectory,
    bool? useIosAppGroup,
    String installedProfileId = const String.fromEnvironment(
      'SIMS_BUILD_PROFILE_ID',
    ),
  }) async {
    late final Directory root;
    final usesSharedAppGroup =
        installedProfileId != groupMediaIosDisposableBuildProfile &&
        (useIosAppGroup ?? Platform.isIOS);
    if (usesSharedAppGroup) {
      final appGroup = await resolveSharedNotificationAppGroupDirectory(
        channel: appGroupPathChannel,
        supportDirectory: supportDirectory,
      );
      if (appGroup == null) {
        throw StateError(
          'The shared notification App Group container is unavailable',
        );
      }
      root = appGroup;
    } else {
      root = await (supportDirectory ?? getApplicationSupportDirectory)();
    }
    return DurableConversationNotificationIdRegistry(
      directory: Directory(
        '${root.path}${Platform.pathSeparator}$directoryName',
      ),
    );
  }

  /// Opens the shared production namespace without letting host tests write to
  /// a developer machine's application-support directory.
  static Future<DurableConversationNotificationIdRegistry> openMobileDefault() {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      throw UnsupportedError(
        'Durable notification-id allocation is mobile-only',
      );
    }
    return openDefault(useIosAppGroup: Platform.isIOS);
  }

  /// Resolves one stable numeric id for [conversationKey].
  ///
  /// Existing mappings do not need an OS query. Before a new mapping is
  /// published, all valid active numeric ids that have no registry owner are
  /// persisted as opaque migration tombstones. Nonnumeric, negative, and
  /// out-of-range active identifiers are ignored.
  Future<int> resolve(
    String conversationKey, {
    required ActiveNotificationIdsResolver activeNotificationIds,
  }) async {
    final normalized = conversationKey.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        conversationKey,
        'conversationKey',
        'must not be empty',
      );
    }
    if (maxProbeAttempts <= 0) {
      throw ArgumentError.value(
        maxProbeAttempts,
        'maxProbeAttempts',
        'must be positive',
      );
    }

    try {
      await directory.create(recursive: true);
      final lock = File(
        '${directory.path}${Platform.pathSeparator}'
        '$coordinationLockFileName',
      );
      return await _serializeInIsolate(lock.path, () {
        return _NotificationIdFlock.withExclusive(lock, () async {
          final owner = sha256.convert(utf8.encode(normalized)).toString();
          final snapshot = await _readSnapshot(owner);
          final existingId = snapshot.ownerIds.isEmpty
              ? null
              : _preferredExistingId(normalized, snapshot.ownerIds);
          if (existingId != null) return existingId;

          late final Iterable<Object?> activeValues;
          try {
            activeValues = await activeNotificationIds();
          } catch (error) {
            throw NotificationIdAllocationException(
              operation: 'active_notification_query',
              errorType: error.runtimeType.toString(),
            );
          }

          for (final value in activeValues) {
            final activeId = _validNotificationId(value);
            if (activeId == null || snapshot.occupiedIds.contains(activeId)) {
              continue;
            }
            await _publishOwnerFile(activeId, _opaqueActiveOwner);
            snapshot.occupiedIds.add(activeId);
          }

          final attempted = <int>{};
          for (var probe = 0; probe < maxProbeAttempts; probe++) {
            final candidate = _candidateGenerator(normalized, probe);
            final validCandidate = _validNotificationId(candidate);
            if (validCandidate == null || !attempted.add(validCandidate)) {
              continue;
            }
            if (snapshot.occupiedIds.contains(validCandidate)) continue;
            await _publishOwnerFile(validCandidate, owner);
            return validCandidate;
          }
          throw const NotificationIdAllocationException(
            operation: 'candidate_exhausted',
            errorType: 'StateError',
          );
        });
      });
    } on NotificationIdAllocationException {
      rethrow;
    } catch (error) {
      throw NotificationIdAllocationException(
        operation: 'registry_storage',
        errorType: error.runtimeType.toString(),
      );
    }
  }

  Future<_RegistrySnapshot> _readSnapshot(String requestedOwner) async {
    final occupiedIds = <int>{};
    final ownerIds = <int>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final match = _ownerFilePattern.firstMatch(name);
      if (match == null) continue;
      final id = int.tryParse(match.group(1)!);
      final validId = _validNotificationId(id);
      if (validId == null) continue;
      occupiedIds.add(validId);
      try {
        if ((await entity.readAsString()).trim() == requestedOwner) {
          ownerIds.add(validId);
        }
      } on FileSystemException {
        // The numeric filename remains an occupied corruption tombstone.
      }
    }
    return _RegistrySnapshot(occupiedIds: occupiedIds, ownerIds: ownerIds);
  }

  int _preferredExistingId(String normalized, List<int> ownerIds) {
    final primary = deterministicConversationNotificationId(normalized);
    return ownerIds.contains(primary) ? primary : (ownerIds..sort()).first;
  }

  Future<void> _publishOwnerFile(int id, String owner) async {
    final target = File(
      '${directory.path}${Platform.pathSeparator}$id$ownerFileSuffix',
    );
    if (await target.exists()) return;

    final random = Random.secure();
    final token = List<int>.generate(12, (_) => random.nextInt(256));
    final suffix = base64UrlEncode(token).replaceAll('=', '');
    final temporary = File(
      '${directory.path}${Platform.pathSeparator}.$id-$suffix.tmp',
    );
    try {
      await temporary.writeAsString(owner, flush: true);
      // Publication is one atomic rename while the cross-process lock is held.
      // A crash before rename leaves only an ignored hidden temp file; a crash
      // after rename leaves a complete owner or opaque tombstone.
      if (!await target.exists()) {
        await temporary.rename(target.path);
      }
    } finally {
      try {
        if (await temporary.exists()) await temporary.delete();
      } on FileSystemException {
        // Hidden leftovers are ignored by snapshot parsing and can be retried.
      }
    }
  }

  Future<T> _serializeInIsolate<T>(
    String key,
    Future<T> Function() action,
  ) async {
    final previous = _isolateTails[key] ?? Future<void>.value();
    final release = Completer<void>();
    _isolateTails[key] = release.future;
    await previous;
    try {
      return await action();
    } finally {
      release.complete();
      if (identical(_isolateTails[key], release.future)) {
        _isolateTails.remove(key);
      }
    }
  }

  static int? _validNotificationId(Object? value) {
    if (value is! int || value < 0 || value > _maxNotificationId) return null;
    return value;
  }

  static int _defaultNotificationIdCandidate(
    String normalizedConversationKey,
    int probe,
  ) {
    if (probe == 0) {
      return deterministicConversationNotificationId(normalizedConversationKey);
    }
    final owner = sha256
        .convert(utf8.encode(normalizedConversationKey))
        .toString();
    final bytes = sha256
        .convert(utf8.encode('mknoon-notification-id-v1:$owner:$probe'))
        .bytes;
    return ByteData.sublistView(Uint8List.fromList(bytes)).getUint32(0) &
        _maxNotificationId;
  }
}

final class _RegistrySnapshot {
  const _RegistrySnapshot({required this.occupiedIds, required this.ownerIds});

  final Set<int> occupiedIds;
  final List<int> ownerIds;
}

typedef _OpenNative = Int32 Function(Pointer<Utf8>, Int32);
typedef _OpenDart = int Function(Pointer<Utf8>, int);
typedef _FlockNative = Int32 Function(Int32, Int32);
typedef _FlockDart = int Function(int, int);
typedef _CloseNative = Int32 Function(Int32);
typedef _CloseDart = int Function(int);

final class _NotificationIdFlock {
  static const int _openReadWrite = 2;
  static const int _lockExclusive = 2;
  static const int _lockUnlock = 8;
  static final _NotificationIdFlockApi _api = _NotificationIdFlockApi.load();

  static Future<T> withExclusive<T>(
    File file,
    Future<T> Function() action,
  ) async {
    await file.create(recursive: true);
    final nativePath = file.path.toNativeUtf8();
    late final int descriptor;
    try {
      descriptor = _api.open(nativePath, _openReadWrite);
    } finally {
      malloc.free(nativePath);
    }
    if (descriptor < 0) {
      throw FileSystemException('Unable to open notification-id lock');
    }
    if (_api.flock(descriptor, _lockExclusive) != 0) {
      _api.close(descriptor);
      throw FileSystemException('Unable to acquire notification-id lock');
    }
    try {
      return await action();
    } finally {
      _api.flock(descriptor, _lockUnlock);
      _api.close(descriptor);
    }
  }
}

final class _NotificationIdFlockApi {
  _NotificationIdFlockApi({
    required this.open,
    required this.flock,
    required this.close,
  });

  final _OpenDart open;
  final _FlockDart flock;
  final _CloseDart close;

  static _NotificationIdFlockApi load() {
    final process = DynamicLibrary.process();
    return _NotificationIdFlockApi(
      open: process.lookupFunction<_OpenNative, _OpenDart>('open'),
      flock: process.lookupFunction<_FlockNative, _FlockDart>('flock'),
      close: process.lookupFunction<_CloseNative, _CloseDart>('close'),
    );
  }
}
