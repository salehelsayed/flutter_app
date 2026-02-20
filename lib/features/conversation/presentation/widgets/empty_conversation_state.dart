import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_app/features/home/presentation/widgets/ring_avatar.dart';

/// Empty state shown when a conversation has no messages yet.
///
/// Displays the contact's avatar with a breathing glow,
/// "Connected!" label, date, dashed divider, and writing prompt.
class EmptyConversationState extends StatefulWidget {
  final String contactPeerId;
  final String connectionDate;

  const EmptyConversationState({
    super.key,
    required this.contactPeerId,
    required this.connectionDate,
  });

  @override
  State<EmptyConversationState> createState() => _EmptyConversationStateState();
}

class _EmptyConversationStateState extends State<EmptyConversationState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildAvatarWithGlow(),
                  const SizedBox(height: 16),
                  const Text(
                    'Connected!',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1DB954),
                      shadows: [
                        Shadow(
                          color: Color.fromRGBO(29, 185, 84, 0.4),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.connectionDate,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: Color.fromRGBO(255, 255, 255, 0.35),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildDashedDivider(),
                  const SizedBox(height: 24),
                  const Text(
                    'Write the first letter\nto start your conversation',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      color: Color.fromRGBO(255, 255, 255, 0.5),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarWithGlow() {
    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Breathing ambient glow
          AnimatedBuilder(
            animation: _glowController,
            builder: (context, child) {
              final t = _glowController.value;
              final scale = 1.0 + 0.15 * math.sin(t * 2 * math.pi);
              final opacity = 0.6 + 0.4 * math.sin(t * 2 * math.pi);

              return Transform.scale(
                scale: scale,
                child: Opacity(
                  opacity: opacity,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Color.fromRGBO(78, 205, 196, 0.08),
                          Color.fromRGBO(78, 205, 196, 0.03),
                          Colors.transparent,
                        ],
                        stops: [0.0, 0.4, 0.7],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          // Avatar
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(
                  color: Color.fromRGBO(78, 205, 196, 0.3),
                  blurRadius: 30,
                ),
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, 0.4),
                  blurRadius: 40,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: RingAvatar(peerId: widget.contactPeerId, size: 80),
          ),
        ],
      ),
    );
  }

  Widget _buildDashedDivider() {
    return FractionallySizedBox(
      widthFactor: 0.6,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final dashWidth = 6.0;
          final dashSpace = 4.0;
          final dashCount = (constraints.maxWidth / (dashWidth + dashSpace)).floor();

          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(dashCount, (_) {
              return Container(
                width: dashWidth,
                height: 1,
                margin: EdgeInsets.only(right: dashSpace),
                color: const Color.fromRGBO(255, 255, 255, 0.12),
              );
            }),
          );
        },
      ),
    );
  }
}
