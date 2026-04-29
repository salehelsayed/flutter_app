import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/theme/feed_colors.dart';

/// Animated hint showing remaining unread messages below the visible preview.
///
/// Purple accent text with bouncing chevron icon, 2s infinite cycle.
/// Hidden when [count] is 0.
class MoreMessagesHint extends StatefulWidget {
  final int count;

  const MoreMessagesHint({super.key, required this.count});

  @override
  State<MoreMessagesHint> createState() => _MoreMessagesHintState();
}

class _MoreMessagesHintState extends State<MoreMessagesHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _bounce;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _bounce = Tween<double>(begin: 0, end: 4).animate(
      CurvedAnimation(parent: _controller, curve: const _BounceCurve()),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.count <= 0) return const SizedBox.shrink();

    final readableColors = context.backgroundReadableColors;
    final isLightSurface = readableColors.isLightSurface;
    final textColor = isLightSurface
        ? const Color(0xFF6D45C9)
        : FeedColors.moreMessagesHint;
    final iconColor = isLightSurface
        ? const Color(0xFF6D45C9).withValues(alpha: 0.72)
        : FeedColors.chevronColor;
    final label = widget.count == 1
        ? '1 more message'
        : '${widget.count} more messages';

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          const SizedBox(width: 4),
          AnimatedBuilder(
            animation: _bounce,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, _bounce.value),
                child: child,
              );
            },
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: iconColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sine-wave bounce: 0 → 1 → 0 over the animation range.
class _BounceCurve extends Curve {
  const _BounceCurve();

  @override
  double transformInternal(double t) {
    // Full sine cycle: 0 → 1 → 0 → -1 → 0
    // We want: 0 → 1 → 0 (half sine)
    return (1 - (2 * t - 1).abs()).clamp(0.0, 1.0);
  }
}
