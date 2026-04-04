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
  if (request != null && request.status == ContactRequestStatus.pending) {
    return ContactRequestNotificationTarget.pendingRequest(request);
  }

  final contact = await contactRepository.getContact(peerId);
  if (contact != null) {
    return ContactRequestNotificationTarget.conversation(contact);
  }

  return const ContactRequestNotificationTarget.missing();
}
