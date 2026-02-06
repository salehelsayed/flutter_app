import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';

/// Result of declining a contact request.
enum DeclineContactRequestResult {
  /// Successfully declined the request.
  success,

  /// Request not found.
  notFound,

  /// Failed to update request status.
  updateError,
}

/// Declines a contact request.
///
/// This function updates the request status to declined.
///
/// Returns the result of the operation.
Future<DeclineContactRequestResult> declineContactRequest({
  required ContactRequestRepository requestRepo,
  required String peerId,
}) async {
  final peerIdPrefix = peerId.length > 10 ? peerId.substring(0, 10) : peerId;

  emitFlowEvent(
    layer: 'FL',
    event: 'CONTACT_REQUEST_DECLINE_START',
    details: {'peerId': peerIdPrefix},
  );

  // 1. Check if request exists
  final request = await requestRepo.getRequest(peerId);
  if (request == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_DECLINE_NOT_FOUND',
      details: {'peerId': peerIdPrefix},
    );
    return DeclineContactRequestResult.notFound;
  }

  // 2. Update status to declined
  try {
    await requestRepo.updateStatus(peerId, ContactRequestStatus.declined);

    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_DECLINE_SUCCESS',
      details: {'peerId': peerIdPrefix},
    );

    return DeclineContactRequestResult.success;
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_DECLINE_ERROR',
      details: {'peerId': peerIdPrefix, 'error': e.toString()},
    );
    return DeclineContactRequestResult.updateError;
  }
}
