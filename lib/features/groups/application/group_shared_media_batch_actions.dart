import 'dart:io';

import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/media_storage_manager.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';
import 'package:flutter_app/core/media/received_media_egress_service.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/media_library.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/group_media_delete_for_me_coordinator.dart';
import 'package:flutter_app/features/groups/application/group_received_media_actions.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_library_controller.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:uuid/uuid.dart';

enum GroupSharedMediaPreflightDenial {
  parentMissing,
  wrongGroup,
  notIncoming,
  attachmentNotGroupOwned,
  notVisualMedia,
  mimeNotAllowed,
  notDisplayable,
  lifecycleRestricted,
  fileMissing,
  unknown,
}

class GroupSharedMediaBatchItemOutcome {
  const GroupSharedMediaBatchItemOutcome({
    required this.attachmentId,
    required this.succeeded,
    this.denial,
    this.itemOutcome,
  });

  final String attachmentId;
  final bool succeeded;
  final GroupSharedMediaPreflightDenial? denial;
  final MediaEgressItemOutcome? itemOutcome;
}

class GroupSharedMediaBatchResult {
  const GroupSharedMediaBatchResult({
    required this.items,
    required this.egressResult,
  });

  final List<GroupSharedMediaBatchItemOutcome> items;
  final MediaEgressResult? egressResult;

  bool get wasCancelled =>
      egressResult?.outcome == MediaEgressOutcome.cancelled;

  Set<String> get succeededIds => {
    for (final item in items)
      if (item.succeeded) item.attachmentId,
  };

  Set<String> get failedIds => {
    for (final item in items)
      if (!item.succeeded) item.attachmentId,
  };
}

class GroupSharedMediaLocalItemOutcome {
  const GroupSharedMediaLocalItemOutcome({
    required this.attachmentId,
    required this.succeeded,
    this.reason,
  });

  final String attachmentId;
  final bool succeeded;
  final String? reason;
}

class GroupSharedMediaLocalBatchResult {
  const GroupSharedMediaLocalBatchResult(this.items);

  final List<GroupSharedMediaLocalItemOutcome> items;

  Set<String> get succeededIds => {
    for (final item in items)
      if (item.succeeded) item.attachmentId,
  };

  Set<String> get failedIds => {
    for (final item in items)
      if (!item.succeeded) item.attachmentId,
  };
}

typedef GroupSharedMediaClearLocalCopy =
    Future<MediaClearLocalCopyResult> Function({
      required MediaLibraryScope scope,
      required String attachmentId,
      required String mime,
    });

typedef GroupSharedMediaEgressDispatch =
    Future<GroupSharedMediaBatchResult> Function(
      List<GroupSharedMediaIdentity> identities,
      MediaEgressDestination destination,
    );

/// Dispatch-time batch Save/Share using the exact same current-row qualifier
/// as the single-item group action controller. All eligible unique identities
/// enter one ordered native request; preflight/native failures remain selected.
class GroupSharedMediaBatchActionsCoordinator {
  GroupSharedMediaBatchActionsCoordinator({
    required this.messageRepository,
    required this.mediaAttachmentRepository,
    required this.egressService,
    MediaFileManager? mediaFileManager,
    GroupMediaEgressRestriction? isEgressRestricted,
    this.fileExists,
    this.stateRepository,
    this.clearLocalCopy,
    String Function()? requestIdFactory,
  }) : mediaFileManager = mediaFileManager ?? MediaFileManager(),
       isEgressRestricted = isEgressRestricted ?? ((_) => false),
       requestIdFactory = requestIdFactory ?? (() => const Uuid().v4());

  final GroupMessageRepository messageRepository;
  final MediaAttachmentRepository mediaAttachmentRepository;
  final ReceivedMediaEgressService egressService;
  final MediaFileManager mediaFileManager;
  final GroupMediaEgressRestriction isEgressRestricted;
  final Future<bool> Function(String resolvedPath)? fileExists;
  final MediaLibraryStateRepository? stateRepository;
  final GroupSharedMediaClearLocalCopy? clearLocalCopy;
  final String Function() requestIdFactory;

  Future<GroupSharedMediaBatchResult> performBatchEgress({
    required List<GroupSharedMediaIdentity> identities,
    required MediaEgressDestination destination,
  }) async {
    final groupIds = identities.map((identity) => identity.groupId).toSet();
    final unique = <String, GroupSharedMediaIdentity>{};
    var hasAliasConflict = false;
    for (final identity in identities) {
      final previous = unique[identity.attachmentId];
      if (previous == null) {
        unique[identity.attachmentId] = identity;
      } else if (previous.groupId != identity.groupId ||
          previous.messageId != identity.messageId) {
        hasAliasConflict = true;
      }
    }
    if (unique.isEmpty ||
        unique.length > kGroupSharedMediaSelectionLimit ||
        groupIds.length != 1 ||
        hasAliasConflict) {
      throw ArgumentError.value(
        identities.length,
        'identities',
        'batch must contain 1..$kGroupSharedMediaSelectionLimit '
            'non-conflicting identities',
      );
    }

    final decisions = <String, GroupMediaCurrentRowDecision>{};
    final candidates = <ReceivedMediaEgressCandidate>[];
    for (final identity in unique.values) {
      final decision = await qualifyCurrentGroupMediaRow(
        groupId: identity.groupId,
        messageId: identity.messageId,
        attachmentId: identity.attachmentId,
        messageRepository: messageRepository,
        mediaAttachmentRepository: mediaAttachmentRepository,
        mediaFileManager: mediaFileManager,
        isEgressRestricted: isEgressRestricted,
        fileExists: fileExists ?? _ioFileExists,
      );
      decisions[identity.attachmentId] = decision;
      if (decision.candidate case final candidate?) {
        candidates.add(candidate);
      }
    }

    MediaEgressResult? egressResult;
    var nativeById = const <String, MediaEgressItemResult>{};
    if (candidates.isNotEmpty) {
      egressResult = await egressService.perform(
        requestId: requestIdFactory(),
        destination: destination,
        selection: candidates,
      );
      nativeById = {
        for (final item in egressResult.items) item.attachmentId: item,
      };
    }
    final sharePresented =
        destination == MediaEgressDestination.share &&
        egressResult?.outcome == MediaEgressOutcome.presented;

    return GroupSharedMediaBatchResult(
      egressResult: egressResult,
      items: [
        for (final identity in unique.values)
          _settle(
            identity: identity,
            decision: decisions[identity.attachmentId]!,
            destination: destination,
            native: nativeById[identity.attachmentId],
            sharePresented: sharePresented,
          ),
      ],
    );
  }

  Future<GroupSharedMediaLocalBatchResult> performBatchBookmark({
    required List<GroupSharedMediaIdentity> identities,
    required bool bookmarked,
  }) async {
    final unique = _validateAndDeduplicate(identities);
    final writer = stateRepository;
    if (writer == null) {
      throw StateError('bookmark state repository is unavailable');
    }
    final outcomes = <GroupSharedMediaLocalItemOutcome>[];
    for (final identity in unique) {
      final current = await _qualifyLocalIdentity(identity);
      if (current.attachment == null) {
        outcomes.add(
          GroupSharedMediaLocalItemOutcome(
            attachmentId: identity.attachmentId,
            succeeded: false,
            reason: current.reason,
          ),
        );
        continue;
      }
      try {
        await writer.setBookmarked(
          identity.attachmentId,
          bookmarked: bookmarked,
        );
        outcomes.add(
          GroupSharedMediaLocalItemOutcome(
            attachmentId: identity.attachmentId,
            succeeded: true,
          ),
        );
      } catch (_) {
        outcomes.add(
          GroupSharedMediaLocalItemOutcome(
            attachmentId: identity.attachmentId,
            succeeded: false,
            reason: 'bookmark_failed',
          ),
        );
      }
    }
    return GroupSharedMediaLocalBatchResult(outcomes);
  }

  Future<GroupSharedMediaLocalBatchResult> performBatchClear({
    required List<GroupSharedMediaIdentity> identities,
  }) async {
    final unique = _validateAndDeduplicate(identities);
    final clear = clearLocalCopy;
    if (clear == null) throw StateError('clear-local-copy is unavailable');
    final outcomes = <GroupSharedMediaLocalItemOutcome>[];
    for (final identity in unique) {
      final current = await _qualifyLocalIdentity(identity);
      final attachment = current.attachment;
      if (attachment == null) {
        outcomes.add(
          GroupSharedMediaLocalItemOutcome(
            attachmentId: identity.attachmentId,
            succeeded: false,
            reason: current.reason,
          ),
        );
        continue;
      }
      try {
        final result = await clear(
          scope: MediaLibraryScope.group(identity.groupId),
          attachmentId: identity.attachmentId,
          mime: attachment.mime,
        );
        final succeeded =
            result == MediaClearLocalCopyResult.cleared ||
            result == MediaClearLocalCopyResult.alreadyCleared;
        outcomes.add(
          GroupSharedMediaLocalItemOutcome(
            attachmentId: identity.attachmentId,
            succeeded: succeeded,
            reason: succeeded ? null : result.name,
          ),
        );
      } catch (_) {
        outcomes.add(
          GroupSharedMediaLocalItemOutcome(
            attachmentId: identity.attachmentId,
            succeeded: false,
            reason: 'clear_failed',
          ),
        );
      }
    }
    return GroupSharedMediaLocalBatchResult(outcomes);
  }

  List<GroupSharedMediaIdentity> _validateAndDeduplicate(
    List<GroupSharedMediaIdentity> identities,
  ) {
    final unique = <String, GroupSharedMediaIdentity>{};
    var conflict = false;
    for (final identity in identities) {
      final previous = unique[identity.attachmentId];
      if (previous == null) {
        unique[identity.attachmentId] = identity;
      } else if (previous.groupId != identity.groupId ||
          previous.messageId != identity.messageId) {
        conflict = true;
      }
    }
    if (unique.isEmpty ||
        unique.length > kGroupSharedMediaSelectionLimit ||
        unique.values.map((item) => item.groupId).toSet().length != 1 ||
        conflict) {
      throw ArgumentError.value(identities.length, 'identities');
    }
    return unique.values.toList(growable: false);
  }

  Future<({MediaAttachment? attachment, String? reason})> _qualifyLocalIdentity(
    GroupSharedMediaIdentity identity,
  ) async {
    final parent = await messageRepository.getMessage(identity.messageId);
    if (parent == null) return (attachment: null, reason: 'parent_missing');
    if (parent.groupId != identity.groupId) {
      return (attachment: null, reason: 'wrong_group');
    }
    final tombstoneGroupId = await messageRepository.getLocalDeletionGroupId(
      identity.messageId,
    );
    if (tombstoneGroupId == identity.groupId) {
      return (attachment: null, reason: 'parent_missing');
    }
    if (!parent.isIncoming) {
      return (attachment: null, reason: 'not_incoming');
    }
    final rows = await mediaAttachmentRepository.getAttachmentsForMessage(
      identity.messageId,
      owner: MediaOwnerLane.group,
    );
    for (final row in rows) {
      if (row.id == identity.attachmentId &&
          row.ownerLane == MediaOwnerLane.group &&
          (row.mediaType == 'image' || row.mediaType == 'video')) {
        return (attachment: row, reason: null);
      }
    }
    return (attachment: null, reason: 'attachment_not_group_owned');
  }

  GroupSharedMediaBatchItemOutcome _settle({
    required GroupSharedMediaIdentity identity,
    required GroupMediaCurrentRowDecision decision,
    required MediaEgressDestination destination,
    required MediaEgressItemResult? native,
    required bool sharePresented,
  }) {
    if (!decision.isQualified) {
      return GroupSharedMediaBatchItemOutcome(
        attachmentId: identity.attachmentId,
        succeeded: false,
        denial: _typedDenial(decision.refusalReason),
      );
    }
    if (destination == MediaEgressDestination.share) {
      return GroupSharedMediaBatchItemOutcome(
        attachmentId: identity.attachmentId,
        succeeded: sharePresented,
      );
    }
    final outcome = native?.outcome ?? MediaEgressItemOutcome.platformFailure;
    return GroupSharedMediaBatchItemOutcome(
      attachmentId: identity.attachmentId,
      succeeded: outcome == MediaEgressItemOutcome.saved,
      itemOutcome: outcome,
    );
  }

  GroupSharedMediaPreflightDenial _typedDenial(String? reason) =>
      switch (reason) {
        'parent_missing' => GroupSharedMediaPreflightDenial.parentMissing,
        'wrong_group' => GroupSharedMediaPreflightDenial.wrongGroup,
        'not_incoming' => GroupSharedMediaPreflightDenial.notIncoming,
        'attachment_not_group_owned' =>
          GroupSharedMediaPreflightDenial.attachmentNotGroupOwned,
        'not_visual_media' => GroupSharedMediaPreflightDenial.notVisualMedia,
        'mime_not_allowed' => GroupSharedMediaPreflightDenial.mimeNotAllowed,
        'not_displayable' => GroupSharedMediaPreflightDenial.notDisplayable,
        'lifecycle_restricted' =>
          GroupSharedMediaPreflightDenial.lifecycleRestricted,
        'file_missing' => GroupSharedMediaPreflightDenial.fileMissing,
        _ => GroupSharedMediaPreflightDenial.unknown,
      };
}

Future<bool> _ioFileExists(String path) async {
  return File(path).exists();
}

class GroupSharedMediaBatchDeleteOutcome {
  const GroupSharedMediaBatchDeleteOutcome({
    required this.deletedMessageIds,
    required this.failedMessageIds,
    required this.deletedAttachmentIds,
    required this.failedAttachmentIds,
  });

  final Set<String> deletedMessageIds;
  final Set<String> failedMessageIds;
  final Set<String> deletedAttachmentIds;
  final Set<String> failedAttachmentIds;
}

typedef GroupSharedMediaDeleteDispatch =
    Future<GroupSharedMediaBatchDeleteOutcome> Function(
      List<GroupSharedMediaIdentity> identities,
    );

/// Whole-message group delete with post-call durable reconciliation. A void
/// coordinator completion is never treated as success by itself.
Future<GroupSharedMediaBatchDeleteOutcome> deleteGroupSharedMediaSelection({
  required List<GroupSharedMediaIdentity> identities,
  required GroupMessageRepository messageRepository,
  required GroupMediaDeleteForMeCoordinator coordinator,
}) async {
  final unique = <String, GroupSharedMediaIdentity>{};
  var conflict = false;
  for (final identity in identities) {
    final previous = unique[identity.attachmentId];
    if (previous == null) {
      unique[identity.attachmentId] = identity;
    } else if (previous.groupId != identity.groupId ||
        previous.messageId != identity.messageId) {
      conflict = true;
    }
  }
  final uniqueParents = unique.values.map((item) => item.messageId).toSet();
  if (unique.isEmpty ||
      unique.length > kGroupSharedMediaSelectionLimit ||
      uniqueParents.length > kGroupSharedMediaSelectionLimit ||
      unique.values.map((item) => item.groupId).toSet().length != 1 ||
      conflict) {
    throw ArgumentError.value(identities.length, 'identities');
  }
  final byParent = <String, List<GroupSharedMediaIdentity>>{};
  for (final identity in unique.values) {
    byParent.putIfAbsent(identity.messageId, () => []).add(identity);
  }

  final deletedMessages = <String>{};
  final failedMessages = <String>{};
  final deletedAttachments = <String>{};
  final failedAttachments = <String>{};
  for (final entry in byParent.entries) {
    final identitiesForParent = entry.value;
    final groupIds = identitiesForParent.map((item) => item.groupId).toSet();
    final groupId = groupIds.length == 1 ? groupIds.single : null;
    final before = await messageRepository.getMessage(entry.key);
    if (groupId == null ||
        before == null ||
        before.groupId != groupId ||
        !before.isIncoming) {
      failedMessages.add(entry.key);
      failedAttachments.addAll(
        identitiesForParent.map((item) => item.attachmentId),
      );
      continue;
    }
    try {
      await coordinator.deleteForMe(groupId: groupId, messageId: entry.key);
    } catch (_) {
      // Reconciliation below is still authoritative: a coordinator can throw
      // after committing the tombstone.
    }
    final remaining = await messageRepository.getMessage(entry.key);
    final tombstoneGroup = await messageRepository.getLocalDeletionGroupId(
      entry.key,
    );
    final provedDeleted = remaining == null && tombstoneGroup == groupId;
    if (provedDeleted) {
      deletedMessages.add(entry.key);
      deletedAttachments.addAll(
        identitiesForParent.map((item) => item.attachmentId),
      );
    } else {
      failedMessages.add(entry.key);
      failedAttachments.addAll(
        identitiesForParent.map((item) => item.attachmentId),
      );
    }
  }
  return GroupSharedMediaBatchDeleteOutcome(
    deletedMessageIds: deletedMessages,
    failedMessageIds: failedMessages,
    deletedAttachmentIds: deletedAttachments,
    failedAttachmentIds: failedAttachments,
  );
}

class GroupSharedMediaBatchDeleteCoordinator {
  GroupSharedMediaBatchDeleteCoordinator({
    required this.messageRepository,
    required this.coordinator,
  });

  final GroupMessageRepository messageRepository;
  final GroupMediaDeleteForMeCoordinator coordinator;
  bool _inFlight = false;

  Future<GroupSharedMediaBatchDeleteOutcome> perform({
    required List<GroupSharedMediaIdentity> identities,
    required bool confirmed,
  }) async {
    if (!confirmed || _inFlight) return _emptyDeleteOutcome;
    _inFlight = true;
    try {
      return await deleteGroupSharedMediaSelection(
        identities: identities,
        messageRepository: messageRepository,
        coordinator: coordinator,
      );
    } finally {
      _inFlight = false;
    }
  }
}

const _emptyDeleteOutcome = GroupSharedMediaBatchDeleteOutcome(
  deletedMessageIds: {},
  failedMessageIds: {},
  deletedAttachmentIds: {},
  failedAttachmentIds: {},
);
