import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/protected_group_content_db_helpers.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/group_media_blob_custody.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/services/protected_group_content_contract.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority_history.dart';
import 'package:flutter_app/features/groups/application/protected_group_media_manifest.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_reaction_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

export 'package:flutter_app/core/services/protected_group_content_contract.dart'
    show ProtectedGroupReactionTargetDisposition;

const _protectedContentFutureSkew = Duration(minutes: 5);
const _groupMediaAesGcmTagBytes = 16;

enum ProtectedGroupContentApplyDisposition {
  applied,
  exactDuplicate,
  terminalReject,
  unverifiedReject,
  prerequisiteWaiting,
  retryableFailure,
}

/// Durable state of the message targeted by an incoming protected reaction.
///
/// A missing projection is deliberately not terminal: the corresponding
/// protected message may still be waiting in the same staged fixed point.
typedef ProtectedGroupContentApplyOutcome = ({
  ProtectedGroupContentApplyDisposition disposition,
  String reasonCode,
  String? reasonDetail,
});

typedef CommitProtectedGroupMessage =
    Future<DbProtectedGroupContentCommitResult> Function({
      required String groupId,
      required String sourcePeerId,
      required String sourceEventId,
      required String sourceTimestamp,
      required Map<String, Object?> eventPayload,
      required Map<String, Object?> messageRow,
      required List<Map<String, Object?>> mediaAttachmentRows,
      required List<DirectMediaBlobCustodyRow> incomingMediaCustodyRows,
      Map<String, Object?>? readyDisplayOutboxRow,
    });

typedef CommitProtectedGroupReaction =
    Future<DbProtectedGroupContentCommitResult> Function({
      required String groupId,
      required String sourcePeerId,
      required String sourceEventId,
      required String sourceTimestamp,
      required Map<String, Object?> eventPayload,
      required Map<String, Object?> reactionRow,
      required String transitionId,
      required String action,
      Map<String, Object?>? readyDisplayOutboxRow,
    });

typedef CommitProtectedGroupContentTerminal =
    Future<DbProtectedGroupContentCommitResult> Function({
      required String groupId,
      required String sourcePeerId,
      required String sourceEventId,
      required String sourceTimestamp,
      required Map<String, Object?> eventPayload,
    });

typedef LoadProtectedGroupContentAuthority =
    Future<ProtectedGroupContentAuthority?> Function(
      String groupId,
      GroupContentAuthorityVersion version,
    );

typedef HasProtectedGroupContentTerminal =
    Future<bool> Function({
      required String groupId,
      required String payloadType,
      required String contentEventId,
    });

typedef HasPendingProtectedGroupContentAuthority =
    Future<bool> Function(String groupId);

typedef BuildProtectedMessageDisplayRow =
    Future<Map<String, Object?>?> Function(GroupMessage message);
typedef BuildProtectedReactionDisplayRow =
    Future<Map<String, Object?>?> Function(
      String groupId,
      GroupReactionPayload reaction,
    );

final class ProtectedGroupContentAuthority {
  const ProtectedGroupContentAuthority({
    required this.observed,
    required this.groupType,
    required this.members,
    required this.terminalFacts,
  });

  final AuthenticatedGroupAuthorityProof observed;
  final GroupType groupType;
  final List<GroupMember> members;
  final List<AuthenticatedGroupAuthorityProof> terminalFacts;

  GroupMember? member(String peerId) {
    for (final candidate in members) {
      if (candidate.peerId == peerId) return candidate;
    }
    return null;
  }

  bool governs({required DateTime eventAt, required String eventId}) {
    final observedOrder = _compareAuthorityOrder(
      observed.eventAt,
      observed.eventId,
      eventAt,
      eventId,
    );
    if (observedOrder > 0) return false;
    for (final fact in terminalFacts) {
      if (_sameAuthorityFact(fact, observed)) continue;
      if (_compareAuthorityOrder(
                fact.eventAt,
                fact.eventId,
                observed.eventAt,
                observed.eventId,
              ) >
              0 &&
          _compareAuthorityOrder(
                fact.eventAt,
                fact.eventId,
                eventAt,
                eventId,
              ) <=
              0) {
        return false;
      }
    }
    return true;
  }

  bool authorizesHistoricalContent({
    required String payloadType,
    required String contentEventId,
    required DateTime eventAt,
    required String logicalSenderPeerId,
    required String senderDeviceId,
    required String senderTransportPeerId,
    required String senderPublicKey,
  }) {
    if (!governs(eventAt: eventAt, eventId: contentEventId) ||
        groupType == GroupType.qa) {
      return false;
    }
    final sender = member(logicalSenderPeerId);
    if (sender == null) return false;
    final device = sender.findDeviceById(
      senderDeviceId,
      activeOnly: true,
      allowLegacyFallback: true,
    );
    if (device == null ||
        device.transportPeerId != senderTransportPeerId ||
        device.deviceSigningPublicKey != senderPublicKey) {
      return false;
    }
    return payloadType != groupOfflineReplayPayloadTypeMessage ||
        groupType != GroupType.announcement ||
        sender.role == MemberRole.admin;
  }
}

/// Loads the exact authenticated version plus every terminal authority fact
/// through the fixed future-skew cutoff. Each query is bounded, but pagination
/// continues to exhaustion and fails closed if a cursor cannot advance. The
/// nearest snapshot at-or-before the observed version is used for historical
/// role/device checks; local sequence is never ordering authority.
Future<ProtectedGroupContentAuthority?>
loadProtectedGroupContentAuthorityFromHistory({
  required String groupId,
  required GroupContentAuthorityVersion version,
  required LoadAuthenticatedGroupAuthorityProof loadExact,
  required LoadGroupAuthorityEventLogPageRows loadCompleteRows,
  required LoadGroupAuthorityEventLogPageRows loadGenesisRows,
  required VerifyAuthenticatedGroupAuthorityProof verify,
}) async {
  final exact = await loadAuthenticatedAuthorityVersion(
    load: loadExact,
    verify: verify,
    groupId: groupId,
    eventAt: version.eventAt,
    eventId: version.eventId,
    keyEpoch: version.keyEpoch,
  );
  if (exact == null) return null;

  final terminal = <AuthenticatedGroupAuthorityProof>[];
  for (final phase in const <AuthenticatedGroupAuthorityPhase>[
    AuthenticatedGroupAuthorityPhase.complete,
    AuthenticatedGroupAuthorityPhase.genesis,
  ]) {
    String? afterAt;
    String? afterId;
    while (true) {
      final page = await loadAuthenticatedGroupAuthorityProofPage(
        loadRows: phase == AuthenticatedGroupAuthorityPhase.complete
            ? loadCompleteRows
            : loadGenesisRows,
        groupId: groupId,
        phase: phase,
        verify: verify,
        afterSourceTimestamp: afterAt,
        afterSourceEventId: afterId,
        throughSourceTimestamp: fixedGroupContentUtc(
          DateTime.now().toUtc().add(_protectedContentFutureSkew),
        ),
        limit: 200,
      );
      terminal.addAll(page);
      if (page.length < 200) break;
      final last = page.last;
      final nextAt = fixedGroupContentUtc(last.eventAt);
      final nextId = authenticatedGroupAuthoritySourceEventId(
        phase,
        last.eventId,
      );
      if (nextAt == afterAt && nextId == afterId) return null;
      afterAt = nextAt;
      afterId = nextId;
    }
  }
  if (!terminal.any((fact) => _sameAuthorityFact(fact, exact))) {
    terminal.add(exact);
  }
  terminal.sort(
    (left, right) => _compareAuthorityOrder(
      right.eventAt,
      right.eventId,
      left.eventAt,
      left.eventId,
    ),
  );

  for (final fact in terminal) {
    if (_compareAuthorityOrder(
          fact.eventAt,
          fact.eventId,
          exact.eventAt,
          exact.eventId,
        ) >
        0) {
      continue;
    }
    final snapshot = _snapshotFromAuthority(fact);
    if (snapshot != null) {
      return ProtectedGroupContentAuthority(
        observed: exact,
        groupType: snapshot.groupType,
        members: snapshot.members,
        terminalFacts: List.unmodifiable(terminal),
      );
    }
  }
  return null;
}

Future<ProtectedGroupContentApplyOutcome> handleProtectedGroupContentReplay({
  required Bridge bridge,
  required GroupRepository groupRepository,
  required ChatMessage message,
  required String localLogicalPeerId,
  required String localTransportPeerId,
  required LoadProtectedGroupContentAuthority loadAuthority,
  required HasPendingProtectedGroupContentAuthority hasPendingAuthority,
  required CommitProtectedGroupMessage commitMessage,
  required CommitProtectedGroupReaction commitReaction,
  required CommitProtectedGroupContentTerminal commitTerminal,
  required HasProtectedGroupContentTerminal hasTerminal,
  required Future<ProtectedGroupReactionTargetDisposition> Function(
    String groupId,
    String messageId,
  )
  resolveReactionTarget,
  BuildProtectedMessageDisplayRow? buildMessageDisplayRow,
  BuildProtectedReactionDisplayRow? buildReactionDisplayRow,
  void Function(GroupMessage message)? publishMessage,
  void Function(ReactionChange change)? publishReaction,
  DateTime Function()? nowUtc,
}) async {
  final wireClassification = classifyProtectedGroupContentWire(message.content);
  final decodedOuter = _stringMap(message.content);
  if (decodedOuter == null) {
    return _unverified('protected_content_outer_malformed');
  }
  if (wireClassification == ProtectedGroupContentWireClassification.unrelated) {
    return _unverified('protected_content_signed_discriminator_missing');
  }
  if (wireClassification ==
      ProtectedGroupContentWireClassification.unverifiedCandidate) {
    return _unverified('protected_content_signed_discriminator_invalid');
  }
  final outer = Map<String, dynamic>.from(decodedOuter);
  // The canonical signed payload is the routing authority. The redundant
  // unsigned outer marker may be absent, but a present crossed value remains
  // input to strict verification and therefore fails closed.
  outer.putIfAbsent('custodyKind', () => groupContentCustodyKind);
  final groupId = _strictString(outer['groupId']);
  if (groupId == null) {
    return _unverified('protected_content_outer_malformed');
  }

  return runGroupAuthorityPhase(
    groupId: groupId,
    action: () async {
      // The preflight must execute under the same per-group authority phase as
      // verification and projection. A bootstrap-level check is only an
      // optimization: a producer can append PREPARED after that check but
      // before this phase is acquired.
      if (await hasPendingAuthority(groupId)) {
        return _waiting('authority_reconciliation_pending');
      }
      ProtectedGroupContentAuthority? authority;
      VerifiedGroupContentReplay verified;
      try {
        verified = await decryptVerifiedGroupContentReplay(
          bridge: bridge,
          groupRepo: groupRepository,
          groupId: groupId,
          envelope: outer,
          expectedRelayPeerId: message.from,
          expectedRecipientPeerId: localTransportPeerId,
          verifyHistoricalSigner:
              ({
                required groupId,
                required authorityVersion,
                required logicalSenderPeerId,
                required senderDeviceId,
                required senderTransportPeerId,
                required senderPublicKey,
              }) async {
                authority = await loadAuthority(groupId, authorityVersion);
                final member = authority?.member(logicalSenderPeerId);
                if (member == null) return false;
                final device = member.findDeviceById(
                  senderDeviceId,
                  activeOnly: true,
                  allowLegacyFallback: true,
                );
                return device != null &&
                    device.transportPeerId == senderTransportPeerId &&
                    device.deviceSigningPublicKey == senderPublicKey;
              },
        );
      } on StateError catch (error) {
        return _waiting('protected_content_key_unavailable', error);
      } on GroupEventLogTamperException catch (error) {
        return _retryable('protected_authority_history_tamper', error);
      } on GroupOfflineReplaySignatureException catch (error) {
        if (error.reason == 'historical_sender_unauthorized' &&
            authority == null) {
          return _waiting('authenticated_authority_version_unavailable');
        }
        return _unverified(error.reason);
      } catch (error) {
        return _retryable('protected_content_verify_failed', error);
      }

      final acceptedAuthority = authority;
      if (acceptedAuthority == null) {
        return _waiting('authenticated_authority_version_unavailable');
      }
      final localMember = acceptedAuthority.member(localLogicalPeerId);
      if (localMember == null ||
          !localMember.activeDevicesWithLegacyFallback().any(
            (device) => device.transportPeerId == localTransportPeerId,
          )) {
        return _waiting('local_historical_membership_unavailable');
      }
      if (await hasTerminal(
        groupId: verified.groupId,
        payloadType: verified.payloadType,
        contentEventId: verified.contentEventId,
      )) {
        return _terminal('protected_content_terminal_duplicate');
      }

      final plaintext = _stringMap(verified.plaintext);
      if (plaintext == null) {
        return _terminalizeVerified(
          verified: verified,
          reason: 'protected_content_plaintext_malformed',
          envelope: message.content,
          commit: commitTerminal,
        );
      }
      final timestamp = parseFixedGroupContentUtc(plaintext['timestamp']);
      final instant = (nowUtc?.call() ?? DateTime.now()).toUtc();
      if (timestamp == null ||
          timestamp.isAfter(instant.add(_protectedContentFutureSkew))) {
        return _terminalizeVerified(
          verified: verified,
          reason: 'protected_content_timestamp_invalid',
          envelope: message.content,
          commit: commitTerminal,
        );
      }
      if (!acceptedAuthority.governs(
        eventAt: timestamp,
        eventId: verified.contentEventId,
      )) {
        return _terminalizeVerified(
          verified: verified,
          reason: 'protected_content_authority_superseded',
          envelope: message.content,
          commit: commitTerminal,
        );
      }

      try {
        if (verified.payloadType == groupOfflineReplayPayloadTypeMessage) {
          return await _applyMessage(
            verified: verified,
            payload: plaintext,
            authority: acceptedAuthority,
            localLogicalPeerId: localLogicalPeerId,
            localTransportPeerId: localTransportPeerId,
            envelope: message.content,
            commitMessage: commitMessage,
            commitTerminal: commitTerminal,
            buildDisplayRow: buildMessageDisplayRow,
            publish: publishMessage,
          );
        }
        if (verified.payloadType == groupOfflineReplayPayloadTypeReaction) {
          return await _applyReaction(
            verified: verified,
            payload: plaintext,
            authority: acceptedAuthority,
            envelope: message.content,
            commitReaction: commitReaction,
            commitTerminal: commitTerminal,
            resolveReactionTarget: resolveReactionTarget,
            buildDisplayRow: buildReactionDisplayRow,
            publish: publishReaction,
          );
        }
        return _terminalizeVerified(
          verified: verified,
          reason: 'protected_content_payload_type_invalid',
          envelope: message.content,
          commit: commitTerminal,
        );
      } on GroupEventLogTamperException catch (error) {
        return _terminal('protected_content_event_conflict', error);
      } on ArgumentError {
        return _terminalizeVerified(
          verified: verified,
          reason: 'protected_content_shape_invalid',
          envelope: message.content,
          commit: commitTerminal,
        );
      } catch (error) {
        return _retryable('protected_content_commit_failed', error);
      }
    },
  );
}

Future<ProtectedGroupContentApplyOutcome> _applyMessage({
  required VerifiedGroupContentReplay verified,
  required Map<String, dynamic> payload,
  required ProtectedGroupContentAuthority authority,
  required String localLogicalPeerId,
  required String localTransportPeerId,
  required String envelope,
  required CommitProtectedGroupMessage commitMessage,
  required CommitProtectedGroupContentTerminal commitTerminal,
  required BuildProtectedMessageDisplayRow? buildDisplayRow,
  required void Function(GroupMessage message)? publish,
}) async {
  final messageId = _strictString(payload['messageId']);
  final rawText = payload['text'];
  final text = rawText is String && rawText.trim() == rawText ? rawText : null;
  final timestamp = parseFixedGroupContentUtc(payload['timestamp']);
  final logicalDeliveryId = _strictString(payload['logicalDeliveryId']);
  final hasQuoted = payload.containsKey('quotedMessageId');
  final quotedMessageId = hasQuoted
      ? _strictString(payload['quotedMessageId'])
      : null;
  final hasMedia = payload.containsKey('media');
  final hasForwarded = payload.containsKey('isForwarded');
  final isForwarded = hasForwarded && payload['isForwarded'] == true;
  final privateFields = GroupPrivateMediaPolicy.wireKeys.any(
    payload.containsKey,
  );
  final sanitized = text == null ? '' : sanitizeMessageText(text);
  final mediaManifest = verified.mediaManifest;
  final mediaManifestHash = verified.mediaManifestHash;
  final hasProtectedMedia = mediaManifest != null;
  final sender = authority.member(verified.logicalSenderPeerId);
  final excluded =
      messageId == null ||
      messageId != verified.contentEventId ||
      timestamp == null ||
      text == null ||
      (!hasProtectedMedia && sanitized.trim().isEmpty) ||
      sanitized.startsWith('{"__sys":') ||
      (hasQuoted &&
          (quotedMessageId == null || quotedMessageId == messageId)) ||
      hasMedia ||
      (hasForwarded &&
          (!isForwarded ||
              !hasProtectedMedia ||
              hasQuoted ||
              mediaManifest.attachments.any(
                (attachment) =>
                    attachment.mediaType != 'image' &&
                    attachment.mediaType != 'video',
              ))) ||
      privateFields ||
      (hasProtectedMedia && mediaManifestHash == null) ||
      (logicalDeliveryId != null && logicalDeliveryId != messageId) ||
      sender == null ||
      authority.groupType == GroupType.qa ||
      (authority.groupType == GroupType.announcement &&
          sender.role != MemberRole.admin);
  if (excluded) {
    return _terminalizeVerified(
      verified: verified,
      reason: 'protected_message_ineligible',
      envelope: envelope,
      commit: commitTerminal,
    );
  }
  if (hasProtectedMedia) {
    final localTargetValid = mediaManifest.attachments.every((attachment) {
      final target = attachment.targetFor(localTransportPeerId);
      return target != null &&
          attachment.ciphertextSize > _groupMediaAesGcmTagBytes &&
          target.custodyKind == groupMediaBlobCustodyKind &&
          target.custodyContract == groupMediaBlobCustodyContract &&
          target.expiresAtMs > 0;
    });
    if (!localTargetValid) {
      return _terminalizeVerified(
        verified: verified,
        reason: 'protected_media_local_target_mismatch',
        envelope: envelope,
        commit: commitTerminal,
      );
    }
  }
  final selfEcho = verified.logicalSenderPeerId == localLogicalPeerId;
  final message = GroupMessage(
    id: messageId,
    groupId: verified.groupId,
    senderPeerId: verified.logicalSenderPeerId,
    transportPeerId: verified.senderTransportPeerId,
    senderUsername: sender.username,
    text: sanitized,
    timestamp: timestamp,
    quotedMessageId: quotedMessageId,
    logicalDeliveryId: logicalDeliveryId ?? messageId,
    keyGeneration: verified.keyEpoch,
    status: selfEcho ? 'sent' : 'delivered',
    isIncoming: !selfEcho,
    isForwarded: isForwarded,
    // Strict replay is immutable. Local arrival time cannot participate in
    // projection equality because the same signed bytes may be redelivered
    // after ACK failure or restart.
    createdAt: timestamp,
  );
  final display = selfEcho ? null : await buildDisplayRow?.call(message);
  final mediaProjection = mediaManifest == null
      ? const (
          attachments: <Map<String, Object?>>[],
          custody: <DirectMediaBlobCustodyRow>[],
        )
      : _buildIncomingProtectedGroupMediaProjection(
          manifest: mediaManifest,
          localTransportPeerId: localTransportPeerId,
          sourceTimestamp: fixedGroupContentUtc(timestamp),
        );
  final result = await commitMessage(
    groupId: verified.groupId,
    sourcePeerId: verified.logicalSenderPeerId,
    sourceEventId: protectedGroupMessageSourceEventId(messageId),
    sourceTimestamp: fixedGroupContentUtc(timestamp),
    eventPayload: _protectedEventPayload(verified, payload),
    messageRow: message.toMap(),
    mediaAttachmentRows: mediaProjection.attachments,
    incomingMediaCustodyRows: mediaProjection.custody,
    readyDisplayOutboxRow: display,
  );
  if (result == DbProtectedGroupContentCommitResult.prerequisiteMissing) {
    return _waiting('protected_message_parent_unavailable');
  }
  if (result == DbProtectedGroupContentCommitResult.applied) {
    publish?.call(message);
  }
  return _fromCommit(result);
}

({
  List<Map<String, Object?>> attachments,
  List<DirectMediaBlobCustodyRow> custody,
})
_buildIncomingProtectedGroupMediaProjection({
  required ProtectedGroupMediaManifest manifest,
  required String localTransportPeerId,
  required String sourceTimestamp,
}) {
  final attachmentRows = <Map<String, Object?>>[];
  final custodyRows = <DirectMediaBlobCustodyRow>[];
  for (final commitment in manifest.attachments) {
    final target = commitment.targetFor(localTransportPeerId);
    if (target == null) {
      throw const FormatException('missing local group-media commitment');
    }
    if (commitment.ciphertextSize <= _groupMediaAesGcmTagBytes) {
      throw const FormatException('invalid group-media ciphertext size');
    }
    final custodyFingerprint = computeGroupMediaBlobCustodyFingerprint(
      groupId: manifest.groupId,
      messageId: manifest.messageId,
      attachmentId: commitment.attachmentId,
      custodyBlobId: commitment.custodyBlobId,
      contentHash: commitment.ciphertextSha256,
      ciphertextSize: commitment.ciphertextSize,
      recipientPeerIds: commitment.recipientPeerIds,
    );
    final attachment = MediaAttachment(
      id: commitment.attachmentId,
      messageId: manifest.messageId,
      mime: commitment.mime,
      size: commitment.ciphertextSize - _groupMediaAesGcmTagBytes,
      mediaType: commitment.mediaType,
      width: commitment.width,
      height: commitment.height,
      durationMs: commitment.durationMs,
      localPath: null,
      downloadStatus: 'pending',
      createdAt: sourceTimestamp,
      waveform: commitment.waveform.isEmpty ? null : commitment.waveform,
      contentHash: commitment.ciphertextSha256,
      encryptionKeyBase64: commitment.encryptionKeyBase64,
      encryptionNonce: commitment.encryptionNonce,
      encryptionScheme: commitment.encryptionScheme,
      groupMediaBlobCustodyFingerprint: custodyFingerprint,
      ownerLane: MediaOwnerLane.group,
    );
    attachmentRows.add(attachment.toMap());
    custodyRows.add(
      DirectMediaBlobCustodyRow(
        attachmentId: commitment.attachmentId,
        messageId: manifest.messageId,
        ownerLane: MediaBlobCustodyOwnerLane.group,
        groupId: manifest.groupId,
        custodyBlobId: commitment.custodyBlobId,
        direction: DirectMediaBlobCustodyDirection.incoming,
        state: DirectMediaBlobCustodyState.incomingCommitted,
        inboxCustodyIncarnationId: null,
        recipientPeerId: null,
        contactAccountPeerId: null,
        recipientMlKemPublicKey: null,
        ciphertextRelativePath: null,
        custodyKind: target.custodyKind,
        custodyContract: target.custodyContract,
        contentHash: commitment.ciphertextSha256,
        ciphertextSize: commitment.ciphertextSize,
        transportMime: kDirectMediaBlobTransportMime,
        expiresAtMs: target.expiresAtMs,
        custodyRelayPeerId: null,
        lastAttemptAt: null,
        nextAttemptAt: null,
        createdAt: sourceTimestamp,
        updatedAt: sourceTimestamp,
      ),
    );
  }
  return (
    attachments: List<Map<String, Object?>>.unmodifiable(attachmentRows),
    custody: List<DirectMediaBlobCustodyRow>.unmodifiable(custodyRows),
  );
}

Future<ProtectedGroupContentApplyOutcome> _applyReaction({
  required VerifiedGroupContentReplay verified,
  required Map<String, dynamic> payload,
  required ProtectedGroupContentAuthority authority,
  required String envelope,
  required CommitProtectedGroupReaction commitReaction,
  required CommitProtectedGroupContentTerminal commitTerminal,
  required Future<ProtectedGroupReactionTargetDisposition> Function(
    String groupId,
    String messageId,
  )
  resolveReactionTarget,
  required BuildProtectedReactionDisplayRow? buildDisplayRow,
  required void Function(ReactionChange change)? publish,
}) async {
  final reaction = GroupReactionPayload.fromDecryptedJson(jsonEncode(payload));
  final transitionId = reaction?.eventId?.trim();
  final timestamp = reaction == null
      ? null
      : parseFixedGroupContentUtc(reaction.timestamp);
  if (reaction == null ||
      transitionId == null ||
      transitionId != verified.contentEventId ||
      GroupReactionTransitionOrder.tryParse(transitionId) == null ||
      timestamp == null ||
      authority.groupType == GroupType.qa ||
      reaction.senderPeerId != verified.logicalSenderPeerId) {
    return _terminalizeVerified(
      verified: verified,
      reason: 'protected_reaction_ineligible',
      envelope: envelope,
      commit: commitTerminal,
    );
  }
  final target = await resolveReactionTarget(
    verified.groupId,
    reaction.messageId,
  );
  if (target == ProtectedGroupReactionTargetDisposition.prerequisiteWaiting) {
    return _waiting('protected_reaction_target_unavailable');
  }
  if (target == ProtectedGroupReactionTargetDisposition.terminal) {
    return _terminalizeVerified(
      verified: verified,
      reason: 'protected_reaction_target_terminal',
      envelope: envelope,
      commit: commitTerminal,
    );
  }
  final row = MessageReaction(
    id: reaction.id,
    messageId: reaction.messageId,
    emoji: reaction.emoji,
    senderPeerId: reaction.senderPeerId,
    timestamp: fixedGroupContentUtc(timestamp),
    createdAt: fixedGroupContentUtc(timestamp),
  ).toMap();
  final display = reaction.action == GroupReactionPayload.actionAdd
      ? await buildDisplayRow?.call(verified.groupId, reaction)
      : null;
  final result = await commitReaction(
    groupId: verified.groupId,
    sourcePeerId: verified.logicalSenderPeerId,
    sourceEventId: protectedGroupReactionSourceEventId(transitionId),
    sourceTimestamp: fixedGroupContentUtc(timestamp),
    eventPayload: _protectedEventPayload(verified, payload),
    reactionRow: row,
    transitionId: transitionId,
    action: reaction.action,
    readyDisplayOutboxRow: display,
  );
  if (result == DbProtectedGroupContentCommitResult.prerequisiteMissing) {
    return _waiting('protected_reaction_target_unavailable');
  }
  if (result == DbProtectedGroupContentCommitResult.applied) {
    publish?.call(
      reaction.action == GroupReactionPayload.actionAdd
          ? ReactionChange.upsert(MessageReaction.fromMap(row))
          : ReactionChange.removed(
              messageId: reaction.messageId,
              senderPeerId: reaction.senderPeerId,
            ),
    );
  }
  return _fromCommit(result);
}

String protectedGroupMessageSourceEventId(String messageId) =>
    'pm1:${_base64(messageId)}';

String protectedGroupReactionSourceEventId(String transitionId) =>
    'pr1:$transitionId';

String protectedGroupContentReconciliationCompleteSourceEventId(
  String authorityEventId,
) =>
    'pt1:${_base64('authority_reconciliation')}:'
    '${_base64(authorityEventId)}:complete';

bool isProtectedGroupContentReconciliationCompleteRow(
  Map<String, Object?>? row, {
  required AuthenticatedGroupAuthorityProof authority,
}) {
  if (row == null ||
      row['group_id'] != authority.groupId ||
      row['event_type'] != protectedGroupContentTerminalEventType ||
      row['source_peer_id'] != authority.actorAccountPeerId ||
      row['source_timestamp'] != fixedGroupContentUtc(authority.eventAt) ||
      row['source_event_id'] !=
          protectedGroupContentReconciliationCompleteSourceEventId(
            authority.eventId,
          )) {
    return false;
  }
  final encoded = row['canonical_payload'];
  if (encoded is! String) return false;
  try {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map || decoded.length != 10) return false;
    const keys = <String>{
      'reasonCode',
      'groupId',
      'authorityEventId',
      'authorityEventAt',
      'authorityKeyEpoch',
      'upperSequence',
      'lastProcessedSequence',
      'lastSourceTimestamp',
      'lastSourceEventId',
      'complete',
    };
    if (!decoded.keys.toSet().containsAll(keys)) return false;
    final upper = decoded['upperSequence'];
    final processed = decoded['lastProcessedSequence'];
    final cursorAt = decoded['lastSourceTimestamp'];
    final cursorId = decoded['lastSourceEventId'];
    return decoded['reasonCode'] == 'authority_reconciliation_complete' &&
        decoded['groupId'] == authority.groupId &&
        decoded['authorityEventId'] == authority.eventId &&
        decoded['authorityEventAt'] ==
            fixedGroupContentUtc(authority.eventAt) &&
        decoded['authorityKeyEpoch'] == authority.keyEpoch &&
        decoded['complete'] == true &&
        upper is int &&
        upper >= 0 &&
        processed is int &&
        processed == upper &&
        (cursorAt == null || cursorAt is String) &&
        (cursorId == null || cursorId is String) &&
        (cursorAt == null) == (cursorId == null);
  } catch (_) {
    return false;
  }
}

Map<String, Object?>? parseProtectedGroupContentTerminalRow(
  Map<String, Object?> row, {
  required String groupId,
}) {
  if (row['group_id'] != groupId ||
      row['event_type'] != protectedGroupContentTerminalEventType) {
    return null;
  }
  final raw = row['canonical_payload'];
  if (raw is! String) return null;
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map
        ? Map<String, Object?>.from(decoded.cast<String, Object?>())
        : null;
  } catch (_) {
    return null;
  }
}

/// A protected content fact is permanently unavailable when receive rejected
/// it, or when an authenticated authority reconciliation invalidated it.
/// Reconciliation page/frontier facts are intentionally not content terminal.
bool isProtectedGroupContentTerminalRowExact(
  Map<String, Object?> row, {
  required String groupId,
  required String payloadType,
  required String contentEventId,
}) {
  final payload = parseProtectedGroupContentTerminalRow(row, groupId: groupId);
  if (payload == null ||
      payload['payloadType'] != payloadType ||
      payload['contentEventId'] != contentEventId) {
    return false;
  }
  final reason = payload['reasonCode'];
  return reason is String &&
      (reason.startsWith('protected_') ||
          reason == 'authority_reconciliation_invalidated');
}

/// Checks every bounded terminal page for one exact immutable content key.
/// The event source ID includes a reason domain, so callers must not derive a
/// single row ID when deciding whether previously rejected content is dead.
Future<bool> hasProtectedGroupContentTerminalEvidence({
  required String groupId,
  required String payloadType,
  required String contentEventId,
  required LoadGroupAuthorityEventLogPageRows loadRows,
  int pageSize = 200,
}) async {
  if (pageSize < 1 || pageSize > 200) {
    throw RangeError.range(pageSize, 1, 200, 'pageSize');
  }
  String? afterAt;
  String? afterId;
  while (true) {
    final page = await loadRows(
      groupId: groupId,
      eventType: protectedGroupContentTerminalEventType,
      afterSourceTimestamp: afterAt,
      afterSourceEventId: afterId,
      throughSourceTimestamp: null,
      limit: pageSize,
    );
    for (final row in page) {
      if (isProtectedGroupContentTerminalRowExact(
        row,
        groupId: groupId,
        payloadType: payloadType,
        contentEventId: contentEventId,
      )) {
        return true;
      }
    }
    if (page.length < pageSize) return false;
    final nextAt = page.last['source_timestamp'] as String?;
    final nextId = page.last['source_event_id'] as String?;
    if (nextAt == null ||
        nextId == null ||
        (nextAt == afterAt && nextId == afterId)) {
      throw StateError('protected content terminal cursor stalled');
    }
    afterAt = nextAt;
    afterId = nextId;
  }
}

String _terminalSourceEventId(String kind, String eventId, String reason) =>
    'pt1:${_base64(kind)}:${_base64(eventId)}:'
    '${sha256.convert(utf8.encode(reason))}';

Future<ProtectedGroupContentApplyOutcome> _terminalizeVerified({
  required VerifiedGroupContentReplay verified,
  required String reason,
  required String envelope,
  required CommitProtectedGroupContentTerminal commit,
}) async {
  final result = await commit(
    groupId: verified.groupId,
    sourcePeerId: verified.logicalSenderPeerId,
    sourceEventId: _terminalSourceEventId(
      verified.payloadType,
      verified.contentEventId,
      reason,
    ),
    sourceTimestamp: fixedGroupContentUtc(verified.authorityVersion.eventAt),
    eventPayload: <String, Object?>{
      'reasonCode': reason,
      'payloadType': verified.payloadType,
      'contentEventId': verified.contentEventId,
      'envelopeDigest': sha256.convert(utf8.encode(envelope)).toString(),
      'authorityEventId': verified.authorityVersion.eventId,
    },
  );
  return switch (result) {
    DbProtectedGroupContentCommitResult.applied => _terminal(reason),
    DbProtectedGroupContentCommitResult.exactDuplicate => _terminal(
      'protected_content_terminal_duplicate',
    ),
    DbProtectedGroupContentCommitResult.prerequisiteMissing => _waiting(
      'protected_content_terminal_prerequisite_missing',
    ),
    DbProtectedGroupContentCommitResult.staleDominated => _waiting(
      'protected_content_terminal_not_committed',
    ),
  };
}

Map<String, Object?> _protectedEventPayload(
  VerifiedGroupContentReplay verified,
  Map<String, dynamic> payload,
) => <String, Object?>{
  'custodyKind': groupContentCustodyKind,
  'groupId': verified.groupId,
  'payloadType': verified.payloadType,
  'contentEventId': verified.contentEventId,
  'authorityEventAt': fixedGroupContentUtc(verified.authorityVersion.eventAt),
  'authorityEventId': verified.authorityVersion.eventId,
  'authorityKeyEpoch': verified.authorityVersion.keyEpoch,
  'logicalSenderPeerId': verified.logicalSenderPeerId,
  'senderDeviceId': verified.senderDeviceId,
  'senderTransportPeerId': verified.senderTransportPeerId,
  'senderPublicKey': verified.senderPublicKey,
  'recipientPeerIds': verified.recipientPeerIds,
  'payload': payload,
};

ProtectedGroupContentApplyOutcome _fromCommit(
  DbProtectedGroupContentCommitResult result,
) => switch (result) {
  DbProtectedGroupContentCommitResult.applied => (
    disposition: ProtectedGroupContentApplyDisposition.applied,
    reasonCode: 'protected_content_applied',
    reasonDetail: null,
  ),
  DbProtectedGroupContentCommitResult.exactDuplicate ||
  DbProtectedGroupContentCommitResult.staleDominated => (
    disposition: ProtectedGroupContentApplyDisposition.exactDuplicate,
    reasonCode: result == DbProtectedGroupContentCommitResult.staleDominated
        ? 'protected_content_stale_dominated'
        : 'protected_content_exact_duplicate',
    reasonDetail: null,
  ),
  DbProtectedGroupContentCommitResult.prerequisiteMissing => _waiting(
    'protected_content_prerequisite_missing',
  ),
};

ProtectedGroupContentApplyOutcome _terminal(String reason, [Object? detail]) =>
    (
      disposition: ProtectedGroupContentApplyDisposition.terminalReject,
      reasonCode: reason,
      reasonDetail: detail?.toString(),
    );

ProtectedGroupContentApplyOutcome _unverified(
  String reason, [
  Object? detail,
]) => (
  disposition: ProtectedGroupContentApplyDisposition.unverifiedReject,
  reasonCode: reason,
  reasonDetail: detail?.toString(),
);

ProtectedGroupContentApplyOutcome _waiting(String reason, [Object? detail]) => (
  disposition: ProtectedGroupContentApplyDisposition.prerequisiteWaiting,
  reasonCode: reason,
  reasonDetail: detail?.toString(),
);

ProtectedGroupContentApplyOutcome _retryable(String reason, [Object? detail]) =>
    (
      disposition: ProtectedGroupContentApplyDisposition.retryableFailure,
      reasonCode: reason,
      reasonDetail: detail?.toString(),
    );

({GroupType groupType, List<GroupMember> members})? _snapshotFromAuthority(
  AuthenticatedGroupAuthorityProof proof,
) {
  final genesisGroup = proof.authorityData['group'];
  final genesisMembers = proof.authorityData['members'];
  if (genesisGroup is Map && genesisMembers is List) {
    try {
      final group = GroupModel.fromMap(Map<String, dynamic>.from(genesisGroup));
      final members = genesisMembers
          .whereType<Map>()
          .map((row) => GroupMember.fromMap(Map<String, dynamic>.from(row)))
          .toList(growable: false);
      if (members.isNotEmpty) return (groupType: group.type, members: members);
    } catch (_) {}
  }
  final text = proof.authorityData['text'];
  final decoded = text is String ? _stringMap(text) : null;
  final configRaw = decoded?['groupConfig'];
  if (configRaw is! Map) return null;
  final config = Map<String, dynamic>.from(configRaw);
  final typeRaw = _strictString(config['groupType']);
  final memberRows = config['members'];
  if (typeRaw == null || memberRows is! List) return null;
  try {
    final members = memberRows
        .whereType<Map>()
        .map(
          (row) => GroupMember.fromConfigMap(
            groupId: proof.groupId,
            map: Map<String, dynamic>.from(row),
            joinedAt: proof.eventAt,
            preserveMissingPermissions: false,
          ),
        )
        .toList(growable: false);
    if (members.isEmpty) return null;
    return (groupType: GroupType.fromValue(typeRaw), members: members);
  } catch (_) {
    return null;
  }
}

int _compareAuthorityOrder(
  DateTime leftAt,
  String leftId,
  DateTime rightAt,
  String rightId,
) {
  final byTime = leftAt.toUtc().compareTo(rightAt.toUtc());
  return byTime != 0 ? byTime : leftId.compareTo(rightId);
}

bool _sameAuthorityFact(
  AuthenticatedGroupAuthorityProof left,
  AuthenticatedGroupAuthorityProof right,
) =>
    left.groupId == right.groupId &&
    left.eventId == right.eventId &&
    left.eventAt.toUtc() == right.eventAt.toUtc() &&
    left.keyEpoch == right.keyEpoch;

Map<String, dynamic>? _stringMap(String raw) {
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } catch (_) {
    return null;
  }
}

String? _strictString(Object? value) {
  if (value is! String || value.isEmpty || value.trim() != value) return null;
  return value;
}

String _base64(String value) =>
    base64Url.encode(utf8.encode(value)).replaceAll('=', '');
