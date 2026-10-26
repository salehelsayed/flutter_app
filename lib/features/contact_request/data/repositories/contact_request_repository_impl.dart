import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import '../../domain/models/contact_request_model.dart';
import '../../domain/repositories/contact_request_repository.dart';

/// Implementation of ContactRequestRepository using database helper functions.
class ContactRequestRepositoryImpl implements ContactRequestRepository {
  final Future<List<Map<String, Object?>>> Function() dbLoadPendingRequests;
  final Future<Map<String, Object?>?> Function(String peerId) dbLoadRequest;
  final Future<void> Function(Map<String, Object?> row) dbUpsertRequest;
  final Future<void> Function(String peerId, String status)
  dbUpdateRequestStatus;
  final Future<ContactRequestDecisionResult> Function(
    Map<String, Object?> expected,
    bool accept,
    bool existingContactOnly,
    Future<void> Function()? beforeMarkAccepted,
  )
  dbDecideRequest;
  final Future<void> Function(String peerId) dbDeleteRequest;
  final Future<bool> Function(String peerId) dbRequestExists;
  final Future<void> Function(String peerId)? onContactAccepted;

  ContactRequestRepositoryImpl({
    required this.dbLoadPendingRequests,
    required this.dbLoadRequest,
    required this.dbUpsertRequest,
    required this.dbUpdateRequestStatus,
    required this.dbDecideRequest,
    required this.dbDeleteRequest,
    required this.dbRequestExists,
    this.onContactAccepted,
  });

  @override
  Future<void> addRequest(ContactRequestModel request) async {
    final peerIdPrefix = request.peerId.length > 10
        ? request.peerId.substring(0, 10)
        : request.peerId;

    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_REPO_ADD_START',
      details: {'peerId': peerIdPrefix},
    );

    try {
      await dbUpsertRequest(request.toMap());

      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_REPO_ADD_SUCCESS',
        details: {'peerId': peerIdPrefix},
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_REPO_ADD_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }

  @override
  Future<ContactRequestModel?> getRequest(String peerId) async {
    final row = await dbLoadRequest(peerId);
    if (row == null) return null;
    return ContactRequestModel.fromMap(row);
  }

  @override
  Future<List<ContactRequestModel>> getPendingRequests() async {
    final rows = await dbLoadPendingRequests();
    return rows.map((row) => ContactRequestModel.fromMap(row)).toList();
  }

  @override
  Future<void> updateStatus(String peerId, ContactRequestStatus status) async {
    final statusString = _statusToString(status);
    await dbUpdateRequestStatus(peerId, statusString);
  }

  @override
  Future<ContactRequestDecisionResult> decideRequest({
    required ContactRequestModel expectedRequest,
    required bool accept,
    bool existingContactOnly = false,
    Future<void> Function()? beforeMarkAccepted,
  }) async {
    final result = await dbDecideRequest(
      expectedRequest.toMap(),
      accept,
      existingContactOnly,
      beforeMarkAccepted,
    );
    if (result == ContactRequestDecisionResult.accepted ||
        result == ContactRequestDecisionResult.alreadyAccepted) {
      await onContactAccepted?.call(expectedRequest.peerId);
    }
    return result;
  }

  @override
  Future<void> deleteRequest(String peerId) async {
    await dbDeleteRequest(peerId);
  }

  @override
  Future<bool> requestExists(String peerId) async {
    return await dbRequestExists(peerId);
  }

  String _statusToString(ContactRequestStatus status) {
    switch (status) {
      case ContactRequestStatus.accepted:
        return 'accepted';
      case ContactRequestStatus.declined:
        return 'declined';
      case ContactRequestStatus.pending:
        return 'pending';
    }
  }
}
