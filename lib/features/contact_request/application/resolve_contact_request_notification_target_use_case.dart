import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';

enum ContactRequestNotificationTargetState {
  pendingRequest,
  conversation,
  missing,
}

class ContactRequestNotificationTarget {
  final ContactRequestNotificationTargetState state;
  final ContactRequestModel? request;
  final ContactModel? contact;

  const ContactRequestNotificationTarget._({
    required this.state,
    this.request,
    this.contact,
  });

  const ContactRequestNotificationTarget.pendingRequest(
    ContactRequestModel request,
  ) : this._(
        state: ContactRequestNotificationTargetState.pendingRequest,
        request: request,
      );

  const ContactRequestNotificationTarget.conversation(ContactModel contact)
    : this._(
        state: ContactRequestNotificationTargetState.conversation,
        contact: contact,
      );

  const ContactRequestNotificationTarget.missing()
    : this._(state: ContactRequestNotificationTargetState.missing);
}

Future<ContactRequestNotificationTarget>
resolveContactRequestNotificationTarget({
  required String peerId,
  required ContactRequestRepository requestRepository,
  required ContactRepository contactRepository,
}) async {
  final request = await requestRepository.getRequest(peerId);
  final contact = await contactRepository.getContact(peerId);
  if (contact?.isBlocked == true) {
    return const ContactRequestNotificationTarget.missing();
  }
  if (contact != null) {
    return ContactRequestNotificationTarget.conversation(contact);
  }
  if (request != null && request.status == ContactRequestStatus.pending) {
    final decision = await requestRepository.decideRequest(
      expectedRequest: request,
      accept: true,
      existingContactOnly: true,
    );
    if (decision == ContactRequestDecisionResult.pending) {
      return ContactRequestNotificationTarget.pendingRequest(request);
    }
    if (decision == ContactRequestDecisionResult.alreadyAccepted) {
      final currentContact = await contactRepository.getContact(peerId);
      if (currentContact != null && !currentContact.isBlocked) {
        return ContactRequestNotificationTarget.conversation(currentContact);
      }
    }
  }
  return const ContactRequestNotificationTarget.missing();
}
