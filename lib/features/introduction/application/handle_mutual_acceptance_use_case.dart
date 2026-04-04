import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/introduction/application/introduction_copy.dart';
import 'package:flutter_app/features/introduction/application/insert_intro_system_message.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/settings/application/download_profile_picture_use_case.dart';

/// Creates a contact for the other party when an introduction reaches
/// mutual acceptance.
///
/// Returns the new [ContactModel] if created, or null if the contact
/// already exists (idempotent) or the introduction is not mutually accepted.
///
/// When [messageRepo] is provided, also inserts a "Connected through
/// [introducer]" system message into the new conversation.
Future<ContactModel?> handleMutualAcceptance({
  required IntroductionModel introduction,
  required ContactRepository contactRepo,
  required String ownPeerId,
  MessageRepository? messageRepo,
  Bridge? bridge,
  DownloadProfilePictureFn? downloadProfilePictureFn,
}) async {
  if (introduction.status != IntroductionOverallStatus.mutualAccepted) {
    return null;
  }

  final isRecipient = introduction.recipientId == ownPeerId;
  final otherPeerId = isRecipient
      ? introduction.introducedId
      : introduction.recipientId;
  final otherUsername = isRecipient
      ? introduction.introducedUsername
      : introduction.recipientUsername;

  if (await contactRepo.contactExists(otherPeerId)) {
    emitFlowEvent(
      layer: 'UC',
      event: 'MUTUAL_ACCEPTANCE_CONTACT_EXISTS',
      details: {'otherPeerId': otherPeerId},
    );
    return null;
  }

  // Use direction-aware key selection:
  // - Recipient (User-B) needs introduced party's keys (User-C)
  // - Introduced party (User-C) needs recipient's keys (User-B)
  final otherPublicKey = isRecipient
      ? introduction.introducedPublicKey
      : introduction.recipientPublicKey;
  final otherMlKemPublicKey = isRecipient
      ? introduction.introducedMlKemPublicKey
      : introduction.recipientMlKemPublicKey;

  final newContact = ContactModel(
    peerId: otherPeerId,
    publicKey: otherPublicKey ?? '',
    rendezvous: '',
    username: otherUsername ?? 'Unknown',
    signature: '',
    scannedAt: DateTime.now().toUtc().toIso8601String(),
    mlKemPublicKey: otherMlKemPublicKey,
    introducedBy: introduction.introducerUsername,
    introducedByPeerId: introduction.introducerId,
  );
  await contactRepo.addContact(newContact);

  // Download avatar for the new contact (fire and forget).
  // If the relay doesn't have it yet, retry after a short delay.
  if (bridge != null) {
    final dlFn = downloadProfilePictureFn ?? downloadProfilePicture;
    () async {
      try {
        var result = await dlFn(
          bridge: bridge,
          contactRepo: contactRepo,
          ownerPeerId: otherPeerId,
          avatarVersion: 'initial',
        );
        if (result != null) return;

        // Retry once after delay — relay may not have the profile yet
        await Future<void>.delayed(const Duration(seconds: 5));
        await dlFn(
          bridge: bridge,
          contactRepo: contactRepo,
          ownerPeerId: otherPeerId,
          avatarVersion: 'initial',
        );
      } catch (e) {
        emitFlowEvent(
          layer: 'UC',
          event: 'INTRO_AVATAR_DOWNLOAD_ERROR',
          details: {'peerId': otherPeerId, 'error': e.toString()},
        );
      }
    }();
  }

  // Insert "Connected through [introducer]" system message
  if (messageRepo != null) {
    await insertIntroSystemMessage(
      messageRepo: messageRepo,
      contactPeerId: otherPeerId,
      text: formatMutualAcceptanceSystemMessage(
        otherUsername: otherUsername ?? '',
        introducerName: introduction.introducerUsername ?? '',
      ),
      ownPeerId: ownPeerId,
    );
  }

  emitFlowEvent(
    layer: 'UC',
    event: 'MUTUAL_ACCEPTANCE_CONTACT_CREATED',
    details: {
      'otherPeerId': otherPeerId,
      'introducedBy': introduction.introducerUsername ?? '',
    },
  );

  return newContact;
}
