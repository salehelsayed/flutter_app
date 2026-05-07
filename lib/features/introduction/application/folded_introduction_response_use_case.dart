import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/introduction/application/accept_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/application/load_introductions_use_case.dart';
import 'package:flutter_app/features/introduction/application/pass_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';

enum FoldedIntroductionActionOutcome { applied, skippedNotPending, failed }

class FoldedIntroductionActionResult {
  final String introductionId;
  final FoldedIntroductionActionOutcome outcome;
  final IntroductionModel? introduction;

  const FoldedIntroductionActionResult({
    required this.introductionId,
    required this.outcome,
    required this.introduction,
  });
}

class FoldedIntroductionActionBatchResult {
  final List<FoldedIntroductionActionResult> results;

  FoldedIntroductionActionBatchResult({
    required List<FoldedIntroductionActionResult> results,
  }) : results = List.unmodifiable(results);

  List<FoldedIntroductionActionResult> get appliedResults => results
      .where(
        (result) => result.outcome == FoldedIntroductionActionOutcome.applied,
      )
      .toList(growable: false);

  List<FoldedIntroductionActionResult> get skippedNotPendingResults => results
      .where(
        (result) =>
            result.outcome == FoldedIntroductionActionOutcome.skippedNotPending,
      )
      .toList(growable: false);

  List<FoldedIntroductionActionResult> get failedResults => results
      .where(
        (result) => result.outcome == FoldedIntroductionActionOutcome.failed,
      )
      .toList(growable: false);

  bool get hasFailures => failedResults.isNotEmpty;
}

Future<FoldedIntroductionActionBatchResult> acceptFoldedIntroduction({
  required IntroductionRepository introRepo,
  required ContactRepository contactRepo,
  required P2PService p2pService,
  required Bridge bridge,
  required FoldedIntroductionReviewItem foldedIntroduction,
  required String ownPeerId,
  required String ownUsername,
  MessageRepository? messageRepo,
}) {
  return _applyFoldedIntroductionAction(
    introRepo: introRepo,
    foldedIntroduction: foldedIntroduction,
    ownPeerId: ownPeerId,
    applySingleIntroduction: (introductionId) => acceptIntroduction(
      introRepo: introRepo,
      contactRepo: contactRepo,
      p2pService: p2pService,
      bridge: bridge,
      introductionId: introductionId,
      ownPeerId: ownPeerId,
      ownUsername: ownUsername,
      messageRepo: messageRepo,
    ),
  );
}

Future<FoldedIntroductionActionBatchResult> passFoldedIntroduction({
  required IntroductionRepository introRepo,
  required ContactRepository contactRepo,
  required P2PService p2pService,
  required Bridge bridge,
  required FoldedIntroductionReviewItem foldedIntroduction,
  required String ownPeerId,
  required String ownUsername,
}) {
  return _applyFoldedIntroductionAction(
    introRepo: introRepo,
    foldedIntroduction: foldedIntroduction,
    ownPeerId: ownPeerId,
    applySingleIntroduction: (introductionId) => passIntroduction(
      introRepo: introRepo,
      contactRepo: contactRepo,
      p2pService: p2pService,
      bridge: bridge,
      introductionId: introductionId,
      ownPeerId: ownPeerId,
      ownUsername: ownUsername,
    ),
  );
}

Future<FoldedIntroductionActionBatchResult> _applyFoldedIntroductionAction({
  required IntroductionRepository introRepo,
  required FoldedIntroductionReviewItem foldedIntroduction,
  required String ownPeerId,
  required Future<IntroductionModel?> Function(String introductionId)
  applySingleIntroduction,
}) async {
  final results = <FoldedIntroductionActionResult>[];

  for (final introductionId
      in foldedIntroduction.pendingCurrentViewerDecisionIntroIds) {
    final currentIntro = await introRepo.getIntroduction(introductionId);
    if (_isNoLongerCurrentPendingDecision(currentIntro, ownPeerId)) {
      results.add(
        FoldedIntroductionActionResult(
          introductionId: introductionId,
          outcome: FoldedIntroductionActionOutcome.skippedNotPending,
          introduction: currentIntro,
        ),
      );
      continue;
    }

    final appliedIntro = await applySingleIntroduction(introductionId);
    if (appliedIntro == null) {
      final latestIntro = await introRepo.getIntroduction(introductionId);
      results.add(
        FoldedIntroductionActionResult(
          introductionId: introductionId,
          outcome: FoldedIntroductionActionOutcome.failed,
          introduction: latestIntro,
        ),
      );
      continue;
    }

    results.add(
      FoldedIntroductionActionResult(
        introductionId: introductionId,
        outcome: FoldedIntroductionActionOutcome.applied,
        introduction: appliedIntro,
      ),
    );
  }

  return FoldedIntroductionActionBatchResult(results: results);
}

bool _isNoLongerCurrentPendingDecision(
  IntroductionModel? introduction,
  String ownPeerId,
) {
  if (introduction == null) {
    return true;
  }

  final currentViewerStatus = _currentViewerStatus(introduction, ownPeerId);
  if (currentViewerStatus == null) {
    return false;
  }

  return introduction.status != IntroductionOverallStatus.pending ||
      currentViewerStatus != IntroductionStatus.pending;
}

IntroductionStatus? _currentViewerStatus(
  IntroductionModel introduction,
  String ownPeerId,
) {
  if (introduction.recipientId == ownPeerId) {
    return introduction.recipientStatus;
  }
  if (introduction.introducedId == ownPeerId) {
    return introduction.introducedStatus;
  }
  return null;
}
