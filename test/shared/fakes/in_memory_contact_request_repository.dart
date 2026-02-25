import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';

/// In-memory [ContactRequestRepository] for integration tests.
class InMemoryContactRequestRepository implements ContactRequestRepository {
  final Map<String, ContactRequestModel> _requests = {};

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
  Future<void> updateStatus(
      String peerId, ContactRequestStatus status) async {
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
