import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/feed_colors.dart';
import 'package:flutter_app/core/utils/ring_avatar_generator.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';

/// A feed card representing a successful new connection.
class ConnectionCard extends StatefulWidget {
  final String contactPeerId;
  final String contactUsername;
  final String? contactAvatarPath;
  final VoidCallback? onSendMessage;
  final bool isBlocked;
  final String? introducedBy;

  const ConnectionCard({
    super.key,
    required this.contactPeerId,
    required this.contactUsername,
    this.contactAvatarPath,
    this.onSendMessage,
    this.isBlocked = false,
    this.introducedBy,
  });

  @override
  State<ConnectionCard> createState() => _ConnectionCardState();
}

class _ConnectionCardState extends State<ConnectionCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryController;
  late final Animation<double> _opacity;
  late final Animation<double> _translateY;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 540),
    );

    final curve = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    );

    _opacity = Tween<double>(begin: 0, end: 1).animate(curve);
    _translateY = Tween<double>(begin: 22, end: 0).animate(curve);
    _scale = Tween<double>(begin: 0.98, end: 1).animate(curve);

    _entryController.forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _entryController,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: Transform.translate(
            offset: Offset(0, _translateY.value),
            child: Transform.scale(scale: _scale.value, child: child),
          ),
        );
      },
      child: _buildCard(),
    );
  }

  Widget _buildCard() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 360.0;
        final height = clampDouble(width / 1.14, 300, 345);

        return SizedBox(
          height: height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(34),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(34),
                  color: FeedColors.cardBg,
                  border: Border.all(color: FeedColors.cardBorder),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Builder(
                          builder: (context) {
                            final bgGlow = RingAvatarGenerator
                                .glowColorForPeerId(widget.contactPeerId);
                            return DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: RadialGradient(
                                  center: const Alignment(0, -0.15),
                                  radius: 0.96,
                                  colors: [
                                    bgGlow.withValues(alpha: 0.12),
                                    bgGlow.withValues(alpha: 0.05),
                                    Colors.transparent,
                                  ],
                                  stops: const [0.0, 0.46, 1.0],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 22, 22, 2),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = constraints.maxWidth < 340;
                          final avatarSize = compact ? 88.0 : 98.0;
                          final contactNameSize = compact ? 20.0 : 22.0;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'Connected!',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: const Color(0xFF39D65F),
                                  fontSize: compact ? 28 : 32,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.3,
                                  shadows: const [
                                    Shadow(
                                      color: Color(0xA0103A1E),
                                      offset: Offset(0, 2),
                                      blurRadius: 2,
                                    ),
                                    Shadow(
                                      color: Color(0x6B2BE658),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: compact ? 18 : 22),
                              _buildAvatarSection(avatarSize),
                              SizedBox(height: compact ? 10 : 14),
                              _buildContactNameRow(
                                compact: compact,
                                contactNameSize: contactNameSize,
                              ),
                              if (widget.introducedBy != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Introduced by ${widget.introducedBy}',
                                  style: TextStyle(
                                    fontSize: compact ? 12 : 13,
                                    color: const Color(0x99FFFFFF),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                              SizedBox(height: compact ? 12 : 16),
                              _buildSendMessageButton(compact),
                            ],
                          );
                        },
                      ),
                    ),
                    if (widget.isBlocked)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(34),
                            color: const Color.fromRGBO(0, 0, 0, 0.45),
                          ),
                          child: const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.block,
                                  size: 28,
                                  color: Color.fromRGBO(255, 255, 255, 0.60),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Blocked',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color.fromRGBO(255, 255, 255, 0.60),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAvatarSection(double avatarSize) {
    final outerSize = avatarSize + 32;
    final glowColor =
        RingAvatarGenerator.glowColorForPeerId(widget.contactPeerId);

    return SizedBox(
      width: outerSize,
      height: outerSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: outerSize,
            height: outerSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  glowColor.withValues(alpha: 0.30),
                  glowColor.withValues(alpha: 0.15),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.50, 1.0],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color.fromRGBO(11, 13, 17, 0.78),
              border: Border.all(
                color: glowColor.withValues(alpha: 0.7),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: glowColor.withValues(alpha: 0.6),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: UserAvatar(peerId: widget.contactPeerId, size: avatarSize),
          ),
        ],
      ),
    );
  }

  Widget _buildContactNameRow({
    required bool compact,
    required double contactNameSize,
  }) {
    final badgeSize = compact ? 23.0 : 25.0;
    final iconSize = compact ? 14.0 : 16.0;

    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: compact ? 230 : 270),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: badgeSize,
              height: badgeSize,
              decoration: const BoxDecoration(
                color: Color(0xFF49C462),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x703FC75F),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Icon(
                Icons.check_rounded,
                size: iconSize,
                color: const Color.fromRGBO(10, 34, 18, 0.95),
              ),
            ),
            SizedBox(width: compact ? 8 : 10),
            Flexible(
              child: Text(
                widget.contactUsername,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: contactNameSize,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.3,
                  shadows: const [
                    Shadow(color: Color(0x77000000), blurRadius: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSendMessageButton(bool compact) {
    return SizedBox(
      width: compact ? 182 : 198,
      height: 42,
      child: ElevatedButton(
        onPressed: widget.isBlocked ? null : widget.onSendMessage,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color.fromRGBO(29, 185, 84, 0.15),
          foregroundColor: const Color(0xFF62D984),
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          side: BorderSide(
            color: const Color(0xFF2DB65F).withValues(alpha: 0.38),
          ),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 18),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.chat_bubble_outline_rounded, size: 18),
              SizedBox(width: 8),
              Text(
                'Send Message',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
