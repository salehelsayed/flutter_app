import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_app/features/home/presentation/widgets/ring_avatar.dart';

/// A glassmorphic feed card showing an incoming message from a contact.
///
/// Displays avatar, sender name, time, message text, and a reply button.
class MessageFeedCard extends StatefulWidget {
  final String contactPeerId;
  final String contactUsername;
  final String messageText;
  final String messageTime;
  final VoidCallback? onReply;
  final VoidCallback? onTap;

  const MessageFeedCard({
    super.key,
    required this.contactPeerId,
    required this.contactUsername,
    required this.messageText,
    required this.messageTime,
    this.onReply,
    this.onTap,
  });

  @override
  State<MessageFeedCard> createState() => _MessageFeedCardState();
}

class _MessageFeedCardState extends State<MessageFeedCard>
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
      duration: const Duration(milliseconds: 600),
    );

    final curve = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    );

    _opacity = Tween<double>(begin: 0, end: 1).animate(curve);
    _translateY = Tween<double>(begin: 30, end: 0).animate(curve);
    _scale = Tween<double>(begin: 0.95, end: 1).animate(curve);

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
    return GestureDetector(
      onTap: widget.onTap ?? widget.onReply,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              color: const Color.fromRGBO(255, 255, 255, 0.08),
              border: Border.all(
                color: const Color.fromRGBO(255, 255, 255, 0.12),
              ),
            ),
            child: Stack(
              children: [
                // Card glow
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 200,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: 0.15,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment(-0.5, -0.5),
                            end: Alignment(0.5, 0.5),
                            colors: [
                              Color(0xFFa8edea),
                              Color(0xFFfed6e3),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Content
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Friend indicator
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                      child: Row(
                        children: [
                          RingAvatar(
                            peerId: widget.contactPeerId,
                            size: 42,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.contactUsername,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Color.fromRGBO(255, 255, 255, 0.95),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.messageTime,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                    color: Color.fromRGBO(255, 255, 255, 0.4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Message text
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      child: Text(
                        widget.messageText,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          color: Color.fromRGBO(255, 255, 255, 0.95),
                          height: 1.6,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    // Footer with reply button
                    Container(
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: Color.fromRGBO(255, 255, 255, 0.08),
                          ),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          GestureDetector(
                            onTap: widget.onReply,
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: const Color.fromRGBO(
                                  255, 255, 255, 0.08,
                                ),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    size: 18,
                                    color: Color.fromRGBO(255, 255, 255, 0.6),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Reply',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Color.fromRGBO(
                                        255, 255, 255, 0.6,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
