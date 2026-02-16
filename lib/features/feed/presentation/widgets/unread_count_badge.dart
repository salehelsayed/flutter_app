import 'package:flutter/material.dart';

/// Animated pill badge showing an unread message count.
///
/// Green (#1DB954) matching the app's online/primary accent.
/// 300ms spring scale-in on appear, 200ms pulse on count change.
/// Counts above 99 are displayed as "99+".
class UnreadCountBadge extends StatefulWidget {
  final int count;

  const UnreadCountBadge({super.key, required this.count});

  @override
  State<UnreadCountBadge> createState() => _UnreadCountBadgeState();
}

class _UnreadCountBadgeState extends State<UnreadCountBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );
    if (widget.count > 0) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(UnreadCountBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count > 0 && oldWidget.count == 0) {
      _controller.forward(from: 0);
    } else if (widget.count == 0 && oldWidget.count > 0) {
      _controller.reverse();
    } else if (widget.count != oldWidget.count && widget.count > 0) {
      // Pulse on count change
      _controller.forward(from: 0.7);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.count <= 0) return const SizedBox.shrink();

    final label = widget.count > 99 ? '99+' : '${widget.count}';

    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        constraints: const BoxConstraints(minWidth: 22),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            colors: [Color(0xFF1DB954), Color(0xFF18A349)],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x661DB954),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}
