import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_service.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_backlog_retention_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_history_gap_repair.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_message_receipt.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_history_gap_repair_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_key_repair_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

const groupUndecryptablePlaceholderText = 'Message could not be decrypted.';

typedef RequestGroupHistoryRepairRange =
    Future<GroupHistoryRepairRangeResult> Function({
      required GroupInboxHistoryGap gap,
      required String sourcePeerId,
      int limit,
    });

/// Drains offline inboxes for all groups on startup.
///
/// For each group, retrieves stored messages from the relay inbox
/// and processes them as incoming messages. Uses cursor-based pagination
/// to ensure exactly-once delivery across pages. Groups are drained in
/// parallel so one slow relay request does not serially stall every other
/// group on startup or resume.
///
/// The first page is fetched synchronously (on the resume budget).
/// If [drainAllPages] is true (default), remaining pages are fetched
/// in the same call. Callers can set it to false and use
/// [drainGroupOfflineInboxContinuation] for background continuation.
Future<void> drainGroupOfflineInbox({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  MediaAttachmentRepository? mediaAttachmentRepo,
  ReactionRepository? reactionRepo,
  GroupMessageListener? groupMessageListener,
  GroupPendingKeyRepairRepository? pendingKeyRepairRepo,
  GroupHistoryGapRepairRepository? historyGapRepairRepo,
  RequestGroupKeyRepair? requestGroupKeyRepair,
  RequestGroupHistoryRepairRange? requestHistoryRepairRange,
  String? selfPeerId,
  bool drainAllPages = true,
  int pageSize = 50,
}) async {
  final drainStopwatch = Stopwatch()..start();
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_DRAIN_OFFLINE_INBOX_BEGIN',
    details: {},
  );

  final groups = await groupRepo.getAllGroups();

  await Future.wait(
    groups.map((group) async {
      final groupStopwatch = Stopwatch()..start();
      try {
        await _drainGroupInbox(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: group.id,
          mediaAttachmentRepo: mediaAttachmentRepo,
          reactionRepo: reactionRepo,
          groupMessageListener: groupMessageListener,
          pendingKeyRepairRepo: pendingKeyRepairRepo,
          historyGapRepairRepo: historyGapRepairRepo,
          requestGroupKeyRepair: requestGroupKeyRepair,
          requestHistoryRepairRange: requestHistoryRepairRange,
          selfPeerId: selfPeerId,
          drainAllPages: drainAllPages,
          pageSize: pageSize,
        );
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_DRAIN_OFFLINE_INBOX_GROUP_ERROR',
          details: {
            'groupId': group.id.length > 8
                ? group.id.substring(0, 8)
                : group.id,
            'error': e.toString(),
          },
        );
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_DRAIN_OFFLINE_INBOX_TIMING',
          details: {
            'scope': 'group',
            'elapsedMs': groupStopwatch.elapsedMilliseconds,
            'outcome': 'error',
            'groupId': group.id.length > 8
                ? group.id.substring(0, 8)
                : group.id,
          },
        );
      }
    }),
  );

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_DRAIN_OFFLINE_INBOX_DONE',
    details: {'groupCount': groups.length},
  );
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_DRAIN_OFFLINE_INBOX_TIMING',
    details: {
      'scope': 'batch',
      'elapsedMs': drainStopwatch.elapsedMilliseconds,
      'outcome': 'complete',
      'groupCount': groups.length,
      'drainAllPages': drainAllPages,
      'pageSize': pageSize,
    },
  );
}

Future<void> drainGroupOfflineInboxForGroup({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required String groupId,
  MediaAttachmentRepository? mediaAttachmentRepo,
  ReactionRepository? reactionRepo,
  GroupMessageListener? groupMessageListener,
  GroupPendingKeyRepairRepository? pendingKeyRepairRepo,
  GroupHistoryGapRepairRepository? historyGapRepairRepo,
  RequestGroupKeyRepair? requestGroupKeyRepair,
  RequestGroupHistoryRepairRange? requestHistoryRepairRange,
  String? selfPeerId,
  bool drainAllPages = true,
  int pageSize = 50,
}) async {
  final drainStopwatch = Stopwatch()..start();
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_DRAIN_OFFLINE_INBOX_SINGLE_BEGIN',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  try {
    await _drainGroupInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: groupId,
      mediaAttachmentRepo: mediaAttachmentRepo,
      reactionRepo: reactionRepo,
      groupMessageListener: groupMessageListener,
      pendingKeyRepairRepo: pendingKeyRepairRepo,
      historyGapRepairRepo: historyGapRepairRepo,
      requestGroupKeyRepair: requestGroupKeyRepair,
      requestHistoryRepairRange: requestHistoryRepairRange,
      selfPeerId: selfPeerId,
      drainAllPages: drainAllPages,
      pageSize: pageSize,
    );

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_DRAIN_OFFLINE_INBOX_SINGLE_DONE',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_DRAIN_OFFLINE_INBOX_TIMING',
      details: {
        'scope': 'single',
        'elapsedMs': drainStopwatch.elapsedMilliseconds,
        'outcome': 'complete',
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'drainAllPages': drainAllPages,
        'pageSize': pageSize,
      },
    );
  } catch (_) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_DRAIN_OFFLINE_INBOX_TIMING',
      details: {
        'scope': 'single',
        'elapsedMs': drainStopwatch.elapsedMilliseconds,
        'outcome': 'error',
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
    rethrow;
  }
}

/// Drains a single group's offline inbox using cursor-based pagination.
///
/// If a cursor is returned by the bridge, fetches subsequent pages until
/// no more messages are available (or [drainAllPages] is false for the
/// first-page-only path).
Future<void> _drainGroupInbox({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required String groupId,
  MediaAttachmentRepository? mediaAttachmentRepo,
  ReactionRepository? reactionRepo,
  GroupMessageListener? groupMessageListener,
  GroupPendingKeyRepairRepository? pendingKeyRepairRepo,
  GroupHistoryGapRepairRepository? historyGapRepairRepo,
  RequestGroupKeyRepair? requestGroupKeyRepair,
  RequestGroupHistoryRepairRange? requestHistoryRepairRange,
  String? selfPeerId,
  bool drainAllPages = true,
  int pageSize = 50,
}) async {
  final drainStopwatch = Stopwatch()..start();
  final retentionCutoff = groupBacklogRetentionCutoff(DateTime.now().toUtc());
  String cursor = (await msgRepo.getInboxCursor(groupId)) ?? '';
  int totalMessages = 0;
  var pageCount = 0;
  DateTime? latestExpiredBacklogAt;
  DateTime? latestRetainedBacklogAt;
  var sawTimestampedRetentionPayload = false;

  do {
    final result = await callGroupInboxRetrieveWithCursor(
      bridge,
      groupId,
      cursor,
      pageSize,
    );

    final messages = result.messages;
    final nextCursor = result.cursor;

    final pageReceipts = <GroupMessageReceipt>[];
    final pageReadMessageIds = <String>[];
    var stopGroupDrain = false;
    try {
      await msgRepo.runInboxPageTransaction(
        groupId: groupId,
        nextCursor: nextCursor,
        receipts: pageReceipts,
        markReadMessageIds: pageReadMessageIds,
        apply: (transactionMsgRepo) async {
          for (final msg in messages) {
            Map<String, dynamic> payload;
            try {
              payload = await decodeInboxMessage(
                bridge,
                groupRepo,
                msg,
                groupId,
              );
            } catch (e) {
              final allowDeletedGroupPlaceholder =
                  e is GroupOfflineReplaySignatureException &&
                  await _isUnknownSenderForDeletedLocalGroup(
                    groupRepo: groupRepo,
                    groupId: groupId,
                    error: e,
                  );
              if (e is GroupOfflineReplaySignatureException &&
                  !allowDeletedGroupPlaceholder) {
                emitFlowEvent(
                  layer: 'FL',
                  event: 'GROUP_DRAIN_OFFLINE_INBOX_REPLAY_SIGNATURE_REJECTED',
                  details: {
                    'groupId': groupId.length > 8
                        ? groupId.substring(0, 8)
                        : groupId,
                    'error': e.reason,
                  },
                );
                rethrow;
              }

              var placeholderSaved = false;
              if (_isMissingGroupReplayKeyError(e) &&
                  pendingKeyRepairRepo != null) {
                final replayEnvelope = _tryDecodeReplayEnvelope(msg['message']);
                if (replayEnvelope != null) {
                  placeholderSaved =
                      await queueMissingGroupReplayKeyRepairFromEnvelope(
                        pendingKeyRepairRepo: pendingKeyRepairRepo,
                        msgRepo: transactionMsgRepo,
                        groupId: groupId,
                        relayEnvelope: msg,
                        replayEnvelope: replayEnvelope,
                        requestGroupKeyRepair:
                            requestGroupKeyRepair ?? emitGroupKeyRepairRequest,
                      );
                }
              }
              if (!placeholderSaved) {
                placeholderSaved =
                    await _persistUndecryptablePlaceholderFromEnvelope(
                      msgRepo: transactionMsgRepo,
                      groupId: groupId,
                      envelope: msg,
                      error: e,
                      allowDeletedGroupUnknownSender:
                          allowDeletedGroupPlaceholder,
                    );
              }
              emitFlowEvent(
                layer: 'FL',
                event: 'GROUP_DRAIN_OFFLINE_INBOX_DECODE_SKIPPED',
                details: {
                  'groupId': groupId.length > 8
                      ? groupId.substring(0, 8)
                      : groupId,
                  'error': e.toString(),
                  'placeholderSaved': placeholderSaved,
                },
              );
              continue;
            }
            final text = payload['text'] as String? ?? '';
            final timestamp =
                payload['timestamp'] as String? ??
                DateTime.now().toUtc().toIso8601String();
            final parsedTimestamp = _tryParseUtcTimestamp(timestamp);
            final isSystemPayload = text.startsWith('{"__sys":');

            if (!isSystemPayload && parsedTimestamp != null) {
              sawTimestampedRetentionPayload = true;
              if (parsedTimestamp.isBefore(retentionCutoff)) {
                latestExpiredBacklogAt = _latestTimestamp(
                  latestExpiredBacklogAt,
                  parsedTimestamp,
                );
                continue;
              }
              latestRetainedBacklogAt = _latestTimestamp(
                latestRetainedBacklogAt,
                parsedTimestamp,
              );
            }

            // Route by type: group_reaction payloads are handled separately.
            if (payload['type'] == 'group_reaction' && reactionRepo != null) {
              final reactionJson = payload['reaction'] as String? ?? '';
              if (reactionJson.isNotEmpty) {
                await handleIncomingGroupReaction(
                  groupRepo: groupRepo,
                  reactionRepo: reactionRepo,
                  groupId: groupId,
                  senderId:
                      payload['senderId'] as String? ??
                      (msg['from'] as String? ?? ''),
                  senderDeviceId: payload['senderDeviceId'] as String?,
                  transportPeerId:
                      payload['transportPeerId'] as String? ??
                      msg['from'] as String?,
                  reactionJson: reactionJson,
                );
              }
              continue;
            }

            final mediaRaw = payload['media'] as List<dynamic>?;
            final media = mediaRaw?.cast<Map<String, dynamic>>();
            final resolvedGroupId = payload['groupId'] as String? ?? groupId;
            final transportSenderId = msg['from'] as String? ?? '';
            final senderId =
                payload['senderId'] as String? ??
                (msg['from'] as String? ?? '');
            final payloadTransportPeerId =
                payload['transportPeerId'] as String?;
            final senderDeviceId = payload['senderDeviceId'] as String?;
            final senderUsername = payload['senderUsername'] as String? ?? '';
            final keyEpoch = payload['keyEpoch'] as int? ?? 0;
            if (payloadTransportPeerId != null &&
                payloadTransportPeerId.isNotEmpty &&
                transportSenderId.isNotEmpty &&
                payloadTransportPeerId != transportSenderId) {
              emitFlowEvent(
                layer: 'FL',
                event: 'GROUP_DRAIN_OFFLINE_INBOX_TRANSPORT_MISMATCH',
                details: {
                  'groupId': resolvedGroupId.length > 8
                      ? resolvedGroupId.substring(0, 8)
                      : resolvedGroupId,
                },
              );
              continue;
            }
            final effectiveTransportPeerId =
                payloadTransportPeerId?.isNotEmpty == true
                ? payloadTransportPeerId!
                : transportSenderId;

            if (groupMessageListener != null && text.startsWith('{"__sys":')) {
              await groupMessageListener.handleReplayEnvelope(
                {
                  'groupId': resolvedGroupId,
                  'senderId': transportSenderId.isNotEmpty
                      ? transportSenderId
                      : senderId,
                  'senderUsername': senderUsername,
                  'keyEpoch': keyEpoch,
                  'text': text,
                  'timestamp': timestamp,
                  if (effectiveTransportPeerId.isNotEmpty)
                    'transportPeerId': effectiveTransportPeerId,
                  if (senderDeviceId != null && senderDeviceId.isNotEmpty)
                    'senderDeviceId': senderDeviceId,
                  if (payload['messageId'] is String)
                    'messageId': payload['messageId'],
                  if (payload['quotedMessageId'] is String)
                    'quotedMessageId': payload['quotedMessageId'],
                  if (media != null) 'media': media,
                },
                msgRepoOverride: transactionMsgRepo,
                rethrowOnError: true,
              );

              if (await groupRepo.getGroup(resolvedGroupId) == null) {
                emitFlowEvent(
                  layer: 'FL',
                  event: 'GROUP_DRAIN_OFFLINE_INBOX_STOP_GROUP_REMOVED',
                  details: {
                    'groupId': resolvedGroupId.length > 8
                        ? resolvedGroupId.substring(0, 8)
                        : resolvedGroupId,
                  },
                );
                stopGroupDrain = true;
                throw const _GroupRemovedDuringDrain();
              }
              continue;
            }

            if (groupMessageListener != null) {
              await groupMessageListener.handleReplayEnvelope(
                {
                  'groupId': resolvedGroupId,
                  'senderId': senderId,
                  'senderUsername': senderUsername,
                  'keyEpoch': keyEpoch,
                  'text': text,
                  'timestamp': timestamp,
                  if (effectiveTransportPeerId.isNotEmpty)
                    'transportPeerId': effectiveTransportPeerId,
                  if (senderDeviceId != null && senderDeviceId.isNotEmpty)
                    'senderDeviceId': senderDeviceId,
                  if (payload['messageId'] is String)
                    'messageId': payload['messageId'],
                  if (payload['quotedMessageId'] is String)
                    'quotedMessageId': payload['quotedMessageId'],
                  if (media != null) 'media': media,
                },
                msgRepoOverride: transactionMsgRepo,
                rethrowOnError: true,
              );
              final payloadReceipts = _receiptsFromPayload(
                payload,
                groupId: resolvedGroupId,
              );
              pageReceipts.addAll(payloadReceipts);
              pageReadMessageIds.addAll(
                _localReadReceiptMessageIds(
                  payloadReceipts,
                  localPeerId: selfPeerId,
                ),
              );
              continue;
            }

            final persistedMessage = await handleIncomingGroupMessage(
              groupRepo: groupRepo,
              msgRepo: transactionMsgRepo,
              groupId: resolvedGroupId,
              senderId: senderId,
              senderUsername: senderUsername,
              keyEpoch: keyEpoch,
              text: text,
              timestamp: timestamp,
              transportPeerId: effectiveTransportPeerId.isNotEmpty
                  ? effectiveTransportPeerId
                  : null,
              senderDeviceId: senderDeviceId,
              messageId: payload['messageId'] as String?,
              quotedMessageId: payload['quotedMessageId'] as String?,
              media: media,
              mediaAttachmentRepo: mediaAttachmentRepo,
            );
            if (persistedMessage != null) {
              final deliveredReceipts = _receiptsForPersistedInboxMessage(
                persistedMessage,
                localPeerId: selfPeerId,
              );
              pageReceipts.addAll(deliveredReceipts);
            }
            final payloadReceipts = _receiptsFromPayload(
              payload,
              groupId: resolvedGroupId,
            );
            pageReceipts.addAll(payloadReceipts);
            pageReadMessageIds.addAll(
              _localReadReceiptMessageIds(
                payloadReceipts,
                localPeerId: selfPeerId,
              ),
            );
          }

          if (result.historyGaps.isNotEmpty && historyGapRepairRepo != null) {
            await _repairHistoryGapsFromPage(
              bridge: bridge,
              groupRepo: groupRepo,
              msgRepo: transactionMsgRepo,
              groupId: groupId,
              gaps: result.historyGaps,
              historyGapRepairRepo: historyGapRepairRepo,
              requestHistoryRepairRange:
                  requestHistoryRepairRange ??
                  ({
                    required GroupInboxHistoryGap gap,
                    required String sourcePeerId,
                    int limit = 50,
                  }) => callGroupHistoryRepairRange(
                    bridge,
                    gap: gap,
                    sourcePeerId: sourcePeerId,
                    limit: limit,
                  ),
              groupMessageListener: groupMessageListener,
              mediaAttachmentRepo: mediaAttachmentRepo,
              pageSize: pageSize,
              selfPeerId: selfPeerId,
            );
          }
        },
      );
    } on _GroupRemovedDuringDrain {
      return;
    }
    if (stopGroupDrain) return;

    totalMessages += messages.length;
    pageCount++;
    cursor = nextCursor;

    // If caller only wants the first page, stop here.
    if (!drainAllPages && cursor.isNotEmpty) {
      await _persistRetentionState(
        groupRepo: groupRepo,
        groupId: groupId,
        sawTimestampedRetentionPayload: sawTimestampedRetentionPayload,
        latestExpiredBacklogAt: latestExpiredBacklogAt,
        latestRetainedBacklogAt: latestRetainedBacklogAt,
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_DRAIN_OFFLINE_INBOX_FIRST_PAGE_DONE',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'messageCount': totalMessages,
          'hasMore': true,
          'nextCursor': cursor.length > 8 ? cursor.substring(0, 8) : cursor,
        },
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_DRAIN_OFFLINE_INBOX_TIMING',
        details: {
          'scope': 'group',
          'elapsedMs': drainStopwatch.elapsedMilliseconds,
          'outcome': 'first_page_complete',
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'messageCount': totalMessages,
          'pageCount': pageCount,
          'drainAllPages': false,
        },
      );
      return;
    }
  } while (cursor.isNotEmpty);

  await _persistRetentionState(
    groupRepo: groupRepo,
    groupId: groupId,
    sawTimestampedRetentionPayload: sawTimestampedRetentionPayload,
    latestExpiredBacklogAt: latestExpiredBacklogAt,
    latestRetainedBacklogAt: latestRetainedBacklogAt,
  );

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_DRAIN_OFFLINE_INBOX_GROUP_DONE',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'messageCount': totalMessages,
    },
  );
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_DRAIN_OFFLINE_INBOX_TIMING',
    details: {
      'scope': 'group',
      'elapsedMs': drainStopwatch.elapsedMilliseconds,
      'outcome': 'complete',
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'messageCount': totalMessages,
      'pageCount': pageCount,
      'drainAllPages': drainAllPages,
    },
  );
}

Future<void> _repairHistoryGapsFromPage({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required String groupId,
  required List<GroupInboxHistoryGap> gaps,
  required GroupHistoryGapRepairRepository historyGapRepairRepo,
  required RequestGroupHistoryRepairRange requestHistoryRepairRange,
  GroupMessageListener? groupMessageListener,
  MediaAttachmentRepository? mediaAttachmentRepo,
  required int pageSize,
  String? selfPeerId,
}) async {
  final members = await groupRepo.getMembers(groupId);
  final authorizedPeerIds = members.map((member) => member.peerId).toSet();
  final normalizedSelfPeerId = selfPeerId?.trim();

  for (final gap in gaps.where((gap) => gap.groupId == groupId)) {
    final now = DateTime.now().toUtc();
    await historyGapRepairRepo.upsertDetected(
      GroupHistoryGapRepair(
        groupId: gap.groupId,
        gapId: gap.gapId,
        missingAfterMessageId: gap.missingAfterMessageId,
        missingBeforeMessageId: gap.missingBeforeMessageId,
        expectedRangeHash: gap.expectedRangeHash,
        expectedHeadMessageId: gap.expectedHeadMessageId,
        candidateSourcePeerIds: gap.candidateSourcePeerIds,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await historyGapRepairRepo.markRepairing(
      groupId: gap.groupId,
      gapId: gap.gapId,
    );

    final authorizedSources = <String>[];
    for (final sourcePeerId in gap.candidateSourcePeerIds) {
      if (!authorizedPeerIds.contains(sourcePeerId)) {
        await historyGapRepairRepo.recordAttempt(
          groupId: gap.groupId,
          gapId: gap.gapId,
          sourcePeerId: sourcePeerId,
          lastError: 'unauthorized_source',
        );
        continue;
      }
      if (normalizedSelfPeerId != null &&
          normalizedSelfPeerId.isNotEmpty &&
          sourcePeerId == normalizedSelfPeerId) {
        await historyGapRepairRepo.recordAttempt(
          groupId: gap.groupId,
          gapId: gap.gapId,
          sourcePeerId: sourcePeerId,
          lastError: 'local_source_skipped',
        );
        continue;
      }
      if (!authorizedSources.contains(sourcePeerId)) {
        authorizedSources.add(sourcePeerId);
      }
    }

    if (authorizedSources.isEmpty) {
      await historyGapRepairRepo.markFailed(
        groupId: gap.groupId,
        gapId: gap.gapId,
        reason: 'no_authorized_sources',
      );
      continue;
    }

    var repaired = false;
    var lastError = 'no_matching_source';
    for (final sourcePeerId in authorizedSources) {
      await historyGapRepairRepo.recordAttempt(
        groupId: gap.groupId,
        gapId: gap.gapId,
        sourcePeerId: sourcePeerId,
        lastError: null,
      );

      late final GroupHistoryRepairRangeResult repairResult;
      try {
        repairResult = await requestHistoryRepairRange(
          gap: gap,
          sourcePeerId: sourcePeerId,
          limit: pageSize,
        );
      } catch (e) {
        lastError = 'request_failed';
        await historyGapRepairRepo.recordAttempt(
          groupId: gap.groupId,
          gapId: gap.gapId,
          sourcePeerId: sourcePeerId,
          lastError: lastError,
        );
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_HISTORY_GAP_REPAIR_SOURCE_REJECTED',
          details: {
            'groupId': _safeId(groupId),
            'gapId': _safeId(gap.gapId),
            'sourcePeerId': _safeId(sourcePeerId),
            'reason': e.toString(),
          },
        );
        continue;
      }

      final validationError = _validateHistoryRepairResult(
        gap: gap,
        expectedSourcePeerId: sourcePeerId,
        result: repairResult,
      );
      if (validationError != null) {
        lastError = validationError;
        await historyGapRepairRepo.recordAttempt(
          groupId: gap.groupId,
          gapId: gap.gapId,
          sourcePeerId: sourcePeerId,
          lastError: validationError,
        );
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_HISTORY_GAP_REPAIR_SOURCE_REJECTED',
          details: {
            'groupId': _safeId(groupId),
            'gapId': _safeId(gap.gapId),
            'sourcePeerId': _safeId(sourcePeerId),
            'reason': validationError,
          },
        );
        continue;
      }

      final repairedMessageIds = await _applyRepairedHistoryMessages(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: groupId,
        messages: repairResult.messages,
        groupMessageListener: groupMessageListener,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );

      if (repairedMessageIds.length != repairResult.messages.length) {
        lastError = 'application_rejected_message';
        await historyGapRepairRepo.recordAttempt(
          groupId: gap.groupId,
          gapId: gap.gapId,
          sourcePeerId: sourcePeerId,
          lastError: lastError,
        );
        continue;
      }

      await historyGapRepairRepo.markRepaired(
        groupId: gap.groupId,
        gapId: gap.gapId,
        repairedMessageIds: repairedMessageIds,
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_HISTORY_GAP_REPAIR_DONE',
        details: {
          'groupId': _safeId(groupId),
          'gapId': _safeId(gap.gapId),
          'sourcePeerId': _safeId(sourcePeerId),
          'messageCount': repairedMessageIds.length,
        },
      );
      repaired = true;
      break;
    }

    if (!repaired) {
      await historyGapRepairRepo.markFailed(
        groupId: gap.groupId,
        gapId: gap.gapId,
        reason: lastError,
      );
    }
  }
}

String? _validateHistoryRepairResult({
  required GroupInboxHistoryGap gap,
  required String expectedSourcePeerId,
  required GroupHistoryRepairRangeResult result,
}) {
  if (result.groupId != gap.groupId) return 'group_mismatch';
  if (result.gapId != gap.gapId) return 'gap_mismatch';
  if (result.sourcePeerId != expectedSourcePeerId) return 'source_mismatch';
  if (result.messages.isEmpty) return 'empty_range';
  if (result.headMessageId != gap.expectedHeadMessageId) {
    return 'head_mismatch';
  }
  final computedHash = computeGroupHistoryRangeHash(result.messages);
  if (result.rangeHash != gap.expectedRangeHash ||
      computedHash != gap.expectedRangeHash) {
    return 'range_hash_mismatch';
  }
  return null;
}

Future<List<String>> _applyRepairedHistoryMessages({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required String groupId,
  required List<Map<String, dynamic>> messages,
  GroupMessageListener? groupMessageListener,
  MediaAttachmentRepository? mediaAttachmentRepo,
}) async {
  final appliedMessageIds = <String>[];

  for (final msg in messages) {
    late final Map<String, dynamic> payload;
    try {
      payload = await decodeInboxMessage(bridge, groupRepo, msg, groupId);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_HISTORY_GAP_REPAIR_MESSAGE_REJECTED',
        details: {'groupId': _safeId(groupId), 'error': e.toString()},
      );
      return const <String>[];
    }
    if (payload['type'] == 'group_reaction') {
      return const <String>[];
    }
    final text = payload['text'] as String? ?? '';
    final timestamp =
        payload['timestamp'] as String? ??
        DateTime.now().toUtc().toIso8601String();
    final mediaRaw = payload['media'] as List<dynamic>?;
    final media = mediaRaw?.cast<Map<String, dynamic>>();
    final resolvedGroupId = payload['groupId'] as String? ?? groupId;
    final transportSenderId = msg['from'] as String? ?? '';
    final senderId =
        payload['senderId'] as String? ?? (msg['from'] as String? ?? '');
    final payloadTransportPeerId = payload['transportPeerId'] as String?;
    final senderDeviceId = payload['senderDeviceId'] as String?;
    final senderUsername = payload['senderUsername'] as String? ?? '';
    final keyEpoch = payload['keyEpoch'] as int? ?? 0;
    if (payloadTransportPeerId != null &&
        payloadTransportPeerId.isNotEmpty &&
        transportSenderId.isNotEmpty &&
        payloadTransportPeerId != transportSenderId) {
      return const <String>[];
    }
    final effectiveTransportPeerId = payloadTransportPeerId?.isNotEmpty == true
        ? payloadTransportPeerId!
        : transportSenderId;
    final messageId = payload['messageId'] as String?;
    if (messageId == null || messageId.isEmpty) {
      return const <String>[];
    }

    if (groupMessageListener != null) {
      await groupMessageListener.handleReplayEnvelope({
        'groupId': resolvedGroupId,
        'senderId': text.startsWith('{"__sys":') && transportSenderId.isNotEmpty
            ? transportSenderId
            : senderId,
        'senderUsername': senderUsername,
        'keyEpoch': keyEpoch,
        'text': text,
        'timestamp': timestamp,
        if (effectiveTransportPeerId.isNotEmpty)
          'transportPeerId': effectiveTransportPeerId,
        if (senderDeviceId != null && senderDeviceId.isNotEmpty)
          'senderDeviceId': senderDeviceId,
        'messageId': messageId,
        if (payload['quotedMessageId'] is String)
          'quotedMessageId': payload['quotedMessageId'],
        if (media != null) 'media': media,
      }, msgRepoOverride: msgRepo);
    } else {
      await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: resolvedGroupId,
        senderId: senderId,
        senderUsername: senderUsername,
        keyEpoch: keyEpoch,
        text: text,
        timestamp: timestamp,
        transportPeerId: effectiveTransportPeerId.isNotEmpty
            ? effectiveTransportPeerId
            : null,
        senderDeviceId: senderDeviceId,
        messageId: messageId,
        quotedMessageId: payload['quotedMessageId'] as String?,
        media: media,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );
    }

    final stored = await msgRepo.getMessage(messageId);
    if (stored == null) {
      return const <String>[];
    }
    appliedMessageIds.add(messageId);
  }

  return appliedMessageIds;
}

String computeGroupHistoryRangeHash(List<Map<String, dynamic>> messages) {
  final canonical = messages
      .map((message) => jsonEncode(_canonicalizeJson(message)))
      .join('\n');
  return sha256.convert(utf8.encode(canonical)).toString();
}

Object? _canonicalizeJson(Object? value) {
  if (value is Map) {
    final sortedKeys = value.keys.map((key) => key.toString()).toList()..sort();
    return {for (final key in sortedKeys) key: _canonicalizeJson(value[key])};
  }
  if (value is List) {
    return value.map(_canonicalizeJson).toList(growable: false);
  }
  return value;
}

String _safeId(String id) => id.length > 8 ? id.substring(0, 8) : id;

/// Decodes an inbox message from the relay's envelope format.
///
/// The relay returns `{from, message, timestamp}` where `message` is a
/// JSON-encoded signed `group_offline_replay` envelope. Legacy decoded maps,
/// pre-decoded sender maps, and fallback relay strings are rejected here so an
/// unsigned replay cannot mutate messages, reactions, system state, cursors, or
/// receipts through normal offline drain or history repair.
Future<Map<String, dynamic>> decodeInboxMessage(
  Bridge bridge,
  GroupRepository groupRepo,
  Map<String, dynamic> envelope,
  String fallbackGroupId,
) async {
  // If the envelope contains a `message` string, decode it.
  final messageStr = envelope['message'];
  if (messageStr is String && messageStr.isNotEmpty) {
    Map<String, dynamic>? decodedMessage;
    try {
      final decoded = jsonDecode(messageStr);
      if (decoded is Map) {
        decodedMessage = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      decodedMessage = null;
    }

    if (decodedMessage != null) {
      if (isGroupOfflineReplayEnvelope(decodedMessage)) {
        final payloadType =
            decodedMessage['payloadType'] as String? ??
            groupOfflineReplayPayloadTypeMessage;
        final plaintext = await decryptGroupOfflineReplayEnvelope(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: fallbackGroupId,
          envelope: decodedMessage,
          expectedRelayPeerId: envelope['from'] as String?,
        );

        if (payloadType == groupOfflineReplayPayloadTypeReaction) {
          return {
            'type': groupOfflineReplayPayloadTypeReaction,
            'reaction': plaintext,
            'senderId': decodedMessage['senderPeerId'],
            'senderDeviceId': decodedMessage['senderDeviceId'],
            'transportPeerId': decodedMessage['senderTransportPeerId'],
          };
        }

        return Map<String, dynamic>.from(
          jsonDecode(plaintext) as Map<String, dynamic>,
        );
      }

      throw GroupOfflineReplaySignatureException('unsigned_relay_payload');
    }
  }

  if (envelope.containsKey('senderId')) {
    throw GroupOfflineReplaySignatureException('unsigned_decoded_payload');
  }

  throw GroupOfflineReplaySignatureException('unsigned_relay_fallback');
}

Future<bool> _persistUndecryptablePlaceholderFromEnvelope({
  required GroupMessageRepository msgRepo,
  required String groupId,
  required Map<String, dynamic> envelope,
  required Object error,
  bool allowDeletedGroupUnknownSender = false,
}) async {
  if (!_isMissingGroupReplayKeyError(error) &&
      !(allowDeletedGroupUnknownSender &&
          error is GroupOfflineReplaySignatureException &&
          error.reason == 'unknown_sender')) {
    return false;
  }

  final replayEnvelope = _tryDecodeReplayEnvelope(envelope['message']);
  if (replayEnvelope == null || !isGroupOfflineReplayEnvelope(replayEnvelope)) {
    return false;
  }

  final payloadType =
      replayEnvelope['payloadType'] as String? ??
      groupOfflineReplayPayloadTypeMessage;
  if (payloadType != groupOfflineReplayPayloadTypeMessage) {
    return false;
  }

  final messageId = (replayEnvelope['messageId'] as String?)?.trim();
  if (messageId == null || messageId.isEmpty) {
    return false;
  }

  final existing = await msgRepo.getMessage(messageId);
  if (existing != null) {
    return true;
  }

  final keyEpoch = replayEnvelope['keyEpoch'] as int;
  final timestamp =
      _tryParseRelayTimestamp(envelope['timestamp']) ?? DateTime.now().toUtc();
  final senderPeerId = (envelope['from'] as String?)?.trim();

  await msgRepo.saveMessage(
    GroupMessage(
      id: messageId,
      groupId: groupId,
      senderPeerId: senderPeerId == null || senderPeerId.isEmpty
          ? 'unknown'
          : senderPeerId,
      transportPeerId: senderPeerId == null || senderPeerId.isEmpty
          ? null
          : senderPeerId,
      senderUsername: null,
      text: groupUndecryptablePlaceholderText,
      timestamp: timestamp,
      keyGeneration: keyEpoch,
      status: 'undecryptable',
      isIncoming: true,
      createdAt: DateTime.now().toUtc(),
    ),
  );

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_DRAIN_OFFLINE_INBOX_UNDECRYPTABLE_PLACEHOLDER_SAVED',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'messageId': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
      'keyEpoch': keyEpoch,
    },
  );

  return true;
}

bool _isMissingGroupReplayKeyError(Object error) {
  return error.toString().contains('Missing group replay key');
}

Future<bool> _isUnknownSenderForDeletedLocalGroup({
  required GroupRepository groupRepo,
  required String groupId,
  required GroupOfflineReplaySignatureException error,
}) async {
  if (error.reason != 'unknown_sender') return false;
  return await groupRepo.getGroup(groupId) == null;
}

Map<String, dynamic>? _tryDecodeReplayEnvelope(Object? rawMessage) {
  if (rawMessage is! String || rawMessage.isEmpty) return null;
  try {
    final decoded = jsonDecode(rawMessage);
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
  } catch (_) {
    return null;
  }
  return null;
}

DateTime? _tryParseRelayTimestamp(Object? rawTimestamp) {
  if (rawTimestamp is int) {
    return DateTime.fromMillisecondsSinceEpoch(rawTimestamp, isUtc: true);
  }
  if (rawTimestamp is double) {
    return DateTime.fromMillisecondsSinceEpoch(
      rawTimestamp.round(),
      isUtc: true,
    );
  }
  if (rawTimestamp is String) {
    final millis = int.tryParse(rawTimestamp);
    if (millis != null) {
      return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    }
    return DateTime.tryParse(rawTimestamp)?.toUtc();
  }
  return null;
}

Future<void> _persistRetentionState({
  required GroupRepository groupRepo,
  required String groupId,
  required bool sawTimestampedRetentionPayload,
  required DateTime? latestExpiredBacklogAt,
  required DateTime? latestRetainedBacklogAt,
}) async {
  if (!sawTimestampedRetentionPayload) return;

  final group = await groupRepo.getGroup(groupId);
  if (group == null) return;

  await groupRepo.updateGroup(
    group.copyWith(
      lastBacklogExpiredAt: latestExpiredBacklogAt,
      lastBacklogRetainedAt: latestRetainedBacklogAt,
    ),
  );
}

DateTime? _tryParseUtcTimestamp(String rawTimestamp) {
  try {
    return DateTime.parse(rawTimestamp).toUtc();
  } catch (_) {
    return null;
  }
}

DateTime? _latestTimestamp(DateTime? current, DateTime candidate) {
  if (current == null || candidate.isAfter(current)) {
    return candidate;
  }
  return current;
}

List<GroupMessageReceipt> _receiptsForPersistedInboxMessage(
  GroupMessage message, {
  required String? localPeerId,
}) {
  final memberPeerId = localPeerId?.trim();
  if (memberPeerId == null || memberPeerId.isEmpty || !message.isIncoming) {
    return const [];
  }
  final now = DateTime.now().toUtc();
  return [
    GroupMessageReceipt(
      groupId: message.groupId,
      messageId: message.id,
      receiptType: groupMessageReceiptTypeDelivered,
      memberPeerId: memberPeerId,
      receiptAt: now,
      sourceEventId: 'local-delivered:${message.groupId}:${message.id}',
      createdAt: now,
      updatedAt: now,
    ),
  ];
}

List<GroupMessageReceipt> _receiptsFromPayload(
  Map<String, dynamic> payload, {
  required String groupId,
}) {
  final rawReceipts = <Object?>[];
  if (payload['receipt'] != null) {
    rawReceipts.add(payload['receipt']);
  }
  final rawReceiptList = payload['receipts'];
  if (rawReceiptList is List) {
    rawReceipts.addAll(rawReceiptList);
  }
  if (rawReceipts.isEmpty) return const [];

  final now = DateTime.now().toUtc();
  final defaultMessageId = payload['messageId'] as String?;
  final receipts = <GroupMessageReceipt>[];
  for (final raw in rawReceipts) {
    if (raw is! Map) continue;
    final receipt = Map<String, dynamic>.from(raw);
    final messageId =
        (receipt['messageId'] as String?)?.trim() ?? defaultMessageId?.trim();
    final memberPeerId =
        (receipt['memberPeerId'] as String?)?.trim() ??
        (receipt['peerId'] as String?)?.trim() ??
        (receipt['from'] as String?)?.trim();
    final receiptType =
        (receipt['receiptType'] as String?)?.trim() ??
        (receipt['type'] as String?)?.trim() ??
        groupMessageReceiptTypeDelivered;
    if (messageId == null ||
        messageId.isEmpty ||
        memberPeerId == null ||
        memberPeerId.isEmpty ||
        !_isSupportedReceiptType(receiptType)) {
      continue;
    }

    final receiptAt =
        DateTime.tryParse(receipt['receiptAt'] as String? ?? '')?.toUtc() ??
        DateTime.tryParse(receipt['timestamp'] as String? ?? '')?.toUtc() ??
        now;
    receipts.add(
      GroupMessageReceipt(
        groupId: groupId,
        messageId: messageId,
        receiptType: receiptType,
        memberPeerId: memberPeerId,
        senderDeviceId: (receipt['senderDeviceId'] as String?)?.trim(),
        receiptAt: receiptAt,
        sourceEventId: (receipt['sourceEventId'] as String?)?.trim(),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
  return receipts;
}

bool _isSupportedReceiptType(String receiptType) {
  return receiptType == groupMessageReceiptTypeDelivered ||
      receiptType == groupMessageReceiptTypeRead;
}

List<String> _localReadReceiptMessageIds(
  Iterable<GroupMessageReceipt> receipts, {
  required String? localPeerId,
}) {
  final peerId = localPeerId?.trim();
  if (peerId == null || peerId.isEmpty) return const [];
  return receipts
      .where(
        (receipt) =>
            receipt.memberPeerId == peerId &&
            receipt.receiptType == groupMessageReceiptTypeRead,
      )
      .map((receipt) => receipt.messageId)
      .toSet()
      .toList(growable: false);
}

class _GroupRemovedDuringDrain implements Exception {
  const _GroupRemovedDuringDrain();
}
