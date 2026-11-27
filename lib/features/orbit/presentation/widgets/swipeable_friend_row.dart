import 'dart:async';

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_app/l10n/app_localizations.dart';

import 'swipe_action_buttons.dart';

typedef _RowAction = ({String label, VoidCallback onSelect, Widget button});

/// Reveals Orbit row actions by swiping toward the start edge or holding the row.
///
/// Uses a [ValueNotifier] to ensure only one row is open at a time.
class SwipeableFriendRow extends StatefulWidget {
  final Widget? child;

  /// Places swipe actions on a row that owns its own semantics node.
  final Widget Function(Map<CustomSemanticsAction, VoidCallback>)? rowBuilder;
  final bool isArchived;
  final bool isBlocked;
  final VoidCallback? onArchive;
  final VoidCallback? onUnarchive;
  final VoidCallback? onBlock;
  final VoidCallback? onUnblock;
  final VoidCallback? onLeave;
  final VoidCallback? onDelete;
  final ValueNotifier<Key?> openRowNotifier;

  const SwipeableFriendRow({
    super.key,
    this.child,
    this.rowBuilder,
    required this.isArchived,
    required this.openRowNotifier,
    this.isBlocked = false,
    this.onArchive,
    this.onUnarchive,
    this.onBlock,
    this.onUnblock,
    this.onLeave,
    this.onDelete,
  }) : assert((child == null) != (rowBuilder == null)),
       assert(isArchived || onLeave == null || onDelete == null);

  @override
  State<SwipeableFriendRow> createState() => _SwipeableFriendRowState();
}

class _SwipeableFriendRowState extends State<SwipeableFriendRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slideController;
  bool _dragCancelled = false;
  bool _isCollapsing = false;

  static const _actionSpacing = 6.0;
  static const _buttonWidth = 72.0;
  static const _snapThreshold = 0.5; // 50% of action width
  static const _snapCurve = Cubic(0.25, 0.46, 0.45, 0.94);
  static const _snapDuration = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: _snapDuration,
      value: 0,
    );
    _slideController.addListener(_syncOpenRowNotifier);
    widget.openRowNotifier.addListener(_onOpenRowChanged);
  }

  void _onOpenRowChanged() {
    if (widget.openRowNotifier.value != widget.key &&
        _slideController.value > 0) {
      _slideController.animateTo(0, curve: _snapCurve);
    }
  }

  @override
  void dispose() {
    widget.openRowNotifier.removeListener(_onOpenRowChanged);
    _slideController.removeListener(_syncOpenRowNotifier);
    if (widget.openRowNotifier.value == widget.key) {
      widget.openRowNotifier.value = null;
    }
    _slideController.dispose();
    super.dispose();
  }

  void _syncOpenRowNotifier() {
    final isOpen = _slideController.value > 0;
    if (isOpen) {
      if (widget.openRowNotifier.value != widget.key) {
        widget.openRowNotifier.value = widget.key;
      }
      return;
    }

    if (widget.openRowNotifier.value == widget.key) {
      widget.openRowNotifier.value = null;
    }
  }

  void _onDragUpdate(
    DragUpdateDetails details,
    double actionWidth,
    double revealSign,
  ) {
    if (_dragCancelled || _isCollapsing) return;
    _slideController.value += details.delta.dx * revealSign / actionWidth;
  }

  void _onDragEnd(DragEndDetails details, double revealSign) {
    if (_dragCancelled || _isCollapsing) return;

    final revealVelocity = (details.primaryVelocity ?? 0) * revealSign;

    if (revealVelocity > 300 || _slideController.value >= _snapThreshold) {
      // Snap open
      _slideController.animateTo(1.0, curve: _snapCurve);
      widget.openRowNotifier.value = widget.key;
    } else {
      // Snap closed
      _slideController.animateTo(0, curve: _snapCurve);
    }
  }

  void _cancelDrag() {
    _dragCancelled = true;
    if (!_isCollapsing) _slideController.animateTo(0, curve: _snapCurve);
  }

  void _handleArchive() {
    setState(() => _isCollapsing = true);

    // Close the swipe first, then collapse the row
    _slideController.animateTo(0, curve: _snapCurve).then((_) {
      widget.onArchive?.call();
    });
  }

  void _handleUnarchive() {
    setState(() => _isCollapsing = true);
    _slideController.animateTo(0, curve: _snapCurve).then((_) {
      widget.onUnarchive?.call();
    });
  }

  void _handleBlock() {
    // Swipe stays open — confirmation dialog handles the rest
    widget.onBlock?.call();
  }

  void _handleUnblock() {
    // No confirmation needed — close swipe and call callback
    _slideController.animateTo(0, curve: _snapCurve);
    widget.onUnblock?.call();
  }

  void _handleDelete() {
    // Swipe stays open — confirmation dialog handles the rest
    widget.onDelete?.call();
  }

  void _handleLeave() {
    // Swipe stays open — confirmation/recovery owns the next state.
    widget.onLeave?.call();
  }

  List<_RowAction> _actions(AppLocalizations l10n) {
    if (widget.isArchived) {
      return [
        if (widget.onUnarchive != null)
          (
            label: l10n.orbit_unarchive_action,
            onSelect: _handleUnarchive,
            button: UnarchiveActionButton(onTap: _handleUnarchive),
          ),
      ];
    }
    return [
      if (widget.isBlocked && widget.onUnblock != null)
        (
          label: l10n.orbit_unblock_action,
          onSelect: _handleUnblock,
          button: UnblockActionButton(onTap: _handleUnblock),
        )
      else if (!widget.isBlocked && widget.onBlock != null)
        (
          label: l10n.orbit_block_action,
          onSelect: _handleBlock,
          button: BlockActionButton(onTap: _handleBlock),
        ),
      if (widget.onLeave != null)
        (
          label: l10n.orbit_leave_action,
          onSelect: _handleLeave,
          button: LeaveActionButton(onTap: _handleLeave),
        ),
      if (widget.onDelete != null)
        (
          label: l10n.orbit_delete_action,
          onSelect: _handleDelete,
          button: DeleteActionButton(onTap: _handleDelete),
        ),
      if (widget.onArchive != null)
        (
          label: l10n.orbit_archive_action,
          onSelect: _handleArchive,
          button: ArchiveActionButton(onTap: _handleArchive),
        ),
    ];
  }

  Future<void> _showActions(
    List<_RowAction> actions,
    Offset globalPosition,
  ) async {
    final overlay = Navigator.of(context).overlay!;
    final bounds = overlay.context.findRenderObject()! as RenderBox;
    final anchor = bounds.globalToLocal(globalPosition);
    final selected = await showMenu<VoidCallback>(
      context: overlay.context,
      position: RelativeRect.fromSize(
        Rect.fromPoints(anchor, anchor),
        bounds.size,
      ),
      items: [
        for (final action in actions)
          PopupMenuItem(value: action.onSelect, child: Text(action.label)),
      ],
    );
    if (mounted) selected?.call();
  }

  @override
  Widget build(BuildContext context) {
    final actions = _actions(AppLocalizations.of(context)!);
    final customActions = {
      for (final action in actions)
        CustomSemanticsAction(label: action.label): action.onSelect,
    };
    final row = widget.rowBuilder?.call(customActions) ?? widget.child!;
    if (actions.isEmpty) return row;

    final actionWidth = widget.isArchived
        ? 180.0
        : _buttonWidth * actions.length + _actionSpacing * (actions.length - 1);
    final revealSign = Directionality.of(context) == TextDirection.rtl
        ? 1.0
        : -1.0;

    final rowOwnsSemantics = widget.rowBuilder != null;
    return Semantics(
      container: !rowOwnsSemantics,
      customSemanticsActions: rowOwnsSemantics ? null : customActions,
      child: AnimatedBuilder(
        animation: _slideController,
        builder: (context, child) {
          final t = _slideController.value;
          final offset = t * actionWidth * revealSign;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              if (t > 0)
                PositionedDirectional(
                  end: 0,
                  top: 0,
                  bottom: 0,
                  child: Transform.translate(
                    offset: Offset(
                      (1 - t) * actionWidth * -revealSign * 0.6,
                      0,
                    ),
                    child: Opacity(
                      opacity: t,
                      child: SizedBox(
                        width: actionWidth,
                        child: widget.isArchived
                            ? Center(child: actions.single.button)
                            : Row(
                                spacing: _actionSpacing,
                                children: [
                                  for (final action in actions)
                                    Expanded(child: action.button),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              Transform.translate(offset: Offset(offset, 0), child: child),
            ],
          );
        },
        child: Listener(
          // Flutter also ends accepted drags on pointer cancellation.
          onPointerCancel: (_) => _cancelDrag(),
          child: GestureDetector(
            excludeFromSemantics: rowOwnsSemantics,
            dragStartBehavior: DragStartBehavior.down,
            onHorizontalDragStart: (_) => _dragCancelled = false,
            onHorizontalDragUpdate: (details) =>
                _onDragUpdate(details, actionWidth, revealSign),
            onHorizontalDragEnd: (details) => _onDragEnd(details, revealSign),
            onLongPressStart: (details) =>
                unawaited(_showActions(actions, details.globalPosition)),
            child: row,
          ),
        ),
      ),
    );
  }
}
