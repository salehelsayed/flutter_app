import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter_app/core/debug/group_media_ios_disposable_profile.dart';
import 'package:flutter_app/core/notifications/app_group_path_channel.dart';
import 'package:flutter_app/core/notifications/app_visibility_authority.dart';
import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';
import 'package:flutter_app/core/notifications/bounded_posix_flock.dart';
import 'package:flutter_app/core/notifications/conversation_notification_content_kind.dart';
import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/notifications/durable_local_notification_effect_coordinator.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger_store.dart';
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
final class DurableConversationNotificationIdRegistry
    implements
        ConversationNotificationContentRegistry,
        DurableLocalNotificationEffectRegistry {
  DurableConversationNotificationIdRegistry({
    required this.directory,
    this.maxProbeAttempts = 128,
    NotificationIdCandidateGenerator? candidateGenerator,
    DurableLocalNotificationEffectCoordinator?
    localNotificationEffectCoordinator,
  }) : _candidateGenerator =
           candidateGenerator ?? _defaultNotificationIdCandidate,
       _localNotificationEffectCoordinator =
           localNotificationEffectCoordinator ??
           DurableLocalNotificationEffectCoordinator(
             ledgerStore: LocalNotificationLedgerStore(directory: directory),
           );

  final Directory directory;
  final int maxProbeAttempts;
  final NotificationIdCandidateGenerator _candidateGenerator;
  final DurableLocalNotificationEffectCoordinator
  _localNotificationEffectCoordinator;

  static const directoryName = 'NotificationConversationIds';
  static const coordinationLockFileName = '.coordination.lock';
  static const ownerFileSuffix = '.owner';
  static const contentKindFileSuffix = '.content-kind';
  static const contentActivationIntentFileSuffix = '.content-intent';
  static const _opaqueActiveOwner = 'opaque-active';
  static const _maxNotificationId = 0x7fffffff;
  static final RegExp _ownerFilePattern = RegExp(r'^(\d+)\.owner$');
  static final Map<String, Future<void>> _isolateTails =
      <String, Future<void>>{};
  static final Object _coordinationLockZoneKey = Object();

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
        return _withCoordinationLock(lock, () async {
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

  /// Returns an existing numeric id without creating storage or allocating a
  /// new owner.
  ///
  /// Cancellation uses this path so a read event can never occupy an id for a
  /// conversation that has no delivered card. Owner publication is atomic and
  /// immutable, so readers do not need to create/acquire the allocation lock.
  Future<int?> lookup(String conversationKey) async {
    final normalized = conversationKey.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        conversationKey,
        'conversationKey',
        'must not be empty',
      );
    }
    if (!await directory.exists()) return null;

    try {
      final owner = sha256.convert(utf8.encode(normalized)).toString();
      final snapshot = await _readSnapshot(owner);
      if (snapshot.ownerIds.isEmpty) return null;
      return _preferredExistingId(normalized, snapshot.ownerIds);
    } on FileSystemException catch (error) {
      // A concurrent support-directory teardown is equivalent to no mapping.
      if (!await directory.exists()) return null;
      throw NotificationIdAllocationException(
        operation: 'registry_lookup',
        errorType: error.runtimeType.toString(),
      );
    } on NotificationIdAllocationException {
      rethrow;
    } catch (error) {
      throw NotificationIdAllocationException(
        operation: 'registry_lookup',
        errorType: error.runtimeType.toString(),
      );
    }
  }

  @override
  Future<ConversationNotificationContentReplacementResult> replaceContent({
    required String conversationKey,
    required int notificationId,
    required ConversationNotificationContentMetadata metadata,
    required Future<void> Function() replace,
  }) async {
    final normalized = _normalizedConversationKey(conversationKey);
    final id = _requiredNotificationId(notificationId);
    await directory.create(recursive: true);
    final lock = _coordinationLockFile();
    return _serializeInIsolate(lock.path, () {
      return _withCoordinationLock(lock, () async {
        await _requireExactOwner(id, normalized);
        final current = await _readContentMetadataFile(id);
        if (_representsSameContentEvent(current, metadata)) {
          return ConversationNotificationContentReplacementResult
              .alreadyCurrent;
        }
        final prepared = await _prepareContentMetadataFile(id, metadata);
        try {
          // NotificationManager/UNUserNotificationCenter replace the existing
          // stable id in place. Publish first so a rejected or failed owner
          // cannot erase the only visible card. The registry lock keeps read,
          // reaction and tap CAS operations behind this native update.
          await replace();
          await _activatePreparedContentMetadataFile(id, prepared);
          return ConversationNotificationContentReplacementResult
              .shownAndRecorded;
        } finally {
          try {
            if (await prepared.exists()) await prepared.delete();
          } on FileSystemException {
            // Hidden prepared files are ignored and can be retried.
          }
        }
      });
    });
  }

  @override
  Future<bool> replaceContentIfGeneration({
    required String conversationKey,
    required int notificationId,
    required String expectedGeneration,
    required ConversationNotificationContentMetadata metadata,
    required Future<void> Function() replace,
  }) async {
    final normalized = _normalizedConversationKey(conversationKey);
    final generation = expectedGeneration.trim();
    if (generation.isEmpty) {
      throw ArgumentError.value(
        expectedGeneration,
        'expectedGeneration',
        'must not be empty',
      );
    }
    final id = _requiredNotificationId(notificationId);
    if (!await directory.exists()) return false;
    if (!await _hasExactOwner(id, normalized)) return false;
    final snapshot = await _readContentMetadataFile(id);
    if (snapshot?.generation != generation) return false;
    final lock = _coordinationLockFile();
    return _serializeInIsolate(lock.path, () {
      return _withCoordinationLock(lock, () async {
        if (!await _hasExactOwner(id, normalized)) return false;
        if (await _readContentMetadataFile(id) != snapshot) return false;
        final prepared = await _prepareContentMetadataFile(id, metadata);
        try {
          await replace();
          await _activatePreparedContentMetadataFile(id, prepared);
          return true;
        } finally {
          try {
            if (await prepared.exists()) await prepared.delete();
          } on FileSystemException {
            // Hidden prepared files are ignored and can be retried.
          }
        }
      });
    });
  }

  @override
  Future<bool> cancelContentIfKind({
    required String conversationKey,
    required int notificationId,
    required ConversationNotificationContentKind kind,
    ConversationNotificationContentCancellationPredicate? shouldCancel,
    required Future<void> Function() cancel,
  }) async {
    final normalized = _normalizedConversationKey(conversationKey);
    final id = _requiredNotificationId(notificationId);
    if (!await directory.exists()) return false;
    if (!await _hasExactOwner(id, normalized)) return false;
    final snapshot = await _readContentMetadataFile(id);
    if (snapshot?.kind != kind) return false;
    if (shouldCancel != null && !await shouldCancel(snapshot!)) {
      return false;
    }
    final lock = _coordinationLockFile();
    return _serializeInIsolate(lock.path, () {
      return _withCoordinationLock(lock, () async {
        if (!await _hasExactOwner(id, normalized)) return false;
        // The database/read-eligibility query above deliberately runs outside
        // flock. Compare the full generation-bearing snapshot here to close
        // message-to-message ABA races without creating a cross-store lock
        // ordering dependency.
        if (await _readContentMetadataFile(id) != snapshot) return false;
        await cancel();
        await _deleteContentKindFile(id);
        return true;
      });
    });
  }

  @override
  Future<bool> cancelContentIfGeneration({
    required String conversationKey,
    required int notificationId,
    required String generation,
    required Future<void> Function() cancel,
  }) async {
    final normalized = _normalizedConversationKey(conversationKey);
    final expectedGeneration = generation.trim();
    if (expectedGeneration.isEmpty) {
      throw ArgumentError.value(generation, 'generation', 'must not be empty');
    }
    final id = _requiredNotificationId(notificationId);
    if (!await directory.exists()) return false;
    if (!await _hasExactOwner(id, normalized)) return false;
    final snapshot = await _readContentMetadataFile(id);
    if (snapshot?.generation != expectedGeneration) return false;
    final lock = _coordinationLockFile();
    return _serializeInIsolate(lock.path, () {
      return _withCoordinationLock(lock, () async {
        if (!await _hasExactOwner(id, normalized)) return false;
        if (await _readContentMetadataFile(id) != snapshot) return false;
        await cancel();
        await _deleteContentKindFile(id);
        return true;
      });
    });
  }

  @override
  Future<void> recordContentMetadata({
    required String conversationKey,
    required int notificationId,
    required ConversationNotificationContentMetadata metadata,
  }) async {
    final normalized = _normalizedConversationKey(conversationKey);
    final id = _requiredNotificationId(notificationId);
    await directory.create(recursive: true);
    final lock = _coordinationLockFile();
    await _serializeInIsolate(lock.path, () {
      return _withCoordinationLock(lock, () async {
        await _requireExactOwner(id, normalized);
        await _publishContentMetadataFile(id, metadata);
      });
    });
  }

  @override
  Future<void> recordContentKind({
    required String conversationKey,
    required int notificationId,
    required ConversationNotificationContentKind kind,
  }) async {
    final normalized = _normalizedConversationKey(conversationKey);
    final id = _requiredNotificationId(notificationId);
    await directory.create(recursive: true);
    final lock = _coordinationLockFile();
    await _serializeInIsolate(lock.path, () {
      return _withCoordinationLock(lock, () async {
        await _requireExactOwner(id, normalized);
        await _publishContentMetadataFile(
          id,
          ConversationNotificationContentMetadata(kind: kind),
        );
      });
    });
  }

  @override
  Future<ConversationNotificationContentMetadata?> lookupContentMetadata({
    required String conversationKey,
    required int notificationId,
  }) async {
    final normalized = _normalizedConversationKey(conversationKey);
    final id = _requiredNotificationId(notificationId);
    if (!await directory.exists()) return null;
    if (!await _hasExactOwner(id, normalized)) return null;
    return _readContentMetadataFile(id);
  }

  @override
  Future<ConversationNotificationContentKind?> lookupContentKind({
    required String conversationKey,
    required int notificationId,
  }) async {
    final normalized = _normalizedConversationKey(conversationKey);
    final id = _requiredNotificationId(notificationId);
    if (!await directory.exists()) return null;
    if (!await _hasExactOwner(id, normalized)) return null;
    return (await _readContentMetadataFile(id))?.kind;
  }

  @override
  Future<void> clearContentKind({
    required String conversationKey,
    required int notificationId,
  }) async {
    final normalized = _normalizedConversationKey(conversationKey);
    final id = _requiredNotificationId(notificationId);
    if (!await directory.exists()) return;
    final lock = _coordinationLockFile();
    await _serializeInIsolate(lock.path, () {
      return _withCoordinationLock(lock, () async {
        if (!await _hasExactOwner(id, normalized)) return;
        await _deleteContentKindFile(id);
      });
    });
  }

  @override
  Future<DurableLocalNotificationEffectResult> runFinalEffect({
    required DurableLocalNotificationEffectContext context,
    required AppVisibilitySuppressionReader appVisibility,
    required AppVisibilityConversationIdentity conversationIdentity,
    required String conversationKey,
    required int notificationId,
    required ConversationNotificationContentMetadata metadata,
    required Future<void> Function() retireCurrent,
    required Future<void> Function() publishNative,
    Future<void> Function()? publishNativeSilently,
    PublishDurableLocalNotificationAtFinalBarrier? publishNativeAtFinalBarrier,
    ResolveDurableLocalNotificationActiveIds? activeNotificationIds,
  }) async {
    final normalized = _normalizedConversationKey(conversationKey);
    final id = _requiredNotificationId(notificationId);
    await directory.create(recursive: true);
    final lock = _coordinationLockFile();
    return _serializeInIsolate(lock.path, () {
      return _withCoordinationLock(lock, () async {
        await _requireExactOwner(id, normalized);
        File? prepared;
        try {
          final result = await _localNotificationEffectCoordinator.runLockHeld(
            context: context,
            appVisibility: appVisibility,
            conversationIdentity: conversationIdentity,
            notificationId: id,
            metadata: metadata,
            prepareContent: () async {
              await _ensureContentActivationIntent(
                id,
                metadata,
                context.currentOpaqueBinding,
              );
              prepared = await _prepareContentMetadataFile(id, metadata);
            },
            retireCurrent: retireCurrent,
            ensureContentActivated: () => _activateContentFromIntent(
              id: id,
              metadata: metadata,
              currentOpaqueBinding: context.currentOpaqueBinding,
              prepared: prepared,
            ),
            hasContentActivationIntent: () async {
              final intent = await _readContentActivationIntent(id);
              return intent != null &&
                  intent.opaqueBinding == context.currentOpaqueBinding &&
                  intent.matchesNext(metadata) &&
                  _contentActivationMetadataDigest(
                        await _readContentMetadataFile(id),
                      ) ==
                      intent.previousDigest;
            },
            completeContentActivation: () => _deleteContentActivationIntent(id),
            exactContentIsCurrent: () async =>
                await _readContentMetadataFile(id) == metadata,
            clearActivatedContent: () => _deleteContentKindFile(id),
            publishNative: publishNative,
            publishNativeSilently: publishNativeSilently,
            publishNativeAtFinalBarrier: publishNativeAtFinalBarrier,
            activeNotificationIds: activeNotificationIds,
          );
          if (result.receipt != null) {
            await _deleteContentActivationIntent(id);
          }
          return result;
        } finally {
          final exactPrepared = prepared;
          if (exactPrepared != null) {
            try {
              if (await exactPrepared.exists()) await exactPrepared.delete();
            } on FileSystemException {
              // Hidden prepared files are ignored and can be retried.
            }
          }
        }
      });
    });
  }

  @override
  Future<LocalNotificationRecordV1?> settleSqlReadyEffect({
    required String currentOpaqueBinding,
    required String eventCorrelation,
    required int expectedRevision,
  }) async {
    if (!await directory.exists()) return null;
    final lock = _coordinationLockFile();
    return _serializeInIsolate(lock.path, () {
      return _withCoordinationLock(
        lock,
        () => _localNotificationEffectCoordinator.settleSqlReadyEffectLockHeld(
          currentOpaqueBinding: currentOpaqueBinding,
          eventCorrelation: eventCorrelation,
          expectedRevision: expectedRevision,
        ),
      );
    });
  }

  @override
  Future<LocalNotificationRecordV1?> lookupExactEffect({
    required String currentOpaqueBinding,
    required String eventCorrelation,
    required String conversationDigest,
    required int notificationId,
    required String contentGeneration,
  }) async {
    if (!await directory.exists()) return null;
    final lock = _coordinationLockFile();
    return _serializeInIsolate(lock.path, () {
      return _withCoordinationLock(
        lock,
        () => _localNotificationEffectCoordinator.lookupExactEffectLockHeld(
          currentOpaqueBinding: currentOpaqueBinding,
          eventCorrelation: eventCorrelation,
          conversationDigest: conversationDigest,
          notificationId: notificationId,
          contentGeneration: contentGeneration,
        ),
      );
    });
  }

  @override
  Future<List<LocalNotificationRecordV1>> listSqlReadyEffectTerminals({
    required String currentOpaqueBinding,
  }) async {
    if (!await directory.exists()) {
      throw const NotificationIdAllocationException(
        operation: 'ledger_terminal_list',
        errorType: 'StateError',
      );
    }
    final lock = _coordinationLockFile();
    return _serializeInIsolate(lock.path, () {
      return _withCoordinationLock(
        lock,
        () => _localNotificationEffectCoordinator
            .listSqlReadyEffectTerminalsLockHeld(
              currentOpaqueBinding: currentOpaqueBinding,
            ),
      );
    });
  }

  @override
  Future<LocalNotificationRecordV1?> upgradeRelayCustodyToSqlReady({
    required String currentOpaqueBinding,
    required String eventCorrelation,
    required int expectedRevision,
  }) async {
    if (!await directory.exists()) return null;
    final lock = _coordinationLockFile();
    return _serializeInIsolate(lock.path, () {
      return _withCoordinationLock(
        lock,
        () => _localNotificationEffectCoordinator
            .upgradeRelayCustodyToSqlReadyLockHeld(
              currentOpaqueBinding: currentOpaqueBinding,
              eventCorrelation: eventCorrelation,
              expectedRevision: expectedRevision,
            ),
      );
    });
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

  String _normalizedConversationKey(String conversationKey) {
    final normalized = conversationKey.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        conversationKey,
        'conversationKey',
        'must not be empty',
      );
    }
    return normalized;
  }

  int _requiredNotificationId(int notificationId) {
    final valid = _validNotificationId(notificationId);
    if (valid == null) {
      throw ArgumentError.value(
        notificationId,
        'notificationId',
        'must be a non-negative signed 32-bit integer',
      );
    }
    return valid;
  }

  File _contentKindFile(int id) => File(
    '${directory.path}${Platform.pathSeparator}$id$contentKindFileSuffix',
  );

  File _contentActivationIntentFile(int id) => File(
    '${directory.path}${Platform.pathSeparator}$id'
    '$contentActivationIntentFileSuffix',
  );

  File _coordinationLockFile() => File(
    '${directory.path}${Platform.pathSeparator}$coordinationLockFileName',
  );

  Future<ConversationNotificationContentMetadata?> _readContentMetadataFile(
    int id,
  ) async {
    final file = _contentKindFile(id);
    try {
      if (!await file.exists()) return null;
      final encoded = (await file.readAsString()).trim();
      try {
        final decoded = ConversationNotificationContentMetadata.fromJson(
          jsonDecode(encoded),
        );
        if (decoded != null) return decoded;
      } on FormatException {
        // Fall through to the legacy single-enum parser below.
      }
      for (final kind in ConversationNotificationContentKind.values) {
        if (kind.name == encoded) {
          return ConversationNotificationContentMetadata(kind: kind);
        }
      }
      return null;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _deleteContentKindFile(int id) async {
    final file = _contentKindFile(id);
    if (await file.exists()) {
      await file.delete();
      BoundedPosixFlock.syncDirectory(directory);
    }
  }

  Future<_ContentActivationIntent?> _readContentActivationIntent(int id) async {
    final file = _contentActivationIntentFile(id);
    try {
      if (!await file.exists()) return null;
      return _ContentActivationIntent.tryFromJson(
        jsonDecode(await file.readAsString()),
      );
    } on Object {
      return null;
    }
  }

  Future<void> _ensureContentActivationIntent(
    int id,
    ConversationNotificationContentMetadata metadata,
    String currentOpaqueBinding,
  ) async {
    final existingFile = _contentActivationIntentFile(id);
    if (await existingFile.exists()) {
      final existing = await _readContentActivationIntent(id);
      if (existing != null &&
          existing.opaqueBinding == currentOpaqueBinding &&
          existing.matchesNext(metadata)) {
        return;
      }
      // The caller already owns the registry lock and the current binding's
      // ledger has granted this exact CLAIMED owner. A mismatched sidecar is
      // therefore stale residue from a retired/rebound authority and may be
      // atomically replaced; it can never authorize an effect by itself.
    }
    final intent = _ContentActivationIntent(
      opaqueBinding: currentOpaqueBinding,
      previousDigest: _contentActivationMetadataDigest(
        await _readContentMetadataFile(id),
      ),
      nextDigest: _contentActivationMetadataDigest(metadata)!,
    );
    final temporary = File(
      '${directory.path}${Platform.pathSeparator}.$id-intent-'
      '${_randomFileSuffix()}.tmp',
    );
    try {
      await temporary.writeAsString(jsonEncode(intent.toJson()), flush: true);
      await temporary.rename(existingFile.path);
      BoundedPosixFlock.syncDirectory(directory);
    } finally {
      try {
        if (await temporary.exists()) await temporary.delete();
      } on FileSystemException {
        // Hidden complete intent files are never authoritative.
      }
    }
  }

  Future<bool> _activateContentFromIntent({
    required int id,
    required ConversationNotificationContentMetadata metadata,
    required String currentOpaqueBinding,
    File? prepared,
  }) async {
    final current = await _readContentMetadataFile(id);
    if (current == metadata) return true;
    final intent = await _readContentActivationIntent(id);
    if (intent == null ||
        intent.opaqueBinding != currentOpaqueBinding ||
        !intent.matchesNext(metadata)) {
      return false;
    }
    if (_contentActivationMetadataDigest(current) != intent.previousDigest) {
      return false;
    }

    final exactPrepared =
        prepared ?? await _prepareContentMetadataFile(id, metadata);
    try {
      await _activatePreparedContentMetadataFile(id, exactPrepared);
      return true;
    } finally {
      if (prepared == null) {
        try {
          if (await exactPrepared.exists()) await exactPrepared.delete();
        } on FileSystemException {
          // The durable intent remains available for another exact retry.
        }
      }
    }
  }

  bool _representsSameContentEvent(
    ConversationNotificationContentMetadata? current,
    ConversationNotificationContentMetadata next,
  ) {
    final currentEvent = current?.eventIdentity?.trim();
    final nextEvent = next.eventIdentity?.trim();
    return current != null &&
        current.kind == next.kind &&
        currentEvent != null &&
        currentEvent.isNotEmpty &&
        nextEvent != null &&
        nextEvent.isNotEmpty &&
        currentEvent == nextEvent;
  }

  Future<void> _deleteContentActivationIntent(int id) async {
    final file = _contentActivationIntentFile(id);
    if (!await file.exists()) return;
    await file.delete();
    BoundedPosixFlock.syncDirectory(directory);
  }

  Future<bool> _hasExactOwner(int id, String normalizedConversationKey) async {
    final ownerFile = File(
      '${directory.path}${Platform.pathSeparator}$id$ownerFileSuffix',
    );
    try {
      if (!await ownerFile.exists()) return false;
      final expectedOwner = sha256
          .convert(utf8.encode(normalizedConversationKey))
          .toString();
      return (await ownerFile.readAsString()).trim() == expectedOwner;
    } on FileSystemException {
      return false;
    }
  }

  Future<void> _requireExactOwner(
    int id,
    String normalizedConversationKey,
  ) async {
    if (await _hasExactOwner(id, normalizedConversationKey)) return;
    throw const NotificationIdAllocationException(
      operation: 'content_kind_owner',
      errorType: 'StateError',
    );
  }

  Future<void> _publishContentMetadataFile(
    int id,
    ConversationNotificationContentMetadata metadata,
  ) async {
    final prepared = await _prepareContentMetadataFile(id, metadata);
    try {
      await _activatePreparedContentMetadataFile(id, prepared);
    } finally {
      try {
        if (await prepared.exists()) await prepared.delete();
      } on FileSystemException {
        // Hidden leftovers are ignored by content-metadata lookup.
      }
    }
  }

  Future<File> _prepareContentMetadataFile(
    int id,
    ConversationNotificationContentMetadata metadata,
  ) async {
    final target = _contentKindFile(id);
    final targetType = await FileSystemEntity.type(
      target.path,
      followLinks: false,
    );
    if (targetType != FileSystemEntityType.notFound &&
        targetType != FileSystemEntityType.file) {
      throw FileSystemException(
        'Notification content metadata target is not a file',
        target.path,
      );
    }
    final random = Random.secure();
    final token = List<int>.generate(12, (_) => random.nextInt(256));
    final suffix = base64UrlEncode(token).replaceAll('=', '');
    final temporary = File(
      '${directory.path}${Platform.pathSeparator}.$id-kind-$suffix.tmp',
    );
    try {
      await temporary.writeAsString(jsonEncode(metadata.toJson()), flush: true);
      return temporary;
    } catch (_) {
      try {
        if (await temporary.exists()) await temporary.delete();
      } on FileSystemException {
        // Hidden leftovers are ignored by content-metadata lookup.
      }
      rethrow;
    }
  }

  String _randomFileSuffix() {
    final random = Random.secure();
    final token = List<int>.generate(12, (_) => random.nextInt(256));
    return base64UrlEncode(token).replaceAll('=', '');
  }

  Future<void> _activatePreparedContentMetadataFile(
    int id,
    File prepared,
  ) async {
    final target = _contentKindFile(id);
    // POSIX rename replaces the old regular file atomically. Android/iOS and
    // this project's host test matrix are POSIX, so readers see old or new
    // metadata and never an absent delete/rename gap.
    await prepared.rename(target.path);
    BoundedPosixFlock.syncDirectory(directory);
  }

  Future<T> _serializeInIsolate<T>(
    String key,
    Future<T> Function() action,
  ) async {
    if (Zone.current[_coordinationLockZoneKey] == key) {
      throw const NotificationIdAllocationException(
        operation: 'registry_lock_reentrant',
        errorType: 'StateError',
      );
    }
    // BSD flock already coordinates distinct descriptors in one Android
    // process. Bypass the legacy Dart tail there so contenders observe the
    // same finite acquisition bound instead of waiting behind an unbounded
    // in-isolate action. Preserve the tail on iOS/macOS.
    if (defaultTargetPlatform == TargetPlatform.android) {
      return action();
    }
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

  Future<T> _withCoordinationLock<T>(File lock, Future<T> Function() action) {
    if (Zone.current[_coordinationLockZoneKey] == lock.path) {
      throw const NotificationIdAllocationException(
        operation: 'registry_lock_reentrant',
        errorType: 'StateError',
      );
    }
    return runZoned(
      () => _NotificationIdFlock.withExclusive(lock, action),
      zoneValues: <Object, Object>{_coordinationLockZoneKey: lock.path},
    );
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

final class _ContentActivationIntent {
  const _ContentActivationIntent({
    required this.opaqueBinding,
    required this.previousDigest,
    required this.nextDigest,
  });

  final String opaqueBinding;
  final String? previousDigest;
  final String nextDigest;

  bool matchesNext(ConversationNotificationContentMetadata metadata) =>
      _contentActivationMetadataDigest(metadata) == nextDigest;

  Map<String, Object?> toJson() => <String, Object?>{
    'v': 1,
    'opaqueBinding': opaqueBinding,
    'previousDigest': previousDigest,
    'nextDigest': nextDigest,
  };

  static _ContentActivationIntent? tryFromJson(Object? value) {
    if (value is! Map ||
        value.keys.any((key) => key is! String) ||
        value.keys.toSet().difference(const <Object>{
          'v',
          'opaqueBinding',
          'previousDigest',
          'nextDigest',
        }).isNotEmpty ||
        value.length != 4 ||
        value['v'] != 1 ||
        !isCanonicalLocalNotificationOpaqueBinding(value['opaqueBinding'])) {
      return null;
    }
    final previousDigest = value['previousDigest'];
    final nextDigest = value['nextDigest'];
    if ((previousDigest != null &&
            (previousDigest is! String ||
                !_contentActivationDigestPattern.hasMatch(previousDigest))) ||
        nextDigest is! String ||
        !_contentActivationDigestPattern.hasMatch(nextDigest)) {
      return null;
    }
    return _ContentActivationIntent(
      opaqueBinding: value['opaqueBinding']! as String,
      previousDigest: previousDigest as String?,
      nextDigest: nextDigest,
    );
  }
}

final RegExp _contentActivationDigestPattern = RegExp(r'^[0-9a-f]{64}$');

String? _contentActivationMetadataDigest(
  ConversationNotificationContentMetadata? metadata,
) {
  if (metadata == null) return null;
  final canonical = jsonEncode(metadata.toJson());
  return sha256
      .convert(
        utf8.encode('mknoon-content-activation-intent-v1\u0000$canonical'),
      )
      .toString();
}

final class _RegistrySnapshot {
  const _RegistrySnapshot({required this.occupiedIds, required this.ownerIds});

  final Set<int> occupiedIds;
  final List<int> ownerIds;
}

final class _NotificationIdFlock {
  static Future<T> withExclusive<T>(
    File file,
    Future<T> Function() action,
  ) async {
    try {
      return await BoundedPosixFlock.withExclusive(file, action);
    } on BoundedPosixFlockUnavailableException catch (error) {
      throw NotificationIdAllocationException(
        operation: 'registry_lock_unavailable',
        errorType: error.runtimeType.toString(),
      );
    }
  }
}
