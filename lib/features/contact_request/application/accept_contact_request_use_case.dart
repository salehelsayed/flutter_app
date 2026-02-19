import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';

/// Result of accepting a contact request.
enum AcceptContactRequestResult {
  /// Successfully accepted and added contact.
  success,

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
/// 2. Converts it to a ContactModel
/// 3. Adds to contacts
/// 4. Updates request status to accepted
///
/// Returns the result of the operation.
Future<AcceptContactRequestResult> acceptContactRequest({
  required ContactRequestRepository requestRepo,
  required ContactRepository contactRepo,
  required String peerId,
}) async {
  final peerIdPrefix = peerId.length > 10 ? peerId.substring(0, 10) : peerId;

  emitFlowEvent(
    layer: 'FL',
    event: 'CONTACT_REQUEST_ACCEPT_START',
    details: {'peerId': peerIdPrefix},
  );

  // 1. Load the request
  final request = await requestRepo.getRequest(peerId);
  if (request == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_ACCEPT_NOT_FOUND',
      details: {'peerId': peerIdPrefix},
    );
    return AcceptContactRequestResult.notFound;
  }

  // 2. Verify status is pending
  if (request.status != ContactRequestStatus.pending) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_ACCEPT_NOT_PENDING',
      details: {'peerId': peerIdPrefix, 'status': request.status.name},
    );
    return AcceptContactRequestResult.notPending;
  }

  // 3. Convert to contact and add
  final contact = request.toContactModel();
  try {
    await contactRepo.addContact(contact);
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_ACCEPT_ADD_ERROR',
      details: {'peerId': peerIdPrefix, 'error': e.toString()},
    );
    return AcceptContactRequestResult.addContactError;
  }

  // 4. Update request status to accepted
  try {
    await requestRepo.updateStatus(peerId, ContactRequestStatus.accepted);
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_ACCEPT_STATUS_ERROR',
      details: {'peerId': peerIdPrefix, 'error': e.toString()},
    );
    return AcceptContactRequestResult.updateStatusError;
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'CONTACT_REQUEST_ACCEPT_SUCCESS',
    details: {'peerId': peerIdPrefix, 'username': contact.username},
  );

  return AcceptContactRequestResult.success;
}
