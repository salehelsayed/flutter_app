import 'dart:async';

import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';

/// In-memory [ContactRequestRepository] for integration tests.
class InMemoryContactRequestRepository implements ContactRequestRepository {
  final Map<String, ContactRequestModel> _requests = {};
  ContactRepository? contactRepository;
  Future<void>? _decisionTail;

  InMemoryContactRequestRepository({this.contactRepository});

  @override
  Future<ContactRequestDecisionResult> decideRequest({
    required ContactRequestModel expectedRequest,
    required bool accept,
    bool existingContactOnly = false,
    Future<void> Function()? beforeMarkAccepted,
  }) async {
    final previous = _decisionTail;
    final done = Completer<void>();
    _decisionTail = done.future;
    if (previous != null) await previous;
    var failure = ContactRequestDecisionResult.updateStatusError;
    var createdContact = false;
    final contacts = contactRepository;
    try {
      final current = await getRequest(expectedRequest.peerId);
      if (current == null) return ContactRequestDecisionResult.notFound;
      if (current.publicKey != expectedRequest.publicKey ||
          current.signature != expectedRequest.signature ||
          current.receivedAt != expectedRequest.receivedAt) {
        return ContactRequestDecisionResult.notPending;
      }
      final contact = await contacts?.getContact(current.peerId);
      if (current.status == ContactRequestStatus.accepted) {
        if (contact?.isBlocked == true) {
          return ContactRequestDecisionResult.blocked;
        }
        return contact != null && accept
            ? ContactRequestDecisionResult.alreadyAccepted
            : ContactRequestDecisionResult.notPending;
      }
      if (current.status != ContactRequestStatus.pending) {
        return !accept && current.status == ContactRequestStatus.declined
            ? ContactRequestDecisionResult.declined
            : ContactRequestDecisionResult.notPending;
      }
      if (contact != null) {
        if (contact.isBlocked && existingContactOnly) {
          return ContactRequestDecisionResult.blocked;
        }
        if (accept && !contact.isBlocked && !existingContactOnly) {
          await beforeMarkAccepted?.call();
        }
        await updateStatus(current.peerId, ContactRequestStatus.accepted);
        if (contact.isBlocked) return ContactRequestDecisionResult.blocked;
        return accept && !existingContactOnly
            ? ContactRequestDecisionResult.accepted
            : ContactRequestDecisionResult.alreadyAccepted;
      }
      if (!accept) {
        await updateStatus(current.peerId, ContactRequestStatus.declined);
        return ContactRequestDecisionResult.declined;
      }
      if (existingContactOnly) return ContactRequestDecisionResult.pending;
      if (contacts == null) {
        throw StateError('Bind the decision fake to its contact repository');
      }
      failure = ContactRequestDecisionResult.addContactError;
      await contacts.addContact(current.toContactModel());
      createdContact = true;
      failure = ContactRequestDecisionResult.updateStatusError;
      await beforeMarkAccepted?.call();
      await updateStatus(current.peerId, ContactRequestStatus.accepted);
      return ContactRequestDecisionResult.accepted;
    } catch (_) {
      if (createdContact) await contacts!.deleteContact(expectedRequest.peerId);
      return failure;
    } finally {
      done.complete();
    }
  }

  @override
  Future<void> addRequest(ContactRequestModel request) async {
    _requests[request.peerId] = request;
  }

  @override
  Future<ContactRequestModel?> getRequest(String peerId) async {
    return _requests[peerId];
  }

  @override
  Future<List<ContactRequestModel>> getPendingRequests() async {
    return _requests.values
        .where((r) => r.status == ContactRequestStatus.pending)
        .toList()
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
  }

  @override
  Future<void> updateStatus(String peerId, ContactRequestStatus status) async {
    final existing = _requests[peerId];
    if (existing != null) {
      _requests[peerId] = existing.copyWith(status: status);
    }
  }

  @override
  Future<void> deleteRequest(String peerId) async {
    _requests.remove(peerId);
  }

  @override
  Future<bool> requestExists(String peerId) async {
    return _requests.containsKey(peerId);
  }

  int get count => _requests.length;
}
