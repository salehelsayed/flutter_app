import 'package:flutter/material.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';

/// A positioned avatar on an orbital ring with staggered scale-in animation.
///
/// Uses [SingleTickerProviderStateMixin] for its entrance animation.
class OrbitalAvatar extends StatefulWidget {
  final String peerId;
  final double size;
  final int globalIndex;
  final double borderWidth;
  final Color borderColor;

  const OrbitalAvatar({
    super.key,
    required this.peerId,
    required this.size,
    required this.globalIndex,
    this.borderWidth = 1.5,
    this.borderColor = const Color(0x1FFFFFFF),
  });

  @override
  State<OrbitalAvatar> createState() => _OrbitalAvatarState();
}

class _OrbitalAvatarState extends State<OrbitalAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.ease,
    );

    Future.delayed(
      Duration(milliseconds: widget.globalIndex * 40),
      () {
        if (mounted) _controller.forward();
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Opacity(
            opacity: _scaleAnimation.value,
            child: child,
          ),
        );
      },
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: widget.borderColor,
            width: widget.borderWidth,
          ),
        ),
        child: ClipOval(
          child: UserAvatar(
            peerId: widget.peerId,
            size: widget.size - widget.borderWidth * 2,
          ),
        ),
      ),
    );
  }
}
