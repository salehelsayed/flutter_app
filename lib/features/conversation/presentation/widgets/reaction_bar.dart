import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';

/// Preset emojis for the quick-reaction bar.
const kPresetEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

/// Floating bar with 6 preset emojis + "+" button for full picker.
///
/// Shown on long-press of a message. Uses glassmorphic styling with
/// scale animation (0.8→1.0, 200ms).
class ReactionBar extends StatefulWidget {
  final String? currentEmoji;
  final void Function(String emoji) onReactionSelected;
  final VoidCallback onPlusTap;
  final VoidCallback onDismiss;
  final double? anchorY;
  final bool inline;

  const ReactionBar({
    super.key,
    this.currentEmoji,
    required this.onReactionSelected,
    required this.onPlusTap,
    required this.onDismiss,
    this.anchorY,
    this.inline = false,
  });

  @override
  State<ReactionBar> createState() => _ReactionBarState();
}

class _ReactionBarState extends State<ReactionBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    final barContent = ScaleTransition(
      scale: _scaleAnimation,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: readableColors.glassSurface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: readableColors.glassBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...kPresetEmojis.map((emoji) => _emojiButton(context, emoji)),
                _plusButton(context),
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.inline) {
      return barContent;
    }

    // Bar height ~60px (44 emoji + 8+8 padding). Place it above the card
    // with an 8px gap. Clamp to keep it on-screen.
    const barHeight = 60.0;
    const gap = 8.0;

    final Widget positioned = widget.anchorY != null
        ? Padding(
            padding: EdgeInsets.only(
              top: (widget.anchorY! - barHeight - gap).clamp(
                8.0,
                double.infinity,
              ),
            ),
            child: Align(alignment: Alignment.topCenter, child: barContent),
          )
        : Center(child: barContent);

    return GestureDetector(
      onTap: widget.onDismiss,
      behavior: HitTestBehavior.opaque,
      child: Container(color: Colors.transparent, child: positioned),
    );
  }

  Widget _emojiButton(BuildContext context, String emoji) {
    final readableColors = context.backgroundReadableColors;
    final selectedAccent = readableColors.isLightSurface
        ? const Color(0xFF16756F)
        : const Color(0xFF4ECDC4);
    final isSelected = widget.currentEmoji == emoji;
    return GestureDetector(
      onTap: () => widget.onReactionSelected(emoji),
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? selectedAccent.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 24)),
      ),
    );
  }

  Widget _plusButton(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    return GestureDetector(
      onTap: widget.onPlusTap,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: readableColors.surfaceSubtle,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Icon(
          Icons.add,
          size: 20,
          color: readableColors.iconSecondary,
        ),
      ),
    );
  }
}
