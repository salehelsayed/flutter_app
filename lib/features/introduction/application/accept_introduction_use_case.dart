import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/introduction/application/handle_mutual_acceptance_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
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

  if (isRecipient) {
    await introRepo.updateRecipientStatus(
        introductionId, IntroductionStatus.accepted);
  } else {
    await introRepo.updateIntroducedStatus(
        introductionId, IntroductionStatus.accepted);
  }

  // Derive new overall status
  final updatedIntro = await introRepo.getIntroduction(introductionId);
  if (updatedIntro == null) return null;

  final newOverall = IntroductionModel.deriveStatus(
    recipientStatus: updatedIntro.recipientStatus,
    introducedStatus: updatedIntro.introducedStatus,
    createdAt: updatedIntro.createdAt,
  );
  await introRepo.updateOverallStatus(introductionId, newOverall);

  // Build accept payload
  final acceptPayload = IntroductionPayload(
    action: 'accept',
    introductionId: introductionId,
    responderId: ownPeerId,
    responderUsername: ownUsername,
    timestamp: DateTime.now().toUtc().toIso8601String(),
  );

  // Send to introducer
  await _sendPayloadToContact(
    p2pService: p2pService,
    bridge: bridge,
    contactRepo: contactRepo,
    ownPeerId: ownPeerId,
    targetPeerId: intro.introducerId,
    payload: acceptPayload,
  );

  // Send to other party
  final otherPeerId =
      isRecipient ? intro.introducedId : intro.recipientId;
  await _sendPayloadToContact(
    p2pService: p2pService,
    bridge: bridge,
    contactRepo: contactRepo,
    ownPeerId: ownPeerId,
    targetPeerId: otherPeerId,
    payload: acceptPayload,
  );

  if (newOverall == IntroductionOverallStatus.mutualAccepted) {
    emitFlowEvent(
      layer: 'UC',
      event: 'INTRO_MUTUAL_ACCEPTANCE',
      details: {'introductionId': introductionId},
    );

    final latestIntro = await introRepo.getIntroduction(introductionId);
    if (latestIntro != null) {
      await handleMutualAcceptance(
        introduction: latestIntro,
        contactRepo: contactRepo,
        ownPeerId: ownPeerId,
        messageRepo: messageRepo,
      );
    }
  }

  final finalIntro = await introRepo.getIntroduction(introductionId);

  emitFlowEvent(
    layer: 'UC',
    event: 'ACCEPT_INTRO_DONE',
    details: {
      'introductionId': introductionId,
      'overallStatus': newOverall.toDbString(),
    },
  );

  return finalIntro;
}

/// Sends an introduction payload to a contact, encrypting with ML-KEM
/// if the contact has a public key. Falls back to relay inbox if direct
/// send fails (e.g. the other party in an introduction isn't a contact
/// yet, so we have no direct address for them).
Future<void> _sendPayloadToContact({
  required P2PService p2pService,
  required Bridge bridge,
  required ContactRepository contactRepo,
  required String ownPeerId,
  required String targetPeerId,
  required IntroductionPayload payload,
}) async {
  final contact = await contactRepo.getContact(targetPeerId);
  if (contact != null && contact.mlKemPublicKey != null) {
    final encrypted = await callEncryptMessage(
      bridge: bridge,
      recipientMlKemPublicKey: contact.mlKemPublicKey!,
      plaintext: payload.toInnerJson(),
    );
    if (encrypted['ok'] == true) {
      final envelope = IntroductionPayload.buildEncryptedEnvelope(
        senderPeerId: ownPeerId,
        kem: encrypted['kem'] as String,
        ciphertext: encrypted['ciphertext'] as String,
        nonce: encrypted['nonce'] as String,
      );
      final sent = await p2pService.sendMessage(targetPeerId, envelope);
      if (sent) return;

      // Direct send failed — fall back to relay inbox
      emitFlowEvent(
        layer: 'UC',
        event: 'INTRO_ACCEPT_DIRECT_SEND_FAILED_TRYING_INBOX',
        details: {'targetPeerId': targetPeerId},
      );
      await p2pService.storeInInbox(targetPeerId, envelope);
      return;
    }
  }

  // Fall back to v1 plaintext
  final sent = await p2pService.sendMessage(targetPeerId, payload.toJson());
  if (!sent) {
    emitFlowEvent(
      layer: 'UC',
      event: 'INTRO_ACCEPT_DIRECT_SEND_FAILED_TRYING_INBOX',
      details: {'targetPeerId': targetPeerId},
    );
    await p2pService.storeInInbox(targetPeerId, payload.toJson());
  }
}
