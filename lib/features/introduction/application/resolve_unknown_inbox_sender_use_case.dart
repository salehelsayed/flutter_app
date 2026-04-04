import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/introduction/application/handle_mutual_acceptance_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';

enum UnknownInboxSenderResolution { rejected, retryable, contactRecovered }

/// Decides how to treat a recovered inbox chat from an unknown sender.
///
/// For normal strangers, the message should still be rejected. For peers that
/// are in the middle of an accepted introduction handshake, the message should
/// stay retryable until the contact exists locally. When the introduction is
/// already mutually accepted, this also opportunistically recreates the
/// missing contact so the replay can succeed on the next attempt.
Future<UnknownInboxSenderResolution> resolveUnknownInboxSender({
  required IntroductionRepository introRepo,
  required ContactRepository contactRepo,
  required String ownPeerId,
  required String senderPeerId,
}) async {
  final intros = [
    ...await introRepo.getIntroductionsByRecipient(ownPeerId),
    ...await introRepo.getIntroductionsByIntroduced(ownPeerId),
  ];

  var sawRetryableIntroduction = false;

  for (final intro in intros) {
    final otherPeerId = _otherPeerIdFor(intro, ownPeerId);
    if (otherPeerId != senderPeerId) {
      continue;
    }

    switch (intro.status) {
      case IntroductionOverallStatus.mutualAccepted:
        await handleMutualAcceptance(
          introduction: intro,
          contactRepo: contactRepo,
          ownPeerId: ownPeerId,
        );
        if (await contactRepo.contactExists(senderPeerId)) {
          return UnknownInboxSenderResolution.contactRecovered;
        }
        sawRetryableIntroduction = true;
        break;
      case IntroductionOverallStatus.alreadyConnected:
        if (await contactRepo.contactExists(senderPeerId)) {
          return UnknownInboxSenderResolution.contactRecovered;
        }
        sawRetryableIntroduction = true;
        break;
      case IntroductionOverallStatus.pending:
        if (_ownSideAccepted(intro, ownPeerId)) {
          sawRetryableIntroduction = true;
        }
        break;
      case IntroductionOverallStatus.passed:
      case IntroductionOverallStatus.expired:
        break;
    }
  }

  return sawRetryableIntroduction
      ? UnknownInboxSenderResolution.retryable
      : UnknownInboxSenderResolution.rejected;
}

String _otherPeerIdFor(IntroductionModel intro, String ownPeerId) {
  if (intro.recipientId == ownPeerId) {
    return intro.introducedId;
  }
  return intro.recipientId;
}

bool _ownSideAccepted(IntroductionModel intro, String ownPeerId) {
  if (intro.recipientId == ownPeerId) {
    return intro.recipientStatus == IntroductionStatus.accepted;
  }
  return intro.introducedStatus == IntroductionStatus.accepted;
}
