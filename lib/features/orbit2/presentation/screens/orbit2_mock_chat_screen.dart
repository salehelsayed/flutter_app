import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/conversation/presentation/navigation/conversation_route_transition.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../application/orbit2_mock_data.dart';
import '../../domain/models/orbit2_friend.dart';
import '../../domain/models/orbit2_group.dart';
import '../widgets/orbit2_backdrop.dart';
import '../widgets/orbit2_group_node.dart';

/// Self-contained mock chat window for the Orbit2 prototype — works for both a
/// 1:1 friend and a group. Sending is intentionally disabled (visuals only).
class Orbit2MockChatScreen extends StatelessWidget {
  final Orbit2Friend? friend;
  final Orbit2Group? group;
  final BackgroundPreference backgroundPreference;

  const Orbit2MockChatScreen({
    super.key,
    this.friend,
    this.group,
    this.backgroundPreference = BackgroundPreference.defaultBackground,
  }) : assert(friend != null || group != null);

  static Future<void> open(
    BuildContext context, {
    required Orbit2Friend friend,
    BackgroundPreference backgroundPreference =
        BackgroundPreference.defaultBackground,
  }) {
    return Navigator.of(context).push<void>(
      buildConversationRoute(
        builder: (_) => Orbit2MockChatScreen(
          friend: friend,
          backgroundPreference: backgroundPreference,
        ),
      ),
    );
  }

  static Future<void> openGroup(
    BuildContext context, {
    required Orbit2Group group,
    BackgroundPreference backgroundPreference =
        BackgroundPreference.defaultBackground,
  }) {
    return Navigator.of(context).push<void>(
      buildConversationRoute(
        builder: (_) => Orbit2MockChatScreen(
          group: group,
          backgroundPreference: backgroundPreference,
        ),
      ),
    );
  }

  bool get _isGroup => group != null;

  @override
  Widget build(BuildContext context) {
    final readable = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
    final lines = _isGroup
        ? Orbit2MockData.groupThread(group!)
        : Orbit2MockData.thread(friend!);

    return Orbit2Backdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Column(
            children: [
              _Header(
                friend: friend,
                group: group,
                readable: readable,
                l10n: l10n,
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  itemCount: lines.length,
                  itemBuilder: (context, i) => _ChatBubble(
                    line: lines[i],
                    readable: readable,
                    showSender: _isGroup,
                  ),
                ),
              ),
              _StubComposer(readable: readable, l10n: l10n),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Orbit2Friend? friend;
  final Orbit2Group? group;
  final BackgroundReadableColors readable;
  final AppLocalizations l10n;
  const _Header({
    required this.friend,
    required this.group,
    required this.readable,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final isGroup = group != null;
    final title = isGroup ? group!.name : friend!.username;
    final subtitle = isGroup
        ? l10n.orbit2_group_members(group!.members.length)
        : l10n.orbit2_mock_chat_demo_chip;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 14, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: readable.divider)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 42,
              height: 42,
              child: Icon(
                Icons.chevron_left_rounded,
                color: readable.iconSecondary,
                size: 26,
              ),
            ),
          ),
          if (isGroup)
            Orbit2GroupNode(group: group!, size: 40)
          else
            UserAvatar(peerId: friend!.peerId, size: 38, showGlow: false),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: readable.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11.5, color: readable.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final Orbit2ChatLine line;
  final BackgroundReadableColors readable;
  final bool showSender;
  const _ChatBubble({
    required this.line,
    required this.readable,
    required this.showSender,
  });

  @override
  Widget build(BuildContext context) {
    final isMe = line.isMe;
    final bg = isMe
        ? AppColors.primaryAccent.withValues(alpha: 0.22)
        : (readable.isLightSurface
              ? Colors.white.withValues(alpha: 0.85)
              : Colors.black.withValues(alpha: 0.45));
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(13, 9, 13, 9),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          border: Border.all(color: readable.glassBorder.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showSender && !isMe && line.senderName != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  line.senderName!,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryAccent,
                  ),
                ),
              ),
            Text(
              line.text,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.3,
                color: readable.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              line.timeLabel,
              style: TextStyle(fontSize: 10, color: readable.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _StubComposer extends StatelessWidget {
  final BackgroundReadableColors readable;
  final AppLocalizations l10n;
  const _StubComposer({required this.readable, required this.l10n});

  void _notifyDisabled(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: readable.surfaceRaised,
          duration: const Duration(milliseconds: 1600),
          content: Text(
            l10n.orbit2_mock_chat_send_disabled,
            style: TextStyle(color: readable.textPrimary, fontSize: 13),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: readable.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: readable.inputFill,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: readable.inputBorder),
              ),
              child: Text(
                l10n.orbit2_mock_chat_composer_hint,
                style: TextStyle(fontSize: 14, color: readable.placeholderText),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => _notifyDisabled(context),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [AppColors.primaryAccent, AppColors.secondaryAccent],
                ),
              ),
              child: const Icon(Icons.arrow_upward_rounded,
                  color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}
