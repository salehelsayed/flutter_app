import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
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
  final bool showReactionBar;
  final bool showReplyAction;
  final bool showEditAction;
  final bool showCopyAction;
  final bool showDeleteAction;
  final VoidCallback onDismiss;
  final void Function(String emoji)? onReactionSelected;
  final VoidCallback? onPlusTap;
  final VoidCallback? onReplyTap;
  final VoidCallback? onEditTap;
  final VoidCallback? onCopyTap;
  final VoidCallback? onDeleteTap;

  const MessageContextOverlay({
    super.key,
    required this.anchorRect,
    this.selectedMessage,
    this.currentEmoji,
    this.showReactionBar = true,
    this.showReplyAction = true,
    this.showEditAction = false,
    this.showCopyAction = false,
    this.showDeleteAction = false,
    required this.onDismiss,
    this.onReactionSelected,
    this.onPlusTap,
    this.onReplyTap,
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
    final readableColors = context.backgroundReadableColors;
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final topPadding = mediaQuery.viewPadding.top + 8;
    final bottomPadding = mediaQuery.viewPadding.bottom + 8;
    final actionCount =
        (widget.showReplyAction ? 1 : 0) +
        (widget.showEditAction ? 1 : 0) +
        (widget.showCopyAction ? 1 : 0) +
        (widget.showDeleteAction ? 1 : 0);
    final hasMenu = actionCount > 0;
    final menuHeight = hasMenu
        ? actionCount * MessageContextOverlay._menuActionHeight
        : 0.0;
    final reactionBlockHeight = widget.showReactionBar
        ? MessageContextOverlay._reactionBarHeight +
              MessageContextOverlay._verticalGap
        : 0.0;
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
    final minSelectedMessageTop = topPadding + reactionBlockHeight;
    final maxSelectedMessageTop =
        size.height -
        bottomPadding -
        (hasMenu ? menuHeight + MessageContextOverlay._verticalGap : 0.0) -
        selectedMessageHeight;
    final selectedMessageTop = widget.selectedMessage != null
        ? _clampToViewport(
            widget.anchorRect.top,
            min: minSelectedMessageTop,
            max: maxSelectedMessageTop,
          )
        : null;
    final reactionBarTop = widget.showReactionBar
        ? (selectedMessageTop != null
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
                ))
        : null;
    final menuTop = hasMenu
        ? (selectedMessageTop != null
              ? selectedMessageTop +
                    selectedMessageHeight +
                    MessageContextOverlay._verticalGap
              : _clampToViewport(
                  widget.anchorRect.bottom + MessageContextOverlay._verticalGap,
                  min:
                      (reactionBarTop != null
                          ? reactionBarTop +
                                MessageContextOverlay._reactionBarHeight +
                                MessageContextOverlay._verticalGap
                          : topPadding),
                  max: size.height - menuHeight - bottomPadding,
                ))
        : null;

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
                  child: Container(
                    color: readableColors.overlayScrim.withValues(alpha: 0.24),
                  ),
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
          if (reactionBarTop != null &&
              widget.onReactionSelected != null &&
              widget.onPlusTap != null)
            Padding(
              padding: EdgeInsets.only(top: reactionBarTop),
              child: Align(
                alignment: anchorAlignment,
                child: ReactionBar(
                  key: MessageContextOverlay.reactionBarKey,
                  currentEmoji: widget.currentEmoji,
                  inline: true,
                  onReactionSelected: (emoji) =>
                      _handleOnce(() => widget.onReactionSelected!(emoji)),
                  onPlusTap: () => _handleOnce(widget.onPlusTap!),
                  onDismiss: () => _handleOnce(widget.onDismiss),
                ),
              ),
            ),
          if (menuTop != null)
            Padding(
              padding: EdgeInsets.only(top: menuTop),
              child: Align(
                alignment: anchorAlignment,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: _ContextMenuCard(
                    key: MessageContextOverlay.menuKey,
                    showReplyAction: widget.showReplyAction,
                    showEditAction: widget.showEditAction,
                    showCopyAction: widget.showCopyAction,
                    showDeleteAction: widget.showDeleteAction,
                    onReplyTap: widget.onReplyTap != null
                        ? () => _handleOnce(widget.onReplyTap!)
                        : null,
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
  final bool showReplyAction;
  final bool showEditAction;
  final bool showCopyAction;
  final bool showDeleteAction;
  final VoidCallback? onReplyTap;
  final VoidCallback? onEditTap;
  final VoidCallback? onCopyTap;
  final VoidCallback? onDeleteTap;

  const _ContextMenuCard({
    super.key,
    required this.showReplyAction,
    required this.showEditAction,
    required this.showCopyAction,
    required this.showDeleteAction,
    this.onReplyTap,
    this.onEditTap,
    this.onCopyTap,
    this.onDeleteTap,
  });

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final danger = readableColors.isLightSurface
        ? const Color(0xFF9D1C12)
        : const Color(0xFFFF8A80);
    final l10n = AppLocalizations.of(context)!;
    final actions = <Widget>[
      if (showReplyAction)
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
          color: danger,
        ),
    ];
    final children = <Widget>[];
    for (var i = 0; i < actions.length; i++) {
      if (i > 0) {
        children.add(
          Divider(
            height: 1,
            thickness: 1,
            color: readableColors.divider,
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
            color: readableColors.glassSurface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: readableColors.glassBorder),
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
  final Color? color;

  const _ContextMenuAction({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final actionColor = color ?? context.backgroundReadableColors.textSecondary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: actionColor),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: actionColor,
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
