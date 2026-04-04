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
  Future<void> updateRecipientStatus(
    String id,
    IntroductionStatus status,
  ) async {
    final intro = _store[id];
    if (intro == null) return;
    _store[id] = intro.copyWith(
      recipientStatus: status,
      recipientRespondedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  @override
  Future<void> updateIntroducedStatus(
    String id,
    IntroductionStatus status,
  ) async {
    final intro = _store[id];
    if (intro == null) return;
    _store[id] = intro.copyWith(
      introducedStatus: status,
      introducedRespondedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  @override
  Future<void> updateOverallStatus(
    String id,
    IntroductionOverallStatus status,
  ) async {
    final intro = _store[id];
    if (intro == null) return;
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
