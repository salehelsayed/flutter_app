import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';

/// Scans pending introductions and expires any older than 30 days.
///
/// Should be called periodically (e.g., on Orbit screen load) to keep
/// the DB in sync with the time-based expiry rule.
Future<int> expireOldIntroductions({
  required IntroductionRepository introRepo,
  required String peerId,
}) async {
  emitFlowEvent(
    layer: 'UC',
    event: 'EXPIRE_OLD_INTROS_START',
    details: {'peerId': peerId.length > 10 ? peerId.substring(0, 10) : peerId},
  );

  final pending = await introRepo.getPendingIntroductionsForUser(peerId);
  int expiredCount = 0;

  for (final intro in pending) {
    final derived = IntroductionModel.deriveStatus(
      recipientStatus: intro.recipientStatus,
      introducedStatus: intro.introducedStatus,
      createdAt: intro.createdAt,
    );

    if (derived == IntroductionOverallStatus.expired) {
      await introRepo.updateOverallStatus(intro.id, IntroductionOverallStatus.expired);
      expiredCount++;
    }
  }

  emitFlowEvent(
    layer: 'UC',
    event: 'EXPIRE_OLD_INTROS_DONE',
    details: {'expiredCount': expiredCount},
  );

  return expiredCount;
}
