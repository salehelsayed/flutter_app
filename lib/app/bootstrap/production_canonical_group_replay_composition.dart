import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_reaction_replay_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/protected_group_content_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/protected_group_reaction_target_db_helpers.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/core/services/protected_group_content_contract.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_key_update_listener.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_service.dart';
import 'package:flutter_app/features/groups/application/linked_group_bootstrap_service.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority_history.dart';
import 'package:flutter_app/features/groups/application/protected_group_content_receive.dart';
import 'package:flutter_app/features/groups/application/protected_group_content_reconciliation.dart';
import 'package:flutter_app/features/groups/application/protected_group_envelope.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

typedef LoadProductionLinkedInstallationAuthority =
    Future<LinkedInstallationAuthoritySnapshot> Function(
      String expectedAccountPeerId,
    );

typedef ApplyProductionProtectedSystemAuthorityReplay =
    Future<ProtectedGroupAuthorityApplyResult> Function(
      ProtectedGroupAuthorityControl control,
      Map<String, dynamic> replayData,
      VerifiedProtectedGroupAuthorityReplay authority,
    );

/// Shared protected-content authority support used by foreground and headless
/// replay. Keeping history verification and terminal reconciliation here makes
/// the two runtime shapes consult the same durable authority facts.
final class ProductionCanonicalProtectedGroupAuthoritySupport {
  const ProductionCanonicalProtectedGroupAuthoritySupport({
    required this.database,
    required this.bridge,
    required this.groupRepository,
  });

  final Database database;
  final Bridge bridge;
  final GroupRepository groupRepository;

  Future<ProtectedGroupContentAuthority?> loadContentAuthority(
    String groupId,
    GroupContentAuthorityVersion version,
  ) {
    return loadProtectedGroupContentAuthorityFromHistory(
      groupId: groupId,
      version: version,
      loadExact: ({required groupId, required phase, required eventId}) =>
          loadAuthenticatedGroupAuthorityProofFromEventLog(
            loadRow: ({required groupId, required sourceEventId}) =>
                dbLoadGroupEventLogEntryExact(
                  database,
                  groupId: groupId,
                  sourceEventId: sourceEventId,
                ),
            groupId: groupId,
            phase: phase,
            eventId: eventId,
            verify: ({required publicKey, required data, required signature}) =>
                callVerifyPayload(
                  bridge: bridge,
                  publicKey: publicKey,
                  data: data,
                  signature: signature,
                ),
          ),
      loadCompleteRows:
          ({
            required groupId,
            required eventType,
            afterSourceTimestamp,
            afterSourceEventId,
            throughSourceTimestamp,
            required limit,
          }) => dbLoadGroupEventLogTypePage(
            database,
            groupId: groupId,
            eventType: eventType,
            afterSourceTimestamp: afterSourceTimestamp,
            afterSourceEventId: afterSourceEventId,
            throughSourceTimestamp: throughSourceTimestamp,
            newestFirst: true,
            limit: limit,
          ),
      loadGenesisRows:
          ({
            required groupId,
            required eventType,
            afterSourceTimestamp,
            afterSourceEventId,
            throughSourceTimestamp,
            required limit,
          }) => dbLoadGroupEventLogTypePage(
            database,
            groupId: groupId,
            eventType: eventType,
            afterSourceTimestamp: afterSourceTimestamp,
            afterSourceEventId: afterSourceEventId,
            throughSourceTimestamp: throughSourceTimestamp,
            newestFirst: true,
            limit: limit,
          ),
      verify: ({required publicKey, required data, required signature}) =>
          callVerifyPayload(
            bridge: bridge,
            publicKey: publicKey,
            data: data,
            signature: signature,
          ),
    );
  }

  Future<bool> reconcileCompletedContentAuthority(
    AuthenticatedGroupAuthorityProof authority, {
    bool allowDominatingProjection = false,
  }) => runGroupAuthorityPhaseIfNeeded(
    groupId: authority.groupId,
    authorityPhaseHeld: isGroupAuthorityPhaseHeld(authority.groupId),
    action: () => reconcileProtectedGroupContentForAuthority(
      db: database,
      groupRepository: groupRepository,
      authority: authority,
      allowDominatingProjection: allowDominatingProjection,
      terminalizePreparedContent:
          ({
            required txn,
            required groupId,
            required payloadType,
            required contentEventId,
            required ownerKind,
            required ownerId,
            required eventPayload,
            required terminalSourcePeerId,
            required terminalSourceEventId,
            required terminalSourceTimestamp,
            required terminalEventPayload,
          }) async {
            if (ownerId != contentEventId) return false;
            if (payloadType == groupOfflineReplayPayloadTypeMessage &&
                ownerKind == 'group_message') {
              final rows = await txn.query(
                'group_messages',
                where: 'id = ? AND group_id = ?',
                whereArgs: <Object?>[ownerId, groupId],
                limit: 1,
              );
              return rows.isNotEmpty &&
                  await dbTerminalizePreparedLocalGroupContentMessageIfExactInTransaction(
                    txn,
                    expected: rows.single,
                    preparedEventPayload: eventPayload,
                    terminalSourcePeerId: terminalSourcePeerId,
                    terminalSourceEventId: terminalSourceEventId,
                    terminalSourceTimestamp: terminalSourceTimestamp,
                    terminalEventPayload: terminalEventPayload,
                  );
            }
            if (payloadType == groupOfflineReplayPayloadTypeReaction &&
                ownerKind == 'group_reaction') {
              final rows = await txn.query(
                'group_reaction_replay_outbox',
                where: 'reaction_id = ? AND group_id = ?',
                whereArgs: <Object?>[ownerId, groupId],
                limit: 1,
              );
              return rows.isNotEmpty &&
                  await dbTerminalizePreparedLocalGroupReactionIfExactInTransaction(
                    txn,
                    expected: rows.single,
                    preparedEventPayload: eventPayload,
                    terminalSourcePeerId: terminalSourcePeerId,
                    terminalSourceEventId: terminalSourceEventId,
                    terminalSourceTimestamp: terminalSourceTimestamp,
                    terminalEventPayload: terminalEventPayload,
                  );
            }
            return false;
          },
      validateHistoricalAuthority:
          ({
            required groupId,
            required payloadType,
            required contentEventId,
            required eventAt,
            required authorityVersion,
            required logicalSenderPeerId,
            required senderDeviceId,
            required senderTransportPeerId,
            required senderPublicKey,
          }) async {
            final historical = await loadContentAuthority(
              groupId,
              authorityVersion,
            );
            return historical?.authorizesHistoricalContent(
                  payloadType: payloadType,
                  contentEventId: contentEventId,
                  eventAt: eventAt,
                  logicalSenderPeerId: logicalSenderPeerId,
                  senderDeviceId: senderDeviceId,
                  senderTransportPeerId: senderTransportPeerId,
                  senderPublicKey: senderPublicKey,
                ) ==
                true;
          },
    ),
  );

  Future<bool> hasUnfinishedContentAuthority(String groupId) {
    return hasPendingProtectedGroupContentAuthority(
      groupId: groupId,
      loadPreparedPage:
          ({afterSourceTimestamp, afterSourceEventId, required limit}) =>
              loadAuthenticatedGroupAuthorityProofPage(
                loadRows:
                    ({
                      required groupId,
                      required eventType,
                      afterSourceTimestamp,
                      afterSourceEventId,
                      throughSourceTimestamp,
                      required limit,
                    }) => dbLoadGroupEventLogTypePage(
                      database,
                      groupId: groupId,
                      eventType: eventType,
                      afterSourceTimestamp: afterSourceTimestamp,
                      afterSourceEventId: afterSourceEventId,
                      throughSourceTimestamp: throughSourceTimestamp,
                      newestFirst: true,
                      limit: limit,
                    ),
                groupId: groupId,
                phase: AuthenticatedGroupAuthorityPhase.prepared,
                verify:
                    ({required publicKey, required data, required signature}) =>
                        callVerifyPayload(
                          bridge: bridge,
                          publicKey: publicKey,
                          data: data,
                          signature: signature,
                        ),
                afterSourceTimestamp: afterSourceTimestamp,
                afterSourceEventId: afterSourceEventId,
                limit: limit,
              ),
      loadExactPhase: ({required phase, required eventId}) =>
          loadAuthenticatedGroupAuthorityProofFromEventLog(
            loadRow: ({required groupId, required sourceEventId}) =>
                dbLoadGroupEventLogEntryExact(
                  database,
                  groupId: groupId,
                  sourceEventId: sourceEventId,
                ),
            groupId: groupId,
            phase: phase,
            eventId: eventId,
            verify: ({required publicKey, required data, required signature}) =>
                callVerifyPayload(
                  bridge: bridge,
                  publicKey: publicKey,
                  data: data,
                  signature: signature,
                ),
          ),
      loadReconciliationRow: (authorityEventId) =>
          dbLoadGroupEventLogEntryExact(
            database,
            groupId: groupId,
            sourceEventId:
                protectedGroupContentReconciliationCompleteSourceEventId(
                  authorityEventId,
                ),
          ),
      repairCompletedAuthority: (authority) =>
          reconcileCompletedContentAuthority(
            authority,
            allowDominatingProjection: true,
          ),
    );
  }
}

Future<ProtectedGroupAuthorityApplyResult>
applyProductionCanonicalProtectedSystemAuthorityReplay({
  required ProtectedGroupAuthorityControl control,
  required Map<String, dynamic> replayData,
  required VerifiedProtectedGroupAuthorityReplay authority,
  required GroupRepository groupRepository,
  required GroupMessageListener groupMessageListener,
}) async {
  if (control == ProtectedGroupAuthorityControl.groupKeyUpdate ||
      !authority.authorizesSystemReplay(replayData)) {
    return ProtectedGroupAuthorityApplyResult.rejected;
  }
  try {
    await groupMessageListener.handleAuthenticatedAuthorityReplayEnvelope(
      replayData,
      authority: authority,
      rethrowOnError: true,
      membershipPhaseHeld: true,
    );
    final after = await protectedGroupAuthorityReplayConverged(
      control: control,
      replayData: replayData,
      groupRepository: groupRepository,
      requireMembershipVersion:
          control == ProtectedGroupAuthorityControl.memberAdd ||
          control == ProtectedGroupAuthorityControl.memberRole ||
          control == ProtectedGroupAuthorityControl.memberRemove,
      allowDominatingMembershipVersion: true,
    );
    return after == true
        ? ProtectedGroupAuthorityApplyResult.applied
        : ProtectedGroupAuthorityApplyResult.retryable;
  } on ProtectedGroupAuthorityReplaySuperseded {
    return ProtectedGroupAuthorityApplyResult.superseded;
  } catch (_) {
    return ProtectedGroupAuthorityApplyResult.retryable;
  }
}

/// The exact production classifier/handler chain for protected content,
/// bootstrap and authority envelopes. Both runtime shapes install [replay]
/// directly; neither owns a smaller headless-only state machine.
final class ProductionCanonicalProtectedGroupReplayComposition {
  const ProductionCanonicalProtectedGroupReplayComposition({
    required this.database,
    required this.bridge,
    required this.groupRepository,
    required this.groupMessageListener,
    required this.groupKeyUpdateListener,
    required this.authoritySupport,
    required this.loadIdentity,
    required this.loadLinkedAuthority,
    required this.applySystemAuthorityReplay,
    required this.retryPendingKeyRepairs,
  });

  final Database database;
  final Bridge bridge;
  final GroupRepository groupRepository;
  final GroupMessageListener groupMessageListener;
  final GroupKeyUpdateListener groupKeyUpdateListener;
  final ProductionCanonicalProtectedGroupAuthoritySupport authoritySupport;
  final Future<IdentityModel?> Function() loadIdentity;
  final LoadProductionLinkedInstallationAuthority loadLinkedAuthority;
  final ApplyProductionProtectedSystemAuthorityReplay
  applySystemAuthorityReplay;
  final Future<void> Function(GroupPendingKeyRepairRetryRequest request)
  retryPendingKeyRepairs;

  Future<ProtectedGroupReplayOutcome> replay(ChatMessage message) async {
    final identity = await loadIdentity();
    if (identity == null ||
        identity.mlKemPublicKey == null ||
        identity.mlKemSecretKey == null) {
      return (
        disposition: ProtectedGroupReplayDisposition.prerequisiteWaiting,
        reasonCode: 'linked_identity_unavailable',
        reasonDetail: null,
      );
    }
    final linkedAuthority = await loadLinkedAuthority(identity.peerId);
    Map<String, dynamic>? contentOuter;
    try {
      final decoded = jsonDecode(message.content);
      if (decoded is Map) contentOuter = Map<String, dynamic>.from(decoded);
    } catch (_) {
      contentOuter = null;
    }

    final contentClassification = classifyProtectedGroupContentWire(
      message.content,
    );
    if (contentClassification !=
        ProtectedGroupContentWireClassification.unrelated) {
      final contentGroupId = contentOuter?['groupId'];
      if (contentGroupId is String &&
          contentGroupId.isNotEmpty &&
          await authoritySupport.hasUnfinishedContentAuthority(
            contentGroupId,
          )) {
        return (
          disposition: ProtectedGroupReplayDisposition.prerequisiteWaiting,
          reasonCode: 'authority_reconciliation_pending',
          reasonDetail: null,
        );
      }
      final localTransportPeerId = linkedAuthority.isActiveLinkedSecondary
          ? linkedAuthority.credential!.transportPeerId
          : identity.peerId;
      final result = await handleProtectedGroupContentReplay(
        bridge: bridge,
        groupRepository: groupRepository,
        message: message,
        localLogicalPeerId: identity.peerId,
        localTransportPeerId: localTransportPeerId,
        loadAuthority: authoritySupport.loadContentAuthority,
        hasPendingAuthority: authoritySupport.hasUnfinishedContentAuthority,
        hasTerminal:
            ({
              required groupId,
              required payloadType,
              required contentEventId,
            }) => hasProtectedGroupContentTerminalEvidence(
              groupId: groupId,
              payloadType: payloadType,
              contentEventId: contentEventId,
              loadRows:
                  ({
                    required groupId,
                    required eventType,
                    afterSourceTimestamp,
                    afterSourceEventId,
                    throughSourceTimestamp,
                    required limit,
                  }) => dbLoadGroupEventLogTypePage(
                    database,
                    groupId: groupId,
                    eventType: eventType,
                    afterSourceTimestamp: afterSourceTimestamp,
                    afterSourceEventId: afterSourceEventId,
                    throughSourceTimestamp: throughSourceTimestamp,
                    newestFirst: true,
                    limit: limit,
                  ),
            ),
        commitMessage:
            ({
              required groupId,
              required sourcePeerId,
              required sourceEventId,
              required sourceTimestamp,
              required eventPayload,
              required messageRow,
              required mediaAttachmentRows,
              required incomingMediaCustodyRows,
              readyDisplayOutboxRow,
            }) => dbCommitProtectedGroupMessage(
              database,
              groupId: groupId,
              sourcePeerId: sourcePeerId,
              sourceEventId: sourceEventId,
              sourceTimestamp: sourceTimestamp,
              eventPayload: eventPayload,
              messageRow: messageRow,
              mediaAttachmentRows: mediaAttachmentRows,
              incomingMediaCustodyRows: incomingMediaCustodyRows,
              readyDisplayOutboxRow: readyDisplayOutboxRow,
            ),
        commitReaction:
            ({
              required groupId,
              required sourcePeerId,
              required sourceEventId,
              required sourceTimestamp,
              required eventPayload,
              required reactionRow,
              required transitionId,
              required action,
              readyDisplayOutboxRow,
            }) => dbCommitProtectedGroupReaction(
              database,
              groupId: groupId,
              sourcePeerId: sourcePeerId,
              sourceEventId: sourceEventId,
              sourceTimestamp: sourceTimestamp,
              eventPayload: eventPayload,
              reactionRow: reactionRow,
              transitionId: transitionId,
              action: action,
              readyDisplayOutboxRow: readyDisplayOutboxRow,
            ),
        commitTerminal:
            ({
              required groupId,
              required sourcePeerId,
              required sourceEventId,
              required sourceTimestamp,
              required eventPayload,
            }) => dbCommitProtectedGroupContentTerminal(
              database,
              groupId: groupId,
              sourcePeerId: sourcePeerId,
              sourceEventId: sourceEventId,
              sourceTimestamp: sourceTimestamp,
              eventPayload: eventPayload,
            ),
        resolveReactionTarget: (groupId, messageId) =>
            dbClassifyProtectedGroupReactionTargetWithEvidence(
              database,
              groupId: groupId,
              messageId: messageId,
            ),
        buildMessageDisplayRow:
            groupMessageListener.buildProtectedMessageDisplayReadyRow,
        buildReactionDisplayRow:
            groupMessageListener.buildProtectedReactionDisplayReadyRow,
        publishMessage: groupMessageListener.publishProtectedGroupMessage,
        publishReaction:
            groupMessageListener.publishProtectedGroupReactionChange,
      );
      return switch (result.disposition) {
        ProtectedGroupContentApplyDisposition.applied => (
          disposition: ProtectedGroupReplayDisposition.applied,
          reasonCode: result.reasonCode,
          reasonDetail: result.reasonDetail,
        ),
        ProtectedGroupContentApplyDisposition.exactDuplicate => (
          disposition: ProtectedGroupReplayDisposition.duplicate,
          reasonCode: result.reasonCode,
          reasonDetail: result.reasonDetail,
        ),
        ProtectedGroupContentApplyDisposition.terminalReject => (
          disposition: ProtectedGroupReplayDisposition.terminalRejected,
          reasonCode: result.reasonCode,
          reasonDetail: result.reasonDetail,
        ),
        ProtectedGroupContentApplyDisposition.unverifiedReject => (
          disposition: ProtectedGroupReplayDisposition.unverifiedRejected,
          reasonCode: result.reasonCode,
          reasonDetail: result.reasonDetail,
        ),
        ProtectedGroupContentApplyDisposition.prerequisiteWaiting => (
          disposition: ProtectedGroupReplayDisposition.prerequisiteWaiting,
          reasonCode: result.reasonCode,
          reasonDetail: result.reasonDetail,
        ),
        ProtectedGroupContentApplyDisposition.retryableFailure => (
          disposition: ProtectedGroupReplayDisposition.retryable,
          reasonCode: result.reasonCode,
          reasonDetail: result.reasonDetail,
        ),
      };
    }

    final envelope = ProtectedGroupEnvelope.tryParse(message.content);
    if (envelope?.type == linkedGroupBootstrapEnvelopeType) {
      final result = await handleLinkedGroupBootstrapEnvelope(
        message: message,
        linkedAuthority: linkedAuthority,
        ownMlKemPublicKey: identity.mlKemPublicKey!,
        ownMlKemSecretKey: identity.mlKemSecretKey!,
        groupRepository: groupRepository,
        callDecrypt:
            ({
              required ownMlKemSecretKey,
              required kem,
              required ciphertext,
              required nonce,
            }) => callDecryptMessage(
              bridge: bridge,
              ownMlKemSecretKey: ownMlKemSecretKey,
              kem: kem,
              ciphertext: ciphertext,
              nonce: nonce,
            ),
        callVerify: ({required publicKey, required data, required signature}) =>
            callVerifyPayload(
              bridge: bridge,
              publicKey: publicKey,
              data: data,
              signature: signature,
            ),
      );
      return switch (result) {
        HandleLinkedGroupBootstrapResult.applied => (
          disposition: ProtectedGroupReplayDisposition.applied,
          reasonCode: 'bootstrap_applied',
          reasonDetail: null,
        ),
        HandleLinkedGroupBootstrapResult.duplicate => (
          disposition: ProtectedGroupReplayDisposition.duplicate,
          reasonCode: 'bootstrap_duplicate',
          reasonDetail: null,
        ),
        HandleLinkedGroupBootstrapResult.terminalRejected => (
          disposition: ProtectedGroupReplayDisposition.terminalRejected,
          reasonCode: 'bootstrap_rejected',
          reasonDetail: null,
        ),
        HandleLinkedGroupBootstrapResult.retryable => (
          disposition: ProtectedGroupReplayDisposition.retryable,
          reasonCode: 'bootstrap_retryable',
          reasonDetail: null,
        ),
      };
    }
    if (envelope?.type != protectedGroupAuthorityEnvelopeType) {
      return (
        disposition: ProtectedGroupReplayDisposition.terminalRejected,
        reasonCode: 'unknown_protected_group_type',
        reasonDetail: null,
      );
    }

    GroupPendingKeyRepairRetryRequest? deferredKeyRepair;
    final result = await handleProtectedGroupAuthority(
      message: message,
      ownTransportPeerId: linkedAuthority.isActiveLinkedSecondary
          ? linkedAuthority.credential!.transportPeerId
          : identity.peerId,
      ownMlKemSecretKey: identity.mlKemSecretKey!,
      groupRepository: groupRepository,
      callDecrypt:
          ({
            required ownMlKemSecretKey,
            required kem,
            required ciphertext,
            required nonce,
          }) => callDecryptMessage(
            bridge: bridge,
            ownMlKemSecretKey: ownMlKemSecretKey,
            kem: kem,
            ciphertext: ciphertext,
            nonce: nonce,
          ),
      callVerify: ({required publicKey, required data, required signature}) =>
          callVerifyPayload(
            bridge: bridge,
            publicKey: publicKey,
            data: data,
            signature: signature,
          ),
      loadAuthorityProof:
          ({required groupId, required phase, required eventId}) =>
              loadAuthenticatedGroupAuthorityProofFromEventLog(
                loadRow: ({required groupId, required sourceEventId}) =>
                    dbLoadGroupEventLogEntryExact(
                      database,
                      groupId: groupId,
                      sourceEventId: sourceEventId,
                    ),
                groupId: groupId,
                phase: phase,
                eventId: eventId,
                verify:
                    ({required publicKey, required data, required signature}) =>
                        callVerifyPayload(
                          bridge: bridge,
                          publicKey: publicKey,
                          data: data,
                          signature: signature,
                        ),
              ),
      appendAuthorityProof: ({required phase, required proof}) async {
        await dbAppendGroupEventLogEntry(
          database,
          groupId: proof.groupId,
          eventType: phase.eventType,
          sourcePeerId: proof.actorAccountPeerId,
          sourceEventId: authenticatedGroupAuthoritySourceEventId(
            phase,
            proof.eventId,
          ),
          sourceTimestamp: fixedGroupAuthorityUtc(proof.eventAt),
          payload: authenticatedGroupAuthorityFactPayload(proof),
        );
      },
      applyReplay: (control, replayData, authority) async {
        try {
          final strictMembershipReplay =
              control == ProtectedGroupAuthorityControl.memberAdd ||
              control == ProtectedGroupAuthorityControl.memberRole ||
              control == ProtectedGroupAuthorityControl.memberRemove;
          final before = await protectedGroupAuthorityReplayConverged(
            control: control,
            replayData: replayData,
            groupRepository: groupRepository,
            requireMembershipVersion: strictMembershipReplay,
          );
          if (before == null) {
            return ProtectedGroupAuthorityApplyResult.rejected;
          }
          if (before &&
              control != ProtectedGroupAuthorityControl.memberConfig) {
            return ProtectedGroupAuthorityApplyResult.duplicate;
          }
          if (control == ProtectedGroupAuthorityControl.groupKeyUpdate) {
            if (!authority.authorizesKeyReplay(replayData)) {
              return ProtectedGroupAuthorityApplyResult.rejected;
            }
            final content = replayData['content'];
            final from = replayData['from'];
            final to = replayData['to'];
            final timestamp = replayData['timestamp'];
            if (content is! String ||
                from is! String ||
                to is! String ||
                timestamp is! String) {
              return ProtectedGroupAuthorityApplyResult.rejected;
            }
            await groupKeyUpdateListener.handleAuthenticatedAuthorityEnvelope(
              ChatMessage(
                from: from,
                to: to,
                content: content,
                timestamp: timestamp,
                isIncoming: true,
              ),
              authority: authority,
              authorityPhaseHeld: true,
              deferPendingRepair: (request) => deferredKeyRepair = request,
            );
          } else if (strictMembershipReplay) {
            return applySystemAuthorityReplay(control, replayData, authority);
          } else {
            await groupMessageListener
                .handleAuthenticatedAuthorityReplayEnvelope(
                  replayData,
                  authority: authority,
                  rethrowOnError: true,
                  membershipPhaseHeld: true,
                );
          }
          final after = await protectedGroupAuthorityReplayConverged(
            control: control,
            replayData: replayData,
            groupRepository: groupRepository,
            requireMembershipVersion: strictMembershipReplay,
            allowDominatingMembershipVersion: strictMembershipReplay,
          );
          return after == true
              ? ProtectedGroupAuthorityApplyResult.applied
              : ProtectedGroupAuthorityApplyResult.retryable;
        } on ProtectedGroupAuthorityReplaySuperseded {
          return ProtectedGroupAuthorityApplyResult.superseded;
        } catch (_) {
          return ProtectedGroupAuthorityApplyResult.retryable;
        }
      },
      reconcileContent: (_, _, authority) =>
          authoritySupport.reconcileCompletedContentAuthority(authority.proof),
    );
    final pendingRepair = deferredKeyRepair;
    if (pendingRepair != null &&
        result == ProtectedGroupAuthorityHandleResult.applied) {
      try {
        await retryPendingKeyRepairs(pendingRepair);
      } catch (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PROTECTED_GROUP_KEY_REPAIR_RETRY_ERROR',
          details: {
            'groupId': pendingRepair.groupId.length > 8
                ? pendingRepair.groupId.substring(0, 8)
                : pendingRepair.groupId,
            'keyEpoch': pendingRepair.keyEpoch,
            'error': error.toString(),
          },
        );
      }
    }
    return switch (result) {
      ProtectedGroupAuthorityHandleResult.applied => (
        disposition: ProtectedGroupReplayDisposition.applied,
        reasonCode: 'authority_applied',
        reasonDetail: null,
      ),
      ProtectedGroupAuthorityHandleResult.duplicate => (
        disposition: ProtectedGroupReplayDisposition.duplicate,
        reasonCode: 'authority_duplicate',
        reasonDetail: null,
      ),
      ProtectedGroupAuthorityHandleResult.terminalRejected => (
        disposition: ProtectedGroupReplayDisposition.terminalRejected,
        reasonCode: 'authority_rejected',
        reasonDetail: null,
      ),
      ProtectedGroupAuthorityHandleResult.retryable => (
        disposition: ProtectedGroupReplayDisposition.retryable,
        reasonCode: 'authority_retryable',
        reasonDetail: null,
      ),
      ProtectedGroupAuthorityHandleResult.prerequisiteWaiting => (
        disposition: ProtectedGroupReplayDisposition.prerequisiteWaiting,
        reasonCode: 'bootstrap_required',
        reasonDetail: null,
      ),
    };
  }
}
