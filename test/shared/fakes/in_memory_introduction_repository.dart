import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_outbox_delivery.dart';
import 'package:flutter_app/features/introduction/domain/models/pending_introduction_response.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';

/// In-memory [IntroductionRepository] for integration tests.
class InMemoryIntroductionRepository implements IntroductionRepository {
  final Map<String, IntroductionModel> _store = {};
  final Map<String, PendingIntroductionResponse> _pendingResponses = {};
  final Map<String, IntroductionOutboxDelivery> _outboxDeliveries = {};

  @override
  Future<void> saveIntroduction(IntroductionModel intro) async {
    _store[intro.id] = intro;
  }

  @override
  Future<void> saveIntroductionWithOutboxDeliveries(
    IntroductionModel intro,
    List<IntroductionOutboxDelivery> deliveries,
  ) async {
    _store[intro.id] = intro;
    for (final delivery in deliveries) {
      _outboxDeliveries[delivery.deliveryId] = delivery;
    }
  }

  @override
  Future<void> replaceIntroductionWithPendingResponseMigration({
    required IntroductionModel intro,
    required List<IntroductionOutboxDelivery> deliveries,
    required List<String> replacedIntroductionIds,
  }) async {
    final replacedIdSet = replacedIntroductionIds.toSet();
    final pendingToMigrate = _pendingResponses.values
        .where((response) => replacedIdSet.contains(response.introductionId))
        .toList(growable: false);

    _store.removeWhere((id, _) => replacedIdSet.contains(id));
    _pendingResponses.removeWhere(
      (_, response) => replacedIdSet.contains(response.introductionId),
    );
    _outboxDeliveries.removeWhere(
      (_, delivery) => replacedIdSet.contains(delivery.introductionId),
    );

    _store[intro.id] = intro;
    for (final delivery in deliveries) {
      _outboxDeliveries[delivery.deliveryId] = delivery;
    }
    for (final response in pendingToMigrate) {
      final migrated = PendingIntroductionResponse(
        responseKey: PendingIntroductionResponse.buildResponseKey(
          introductionId: intro.id,
          responderId: response.responderId,
          action: response.action,
        ),
        introductionId: intro.id,
        action: response.action,
        responderId: response.responderId,
        transportSenderPeerId: response.transportSenderPeerId,
        responderUsername: response.responderUsername,
        createdAt: response.createdAt,
      );
      _pendingResponses[migrated.responseKey] = migrated;
    }
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
    final intro = _store[introductionId];
    if (intro == null) return false;
    final partyStatus = isRecipient
        ? intro.recipientStatus
        : intro.introducedStatus;
    if (intro.status != IntroductionOverallStatus.pending ||
        partyStatus != IntroductionStatus.pending) {
      return false;
    }
    final recipientStatus = isRecipient
        ? responseStatus
        : intro.recipientStatus;
    final introducedStatus = isRecipient
        ? intro.introducedStatus
        : responseStatus;
    final derivedOverallStatus = IntroductionModel.deriveStatus(
      recipientStatus: recipientStatus,
      introducedStatus: introducedStatus,
      createdAt: intro.createdAt,
    );
    _store[introductionId] = intro.copyWith(
      recipientStatus: recipientStatus,
      introducedStatus: introducedStatus,
      status: derivedOverallStatus,
      recipientRespondedAt: isRecipient
          ? respondedAt
          : intro.recipientRespondedAt,
      introducedRespondedAt: isRecipient
          ? intro.introducedRespondedAt
          : respondedAt,
    );
    for (final delivery in deliveries) {
      _outboxDeliveries[delivery.deliveryId] = delivery;
    }
    return true;
  }

  @override
  Future<IntroductionModel?> getIntroduction(String id) async {
    return _store[id];
  }

  @override
  Future<void> deleteIntroduction(String id) async {
    _store.remove(id);
    _pendingResponses.removeWhere(
      (_, response) => response.introductionId == id,
    );
    _outboxDeliveries.removeWhere(
      (_, delivery) => delivery.introductionId == id,
    );
  }

  @override
  Future<List<IntroductionModel>> getIntroductionsByRecipient(
    String recipientId,
  ) async {
    return _store.values.where((i) => i.recipientId == recipientId).toList();
  }

  @override
  Future<List<IntroductionModel>> getIntroductionsByIntroduced(
    String introducedId,
  ) async {
    return _store.values.where((i) => i.introducedId == introducedId).toList();
  }

  @override
  Future<List<IntroductionModel>> getIntroductionsByIntroducer(
    String introducerId,
  ) async {
    return _store.values.where((i) => i.introducerId == introducerId).toList();
  }

  @override
  Future<List<IntroductionModel>> getIntroductionsForRecipientAndIntroducer(
    String recipientId,
    String introducerId,
  ) async {
    return _store.values
        .where(
          (i) => i.recipientId == recipientId && i.introducerId == introducerId,
        )
        .toList();
  }

  @override
  Future<bool> updateRecipientStatus(
    String id,
    IntroductionStatus status,
  ) async {
    final intro = _store[id];
    if (intro == null) return false;
    if (intro.status != IntroductionOverallStatus.pending ||
        intro.recipientStatus != IntroductionStatus.pending) {
      return false;
    }
    _store[id] = intro.copyWith(
      recipientStatus: status,
      recipientRespondedAt: DateTime.now().toUtc().toIso8601String(),
    );
    return true;
  }

  @override
  Future<bool> updateIntroducedStatus(
    String id,
    IntroductionStatus status,
  ) async {
    final intro = _store[id];
    if (intro == null) return false;
    if (intro.status != IntroductionOverallStatus.pending ||
        intro.introducedStatus != IntroductionStatus.pending) {
      return false;
    }
    _store[id] = intro.copyWith(
      introducedStatus: status,
      introducedRespondedAt: DateTime.now().toUtc().toIso8601String(),
    );
    return true;
  }

  @override
  Future<void> updateOverallStatus(
    String id,
    IntroductionOverallStatus status,
  ) async {
    final intro = _store[id];
    if (intro == null) return;
    if (intro.status != IntroductionOverallStatus.pending) return;
    _store[id] = intro.copyWith(status: status);
  }

  @override
  Future<List<IntroductionModel>> getPendingIntroductionsForUser(
    String peerId,
  ) async {
    return _store.values
        .where(
          (i) =>
              (i.recipientId == peerId || i.introducedId == peerId) &&
              (i.status == IntroductionOverallStatus.pending ||
                  i.status == IntroductionOverallStatus.alreadyConnected),
        )
        .toList();
  }

  @override
  Future<int> countPendingIntroductions(String peerId) async {
    return _store.values
        .where(
          (i) =>
              (i.recipientId == peerId || i.introducedId == peerId) &&
              i.status == IntroductionOverallStatus.pending,
        )
        .length;
  }

  @override
  Future<void> savePendingResponse(PendingIntroductionResponse response) async {
    _pendingResponses[response.responseKey] = response;
  }

  @override
  Future<List<PendingIntroductionResponse>> loadPendingResponses(
    String introductionId,
  ) async {
    final responses =
        _pendingResponses.values
            .where((response) => response.introductionId == introductionId)
            .toList(growable: false)
          ..sort((a, b) {
            final createdAtCompare = a.createdAt.compareTo(b.createdAt);
            if (createdAtCompare != 0) {
              return createdAtCompare;
            }
            return a.responseKey.compareTo(b.responseKey);
          });
    return responses;
  }

  @override
  Future<void> deletePendingResponse(String responseKey) async {
    _pendingResponses.remove(responseKey);
  }

  @override
  Future<void> saveOutboxDelivery(IntroductionOutboxDelivery delivery) async {
    _outboxDeliveries[delivery.deliveryId] = delivery;
  }

  @override
  Future<List<IntroductionOutboxDelivery>> loadOutboxDeliveriesForIntroduction(
    String introductionId,
  ) async {
    final deliveries =
        _outboxDeliveries.values
            .where((delivery) => delivery.introductionId == introductionId)
            .toList(growable: false)
          ..sort((a, b) {
            final createdAtCompare = a.createdAt.compareTo(b.createdAt);
            if (createdAtCompare != 0) {
              return createdAtCompare;
            }
            return a.deliveryId.compareTo(b.deliveryId);
          });
    return deliveries;
  }

  @override
  Future<List<IntroductionOutboxDelivery>> loadRetryableOutboxDeliveries({
    Duration olderThan = const Duration(seconds: 60),
    int limit = 100,
  }) async {
    final threshold = DateTime.now().toUtc().subtract(olderThan);
    final deliveries =
        _outboxDeliveries.values
            .where((delivery) {
              if (delivery.deliveryStatus ==
                  IntroductionOutboxDeliveryStatus.failed) {
                return true;
              }
              if (delivery.deliveryStatus ==
                      IntroductionOutboxDeliveryStatus.delivered &&
                  delivery.deliveryPath ==
                      IntroductionOutboxDeliveryPath.inbox) {
                return true;
              }
              if (delivery.deliveryStatus !=
                      IntroductionOutboxDeliveryStatus.sending &&
                  delivery.deliveryStatus !=
                      IntroductionOutboxDeliveryStatus.sent) {
                return false;
              }
              final updatedAt = DateTime.tryParse(delivery.updatedAt);
              return updatedAt == null || !updatedAt.isAfter(threshold);
            })
            .toList(growable: false)
          ..sort((a, b) {
            final createdAtCompare = a.createdAt.compareTo(b.createdAt);
            if (createdAtCompare != 0) {
              return createdAtCompare;
            }
            return a.deliveryId.compareTo(b.deliveryId);
          });
    return deliveries.take(limit).toList(growable: false);
  }

  @override
  Future<void> deleteOutboxDelivery(String deliveryId) async {
    _outboxDeliveries.remove(deliveryId);
  }

  @override
  Future<void> deleteOutboxDeliveriesForIntroduction(
    String introductionId,
  ) async {
    _outboxDeliveries.removeWhere(
      (_, delivery) => delivery.introductionId == introductionId,
    );
  }

  List<IntroductionOutboxDelivery> allOutboxDeliveries() {
    final deliveries = _outboxDeliveries.values.toList(growable: false)
      ..sort((a, b) {
        final createdAtCompare = a.createdAt.compareTo(b.createdAt);
        if (createdAtCompare != 0) {
          return createdAtCompare;
        }
        return a.deliveryId.compareTo(b.deliveryId);
      });
    return deliveries;
  }

  /// Clears all stored introductions. Test helper only.
  void clear() {
    _store.clear();
    _pendingResponses.clear();
    _outboxDeliveries.clear();
  }
}
