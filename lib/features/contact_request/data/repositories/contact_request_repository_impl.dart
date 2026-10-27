import 'package:flutter_app/core/database/db_write_transaction.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

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

/// Rechecks the displayed request and commits contact/decision together.
Future<ContactRequestDecisionResult> dbDecideContactRequest(
  Database db,
  Map<String, Object?> expected,
  bool accept,
  bool existingContactOnly,
  Future<void> Function()? beforeMarkAccepted, {
  Future<void> Function()? beforeCreateContact,
}) async {
  final peerId = expected['peer_id'] as String;
  var failure = ContactRequestDecisionResult.updateStatusError;
  try {
    return await dbWriteTransaction(db, (txn) async {
      final rows = await txn.query(
        'contact_requests',
        where: 'peer_id = ?',
        whereArgs: [peerId],
        limit: 1,
      );
      if (rows.isEmpty) return ContactRequestDecisionResult.notFound;
      final current = rows.single;
      if (current['public_key'] != expected['public_key'] ||
          current['signature'] != expected['signature'] ||
          current['received_at'] != expected['received_at']) {
        return ContactRequestDecisionResult.notPending;
      }
      final contacts = await txn.query(
        'contacts',
        where: 'peer_id = ?',
        whereArgs: [peerId],
        limit: 1,
      );
      final hasContact = contacts.isNotEmpty;
      final blocked = hasContact && contacts.single['is_blocked'] == 1;
      if (current['status'] == 'accepted') {
        if (blocked) return ContactRequestDecisionResult.blocked;
        return hasContact && accept
            ? ContactRequestDecisionResult.alreadyAccepted
            : ContactRequestDecisionResult.notPending;
      }
      if (current['status'] != 'pending') {
        return !accept && current['status'] == 'declined'
            ? ContactRequestDecisionResult.declined
            : ContactRequestDecisionResult.notPending;
      }

      Future<void> mark(String status) async {
        final changed = await txn.update(
          'contact_requests',
          {'status': status},
          where:
              'peer_id = ? AND public_key = ? AND signature = ? '
              'AND received_at = ? AND status = ?',
          whereArgs: [
            peerId,
            expected['public_key'],
            expected['signature'],
            expected['received_at'],
            'pending',
          ],
        );
        if (changed != 1) {
          throw StateError('Contact request changed during decision');
        }
      }

      if (hasContact) {
        if (blocked && existingContactOnly) {
          return ContactRequestDecisionResult.blocked;
        }
        if (!blocked) {
          await beforeMarkAccepted?.call();
        }
        await mark('accepted');
        if (blocked) return ContactRequestDecisionResult.blocked;
        return accept && !existingContactOnly
            ? ContactRequestDecisionResult.accepted
            : ContactRequestDecisionResult.alreadyAccepted;
      }
      if (!accept) {
        await mark('declined');
        return ContactRequestDecisionResult.declined;
      }
      if (existingContactOnly) return ContactRequestDecisionResult.pending;

      failure = ContactRequestDecisionResult.addContactError;
      await beforeCreateContact?.call();
      await txn.insert(
        'contacts',
        ContactRequestModel.fromMap(current).toContactModel().toMap(),
      );
      failure = ContactRequestDecisionResult.updateStatusError;
      await beforeMarkAccepted?.call();
      await mark('accepted');
      return ContactRequestDecisionResult.accepted;
    });
  } catch (error) {
    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACT_REQUESTS_DB_DECISION_ERROR',
      details: {'error': error.toString()},
    );
    return failure;
  }
}
