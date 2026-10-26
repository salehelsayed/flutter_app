import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';

/// Result of accepting a contact request.
enum AcceptContactRequestResult {
  /// Successfully accepted and added contact.
  success,

  /// This exact request was already accepted and still has a current contact.
  alreadyAccepted,

  /// Request not found.
  notFound,

  /// Request is not in pending status.
  notPending,

  /// Failed to add contact.
  addContactError,

  /// Failed to update request status.
  updateStatusError,
}

/// Accepts a contact request and adds the sender as a contact.
///
/// This function:
/// 1. Loads the request
/// 2. Rechecks the exact request and current contact in one transaction
/// 3. Commits a new contact and accepted status together, preserving existing contacts
///
/// Returns the result of the operation.
Future<AcceptContactRequestResult> acceptContactRequest({
  required ContactRequestRepository requestRepo,
  required ContactRepository contactRepo,
  required String peerId,
  ContactRequestModel? expectedRequest,
  Future<void> Function()? beforeMarkAccepted,
}) async {
  final peerIdPrefix = peerId.length > 10 ? peerId.substring(0, 10) : peerId;

  emitFlowEvent(
    layer: 'FL',
    event: 'CONTACT_REQUEST_ACCEPT_START',
    details: {'peerId': peerIdPrefix},
  );

  final request = expectedRequest ?? await requestRepo.getRequest(peerId);
  if (request == null || request.peerId != peerId) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_ACCEPT_NOT_FOUND',
      details: {'peerId': peerIdPrefix},
    );
    return AcceptContactRequestResult.notFound;
  }

  try {
    final decision = await requestRepo.decideRequest(
      expectedRequest: request,
      accept: true,
      beforeMarkAccepted: beforeMarkAccepted,
    );
    var result = switch (decision) {
      ContactRequestDecisionResult.accepted =>
        AcceptContactRequestResult.success,
      ContactRequestDecisionResult.alreadyAccepted =>
        AcceptContactRequestResult.alreadyAccepted,
      ContactRequestDecisionResult.notFound =>
        AcceptContactRequestResult.notFound,
      ContactRequestDecisionResult.addContactError =>
        AcceptContactRequestResult.addContactError,
      ContactRequestDecisionResult.updateStatusError =>
        AcceptContactRequestResult.updateStatusError,
      _ => AcceptContactRequestResult.notPending,
    };
    if (result == AcceptContactRequestResult.success ||
        result == AcceptContactRequestResult.alreadyAccepted) {
      final current = await contactRepo.getContact(peerId);
      if (current == null || current.isBlocked) {
        result = AcceptContactRequestResult.notPending;
      }
    }
    emitFlowEvent(
      layer: 'FL',
      event: switch (result) {
        AcceptContactRequestResult.success ||
        AcceptContactRequestResult.alreadyAccepted =>
          'CONTACT_REQUEST_ACCEPT_SUCCESS',
        AcceptContactRequestResult.notFound =>
          'CONTACT_REQUEST_ACCEPT_NOT_FOUND',
        AcceptContactRequestResult.notPending =>
          'CONTACT_REQUEST_ACCEPT_NOT_PENDING',
        AcceptContactRequestResult.addContactError =>
          'CONTACT_REQUEST_ACCEPT_ADD_ERROR',
        AcceptContactRequestResult.updateStatusError =>
          'CONTACT_REQUEST_ACCEPT_STATUS_ERROR',
      },
      details: {'peerId': peerIdPrefix, 'result': result.name},
    );
    return result;
  } catch (error) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_ACCEPT_STATUS_ERROR',
      details: {'peerId': peerIdPrefix, 'error': error.toString()},
    );
    return AcceptContactRequestResult.updateStatusError;
  }
}
