import 'dart:math' as math;

import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/settings/application/media_download_policy.dart';
import 'package:flutter_app/features/settings/domain/models/media_download_preferences.dart';

/// Stable address for the next durable recovery page.
///
/// Repository adapters must order candidates by this exact
/// `(created_at ASC, attachment_id ASC)` tuple and return only rows strictly
/// after [after].
class RecoverableGroupDownloadCursor
    implements Comparable<RecoverableGroupDownloadCursor> {
  const RecoverableGroupDownloadCursor({
    required this.createdAt,
    required this.attachmentId,
  });

  final String createdAt;
  final String attachmentId;

  @override
  int compareTo(RecoverableGroupDownloadCursor other) {
    final timestampOrder = createdAt.compareTo(other.createdAt);
    if (timestampOrder != 0) return timestampOrder;
    return attachmentId.compareTo(other.attachmentId);
  }

  @override
  bool operator ==(Object other) =>
      other is RecoverableGroupDownloadCursor &&
      other.createdAt == createdAt &&
      other.attachmentId == attachmentId;

  @override
  int get hashCode => Object.hash(createdAt, attachmentId);
}

/// One query-time snapshot returned by the durable recovery capability.
///
/// The snapshot is never transferred directly. Its identifiers locate exact
/// current attachment, parent, and group rows immediately before policy and
/// transfer decisions.
class RecoverableGroupDownloadCandidate {
  const RecoverableGroupDownloadCandidate({
    required this.attachment,
    required this.groupId,
  });

  final MediaAttachment attachment;
  final String groupId;

  RecoverableGroupDownloadCursor get cursor => RecoverableGroupDownloadCursor(
    createdAt: attachment.createdAt,
    attachmentId: attachment.id,
  );
}

/// Completion value shared by every trigger that joined one coordinator run.
class GroupMediaDownloadRecoveryResult {
  GroupMediaDownloadRecoveryResult({
    required this.scannedCount,
    required this.attemptedTransferCount,
    required this.successfulTransferCount,
    required Iterable<String> downloadedAttachmentIds,
    required Iterable<String> affectedMessageIds,
  }) : downloadedAttachmentIds = Set<String>.unmodifiable(
         downloadedAttachmentIds,
       ),
       affectedMessageIds = Set<String>.unmodifiable(affectedMessageIds);

  factory GroupMediaDownloadRecoveryResult.empty() =>
      GroupMediaDownloadRecoveryResult(
        scannedCount: 0,
        attemptedTransferCount: 0,
        successfulTransferCount: 0,
        downloadedAttachmentIds: const <String>{},
        affectedMessageIds: const <String>{},
      );

  final int scannedCount;
  final int attemptedTransferCount;
  final int successfulTransferCount;
  final Set<String> downloadedAttachmentIds;
  final Set<String> affectedMessageIds;

  GroupMediaDownloadRecoveryResult merge(
    GroupMediaDownloadRecoveryResult other,
  ) => GroupMediaDownloadRecoveryResult(
    scannedCount: scannedCount + other.scannedCount,
    attemptedTransferCount:
        attemptedTransferCount + other.attemptedTransferCount,
    successfulTransferCount:
        successfulTransferCount + other.successfulTransferCount,
    downloadedAttachmentIds: <String>{
      ...downloadedAttachmentIds,
      ...other.downloadedAttachmentIds,
    },
    affectedMessageIds: <String>{
      ...affectedMessageIds,
      ...other.affectedMessageIds,
    },
  );
}

typedef LoadRecoverableGroupDownloadPage =
    Future<List<RecoverableGroupDownloadCandidate>> Function({
      required RecoverableGroupDownloadCursor? after,
      required int limit,
    });

typedef LoadCurrentGroupDownloadAttachment =
    Future<MediaAttachment?> Function(String attachmentId);

typedef LoadCurrentGroupDownloadParent =
    Future<GroupMessage?> Function(String messageId);

typedef LoadCurrentGroupDownloadGroup =
    Future<GroupModel?> Function(String groupId);

typedef TransferRecoveredGroupDownload =
    Future<MediaAttachment?> Function({
      required MediaAttachment attachment,
      required GroupMessage parent,
      required GroupModel group,
    });

typedef RetryIncompleteGroupDownloads = Future<int> Function();

typedef AllowsGroupMediaDownloadNetworkSideEffects = Future<bool> Function();

typedef RetryPendingStrictGroupMediaBlobAcknowledgements =
    Future<int> Function();

Future<bool> _allowGroupMediaDownloadNetworkSideEffects() async => true;

Future<int> _retryNoStrictGroupMediaBlobAcknowledgements() async => 0;

/// Production-facing coordinator type shared by all automatic entry points.
typedef GroupMediaDownloadCoordinator = RetryIncompleteGroupDownloadsUseCase;

/// Bounded, shared coordinator for automatic ordinary-group media recovery.
///
/// One instance is intended to be shared by listener, route, resume, and
/// periodic triggers. Overlapping calls return the same in-flight future.
class RetryIncompleteGroupDownloadsUseCase {
  RetryIncompleteGroupDownloadsUseCase({
    required this.loadPage,
    required this.loadCurrentAttachment,
    required this.loadCurrentParent,
    required this.loadCurrentGroup,
    required this.autoDownloadDecider,
    required this.transfer,
    TransferRecoveredGroupDownload? strictTransfer,
    this.retryPendingStrictAcknowledgements =
        _retryNoStrictGroupMediaBlobAcknowledgements,
    this.allowsNetworkSideEffects = _allowGroupMediaDownloadNetworkSideEffects,
    this.pageSize = 25,
    this.scanLimit = 200,
    this.transferLimit = 10,
  }) : strictTransfer = strictTransfer ?? transfer {
    if (pageSize <= 0) {
      throw ArgumentError.value(pageSize, 'pageSize', 'must be positive');
    }
    if (scanLimit <= 0) {
      throw ArgumentError.value(scanLimit, 'scanLimit', 'must be positive');
    }
    if (transferLimit <= 0) {
      throw ArgumentError.value(
        transferLimit,
        'transferLimit',
        'must be positive',
      );
    }
  }

  final LoadRecoverableGroupDownloadPage loadPage;
  final LoadCurrentGroupDownloadAttachment loadCurrentAttachment;
  final LoadCurrentGroupDownloadParent loadCurrentParent;
  final LoadCurrentGroupDownloadGroup loadCurrentGroup;
  final MediaAutoDownloadDecider autoDownloadDecider;
  final TransferRecoveredGroupDownload transfer;

  /// Exact Plan-365 owner for fingerprinted group rows. Production defaults
  /// to the same `downloadMedia` adapter, whose durable discriminator routes
  /// into strict custody; tests and restricted runtimes may inject the narrow
  /// owner directly. A fingerprinted row never calls [transfer].
  final TransferRecoveredGroupDownload strictTransfer;
  final RetryPendingStrictGroupMediaBlobAcknowledgements
  retryPendingStrictAcknowledgements;
  final AllowsGroupMediaDownloadNetworkSideEffects allowsNetworkSideEffects;

  /// Maximum number of rows requested from the repository at once.
  final int pageSize;

  /// Maximum number of distinct, forward-progressing candidates inspected.
  final int scanLimit;

  /// Maximum number of policy-allowed transfers attempted in one pass.
  final int transferLimit;

  Future<GroupMediaDownloadRecoveryResult>? _inFlightRecovery;
  Future<int>? _inFlightCount;
  Future<int>? _inFlightStrictCount;
  bool _activeDrainIncludesSweep = false;
  bool _pendingSweep = false;
  RecoverableGroupDownloadCursor? _nextSweepCursor;
  RecoverableGroupDownloadCursor? _nextStrictSweepCursor;
  final Map<String, Set<String>> _pendingTargets = <String, Set<String>>{};

  bool get isIdle => _inFlightRecovery == null && _inFlightStrictCount == null;

  /// Runs one bounded pass, or joins the pass already owned by this instance.
  Future<int> call() {
    final existing = _inFlightCount;
    if (existing != null) return existing;

    late final Future<int> tracked;
    tracked = sweep()
        .then((result) => result.successfulTransferCount)
        .whenComplete(() {
          if (identical(_inFlightCount, tracked)) {
            _inFlightCount = null;
          }
        });
    _inFlightCount = tracked;
    return tracked;
  }

  /// Restricted linked-runtime drain for Plan-365 custody only.
  ///
  /// It first retries the independent ACK_PENDING lane, then cursor-pages the
  /// incumbent recoverable attachment query while invoking [strictTransfer]
  /// only for rows carrying the durable group custody fingerprint. Ordinary
  /// legacy candidates may consume bounded scan budget but can never reach
  /// [transfer] or any proof-less bridge path from this entry point.
  Future<int> callStrictGroupMediaCustodyOnly() {
    final existing = _inFlightStrictCount;
    if (existing != null) return existing;

    late final Future<int> tracked;
    tracked = _runStrictCustodyOnlyPass().whenComplete(() {
      if (identical(_inFlightStrictCount, tracked)) {
        _inFlightStrictCount = null;
      }
    });
    _inFlightStrictCount = tracked;
    return tracked;
  }

  /// Requests a global cursor-paged durable sweep.
  ///
  /// A duplicate global request joins the active run. When the active run was
  /// initially target-only, one global pass is appended to the same future.
  Future<GroupMediaDownloadRecoveryResult> sweep() {
    final active = _inFlightRecovery;
    if (active != null) {
      if (!_activeDrainIncludesSweep) {
        _activeDrainIncludesSweep = true;
        _pendingSweep = true;
      }
      return active;
    }

    _activeDrainIncludesSweep = true;
    _pendingSweep = true;
    return _startDrain();
  }

  /// Recovers exact committed attachment IDs for one group.
  ///
  /// Listener and route triggers use this path so a newly enriched row cannot
  /// sit behind the global scan bound. IDs arriving during another pass are
  /// de-duplicated and appended to that pass's shared completion future.
  Future<GroupMediaDownloadRecoveryResult> recoverAttachments({
    required String groupId,
    required Iterable<String> attachmentIds,
  }) {
    if (groupId.isEmpty) {
      throw ArgumentError.value(groupId, 'groupId', 'must not be empty');
    }
    final ids = attachmentIds.where((id) => id.isNotEmpty).toSet();
    final active = _inFlightRecovery;
    if (ids.isEmpty) {
      return active ?? Future.value(GroupMediaDownloadRecoveryResult.empty());
    }

    _pendingTargets.putIfAbsent(groupId, () => <String>{}).addAll(ids);
    return active ?? _startDrain();
  }

  /// Completes after the current shared sweep and any merged targeted tail.
  Future<void> waitForIdle() {
    final active = <Future<Object?>>[?_inFlightRecovery, ?_inFlightStrictCount];
    if (active.isEmpty) return Future<void>.value();
    return Future.wait<Object?>(active).then<void>((_) {});
  }

  Future<GroupMediaDownloadRecoveryResult> _startDrain() {
    late final Future<GroupMediaDownloadRecoveryResult> tracked;
    tracked = _drainRequests().whenComplete(() {
      if (identical(_inFlightRecovery, tracked)) {
        _inFlightRecovery = null;
        _activeDrainIncludesSweep = false;
      }
    });
    _inFlightRecovery = tracked;
    return tracked;
  }

  Future<GroupMediaDownloadRecoveryResult> _drainRequests() async {
    var aggregate = GroupMediaDownloadRecoveryResult.empty();
    // ACK_PENDING rows have already committed durable plaintext and are no
    // longer discoverable through pending-attachment paging. Drain that
    // independent lane on every lifecycle invocation before scanning new
    // downloads; a failure is retained by its strict owner and cannot block
    // ordinary/voice fairness below.
    try {
      await retryPendingStrictAcknowledgements();
    } catch (_) {}
    while (_pendingSweep || _pendingTargets.isNotEmpty) {
      if (_pendingSweep) {
        _pendingSweep = false;
        aggregate = aggregate.merge(await _runPagedPass());
        continue;
      }

      final targets = <String, Set<String>>{
        for (final entry in _pendingTargets.entries)
          entry.key: Set<String>.of(entry.value),
      };
      _pendingTargets.clear();
      final targeted = await _runTargetedPass(targets);
      aggregate = aggregate.merge(targeted.result);
      for (final entry in targeted.remainder.entries) {
        _pendingTargets
            .putIfAbsent(entry.key, () => <String>{})
            .addAll(entry.value);
      }
    }
    return aggregate;
  }

  Future<GroupMediaDownloadRecoveryResult> _runPagedPass() async {
    var after = _nextSweepCursor;
    var exhausted = false;
    final result = _RecoveryResultBuilder();

    while (result.scannedCount < scanLimit &&
        result.attemptedTransferCount < transferLimit) {
      final requestLimit = math.min(pageSize, scanLimit - result.scannedCount);
      final page = await loadPage(after: after, limit: requestLimit);
      if (page.isEmpty) {
        exhausted = true;
        break;
      }

      var madeCursorProgress = false;
      for (final candidate in page.take(requestLimit)) {
        if (result.scannedCount >= scanLimit ||
            result.attemptedTransferCount >= transferLimit) {
          break;
        }

        final candidateCursor = candidate.cursor;
        if (after != null && candidateCursor.compareTo(after) <= 0) {
          continue;
        }
        after = candidateCursor;
        madeCursorProgress = true;
        result.scannedCount++;

        final authority = await _loadCurrentAuthority(candidate);
        if (authority == null) continue;
        await _attemptTransfer(authority, result);
      }

      if (!madeCursorProgress || page.length < requestLimit) {
        exhausted = true;
        break;
      }
    }

    // A bounded pass retains the last inspected durable address so the next
    // trigger cannot repeatedly spend its scan budget on the same denied or
    // malformed prefix. Once the repository is exhausted, the following
    // trigger begins a fresh cycle so newly inserted/changed earlier rows are
    // eventually reconsidered too.
    _nextSweepCursor = exhausted ? null : after;

    return result.build();
  }

  Future<int> _runStrictCustodyOnlyPass() async {
    try {
      if (!await allowsNetworkSideEffects()) return 0;
    } catch (_) {
      return 0;
    }

    var progress = 0;
    try {
      progress += await retryPendingStrictAcknowledgements();
    } catch (_) {}

    var after = _nextStrictSweepCursor;
    var exhausted = false;
    final result = _RecoveryResultBuilder();
    while (result.scannedCount < scanLimit &&
        result.attemptedTransferCount < transferLimit) {
      final requestLimit = math.min(pageSize, scanLimit - result.scannedCount);
      final page = await loadPage(after: after, limit: requestLimit);
      if (page.isEmpty) {
        exhausted = true;
        break;
      }
      var madeCursorProgress = false;
      for (final candidate in page.take(requestLimit)) {
        if (result.scannedCount >= scanLimit ||
            result.attemptedTransferCount >= transferLimit) {
          break;
        }
        final cursor = candidate.cursor;
        if (after != null && cursor.compareTo(after) <= 0) continue;
        after = cursor;
        madeCursorProgress = true;
        result.scannedCount++;
        final authority = await _loadCurrentAuthority(candidate);
        if (authority == null ||
            authority.attachment.groupMediaBlobCustodyFingerprint == null) {
          continue;
        }
        await _attemptTransfer(authority, result);
      }
      if (!madeCursorProgress || page.length < requestLimit) {
        exhausted = true;
        break;
      }
    }
    _nextStrictSweepCursor = exhausted ? null : after;
    return progress + result.successfulTransferCount;
  }

  Future<
    ({
      GroupMediaDownloadRecoveryResult result,
      Map<String, Set<String>> remainder,
    })
  >
  _runTargetedPass(Map<String, Set<String>> targets) async {
    final result = _RecoveryResultBuilder();
    final remainder = <String, Set<String>>{};
    final addresses =
        <(String, String)>[
          for (final entry in targets.entries)
            for (final attachmentId in entry.value) (entry.key, attachmentId),
        ]..sort((left, right) {
          final groupOrder = left.$1.compareTo(right.$1);
          return groupOrder != 0 ? groupOrder : left.$2.compareTo(right.$2);
        });

    for (var index = 0; index < addresses.length; index++) {
      if (result.scannedCount >= scanLimit ||
          result.attemptedTransferCount >= transferLimit) {
        for (final (groupId, attachmentId) in addresses.skip(index)) {
          remainder.putIfAbsent(groupId, () => <String>{}).add(attachmentId);
        }
        break;
      }
      final (groupId, attachmentId) = addresses[index];
      result.scannedCount++;
      final selected = await loadCurrentAttachment(attachmentId);
      if (selected == null) continue;
      final authority = await _loadCurrentAuthority(
        RecoverableGroupDownloadCandidate(
          attachment: selected,
          groupId: groupId,
        ),
      );
      if (authority == null) continue;
      await _attemptTransfer(authority, result);
    }
    return (result: result.build(), remainder: remainder);
  }

  Future<void> _attemptTransfer(
    _CurrentGroupDownloadAuthority authority,
    _RecoveryResultBuilder result,
  ) async {
    // The account/migration gate owns permission to touch the network. It is
    // deliberately first: preferences and durable authority are re-read only
    // after that awaited boundary, immediately before the transfer call.
    try {
      if (!await allowsNetworkSideEffects()) return;
    } catch (_) {
      return;
    }

    final requalified = await _loadCurrentAuthority(
      RecoverableGroupDownloadCandidate(
        attachment: authority.attachment,
        groupId: authority.group.id,
      ),
    );
    if (requalified == null) return;

    final allowed = await _policyAllows(requalified);
    if (!allowed) return;

    // This is intentionally adjacent to the awaited policy decision. The
    // transfer function owns the final claim/commit CAS and must receive the
    // exact current row, never the query-time snapshot.
    result.attemptedTransferCount++;
    try {
      final transferOwner =
          requalified.attachment.groupMediaBlobCustodyFingerprint != null
          ? strictTransfer
          : transfer;
      final downloaded = await transferOwner(
        attachment: requalified.attachment,
        parent: requalified.parent,
        group: requalified.group,
      );
      if (downloaded != null &&
          downloaded.id == requalified.attachment.id &&
          downloaded.messageId == requalified.attachment.messageId) {
        result.successfulTransferCount++;
        result.downloadedAttachmentIds.add(downloaded.id);
        result.affectedMessageIds.add(downloaded.messageId);
      }
    } catch (_) {
      // The transfer boundary is responsible for persisting its truthful
      // retry state. One failed blob must not starve later candidates.
    }
  }

  Future<_CurrentGroupDownloadAuthority?> _loadCurrentAuthority(
    RecoverableGroupDownloadCandidate candidate,
  ) async {
    final attachment = await loadCurrentAttachment(candidate.attachment.id);
    if (attachment == null ||
        attachment.id != candidate.attachment.id ||
        attachment.messageId != candidate.attachment.messageId ||
        attachment.ownerLane != MediaOwnerLane.group ||
        !_isRecoverableAttachment(attachment)) {
      return null;
    }

    final parent = await loadCurrentParent(candidate.attachment.messageId);
    if (parent == null ||
        parent.id != candidate.attachment.messageId ||
        parent.groupId != candidate.groupId ||
        !_isCurrentOrdinaryIncomingParent(parent)) {
      return null;
    }

    final group = await loadCurrentGroup(candidate.groupId);
    if (group == null ||
        group.id != candidate.groupId ||
        group.isDissolved ||
        group.selfRemovedAt != null) {
      return null;
    }

    return _CurrentGroupDownloadAuthority(
      attachment: attachment,
      parent: parent,
      group: group,
    );
  }

  Future<bool> _policyAllows(_CurrentGroupDownloadAuthority authority) async {
    try {
      return await autoDownloadDecider.shouldAutoDownload(
        conversationKind: authority.group.type == GroupType.announcement
            ? MediaConversationKind.announcement
            : MediaConversationKind.discussion,
        storageOwner: MediaOwnerLane.group,
        mediaType: authority.attachment.mediaType,
        downloadStatus: authority.attachment.downloadStatus,
        isProtected: false,
      );
    } catch (_) {
      // Preference/network lookup failures fail closed without claiming or
      // mutating the durable row.
      return false;
    }
  }
}

bool _isRecoverableAttachment(MediaAttachment attachment) {
  if ((attachment.downloadRetryCount ?? 0) >= kMaxDownloadRetries) {
    return false;
  }
  final statusIsRecoverable =
      attachment.downloadStatus == kMediaDownloadStatusPending ||
      attachment.downloadStatus == kMediaDownloadStatusDownloading ||
      attachment.downloadStatus == kMediaDownloadStatusFailed;
  if (!statusIsRecoverable) return false;

  return GroupMediaMimePolicy.validateDescriptor(
        mime: attachment.mime,
        mediaType: attachment.mediaType,
      ).isValid &&
      GroupMediaSizePolicy.validateAttachments(<MediaAttachment>[
        attachment,
      ], perMediaLimitBytes: kGroupMediaPerAttachmentLimitBytes).isValid &&
      GroupMediaIntegrityPolicy.hasRequiredVerificationMetadata(attachment);
}

bool _isCurrentOrdinaryIncomingParent(GroupMessage parent) =>
    parent.isIncoming &&
    parent.privateMediaPolicy.isOrdinary &&
    parent.mediaReceivedAt == null &&
    parent.mediaExpiresAt == null &&
    parent.mediaLastCheckedAt == null &&
    parent.mediaConsumedAt == null &&
    parent.mediaExpiredAt == null &&
    !parent.mediaCleanupPending;

class _CurrentGroupDownloadAuthority {
  const _CurrentGroupDownloadAuthority({
    required this.attachment,
    required this.parent,
    required this.group,
  });

  final MediaAttachment attachment;
  final GroupMessage parent;
  final GroupModel group;
}

class _RecoveryResultBuilder {
  int scannedCount = 0;
  int attemptedTransferCount = 0;
  int successfulTransferCount = 0;
  final Set<String> downloadedAttachmentIds = <String>{};
  final Set<String> affectedMessageIds = <String>{};

  GroupMediaDownloadRecoveryResult build() => GroupMediaDownloadRecoveryResult(
    scannedCount: scannedCount,
    attemptedTransferCount: attemptedTransferCount,
    successfulTransferCount: successfulTransferCount,
    downloadedAttachmentIds: downloadedAttachmentIds,
    affectedMessageIds: affectedMessageIds,
  );
}
