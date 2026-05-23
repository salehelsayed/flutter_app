import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/introduction/application/introduction_outbound_delivery.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_payload.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';

/// Passes (declines) an introduction on behalf of the current user.
///
/// Updates the appropriate party's status to passed, derives the new
/// overall status, and sends pass notifications to the introducer and
/// the other party. Returns the updated introduction model.
Future<IntroductionModel?> passIntroduction({
  required IntroductionRepository introRepo,
  required ContactRepository contactRepo,
  required P2PService p2pService,
  required Bridge bridge,
  required String introductionId,
  required String ownPeerId,
  required String ownUsername,
}) async {
  emitFlowEvent(
    layer: 'UC',
    event: 'PASS_INTRO_START',
    details: {'introductionId': introductionId},
  );

  final intro = await introRepo.getIntroduction(introductionId);
  if (intro == null) {
    emitFlowEvent(
      layer: 'UC',
      event: 'PASS_INTRO_NOT_FOUND',
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
      event: 'PASS_INTRO_NON_PARTY_CALLER',
      details: {'introductionId': introductionId, 'ownPeerId': ownPeerId},
    );
    return null;
  }

  if (_isTerminalOverallStatus(intro.status) ||
      _ownPartyStatus(intro: intro, isRecipient: isRecipient) !=
          IntroductionStatus.pending) {
    emitFlowEvent(
      layer: 'UC',
      event: 'PASS_INTRO_NOOP_TERMINAL_OR_ANSWERED',
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
      event: 'PASS_INTRO_STRANGER_KEY_MISMATCH',
      details: {'introductionId': introductionId, 'targetPeerId': otherPeerId},
    );
    return null;
  }

  final didUpdate = isRecipient
      ? await introRepo.updateRecipientStatus(
          introductionId,
          IntroductionStatus.passed,
        )
      : await introRepo.updateIntroducedStatus(
          introductionId,
          IntroductionStatus.passed,
        );
  if (!didUpdate) {
    final latestIntro = await introRepo.getIntroduction(introductionId);
    emitFlowEvent(
      layer: 'UC',
      event: 'PASS_INTRO_NOOP_GUARDED_UPDATE',
      details: {'introductionId': introductionId},
    );
    return latestIntro ?? intro;
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

  // Build pass payload
  final passPayload = IntroductionPayload(
    action: 'pass',
    introductionId: introductionId,
    responderId: ownPeerId,
    responderUsername: ownUsername,
    timestamp: DateTime.now().toUtc().toIso8601String(),
  );

  // Send to introducer
  await _sendPayloadToContact(
    introRepo: introRepo,
    p2pService: p2pService,
    bridge: bridge,
    contactRepo: contactRepo,
    ownPeerId: ownPeerId,
    targetPeerId: intro.introducerId,
    payload: passPayload,
  );

  // Send to other party — pass ML-KEM key from intro record since
  // the other party isn't a contact yet (contact lookup would miss them).
  await _sendPayloadToContact(
    introRepo: introRepo,
    p2pService: p2pService,
    bridge: bridge,
    contactRepo: contactRepo,
    ownPeerId: ownPeerId,
    targetPeerId: otherPeerId,
    payload: passPayload,
    mlKemPublicKey: otherMlKemKey,
  );

  final finalIntro = await introRepo.getIntroduction(introductionId);

  emitFlowEvent(
    layer: 'UC',
    event: 'PASS_INTRO_DONE',
    details: {
      'introductionId': introductionId,
      'overallStatus': newOverall.toDbString(),
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

/// Sends an introduction payload to a contact, encrypting with ML-KEM
/// if the contact has a public key.
Future<void> _sendPayloadToContact({
  required IntroductionRepository introRepo,
  required P2PService p2pService,
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

  await deliverIntroductionPayloadReliably(
    introRepo: introRepo,
    p2pService: p2pService,
    bridge: bridge,
    senderPeerId: ownPeerId,
    targetPeerId: targetPeerId,
    targetMlKemPublicKey: effectiveMlKemKey,
    payload: payload,
  );
}
