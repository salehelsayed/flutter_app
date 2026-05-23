import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/introduction/application/handle_mutual_acceptance_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_payload.dart';
import 'package:flutter_app/features/introduction/domain/models/pending_introduction_response.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';

/// Result of processing an incoming introduction message.
enum HandleIntroductionResult {
  success,
  alreadyExists,
  deferred,
  blocked,
  rejected,
  error,
}

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
  String? transportSenderPeerId,
  MessageRepository? messageRepo,
  Bridge? bridge,
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
    if (_hasTransportSenderMismatch(
      payload: payload,
      transportSenderPeerId: transportSenderPeerId,
    )) {
      emitFlowEvent(
        layer: 'UC',
        event: 'HANDLE_INCOMING_INTRO_TRANSPORT_SENDER_MISMATCH',
        details: {
          'introductionId': payload.introductionId,
          'action': payload.action,
          'transportSenderPeerId': transportSenderPeerId ?? '',
        },
      );
      return (HandleIntroductionResult.rejected, null);
    }

    if (payload.action == 'send') {
      return await _handleSend(
        payload: payload,
        introRepo: introRepo,
        contactRepo: contactRepo,
        ownPeerId: ownPeerId,
        messageRepo: messageRepo,
        bridge: bridge,
      );
    } else if (payload.action == 'accept' || payload.action == 'pass') {
      return await _handleResponse(
        payload: payload,
        introRepo: introRepo,
        contactRepo: contactRepo,
        ownPeerId: ownPeerId,
        transportSenderPeerId: transportSenderPeerId,
        messageRepo: messageRepo,
        bridge: bridge,
      );
    }

    emitFlowEvent(
      layer: 'UC',
      event: 'HANDLE_INCOMING_INTRO_UNKNOWN_ACTION',
      details: {'action': payload.action},
    );
    return (HandleIntroductionResult.rejected, null);
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

bool _hasTransportSenderMismatch({
  required IntroductionPayload payload,
  required String? transportSenderPeerId,
}) {
  if (transportSenderPeerId == null || transportSenderPeerId.isEmpty) {
    return false;
  }

  if (payload.action == 'send') {
    return payload.introducerId != transportSenderPeerId;
  }

  if (payload.action == 'accept' || payload.action == 'pass') {
    return payload.responderId != transportSenderPeerId;
  }

  return false;
}

Future<(HandleIntroductionResult, IntroductionModel?)> _handleSend({
  required IntroductionPayload payload,
  required IntroductionRepository introRepo,
  required ContactRepository contactRepo,
  required String ownPeerId,
  MessageRepository? messageRepo,
  Bridge? bridge,
}) async {
  final introducerId = payload.introducerId?.trim() ?? '';
  final recipientId = payload.recipientId?.trim() ?? '';
  final introducedId = payload.introducedId?.trim() ?? '';
  if (introducerId.isEmpty || recipientId.isEmpty || introducedId.isEmpty) {
    emitFlowEvent(
      layer: 'UC',
      event: 'HANDLE_INCOMING_INTRO_INVALID_SEND',
      details: {
        'introductionId': payload.introductionId,
        'hasIntroducerId': introducerId.isNotEmpty,
        'hasRecipientId': recipientId.isNotEmpty,
        'hasIntroducedId': introducedId.isNotEmpty,
      },
    );
    return (HandleIntroductionResult.rejected, null);
  }

  final isRecipient = ownPeerId == recipientId;
  final isIntroduced = ownPeerId == introducedId;
  if (!isRecipient && !isIntroduced) {
    emitFlowEvent(
      layer: 'UC',
      event: 'HANDLE_INCOMING_INTRO_SEND_NOT_ADDRESSED',
      details: {
        'introductionId': payload.introductionId,
        'ownPeerId': ownPeerId,
      },
    );
    return (HandleIntroductionResult.rejected, null);
  }

  // Check if introduction already exists
  final existing = await introRepo.getIntroduction(payload.introductionId);
  if (existing != null) {
    await _replayPendingResponses(
      introductionId: payload.introductionId,
      introRepo: introRepo,
      contactRepo: contactRepo,
      ownPeerId: ownPeerId,
      messageRepo: messageRepo,
      bridge: bridge,
    );
    final latest = await introRepo.getIntroduction(payload.introductionId);
    emitFlowEvent(
      layer: 'UC',
      event: 'HANDLE_INCOMING_INTRO_ALREADY_EXISTS',
      details: {'introductionId': payload.introductionId},
    );
    return (HandleIntroductionResult.alreadyExists, latest ?? existing);
  }

  final existingPairIntroductions = await _loadExistingPairIntroductions(
    introRepo: introRepo,
    payload: payload,
  );
  final latestPairIntroduction = _latestIntroduction(existingPairIntroductions);
  if (latestPairIntroduction != null &&
      !_isIncomingIntroductionNewerThan(
        existingIntroduction: latestPairIntroduction,
        incomingCreatedAt: payload.timestamp,
      )) {
    emitFlowEvent(
      layer: 'UC',
      event: 'HANDLE_INCOMING_INTRO_ALREADY_EXISTS',
      details: {'introductionId': latestPairIntroduction.id},
    );
    return (HandleIntroductionResult.alreadyExists, latestPairIntroduction);
  }

  final model = IntroductionModel(
    id: payload.introductionId,
    introducerId: introducerId,
    recipientId: recipientId,
    introducedId: introducedId,
    createdAt: payload.timestamp,
    introducerUsername: payload.introducerUsername,
    recipientUsername: payload.recipientUsername,
    introducedUsername: payload.introducedUsername,
    introducedPublicKey: payload.introducedPublicKey,
    introducedMlKemPublicKey: payload.introducedMlKemPublicKey,
    recipientPublicKey: payload.recipientPublicKey,
    recipientMlKemPublicKey: payload.recipientMlKemPublicKey,
  );

  if (existingPairIntroductions.isEmpty) {
    await introRepo.saveIntroduction(model);
  } else {
    await introRepo.replaceIntroductionWithPendingResponseMigration(
      intro: model,
      deliveries: const [],
      replacedIntroductionIds: existingPairIntroductions
          .map((intro) => intro.id)
          .toList(growable: false),
    );
  }

  // Check if the other party is already a contact
  final otherPeerId = isRecipient ? introducedId : recipientId;

  if (otherPeerId.isNotEmpty && await contactRepo.contactExists(otherPeerId)) {
    await introRepo.updateOverallStatus(
      model.id,
      IntroductionOverallStatus.alreadyConnected,
    );

    emitFlowEvent(
      layer: 'UC',
      event: 'HANDLE_INCOMING_INTRO_ALREADY_CONNECTED',
      details: {
        'introductionId': payload.introductionId,
        'otherPeerId': otherPeerId,
      },
    );
  }

  await _replayPendingResponses(
    introductionId: payload.introductionId,
    introRepo: introRepo,
    contactRepo: contactRepo,
    ownPeerId: ownPeerId,
    messageRepo: messageRepo,
    bridge: bridge,
  );

  final finalIntro = await introRepo.getIntroduction(model.id);

  emitFlowEvent(
    layer: 'UC',
    event: 'HANDLE_INCOMING_INTRO_SAVED',
    details: {
      'introductionId': payload.introductionId,
      'introducerId': introducerId,
    },
  );

  return (HandleIntroductionResult.success, finalIntro ?? model);
}

Future<List<IntroductionModel>> _loadExistingPairIntroductions({
  required IntroductionRepository introRepo,
  required IntroductionPayload payload,
}) async {
  final recipientId = payload.recipientId?.trim() ?? '';
  final introducedId = payload.introducedId?.trim() ?? '';
  final introducerId = payload.introducerId?.trim() ?? '';
  if (recipientId.isEmpty || introducedId.isEmpty || introducerId.isEmpty) {
    return const <IntroductionModel>[];
  }

  final byRecipient = await introRepo.getIntroductionsByRecipient(recipientId);
  final byRecipientCounterpart = await introRepo.getIntroductionsByRecipient(
    introducedId,
  );
  final byIntroduced = await introRepo.getIntroductionsByIntroduced(
    introducedId,
  );
  final byIntroducedCounterpart = await introRepo.getIntroductionsByIntroduced(
    recipientId,
  );
  final matchesById = <String, IntroductionModel>{};

  for (final intro in [
    ...byRecipient,
    ...byRecipientCounterpart,
    ...byIntroduced,
    ...byIntroducedCounterpart,
  ]) {
    if (intro.introducerId != introducerId) continue;
    if (!_isSameIntroductionPair(
      introRecipientId: intro.recipientId,
      introIntroducedId: intro.introducedId,
      recipientId: recipientId,
      introducedId: introducedId,
    )) {
      continue;
    }
    matchesById[intro.id] = intro;
  }

  return matchesById.values.toList(growable: false);
}

IntroductionModel? _latestIntroduction(List<IntroductionModel> introductions) {
  if (introductions.isEmpty) return null;

  final sorted = [...introductions]
    ..sort(
      (a, b) =>
          DateTime.parse(a.createdAt).compareTo(DateTime.parse(b.createdAt)),
    );
  return sorted.last;
}

bool _isIncomingIntroductionNewerThan({
  required IntroductionModel existingIntroduction,
  required String incomingCreatedAt,
}) {
  return DateTime.parse(
    incomingCreatedAt,
  ).isAfter(DateTime.parse(existingIntroduction.createdAt));
}

bool _isSameIntroductionPair({
  required String introRecipientId,
  required String introIntroducedId,
  required String recipientId,
  required String introducedId,
}) {
  final sameDirection =
      introRecipientId == recipientId && introIntroducedId == introducedId;
  final reversedDirection =
      introRecipientId == introducedId && introIntroducedId == recipientId;
  return sameDirection || reversedDirection;
}

Future<(HandleIntroductionResult, IntroductionModel?)> _handleResponse({
  required IntroductionPayload payload,
  required IntroductionRepository introRepo,
  required ContactRepository contactRepo,
  required String ownPeerId,
  String? transportSenderPeerId,
  MessageRepository? messageRepo,
  Bridge? bridge,
}) async {
  final responderId = payload.responderId ?? '';
  if (responderId.isEmpty) {
    emitFlowEvent(
      layer: 'UC',
      event: 'HANDLE_INCOMING_INTRO_MISSING_RESPONDER',
      details: {'introductionId': payload.introductionId},
    );
    return (HandleIntroductionResult.rejected, null);
  }

  final existing = await introRepo.getIntroduction(payload.introductionId);
  if (existing == null) {
    await introRepo.savePendingResponse(
      PendingIntroductionResponse.fromPayload(
        payload,
        transportSenderPeerId: transportSenderPeerId,
      ),
    );
    emitFlowEvent(
      layer: 'UC',
      event: 'HANDLE_INCOMING_INTRO_RESPONSE_DEFERRED',
      details: {
        'introductionId': payload.introductionId,
        'responderId': responderId,
        'action': payload.action,
      },
    );
    return (HandleIntroductionResult.deferred, null);
  }

  return _applyResponseToExistingIntroduction(
    payload: payload,
    existing: existing,
    introRepo: introRepo,
    contactRepo: contactRepo,
    ownPeerId: ownPeerId,
    messageRepo: messageRepo,
    bridge: bridge,
  );
}

Future<(HandleIntroductionResult, IntroductionModel?)>
_applyResponseToExistingIntroduction({
  required IntroductionPayload payload,
  required IntroductionModel existing,
  required IntroductionRepository introRepo,
  required ContactRepository contactRepo,
  required String ownPeerId,
  MessageRepository? messageRepo,
  Bridge? bridge,
}) async {
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
    return (HandleIntroductionResult.rejected, null);
  }

  final status = payload.action == 'accept'
      ? IntroductionStatus.accepted
      : IntroductionStatus.passed;

  if (_isTerminalOverallStatus(existing.status)) {
    return _handleTerminalResponseReplay(
      payload: payload,
      existing: existing,
      contactRepo: contactRepo,
      ownPeerId: ownPeerId,
      messageRepo: messageRepo,
      bridge: bridge,
    );
  }

  final existingPartyStatus = isRecipient
      ? existing.recipientStatus
      : existing.introducedStatus;
  if (existingPartyStatus != IntroductionStatus.pending) {
    final latestIntro = existingPartyStatus == status
        ? await _reconcilePendingDerivedTerminalStatus(
            existing: existing,
            introRepo: introRepo,
            contactRepo: contactRepo,
            ownPeerId: ownPeerId,
            messageRepo: messageRepo,
            bridge: bridge,
          )
        : existing;
    final result = existingPartyStatus == status
        ? HandleIntroductionResult.alreadyExists
        : HandleIntroductionResult.rejected;
    emitFlowEvent(
      layer: 'UC',
      event: 'HANDLE_INCOMING_INTRO_ALREADY_ANSWERED',
      details: {
        'introductionId': payload.introductionId,
        'responderId': responderId,
        'action': payload.action,
        'existingStatus': existingPartyStatus.toDbString(),
      },
    );
    return (result, latestIntro);
  }

  final didUpdate = isRecipient
      ? await introRepo.updateRecipientStatus(payload.introductionId, status)
      : await introRepo.updateIntroducedStatus(payload.introductionId, status);
  if (!didUpdate) {
    final latestIntro =
        await introRepo.getIntroduction(payload.introductionId) ?? existing;
    if (_isTerminalOverallStatus(latestIntro.status)) {
      return _handleTerminalResponseReplay(
        payload: payload,
        existing: latestIntro,
        contactRepo: contactRepo,
        ownPeerId: ownPeerId,
        messageRepo: messageRepo,
        bridge: bridge,
      );
    }
    final latestPartyStatus = isRecipient
        ? latestIntro.recipientStatus
        : latestIntro.introducedStatus;
    if (latestPartyStatus != IntroductionStatus.pending &&
        latestPartyStatus != status) {
      return (HandleIntroductionResult.rejected, latestIntro);
    }
    final reconciledIntro = latestPartyStatus == status
        ? await _reconcilePendingDerivedTerminalStatus(
            existing: latestIntro,
            introRepo: introRepo,
            contactRepo: contactRepo,
            ownPeerId: ownPeerId,
            messageRepo: messageRepo,
            bridge: bridge,
          )
        : latestIntro;
    emitFlowEvent(
      layer: 'UC',
      event: 'HANDLE_INCOMING_INTRO_GUARDED_UPDATE_SKIPPED',
      details: {'introductionId': payload.introductionId},
    );
    return (HandleIntroductionResult.alreadyExists, reconciledIntro);
  }

  // Re-fetch to get updated individual statuses
  final updatedIntro = await introRepo.getIntroduction(payload.introductionId);
  if (updatedIntro == null) {
    return (HandleIntroductionResult.error, null);
  }
  if (_isTerminalOverallStatus(updatedIntro.status)) {
    return _handleTerminalResponseReplay(
      payload: payload,
      existing: updatedIntro,
      contactRepo: contactRepo,
      ownPeerId: ownPeerId,
      messageRepo: messageRepo,
      bridge: bridge,
    );
  }

  // Derive and update overall status
  final newOverall = IntroductionModel.deriveStatus(
    recipientStatus: updatedIntro.recipientStatus,
    introducedStatus: updatedIntro.introducedStatus,
    createdAt: updatedIntro.createdAt,
  );
  await introRepo.updateOverallStatus(payload.introductionId, newOverall);

  if (newOverall == IntroductionOverallStatus.mutualAccepted) {
    final latestIntro = await introRepo.getIntroduction(payload.introductionId);
    if (latestIntro != null) {
      await handleMutualAcceptance(
        introduction: latestIntro,
        contactRepo: contactRepo,
        ownPeerId: ownPeerId,
        messageRepo: messageRepo,
        bridge: bridge,
      );
    }
  }

  final finalIntro = await introRepo.getIntroduction(payload.introductionId);

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

Future<IntroductionModel> _reconcilePendingDerivedTerminalStatus({
  required IntroductionModel existing,
  required IntroductionRepository introRepo,
  required ContactRepository contactRepo,
  required String ownPeerId,
  MessageRepository? messageRepo,
  Bridge? bridge,
}) async {
  if (existing.status != IntroductionOverallStatus.pending) {
    return existing;
  }

  final derived = IntroductionModel.deriveStatus(
    recipientStatus: existing.recipientStatus,
    introducedStatus: existing.introducedStatus,
    createdAt: existing.createdAt,
  );
  if (derived == IntroductionOverallStatus.pending) {
    return existing;
  }

  await introRepo.updateOverallStatus(existing.id, derived);
  final latestIntro =
      await introRepo.getIntroduction(existing.id) ??
      existing.copyWith(status: derived);
  if (latestIntro.status == IntroductionOverallStatus.mutualAccepted) {
    await handleMutualAcceptance(
      introduction: latestIntro,
      contactRepo: contactRepo,
      ownPeerId: ownPeerId,
      messageRepo: messageRepo,
      bridge: bridge,
    );
  }
  return latestIntro;
}

Future<(HandleIntroductionResult, IntroductionModel?)>
_handleTerminalResponseReplay({
  required IntroductionPayload payload,
  required IntroductionModel existing,
  required ContactRepository contactRepo,
  required String ownPeerId,
  MessageRepository? messageRepo,
  Bridge? bridge,
}) async {
  if (existing.status == IntroductionOverallStatus.mutualAccepted) {
    await handleMutualAcceptance(
      introduction: existing,
      contactRepo: contactRepo,
      ownPeerId: ownPeerId,
      messageRepo: messageRepo,
      bridge: bridge,
    );
  }

  final result =
      existing.status == IntroductionOverallStatus.passed ||
          existing.status == IntroductionOverallStatus.expired
      ? HandleIntroductionResult.rejected
      : HandleIntroductionResult.alreadyExists;

  emitFlowEvent(
    layer: 'UC',
    event: 'HANDLE_INCOMING_INTRO_TERMINAL_RESPONSE_IGNORED',
    details: {
      'introductionId': payload.introductionId,
      'responderId': payload.responderId ?? '',
      'action': payload.action,
      'status': existing.status.toDbString(),
      'result': result.name,
    },
  );

  return (result, existing);
}

bool _isTerminalOverallStatus(IntroductionOverallStatus status) {
  return status == IntroductionOverallStatus.mutualAccepted ||
      status == IntroductionOverallStatus.passed ||
      status == IntroductionOverallStatus.expired ||
      status == IntroductionOverallStatus.alreadyConnected;
}

Future<void> _replayPendingResponses({
  required String introductionId,
  required IntroductionRepository introRepo,
  required ContactRepository contactRepo,
  required String ownPeerId,
  MessageRepository? messageRepo,
  Bridge? bridge,
}) async {
  final pendingResponses = await introRepo.loadPendingResponses(introductionId);
  if (pendingResponses.isEmpty) {
    return;
  }

  emitFlowEvent(
    layer: 'UC',
    event: 'HANDLE_INCOMING_INTRO_REPLAY_PENDING_RESPONSES_START',
    details: {
      'introductionId': introductionId,
      'count': pendingResponses.length,
    },
  );

  for (final pending in pendingResponses) {
    final pendingTransportSenderPeerId =
        pending.transportSenderPeerId ?? pending.responderId;
    if (pendingTransportSenderPeerId != pending.responderId) {
      emitFlowEvent(
        layer: 'UC',
        event: 'HANDLE_INCOMING_INTRO_PENDING_RESPONSE_SENDER_MISMATCH',
        details: {
          'introductionId': introductionId,
          'responseKey': pending.responseKey,
          'transportSenderPeerId': pendingTransportSenderPeerId,
          'responderId': pending.responderId,
        },
      );
      await introRepo.deletePendingResponse(pending.responseKey);
      continue;
    }

    final existing = await introRepo.getIntroduction(introductionId);
    if (existing == null) {
      throw StateError(
        'Introduction $introductionId disappeared before deferred replay.',
      );
    }

    final (result, _) = await _applyResponseToExistingIntroduction(
      payload: pending.toPayload(),
      existing: existing,
      introRepo: introRepo,
      contactRepo: contactRepo,
      ownPeerId: ownPeerId,
      messageRepo: messageRepo,
      bridge: bridge,
    );

    if (result == HandleIntroductionResult.success ||
        result == HandleIntroductionResult.rejected ||
        result == HandleIntroductionResult.alreadyExists) {
      await introRepo.deletePendingResponse(pending.responseKey);
      continue;
    }

    throw StateError(
      'Deferred intro response replay failed for $introductionId with result $result.',
    );
  }

  emitFlowEvent(
    layer: 'UC',
    event: 'HANDLE_INCOMING_INTRO_REPLAY_PENDING_RESPONSES_SUCCESS',
    details: {
      'introductionId': introductionId,
      'count': pendingResponses.length,
    },
  );
}
