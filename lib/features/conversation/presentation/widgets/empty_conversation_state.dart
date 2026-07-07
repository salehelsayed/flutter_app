import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';

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
    final readableColors = context.backgroundReadableColors;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildAvatarWithGlow(readableColors),
                  const SizedBox(height: 16),
                  Text(
                    AppLocalizations.of(context)!.connected_title,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: readableColors.connectedHeading,
                      shadows: [
                        Shadow(
                          color: readableColors.connectedHeading.withValues(
                            alpha: 0.4,
                          ),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.connectionDate,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: readableColors.emptyDate,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildDashedDivider(readableColors),
                  const SizedBox(height: 24),
                  Text(
                    AppLocalizations.of(
                      context,
                    )!.conversation_empty_first_letter,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      color: readableColors.emptyHint,
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

  Widget _buildAvatarWithGlow(BackgroundReadableColors readableColors) {
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
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          readableColors.emptyAvatarGlow.withValues(
                            alpha: 0.08,
                          ),
                          readableColors.emptyAvatarGlow.withValues(
                            alpha: 0.03,
                          ),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.4, 0.7],
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
              boxShadow: [
                BoxShadow(
                  color: readableColors.emptyAvatarGlow.withValues(alpha: 0.3),
                  blurRadius: 30,
                ),
                const BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, 0.4),
                  blurRadius: 40,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: UserAvatar(peerId: widget.contactPeerId, size: 80),
          ),
        ],
      ),
    );
  }

  Widget _buildDashedDivider(BackgroundReadableColors readableColors) {
    return FractionallySizedBox(
      widthFactor: 0.6,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final dashWidth = 6.0;
          final dashSpace = 4.0;
          final dashCount = (constraints.maxWidth / (dashWidth + dashSpace))
              .floor();

          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(dashCount, (_) {
              return Container(
                width: dashWidth,
                height: 1,
                margin: EdgeInsets.only(right: dashSpace),
                color: readableColors.emptyDivider,
              );
            }),
          );
        },
      ),
    );
  }
}
