import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';

/// In-memory [IntroductionRepository] for integration tests.
class InMemoryIntroductionRepository implements IntroductionRepository {
  final Map<String, IntroductionModel> _store = {};

  @override
  Future<void> saveIntroduction(IntroductionModel intro) async {
    _store[intro.id] = intro;
  }

  @override
  Future<IntroductionModel?> getIntroduction(String id) async {
    return _store[id];
  }

  @override
  Future<List<IntroductionModel>> getIntroductionsByRecipient(
      String recipientId) async {
    return _store.values.where((i) => i.recipientId == recipientId).toList();
  }

  @override
  Future<List<IntroductionModel>> getIntroductionsByIntroduced(
      String introducedId) async {
    return _store.values.where((i) => i.introducedId == introducedId).toList();
  }

  @override
  Future<List<IntroductionModel>> getIntroductionsByIntroducer(
      String introducerId) async {
    return _store.values
        .where((i) => i.introducerId == introducerId)
        .toList();
  }

  @override
  Future<List<IntroductionModel>> getIntroductionsForRecipientAndIntroducer(
      String recipientId, String introducerId) async {
    return _store.values
        .where((i) =>
            i.recipientId == recipientId && i.introducerId == introducerId)
        .toList();
  }

  @override
  Future<void> updateRecipientStatus(
      String id, IntroductionStatus status) async {
    final intro = _store[id];
    if (intro == null) return;
    _store[id] = intro.copyWith(
      recipientStatus: status,
      recipientRespondedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  @override
  Future<void> updateIntroducedStatus(
      String id, IntroductionStatus status) async {
    final intro = _store[id];
    if (intro == null) return;
    _store[id] = intro.copyWith(
      introducedStatus: status,
      introducedRespondedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  @override
  Future<void> updateOverallStatus(
      String id, IntroductionOverallStatus status) async {
    final intro = _store[id];
    if (intro == null) return;
    _store[id] = intro.copyWith(status: status);
  }

  @override
  Future<List<IntroductionModel>> getPendingIntroductionsForUser(
      String peerId) async {
    return _store.values
        .where((i) =>
            (i.recipientId == peerId || i.introducedId == peerId) &&
            (i.status == IntroductionOverallStatus.pending ||
             i.status == IntroductionOverallStatus.alreadyConnected))
        .toList();
  }

  @override
  Future<int> countPendingIntroductions(String peerId) async {
    return _store.values
        .where((i) =>
            (i.recipientId == peerId || i.introducedId == peerId) &&
            i.status == IntroductionOverallStatus.pending)
        .length;
  }

  /// Clears all stored introductions. Test helper only.
  void clear() {
    _store.clear();
  }
}
