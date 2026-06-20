import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../application/orbit2_mock_data.dart';
import '../../domain/models/orbit2_friend.dart';
import '../../domain/models/orbit2_group.dart';
import 'orbit2_group_node.dart';

/// Read-only "Messages" surface: each conversation as an avatar + its last
/// incoming line, ordered by (synthetic) recency. Shown instead of the
/// constellation when the view mode is Messages — the inner circle is absent
/// by construction.
class Orbit2InboxView extends StatelessWidget {
  final List<Orbit2InboxEntry> entries;
  final ValueChanged<Orbit2Friend> onOpenFriend;
  final ValueChanged<Orbit2Group> onOpenGroup;

  const Orbit2InboxView({
    super.key,
    required this.entries,
    required this.onOpenFriend,
    required this.onOpenGroup,
  });

  @override
  Widget build(BuildContext context) {
    final readable = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;

    if (entries.isEmpty) {
      return Center(
        child: Text(
          l10n.orbit2_inbox_empty,
          style: TextStyle(fontSize: 14, color: readable.textMuted),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 92),
      itemCount: entries.length,
      itemBuilder: (context, i) =>
          _InboxRow(entry: entries[i], readable: readable, onOpenFriend: onOpenFriend, onOpenGroup: onOpenGroup),
    );
  }
}

class _InboxRow extends StatelessWidget {
  final Orbit2InboxEntry entry;
  final BackgroundReadableColors readable;
  final ValueChanged<Orbit2Friend> onOpenFriend;
  final ValueChanged<Orbit2Group> onOpenGroup;

  const _InboxRow({
    required this.entry,
    required this.readable,
    required this.onOpenFriend,
    required this.onOpenGroup,
  });

  @override
  Widget build(BuildContext context) {
    final line = entry.lastLine;
    final preview = line.isMe ? 'You: ${line.text}' : line.text;

    return Semantics(
      button: true,
      label: 'Open chat with ${entry.title}',
      child: GestureDetector(
        key: ValueKey('inbox-row-${entry.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => entry.isGroup
            ? onOpenGroup(entry.group!)
            : onOpenFriend(entry.friend!),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: readable.glassSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: readable.glassBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: entry.isGroup
                    ? Orbit2GroupNode(
                        key: ValueKey('inbox-avatar-${entry.id}'),
                        group: entry.group!,
                        size: 44,
                      )
                    : ClipOval(
                        key: ValueKey('inbox-avatar-${entry.id}'),
                        child: UserAvatar(
                          peerId: entry.friend!.peerId,
                          size: 44,
                          showGlow: false,
                          showPhotoFrame: false,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: readable.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          line.timeLabel,
                          style: TextStyle(
                            fontSize: 11,
                            color: readable.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (entry.isGroup && line.senderName != null) ...[
                          Text(
                            '${line.senderName}: ',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1ED760),
                            ),
                          ),
                        ],
                        Expanded(
                          child: Text(
                            preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: readable.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
