import 'dart:ui';
import 'package:flutter/material.dart';

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
    final barContent = ScaleTransition(
      scale: _scaleAnimation,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(18, 20, 28, 0.95),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: const Color.fromRGBO(255, 255, 255, 0.10),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...kPresetEmojis.map((emoji) => _emojiButton(emoji)),
                _plusButton(),
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

  Widget _emojiButton(String emoji) {
    final isSelected = widget.currentEmoji == emoji;
    return GestureDetector(
      onTap: () => widget.onReactionSelected(emoji),
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? const Color.fromRGBO(78, 205, 196, 0.20)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 24)),
      ),
    );
  }

  Widget _plusButton() {
    return GestureDetector(
      onTap: widget.onPlusTap,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color.fromRGBO(255, 255, 255, 0.06),
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Icon(
          Icons.add,
          size: 20,
          color: Color.fromRGBO(255, 255, 255, 0.5),
        ),
      ),
    );
  }
}
