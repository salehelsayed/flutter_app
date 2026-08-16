import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter_app/core/debug/group_media_ios_disposable_profile.dart';
import 'package:flutter_app/core/notifications/app_group_path_channel.dart';
import 'package:flutter_app/core/notifications/bounded_posix_flock.dart';
import 'package:flutter_app/core/notifications/recent_remote_gate_ios_wiring.dart';

/// A first-wins reservation for one logical message notification.
///
/// The reservation remains pending until Android reaches the native show
/// boundary or [commit] records a known earlier/later success. A producer may
/// [release] only while it is still pending and therefore knows no native show
/// was attempted. Both mutations verify the opaque [token], so a stale
/// producer can never alter a newer reservation.
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

  /// Revalidates this exact provisional owner immediately before publication.
  /// A stale producer must never publish after another process reclaimed it.
  Future<bool> validateOwner() => _owner._validateMessageClaim(this);

  /// Moves the exact claim to a non-reclaimable publication state before the
  /// native call, then commits it after the callback returns successfully.
  ///
  /// A separate validate-then-publish sequence is unsafe because publication
  /// can wait beyond the provisional TTL. Once the callback is invoked, an
  /// error or process death leaves a fail-closed publication residue because
  /// the native side effect is unknowable; [release] will refuse that state.
  Future<DurableNotificationClaimedPublicationResult> publishAndCommit(
    Future<void> Function() publish,
  ) => _owner._publishAndCommitMessageClaim(this, publish);

  Future<bool> commit() => _owner._commitMessageClaim(this);

  Future<bool> release() => _owner._releaseMessageClaim(this);
}

/// Exact-event ownership outcome around one native publication attempt.
final class DurableNotificationClaimedPublicationResult {
  const DurableNotificationClaimedPublicationResult._({
    required this.published,
    required this.claimCommitted,
  });

  const DurableNotificationClaimedPublicationResult.ownershipLost()
    : this._(published: false, claimCommitted: false);

  const DurableNotificationClaimedPublicationResult.published({
    required bool claimCommitted,
  }) : this._(published: true, claimCommitted: claimCommitted);

  /// Whether the native publication callback completed successfully.
  final bool published;

  /// Whether the exact event was durably changed from pending to committed
  /// before its coordination lock was released.
  final bool claimCommitted;
}

/// Android reached the native notification publication boundary, but the
/// platform call did not return a trustworthy success result.
///
/// A method-channel error is not proof that `NotificationManager.notify` did
/// not run. Callers must therefore retain any `publishing` event/tone owners
/// fail-closed instead of releasing them for an audible redelivery.
final class DurableNotificationPublicationAttemptedException
    implements Exception {
  const DurableNotificationPublicationAttemptedException({
    required this.errorType,
  });

  final String errorType;

  @override
  String toString() =>
      'DurableNotificationPublicationAttemptedException('
      'errorType: $errorType)';
}

/// The final durable canonical/visibility barrier denied native entry after
/// provisional event/tone owners had been armed. Owners must roll back their
/// exact publishing residue because no platform callback was invoked.
final class DurableNotificationPublicationNotAuthorizedException
    implements Exception {
  const DurableNotificationPublicationNotAuthorizedException();
}

/// Typed ownership outcome for an exact notification event.
enum DurableNotificationClaimDisposition {
  /// This caller owns a new provisional claim and may attempt OS publication.
  acquired,

  /// Another producer owns a fresh pending claim or a fresh native publication
  /// attempt. Retry after its bounded window; this is not proof of display.
  pending,

  /// A committed, legacy, NSE, or malformed fail-closed owner exists.
  committedOrUnavailable,
}

final class DurableNotificationClaimAcquisition {
  const DurableNotificationClaimAcquisition._({
    required this.disposition,
    this.claim,
  });

  const DurableNotificationClaimAcquisition.acquired(
    DurableNotificationEventClaim claim,
  ) : this._(
        disposition: DurableNotificationClaimDisposition.acquired,
        claim: claim,
      );

  const DurableNotificationClaimAcquisition.pending()
    : this._(disposition: DurableNotificationClaimDisposition.pending);

  const DurableNotificationClaimAcquisition.committedOrUnavailable()
    : this._(
        disposition: DurableNotificationClaimDisposition.committedOrUnavailable,
      );

  final DurableNotificationClaimDisposition disposition;
  final DurableNotificationEventClaim? claim;
}

/// A token-owned reservation for the next audible notification in one
/// conversation.
///
/// [commit] starts the durable tone window after the OS show callback returns.
/// [release] removes only a still-pending reservation, before Android invokes
/// native show. Once publication is attempted, recovery converts the residue
/// into a silent window instead. Every mutation is compare-and-set: a stale
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

  /// Publishes audibly only while this exact token owns the tone lock, and
  /// commits the tone window before releasing that lock. If ownership was
  /// lost, [publishAudibly] is not entered and the caller must publish silently.
  Future<DurableNotificationTonePublicationResult> publishAndCommit(
    Future<void> Function() publishAudibly,
  ) => _owner._publishAndCommitToneReservation(this, publishAudibly);

  Future<bool> commit() => _owner._commitToneReservation(this);

  Future<bool> release() => _owner._releaseToneReservation(this);
}

/// Tone-owner outcome at the native publication boundary.
final class DurableNotificationTonePublicationResult {
  const DurableNotificationTonePublicationResult._({
    required this.publishedAudibly,
    required this.toneCommitted,
  });

  const DurableNotificationTonePublicationResult.ownershipLost()
    : this._(publishedAudibly: false, toneCommitted: false);

  const DurableNotificationTonePublicationResult.published({
    required bool toneCommitted,
  }) : this._(publishedAudibly: true, toneCommitted: toneCommitted);

  final bool publishedAudibly;
  final bool toneCommitted;
}

/// Result of finalizing owners after the native publication callback returns.
final class DurableShownNotificationOwnerCommitResult {
  const DurableShownNotificationOwnerCommitResult({
    required this.messageClaimCommitted,
    required this.toneReservationCommitted,
  });

  final bool messageClaimCommitted;
  final bool toneReservationCommitted;
}

/// Starts both independent post-show commits without letting one lock starve
/// the other. The exact event claim is launched first because it is the
/// authority that prevents a second card or alert for the same event.
Future<DurableShownNotificationOwnerCommitResult>
commitShownNotificationOwners({
  DurableNotificationEventClaim? messageClaim,
  DurableNotificationToneReservation? toneReservation,
}) async {
  final claimCommit = () async {
    if (messageClaim == null) return true;
    try {
      return await messageClaim.commit();
    } catch (_) {
      return false;
    }
  }();
  final toneCommit = () async {
    if (toneReservation == null) return true;
    try {
      return await toneReservation.commit();
    } catch (_) {
      return false;
    }
  }();
  final committed = await Future.wait<bool>(<Future<bool>>[
    claimCommit,
    toneCommit,
  ]);
  return DurableShownNotificationOwnerCommitResult(
    messageClaimCommitted: committed[0],
    toneReservationCommitted: committed[1],
  );
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
  const _MessageClaimRecord({
    required this.state,
    required this.token,
    required this.createdAtMs,
    this.publishingAtMs,
  });

  final String state;
  final String token;
  final int createdAtMs;
  final int? publishingAtMs;
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
    this.publishingAtMs,
    this.committedAtMs,
  });

  final String state;
  final String token;
  final int reservedAtMs;
  final int createdAtMs;
  final int? publishingAtMs;
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
    TargetPlatform? platform,
    this.beforeToneWrite,
  }) : now = now ?? DateTime.now,
       platform = platform ?? defaultTargetPlatform,
       _claimTokenFactory = claimTokenFactory ?? _newClaimToken,
       _exclusiveClaimWriter =
           exclusiveClaimWriter ?? _writeExclusiveClaimContents,
       _pendingClaimDelay =
           pendingClaimDelay ?? ((delay) => Future<void>.delayed(delay));

  final Directory directory;
  final DateTime Function() now;
  final TargetPlatform platform;
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
    String installedProfileId = const String.fromEnvironment(
      'SIMS_BUILD_PROFILE_ID',
    ),
  }) async {
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
    try {
      return await _withEventCoordinationLock(() async {
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
    } on BoundedPosixFlockUnavailableException {
      return false;
    }
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
    return (await acquireMessageEventClaim(
      type: type,
      eventIdentity: eventIdentity,
    )).claim;
  }

  /// Acquires an exact event claim without conflating a fresh contender with a
  /// terminal committed/NSE owner.
  Future<DurableNotificationClaimAcquisition> acquireMessageEventClaim({
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
      return DurableNotificationClaimAcquisition.acquired(first.claim!);
    }
    if (first.state != _MessageClaimAttemptState.pending) {
      return const DurableNotificationClaimAcquisition.committedOrUnavailable();
    }

    if (pendingClaimWait > Duration.zero) {
      await _pendingClaimDelay(pendingClaimWait);
    }
    final retry = await _attemptMessageClaim(
      type: normalizedType,
      eventIdentity: normalizedIdentity,
    );
    return switch (retry.state) {
      _MessageClaimAttemptState.claimed =>
        DurableNotificationClaimAcquisition.acquired(retry.claim!),
      _MessageClaimAttemptState.pending =>
        const DurableNotificationClaimAcquisition.pending(),
      _MessageClaimAttemptState.unavailable =>
        const DurableNotificationClaimAcquisition.committedOrUnavailable(),
    };
  }

  Future<_MessageClaimAttempt> _attemptMessageClaim({
    required String type,
    required String eventIdentity,
  }) async {
    final eventDir = Directory('${directory.path}/$eventClaimsDirectoryName');
    await eventDir.create(recursive: true);
    try {
      return await _withEventCoordinationLock(() async {
        await _prune(eventDir, ttl: eventTtl, maxEntries: maxEventClaims);
        final file = File(
          '${eventDir.path}/${messageEventClaimFileName(type: type, eventIdentity: eventIdentity)}',
        );
        if (await file.exists()) {
          final existing = await _ownedMessageClaimRecord(file);
          if (existing == null) {
            return const _MessageClaimAttempt.unavailable();
          }
          if (existing.state == 'publishing') {
            final nowMs = now().toUtc().millisecondsSinceEpoch;
            if (!_messagePublicationIsStale(existing, nowMs)) {
              return const _MessageClaimAttempt.pending();
            }
            // Once an Android native publication attempt has outlived the
            // recovery TTL its result is unknowable. Finalize it as terminal
            // instead of reclaiming it (duplicate risk) or leaving an
            // immortal retryable/capacity-exempt residue.
            await _finalizeUnknownMessagePublication(file, nowMs);
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
    } on BoundedPosixFlockUnavailableException {
      return const _MessageClaimAttempt.unavailable();
    }
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
      ownerCompletion: true,
    );
  }

  Future<bool> _validateMessageClaim(
    DurableNotificationEventClaim claim,
  ) async {
    try {
      return await _withEventCoordinationLock(() async {
        final record = await _pendingMessageClaimRecord(claim._file);
        return record != null && record.token == claim.token;
      });
    } on BoundedPosixFlockUnavailableException {
      return false;
    } on FileSystemException {
      return false;
    }
  }

  Future<DurableNotificationClaimedPublicationResult>
  _publishAndCommitMessageClaim(
    DurableNotificationEventClaim claim,
    Future<void> Function() publish,
  ) async {
    if (platform != TargetPlatform.android) {
      final stillOwned = await _validateMessageClaim(claim);
      if (!stillOwned) {
        return const DurableNotificationClaimedPublicationResult.ownershipLost();
      }
      await publish();
      return DurableNotificationClaimedPublicationResult.published(
        claimCommitted: await _commitMessageClaim(claim),
      );
    }

    final beganPublication = await _beginMessageClaimPublication(claim);
    if (!beganPublication) {
      return const DurableNotificationClaimedPublicationResult.ownershipLost();
    }

    try {
      await publish();
    } catch (error, stackTrace) {
      if (error is DurableNotificationPublicationNotAuthorizedException) {
        await _abortPublishedMessageClaim(claim);
        Error.throwWithStackTrace(error, stackTrace);
      }
      if (error is DurableNotificationPublicationAttemptedException) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      Error.throwWithStackTrace(
        DurableNotificationPublicationAttemptedException(
          errorType: error.runtimeType.toString(),
        ),
        stackTrace,
      );
    }
    // The publishing state is already non-reclaimable, so finalization may use
    // bounded acquisition. If another event owns the global coordination lock,
    // leave this exact residue fail-closed instead of retaining the callback.
    final committed = await _commitPublishedMessageClaim(claim);
    return DurableNotificationClaimedPublicationResult.published(
      claimCommitted: committed,
    );
  }

  Future<bool> _commitPublishedMessageClaim(
    DurableNotificationEventClaim claim,
  ) {
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

  Future<bool> _abortPublishedMessageClaim(
    DurableNotificationEventClaim claim,
  ) => _mutateOwnedMessageClaim(
    claim,
    (file) => file.delete(),
    allowedStates: const <String>{'publishing'},
  );

  Future<bool> _beginMessageClaimPublication(
    DurableNotificationEventClaim claim,
  ) async {
    try {
      return await _withEventCoordinationLock(() async {
        final record = await _ownedMessageClaimRecord(claim._file);
        if (record == null ||
            record.state != 'pending' ||
            record.token != claim.token) {
          return false;
        }
        try {
          await claim._file.writeAsString(
            jsonEncode(<String, Object>{
              'state': 'publishing',
              'token': claim.token,
              'createdAtMs': record.createdAtMs,
              'publishingAtMs': now().toUtc().millisecondsSinceEpoch,
            }),
            flush: true,
          );
          return true;
        } on FileSystemException {
          return false;
        }
      });
    } on BoundedPosixFlockUnavailableException {
      return false;
    }
  }

  Future<bool> _releaseMessageClaim(DurableNotificationEventClaim claim) {
    return _mutateOwnedMessageClaim(
      claim,
      (file) => file.delete(),
      allowedStates: const <String>{'pending'},
    );
  }

  Future<bool> _mutateOwnedMessageClaim(
    DurableNotificationEventClaim claim,
    Future<void> Function(File file) mutate, {
    bool ownerCompletion = false,
    Set<String>? allowedStates,
  }) async {
    Future<bool> mutateExactOwner() async {
      final file = claim._file;
      final record = await _ownedMessageClaimRecord(file);
      if (record == null ||
          record.token != claim.token ||
          (allowedStates != null && !allowedStates.contains(record.state))) {
        return false;
      }
      try {
        await mutate(file);
        return true;
      } on FileSystemException {
        return false;
      }
    }

    try {
      return await _withEventCoordinationLock(
        mutateExactOwner,
        ownerCompletion: ownerCompletion,
      );
    } on BoundedPosixFlockUnavailableException {
      return false;
    }
  }

  Future<T> _withEventCoordinationLock<T>(
    Future<T> Function() action, {
    bool ownerCompletion = false,
  }) {
    final lock = File(
      '${directory.path}${Platform.pathSeparator}.$eventClaimsDirectoryName.lock',
    );
    Future<T> guarded() => ownerCompletion
        ? _PosixFlock.withExclusiveOwnerCompletion(lock, action)
        : _PosixFlock.withExclusive(lock, action);
    if (platform == TargetPlatform.android) {
      return guarded();
    }
    return _serializeInIsolate(
      tails: _eventIsolateTails,
      key: lock.path,
      action: guarded,
    );
  }

  Future<bool> _isPendingMessageClaim(File file) async =>
      await _pendingMessageClaimRecord(file) != null;

  Future<_MessageClaimRecord?> _pendingMessageClaimRecord(File file) async {
    final record = await _ownedMessageClaimRecord(file);
    return record?.state == 'pending' ? record : null;
  }

  Future<_MessageClaimRecord?> _ownedMessageClaimRecord(File file) async {
    try {
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final state = decoded['state'];
      final token = decoded['token'];
      final createdAtMs = decoded['createdAtMs'];
      final publishingAtMs = decoded['publishingAtMs'];
      final committedAtMs = decoded['committedAtMs'];
      final publicationOutcome = decoded['publicationOutcome'];
      if (token is! String || createdAtMs is! int) {
        return null;
      }
      if (platform != TargetPlatform.android) {
        // Preserve the pre-Plan-334 Apple parser exactly: only `pending` owns
        // a token and extra fields are ignored by the legacy protocol.
        if (state != 'pending') return null;
        return _MessageClaimRecord(
          state: 'pending',
          token: _normalize(token, 'token'),
          createdAtMs: createdAtMs,
        );
      }

      final validAndroidShape =
          (state == 'pending' &&
              publishingAtMs == null &&
              committedAtMs == null &&
              publicationOutcome == null) ||
          (state == 'publishing' &&
              publishingAtMs is int &&
              committedAtMs == null &&
              publicationOutcome == null);
      if (!validAndroidShape) return null;
      return _MessageClaimRecord(
        state: state as String,
        token: _normalize(token, 'token'),
        createdAtMs: createdAtMs,
        publishingAtMs: publishingAtMs as int?,
      );
    } catch (_) {
      // Empty/legacy/NSE/malformed claim files are fail-closed committed claims.
      return null;
    }
  }

  bool _messageClaimIsStale(_MessageClaimRecord record, int nowMs) =>
      nowMs - record.createdAtMs >= pendingMessageClaimTtl.inMilliseconds;

  bool _messagePublicationIsStale(_MessageClaimRecord record, int nowMs) =>
      nowMs - (record.publishingAtMs ?? record.createdAtMs) >=
      pendingMessageClaimTtl.inMilliseconds;

  Future<bool> _finalizeUnknownMessagePublication(File file, int nowMs) async {
    try {
      await _writeAtomicRecord(
        file,
        jsonEncode(<String, Object>{
          'state': 'committed',
          'committedAtMs': nowMs,
          'publicationOutcome': 'unknown',
        }),
      );
      return true;
    } catch (_) {
      // The original `publishing` record remains the fail-closed authority when
      // atomic replacement cannot complete. Never surface this as fail-open
      // claim storage: a native side effect may already exist.
      return false;
    }
  }

  /// Reserves the audible right for a conversation without starting its tone
  /// window. Call [DurableNotificationToneReservation.commit] only after the
  /// native publication callback returns, or
  /// [DurableNotificationToneReservation.release] only after a known
  /// pre-publication failure.
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
  /// [reserveTone] and commit only after the native publication callback returns.
  Future<bool> acquireTone(String conversationKey) async {
    final reservation = await reserveTone(conversationKey);
    if (reservation == null) return false;
    return reservation.commit();
  }

  Future<_ToneReservationAttempt> _attemptToneReservation(
    Directory toneDir,
    String normalized,
  ) async {
    try {
      return await _withToneCoordinationLock(toneDir, () async {
        final file = File('${toneDir.path}/${_fileKey(normalized)}.lease');
        final pendingFile = File(
          '${toneDir.path}/.${_fileKey(normalized)}'
          '$tonePendingReservationFileSuffix',
        );
        final nowMs = now().toUtc().millisecondsSinceEpoch;
        await _prune(toneDir, ttl: eventTtl, maxEntries: maxToneLeases);

        if (await pendingFile.exists()) {
          final record = await _readToneReservationRecord(pendingFile);
          if (platform != TargetPlatform.android) {
            // Keep the pre-Plan-334 Apple sidecar protocol byte-for-behavior.
            // The NSE shares these files and relies on the legacy parser,
            // repair timestamp, and in-place numeric writes.
            if (record == null) {
              await _deleteIfExists(pendingFile);
            } else if (record.state == 'committed') {
              await _repairLegacyCommittedToneReservation(
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
                await _deleteIfExists(pendingFile);
              } else if (!_toneReservationIsStale(record, nowMs)) {
                return const _ToneReservationAttempt.pending();
              } else {
                await _deleteIfExists(file);
                await _deleteIfExists(pendingFile);
              }
            } else {
              await _deleteIfExists(pendingFile);
            }
          } else if (record == null) {
            // This can be a legacy torn `publishing -> committed` rewrite after
            // native show. Repair at observation time and make this attempt
            // silent; deleting it and trusting an old numeric reservation could
            // grant a second sound immediately.
            final postShowAtMs = await _readTonePostShowTimestampMs(
              pendingFile,
            );
            await _repairUnknownTonePublication(
              file: file,
              pendingFile: pendingFile,
              nowMs: nowMs,
              postShowAtMs: postShowAtMs,
            );
            return const _ToneReservationAttempt.unavailable();
          } else if (record.state == 'committed') {
            await _repairCommittedToneReservation(
              file: file,
              pendingFile: pendingFile,
              record: record,
              nowMs: nowMs,
            );
            return const _ToneReservationAttempt.unavailable();
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
          } else if (record.state == 'publishing') {
            // A previous process reached the audible native boundary but died
            // (or received an ambiguous platform result) before commit. Start
            // a fresh silent window at recovery time; never reclaim it for an
            // immediate second sound, regardless of reservation age.
            await _repairUnknownTonePublication(
              file: file,
              pendingFile: pendingFile,
              nowMs: nowMs,
              postShowAtMs: record.publishingAtMs,
            );
            return const _ToneReservationAttempt.unavailable();
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
    } on BoundedPosixFlockUnavailableException {
      return const _ToneReservationAttempt.unavailable();
    }
  }

  Future<bool> _commitToneReservation(
    DurableNotificationToneReservation reservation,
  ) async {
    final toneDir = reservation._leaseFile.parent;
    try {
      return await _withToneCoordinationLock(
        toneDir,
        () => _commitToneReservationExactOwner(reservation, toneDir),
        ownerCompletion: true,
      );
    } on BoundedPosixFlockUnavailableException {
      return false;
    }
  }

  Future<DurableNotificationTonePublicationResult>
  _publishAndCommitToneReservation(
    DurableNotificationToneReservation reservation,
    Future<void> Function() publishAudibly,
  ) async {
    if (platform != TargetPlatform.android) {
      await publishAudibly();
      return DurableNotificationTonePublicationResult.published(
        toneCommitted: await _commitToneReservation(reservation),
      );
    }

    final toneDir = reservation._leaseFile.parent;
    var nativePublicationEntered = false;
    var nativePublicationCompleted = false;
    try {
      return await _withToneCoordinationLock(toneDir, () async {
        final record = await _readToneReservationRecord(
          reservation._pendingFile,
        );
        if (!_toneReservationIsPendingOwner(record, reservation) ||
            !await _toneLeaseMatches(
              reservation._leaseFile,
              reservation._reservedAtMs,
            )) {
          return const DurableNotificationTonePublicationResult.ownershipLost();
        }

        try {
          await _writeToneReservationRecord(
            reservation._pendingFile,
            jsonEncode(<String, Object>{
              'state': 'publishing',
              'token': reservation.token,
              'reservedAtMs': reservation._reservedAtMs,
              'createdAtMs': record!.createdAtMs,
              'publishingAtMs': now().toUtc().millisecondsSinceEpoch,
            }),
          );
        } catch (_) {
          // No native call was made. Degrade this publication to silent; the
          // original pending reservation remains bounded and reclaimable.
          return const DurableNotificationTonePublicationResult.ownershipLost();
        }
        nativePublicationEntered = true;
        try {
          await publishAudibly();
          nativePublicationCompleted = true;
        } catch (error, stackTrace) {
          if (error is DurableNotificationPublicationNotAuthorizedException) {
            await _abortTonePublicationExactOwner(reservation);
            Error.throwWithStackTrace(error, stackTrace);
          }
          if (error is DurableNotificationPublicationAttemptedException) {
            Error.throwWithStackTrace(error, stackTrace);
          }
          Error.throwWithStackTrace(
            DurableNotificationPublicationAttemptedException(
              errorType: error.runtimeType.toString(),
            ),
            stackTrace,
          );
        }
        try {
          final committed = await _commitToneReservationExactOwner(
            reservation,
            toneDir,
          );
          return DurableNotificationTonePublicationResult.published(
            toneCommitted: committed,
          );
        } catch (_) {
          // Native publication already completed. Preserve the provisional
          // tone residue fail-closed instead of permitting a second sound.
          return const DurableNotificationTonePublicationResult.published(
            toneCommitted: false,
          );
        }
      });
    } catch (error, stackTrace) {
      if (error is DurableNotificationPublicationNotAuthorizedException) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      if (error is DurableNotificationPublicationAttemptedException) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      if (!nativePublicationEntered) {
        // Directory/lock/record failures happened before the callback boundary.
        // The caller can still issue exactly one silent native publication.
        return const DurableNotificationTonePublicationResult.ownershipLost();
      }
      if (nativePublicationCompleted) {
        // Native publication returned successfully. Any later coordination
        // failure is bookkeeping-only and must not cause a second show.
        return const DurableNotificationTonePublicationResult.published(
          toneCommitted: false,
        );
      }
      Error.throwWithStackTrace(
        DurableNotificationPublicationAttemptedException(
          errorType: error.runtimeType.toString(),
        ),
        stackTrace,
      );
    }
  }

  Future<bool> _commitToneReservationExactOwner(
    DurableNotificationToneReservation reservation,
    Directory toneDir,
  ) async {
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
    await _writeToneReservationRecord(
      reservation._pendingFile,
      jsonEncode(<String, Object>{
        'state': 'committed',
        'token': reservation.token,
        'reservedAtMs': reservation._reservedAtMs,
        'createdAtMs': record!.createdAtMs,
        'committedAtMs': committedAtMs,
      }),
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
  }

  Future<void> _abortTonePublicationExactOwner(
    DurableNotificationToneReservation reservation,
  ) async {
    final record = await _readToneReservationRecord(reservation._pendingFile);
    if (!_toneReservationIsOwnedBy(record, reservation)) return;
    final leaseMatches = await _toneLeaseMatches(
      reservation._leaseFile,
      reservation._reservedAtMs,
    );
    await _deleteIfExists(reservation._pendingFile);
    if (leaseMatches) await _deleteIfExists(reservation._leaseFile);
  }

  Future<bool> _releaseToneReservation(
    DurableNotificationToneReservation reservation,
  ) async {
    final toneDir = reservation._leaseFile.parent;
    try {
      return await _withToneCoordinationLock(toneDir, () async {
        final record = await _readToneReservationRecord(
          reservation._pendingFile,
        );
        if (!_toneReservationIsPendingOwner(record, reservation)) return false;

        final leaseMatches = await _toneLeaseMatches(
          reservation._leaseFile,
          reservation._reservedAtMs,
        );
        if (leaseMatches) {
          final leaseDeleted = await _deleteIfExists(reservation._leaseFile);
          final pendingDeleted = await _deleteIfExists(
            reservation._pendingFile,
          );
          return leaseDeleted && pendingDeleted;
        }
        await _deleteIfExists(reservation._pendingFile);
        return false;
      });
    } on BoundedPosixFlockUnavailableException {
      return false;
    }
  }

  bool _toneReservationIsOwnedBy(
    _ToneReservationRecord? record,
    DurableNotificationToneReservation reservation,
  ) =>
      record != null &&
      (record.state == 'pending' ||
          (platform == TargetPlatform.android &&
              record.state == 'publishing')) &&
      record.token == reservation.token &&
      record.reservedAtMs == reservation._reservedAtMs;

  bool _toneReservationIsPendingOwner(
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
      final publishingAtMs = decoded['publishingAtMs'];
      final committedAtMs = decoded['committedAtMs'];
      if (state is! String ||
          token is! String ||
          token.trim().isEmpty ||
          reservedAtMs is! int ||
          createdAtMs is! int ||
          (committedAtMs != null && committedAtMs is! int)) {
        return null;
      }
      if (platform != TargetPlatform.android) {
        // This is the exact legacy parser used by the Apple App Group/NSE
        // protocol: arbitrary string states and extra publishing fields remain
        // accepted, then the attempt logic decides whether to discard them.
        return _ToneReservationRecord(
          state: state,
          token: token.trim(),
          reservedAtMs: reservedAtMs,
          createdAtMs: createdAtMs,
          committedAtMs: committedAtMs as int?,
        );
      }

      final validAndroidShape =
          (state == 'pending' &&
              publishingAtMs == null &&
              committedAtMs == null) ||
          (state == 'publishing' &&
              publishingAtMs is int &&
              committedAtMs == null) ||
          (state == 'committed' &&
              publishingAtMs == null &&
              committedAtMs is int);
      if (!validAndroidShape) return null;
      return _ToneReservationRecord(
        state: state,
        token: token.trim(),
        reservedAtMs: reservedAtMs,
        createdAtMs: createdAtMs,
        publishingAtMs: publishingAtMs as int?,
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
    required int nowMs,
  }) async {
    await _repairTonePublicationAtObservation(
      file: file,
      pendingFile: pendingFile,
      nowMs: nowMs,
      postShowAtMs: record.committedAtMs,
    );
  }

  Future<void> _repairUnknownTonePublication({
    required File file,
    required File pendingFile,
    required int nowMs,
    int? postShowAtMs,
  }) async {
    await _repairTonePublicationAtObservation(
      file: file,
      pendingFile: pendingFile,
      nowMs: nowMs,
      postShowAtMs: postShowAtMs,
    );
  }

  Future<void> _repairTonePublicationAtObservation({
    required File file,
    required File pendingFile,
    required int nowMs,
    required int? postShowAtMs,
  }) async {
    try {
      final recordedAtMs = await _readToneTimestampMs(file);
      var repairedAtMs = nowMs;
      if (recordedAtMs != null) {
        repairedAtMs = max(repairedAtMs, recordedAtMs);
      }
      if (postShowAtMs != null) {
        repairedAtMs = max(repairedAtMs, postShowAtMs);
      }
      await _writeToneTimestamp(file, repairedAtMs);
      await _deleteIfExists(pendingFile);
    } catch (_) {
      // Preserve the post-show sidecar fail-closed. A later reservation retries
      // repair; it must not publish audibly while the outcome is unknown.
    }
  }

  Future<void> _repairLegacyCommittedToneReservation({
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

  Future<int?> _readTonePostShowTimestampMs(File file) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final timestamps = <int>[
        if (decoded['publishingAtMs'] is int) decoded['publishingAtMs'] as int,
        if (decoded['committedAtMs'] is int) decoded['committedAtMs'] as int,
      ];
      return timestamps.isEmpty ? null : timestamps.reduce(max);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _toneLeaseMatches(File file, int expectedMs) async =>
      await _readToneTimestampMs(file) == expectedMs;

  Future<void> _writeToneTimestamp(File file, int timestampMs) {
    final contents = (timestampMs / Duration.millisecondsPerSecond)
        .toStringAsFixed(3);
    if (platform == TargetPlatform.android) {
      return _writeAtomicRecord(file, contents);
    }
    return file.writeAsString(contents, flush: true);
  }

  Future<void> _writeToneReservationRecord(File file, String contents) {
    if (platform == TargetPlatform.android) {
      return _writeAtomicRecord(file, contents);
    }
    return file.writeAsString(contents, flush: true);
  }

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
    Future<T> Function() action, {
    bool ownerCompletion = false,
  }) async {
    await toneDir.create(recursive: true);
    final coordination = File('${toneDir.path}/$toneCoordinationLockFileName');
    Future<T> guarded() => ownerCompletion
        ? _PosixFlock.withExclusiveOwnerCompletion(coordination, action)
        : _PosixFlock.withExclusive(coordination, action);
    if (platform == TargetPlatform.android) {
      return guarded();
    }
    return _serializeToneInIsolate(toneDir.path, guarded);
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

  static Future<void> _writeAtomicRecord(File target, String contents) async {
    final temporary = File('${target.path}.replacement.tmp');
    try {
      await temporary.writeAsString(contents, flush: true);
      // POSIX rename replaces the old regular file atomically. A crash before
      // this line leaves the previous fail-closed record intact; after it, the
      // replacement is complete and parseable.
      await temporary.rename(target.path);
    } finally {
      try {
        if (await temporary.exists()) await temporary.delete();
      } catch (_) {
        // Hidden crash debris is ignored by exact-name readers and pruned later.
      }
    }
  }

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
        final ownedMessageClaim = await _ownedMessageClaimRecord(entity);
        if (ownedMessageClaim != null) {
          final nowMs = now().toUtc().millisecondsSinceEpoch;
          if (ownedMessageClaim.state == 'pending' &&
              _messageClaimIsStale(ownedMessageClaim, nowMs)) {
            await entity.delete();
          } else if (ownedMessageClaim.state == 'publishing' &&
              _messagePublicationIsStale(ownedMessageClaim, nowMs)) {
            final finalized = await _finalizeUnknownMessagePublication(
              entity,
              nowMs,
            );
            if (finalized) fresh.add((file: entity, timestamp: nowMs));
          }
          // Fresh pending/publication owners are outside committed-history
          // capacity pruning. Stale publication attempts were finalized above
          // and now participate in ordinary TTL/capacity pruning.
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
      if (value == null || !value.isFinite) return null;
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

/// `RandomAccessFile.lock` uses process-scoped POSIX record locks, so two Dart
/// isolates in the same Android process can both acquire it. BSD `flock`
/// instead coordinates independent open file descriptions in the same process
/// and across the app/NSE process boundary. Swift uses this exact lock file and
/// protocol.
final class _PosixFlock {
  static Future<T> withExclusive<T>(File file, Future<T> Function() action) =>
      BoundedPosixFlock.withExclusive(file, action);

  static Future<T> withExclusiveOwnerCompletion<T>(
    File file,
    Future<T> Function() action,
  ) => BoundedPosixFlock.withExclusiveOwnerCompletion(file, action);
}
