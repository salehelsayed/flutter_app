import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';

/// Loads all pending introductions for the given user (as recipient or
/// introduced party).
Future<List<IntroductionModel>> loadIntroductionsForUser({
  required IntroductionRepository introRepo,
  required String peerId,
}) async {
  emitFlowEvent(
    layer: 'UC',
    event: 'LOAD_INTRODUCTIONS_START',
    details: {
      'peerId': peerId.length > 10 ? peerId.substring(0, 10) : peerId,
    },
  );

  final intros = await introRepo.getPendingIntroductionsForUser(peerId);

  emitFlowEvent(
    layer: 'UC',
    event: 'LOAD_INTRODUCTIONS_DONE',
    details: {'count': intros.length},
  );

  return intros;
}

/// Groups a list of introductions by their introducer ID.
///
/// Returns a map where each key is an introducer's peer ID and the value
/// is the list of introductions from that introducer.
Map<String, List<IntroductionModel>> groupByIntroducer(
    List<IntroductionModel> intros) {
  final grouped = <String, List<IntroductionModel>>{};
  for (final intro in intros) {
    final key = intro.introducerId;
    grouped.putIfAbsent(key, () => []).add(intro);
  }
  return grouped;
}
