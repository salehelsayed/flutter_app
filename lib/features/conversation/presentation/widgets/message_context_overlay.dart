import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/reaction_bar.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

class MessageContextOverlay extends StatelessWidget {
  static const overlayKey = ValueKey('message-context-overlay');
  static const backdropKey = ValueKey('message-context-backdrop');
  static const reactionBarKey = ValueKey('message-context-reaction-bar');
  static const selectedMessageKey = ValueKey(
    'message-context-selected-message',
  );
  static const menuKey = ValueKey('message-context-menu');
  static const replyActionKey = ValueKey('message-context-reply-action');
  static const editActionKey = ValueKey('message-context-edit-action');
  static const copyActionKey = ValueKey('message-context-copy-action');
  static const deleteActionKey = ValueKey('message-context-delete-action');

  static const _reactionBarHeight = 60.0;
  static const _menuActionHeight = 58.0;
  static const _verticalGap = 12.0;

  final Rect anchorRect;
  final Widget? selectedMessage;
  final String? currentEmoji;
  final bool showEditAction;
  final bool showCopyAction;
  final bool showDeleteAction;
  final VoidCallback onDismiss;
  final void Function(String emoji) onReactionSelected;
  final VoidCallback onPlusTap;
  final VoidCallback onReplyTap;
  final VoidCallback? onEditTap;
  final VoidCallback? onCopyTap;
  final VoidCallback? onDeleteTap;

  const MessageContextOverlay({
    super.key,
    required this.anchorRect,
    this.selectedMessage,
    this.currentEmoji,
    this.showEditAction = false,
    this.showCopyAction = false,
    this.showDeleteAction = false,
    required this.onDismiss,
    required this.onReactionSelected,
    required this.onPlusTap,
    required this.onReplyTap,
    this.onEditTap,
    this.onCopyTap,
    this.onDeleteTap,
  });

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final topPadding = mediaQuery.viewPadding.top + 8;
    final bottomPadding = mediaQuery.viewPadding.bottom + 8;
    final actionCount =
        1 +
        (showEditAction ? 1 : 0) +
        (showCopyAction ? 1 : 0) +
        (showDeleteAction ? 1 : 0);
    final menuHeight = actionCount * _menuActionHeight;
    final selectedMessageWidth = anchorRect.width > 0
        ? anchorRect.width
        : size.width - 32;
    final selectedMessageHeight = anchorRect.height > 0
        ? anchorRect.height
        : 120.0;
    final anchorAlignment = Alignment(
      ((anchorRect.center.dx / size.width) * 2 - 1).clamp(-1.0, 1.0),
      -1,
    );
    final minSelectedMessageTop =
        topPadding + _reactionBarHeight + _verticalGap;
    final maxSelectedMessageTop =
        size.height -
        bottomPadding -
        menuHeight -
        _verticalGap -
        selectedMessageHeight;
    final selectedMessageTop = selectedMessage != null
        ? _clampToViewport(
            anchorRect.top,
            min: minSelectedMessageTop,
            max: maxSelectedMessageTop,
          )
        : null;
    final reactionBarTop = selectedMessageTop != null
        ? selectedMessageTop - _reactionBarHeight - _verticalGap
        : _clampToViewport(
            anchorRect.top - _reactionBarHeight - _verticalGap,
            min: topPadding,
            max: size.height - _reactionBarHeight - bottomPadding,
          );
    final menuTop = selectedMessageTop != null
        ? selectedMessageTop + selectedMessageHeight + _verticalGap
        : _clampToViewport(
            anchorRect.bottom + _verticalGap,
            min: reactionBarTop + _reactionBarHeight + _verticalGap,
            max: size.height - menuHeight - bottomPadding,
          );

    return Material(
      key: overlayKey,
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              key: backdropKey,
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(color: const Color.fromRGBO(6, 8, 12, 0.24)),
                ),
              ),
            ),
          ),
          if (selectedMessageTop != null && selectedMessage != null)
            Padding(
              padding: EdgeInsets.only(top: selectedMessageTop),
              child: Align(
                alignment: anchorAlignment,
                child: SizedBox(
                  width: selectedMessageWidth,
                  height: selectedMessageHeight,
                  child: KeyedSubtree(
                    key: selectedMessageKey,
                    child: ClipRect(
                      child: IgnorePointer(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            width: selectedMessageWidth,
                            child: selectedMessage!,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.only(top: reactionBarTop),
            child: Align(
              alignment: anchorAlignment,
              child: ReactionBar(
                key: reactionBarKey,
                currentEmoji: currentEmoji,
                inline: true,
                onReactionSelected: onReactionSelected,
                onPlusTap: onPlusTap,
                onDismiss: onDismiss,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: menuTop),
            child: Align(
              alignment: anchorAlignment,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: _ContextMenuCard(
                  key: menuKey,
                  showEditAction: showEditAction,
                  showCopyAction: showCopyAction,
                  showDeleteAction: showDeleteAction,
                  onReplyTap: onReplyTap,
                  onEditTap: onEditTap,
                  onCopyTap: onCopyTap,
                  onDeleteTap: onDeleteTap,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _clampToViewport(
    double value, {
    required double min,
    required double max,
  }) {
    if (max < min) return min;
    return value.clamp(min, max).toDouble();
  }
}

class _ContextMenuCard extends StatelessWidget {
  final bool showEditAction;
  final bool showCopyAction;
  final bool showDeleteAction;
  final VoidCallback onReplyTap;
  final VoidCallback? onEditTap;
  final VoidCallback? onCopyTap;
  final VoidCallback? onDeleteTap;

  const _ContextMenuCard({
    super.key,
    required this.showEditAction,
    required this.showCopyAction,
    required this.showDeleteAction,
    required this.onReplyTap,
    this.onEditTap,
    this.onCopyTap,
    this.onDeleteTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final actions = <Widget>[
      _ContextMenuAction(
        key: MessageContextOverlay.replyActionKey,
        icon: Icons.reply_rounded,
        label: l10n.conversation_context_reply,
        onTap: onReplyTap,
      ),
      if (showEditAction)
        _ContextMenuAction(
          key: MessageContextOverlay.editActionKey,
          icon: Icons.edit_rounded,
          label: l10n.conversation_context_edit,
          onTap: onEditTap,
        ),
      if (showCopyAction)
        _ContextMenuAction(
          key: MessageContextOverlay.copyActionKey,
          icon: Icons.copy_rounded,
          label: l10n.conversation_context_copy,
          onTap: onCopyTap,
        ),
      if (showDeleteAction)
        _ContextMenuAction(
          key: MessageContextOverlay.deleteActionKey,
          icon: Icons.delete_outline_rounded,
          label: l10n.conversation_context_delete,
          onTap: onDeleteTap,
          color: const Color(0xFFFF8A80),
        ),
    ];
    final children = <Widget>[];
    for (var i = 0; i < actions.length; i++) {
      if (i > 0) {
        children.add(
          const Divider(
            height: 1,
            thickness: 1,
            color: Color.fromRGBO(255, 255, 255, 0.08),
          ),
        );
      }
      children.add(actions[i]);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: const Color.fromRGBO(18, 20, 28, 0.95),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color.fromRGBO(255, 255, 255, 0.10),
            ),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}

class _ContextMenuAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;

  const _ContextMenuAction({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.color = const Color.fromRGBO(255, 255, 255, 0.78),
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
