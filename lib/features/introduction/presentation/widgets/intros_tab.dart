import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intro_group_header.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intro_row.dart';

/// Tab content for the Orbit screen's "Intros" filter tab.
///
/// Renders introductions grouped by introducer. Each group has a header
/// ("From [username]") followed by individual [IntroRow] widgets.
class IntrosTab extends StatelessWidget {
  final Map<String, List<IntroductionModel>> groupedIntros;
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

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    if (groupedIntros.isEmpty) {
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
