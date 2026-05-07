import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';

class FoldedIntroductionReviewItem {
  final String targetPeerId;
  final String? targetPeerName;
  final String targetDisplayName;
  final String displaySourceIntroductionId;
  final IntroductionModel newestIntroduction;
  final List<IntroductionModel> introductions;
  final List<String> introductionIds;
  final List<FoldedIntroductionIntroducerAttribution> introducerAttributions;
  final List<String> pendingCurrentViewerDecisionIntroIds;
  final List<String> acceptedCurrentViewerDecisionIntroIds;
  final List<String> passedCurrentViewerDecisionIntroIds;

  FoldedIntroductionReviewItem({
    required this.targetPeerId,
    required this.targetPeerName,
    required this.targetDisplayName,
    required this.displaySourceIntroductionId,
    required this.newestIntroduction,
    required List<IntroductionModel> introductions,
    required List<String> introductionIds,
    required List<FoldedIntroductionIntroducerAttribution>
    introducerAttributions,
    required List<String> pendingCurrentViewerDecisionIntroIds,
    required List<String> acceptedCurrentViewerDecisionIntroIds,
    required List<String> passedCurrentViewerDecisionIntroIds,
  }) : introductions = List.unmodifiable(introductions),
       introductionIds = List.unmodifiable(introductionIds),
       introducerAttributions = List.unmodifiable(introducerAttributions),
       pendingCurrentViewerDecisionIntroIds = List.unmodifiable(
         pendingCurrentViewerDecisionIntroIds,
       ),
       acceptedCurrentViewerDecisionIntroIds = List.unmodifiable(
         acceptedCurrentViewerDecisionIntroIds,
       ),
       passedCurrentViewerDecisionIntroIds = List.unmodifiable(
         passedCurrentViewerDecisionIntroIds,
       );

  bool get hasCurrentViewerResponded =>
      acceptedCurrentViewerDecisionIntroIds.isNotEmpty ||
      passedCurrentViewerDecisionIntroIds.isNotEmpty;

  bool get hasPendingCurrentViewerDecision =>
      pendingCurrentViewerDecisionIntroIds.isNotEmpty;
}

class FoldedIntroductionIntroducerAttribution {
  final String introducerId;
  final String displayName;

  const FoldedIntroductionIntroducerAttribution({
    required this.introducerId,
    required this.displayName,
  });
}

/// Loads all pending introductions for the given user (as recipient or
/// introduced party).
Future<List<IntroductionModel>> loadIntroductionsForUser({
  required IntroductionRepository introRepo,
  required String peerId,
}) async {
  emitFlowEvent(
    layer: 'UC',
    event: 'LOAD_INTRODUCTIONS_START',
    details: {'peerId': peerId.length > 10 ? peerId.substring(0, 10) : peerId},
  );

  final intros = await introRepo.getPendingIntroductionsForUser(peerId);

  emitFlowEvent(
    layer: 'UC',
    event: 'LOAD_INTRODUCTIONS_DONE',
    details: {'count': intros.length},
  );

  return intros;
}

List<FoldedIntroductionReviewItem> foldIntroductionsForReview({
  required List<IntroductionModel> introductions,
  required String ownPeerId,
}) {
  final groupedByTargetPeer = <String, List<IntroductionModel>>{};

  for (final intro in introductions) {
    if (!_isActiveReviewStatus(intro.status)) {
      continue;
    }

    final targetPeerId = _targetPeerIdForViewer(intro, ownPeerId);
    if (targetPeerId == null) {
      continue;
    }

    groupedByTargetPeer
        .putIfAbsent(targetPeerId, () => <IntroductionModel>[])
        .add(intro);
  }

  final items = groupedByTargetPeer.entries
      .map((entry) {
        final sortedIntroductions = entry.value.toList(growable: false)
          ..sort(_compareIntroductionsNewestFirst);
        final newestIntroduction = sortedIntroductions.first;
        final targetPeerName = _targetPeerNameForViewer(
          newestIntroduction,
          ownPeerId,
        );

        final pendingCurrentViewerDecisionIntroIds = <String>[];
        final acceptedCurrentViewerDecisionIntroIds = <String>[];
        final passedCurrentViewerDecisionIntroIds = <String>[];

        for (final intro in sortedIntroductions) {
          final currentViewerStatus = _currentViewerStatus(intro, ownPeerId);
          switch (currentViewerStatus) {
            case IntroductionStatus.pending:
              if (intro.status == IntroductionOverallStatus.pending) {
                pendingCurrentViewerDecisionIntroIds.add(intro.id);
              }
              break;
            case IntroductionStatus.accepted:
              acceptedCurrentViewerDecisionIntroIds.add(intro.id);
              break;
            case IntroductionStatus.passed:
              passedCurrentViewerDecisionIntroIds.add(intro.id);
              break;
            case null:
              break;
          }
        }

        return FoldedIntroductionReviewItem(
          targetPeerId: entry.key,
          targetPeerName: targetPeerName,
          targetDisplayName: _displayName(
            targetPeerName,
            fallbackPeerId: entry.key,
          ),
          displaySourceIntroductionId: newestIntroduction.id,
          newestIntroduction: newestIntroduction,
          introductions: sortedIntroductions,
          introductionIds: sortedIntroductions
              .map((intro) => intro.id)
              .toList(growable: false),
          introducerAttributions: _introducerAttributions(sortedIntroductions),
          pendingCurrentViewerDecisionIntroIds:
              pendingCurrentViewerDecisionIntroIds,
          acceptedCurrentViewerDecisionIntroIds:
              acceptedCurrentViewerDecisionIntroIds,
          passedCurrentViewerDecisionIntroIds:
              passedCurrentViewerDecisionIntroIds,
        );
      })
      .toList(growable: false);

  return items..sort((a, b) {
    final newestCompare = _compareIntroductionsNewestFirst(
      a.newestIntroduction,
      b.newestIntroduction,
    );
    if (newestCompare != 0) {
      return newestCompare;
    }
    return a.targetPeerId.compareTo(b.targetPeerId);
  });
}

int countFoldedPendingIntroductionTargets({
  required List<IntroductionModel> introductions,
  required String ownPeerId,
}) {
  final targetPeerIds = <String>{};

  for (final intro in introductions) {
    if (intro.status != IntroductionOverallStatus.pending) {
      continue;
    }

    final targetPeerId = _targetPeerIdForViewer(intro, ownPeerId);
    if (targetPeerId == null) {
      continue;
    }

    targetPeerIds.add(targetPeerId);
  }

  return targetPeerIds.length;
}

/// Groups a list of introductions by their introducer ID.
///
/// Returns a map where each key is an introducer's peer ID and the value
/// is the list of introductions from that introducer.
Map<String, List<IntroductionModel>> groupByIntroducer(
  List<IntroductionModel> intros,
) {
  final grouped = <String, List<IntroductionModel>>{};
  for (final intro in intros) {
    final key = intro.introducerId;
    grouped.putIfAbsent(key, () => []).add(intro);
  }
  return grouped;
}

bool _isActiveReviewStatus(IntroductionOverallStatus status) {
  return status == IntroductionOverallStatus.pending ||
      status == IntroductionOverallStatus.alreadyConnected;
}

String? _targetPeerIdForViewer(IntroductionModel intro, String ownPeerId) {
  if (intro.recipientId == ownPeerId) {
    return intro.introducedId;
  }
  if (intro.introducedId == ownPeerId) {
    return intro.recipientId;
  }
  return null;
}

String? _targetPeerNameForViewer(IntroductionModel intro, String ownPeerId) {
  if (intro.recipientId == ownPeerId) {
    return _cleanDisplayName(intro.introducedUsername);
  }
  if (intro.introducedId == ownPeerId) {
    return _cleanDisplayName(intro.recipientUsername);
  }
  return null;
}

IntroductionStatus? _currentViewerStatus(
  IntroductionModel intro,
  String ownPeerId,
) {
  if (intro.recipientId == ownPeerId) {
    return intro.recipientStatus;
  }
  if (intro.introducedId == ownPeerId) {
    return intro.introducedStatus;
  }
  return null;
}

List<FoldedIntroductionIntroducerAttribution> _introducerAttributions(
  List<IntroductionModel> introductions,
) {
  final byIntroducer = <String, FoldedIntroductionIntroducerAttribution>{};

  for (final intro in introductions) {
    final displayName = _displayName(
      intro.introducerUsername,
      fallbackPeerId: intro.introducerId,
    );
    final existing = byIntroducer[intro.introducerId];
    if (existing == null || existing.displayName == intro.introducerId) {
      byIntroducer[intro.introducerId] =
          FoldedIntroductionIntroducerAttribution(
            introducerId: intro.introducerId,
            displayName: displayName,
          );
    }
  }

  return byIntroducer.values.toList(growable: false);
}

int _compareIntroductionsNewestFirst(IntroductionModel a, IntroductionModel b) {
  final aCreatedAt = DateTime.tryParse(a.createdAt);
  final bCreatedAt = DateTime.tryParse(b.createdAt);

  if (aCreatedAt != null && bCreatedAt != null) {
    final createdAtCompare = bCreatedAt.compareTo(aCreatedAt);
    if (createdAtCompare != 0) {
      return createdAtCompare;
    }
  } else if (aCreatedAt != null) {
    return -1;
  } else if (bCreatedAt != null) {
    return 1;
  }

  return a.id.compareTo(b.id);
}

String _displayName(String? value, {String? fallbackPeerId}) {
  final cleanedValue = _cleanDisplayName(value);
  if (cleanedValue != null) {
    return cleanedValue;
  }

  final cleanedPeerId = _cleanDisplayName(fallbackPeerId);
  if (cleanedPeerId != null) {
    return cleanedPeerId;
  }

  return 'Unknown';
}

String? _cleanDisplayName(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}
