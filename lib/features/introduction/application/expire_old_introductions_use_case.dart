import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/introduction/application/handle_mutual_acceptance_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';

/// Reconciles stored pending introductions against current derived truth.
///
/// This heals upgrade-path rows that were left persisted as `pending` even
/// though party statuses now derive to `mutualAccepted`, `passed`, or
/// `expired`. When a stale row derives to `mutualAccepted`, this also reruns
/// the idempotent mutual-acceptance side effects so the missing contact can be
/// recreated on startup.
Future<int> expireOldIntroductions({
  required IntroductionRepository introRepo,
  required String peerId,
  ContactRepository? contactRepo,
  MessageRepository? messageRepo,
  Bridge? bridge,
}) async {
  emitFlowEvent(
    layer: 'UC',
    event: 'EXPIRE_OLD_INTROS_START',
    details: {'peerId': peerId.length > 10 ? peerId.substring(0, 10) : peerId},
  );

  final pending = await introRepo.getPendingIntroductionsForUser(peerId);
  int repairedCount = 0;

  for (final intro in pending) {
    // The pending loader also returns `alreadyConnected` rows for current
    // product behavior. Reconciliation only repairs stale stored `pending`
    // rows so we don't rewrite adjacent accepted contracts on startup.
    if (intro.status != IntroductionOverallStatus.pending) {
      continue;
    }

    final derived = IntroductionModel.deriveStatus(
      recipientStatus: intro.recipientStatus,
      introducedStatus: intro.introducedStatus,
      createdAt: intro.createdAt,
    );

    if (derived == IntroductionOverallStatus.pending) {
      continue;
    }

    await introRepo.updateOverallStatus(intro.id, derived);
    repairedCount++;

    if (derived == IntroductionOverallStatus.mutualAccepted &&
        contactRepo != null) {
      final repairedIntro =
          await introRepo.getIntroduction(intro.id) ??
          intro.copyWith(status: derived);
      await handleMutualAcceptance(
        introduction: repairedIntro,
        contactRepo: contactRepo,
        ownPeerId: peerId,
        messageRepo: messageRepo,
        bridge: bridge,
      );
    }
  }

  emitFlowEvent(
    layer: 'UC',
    event: 'EXPIRE_OLD_INTROS_DONE',
    details: {'expiredCount': repairedCount},
  );

  return repairedCount;
}
