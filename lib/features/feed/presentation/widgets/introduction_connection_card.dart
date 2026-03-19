import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/core/theme/feed_colors.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';

/// A feed card shown when two users connect through an introduction.
///
/// Displays "Introduced by X" with a small introducer avatar at the top,
/// two user avatars side by side with a dashed line, and a
/// "Send Message" button.
class IntroductionConnectionCard extends StatefulWidget {
  final String ownPeerId;
  final String ownUsername;
  final String contactPeerId;
  final String contactUsername;
  final String introducedBy;
  final String? introducedByPeerId;
  final VoidCallback? onSendMessage;
  final bool isBlocked;

  const IntroductionConnectionCard({
    super.key,
    required this.ownPeerId,
    required this.ownUsername,
    required this.contactPeerId,
    required this.contactUsername,
    required this.introducedBy,
    this.introducedByPeerId,
    this.onSendMessage,
    this.isBlocked = false,
  });

  @override
  State<IntroductionConnectionCard> createState() =>
      _IntroductionConnectionCardState();
}

class _IntroductionConnectionCardState
    extends State<IntroductionConnectionCard>
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
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: FeedColors.cardBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 340;

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildIntroducedByRow(compact),
                      SizedBox(height: compact ? 14 : 18),
                      _buildDualAvatarSection(compact),
                      SizedBox(height: compact ? 14 : 18),
                      _buildSendMessageButton(compact),
                    ],
                  );
                },
              ),
            ),
            if (widget.isBlocked) _buildBlockedOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildDualAvatarSection(bool compact) {
    final avatarSize = compact ? 64.0 : 72.0;
    final outerSize = avatarSize + 20;
    final gap = compact ? 28.0 : 36.0;
    final totalWidth = outerSize * 2 + gap;

    return SizedBox(
      width: totalWidth,
      height: outerSize + 22, // extra space for username labels
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Dashed line between avatars
          Positioned(
            left: outerSize / 2,
            right: outerSize / 2,
            top: outerSize / 2,
            child: CustomPaint(
              size: Size(gap, 1),
              painter: _DashedLinePainter(),
            ),
          ),
          // Left avatar (own)
          Positioned(
            left: 0,
            top: 0,
            child: _buildSingleAvatar(
              peerId: widget.ownPeerId,
              username: widget.ownUsername,
              size: avatarSize,
              outerSize: outerSize,
              compact: compact,
            ),
          ),
          // Right avatar (contact)
          Positioned(
            right: 0,
            top: 0,
            child: _buildSingleAvatar(
              peerId: widget.contactPeerId,
              username: widget.contactUsername,
              size: avatarSize,
              outerSize: outerSize,
              compact: compact,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleAvatar({
    required String peerId,
    required String username,
    required double size,
    required double outerSize,
    required bool compact,
  }) {
    return Column(
      children: [
        SizedBox(
          width: outerSize,
          height: outerSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: outerSize,
                height: outerSize,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Color(0x402DB65F),
                      Color(0x1F2DB65F),
                      Colors.transparent,
                    ],
                    stops: [0.0, 0.55, 1.0],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color.fromRGBO(11, 13, 17, 0.78),
                  border: Border.all(
                    color: const Color.fromRGBO(255, 255, 255, 0.15),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color.fromRGBO(0, 0, 0, 0.45),
                      blurRadius: 16,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: UserAvatar(peerId: peerId, size: size),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: outerSize + 8,
          child: Text(
            username,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 13 : 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIntroducedByRow(bool compact) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.introducedByPeerId != null) ...[
          UserAvatar(peerId: widget.introducedByPeerId!, size: 20),
          const SizedBox(width: 6),
        ],
        Text(
          AppLocalizations.of(context)!.introduced_by(widget.introducedBy),
          style: TextStyle(
            fontSize: compact ? 12 : 13,
            color: const Color(0x99FFFFFF),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
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
            children: [
              const Icon(Icons.chat_bubble_outline_rounded, size: 18),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context)!.send_message,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBlockedOverlay() {
    return Positioned.fill(
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
    );
  }
}

/// Paints a horizontal dashed line between the two avatars.
class _DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x661DB954)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    const dashWidth = 6.0;
    const dashGap = 4.0;
    final y = size.height / 2;
    var x = 0.0;

    while (x < size.width) {
      final end = min(x + dashWidth, size.width);
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      x += dashWidth + dashGap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
