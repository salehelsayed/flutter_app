import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/application/accept_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

/// Accepts a contact request and fires a reciprocal contact request so the
/// original sender receives our ML-KEM public key (Part 2 of bidirectional
/// key exchange).
///
/// Delegates the local DB state transition to [acceptContactRequest], then
/// fire-and-forgets [sendContactRequest] on success.
Future<AcceptContactRequestResult> acceptAndReciprocateContactRequest({
  required ContactRequestRepository requestRepo,
  required ContactRepository contactRepo,
  required String peerId,
  required P2PService p2pService,
  required IdentityRepository identityRepo,
  required Bridge bridge,
}) async {
  // 1. Delegate local accept to existing use case
  final result = await acceptContactRequest(
    requestRepo: requestRepo,
    contactRepo: contactRepo,
    peerId: peerId,
  );

  // 2. On success, fire-and-forget reciprocal request
  if (result == AcceptContactRequestResult.success) {
    sendContactRequest(
      p2pService: p2pService,
      identityRepo: identityRepo,
      bridge: bridge,
      targetPeerId: peerId,
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
