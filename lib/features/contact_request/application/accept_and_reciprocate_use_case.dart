import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/application/accept_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/settings/application/download_profile_picture_use_case.dart';

/// Accepts a contact request and fires a reciprocal contact request so the
/// original sender receives our ML-KEM public key (Part 2 of bidirectional
/// key exchange).
///
/// Delegates the local DB state transition to [acceptContactRequest], then
/// fire-and-forgets [sendContactRequest] on success.
///
/// [onProfileDownloaded] is called when the fire-and-forget profile picture
/// download succeeds. Callers can use this to trigger a UI refresh.
Future<AcceptContactRequestResult> acceptAndReciprocateContactRequest({
  required ContactRequestRepository requestRepo,
  required ContactRepository contactRepo,
  required String peerId,
  required P2PService p2pService,
  required IdentityRepository identityRepo,
  required Bridge bridge,
  DownloadProfilePictureFn downloadProfilePictureFn = downloadProfilePicture,
  void Function(ContactModel)? onProfileDownloaded,
}) async {
  // 1. Delegate local accept to existing use case
  final result = await acceptContactRequest(
    requestRepo: requestRepo,
    contactRepo: contactRepo,
    peerId: peerId,
  );

  // 2. On success, fire-and-forget reciprocal request
  if (result == AcceptContactRequestResult.success) {
    // Speculatively download the contact's profile picture (fire and forget)
    () async {
      try {
        final updated = await downloadProfilePictureFn(
          bridge: bridge,
          contactRepo: contactRepo,
          ownerPeerId: peerId,
          avatarVersion: 'initial',
        );
        if (updated != null) onProfileDownloaded?.call(updated);
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'INITIAL_PROFILE_DOWNLOAD_ERROR',
          details: {'peerId': peerId, 'error': e.toString()},
        );
      }
    }();

    // Load the now-accepted contact to get their public key for v2 encryption
    final contact = await contactRepo.getContact(peerId);
    final recipientPublicKey = contact?.publicKey;

    sendContactRequest(
      p2pService: p2pService,
      identityRepo: identityRepo,
      bridge: bridge,
      targetPeerId: peerId,
      recipientPublicKey: recipientPublicKey,
    ).then((sendResult) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RECIPROCAL_CONTACT_REQUEST_RESULT',
        details: {
          'peerId': peerId.length > 10 ? peerId.substring(0, 10) : peerId,
          'result': sendResult.name,
        },
      );
    });
  }

  return result;
}
