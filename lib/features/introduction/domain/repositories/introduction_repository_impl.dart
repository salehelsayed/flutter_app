import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import '../models/introduction_model.dart';
import 'introduction_repository.dart';

/// Implementation of IntroductionRepository using database helper functions.
class IntroductionRepositoryImpl implements IntroductionRepository {
  final Future<void> Function(Map<String, Object?> row) dbInsertIntroduction;
  final Future<Map<String, Object?>?> Function(String id) dbLoadIntroduction;
  final Future<List<Map<String, Object?>>> Function(String recipientId)
      dbLoadIntroductionsByRecipient;
  final Future<List<Map<String, Object?>>> Function(String introducedId)
      dbLoadIntroductionsByIntroduced;
  final Future<List<Map<String, Object?>>> Function(String introducerId)
      dbLoadIntroductionsByIntroducer;
  final Future<List<Map<String, Object?>>> Function(
    String recipientId,
    String introducerId,
  ) dbLoadIntroductionsForRecipientAndIntroducer;
  final Future<void> Function(String id, String status, String respondedAt)
      dbUpdateRecipientStatus;
  final Future<void> Function(String id, String status, String respondedAt)
      dbUpdateIntroducedStatus;
  final Future<void> Function(String id, String status) dbUpdateOverallStatus;
  final Future<List<Map<String, Object?>>> Function(String peerId)
      dbLoadPendingIntroductionsForUser;
  final Future<int> Function(String peerId) dbCountPendingIntroductions;

  IntroductionRepositoryImpl({
    required this.dbInsertIntroduction,
    required this.dbLoadIntroduction,
    required this.dbLoadIntroductionsByRecipient,
    required this.dbLoadIntroductionsByIntroduced,
    required this.dbLoadIntroductionsByIntroducer,
    required this.dbLoadIntroductionsForRecipientAndIntroducer,
    required this.dbUpdateRecipientStatus,
    required this.dbUpdateIntroducedStatus,
    required this.dbUpdateOverallStatus,
    required this.dbLoadPendingIntroductionsForUser,
    required this.dbCountPendingIntroductions,
  });

  @override
  Future<void> saveIntroduction(IntroductionModel intro) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'INTRODUCTIONS_REPO_SAVE_START',
      details: {'id': intro.id.length > 10 ? intro.id.substring(0, 10) : intro.id},
    );

    try {
      await dbInsertIntroduction(intro.toMap());

      emitFlowEvent(
        layer: 'FL',
        event: 'INTRODUCTIONS_REPO_SAVE_SUCCESS',
        details: {'id': intro.id.length > 10 ? intro.id.substring(0, 10) : intro.id},
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'INTRODUCTIONS_REPO_SAVE_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }

  @override
  Future<IntroductionModel?> getIntroduction(String id) async {
    final row = await dbLoadIntroduction(id);
    if (row == null) return null;
    return IntroductionModel.fromMap(row);
  }

  @override
  Future<List<IntroductionModel>> getIntroductionsByRecipient(String recipientId) async {
    final rows = await dbLoadIntroductionsByRecipient(recipientId);
    return rows.map((row) => IntroductionModel.fromMap(row)).toList();
  }

  @override
  Future<List<IntroductionModel>> getIntroductionsByIntroduced(String introducedId) async {
    final rows = await dbLoadIntroductionsByIntroduced(introducedId);
    return rows.map((row) => IntroductionModel.fromMap(row)).toList();
  }

  @override
  Future<List<IntroductionModel>> getIntroductionsByIntroducer(String introducerId) async {
    final rows = await dbLoadIntroductionsByIntroducer(introducerId);
    return rows.map((row) => IntroductionModel.fromMap(row)).toList();
  }

  @override
  Future<List<IntroductionModel>> getIntroductionsForRecipientAndIntroducer(
    String recipientId,
    String introducerId,
  ) async {
    final rows = await dbLoadIntroductionsForRecipientAndIntroducer(
      recipientId,
      introducerId,
    );
    return rows.map((row) => IntroductionModel.fromMap(row)).toList();
  }

  @override
  Future<void> updateRecipientStatus(String id, IntroductionStatus status) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'INTRODUCTIONS_REPO_UPDATE_RECIPIENT_STATUS_START',
      details: {'id': id.length > 10 ? id.substring(0, 10) : id, 'status': status.toDbString()},
    );

    try {
      final respondedAt = DateTime.now().toUtc().toIso8601String();
      await dbUpdateRecipientStatus(id, status.toDbString(), respondedAt);

      emitFlowEvent(
        layer: 'FL',
        event: 'INTRODUCTIONS_REPO_UPDATE_RECIPIENT_STATUS_SUCCESS',
        details: {'id': id.length > 10 ? id.substring(0, 10) : id, 'status': status.toDbString()},
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'INTRODUCTIONS_REPO_UPDATE_RECIPIENT_STATUS_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }

  @override
  Future<void> updateIntroducedStatus(String id, IntroductionStatus status) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'INTRODUCTIONS_REPO_UPDATE_INTRODUCED_STATUS_START',
      details: {'id': id.length > 10 ? id.substring(0, 10) : id, 'status': status.toDbString()},
    );

    try {
      final respondedAt = DateTime.now().toUtc().toIso8601String();
      await dbUpdateIntroducedStatus(id, status.toDbString(), respondedAt);

      emitFlowEvent(
        layer: 'FL',
        event: 'INTRODUCTIONS_REPO_UPDATE_INTRODUCED_STATUS_SUCCESS',
        details: {'id': id.length > 10 ? id.substring(0, 10) : id, 'status': status.toDbString()},
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'INTRODUCTIONS_REPO_UPDATE_INTRODUCED_STATUS_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }

  @override
  Future<void> updateOverallStatus(String id, IntroductionOverallStatus status) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'INTRODUCTIONS_REPO_UPDATE_OVERALL_STATUS_START',
      details: {'id': id.length > 10 ? id.substring(0, 10) : id, 'status': status.toDbString()},
    );

    try {
      await dbUpdateOverallStatus(id, status.toDbString());

      emitFlowEvent(
        layer: 'FL',
        event: 'INTRODUCTIONS_REPO_UPDATE_OVERALL_STATUS_SUCCESS',
        details: {'id': id.length > 10 ? id.substring(0, 10) : id, 'status': status.toDbString()},
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'INTRODUCTIONS_REPO_UPDATE_OVERALL_STATUS_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }

  @override
  Future<List<IntroductionModel>> getPendingIntroductionsForUser(String peerId) async {
    final rows = await dbLoadPendingIntroductionsForUser(peerId);
    return rows.map((row) => IntroductionModel.fromMap(row)).toList();
  }

  @override
  Future<int> countPendingIntroductions(String peerId) async {
    return await dbCountPendingIntroductions(peerId);
  }
}
