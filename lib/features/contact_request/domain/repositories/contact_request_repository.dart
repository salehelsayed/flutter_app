import '../models/contact_request_model.dart';

enum ContactRequestDecisionResult {
  pending,
  accepted,
  alreadyAccepted,
  declined,
  notFound,
  notPending,
  blocked,
  addContactError,
  updateStatusError,
}

/// Repository interface for managing contact requests.
abstract class ContactRequestRepository {
  /// Adds a new contact request to the database.
  ///
  /// If a request with the same peerId already exists, it will be updated.
  Future<void> addRequest(ContactRequestModel request);

  /// Retrieves a contact request by peer ID.
  ///
  /// Returns null if no request with the given ID exists.
  Future<ContactRequestModel?> getRequest(String peerId);

  /// Retrieves all pending contact requests.
  ///
  /// Returns an empty list if no pending requests exist.
  Future<List<ContactRequestModel>> getPendingRequests();

  /// Updates the status of a contact request.
  Future<void> updateStatus(String peerId, ContactRequestStatus status);

  /// Decides the exact stored request and creates its contact atomically.
  /// With [existingContactOnly], settles legacy contact/pending half-states and
  /// returns [ContactRequestDecisionResult.pending] when consent is still needed.
  Future<ContactRequestDecisionResult> decideRequest({
    required ContactRequestModel expectedRequest,
    required bool accept,
    bool existingContactOnly = false,
    Future<void> Function()? beforeMarkAccepted,
  });

  /// Deletes a contact request by peer ID.
  Future<void> deleteRequest(String peerId);

  /// Checks if a contact request with the given peer ID exists.
  Future<bool> requestExists(String peerId);
}
