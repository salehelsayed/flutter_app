import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';

/// In-memory [ContactRequestRepository] for tests.
///
/// Stores requests in a map, tracks call counts and last arguments.
class FakeContactRequestRepository implements ContactRequestRepository {
  final Map<String, ContactRequestModel> _requests = {};

  // Call tracking
  int addRequestCallCount = 0;
  int getRequestCallCount = 0;
  int getPendingRequestsCallCount = 0;
  int updateStatusCallCount = 0;
  int deleteRequestCallCount = 0;
  int requestExistsCallCount = 0;

  // Last arguments
  ContactRequestModel? lastAddedRequest;
  String? lastUpdateStatusPeerId;
  ContactRequestStatus? lastUpdateStatus;

  // Configurable errors
  bool throwOnAddRequest = false;
  bool throwOnUpdateStatus = false;

  /// Seed requests for testing.
  void seed(List<ContactRequestModel> requests) {
    _requests.clear();
    for (final r in requests) {
      _requests[r.peerId] = r;
    }
  }

  @override
  Future<void> addRequest(ContactRequestModel request) async {
    addRequestCallCount++;
    lastAddedRequest = request;
    if (throwOnAddRequest) throw Exception('FakeContactRequestRepository: addRequest error');
    _requests[request.peerId] = request;
  }

  @override
  Future<ContactRequestModel?> getRequest(String peerId) async {
    getRequestCallCount++;
    return _requests[peerId];
  }

  @override
  Future<List<ContactRequestModel>> getPendingRequests() async {
    getPendingRequestsCallCount++;
    return _requests.values
        .where((r) => r.status == ContactRequestStatus.pending)
        .toList()
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
  }

  @override
  Future<void> updateStatus(String peerId, ContactRequestStatus status) async {
    updateStatusCallCount++;
    lastUpdateStatusPeerId = peerId;
    lastUpdateStatus = status;
    if (throwOnUpdateStatus) throw Exception('FakeContactRequestRepository: updateStatus error');
    final existing = _requests[peerId];
    if (existing != null) {
      _requests[peerId] = existing.copyWith(status: status);
    }
  }

  @override
  Future<void> deleteRequest(String peerId) async {
    deleteRequestCallCount++;
    _requests.remove(peerId);
  }

  @override
  Future<bool> requestExists(String peerId) async {
    requestExistsCallCount++;
    return _requests.containsKey(peerId);
  }
}
