import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter_app/core/notifications/app_group_path_channel.dart';
import 'package:flutter_app/core/notifications/recent_remote_gate_ios_wiring.dart';

/// A first-wins reservation for one logical message notification.
///
/// The reservation remains pending until [commit] records that the OS show call
/// succeeded. A failed producer must [release] it so one bounded contender
/// retry (or a later redelivery) can take ownership. Both mutations verify the
/// opaque [token], so a stale producer can never alter a newer reservation.
class DurableNotificationEventClaim {
  DurableNotificationEventClaim._({
    required DurableNotificationToneLease owner,
    required this.type,
    required this.eventIdentity,
    required this.token,
    required File file,
  }) : _owner = owner,
       _file = file;

  final DurableNotificationToneLease _owner;
  final File _file;
  final String type;
  final String eventIdentity;
  final String token;

  Future<bool> commit() => _owner._commitMessageClaim(this);

  Future<bool> release() => _owner._releaseMessageClaim(this);
}

/// A token-owned reservation for the next audible notification in one
/// conversation.
///
/// [commit] starts the durable tone window after the OS show call succeeds.
/// [release] removes the provisional lease after a failed show so a redelivery
/// can remain audible. Both operations are compare-and-set mutations: a stale
/// handle can never alter a newer reservation.
class DurableNotificationToneReservation {
  DurableNotificationToneReservation._({
    required DurableNotificationToneLease owner,
    required this.conversationKey,
    required this.token,
    required int reservedAtMs,
    required File leaseFile,
    required File pendingFile,
  }) : _owner = owner,
       _reservedAtMs = reservedAtMs,
       _leaseFile = leaseFile,
       _pendingFile = pendingFile;

  final DurableNotificationToneLease _owner;
  final File _leaseFile;
  final File _pendingFile;
  final int _reservedAtMs;
  final String conversationKey;
  final String token;

  Future<bool> commit() => _owner._commitToneReservation(this);

  Future<bool> release() => _owner._releaseToneReservation(this);
}

enum _MessageClaimAttemptState { claimed, pending, unavailable }

class _MessageClaimAttempt {
  const _MessageClaimAttempt._(this.state, this.claim);

  const _MessageClaimAttempt.claimed(DurableNotificationEventClaim claim)
    : this._(_MessageClaimAttemptState.claimed, claim);

  const _MessageClaimAttempt.pending()
    : this._(_MessageClaimAttemptState.pending, null);

  const _MessageClaimAttempt.unavailable()
    : this._(_MessageClaimAttemptState.unavailable, null);

  final _MessageClaimAttemptState state;
  final DurableNotificationEventClaim? claim;
}

class _MessageClaimRecord {
  const _MessageClaimRecord({required this.token, required this.createdAtMs});

  final String token;
  final int createdAtMs;
}

enum _ToneReservationAttemptState { reserved, pending, unavailable }

class _ToneReservationAttempt {
  const _ToneReservationAttempt._(this.state, this.reservation);

  const _ToneReservationAttempt.reserved(
    DurableNotificationToneReservation reservation,
  ) : this._(_ToneReservationAttemptState.reserved, reservation);

  const _ToneReservationAttempt.pending()
    : this._(_ToneReservationAttemptState.pending, null);

  const _ToneReservationAttempt.unavailable()
    : this._(_ToneReservationAttemptState.unavailable, null);

  final _ToneReservationAttemptState state;
  final DurableNotificationToneReservation? reservation;
}

class _ToneReservationRecord {
  const _ToneReservationRecord({
    required this.state,
    required this.token,
    required this.reservedAtMs,
    required this.createdAtMs,
    this.committedAtMs,
  });

  final String state;
  final String token;
  final int reservedAtMs;
  final int createdAtMs;
  final int? committedAtMs;
}

typedef NotificationClaimTokenFactory = String Function();
typedef ExclusiveNotificationClaimWriter =
    Future<void> Function(File file, String contents);
typedef PendingNotificationClaimDelay = Future<void> Function(Duration delay);

/// Redacted storage failure from exact notification ownership coordination.
///
/// Logical message/conversation identifiers and filesystem paths are omitted so
/// callers may safely emit this value in diagnostic telemetry.
final class DurableNotificationStorageException implements Exception {
  const DurableNotificationStorageException({
    required this.operation,
    required this.errorType,
  });

  final String operation;
  final String errorType;

  @override
  String toString() =>
      'DurableNotificationStorageException(operation: $operation, '
      'errorType: $errorType)';
}

/// Filesystem-backed notification coordination shared by the foreground and
/// Firebase background isolates. Event claims use exclusive file creation;
/// tone leases use a cross-isolate/cross-process `flock` below.
class DurableNotificationToneLease {
  DurableNotificationToneLease({
    required this.directory,
    DateTime Function()? now,
    this.toneWindow = const Duration(seconds: 30),
    this.eventTtl = const Duration(hours: 48),
    this.maxEventClaims = 256,
    this.maxToneLeases = 256,
    this.pendingClaimWait = const Duration(milliseconds: 250),
    this.pendingMessageClaimTtl = const Duration(seconds: 60),
    this.pendingToneReservationWait = const Duration(milliseconds: 250),
    this.pendingToneReservationTtl = const Duration(seconds: 60),
    NotificationClaimTokenFactory? claimTokenFactory,
    ExclusiveNotificationClaimWriter? exclusiveClaimWriter,
    PendingNotificationClaimDelay? pendingClaimDelay,
    this.beforeToneWrite,
  }) : now = now ?? DateTime.now,
       _claimTokenFactory = claimTokenFactory ?? _newClaimToken,
       _exclusiveClaimWriter =
           exclusiveClaimWriter ?? _writeExclusiveClaimContents,
       _pendingClaimDelay =
           pendingClaimDelay ?? ((delay) => Future<void>.delayed(delay));

  final Directory directory;
  final DateTime Function() now;
  final Duration toneWindow;
  final Duration eventTtl;
  final int maxEventClaims;
  final int maxToneLeases;
  final Duration pendingClaimWait;
  final Duration pendingMessageClaimTtl;
  final Duration pendingToneReservationWait;
  final Duration pendingToneReservationTtl;
  final NotificationClaimTokenFactory _claimTokenFactory;
  final ExclusiveNotificationClaimWriter _exclusiveClaimWriter;
  final PendingNotificationClaimDelay _pendingClaimDelay;

  /// Causal race-test hook before the provisional numeric lease is written.
  /// Production callers leave this null.
  final Future<void> Function()? beforeToneWrite;

  static const eventClaimsDirectoryName = 'NotificationServiceDedupe';
  static const toneLeasesDirectoryName = 'NotificationToneLeases';
  static const toneCoordinationLockFileName = '.coordination.lock';
  static const tonePendingReservationFileSuffix = '.pending-tone';
  static final Map<String, Future<void>> _eventIsolateTails =
      <String, Future<void>>{};
  static final Map<String, Future<void>> _toneIsolateTails =
      <String, Future<void>>{};

  static Future<DurableNotificationToneLease> openDefault({
    AppGroupPathChannel? appGroupPathChannel,
    Future<Directory> Function()? supportDirectory,
    bool? useIosAppGroup,
  }) async {
    if (useIosAppGroup ?? Platform.isIOS) {
      final appGroup = await resolveSharedNotificationAppGroupDirectory(
        channel: appGroupPathChannel,
        supportDirectory: supportDirectory,
      );
      if (appGroup == null) {
        throw StateError(
          'The shared notification App Group container is unavailable',
        );
      }
      return DurableNotificationToneLease(directory: appGroup);
    }

    final support =
        await (supportDirectory ?? getApplicationSupportDirectory)();
    return DurableNotificationToneLease(
      directory: Directory(
        '${support.path}${Platform.pathSeparator}ReactionNotificationClaims',
      ),
    );
  }

  /// Opens the production mobile namespace without making host tests write to
  /// a developer machine's application-support directory.
  static Future<DurableNotificationToneLease> openMobileDefault() {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      throw UnsupportedError('Durable notification ownership is mobile-only');
    }
    return openDefault(useIosAppGroup: Platform.isIOS);
  }

  /// Atomically claims a validated logical reaction event.
  Future<bool> claimEvent(String eventIdentity) async {
    final normalized = _normalize(eventIdentity, 'eventIdentity');
    final eventDir = Directory('${directory.path}/$eventClaimsDirectoryName');
    await eventDir.create(recursive: true);
    return _withEventCoordinationLock(() async {
      await _prune(eventDir, ttl: eventTtl, maxEntries: maxEventClaims);
      final file = File('${eventDir.path}/${eventClaimFileName(normalized)}');
      final won = await _createExclusive(file);
      if (won) {
        await _prune(
          eventDir,
          ttl: eventTtl,
          maxEntries: maxEventClaims,
          protecting: file,
        );
      }
      return won;
    });
  }

  /// Reserves one direct/group message event using the exact Swift NSE file
  /// contract: `<type>-<safe message id>` under `NotificationServiceDedupe`.
  ///
  /// If another producer currently owns a pending reservation, this waits once
  /// for a bounded interval and retries exactly once. A committed/legacy/NSE
  /// file is final and suppresses immediately.
  Future<DurableNotificationEventClaim?> claimMessageEvent({
    required String type,
    required String eventIdentity,
  }) async {
    final normalizedType = _normalize(type, 'type');
    final normalizedIdentity = _normalize(eventIdentity, 'eventIdentity');
    final first = await _attemptMessageClaim(
      type: normalizedType,
      eventIdentity: normalizedIdentity,
    );
    if (first.state == _MessageClaimAttemptState.claimed) {
      return first.claim;
    }
    if (first.state != _MessageClaimAttemptState.pending) {
      return null;
    }

    if (pendingClaimWait > Duration.zero) {
      await _pendingClaimDelay(pendingClaimWait);
    }
    final retry = await _attemptMessageClaim(
      type: normalizedType,
      eventIdentity: normalizedIdentity,
    );
    return retry.claim;
  }

  Future<_MessageClaimAttempt> _attemptMessageClaim({
    required String type,
    required String eventIdentity,
  }) async {
    final eventDir = Directory('${directory.path}/$eventClaimsDirectoryName');
    await eventDir.create(recursive: true);
    return _withEventCoordinationLock(() async {
      await _prune(eventDir, ttl: eventTtl, maxEntries: maxEventClaims);
      final file = File(
        '${eventDir.path}/${messageEventClaimFileName(type: type, eventIdentity: eventIdentity)}',
      );
      if (await file.exists()) {
        final existing = await _pendingMessageClaimRecord(file);
        if (existing == null) {
          return const _MessageClaimAttempt.unavailable();
        }
        final nowMs = now().toUtc().millisecondsSinceEpoch;
        if (!_messageClaimIsStale(existing, nowMs)) {
          return const _MessageClaimAttempt.pending();
        }
        try {
          // The event flock makes this an atomic compare/read/delete/replace
          // sequence for Dart producers. Only a parsed stale pending record is
          // reclaimed; committed, NSE, legacy, and malformed files survive.
          await file.delete();
        } catch (error, stackTrace) {
          Error.throwWithStackTrace(
            DurableNotificationStorageException(
              operation: 'stale_pending_claim_replace',
              errorType: error.runtimeType.toString(),
            ),
            stackTrace,
          );
        }
      }

      final token = _claimTokenFactory();
      final won = await _createExclusive(
        file,
        contents: jsonEncode(<String, Object>{
          'state': 'pending',
          'token': token,
          'createdAtMs': now().toUtc().millisecondsSinceEpoch,
        }),
      );
      if (!won) {
        return await _isPendingMessageClaim(file)
            ? const _MessageClaimAttempt.pending()
            : const _MessageClaimAttempt.unavailable();
      }

      await _prune(
        eventDir,
        ttl: eventTtl,
        maxEntries: maxEventClaims,
        protecting: file,
      );
      return _MessageClaimAttempt.claimed(
        DurableNotificationEventClaim._(
          owner: this,
          type: type,
          eventIdentity: eventIdentity,
          token: token,
          file: file,
        ),
      );
    });
  }

  Future<bool> _commitMessageClaim(DurableNotificationEventClaim claim) {
    return _mutateOwnedMessageClaim(
      claim,
      (file) => file.writeAsString(
        jsonEncode(<String, Object>{
          'state': 'committed',
          'committedAtMs': now().toUtc().millisecondsSinceEpoch,
        }),
        flush: true,
      ),
    );
  }

  Future<bool> _releaseMessageClaim(DurableNotificationEventClaim claim) {
    return _mutateOwnedMessageClaim(claim, (file) => file.delete());
  }

  Future<bool> _mutateOwnedMessageClaim(
    DurableNotificationEventClaim claim,
    Future<void> Function(File file) mutate,
  ) async {
    return _withEventCoordinationLock(() async {
      final file = claim._file;
      final pendingToken = await _pendingMessageClaimToken(file);
      if (pendingToken == null || pendingToken != claim.token) {
        return false;
      }
      try {
        await mutate(file);
        return true;
      } on FileSystemException {
        return false;
      }
    });
  }

  Future<T> _withEventCoordinationLock<T>(Future<T> Function() action) {
    final lock = File(
      '${directory.path}${Platform.pathSeparator}.$eventClaimsDirectoryName.lock',
    );
    return _serializeInIsolate(
      tails: _eventIsolateTails,
      key: lock.path,
      action: () => _PosixFlock.withExclusive(lock, action),
    );
  }

  Future<bool> _isPendingMessageClaim(File file) async =>
      await _pendingMessageClaimRecord(file) != null;

  Future<String?> _pendingMessageClaimToken(File file) async {
    return (await _pendingMessageClaimRecord(file))?.token;
  }

  Future<_MessageClaimRecord?> _pendingMessageClaimRecord(File file) async {
    try {
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['state'] != 'pending') return null;
      final token = decoded['token'];
      final createdAtMs = decoded['createdAtMs'];
      if (token is! String || createdAtMs is! int) return null;
      return _MessageClaimRecord(
        token: _normalize(token, 'token'),
        createdAtMs: createdAtMs,
      );
    } catch (_) {
      // Empty/legacy/NSE/malformed claim files are fail-closed committed claims.
      return null;
    }
  }

  bool _messageClaimIsStale(_MessageClaimRecord record, int nowMs) =>
      nowMs - record.createdAtMs >= pendingMessageClaimTtl.inMilliseconds;

  /// Reserves the audible right for a conversation without starting its tone
  /// window. Call [DurableNotificationToneReservation.commit] only after the OS
  /// notification show succeeds, or [DurableNotificationToneReservation.release]
  /// after failure.
  ///
  /// A numeric provisional lease remains visible to the Swift NSE and legacy
  /// Dart readers, while a hidden token sidecar provides compare-and-set
  /// ownership to new Dart producers.
  Future<DurableNotificationToneReservation?> reserveTone(
    String conversationKey,
  ) async {
    final normalized = _normalize(conversationKey, 'conversationKey');
    final toneDir = Directory('${directory.path}/$toneLeasesDirectoryName');
    final first = await _attemptToneReservation(toneDir, normalized);
    if (first.state == _ToneReservationAttemptState.reserved) {
      return first.reservation;
    }
    if (first.state != _ToneReservationAttemptState.pending) {
      return null;
    }

    if (pendingToneReservationWait > Duration.zero) {
      await Future<void>.delayed(pendingToneReservationWait);
    }
    final retry = await _attemptToneReservation(toneDir, normalized);
    return retry.reservation;
  }

  /// Backward-compatible one-step tone acquisition. New show paths should use
  /// [reserveTone] and commit only after the OS show succeeds.
  Future<bool> acquireTone(String conversationKey) async {
    final reservation = await reserveTone(conversationKey);
    if (reservation == null) return false;
    return reservation.commit();
  }

  Future<_ToneReservationAttempt> _attemptToneReservation(
    Directory toneDir,
    String normalized,
  ) async {
    return _withToneCoordinationLock(toneDir, () async {
      final file = File('${toneDir.path}/${_fileKey(normalized)}.lease');
      final pendingFile = File(
        '${toneDir.path}/.${_fileKey(normalized)}'
        '$tonePendingReservationFileSuffix',
      );
      final nowMs = now().toUtc().millisecondsSinceEpoch;
      await _prune(toneDir, ttl: eventTtl, maxEntries: maxToneLeases);

      if (await pendingFile.exists()) {
        final record = await _readToneReservationRecord(pendingFile);
        if (record == null) {
          // A malformed/orphaned sidecar has no token authority. Preserve any
          // numeric lease below, but do not let the sidecar block forever.
          await _deleteIfExists(pendingFile);
        } else if (record.state == 'committed') {
          await _repairCommittedToneReservation(
            file: file,
            pendingFile: pendingFile,
            record: record,
          );
        } else if (record.state == 'pending') {
          final leaseMatches = await _toneLeaseMatches(
            file,
            record.reservedAtMs,
          );
          if (!leaseMatches) {
            // Missing/mismatched provisional data means this sidecar is stale;
            // never delete a different numeric lease owned by another writer.
            await _deleteIfExists(pendingFile);
          } else if (!_toneReservationIsStale(record, nowMs)) {
            return const _ToneReservationAttempt.pending();
          } else {
            // The pending owner exceeded its bounded recovery TTL. Delete only
            // the exact provisional timestamp paired with that owner.
            await _deleteIfExists(file);
            await _deleteIfExists(pendingFile);
          }
        } else {
          await _deleteIfExists(pendingFile);
        }
      }

      if (await file.exists()) {
        final recordedAt = await _readToneTimestampMs(file);
        if (recordedAt != null &&
            nowMs - recordedAt < toneWindow.inMilliseconds) {
          return const _ToneReservationAttempt.unavailable();
        }
      }

      final hook = beforeToneWrite;
      if (hook != null) await hook();

      final token = _normalize(_claimTokenFactory(), 'token');
      await pendingFile.writeAsString(
        jsonEncode(<String, Object>{
          'state': 'pending',
          'token': token,
          'reservedAtMs': nowMs,
          'createdAtMs': nowMs,
        }),
        flush: true,
      );
      try {
        await _writeToneTimestamp(file, nowMs);
      } catch (_) {
        await _deleteIfExists(pendingFile);
        rethrow;
      }
      await _prune(toneDir, ttl: eventTtl, maxEntries: maxToneLeases);
      return _ToneReservationAttempt.reserved(
        DurableNotificationToneReservation._(
          owner: this,
          conversationKey: normalized,
          token: token,
          reservedAtMs: nowMs,
          leaseFile: file,
          pendingFile: pendingFile,
        ),
      );
    });
  }

  Future<bool> _commitToneReservation(
    DurableNotificationToneReservation reservation,
  ) {
    final toneDir = reservation._leaseFile.parent;
    return _withToneCoordinationLock(toneDir, () async {
      final record = await _readToneReservationRecord(reservation._pendingFile);
      if (!_toneReservationIsOwnedBy(record, reservation)) return false;
      if (!await _toneLeaseMatches(
        reservation._leaseFile,
        reservation._reservedAtMs,
      )) {
        return false;
      }

      final committedAtMs = now().toUtc().millisecondsSinceEpoch;
      // Mark committed first. If the process dies before the numeric rewrite,
      // a later producer repairs this fail-closed residue under the same lock.
      await reservation._pendingFile.writeAsString(
        jsonEncode(<String, Object>{
          'state': 'committed',
          'token': reservation.token,
          'reservedAtMs': reservation._reservedAtMs,
          'createdAtMs': record!.createdAtMs,
          'committedAtMs': committedAtMs,
        }),
        flush: true,
      );
      await _writeToneTimestamp(reservation._leaseFile, committedAtMs);
      await _deleteIfExists(reservation._pendingFile);
      await _prune(
        toneDir,
        ttl: eventTtl,
        maxEntries: maxToneLeases,
        protecting: reservation._leaseFile,
      );
      return true;
    });
  }

  Future<bool> _releaseToneReservation(
    DurableNotificationToneReservation reservation,
  ) {
    final toneDir = reservation._leaseFile.parent;
    return _withToneCoordinationLock(toneDir, () async {
      final record = await _readToneReservationRecord(reservation._pendingFile);
      if (!_toneReservationIsOwnedBy(record, reservation)) return false;

      final leaseMatches = await _toneLeaseMatches(
        reservation._leaseFile,
        reservation._reservedAtMs,
      );
      if (leaseMatches) {
        final leaseDeleted = await _deleteIfExists(reservation._leaseFile);
        final pendingDeleted = await _deleteIfExists(reservation._pendingFile);
        return leaseDeleted && pendingDeleted;
      }
      await _deleteIfExists(reservation._pendingFile);
      return false;
    });
  }

  bool _toneReservationIsOwnedBy(
    _ToneReservationRecord? record,
    DurableNotificationToneReservation reservation,
  ) =>
      record != null &&
      record.state == 'pending' &&
      record.token == reservation.token &&
      record.reservedAtMs == reservation._reservedAtMs;

  bool _toneReservationIsStale(_ToneReservationRecord record, int nowMs) =>
      nowMs - record.createdAtMs >= pendingToneReservationTtl.inMilliseconds;

  Future<_ToneReservationRecord?> _readToneReservationRecord(File file) async {
    try {
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final state = decoded['state'];
      final token = decoded['token'];
      final reservedAtMs = decoded['reservedAtMs'];
      final createdAtMs = decoded['createdAtMs'];
      final committedAtMs = decoded['committedAtMs'];
      if (state is! String ||
          token is! String ||
          token.trim().isEmpty ||
          reservedAtMs is! int ||
          createdAtMs is! int ||
          (committedAtMs != null && committedAtMs is! int)) {
        return null;
      }
      return _ToneReservationRecord(
        state: state,
        token: token.trim(),
        reservedAtMs: reservedAtMs,
        createdAtMs: createdAtMs,
        committedAtMs: committedAtMs as int?,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _repairCommittedToneReservation({
    required File file,
    required File pendingFile,
    required _ToneReservationRecord record,
  }) async {
    final committedAtMs = record.committedAtMs;
    if (committedAtMs == null) {
      await _deleteIfExists(pendingFile);
      return;
    }
    final recordedAtMs = await _readToneTimestampMs(file);
    if (recordedAtMs == null ||
        recordedAtMs == record.reservedAtMs ||
        recordedAtMs == committedAtMs) {
      await _writeToneTimestamp(file, committedAtMs);
    }
    await _deleteIfExists(pendingFile);
  }

  Future<bool> _toneLeaseMatches(File file, int expectedMs) async =>
      await _readToneTimestampMs(file) == expectedMs;

  Future<void> _writeToneTimestamp(File file, int timestampMs) =>
      file.writeAsString(
        (timestampMs / Duration.millisecondsPerSecond).toStringAsFixed(3),
        flush: true,
      );

  Future<bool> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) await file.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  Future<T> _withToneCoordinationLock<T>(
    Directory toneDir,
    Future<T> Function() action,
  ) async {
    await toneDir.create(recursive: true);
    final coordination = File('${toneDir.path}/$toneCoordinationLockFileName');
    return _serializeToneInIsolate(
      toneDir.path,
      () => _PosixFlock.withExclusive(coordination, action),
    );
  }

  Future<T> _serializeToneInIsolate<T>(
    String key,
    Future<T> Function() action,
  ) => _serializeInIsolate(tails: _toneIsolateTails, key: key, action: action);

  Future<T> _serializeInIsolate<T>({
    required Map<String, Future<void>> tails,
    required String key,
    required Future<T> Function() action,
  }) async {
    final previous = tails[key] ?? Future<void>.value();
    final release = Completer<void>();
    tails[key] = release.future;
    await previous;
    try {
      return await action();
    } finally {
      release.complete();
      if (identical(tails[key], release.future)) {
        tails.remove(key);
      }
    }
  }

  Future<bool> _createExclusive(File file, {String? contents}) async {
    try {
      await file.parent.create(recursive: true);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        DurableNotificationStorageException(
          operation: 'exclusive_claim_directory_create',
          errorType: error.runtimeType.toString(),
        ),
        stackTrace,
      );
    }

    try {
      await file.create(exclusive: true);
    } catch (error, stackTrace) {
      try {
        if (await file.exists()) return false;
      } catch (_) {
        // Fall through to the typed storage failure below.
      }
      Error.throwWithStackTrace(
        DurableNotificationStorageException(
          operation: 'exclusive_claim_create',
          errorType: error.runtimeType.toString(),
        ),
        stackTrace,
      );
    }

    try {
      await _exclusiveClaimWriter(
        file,
        contents ?? now().toUtc().millisecondsSinceEpoch.toString(),
      );
      return true;
    } catch (error, stackTrace) {
      // Exclusive creation succeeded in this attempt, so this is the only path
      // allowed to remove the file. The event flock remains held by the caller;
      // an existing owner's collision is never deleted here.
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Preserve the original typed write failure; a later storage recovery
        // can handle an undeletable filesystem residue.
      }
      Error.throwWithStackTrace(
        DurableNotificationStorageException(
          operation: 'exclusive_claim_write',
          errorType: error.runtimeType.toString(),
        ),
        stackTrace,
      );
    }
  }

  static Future<void> _writeExclusiveClaimContents(
    File file,
    String contents,
  ) => file.writeAsString(contents, flush: true);

  Future<void> _prune(
    Directory target, {
    required Duration ttl,
    required int maxEntries,
    File? protecting,
  }) async {
    await target.create(recursive: true);
    final cutoff = now().toUtc().millisecondsSinceEpoch - ttl.inMilliseconds;
    final fresh = <({File file, int timestamp})>[];
    await for (final entity in target.list()) {
      if (entity is! File) continue;
      if (protecting != null && entity.path == protecting.path) continue;
      if (entity.path.endsWith(
        '${Platform.pathSeparator}$toneCoordinationLockFileName',
      )) {
        continue;
      }
      final entityName = entity.uri.pathSegments.last;
      if (entityName.startsWith('.') &&
          entityName.endsWith(tonePendingReservationFileSuffix)) {
        continue;
      }
      try {
        if (entityName.endsWith('.lease')) {
          final identity = entityName.substring(0, entityName.length - 6);
          final pendingFile = File(
            '${target.path}/.$identity$tonePendingReservationFileSuffix',
          );
          // A live provisional lease is bounded by its own short recovery TTL,
          // not by capacity pruning intended for committed lease history.
          if (await pendingFile.exists()) continue;
        }
        final pendingMessageClaim = await _pendingMessageClaimRecord(entity);
        if (pendingMessageClaim != null) {
          if (_messageClaimIsStale(
            pendingMessageClaim,
            now().toUtc().millisecondsSinceEpoch,
          )) {
            await entity.delete();
          }
          // Fresh pending owners are outside committed-history capacity pruning;
          // stale ones were reclaimed by exact parsed state above.
          continue;
        }
        final timestamp =
            await _readTimestamp(entity) ??
            (await entity.lastModified()).toUtc().millisecondsSinceEpoch;
        if (timestamp < cutoff) {
          await entity.delete();
        } else {
          fresh.add((file: entity, timestamp: timestamp));
        }
      } on FileSystemException {
        // Concurrent create/delete is expected between isolates.
      }
    }
    fresh.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final retainedCapacity = max(0, maxEntries - (protecting == null ? 0 : 1));
    final overflow = fresh.length - retainedCapacity;
    if (overflow <= 0) return;
    for (final entry in fresh.take(overflow)) {
      try {
        await entry.file.delete();
      } on FileSystemException {
        // Best-effort bounded pruning; a later call retries.
      }
    }
  }

  Future<int?> _readTimestamp(File file) async {
    try {
      return int.tryParse((await file.readAsString()).trim());
    } catch (_) {
      // Swift/NSE and legacy claim files are allowed to be empty or otherwise
      // non-numeric. Even invalid external bytes must fall back to mtime so a
      // malformed existing owner stays fail-closed instead of aborting prune.
      return null;
    }
  }

  Future<int?> _readToneTimestampMs(File file) async {
    try {
      final value = double.tryParse((await file.readAsString()).trim());
      if (value == null) return null;
      // Swift stores TimeInterval seconds. Accept the prior Dart millisecond
      // representation during upgrade so an existing lease remains safe.
      return value >= 100000000000
          ? value.round()
          : (value * Duration.millisecondsPerSecond).round();
    } on FileSystemException {
      return null;
    }
  }

  static String eventClaimFileName(String eventIdentity) =>
      messageEventClaimFileName(
        type: 'message_reaction',
        eventIdentity: eventIdentity,
      );

  static String messageEventClaimFileName({
    required String type,
    required String eventIdentity,
  }) => '${_safeFileComponent(type)}-${_safeFileComponent(eventIdentity)}';

  static String _safeFileComponent(String value) {
    final buffer = StringBuffer();
    for (final codeUnit in value.codeUnits) {
      final isAsciiAlphaNumeric =
          (codeUnit >= 48 && codeUnit <= 57) ||
          (codeUnit >= 65 && codeUnit <= 90) ||
          (codeUnit >= 97 && codeUnit <= 122);
      buffer.writeCharCode(
        isAsciiAlphaNumeric || codeUnit == 45 || codeUnit == 95 ? codeUnit : 95,
      );
    }
    return buffer.toString();
  }

  String _fileKey(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  String _normalize(String value, String name) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, 'must not be empty');
    }
    return normalized;
  }

  static String _newClaimToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(18, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}

typedef _OpenNative = Int32 Function(Pointer<Utf8>, Int32);
typedef _OpenDart = int Function(Pointer<Utf8>, int);
typedef _FlockNative = Int32 Function(Int32, Int32);
typedef _FlockDart = int Function(int, int);
typedef _CloseNative = Int32 Function(Int32);
typedef _CloseDart = int Function(int);

/// `RandomAccessFile.lock` uses process-scoped POSIX record locks, so two Dart
/// isolates in the same Android process can both acquire it. BSD `flock`
/// instead coordinates independent open file descriptions in the same process
/// and across the app/NSE process boundary. Swift uses this exact lock file and
/// protocol.
final class _PosixFlock {
  static const int _openReadWrite = 2;
  static const int _lockExclusive = 2;
  static const int _lockUnlock = 8;
  static final _PosixFlockApi _api = _PosixFlockApi.load();

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
      throw FileSystemException(
        'Unable to open notification tone lock',
        file.path,
      );
    }
    if (_api.flock(descriptor, _lockExclusive) != 0) {
      _api.close(descriptor);
      throw FileSystemException(
        'Unable to acquire notification tone lock',
        file.path,
      );
    }
    try {
      return await action();
    } finally {
      _api.flock(descriptor, _lockUnlock);
      _api.close(descriptor);
    }
  }
}

final class _PosixFlockApi {
  _PosixFlockApi._(this.open, this.flock, this.close);

  final _OpenDart open;
  final _FlockDart flock;
  final _CloseDart close;

  factory _PosixFlockApi.load() {
    if (!(Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isLinux)) {
      throw UnsupportedError('Notification tone flock is unavailable');
    }
    final library = Platform.isAndroid
        ? DynamicLibrary.open('libc.so')
        : DynamicLibrary.process();
    return _PosixFlockApi._(
      library.lookupFunction<_OpenNative, _OpenDart>('open'),
      library.lookupFunction<_FlockNative, _FlockDart>('flock'),
      library.lookupFunction<_CloseNative, _CloseDart>('close'),
    );
  }
}
