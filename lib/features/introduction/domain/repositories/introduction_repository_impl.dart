import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import '../models/introduction_model.dart';
import '../models/introduction_outbox_delivery.dart';
import '../models/pending_introduction_response.dart';
import 'introduction_repository.dart';

/// Implementation of IntroductionRepository using database helper functions.
class IntroductionRepositoryImpl implements IntroductionRepository {
  final Future<void> Function(Map<String, Object?> row) dbInsertIntroduction;
  final Future<Map<String, Object?>?> Function(String id) dbLoadIntroduction;
  final Future<void> Function(String id) dbDeleteIntroduction;
  final Future<List<Map<String, Object?>>> Function(String recipientId)
  dbLoadIntroductionsByRecipient;
  final Future<List<Map<String, Object?>>> Function(String introducedId)
  dbLoadIntroductionsByIntroduced;
  final Future<List<Map<String, Object?>>> Function(String introducerId)
  dbLoadIntroductionsByIntroducer;
  final Future<List<Map<String, Object?>>> Function(
    String recipientId,
    String introducerId,
  )
  dbLoadIntroductionsForRecipientAndIntroducer;
  final Future<bool> Function(String id, String status, String respondedAt)
  dbUpdateRecipientStatus;
  final Future<bool> Function(String id, String status, String respondedAt)
  dbUpdateIntroducedStatus;
  final Future<void> Function(String id, String status) dbUpdateOverallStatus;
  final Future<List<Map<String, Object?>>> Function(String peerId)
  dbLoadPendingIntroductionsForUser;
  final Future<int> Function(String peerId) dbCountPendingIntroductions;
  final Future<void> Function(Map<String, Object?> row)
  dbUpsertPendingIntroductionResponse;
  final Future<List<Map<String, Object?>>> Function(String introductionId)
  dbLoadPendingIntroductionResponses;
  final Future<void> Function(String responseKey)
  dbDeletePendingIntroductionResponse;
  final Future<void> Function(Map<String, Object?> row)
  dbUpsertIntroductionOutboxDelivery;
  final Future<void> Function(
    Map<String, Object?> introductionRow,
    List<Map<String, Object?>> deliveryRows,
  )
  dbSaveIntroductionWithOutboxDeliveries;
  final Future<void> Function({
    required Map<String, Object?> introductionRow,
    required List<Map<String, Object?>> deliveryRows,
    required List<String> replacedIntroductionIds,
  })
  dbReplaceIntroductionWithPendingResponseMigration;
  final Future<bool> Function({
    required String introductionId,
    required bool isRecipient,
    required String responseStatus,
    required String respondedAt,
    required String overallStatus,
    required List<Map<String, Object?>> deliveryRows,
  })
  dbSaveIntroductionResponseWithOutboxDeliveries;
  final Future<List<Map<String, Object?>>> Function(String introductionId)
  dbLoadIntroductionOutboxDeliveriesForIntroduction;
  final Future<List<Map<String, Object?>>> Function({
    required String olderThan,
    int limit,
  })
  dbLoadRetryableIntroductionOutboxDeliveries;
  final Future<void> Function(String deliveryId)
  dbDeleteIntroductionOutboxDelivery;
  final Future<void> Function(String introductionId)
  dbDeleteIntroductionOutboxDeliveriesForIntroduction;

  IntroductionRepositoryImpl({
    required this.dbInsertIntroduction,
    required this.dbLoadIntroduction,
    required this.dbDeleteIntroduction,
    required this.dbLoadIntroductionsByRecipient,
    required this.dbLoadIntroductionsByIntroduced,
    required this.dbLoadIntroductionsByIntroducer,
    required this.dbLoadIntroductionsForRecipientAndIntroducer,
    required this.dbUpdateRecipientStatus,
    required this.dbUpdateIntroducedStatus,
    required this.dbUpdateOverallStatus,
    required this.dbLoadPendingIntroductionsForUser,
    required this.dbCountPendingIntroductions,
    required this.dbUpsertPendingIntroductionResponse,
    required this.dbLoadPendingIntroductionResponses,
    required this.dbDeletePendingIntroductionResponse,
    required this.dbUpsertIntroductionOutboxDelivery,
    required this.dbSaveIntroductionWithOutboxDeliveries,
    required this.dbReplaceIntroductionWithPendingResponseMigration,
    required this.dbSaveIntroductionResponseWithOutboxDeliveries,
    required this.dbLoadIntroductionOutboxDeliveriesForIntroduction,
    required this.dbLoadRetryableIntroductionOutboxDeliveries,
    required this.dbDeleteIntroductionOutboxDelivery,
    required this.dbDeleteIntroductionOutboxDeliveriesForIntroduction,
  });

  @override
  Future<void> saveIntroduction(IntroductionModel intro) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'INTRODUCTIONS_REPO_SAVE_START',
      details: {
        'id': intro.id.length > 10 ? intro.id.substring(0, 10) : intro.id,
      },
    );

    try {
      await dbInsertIntroduction(intro.toMap());

      emitFlowEvent(
        layer: 'FL',
        event: 'INTRODUCTIONS_REPO_SAVE_SUCCESS',
        details: {
          'id': intro.id.length > 10 ? intro.id.substring(0, 10) : intro.id,
        },
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
  Future<void> saveIntroductionWithOutboxDeliveries(
    IntroductionModel intro,
    List<IntroductionOutboxDelivery> deliveries,
  ) async {
    await dbSaveIntroductionWithOutboxDeliveries(
      intro.toMap(),
      deliveries.map((delivery) => delivery.toMap()).toList(growable: false),
    );
  }

  @override
  Future<void> replaceIntroductionWithPendingResponseMigration({
    required IntroductionModel intro,
    required List<IntroductionOutboxDelivery> deliveries,
    required List<String> replacedIntroductionIds,
  }) async {
    await dbReplaceIntroductionWithPendingResponseMigration(
      introductionRow: intro.toMap(),
      deliveryRows: deliveries
          .map((delivery) => delivery.toMap())
          .toList(growable: false),
      replacedIntroductionIds: replacedIntroductionIds,
    );
  }

  @override
  Future<bool> saveIntroductionResponseWithOutboxDeliveries({
    required String introductionId,
    required bool isRecipient,
    required IntroductionStatus responseStatus,
    required IntroductionOverallStatus overallStatus,
    required String respondedAt,
    required List<IntroductionOutboxDelivery> deliveries,
  }) async {
    return dbSaveIntroductionResponseWithOutboxDeliveries(
      introductionId: introductionId,
      isRecipient: isRecipient,
      responseStatus: responseStatus.toDbString(),
      respondedAt: respondedAt,
      overallStatus: overallStatus.toDbString(),
      deliveryRows: deliveries
          .map((delivery) => delivery.toMap())
          .toList(growable: false),
    );
  }

  @override
  Future<IntroductionModel?> getIntroduction(String id) async {
    final row = await dbLoadIntroduction(id);
    if (row == null) return null;
    return IntroductionModel.fromMap(row);
  }

  @override
  Future<void> deleteIntroduction(String id) async {
    final pendingResponses = await loadPendingResponses(id);
    for (final response in pendingResponses) {
      await deletePendingResponse(response.responseKey);
    }
    await deleteOutboxDeliveriesForIntroduction(id);
    await dbDeleteIntroduction(id);
  }

  @override
  Future<List<IntroductionModel>> getIntroductionsByRecipient(
    String recipientId,
  ) async {
    final rows = await dbLoadIntroductionsByRecipient(recipientId);
    return rows.map((row) => IntroductionModel.fromMap(row)).toList();
  }

  @override
  Future<List<IntroductionModel>> getIntroductionsByIntroduced(
    String introducedId,
  ) async {
    final rows = await dbLoadIntroductionsByIntroduced(introducedId);
    return rows.map((row) => IntroductionModel.fromMap(row)).toList();
  }

  @override
  Future<List<IntroductionModel>> getIntroductionsByIntroducer(
    String introducerId,
  ) async {
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
  Future<bool> updateRecipientStatus(
    String id,
    IntroductionStatus status,
  ) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'INTRODUCTIONS_REPO_UPDATE_RECIPIENT_STATUS_START',
      details: {
        'id': id.length > 10 ? id.substring(0, 10) : id,
        'status': status.toDbString(),
      },
    );

    try {
      final respondedAt = DateTime.now().toUtc().toIso8601String();
      final updated = await dbUpdateRecipientStatus(
        id,
        status.toDbString(),
        respondedAt,
      );

      emitFlowEvent(
        layer: 'FL',
        event: 'INTRODUCTIONS_REPO_UPDATE_RECIPIENT_STATUS_SUCCESS',
        details: {
          'id': id.length > 10 ? id.substring(0, 10) : id,
          'status': status.toDbString(),
          'updated': updated,
        },
      );
      return updated;
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
  Future<bool> updateIntroducedStatus(
    String id,
    IntroductionStatus status,
  ) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'INTRODUCTIONS_REPO_UPDATE_INTRODUCED_STATUS_START',
      details: {
        'id': id.length > 10 ? id.substring(0, 10) : id,
        'status': status.toDbString(),
      },
    );

    try {
      final respondedAt = DateTime.now().toUtc().toIso8601String();
      final updated = await dbUpdateIntroducedStatus(
        id,
        status.toDbString(),
        respondedAt,
      );

      emitFlowEvent(
        layer: 'FL',
        event: 'INTRODUCTIONS_REPO_UPDATE_INTRODUCED_STATUS_SUCCESS',
        details: {
          'id': id.length > 10 ? id.substring(0, 10) : id,
          'status': status.toDbString(),
          'updated': updated,
        },
      );
      return updated;
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
  Future<void> updateOverallStatus(
    String id,
    IntroductionOverallStatus status,
  ) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'INTRODUCTIONS_REPO_UPDATE_OVERALL_STATUS_START',
      details: {
        'id': id.length > 10 ? id.substring(0, 10) : id,
        'status': status.toDbString(),
      },
    );

    try {
      await dbUpdateOverallStatus(id, status.toDbString());

      emitFlowEvent(
        layer: 'FL',
        event: 'INTRODUCTIONS_REPO_UPDATE_OVERALL_STATUS_SUCCESS',
        details: {
          'id': id.length > 10 ? id.substring(0, 10) : id,
          'status': status.toDbString(),
        },
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
  Future<List<IntroductionModel>> getPendingIntroductionsForUser(
    String peerId,
  ) async {
    final rows = await dbLoadPendingIntroductionsForUser(peerId);
    return rows.map((row) => IntroductionModel.fromMap(row)).toList();
  }

  @override
  Future<int> countPendingIntroductions(String peerId) async {
    return await dbCountPendingIntroductions(peerId);
  }

  @override
  Future<void> savePendingResponse(PendingIntroductionResponse response) async {
    await dbUpsertPendingIntroductionResponse(response.toMap());
  }

  @override
  Future<List<PendingIntroductionResponse>> loadPendingResponses(
    String introductionId,
  ) async {
    final rows = await dbLoadPendingIntroductionResponses(introductionId);
    return rows
        .map((row) => PendingIntroductionResponse.fromMap(row))
        .toList(growable: false);
  }

  @override
  Future<void> deletePendingResponse(String responseKey) async {
    await dbDeletePendingIntroductionResponse(responseKey);
  }

  @override
  Future<void> saveOutboxDelivery(IntroductionOutboxDelivery delivery) async {
    await dbUpsertIntroductionOutboxDelivery(delivery.toMap());
  }

  @override
  Future<List<IntroductionOutboxDelivery>> loadOutboxDeliveriesForIntroduction(
    String introductionId,
  ) async {
    final rows = await dbLoadIntroductionOutboxDeliveriesForIntroduction(
      introductionId,
    );
    return rows.map(IntroductionOutboxDelivery.fromMap).toList(growable: false);
  }

  @override
  Future<List<IntroductionOutboxDelivery>> loadRetryableOutboxDeliveries({
    Duration olderThan = const Duration(seconds: 60),
    int limit = 100,
  }) async {
    final threshold = DateTime.now()
        .toUtc()
        .subtract(olderThan)
        .toIso8601String();
    final rows = await dbLoadRetryableIntroductionOutboxDeliveries(
      olderThan: threshold,
      limit: limit,
    );
    return rows.map(IntroductionOutboxDelivery.fromMap).toList(growable: false);
  }

  @override
  Future<void> deleteOutboxDelivery(String deliveryId) async {
    await dbDeleteIntroductionOutboxDelivery(deliveryId);
  }

  @override
  Future<void> deleteOutboxDeliveriesForIntroduction(
    String introductionId,
  ) async {
    await dbDeleteIntroductionOutboxDeliveriesForIntroduction(introductionId);
  }
}
