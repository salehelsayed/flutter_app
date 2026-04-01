import 'package:flutter/material.dart';
import 'swipe_action_buttons.dart';

/// Swipeable wrapper for friend rows with slide-to-reveal action buttons.
///
/// Left-swipe reveals action buttons behind the card content:
/// - Active tab: buttons for the callbacks that are actually provided
/// - Archived tab: "Unarchive" pill button (180px action area)
///
/// Uses a [ValueNotifier] to ensure only one row is open at a time.
class SwipeableFriendRow extends StatefulWidget {
  final Widget child;
  final bool isArchived;
  final bool isBlocked;
  final VoidCallback? onArchive;
  final VoidCallback? onUnarchive;
  final VoidCallback? onBlock;
  final VoidCallback? onUnblock;
  final VoidCallback? onDelete;
  final ValueNotifier<Key?> openRowNotifier;

  const SwipeableFriendRow({
    super.key,
    required this.child,
    required this.isArchived,
    required this.openRowNotifier,
    this.isBlocked = false,
    this.onArchive,
    this.onUnarchive,
    this.onBlock,
    this.onUnblock,
    this.onDelete,
  });

  @override
  State<SwipeableFriendRow> createState() => _SwipeableFriendRowState();
}

class _SwipeableFriendRowState extends State<SwipeableFriendRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slideController;
  double _dragStartX = 0;
  bool _isDragging = false;
  bool _isHorizontalDrag = false;
  bool _directionLocked = false;
  bool _isCollapsing = false;

  // Active with block: 3 buttons (48×3) + gaps (8×2) + padding (8×2) = 176 → 180
  // Active without block: 2 buttons (48×2) + gap (8×1) + padding (8×2) = 128 → 130
  // Delete-only: 1 button (48) + padding = ~80
  // Archived: Unarchive pill (~170) + padding
  bool get _hasBlockAction =>
      widget.onBlock != null || widget.onUnblock != null;
  bool get _hasDeleteAction => widget.onDelete != null;
  bool get _hasArchiveAction => widget.onArchive != null;
  int get _actionCount =>
      (_hasBlockAction ? 1 : 0) +
      (_hasDeleteAction ? 1 : 0) +
      (_hasArchiveAction ? 1 : 0);
  double get _actionWidth => widget.isArchived
      ? 180.0
      : switch (_actionCount) {
          0 => 0.0,
          1 => 82.0,
          2 => 130.0,
          _ => 180.0,
        };

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

  void _onDragStart(DragStartDetails details) {
    _dragStartX = details.localPosition.dx;
    _isDragging = true;
    _isHorizontalDrag = false;
    _directionLocked = false;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_isDragging || _isCollapsing) return;

    // Lock direction after 8px of movement
    if (!_directionLocked) {
      final dx = (details.localPosition.dx - _dragStartX).abs();
      final dy = details.delta.dy.abs();
      if (dx > 8 || dy > 8) {
        _directionLocked = true;
        _isHorizontalDrag = dx > dy;
      }
      return;
    }

    if (!_isHorizontalDrag) return;

    final delta = details.delta.dx;
    final currentPixels = _slideController.value * _actionWidth;
    var newPixels = currentPixels - delta; // Negate: left swipe = positive

    // Rubber band beyond action width
    if (newPixels > _actionWidth) {
      final excess = newPixels - _actionWidth;
      newPixels = _actionWidth + excess * 0.3;
    }

    // Clamp to [0, actionWidth + rubberBand]
    newPixels = newPixels.clamp(0.0, _actionWidth * 1.5);
    _slideController.value = newPixels / _actionWidth;

    // Notify that this row is being interacted with
    if (_slideController.value > 0) {
      widget.openRowNotifier.value = widget.key;
    }
  }

  void _onDragEnd(DragEndDetails details) {
    _isDragging = false;
    if (!_isHorizontalDrag || _isCollapsing) return;

    final velocity = details.primaryVelocity ?? 0;

    if (velocity < -300 || _slideController.value >= _snapThreshold) {
      // Snap open
      _slideController.animateTo(1.0, curve: _snapCurve);
      widget.openRowNotifier.value = widget.key;
    } else {
      // Snap closed
      _slideController.animateTo(0, curve: _snapCurve);
    }
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

  @override
  Widget build(BuildContext context) {
    if (!widget.isArchived && _actionCount == 0) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _slideController,
      builder: (context, child) {
        final t = _slideController.value.clamp(0.0, 1.5);
        final offset = t * _actionWidth;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Action buttons behind — right-aligned
            if (t > 0)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: _buildActionButtons(t),
              ),

            // Card content — slides left
            Transform.translate(
              offset: Offset(-offset, 0),
              child: GestureDetector(
                onHorizontalDragStart: _onDragStart,
                onHorizontalDragUpdate: _onDragUpdate,
                onHorizontalDragEnd: _onDragEnd,
                child: widget.child,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActionButtons(double t) {
    // Parallax: buttons slide in from right at 60% of the card's speed
    final buttonOffset = (1 - t) * _actionWidth * 0.6;
    final buttons = <Widget>[];

    void addButton(Widget button) {
      if (buttons.isNotEmpty) {
        buttons.add(const SizedBox(width: 8));
      }
      buttons.add(button);
    }

    if (_hasBlockAction) {
      addButton(
        widget.isBlocked
            ? UnblockActionButton(onTap: _handleUnblock)
            : BlockActionButton(onTap: _handleBlock),
      );
    }
    if (_hasDeleteAction) {
      addButton(DeleteActionButton(onTap: _handleDelete));
    }
    if (_hasArchiveAction) {
      addButton(ArchiveActionButton(onTap: _handleArchive));
    }

    return Transform.translate(
      offset: Offset(buttonOffset, 0),
      child: Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: widget.isArchived
            ? SizedBox(
                width: _actionWidth,
                child: Center(
                  child: UnarchiveActionButton(onTap: _handleUnarchive),
                ),
              )
            : SizedBox(
                width: _actionWidth,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: buttons,
                ),
              ),
      ),
    );
  }
}
