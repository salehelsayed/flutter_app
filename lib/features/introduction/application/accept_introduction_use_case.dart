import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/introduction/application/introduction_outbound_delivery.dart';
import 'package:flutter_app/features/introduction/application/handle_mutual_acceptance_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_outbox_delivery.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_payload.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';

/// Accepts an introduction on behalf of the current user.
///
/// Updates the appropriate party's status to accepted, derives the new
/// overall status, and sends accept notifications to the introducer and
/// the other party. Returns the updated introduction model.
Future<IntroductionModel?> acceptIntroduction({
  required IntroductionRepository introRepo,
  required ContactRepository contactRepo,
  required P2PService p2pService,
  required Bridge bridge,
  required String introductionId,
  required String ownPeerId,
  required String ownUsername,
  MessageRepository? messageRepo,
}) async {
  emitFlowEvent(
    layer: 'UC',
    event: 'ACCEPT_INTRO_START',
    details: {'introductionId': introductionId},
  );

  final intro = await introRepo.getIntroduction(introductionId);
  if (intro == null) {
    emitFlowEvent(
      layer: 'UC',
      event: 'ACCEPT_INTRO_NOT_FOUND',
      details: {'introductionId': introductionId},
    );
    return null;
  }

  // Determine if we are recipient or introduced
  final isRecipient = intro.recipientId == ownPeerId;
  final isIntroduced = intro.introducedId == ownPeerId;

  if (!isRecipient && !isIntroduced) {
    emitFlowEvent(
      layer: 'UC',
      event: 'ACCEPT_INTRO_NON_PARTY_CALLER',
      details: {'introductionId': introductionId, 'ownPeerId': ownPeerId},
    );
    return null;
  }

  if (_isTerminalOverallStatus(intro.status) ||
      _ownPartyStatus(intro: intro, isRecipient: isRecipient) !=
          IntroductionStatus.pending) {
    if (intro.status == IntroductionOverallStatus.mutualAccepted) {
      await handleMutualAcceptance(
        introduction: intro,
        contactRepo: contactRepo,
        ownPeerId: ownPeerId,
        messageRepo: messageRepo,
        bridge: bridge,
      );
    }
    emitFlowEvent(
      layer: 'UC',
      event: 'ACCEPT_INTRO_NOOP_TERMINAL_OR_ANSWERED',
      details: {
        'introductionId': introductionId,
        'status': intro.status.toDbString(),
      },
    );
    return intro;
  }

  final otherPeerId = isRecipient ? intro.introducedId : intro.recipientId;
  final otherMlKemKey = isRecipient
      ? intro.introducedMlKemPublicKey
      : intro.recipientMlKemPublicKey;
  if (await _hasIntroContactMlKemMismatch(
    contactRepo: contactRepo,
    targetPeerId: otherPeerId,
    introMlKemPublicKey: otherMlKemKey,
  )) {
    emitFlowEvent(
      layer: 'UC',
      event: 'ACCEPT_INTRO_STRANGER_KEY_MISMATCH',
      details: {'introductionId': introductionId, 'targetPeerId': otherPeerId},
    );
    return null;
  }

  final respondedAt = DateTime.now().toUtc().toIso8601String();
  final recipientStatus = isRecipient
      ? IntroductionStatus.accepted
      : intro.recipientStatus;
  final introducedStatus = isRecipient
      ? intro.introducedStatus
      : IntroductionStatus.accepted;
  final newOverall = IntroductionModel.deriveStatus(
    recipientStatus: recipientStatus,
    introducedStatus: introducedStatus,
    createdAt: intro.createdAt,
  );

  // Build accept payload
  final acceptPayload = IntroductionPayload(
    action: 'accept',
    introductionId: introductionId,
    responderId: ownPeerId,
    responderUsername: ownUsername,
    timestamp: respondedAt,
  );

  final deliveryForIntroducer = await _createPayloadDeliveryForContact(
    bridge: bridge,
    contactRepo: contactRepo,
    ownPeerId: ownPeerId,
    targetPeerId: intro.introducerId,
    payload: acceptPayload,
  );

  final deliveryForOtherParty = await _createPayloadDeliveryForContact(
    bridge: bridge,
    contactRepo: contactRepo,
    ownPeerId: ownPeerId,
    targetPeerId: otherPeerId,
    payload: acceptPayload,
    mlKemPublicKey: otherMlKemKey,
  );

  final didSave = await introRepo.saveIntroductionResponseWithOutboxDeliveries(
    introductionId: introductionId,
    isRecipient: isRecipient,
    responseStatus: IntroductionStatus.accepted,
    overallStatus: newOverall,
    respondedAt: respondedAt,
    deliveries: [deliveryForIntroducer, deliveryForOtherParty],
  );
  if (!didSave) {
    final latestIntro = await introRepo.getIntroduction(introductionId);
    emitFlowEvent(
      layer: 'UC',
      event: 'ACCEPT_INTRO_NOOP_GUARDED_UPDATE',
      details: {'introductionId': introductionId},
    );
    return latestIntro ?? intro;
  }
  var persistedIntro = await introRepo.getIntroduction(introductionId);
  final persistedOverall = persistedIntro?.status ?? newOverall;

  // Send to introducer.
  await deliverStagedIntroductionDelivery(
    introRepo: introRepo,
    p2pService: p2pService,
    delivery: deliveryForIntroducer,
  );

  // Send to other party.
  await deliverStagedIntroductionDelivery(
    introRepo: introRepo,
    p2pService: p2pService,
    delivery: deliveryForOtherParty,
  );

  if (persistedOverall == IntroductionOverallStatus.mutualAccepted) {
    emitFlowEvent(
      layer: 'UC',
      event: 'INTRO_MUTUAL_ACCEPTANCE',
      details: {'introductionId': introductionId},
    );

    persistedIntro ??= await introRepo.getIntroduction(introductionId);
    if (persistedIntro != null) {
      await handleMutualAcceptance(
        introduction: persistedIntro,
        contactRepo: contactRepo,
        ownPeerId: ownPeerId,
        messageRepo: messageRepo,
        bridge: bridge,
      );
    }
  }

  final finalIntro = await introRepo.getIntroduction(introductionId);

  emitFlowEvent(
    layer: 'UC',
    event: 'ACCEPT_INTRO_DONE',
    details: {
      'introductionId': introductionId,
      'overallStatus': (finalIntro?.status ?? persistedOverall).toDbString(),
    },
  );

  return finalIntro;
}

bool _isTerminalOverallStatus(IntroductionOverallStatus status) {
  return status == IntroductionOverallStatus.mutualAccepted ||
      status == IntroductionOverallStatus.passed ||
      status == IntroductionOverallStatus.expired ||
      status == IntroductionOverallStatus.alreadyConnected;
}

IntroductionStatus _ownPartyStatus({
  required IntroductionModel intro,
  required bool isRecipient,
}) {
  return isRecipient ? intro.recipientStatus : intro.introducedStatus;
}

Future<bool> _hasIntroContactMlKemMismatch({
  required ContactRepository contactRepo,
  required String targetPeerId,
  required String? introMlKemPublicKey,
}) async {
  if (introMlKemPublicKey == null || introMlKemPublicKey.isEmpty) {
    return false;
  }

  final contact = await contactRepo.getContact(targetPeerId);
  final contactMlKemPublicKey = contact?.mlKemPublicKey;
  if (contactMlKemPublicKey == null || contactMlKemPublicKey.isEmpty) {
    return false;
  }

  return contactMlKemPublicKey != introMlKemPublicKey;
}

/// Builds an introduction outbox row for a contact, encrypting with ML-KEM
/// if the contact has a public key.
Future<IntroductionOutboxDelivery> _createPayloadDeliveryForContact({
  required Bridge bridge,
  required ContactRepository contactRepo,
  required String ownPeerId,
  required String targetPeerId,
  required IntroductionPayload payload,
  String? mlKemPublicKey,
}) async {
  // Use provided key first (from intro record), then fall back to contact lookup.
  String? effectiveMlKemKey = mlKemPublicKey;
  if (effectiveMlKemKey == null) {
    final contact = await contactRepo.getContact(targetPeerId);
    effectiveMlKemKey = contact?.mlKemPublicKey;
  }

  return createIntroductionOutboxDelivery(
    bridge: bridge,
    senderPeerId: ownPeerId,
    targetPeerId: targetPeerId,
    targetMlKemPublicKey: effectiveMlKemKey,
    payload: payload,
  );
}
