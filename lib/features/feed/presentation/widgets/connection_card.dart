import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_app/features/home/presentation/widgets/ring_avatar.dart';

/// A feed card representing a successful new connection.
class ConnectionCard extends StatefulWidget {
  final String contactPeerId;
  final String contactUsername;
  final String? contactAvatarPath;
  final VoidCallback? onSendMessage;

  const ConnectionCard({
    super.key,
    required this.contactPeerId,
    required this.contactUsername,
    this.contactAvatarPath,
    this.onSendMessage,
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
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(34),
                  border: Border.all(
                    color: const Color.fromRGBO(255, 255, 255, 0.14),
                  ),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.fromRGBO(35, 38, 48, 0.82),
                      Color.fromRGBO(21, 24, 30, 0.90),
                      Color.fromRGBO(15, 17, 22, 0.94),
                    ],
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color.fromRGBO(0, 0, 0, 0.5),
                      blurRadius: 30,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: const Alignment(0, -0.15),
                              radius: 0.9,
                              colors: [
                                const Color(0x3023A74B),
                                const Color(0x1223A74B),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.52, 1.0],
                            ),
                          ),
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
                              SizedBox(height: compact ? 12 : 16),
                              _buildSendMessageButton(compact),
                            ],
                          );
                        },
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
    final outerSize = avatarSize + 24;

    return SizedBox(
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
            padding: const EdgeInsets.all(8),
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
            child: RingAvatar(peerId: widget.contactPeerId, size: avatarSize),
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
        onPressed: widget.onSendMessage,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color.fromRGBO(45, 155, 91, 0.26),
          foregroundColor: const Color(0xFF56C672),
          elevation: 0,
          shadowColor: Colors.transparent,
          side: BorderSide(
            color: const Color(0xFF2DB65F).withValues(alpha: 0.55),
          ),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 18),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
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
    );
  }
}
