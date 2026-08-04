import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/notifications/conversation_notification_content_kind.dart';
import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_reaction_payload.dart';
import 'package:flutter_app/features/push/application/background_group_notification_post_show_fence.dart';
import 'package:flutter_app/features/push/application/background_push_notification_fallback.dart';
import 'package:flutter_app/features/push/application/group_reaction_notification_copy.dart';
import 'package:flutter_app/features/push/application/notification_preview_copy.dart';
import 'package:flutter_app/features/push/application/private_media_notification_body.dart';

typedef DecryptOneToOnePush =
    Future<String> Function({
      required String kem,
      required String ciphertext,
      required String nonce,
    });

typedef DecryptGroupPush =
    Future<String> Function({
      required String groupId,
      required int keyEpoch,
      required String ciphertext,
      required String nonce,
    });

typedef VerifyGroupReactionPushSignature =
    Future<bool> Function({
      required String publicKey,
      required String signedPayload,
      required String signature,
    });

/// A verified recipient nomination from the separately signed optional
/// group-reaction notification extension.
///
/// The relay is allowed to use this extension to select a wake target, but the
/// recipient still verifies the signature, parity for every provided outer
/// field, and that this installation's transport is in the signed nomination
/// before consulting local group state.
class VerifiedGroupReactionNotificationNomination {
  const VerifiedGroupReactionNotificationNomination({
    required this.reactorTransportPeerId,
    required this.senderPublicKey,
    required this.transitionId,
  });

  final String reactorTransportPeerId;
  final String senderPublicKey;
  final String transitionId;
}

/// Integrity failures are different from crypto unavailability. A recognized
/// reaction whose decrypted fields conflict with the signed/outer wake hint
/// must never degrade to a semantic fallback card.
class GroupReactionNotificationIntegrityException implements Exception {
  const GroupReactionNotificationIntegrityException(this.reason);

  final String reason;

  @override
  String toString() => 'GroupReactionNotificationIntegrityException($reason)';
}

/// A successfully authenticated direct-reaction plaintext disagreed with the
/// recipient-authorized outer scope. This must not degrade to generic copy.
class DirectReactionNotificationIntegrityException implements Exception {
  const DirectReactionNotificationIntegrityException(this.reason);

  final String reason;

  @override
  String toString() => 'DirectReactionNotificationIntegrityException($reason)';
}

/// A successfully decrypted ordinary message whose recipient-owned routing
/// facts disagree with its private payload must be suppressed, not converted
/// into a generic card. Group crypto/plugin unavailability is content-free only
/// for an authenticated local context carrying relay `preview_unavailable=1`.
class OrdinaryMessageNotificationIntegrityException implements Exception {
  const OrdinaryMessageNotificationIntegrityException(this.reason);

  final String reason;

  @override
  String toString() => 'OrdinaryMessageNotificationIntegrityException($reason)';
}

/// Recipient-owned direct-chat facts used by the background preview path.
/// [senderUsername] is trusted local copy; the decrypted display name is never
/// authoritative when this context is present.
class DirectMessageNotificationContext {
  const DirectMessageNotificationContext({
    required this.senderPeerId,
    required this.senderUsername,
    required this.expectedMessageId,
  });

  final String senderPeerId;
  final String? senderUsername;
  final String? expectedMessageId;
}

/// Recipient-owned group facts used by the background preview path.
///
/// Production resolution binds [senderTransportPeerId] to exactly one active
/// local member device, then derives [senderPeerId], [senderUsername], and role
/// from the local roster. Nullable fields remain for legacy/context-free preview
/// callers, not as authorization fallback for the background handler.
class GroupMessageNotificationContext {
  const GroupMessageNotificationContext({
    required this.groupId,
    required this.groupName,
    required this.localPeerId,
    required this.senderPeerId,
    this.senderTransportPeerId,
    required this.senderUsername,
    required this.expectedMessageId,
  });

  final String groupId;
  final String? groupName;
  final String localPeerId;
  final String? senderPeerId;
  final String? senderTransportPeerId;
  final String? senderUsername;
  final String? expectedMessageId;
}

/// Recipient-owned facts required before private reaction preview material is
/// allowed into a notification. Sender-authored display names are never used.
class DirectReactionNotificationContext {
  const DirectReactionNotificationContext({
    required this.actorPeerId,
    required this.actorUsername,
    required this.targetMessageId,
  });

  final String actorPeerId;
  final String actorUsername;
  final String targetMessageId;
}

/// Recipient-owned group facts required before a private group reaction can
/// become a contextual notification. Sender-authored display fields are never
/// accepted from the push payload.
class GroupReactionNotificationContext {
  const GroupReactionNotificationContext({
    required this.groupId,
    required this.groupName,
    required this.actorPeerId,
    required this.actorUsername,
    required this.targetMessageId,
    this.targetKind = GroupReactionTargetKind.message,
    this.currentReactionId,
    this.currentReactionTimestamp,
    this.currentReactionRemovedAt,
    this.currentReactionAcknowledged = false,
    this.expectedTransitionId,
  });

  final String groupId;
  final String groupName;
  final String actorPeerId;
  final String actorUsername;
  final String targetMessageId;
  final GroupReactionTargetKind targetKind;

  /// Recipient-owned state identifier for the current sender/target row.
  /// Together with [currentReactionTimestamp], this lets decrypted replay
  /// checks bind a read acknowledgement without trusting outer push fields.
  final String? currentReactionId;

  /// Recipient-owned last-writer-wins comparand for this target/reactor pair.
  /// A tombstoned or newer row suppresses a delayed ADD before any event claim.
  final String? currentReactionTimestamp;
  final String? currentReactionRemovedAt;
  final bool currentReactionAcknowledged;

  /// Signed nomination identity used when the transport omits its duplicate
  /// outer transition id. Authenticated plaintext must still match this id.
  final String? expectedTransitionId;

  bool get hasCurrentReaction => currentReactionTimestamp != null;
}

/// Verifies the optional signed group-reaction notification extension and
/// proves that [localTransportPeerId] is one of its exact nominated transports.
/// Malformed, non-canonical, mismatched, non-nominated, and invalidly signed
/// inputs fail closed.
Future<VerifiedGroupReactionNotificationNomination?>
verifyGroupReactionNotificationNomination({
  required Map<String, dynamic> data,
  required String? localTransportPeerId,
  required VerifyGroupReactionPushSignature verifySignature,
}) async {
  final localTransport = _trimToNull(localTransportPeerId);
  final rawExtension = _trimToNull(data['notification_extension']?.toString());
  final senderPublicKey = _trimToNull(data['sender_public_key']?.toString());
  if (localTransport == null ||
      rawExtension == null ||
      senderPublicKey == null ||
      data['capability_version']?.toString() != 'group_reaction_v1' ||
      data['envelope_version']?.toString() != '1') {
    return null;
  }

  final Map<String, dynamic> extension;
  try {
    final decoded = jsonDecode(rawExtension);
    if (decoded is! Map) return null;
    extension = decoded.map<String, dynamic>(
      (key, value) => MapEntry(key.toString(), value),
    );
  } catch (_) {
    return null;
  }

  const exactKeys = <String>{
    'version',
    'transitionId',
    'action',
    'targetMessageId',
    'reactorPeerId',
    'reactorTransportPeerId',
    'replayRecipientSetHash',
    'notificationRecipientTransportPeerIds',
    'baseEnvelopeHash',
    'signatureAlgorithm',
    'signedPayload',
    'signature',
  };
  if (extension.keys.toSet().difference(exactKeys).isNotEmpty ||
      exactKeys.difference(extension.keys.toSet()).isNotEmpty ||
      extension['version'] != 1 ||
      extension['signatureAlgorithm'] != 'ed25519') {
    return null;
  }

  String? exactExtensionString(String key) {
    final value = extension[key];
    if (value is! String || value.isEmpty || value != value.trim()) return null;
    return value;
  }

  final transitionId = exactExtensionString('transitionId');
  final action = exactExtensionString('action');
  final targetMessageId = exactExtensionString('targetMessageId');
  final reactorPeerId = exactExtensionString('reactorPeerId');
  final reactorTransportPeerId = exactExtensionString('reactorTransportPeerId');
  final replayRecipientSetHash = exactExtensionString('replayRecipientSetHash');
  final baseEnvelopeHash = exactExtensionString('baseEnvelopeHash');
  final signedPayload = exactExtensionString('signedPayload');
  final signature = exactExtensionString('signature');
  final rawRecipients = extension['notificationRecipientTransportPeerIds'];
  if (transitionId == null ||
      action != GroupReactionPayload.actionAdd ||
      targetMessageId == null ||
      reactorPeerId == null ||
      reactorTransportPeerId == null ||
      replayRecipientSetHash == null ||
      baseEnvelopeHash == null ||
      signedPayload == null ||
      signature == null ||
      rawRecipients is! List) {
    return null;
  }

  final recipients = <String>[];
  for (final raw in rawRecipients) {
    if (raw is! String || raw.isEmpty || raw != raw.trim()) return null;
    recipients.add(raw);
  }
  final canonicalRecipients = recipients.toSet().toList(growable: false)
    ..sort();
  if (canonicalRecipients.length != recipients.length ||
      !_sameStrings(canonicalRecipients, recipients) ||
      !canonicalRecipients.contains(localTransport)) {
    return null;
  }

  final outerGroupId =
      _trimToNull(data['groupId']?.toString()) ??
      _trimToNull(data['group_id']?.toString());
  final outerTransitionId =
      _trimToNull(data['event_id']?.toString()) ??
      _trimToNull(data['reaction_id']?.toString());
  final outerTargetMessageId =
      _trimToNull(data['target_message_id']?.toString()) ??
      _trimToNull(data['targetMessageId']?.toString());
  final outerReactorPeerId =
      _trimToNull(data['reactor_peer_id']?.toString()) ??
      _trimToNull(data['sender_id']?.toString()) ??
      _trimToNull(data['from']?.toString());
  final outerReactorTransportPeerId = _trimToNull(
    data['reactor_transport_peer_id']?.toString(),
  );
  final outerBaseEnvelopeHash = _trimToNull(
    data['base_envelope_hash']?.toString(),
  );
  if (data['type']?.toString() != 'group_reaction' ||
      outerGroupId == null ||
      (outerTransitionId != null && transitionId != outerTransitionId) ||
      action != data['action']?.toString() ||
      targetMessageId != outerTargetMessageId ||
      reactorPeerId != outerReactorPeerId ||
      reactorTransportPeerId != outerReactorTransportPeerId ||
      baseEnvelopeHash != outerBaseEnvelopeHash) {
    return null;
  }

  final expectedSignedPayload =
      canonicalizeGroupEventLogPayload(<String, Object?>{
        'kind': 'group_reaction_notification',
        'version': 1,
        'transitionId': transitionId,
        'action': action,
        'targetMessageId': targetMessageId,
        'reactorPeerId': reactorPeerId,
        'reactorTransportPeerId': reactorTransportPeerId,
        'replayRecipientSetHash': replayRecipientSetHash,
        'notificationRecipientTransportPeerIds': canonicalRecipients,
        'baseEnvelopeHash': baseEnvelopeHash,
      });
  if (signedPayload != expectedSignedPayload) return null;

  bool validSignature;
  try {
    validSignature = await verifySignature(
      publicKey: senderPublicKey,
      signedPayload: signedPayload,
      signature: signature,
    );
  } catch (_) {
    return null;
  }
  if (!validSignature) return null;
  return VerifiedGroupReactionNotificationNomination(
    reactorTransportPeerId: reactorTransportPeerId,
    senderPublicKey: senderPublicKey,
    transitionId: transitionId,
  );
}

bool isCurrentGroupReactionKeyEpoch({
  required int requestedEpoch,
  required int? selectedEpoch,
  required int? latestEpoch,
}) =>
    requestedEpoch >= 0 &&
    selectedEpoch == requestedEpoch &&
    latestEpoch == requestedEpoch;

Future<BackgroundPushNotificationFallback> resolveBackgroundPushNotification(
  RemoteMessage message, {
  DecryptOneToOnePush? decryptOneToOne,
  DecryptGroupPush? decryptGroup,
  DirectMessageNotificationContext? directMessageContext,
  GroupMessageNotificationContext? groupMessageContext,
  DirectReactionNotificationContext? directReactionContext,
  GroupReactionNotificationContext? groupReactionContext,
  Locale? locale,
}) async {
  final fallback = buildBackgroundPushFallbackNotification(message);
  final data = message.data;
  final type = _trimToNull(data['type']?.toString());

  if (type == 'new_message') {
    return _resolveOneToOnePreview(
      data,
      fallback,
      decryptOneToOne: decryptOneToOne,
      context: directMessageContext,
      locale: locale,
    );
  }
  if (type == 'group_message') {
    return _resolveGroupPreview(
      data,
      fallback,
      decryptGroup: decryptGroup,
      context: groupMessageContext,
      locale: locale,
    );
  }
  if (type == 'message_reaction') {
    return _resolveDirectReactionPreview(
      data,
      fallback,
      decryptOneToOne: decryptOneToOne,
      context: directReactionContext,
    );
  }
  if (type == 'group_reaction') {
    return _resolveGroupReactionPreview(
      data,
      fallback,
      decryptGroup: decryptGroup,
      context: groupReactionContext,
      locale: locale,
    );
  }

  return fallback;
}

Future<BackgroundPushNotificationFallback> _resolveGroupReactionPreview(
  Map<String, dynamic> data,
  BackgroundPushNotificationFallback fallback, {
  required DecryptGroupPush? decryptGroup,
  required GroupReactionNotificationContext? context,
  required Locale? locale,
}) async {
  final actorName = _trimToNull(context?.actorUsername);
  final outerGroupId =
      _trimToNull(data['groupId']?.toString()) ??
      _trimToNull(data['group_id']?.toString());
  final outerSender =
      _trimToNull(data['reactor_peer_id']?.toString()) ??
      _trimToNull(data['sender_id']?.toString()) ??
      _trimToNull(data['from']?.toString());
  final outerEventId =
      _trimToNull(data['event_id']?.toString()) ??
      _trimToNull(data['reaction_id']?.toString());
  final outerTargetId =
      _trimToNull(data['target_message_id']?.toString()) ??
      _trimToNull(data['targetMessageId']?.toString());
  final outerAction = _trimToNull(data['action']?.toString());
  final outerTimestamp =
      _trimToNull(data['reaction_timestamp']?.toString()) ??
      _trimToNull(data['timestamp']?.toString());
  final keyEpoch = int.tryParse(data['keyEpoch']?.toString() ?? '');
  final ciphertext = _trimToNull(data['ciphertext']?.toString());
  final nonce = _trimToNull(data['nonce']?.toString());
  final authorizedOuterScope =
      context != null &&
      outerGroupId == context.groupId &&
      outerSender == context.actorPeerId &&
      outerTargetId == context.targetMessageId &&
      outerAction == GroupReactionPayload.actionAdd;
  final provisionalComparand = authorizedOuterScope && outerEventId != null
      ? BackgroundProvisionalGroupReactionNotificationComparand(
          groupId: context.groupId,
          messageId: context.targetMessageId,
          senderPeerId: context.actorPeerId,
          notificationEventIdentity: boundedReactionEventIdentity(outerEventId),
        )
      : null;
  final trustedFallback = BackgroundPushNotificationFallback(
    title:
        _trimToNull(context?.groupName) ??
        backgroundPushGroupReactionFallbackTitle,
    body: localizedGroupReactionNotificationBodyForTargetKind(
      actorName: actorName,
      targetKind: context?.targetKind ?? GroupReactionTargetKind.message,
      locale: locale,
    ),
    payload: fallback.payload,
    groupComparand: provisionalComparand,
  );

  if (!authorizedOuterScope) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_ANDROID_DATA_DECRYPT_FAIL',
      details: {
        'kind': 'group_reaction',
        'reason': 'group_reaction_context_or_input',
      },
    );
    throw const GroupReactionNotificationIntegrityException(
      'group_reaction_context_or_input',
    );
  }
  final authorizedContext = context;
  if (keyEpoch == null ||
      decryptGroup == null ||
      ciphertext == null ||
      nonce == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_ANDROID_DATA_DECRYPT_FAIL',
      details: {
        'kind': 'group_reaction',
        'reason': 'group_reaction_crypto_input_unavailable',
      },
    );
    if (outerEventId == null || authorizedContext.hasCurrentReaction) {
      throw const GroupReactionNotificationIntegrityException(
        'group_reaction_identity_or_state_unverifiable_without_plaintext',
      );
    }
    return trustedFallback;
  }

  try {
    final plaintext = await decryptGroup(
      groupId: outerGroupId!,
      keyEpoch: keyEpoch,
      ciphertext: ciphertext,
      nonce: nonce,
    );
    final payload = GroupReactionPayload.fromDecryptedJson(plaintext);
    final authenticatedTransitionId = payload?.eventId?.trim();
    final parityMatches =
        payload != null &&
        payload.action == GroupReactionPayload.actionAdd &&
        ((outerEventId == null &&
                authenticatedTransitionId != null &&
                authenticatedTransitionId.isNotEmpty &&
                (authorizedContext.expectedTransitionId == null ||
                    authenticatedTransitionId ==
                        authorizedContext.expectedTransitionId)) ||
            (outerEventId != null &&
                payload.notificationTransitionId == outerEventId)) &&
        payload.messageId == outerTargetId &&
        payload.senderPeerId == outerSender &&
        (outerTimestamp == null || payload.timestamp == outerTimestamp);
    if (!parityMatches) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PUSH_ANDROID_DATA_DECRYPT_FAIL',
        details: {
          'kind': 'group_reaction',
          'reason': 'group_reaction_parity_mismatch',
        },
      );
      throw const GroupReactionNotificationIntegrityException(
        'group_reaction_parity_mismatch',
      );
    }
    if (_groupReactionPayloadIsStale(payload, authorizedContext)) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PUSH_ANDROID_DATA_DECRYPT_FAIL',
        details: {
          'kind': 'group_reaction',
          'reason': 'group_reaction_stale_local_state',
        },
      );
      throw const GroupReactionNotificationIntegrityException(
        'group_reaction_stale_local_state',
      );
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_ANDROID_DATA_DECRYPT_OK',
      details: {'kind': 'group_reaction'},
    );
    return BackgroundPushNotificationFallback(
      title: authorizedContext.groupName,
      body: localizedGroupReactionNotificationBodyForTargetKind(
        actorName: authorizedContext.actorUsername,
        targetKind: authorizedContext.targetKind,
        locale: locale,
      ),
      payload: fallback.payload,
      groupComparand: BackgroundGroupReactionNotificationComparand(
        groupId: authorizedContext.groupId,
        reactionId: payload.id,
        messageId: payload.messageId,
        senderPeerId: payload.senderPeerId,
        timestamp: payload.timestamp,
        notificationEventIdentity: boundedReactionEventIdentity(
          payload.notificationTransitionId,
        ),
      ),
      resolvedEventIdentity: _resolvedAuthenticatedPushEventIdentity(
        kind: ConversationNotificationContentKind.reaction,
        canonicalEventId: payload.notificationTransitionId,
        outerEventId: outerEventId,
        targetMessageId: payload.messageId,
        action: payload.action,
      ),
    );
  } on GroupReactionNotificationIntegrityException {
    rethrow;
  } catch (_) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_ANDROID_DATA_DECRYPT_FAIL',
      details: {
        'kind': 'group_reaction',
        'reason': 'group_reaction_decrypt_error',
      },
    );
    if (outerEventId == null || authorizedContext.hasCurrentReaction) {
      throw const GroupReactionNotificationIntegrityException(
        'group_reaction_identity_or_state_unverifiable_without_plaintext',
      );
    }
    return trustedFallback;
  }
}

bool _groupReactionPayloadIsStale(
  GroupReactionPayload payload,
  GroupReactionNotificationContext context,
) {
  final incomingAt = DateTime.tryParse(payload.timestamp)?.toUtc();
  final currentTimestamp =
      context.currentReactionRemovedAt ?? context.currentReactionTimestamp;
  final currentAt = DateTime.tryParse(currentTimestamp ?? '')?.toUtc();
  if (incomingAt == null) return true;
  if (currentAt == null) return context.hasCurrentReaction;
  if (incomingAt.isBefore(currentAt)) return true;
  if (context.currentReactionAcknowledged &&
      context.currentReactionId == payload.id &&
      incomingAt == currentAt) {
    return true;
  }
  return context.currentReactionRemovedAt != null &&
      !incomingAt.isAfter(currentAt);
}

Future<BackgroundPushNotificationFallback> _resolveDirectReactionPreview(
  Map<String, dynamic> data,
  BackgroundPushNotificationFallback fallback, {
  required DecryptOneToOnePush? decryptOneToOne,
  required DirectReactionNotificationContext? context,
}) async {
  final trustedFallback = BackgroundPushNotificationFallback(
    title:
        _trimToNull(context?.actorUsername) ??
        backgroundPushReactionFallbackTitle,
    body: backgroundPushReactionFallbackBody,
    payload: fallback.payload,
  );
  final outerSender =
      _trimToNull(data['sender_id']?.toString()) ??
      _trimToNull(data['from']?.toString());
  final outerEventId =
      _trimToNull(data['event_id']?.toString()) ??
      _trimToNull(data['reaction_id']?.toString());
  final outerTargetId =
      _trimToNull(data['target_message_id']?.toString()) ??
      _trimToNull(data['targetMessageId']?.toString());
  final outerAction = _trimToNull(data['action']?.toString());
  final kem = _trimToNull(data['kem']?.toString());
  final ciphertext = _trimToNull(data['ciphertext']?.toString());
  final nonce = _trimToNull(data['nonce']?.toString());

  if (context == null ||
      outerSender != context.actorPeerId ||
      outerTargetId != context.targetMessageId ||
      outerAction != 'add' ||
      decryptOneToOne == null ||
      kem == null ||
      ciphertext == null ||
      nonce == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_ANDROID_DATA_DECRYPT_FAIL',
      details: {'kind': 'reaction', 'reason': 'reaction_context_or_input'},
    );
    return trustedFallback;
  }

  try {
    final plaintext = await decryptOneToOne(
      kem: kem,
      ciphertext: ciphertext,
      nonce: nonce,
    );
    final payload = ReactionPayload.fromDecryptedJson(plaintext);
    final parityMatches =
        payload != null &&
        payload.action == 'add' &&
        (outerEventId == null || payload.id == outerEventId) &&
        payload.messageId == outerTargetId &&
        payload.senderPeerId == outerSender;
    if (!parityMatches) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PUSH_ANDROID_DATA_DECRYPT_FAIL',
        details: {'kind': 'reaction', 'reason': 'reaction_parity_mismatch'},
      );
      throw const DirectReactionNotificationIntegrityException(
        'direct_reaction_parity_mismatch',
      );
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_ANDROID_DATA_DECRYPT_OK',
      details: {'kind': 'reaction'},
    );
    return BackgroundPushNotificationFallback(
      title: context.actorUsername,
      body: 'Reacted ${payload.emoji} to your message',
      payload: fallback.payload,
      resolvedEventIdentity: _resolvedAuthenticatedPushEventIdentity(
        kind: ConversationNotificationContentKind.reaction,
        canonicalEventId: payload.id,
        outerEventId: outerEventId,
        targetMessageId: payload.messageId,
        action: payload.action,
      ),
    );
  } on DirectReactionNotificationIntegrityException {
    rethrow;
  } catch (_) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_ANDROID_DATA_DECRYPT_FAIL',
      details: {'kind': 'reaction', 'reason': 'reaction_decrypt_error'},
    );
    return trustedFallback;
  }
}

Future<BackgroundPushNotificationFallback> _resolveOneToOnePreview(
  Map<String, dynamic> data,
  BackgroundPushNotificationFallback fallback, {
  required DecryptOneToOnePush? decryptOneToOne,
  required DirectMessageNotificationContext? context,
  required Locale? locale,
}) async {
  final trustedFallback = BackgroundPushNotificationFallback(
    title: _trimToNull(context?.senderUsername) ?? 'Mknoon',
    body: localizedNotificationMessage(locale: locale),
    payload: fallback.payload,
  );
  final outerSender =
      _trimToNull(data['sender_id']?.toString()) ??
      _trimToNull(data['senderId']?.toString()) ??
      _trimToNull(data['senderPeerId']?.toString()) ??
      _trimToNull(data['from']?.toString());
  final outerMessageId =
      _trimToNull(data['message_id']?.toString()) ??
      _trimToNull(data['messageId']?.toString()) ??
      _trimToNull(data['id']?.toString()) ??
      _trimToNull(data['msgId']?.toString());
  final kem = _trimToNull(data['kem']?.toString());
  final ciphertext = _trimToNull(data['ciphertext']?.toString());
  final nonce = _trimToNull(data['nonce']?.toString());
  if (context != null &&
      (outerSender != context.senderPeerId ||
          (context.expectedMessageId != null &&
              outerMessageId != context.expectedMessageId))) {
    throw const OrdinaryMessageNotificationIntegrityException(
      'direct_outer_context_mismatch',
    );
  }
  if (decryptOneToOne == null ||
      kem == null ||
      ciphertext == null ||
      nonce == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_ANDROID_DATA_DECRYPT_FAIL',
      details: {'kind': 'chat', 'reason': 'missing_chat_decrypt_input'},
    );
    return context == null ? fallback : trustedFallback;
  }

  final String plaintext;
  try {
    plaintext = await decryptOneToOne(
      kem: kem,
      ciphertext: ciphertext,
      nonce: nonce,
    );
  } on OrdinaryMessageNotificationIntegrityException {
    rethrow;
  } catch (_) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_ANDROID_DATA_DECRYPT_FAIL',
      details: {'kind': 'chat', 'reason': 'chat_decrypt_error'},
    );
    return context == null ? fallback : trustedFallback;
  }

  final payload = MessagePayload.fromDecryptedJson(plaintext);
  if (payload == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_ANDROID_DATA_DECRYPT_FAIL',
      details: {'kind': 'chat', 'reason': 'invalid_chat_plaintext'},
    );
    if (context != null) {
      throw const OrdinaryMessageNotificationIntegrityException(
        'invalid_direct_plaintext',
      );
    }
    return fallback;
  }
  if ((outerMessageId != null && payload.id != outerMessageId) ||
      (context != null &&
          (payload.senderPeerId != context.senderPeerId ||
              (context.expectedMessageId != null &&
                  payload.id != context.expectedMessageId)))) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_ANDROID_DATA_DECRYPT_FAIL',
      details: {'kind': 'chat', 'reason': 'chat_parity_mismatch'},
    );
    throw const OrdinaryMessageNotificationIntegrityException(
      'direct_plaintext_parity_mismatch',
    );
  }

  if (context != null && _trimToNull(context.senderUsername) == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_ANDROID_DATA_DECRYPT_OK',
      details: {'kind': 'chat', 'copy': 'trusted_generic'},
    );
    return BackgroundPushNotificationFallback(
      title: trustedFallback.title,
      body: trustedFallback.body,
      payload: trustedFallback.payload,
      resolvedEventIdentity: _resolvedAuthenticatedPushEventIdentity(
        kind: ConversationNotificationContentKind.message,
        canonicalEventId: payload.id,
        outerEventId: outerMessageId,
      ),
    );
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'PUSH_ANDROID_DATA_DECRYPT_OK',
    details: {'kind': 'chat'},
  );
  return BackgroundPushNotificationFallback(
    title:
        _trimToNull(context?.senderUsername) ??
        _trimToNull(payload.senderUsername) ??
        fallback.title,
    body: pushPreviewBody(
      payload.text,
      payload.media,
      privateMediaPolicy: payload.privateMediaPolicy,
      locale: locale,
    ),
    payload: fallback.payload,
    resolvedEventIdentity: _resolvedAuthenticatedPushEventIdentity(
      kind: ConversationNotificationContentKind.message,
      canonicalEventId: payload.id,
      outerEventId: outerMessageId,
    ),
  );
}

Future<BackgroundPushNotificationFallback> _resolveGroupPreview(
  Map<String, dynamic> data,
  BackgroundPushNotificationFallback fallback, {
  required DecryptGroupPush? decryptGroup,
  required GroupMessageNotificationContext? context,
  required Locale? locale,
}) async {
  final trustedMessageId = _trimToNull(context?.expectedMessageId);
  final trustedSenderPeerId = _trimToNull(context?.senderPeerId);
  final groupComparand =
      context != null && trustedMessageId != null && trustedSenderPeerId != null
      ? BackgroundGroupMessageNotificationComparand(
          groupId: context.groupId,
          messageId: trustedMessageId,
          senderPeerId: trustedSenderPeerId,
          senderTransportPeerId: context.senderTransportPeerId,
        )
      : null;
  final trustedFallback = BackgroundPushNotificationFallback(
    title: _trimToNull(context?.groupName) ?? 'Mknoon',
    body: localizedNotificationMessage(locale: locale),
    payload: fallback.payload,
    groupComparand: groupComparand,
  );
  final trustedPreviewUnavailableFallback = BackgroundPushNotificationFallback(
    title: _trimToNull(context?.groupName) ?? 'Mknoon',
    body: _groupUserPreviewBody(
      text: '',
      media: null,
      senderUsername: _trimToNull(context?.senderUsername),
      locale: locale,
    ),
    payload: fallback.payload,
    groupComparand: groupComparand,
  );
  final groupId =
      _trimToNull(data['groupId']?.toString()) ??
      _trimToNull(data['group_id']?.toString());
  final outerSender =
      _trimToNull(data['sender_id']?.toString()) ??
      _trimToNull(data['senderId']?.toString()) ??
      _trimToNull(data['senderPeerId']?.toString()) ??
      _trimToNull(data['from']?.toString());
  final outerSenderTransport = _trimToNull(
    data['sender_transport_peer_id']?.toString(),
  );
  final outerMessageId =
      _trimToNull(data['message_id']?.toString()) ??
      _trimToNull(data['messageId']?.toString()) ??
      _trimToNull(data['id']?.toString()) ??
      _trimToNull(data['msgId']?.toString());
  final ciphertext = _trimToNull(data['ciphertext']?.toString());
  final nonce = _trimToNull(data['nonce']?.toString());
  final keyEpoch = int.tryParse(
    data['keyEpoch']?.toString() ?? data['key_epoch']?.toString() ?? '',
  );
  final previewUnavailable = data['preview_unavailable']?.toString() == '1';
  if (context != null &&
      (groupId != context.groupId ||
          (context.senderTransportPeerId != null &&
              outerSenderTransport != context.senderTransportPeerId) ||
          (outerSender != null && outerSender != context.senderPeerId) ||
          (context.expectedMessageId != null &&
              outerMessageId != context.expectedMessageId))) {
    throw const OrdinaryMessageNotificationIntegrityException(
      'group_outer_context_mismatch',
    );
  }
  if (decryptGroup == null ||
      groupId == null ||
      keyEpoch == null ||
      ciphertext == null ||
      nonce == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_ANDROID_DATA_DECRYPT_FAIL',
      details: {'kind': 'group', 'reason': 'missing_group_decrypt_input'},
    );
    if (context != null && previewUnavailable) {
      return trustedPreviewUnavailableFallback;
    }
    throw const OrdinaryMessageNotificationIntegrityException(
      'missing_group_decrypt_input',
    );
  }

  final String plaintext;
  try {
    plaintext = await decryptGroup(
      groupId: groupId,
      keyEpoch: keyEpoch,
      ciphertext: ciphertext,
      nonce: nonce,
    );
  } on OrdinaryMessageNotificationIntegrityException {
    rethrow;
  } catch (_) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_ANDROID_DATA_DECRYPT_FAIL',
      details: {'kind': 'group', 'reason': 'group_decrypt_error'},
    );
    throw const OrdinaryMessageNotificationIntegrityException(
      'group_decrypt_error',
    );
  }

  final Map<String, dynamic> payload;
  try {
    final decoded = jsonDecode(plaintext);
    if (decoded is! Map) throw const FormatException('not a JSON object');
    payload = decoded.map<String, dynamic>(
      (key, value) => MapEntry(key.toString(), value),
    );
  } catch (_) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_ANDROID_DATA_DECRYPT_FAIL',
      details: {'kind': 'group', 'reason': 'invalid_group_plaintext'},
    );
    throw const OrdinaryMessageNotificationIntegrityException(
      'invalid_group_plaintext',
    );
  }
  final extra = payload['extra'] is Map
      ? Map<dynamic, dynamic>.from(payload['extra'] as Map)
      : const <dynamic, dynamic>{};
  final decodedGroupId =
      _trimToNull(payload['groupId']?.toString()) ??
      _trimToNull(payload['group_id']?.toString()) ??
      _trimToNull(extra['groupId']?.toString()) ??
      _trimToNull(extra['group_id']?.toString());
  final decodedMessageId =
      _trimToNull(payload['messageId']?.toString()) ??
      _trimToNull(payload['message_id']?.toString()) ??
      _trimToNull(payload['id']?.toString()) ??
      _trimToNull(extra['messageId']?.toString()) ??
      _trimToNull(extra['message_id']?.toString()) ??
      _trimToNull(extra['id']?.toString());
  final decodedSender =
      _trimToNull(payload['senderPeerId']?.toString()) ??
      _trimToNull(payload['senderId']?.toString()) ??
      _trimToNull(payload['sender_id']?.toString()) ??
      _trimToNull(extra['senderPeerId']?.toString()) ??
      _trimToNull(extra['senderId']?.toString()) ??
      _trimToNull(extra['sender_id']?.toString());
  if ((decodedMessageId == null && context != null) ||
      (decodedMessageId != null &&
          outerMessageId != null &&
          decodedMessageId != outerMessageId) ||
      (context != null &&
          ((decodedGroupId != null && decodedGroupId != context.groupId) ||
              (context.expectedMessageId != null &&
                  decodedMessageId != context.expectedMessageId) ||
              decodedSender == context.localPeerId ||
              (context.senderPeerId != null &&
                  decodedSender != context.senderPeerId)))) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_ANDROID_DATA_DECRYPT_FAIL',
      details: {'kind': 'group', 'reason': 'group_parity_mismatch'},
    );
    throw const OrdinaryMessageNotificationIntegrityException(
      'group_plaintext_parity_mismatch',
    );
  }

  final resolvedEventIdentity = decodedMessageId == null
      ? null
      : _resolvedAuthenticatedPushEventIdentity(
          kind: ConversationNotificationContentKind.message,
          canonicalEventId: decodedMessageId,
          outerEventId: outerMessageId,
        );
  final resolvedGroupComparand =
      context != null && decodedMessageId != null && decodedSender != null
      ? BackgroundGroupMessageNotificationComparand(
          groupId: context.groupId,
          messageId: decodedMessageId,
          senderPeerId: decodedSender,
          senderTransportPeerId: context.senderTransportPeerId,
        )
      : groupComparand;

  if (context != null && _trimToNull(context.groupName) == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_ANDROID_DATA_DECRYPT_OK',
      details: {'kind': 'group', 'copy': 'trusted_generic'},
    );
    return BackgroundPushNotificationFallback(
      title: trustedFallback.title,
      body: trustedFallback.body,
      payload: trustedFallback.payload,
      groupComparand: resolvedGroupComparand,
      resolvedEventIdentity: resolvedEventIdentity,
    );
  }

  final explicitPrivatePolicy = _decodeExplicitGroupPrivateMediaPolicy(
    payload,
    extra,
  );
  if (explicitPrivatePolicy?.requiresRedaction ?? false) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_ANDROID_DATA_DECRYPT_OK',
      details: {'kind': 'group'},
    );
    return BackgroundPushNotificationFallback(
      title: 'Mknoon',
      body: localizedGroupPrivateMediaNotificationBody(locale: locale),
      payload: fallback.payload,
      groupComparand: resolvedGroupComparand,
      resolvedEventIdentity: resolvedEventIdentity,
    );
  }
  final groupName =
      _trimToNull(context?.groupName) ??
      _trimToNull(payload['groupName']?.toString()) ??
      _trimToNull(extra['groupName']?.toString());
  final decryptedSenderUsername =
      _trimToNull(payload['senderUsername']?.toString()) ??
      _trimToNull(payload['username']?.toString());
  // Do not promote a decrypted actor name when the provider omitted
  // authoritative sender metadata. That dependency is explicit: no outer
  // sender means no actor prefix, even though the group content decrypts.
  final senderUsername = context == null
      ? decryptedSenderUsername
      : context.senderPeerId == null
      ? null
      : _trimToNull(context.senderUsername);
  final text = payload['text']?.toString() ?? '';
  final media = payload['media'] is List
      ? payload['media'] as List<dynamic>
      : extra['media'] is List
      ? extra['media'] as List<dynamic>
      : null;
  final systemPreview = _groupSystemPreviewBody(
    text: text,
    senderUsername: senderUsername,
    allowPayloadMemberName: context == null,
  );
  final body =
      systemPreview ??
      _groupUserPreviewBody(
        text: text,
        media: media,
        senderUsername: senderUsername,
        locale: locale,
      );

  emitFlowEvent(
    layer: 'FL',
    event: 'PUSH_ANDROID_DATA_DECRYPT_OK',
    details: {'kind': 'group'},
  );
  return BackgroundPushNotificationFallback(
    title: groupName ?? fallback.title,
    body: body,
    payload: fallback.payload,
    groupComparand: resolvedGroupComparand,
    resolvedEventIdentity: resolvedEventIdentity,
  );
}

ResolvedPushEventIdentity _resolvedAuthenticatedPushEventIdentity({
  required ConversationNotificationContentKind kind,
  required String canonicalEventId,
  required String? outerEventId,
  String? targetMessageId,
  String? action,
}) {
  if (outerEventId == null) {
    return ResolvedPushEventIdentity.authenticatedInner(
      kind: kind,
      canonicalEventId: canonicalEventId,
      targetMessageId: targetMessageId,
      action: action,
    );
  }
  return ResolvedPushEventIdentity.outerAndAuthenticated(
    kind: kind,
    canonicalEventId: canonicalEventId,
    targetMessageId: targetMessageId,
    action: action,
  );
}

GroupPrivateMediaPolicy? _decodeExplicitGroupPrivateMediaPolicy(
  Map<String, dynamic> payload,
  Map<dynamic, dynamic> extra,
) {
  final candidates = <Map<String, Object?>>[];
  for (final source in <Map<dynamic, dynamic>>[payload, extra]) {
    final present = <String, Object?>{};
    for (final key in GroupPrivateMediaPolicy.wireKeys) {
      if (source.containsKey(key)) present[key] = source[key];
    }
    if (present.isNotEmpty) candidates.add(present);
  }
  if (candidates.isEmpty) return null;

  final decoded = candidates
      .map(GroupPrivateMediaPolicy.fromWireExtras)
      .toList(growable: false);
  if (decoded.any((policy) => policy.isUnsupported)) {
    return const GroupPrivateMediaPolicy.unsupported();
  }
  final first = decoded.first;
  if (decoded.any((policy) => policy != first)) {
    return const GroupPrivateMediaPolicy.unsupported();
  }
  return first;
}

String pushPreviewBody(
  String text,
  List<dynamic>? media, {
  PrivateMediaPolicy privateMediaPolicy = const PrivateMediaPolicy.ordinary(),
  Locale? locale,
}) {
  if (privateMediaPolicy.requiresRedaction) {
    return localizedPrivateMediaNotificationBody(locale: locale);
  }
  final trimmed = text.trim();
  if (trimmed.isNotEmpty) {
    return _capPreview(trimmed);
  }
  if (media == null || media.isEmpty) {
    return localizedNotificationMessage(locale: locale);
  }

  final types = media
      .whereType<Map>()
      .map((item) => item['mediaType']?.toString())
      .whereType<String>()
      .toList();
  if (types.isEmpty) {
    return localizedNotificationMedia(locale: locale);
  }
  final first = types.first;
  if (types.any((type) => type != first)) {
    return localizedNotificationMedia(locale: locale);
  }
  return switch (first) {
    'image' => localizedNotificationPhoto(1, locale: locale),
    'video' => localizedNotificationVideo(1, locale: locale),
    'audio' => localizedNotificationVoiceMessage(locale: locale),
    'file' => localizedNotificationFile(1, locale: locale),
    _ => localizedNotificationMedia(locale: locale),
  };
}

String _groupUserPreviewBody({
  required String text,
  required List<dynamic>? media,
  required String? senderUsername,
  required Locale? locale,
}) {
  final preview = pushPreviewBody(text, media, locale: locale);
  return senderUsername == null ? preview : '$senderUsername: $preview';
}

String? _groupSystemPreviewBody({
  required String text,
  required String? senderUsername,
  bool allowPayloadMemberName = true,
}) {
  final trimmed = text.trim();
  if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) {
    return null;
  }

  final Map<String, dynamic> decoded;
  try {
    final raw = jsonDecode(trimmed);
    if (raw is Map<String, dynamic>) {
      decoded = raw;
    } else if (raw is Map) {
      decoded = raw.cast<String, dynamic>();
    } else {
      return null;
    }
  } catch (_) {
    return null;
  }

  final systemType = _trimToNull(decoded['__sys']?.toString());
  if (systemType == null) {
    return null;
  }
  if (systemType != 'member_joined') {
    return 'Group update';
  }

  if (!allowPayloadMemberName) {
    return 'Group update';
  }

  final member = decoded['member'];
  final memberUsername = member is Map
      ? _trimToNull(member['username']?.toString())
      : null;
  final displayName = memberUsername ?? senderUsername;
  return displayName == null
      ? 'A member joined the group'
      : '$displayName joined the group';
}

String _capPreview(String text, {int maxScalars = 140}) {
  final scalars = text.runes.toList();
  if (scalars.length <= maxScalars) {
    return text;
  }
  return String.fromCharCodes(scalars.take(maxScalars));
}

String? _trimToNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
