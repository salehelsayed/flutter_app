import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/introduction/application/handle_mutual_acceptance_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_payload.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';

/// Result of processing an incoming introduction message.
enum HandleIntroductionResult { success, alreadyExists, blocked, error }

/// Processes an incoming introduction payload and persists the result.
///
/// For 'send' actions: creates a new introduction record.
/// For 'accept'/'pass' actions: updates the appropriate party's status
/// and derives the new overall status.
Future<(HandleIntroductionResult, IntroductionModel?)>
    handleIncomingIntroduction({
  required IntroductionPayload payload,
  required IntroductionRepository introRepo,
  required ContactRepository contactRepo,
  required String ownPeerId,
  MessageRepository? messageRepo,
}) async {
  emitFlowEvent(
    layer: 'UC',
    event: 'HANDLE_INCOMING_INTRO_START',
    details: {
      'action': payload.action,
      'introductionId': payload.introductionId,
    },
  );

  try {
    if (payload.action == 'send') {
      return await _handleSend(
        payload: payload,
        introRepo: introRepo,
        ownPeerId: ownPeerId,
      );
    } else if (payload.action == 'accept' || payload.action == 'pass') {
      return await _handleResponse(
        payload: payload,
        introRepo: introRepo,
        contactRepo: contactRepo,
        ownPeerId: ownPeerId,
        messageRepo: messageRepo,
      );
    }

    emitFlowEvent(
      layer: 'UC',
      event: 'HANDLE_INCOMING_INTRO_UNKNOWN_ACTION',
      details: {'action': payload.action},
    );
    return (HandleIntroductionResult.error, null);
  } catch (e) {
    emitFlowEvent(
      layer: 'UC',
      event: 'HANDLE_INCOMING_INTRO_ERROR',
      details: {
        'introductionId': payload.introductionId,
        'error': e.toString(),
      },
    );
    return (HandleIntroductionResult.error, null);
  }
}

Future<(HandleIntroductionResult, IntroductionModel?)> _handleSend({
  required IntroductionPayload payload,
  required IntroductionRepository introRepo,
  required String ownPeerId,
}) async {
  // Check if introduction already exists
  final existing = await introRepo.getIntroduction(payload.introductionId);
  if (existing != null) {
    emitFlowEvent(
      layer: 'UC',
      event: 'HANDLE_INCOMING_INTRO_ALREADY_EXISTS',
      details: {'introductionId': payload.introductionId},
    );
    return (HandleIntroductionResult.alreadyExists, existing);
  }

  final model = IntroductionModel(
    id: payload.introductionId,
    introducerId: payload.introducerId ?? '',
    recipientId: payload.recipientId ?? '',
    introducedId: payload.introducedId ?? '',
    createdAt: payload.timestamp,
    introducerUsername: payload.introducerUsername,
    recipientUsername: payload.recipientUsername,
    introducedUsername: payload.introducedUsername,
    introducedPublicKey: payload.introducedPublicKey,
    introducedMlKemPublicKey: payload.introducedMlKemPublicKey,
    recipientPublicKey: payload.recipientPublicKey,
    recipientMlKemPublicKey: payload.recipientMlKemPublicKey,
  );

  await introRepo.saveIntroduction(model);

  emitFlowEvent(
    layer: 'UC',
    event: 'HANDLE_INCOMING_INTRO_SAVED',
    details: {
      'introductionId': payload.introductionId,
      'introducerId': payload.introducerId ?? '',
    },
  );

  return (HandleIntroductionResult.success, model);
}

Future<(HandleIntroductionResult, IntroductionModel?)> _handleResponse({
  required IntroductionPayload payload,
  required IntroductionRepository introRepo,
  required ContactRepository contactRepo,
  required String ownPeerId,
  MessageRepository? messageRepo,
}) async {
  final existing = await introRepo.getIntroduction(payload.introductionId);
  if (existing == null) {
    emitFlowEvent(
      layer: 'UC',
      event: 'HANDLE_INCOMING_INTRO_NOT_FOUND',
      details: {'introductionId': payload.introductionId},
    );
    return (HandleIntroductionResult.error, null);
  }

  // Determine if the responder is the recipient or the introduced party
  final responderId = payload.responderId ?? '';
  final isRecipient = responderId == existing.recipientId;
  final isIntroduced = responderId == existing.introducedId;

  if (!isRecipient && !isIntroduced) {
    emitFlowEvent(
      layer: 'UC',
      event: 'HANDLE_INCOMING_INTRO_UNKNOWN_RESPONDER',
      details: {
        'introductionId': payload.introductionId,
        'responderId': responderId,
      },
    );
    return (HandleIntroductionResult.error, null);
  }

  final status = payload.action == 'accept'
      ? IntroductionStatus.accepted
      : IntroductionStatus.passed;

  if (isRecipient) {
    await introRepo.updateRecipientStatus(payload.introductionId, status);
  } else {
    await introRepo.updateIntroducedStatus(payload.introductionId, status);
  }

  // Re-fetch to get updated individual statuses
  final updatedIntro =
      await introRepo.getIntroduction(payload.introductionId);
  if (updatedIntro == null) {
    return (HandleIntroductionResult.error, null);
  }

  // Derive and update overall status
  final newOverall = IntroductionModel.deriveStatus(
    recipientStatus: updatedIntro.recipientStatus,
    introducedStatus: updatedIntro.introducedStatus,
    createdAt: updatedIntro.createdAt,
  );
  await introRepo.updateOverallStatus(payload.introductionId, newOverall);

  if (newOverall == IntroductionOverallStatus.mutualAccepted) {
    final latestIntro =
        await introRepo.getIntroduction(payload.introductionId);
    if (latestIntro != null) {
      await handleMutualAcceptance(
        introduction: latestIntro,
        contactRepo: contactRepo,
        ownPeerId: ownPeerId,
        messageRepo: messageRepo,
      );
    }
  }

  final finalIntro =
      await introRepo.getIntroduction(payload.introductionId);

  emitFlowEvent(
    layer: 'UC',
    event: 'HANDLE_INCOMING_INTRO_STATUS_UPDATED',
    details: {
      'introductionId': payload.introductionId,
      'action': payload.action,
      'responderId': responderId,
      'newOverall': newOverall.toDbString(),
    },
  );

  return (HandleIntroductionResult.success, finalIntro);
}
