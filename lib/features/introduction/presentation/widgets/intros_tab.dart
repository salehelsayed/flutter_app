import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/introduction/application/load_introductions_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intro_group_header.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intro_row.dart';

/// Tab content for the Orbit screen's "Intros" filter tab.
///
/// Renders introductions grouped by introducer. Each group has a header
/// ("From [username]") followed by individual [IntroRow] widgets.
class IntrosTab extends StatelessWidget {
  final Map<String, List<IntroductionModel>> groupedIntros;
  final List<FoldedIntroductionReviewItem>? foldedReviewItems;
  final Map<String, String> introducerUsernames;
  final void Function(String introductionId) onAccept;
  final void Function(String introductionId) onPass;
  final String ownPeerId;
  final void Function(String peerId)? onSendMessage;
  final Set<String> blockedPeerIds;
  final Set<String> processingIntroductionIds;

  const IntrosTab({
    super.key,
    required this.groupedIntros,
    this.foldedReviewItems,
    required this.introducerUsernames,
    required this.onAccept,
    required this.onPass,
    this.ownPeerId = '',
    this.onSendMessage,
    this.blockedPeerIds = const {},
    this.processingIntroductionIds = const {},
  });

  String _displayName(String? username, {String? fallbackPeerId}) {
    final trimmedUsername = username?.trim();
    if (trimmedUsername != null && trimmedUsername.isNotEmpty) {
      return trimmedUsername;
    }

    final trimmedPeerId = fallbackPeerId?.trim();
    if (trimmedPeerId != null && trimmedPeerId.isNotEmpty) {
      return trimmedPeerId;
    }

    return 'Unknown';
  }

  IntroductionStatus _ownPartyStatusForFolded(
    FoldedIntroductionReviewItem item,
  ) {
    if (item.passedCurrentViewerDecisionIntroIds.isNotEmpty) {
      return IntroductionStatus.passed;
    }
    if (item.acceptedCurrentViewerDecisionIntroIds.isNotEmpty) {
      return IntroductionStatus.accepted;
    }
    return IntroductionStatus.pending;
  }

  bool _showActionsForFolded(FoldedIntroductionReviewItem item) {
    return item.hasPendingCurrentViewerDecision &&
        !item.hasCurrentViewerResponded;
  }

  Widget _buildFoldedIntroRow(FoldedIntroductionReviewItem item) {
    final intro = item.newestIntroduction;
    final ownPartyStatus = _ownPartyStatusForFolded(item);
    final showActions = _showActionsForFolded(item);
    final isProcessing = item.introductionIds.any(
      (id) => processingIntroductionIds.contains(id),
    );

    return IntroRow(
      introduction: intro,
      displayUsername: item.targetDisplayName,
      displayPeerId: item.targetPeerId,
      introducerAttributionNames: item.introducerAttributions
          .map((attribution) => attribution.displayName)
          .toList(growable: false),
      showActions: showActions,
      isProcessing: isProcessing,
      onAccept: showActions
          ? () => onAccept(item.displaySourceIntroductionId)
          : null,
      onPass: showActions
          ? () => onPass(item.displaySourceIntroductionId)
          : null,
      ownPartyStatus: ownPartyStatus,
      waitingForUsername: item.targetDisplayName,
      onSendMessage:
          intro.status == IntroductionOverallStatus.mutualAccepted &&
              onSendMessage != null
          ? () => onSendMessage!(item.targetPeerId)
          : null,
      isOtherBlocked: blockedPeerIds.contains(item.targetPeerId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final foldedItems = foldedReviewItems;

    if (foldedItems != null ? foldedItems.isEmpty : groupedIntros.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No introductions yet',
            style: TextStyle(fontSize: 14, color: readableColors.textMuted),
          ),
        ),
      );
    }

    if (foldedItems != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'These are people your friends know well. Once you both accept, you can start chatting.',
                style: TextStyle(fontSize: 13, color: readableColors.textMuted),
                textAlign: TextAlign.center,
              ),
            ),
            for (final item in foldedItems)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildFoldedIntroRow(item),
              ),
          ],
        ),
      );
    }

    final introducerIds = groupedIntros.keys.toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'These are people your friends know well. Once you both accept, you can start chatting.',
              style: TextStyle(fontSize: 13, color: readableColors.textMuted),
              textAlign: TextAlign.center,
            ),
          ),
          for (
            var groupIndex = 0;
            groupIndex < introducerIds.length;
            groupIndex++
          ) ...[
            if (groupIndex > 0) const SizedBox(height: 16),
            IntroGroupHeader(
              introducerUsername: _displayName(
                introducerUsernames[introducerIds[groupIndex]],
                fallbackPeerId: introducerIds[groupIndex],
              ),
            ),
            const SizedBox(height: 8),
            for (final intro in groupedIntros[introducerIds[groupIndex]]!) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Builder(
                  builder: (context) {
                    final amRecipient = intro.recipientId == ownPeerId;
                    final displayPeerId = amRecipient
                        ? intro.introducedId
                        : intro.recipientId;
                    final displayUsername = amRecipient
                        ? _displayName(
                            intro.introducedUsername,
                            fallbackPeerId: displayPeerId,
                          )
                        : _displayName(
                            intro.recipientUsername,
                            fallbackPeerId: displayPeerId,
                          );
                    final ownPartyStatus = amRecipient
                        ? intro.recipientStatus
                        : intro.introducedStatus;
                    final waitingForUsername = amRecipient
                        ? _displayName(
                            intro.introducedUsername,
                            fallbackPeerId: displayPeerId,
                          )
                        : _displayName(
                            intro.recipientUsername,
                            fallbackPeerId: displayPeerId,
                          );
                    final showActions =
                        ownPartyStatus == IntroductionStatus.pending &&
                        intro.status == IntroductionOverallStatus.pending;

                    return IntroRow(
                      introduction: intro,
                      displayUsername: displayUsername,
                      displayPeerId: displayPeerId,
                      showActions: showActions,
                      isProcessing: processingIntroductionIds.contains(
                        intro.id,
                      ),
                      onAccept: showActions ? () => onAccept(intro.id) : null,
                      onPass: showActions ? () => onPass(intro.id) : null,
                      ownPartyStatus: ownPartyStatus,
                      waitingForUsername: waitingForUsername,
                      onSendMessage:
                          intro.status ==
                                  IntroductionOverallStatus.mutualAccepted &&
                              onSendMessage != null
                          ? () => onSendMessage!(displayPeerId)
                          : null,
                      isOtherBlocked: blockedPeerIds.contains(displayPeerId),
                    );
                  },
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
