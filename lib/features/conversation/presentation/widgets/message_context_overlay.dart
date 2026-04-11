import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/reaction_bar.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

class MessageContextOverlay extends StatefulWidget {
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
  State<MessageContextOverlay> createState() => _MessageContextOverlayState();
}

class _MessageContextOverlayState extends State<MessageContextOverlay> {
  bool _handledAction = false;

  void _handleOnce(VoidCallback action) {
    if (_handledAction) return;
    _handledAction = true;
    action();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final topPadding = mediaQuery.viewPadding.top + 8;
    final bottomPadding = mediaQuery.viewPadding.bottom + 8;
    final actionCount =
        1 +
        (widget.showEditAction ? 1 : 0) +
        (widget.showCopyAction ? 1 : 0) +
        (widget.showDeleteAction ? 1 : 0);
    final menuHeight = actionCount * MessageContextOverlay._menuActionHeight;
    final selectedMessageWidth = widget.anchorRect.width > 0
        ? widget.anchorRect.width
        : size.width - 32;
    final selectedMessageHeight = widget.anchorRect.height > 0
        ? widget.anchorRect.height
        : 120.0;
    final anchorAlignment = Alignment(
      ((widget.anchorRect.center.dx / size.width) * 2 - 1).clamp(-1.0, 1.0),
      -1,
    );
    final minSelectedMessageTop =
        topPadding +
        MessageContextOverlay._reactionBarHeight +
        MessageContextOverlay._verticalGap;
    final maxSelectedMessageTop =
        size.height -
        bottomPadding -
        menuHeight -
        MessageContextOverlay._verticalGap -
        selectedMessageHeight;
    final selectedMessageTop = widget.selectedMessage != null
        ? _clampToViewport(
            widget.anchorRect.top,
            min: minSelectedMessageTop,
            max: maxSelectedMessageTop,
          )
        : null;
    final reactionBarTop = selectedMessageTop != null
        ? selectedMessageTop -
              MessageContextOverlay._reactionBarHeight -
              MessageContextOverlay._verticalGap
        : _clampToViewport(
            widget.anchorRect.top -
                MessageContextOverlay._reactionBarHeight -
                MessageContextOverlay._verticalGap,
            min: topPadding,
            max:
                size.height -
                MessageContextOverlay._reactionBarHeight -
                bottomPadding,
          );
    final menuTop = selectedMessageTop != null
        ? selectedMessageTop +
              selectedMessageHeight +
              MessageContextOverlay._verticalGap
        : _clampToViewport(
            widget.anchorRect.bottom + MessageContextOverlay._verticalGap,
            min:
                reactionBarTop +
                MessageContextOverlay._reactionBarHeight +
                MessageContextOverlay._verticalGap,
            max: size.height - menuHeight - bottomPadding,
          );

    return Material(
      key: MessageContextOverlay.overlayKey,
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              key: MessageContextOverlay.backdropKey,
              behavior: HitTestBehavior.opaque,
              onTap: () => _handleOnce(widget.onDismiss),
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(color: const Color.fromRGBO(6, 8, 12, 0.24)),
                ),
              ),
            ),
          ),
          if (selectedMessageTop != null && widget.selectedMessage != null)
            Padding(
              padding: EdgeInsets.only(top: selectedMessageTop),
              child: Align(
                alignment: anchorAlignment,
                child: SizedBox(
                  width: selectedMessageWidth,
                  height: selectedMessageHeight,
                  child: KeyedSubtree(
                    key: MessageContextOverlay.selectedMessageKey,
                    child: ClipRect(
                      child: IgnorePointer(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            width: selectedMessageWidth,
                            child: widget.selectedMessage!,
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
                key: MessageContextOverlay.reactionBarKey,
                currentEmoji: widget.currentEmoji,
                inline: true,
                onReactionSelected: (emoji) =>
                    _handleOnce(() => widget.onReactionSelected(emoji)),
                onPlusTap: () => _handleOnce(widget.onPlusTap),
                onDismiss: () => _handleOnce(widget.onDismiss),
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
                  key: MessageContextOverlay.menuKey,
                  showEditAction: widget.showEditAction,
                  showCopyAction: widget.showCopyAction,
                  showDeleteAction: widget.showDeleteAction,
                  onReplyTap: () => _handleOnce(widget.onReplyTap),
                  onEditTap: widget.onEditTap != null
                      ? () => _handleOnce(widget.onEditTap!)
                      : null,
                  onCopyTap: widget.onCopyTap != null
                      ? () => _handleOnce(widget.onCopyTap!)
                      : null,
                  onDeleteTap: widget.onDeleteTap != null
                      ? () => _handleOnce(widget.onDeleteTap!)
                      : null,
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
