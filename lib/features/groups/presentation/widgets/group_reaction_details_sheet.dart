import 'package:flutter/material.dart';

import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

class GroupReactionParticipantEntry {
  final String peerId;
  final String displayName;
  final String emoji;
  final bool isSelf;

  const GroupReactionParticipantEntry({
    required this.peerId,
    required this.displayName,
    required this.emoji,
    this.isSelf = false,
  });
}

String groupReactionDisplayName({
  required String peerId,
  String? username,
  String? ownPeerId,
  String selfLabel = 'You',
}) {
  if (ownPeerId != null && peerId == ownPeerId) {
    return selfLabel;
  }

  final trimmed = username?.trim();
  if (trimmed != null && trimmed.isNotEmpty) {
    return trimmed;
  }

  return peerId.length > 12 ? '${peerId.substring(0, 12)}...' : peerId;
}

List<GroupReactionParticipantEntry> buildGroupReactionParticipantEntries({
  required List<MessageReaction> reactions,
  required String emoji,
  required Iterable<GroupMember> members,
  Map<String, String> usernameHintsByPeerId = const <String, String>{},
  String? ownPeerId,
  String selfLabel = 'You',
}) {
  final membersByPeerId = {for (final member in members) member.peerId: member};
  String? resolvedUsername(String peerId) {
    final memberUsername = membersByPeerId[peerId]?.username?.trim();
    if (memberUsername != null && memberUsername.isNotEmpty) {
      return memberUsername;
    }

    final hintUsername = usernameHintsByPeerId[peerId]?.trim();
    if (hintUsername != null && hintUsername.isNotEmpty) {
      return hintUsername;
    }

    return null;
  }

  final filtered =
      reactions.where((reaction) => reaction.emoji == emoji).toList()..sort((
        left,
        right,
      ) {
        final leftIsSelf = ownPeerId != null && left.senderPeerId == ownPeerId;
        final rightIsSelf =
            ownPeerId != null && right.senderPeerId == ownPeerId;
        if (leftIsSelf != rightIsSelf) {
          return leftIsSelf ? -1 : 1;
        }

        final leftName = groupReactionDisplayName(
          peerId: left.senderPeerId,
          username: resolvedUsername(left.senderPeerId),
          ownPeerId: ownPeerId,
          selfLabel: selfLabel,
        );
        final rightName = groupReactionDisplayName(
          peerId: right.senderPeerId,
          username: resolvedUsername(right.senderPeerId),
          ownPeerId: ownPeerId,
          selfLabel: selfLabel,
        );
        return leftName.toLowerCase().compareTo(rightName.toLowerCase());
      });

  return filtered
      .map(
        (reaction) => GroupReactionParticipantEntry(
          peerId: reaction.senderPeerId,
          displayName: groupReactionDisplayName(
            peerId: reaction.senderPeerId,
            username: resolvedUsername(reaction.senderPeerId),
            ownPeerId: ownPeerId,
            selfLabel: selfLabel,
          ),
          emoji: reaction.emoji,
          isSelf: ownPeerId != null && reaction.senderPeerId == ownPeerId,
        ),
      )
      .toList(growable: false);
}

Future<Map<String, String>> loadGroupReactionUsernameHints({
  required Iterable<String> peerIds,
  required ContactRepository contactRepo,
  required String groupId,
  GroupMessageRepository? msgRepo,
}) async {
  final unresolvedPeerIds = peerIds.toSet();
  final hintsByPeerId = <String, String>{};

  for (final peerId in unresolvedPeerIds.toList()) {
    final contact = await contactRepo.getContact(peerId);
    final username = contact?.username.trim();
    if (username != null && username.isNotEmpty) {
      hintsByPeerId[peerId] = username;
      unresolvedPeerIds.remove(peerId);
    }
  }

  if (unresolvedPeerIds.isEmpty || msgRepo == null) {
    return hintsByPeerId;
  }

  final recentMessages = await msgRepo.getMessagesPage(groupId, limit: 200);
  for (final message in recentMessages.reversed) {
    final peerId = message.senderPeerId;
    if (!unresolvedPeerIds.contains(peerId)) {
      continue;
    }

    final username = message.senderUsername?.trim();
    if (username == null || username.isEmpty) {
      continue;
    }

    hintsByPeerId[peerId] = username;
    unresolvedPeerIds.remove(peerId);
    if (unresolvedPeerIds.isEmpty) {
      break;
    }
  }

  return hintsByPeerId;
}

class GroupReactionDetailsSheet extends StatelessWidget {
  static const sheetKey = ValueKey('group-reaction-details-sheet');

  static ValueKey rowKey(String peerId) =>
      ValueKey('group-reaction-participant-$peerId');

  final String emoji;
  final List<GroupReactionParticipantEntry> participants;

  const GroupReactionDetailsSheet({
    super.key,
    required this.emoji,
    required this.participants,
  });

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          key: sheetKey,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: readableColors.divider,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.group_reactions_title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: readableColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$emoji ${participants.length}',
              style: TextStyle(
                fontSize: 13,
                color: readableColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: participants.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: readableColors.divider),
                itemBuilder: (context, index) {
                  final participant = participants[index];
                  return ListTile(
                    key: rowKey(participant.peerId),
                    contentPadding: EdgeInsets.zero,
                    leading: UserAvatar(
                      peerId: participant.peerId,
                      size: 36,
                      showPhotoFrame: false,
                    ),
                    title: Text(
                      participant.displayName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: readableColors.textPrimary,
                      ),
                    ),
                    trailing: Text(
                      participant.emoji,
                      style: const TextStyle(fontSize: 20),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
