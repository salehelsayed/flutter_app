import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/introduction/application/handle_mutual_acceptance_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';

class VerifiedContactRequestEnvelope {
  final String peerId;
  final String publicKey;
  final String rendezvous;
  final String username;
  final String signature;
  final String? mlKemPublicKey;

  const VerifiedContactRequestEnvelope({
    required this.peerId,
    required this.publicKey,
    required this.rendezvous,
    required this.username,
    required this.signature,
    this.mlKemPublicKey,
  });
}

enum IntroContactRequestRecoveryAction {
  noMatch,
  continueAsContactRequest,
  recovered,
}

class IntroContactRequestRecoveryResult {
  final IntroContactRequestRecoveryAction action;
  final IntroductionModel? introduction;
  final ContactModel? contact;
  final bool contactKeyUpdated;

  const IntroContactRequestRecoveryResult._({
    required this.action,
    this.introduction,
    this.contact,
    this.contactKeyUpdated = false,
  });

  const IntroContactRequestRecoveryResult.noMatch()
    : this._(action: IntroContactRequestRecoveryAction.noMatch);

  const IntroContactRequestRecoveryResult.continueAsContactRequest()
    : this._(
        action: IntroContactRequestRecoveryAction.continueAsContactRequest,
      );

  const IntroContactRequestRecoveryResult.recovered({
    required IntroductionModel introduction,
    ContactModel? contact,
    bool contactKeyUpdated = false,
  }) : this._(
         action: IntroContactRequestRecoveryAction.recovered,
         introduction: introduction,
         contact: contact,
         contactKeyUpdated: contactKeyUpdated,
       );
}

typedef AttemptSilentIntroContactRequestRecovery =
    Future<IntroContactRequestRecoveryResult> Function(
      VerifiedContactRequestEnvelope request,
    );

Future<IntroContactRequestRecoveryResult> recoverIntroContactRequest({
  required IntroductionRepository introRepo,
  required ContactRequestRepository requestRepo,
  required ContactRepository contactRepo,
  required String ownPeerId,
  required VerifiedContactRequestEnvelope request,
  MessageRepository? messageRepo,
  Bridge? bridge,
}) async {
  final pendingIntros = await introRepo.getPendingIntroductionsForUser(
    ownPeerId,
  );
  final pairIntros = pendingIntros
      .where(
        (intro) =>
            intro.status == IntroductionOverallStatus.pending &&
            _otherPeerIdFor(intro, ownPeerId) == request.peerId,
      )
      .toList(growable: false);

  if (pairIntros.isEmpty) {
    return const IntroContactRequestRecoveryResult.noMatch();
  }

  final qualifyingIntros = pairIntros
      .where(
        (intro) =>
            _localSideAccepted(intro, ownPeerId) &&
            _remoteSideStatusFor(intro, ownPeerId) ==
                IntroductionStatus.pending,
      )
      .toList(growable: false);

  if (qualifyingIntros.isEmpty) {
    return const IntroContactRequestRecoveryResult.noMatch();
  }

  final distinctIntroducerIds = pairIntros
      .map((intro) => intro.introducerId)
      .toSet();
  if (qualifyingIntros.length != 1 || distinctIntroducerIds.length > 1) {
    await _deletePendingRequestIfPresent(requestRepo, request.peerId);
    return const IntroContactRequestRecoveryResult.continueAsContactRequest();
  }

  final qualifyingIntro = qualifyingIntros.single;
  final introNeedsMerge = _introNeedsRemoteIdentityMerge(
    introduction: qualifyingIntro,
    ownPeerId: ownPeerId,
    request: request,
  );
  final mergedIntro = _mergeRemoteIdentityIntoIntroduction(
    introduction: qualifyingIntro,
    ownPeerId: ownPeerId,
    request: request,
  );
  if (introNeedsMerge) {
    await introRepo.saveIntroduction(mergedIntro);
  }

  await _acceptRemoteSide(
    introRepo: introRepo,
    introductionId: qualifyingIntro.id,
    ownPeerId: ownPeerId,
    introduction: mergedIntro,
  );

  final updatedIntro = await introRepo.getIntroduction(qualifyingIntro.id);
  if (updatedIntro == null) {
    return const IntroContactRequestRecoveryResult.noMatch();
  }

  final newOverall = IntroductionModel.deriveStatus(
    recipientStatus: updatedIntro.recipientStatus,
    introducedStatus: updatedIntro.introducedStatus,
    createdAt: updatedIntro.createdAt,
  );
  await introRepo.updateOverallStatus(updatedIntro.id, newOverall);

  final convergedIntro = await introRepo.getIntroduction(updatedIntro.id);
  if (convergedIntro == null ||
      convergedIntro.status != IntroductionOverallStatus.mutualAccepted) {
    return const IntroContactRequestRecoveryResult.noMatch();
  }

  final existingContact = await contactRepo.getContact(request.peerId);
  final bool contactKeyWasMissing =
      existingContact?.mlKemPublicKey == null && request.mlKemPublicKey != null;

  ContactModel? recoveredContact;
  if (existingContact == null) {
    await handleMutualAcceptance(
      introduction: convergedIntro,
      contactRepo: contactRepo,
      ownPeerId: ownPeerId,
      messageRepo: messageRepo,
      bridge: bridge,
    );
    recoveredContact = await contactRepo.getContact(request.peerId);
  } else {
    final contactNeedsMerge = _contactNeedsRecoveryMerge(
      existingContact: existingContact,
      introduction: convergedIntro,
      request: request,
      contactKeyWasMissing: contactKeyWasMissing,
    );
    final updatedContact = _mergeRecoveredContact(
      existingContact: existingContact,
      introduction: convergedIntro,
      request: request,
      contactKeyWasMissing: contactKeyWasMissing,
    );
    if (contactNeedsMerge) {
      await contactRepo.addContact(updatedContact);
    }
    recoveredContact = await contactRepo.getContact(request.peerId);
  }

  await _deletePendingRequestIfPresent(requestRepo, request.peerId);

  return IntroContactRequestRecoveryResult.recovered(
    introduction: convergedIntro,
    contact: recoveredContact,
    contactKeyUpdated: contactKeyWasMissing,
  );
}

String _otherPeerIdFor(IntroductionModel intro, String ownPeerId) {
  return intro.recipientId == ownPeerId
      ? intro.introducedId
      : intro.recipientId;
}

bool _localSideAccepted(IntroductionModel intro, String ownPeerId) {
  return intro.recipientId == ownPeerId
      ? intro.recipientStatus == IntroductionStatus.accepted
      : intro.introducedStatus == IntroductionStatus.accepted;
}

IntroductionStatus _remoteSideStatusFor(
  IntroductionModel intro,
  String ownPeerId,
) {
  return intro.recipientId == ownPeerId
      ? intro.introducedStatus
      : intro.recipientStatus;
}

Future<void> _acceptRemoteSide({
  required IntroductionRepository introRepo,
  required String introductionId,
  required String ownPeerId,
  required IntroductionModel introduction,
}) async {
  if (introduction.recipientId == ownPeerId) {
    await introRepo.updateIntroducedStatus(
      introductionId,
      IntroductionStatus.accepted,
    );
    return;
  }

  await introRepo.updateRecipientStatus(
    introductionId,
    IntroductionStatus.accepted,
  );
}

IntroductionModel _mergeRemoteIdentityIntoIntroduction({
  required IntroductionModel introduction,
  required String ownPeerId,
  required VerifiedContactRequestEnvelope request,
}) {
  final remoteIsIntroduced = introduction.recipientId == ownPeerId;
  if (remoteIsIntroduced) {
    return introduction.copyWith(
      introducedPublicKey:
          introduction.introducedPublicKey ?? request.publicKey,
      introducedMlKemPublicKey:
          introduction.introducedMlKemPublicKey ?? request.mlKemPublicKey,
      introducedUsername: _pickPreferredValue(
        introduction.introducedUsername,
        request.username,
      ),
    );
  }

  return introduction.copyWith(
    recipientPublicKey: introduction.recipientPublicKey ?? request.publicKey,
    recipientMlKemPublicKey:
        introduction.recipientMlKemPublicKey ?? request.mlKemPublicKey,
    recipientUsername: _pickPreferredValue(
      introduction.recipientUsername,
      request.username,
    ),
  );
}

bool _introNeedsRemoteIdentityMerge({
  required IntroductionModel introduction,
  required String ownPeerId,
  required VerifiedContactRequestEnvelope request,
}) {
  final remoteIsIntroduced = introduction.recipientId == ownPeerId;
  if (remoteIsIntroduced) {
    return introduction.introducedPublicKey == null ||
        introduction.introducedMlKemPublicKey == null &&
            request.mlKemPublicKey != null ||
        _shouldReplaceTextValue(
          introduction.introducedUsername,
          request.username,
        );
  }

  return introduction.recipientPublicKey == null ||
      introduction.recipientMlKemPublicKey == null &&
          request.mlKemPublicKey != null ||
      _shouldReplaceTextValue(introduction.recipientUsername, request.username);
}

bool _contactNeedsRecoveryMerge({
  required ContactModel existingContact,
  required IntroductionModel introduction,
  required VerifiedContactRequestEnvelope request,
  required bool contactKeyWasMissing,
}) {
  return existingContact.publicKey.isEmpty ||
      existingContact.rendezvous.isEmpty ||
      existingContact.signature.isEmpty ||
      contactKeyWasMissing ||
      _shouldReplaceTextValue(existingContact.username, request.username) ||
      _shouldReplaceTextValue(
        existingContact.introducedBy,
        introduction.introducerUsername,
      ) ||
      _shouldReplaceTextValue(
        existingContact.introducedByPeerId,
        introduction.introducerId,
      );
}

ContactModel _mergeRecoveredContact({
  required ContactModel existingContact,
  required IntroductionModel introduction,
  required VerifiedContactRequestEnvelope request,
  required bool contactKeyWasMissing,
}) {
  return existingContact.copyWith(
    publicKey: existingContact.publicKey.isEmpty
        ? request.publicKey
        : existingContact.publicKey,
    rendezvous: existingContact.rendezvous.isEmpty
        ? request.rendezvous
        : existingContact.rendezvous,
    username: _pickPreferredValue(existingContact.username, request.username),
    signature: existingContact.signature.isEmpty
        ? request.signature
        : existingContact.signature,
    mlKemPublicKey: contactKeyWasMissing
        ? request.mlKemPublicKey
        : existingContact.mlKemPublicKey,
    introducedBy: _pickPreferredValue(
      existingContact.introducedBy,
      introduction.introducerUsername,
    ),
    introducedByPeerId: _pickPreferredValue(
      existingContact.introducedByPeerId,
      introduction.introducerId,
    ),
  );
}

String? _pickPreferredValue(String? currentValue, String? fallbackValue) {
  final current = currentValue?.trim();
  if (current != null && current.isNotEmpty && current != 'Unknown') {
    return currentValue;
  }

  final fallback = fallbackValue?.trim();
  if (fallback == null || fallback.isEmpty) {
    return currentValue;
  }
  return fallbackValue;
}

bool _shouldReplaceTextValue(String? currentValue, String? fallbackValue) {
  final current = currentValue?.trim();
  final fallback = fallbackValue?.trim();
  return (current == null || current.isEmpty || current == 'Unknown') &&
      fallback != null &&
      fallback.isNotEmpty;
}

Future<void> _deletePendingRequestIfPresent(
  ContactRequestRepository requestRepo,
  String peerId,
) async {
  final existingRequest = await requestRepo.getRequest(peerId);
  if (existingRequest != null &&
      existingRequest.status == ContactRequestStatus.pending) {
    await requestRepo.deleteRequest(peerId);
  }
}
