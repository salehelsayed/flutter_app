import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';

/// Individual message bubble within an expanded thread card.
///
/// Supports bidirectional display:
/// - Received (isIncoming=true): full width, glass bg, normal brightness
/// - Sent (isIncoming=false): 24px left margin, teal right accent, dimmer text
/// Unread received messages get warm/orange border tint with subtle glow.
class MessageBubble extends StatelessWidget {
  final String text;
  final String time;
  final bool isUnread;
  final bool isIncoming;
  final String? status;
  final String? senderLabel;
  final String? quotedText;
  final bool isQuoteUnavailable;

  const MessageBubble({
    super.key,
    required this.text,
    required this.time,
    this.isUnread = false,
    this.isIncoming = true,
    this.status,
    this.senderLabel,
    this.quotedText,
    this.isQuoteUnavailable = false,
  });

  @override
  Widget build(BuildContext context) {
    final isSent = !isIncoming;

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(left: isSent ? 24 : 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            // Main content with uniform border
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: _backgroundColor,
                border: Border.all(color: _borderColor),
                boxShadow: isUnread && isIncoming
                    ? [
                        BoxShadow(
                          color: AppColors.warmOrange.withValues(alpha: 0.06),
                          blurRadius: 8,
                          spreadRadius: 0,
                        ),
                      ]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (quotedText != null || isQuoteUnavailable)
                    _buildQuoteBar(),
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: Color.fromRGBO(
                        255,
                        255,
                        255,
                        isSent ? 0.70 : 0.88,
                      ),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _buildTimestamp(),
                  ),
                ],
              ),
            ),
            // Teal right accent for sent messages
            if (isSent)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 2,
                  decoration: BoxDecoration(
                    color: AppColors.tealAccent.withValues(alpha: 0.30),
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(14),
                      bottomRight: Radius.circular(14),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color get _backgroundColor {
    if (!isIncoming) {
      return const Color.fromRGBO(255, 255, 255, 0.03);
    }
    return isUnread
        ? const Color.fromRGBO(255, 255, 255, 0.07)
        : const Color.fromRGBO(255, 255, 255, 0.04);
  }

  Color get _borderColor {
    if (!isIncoming) {
      return const Color.fromRGBO(255, 255, 255, 0.06);
    }
    if (isUnread) {
      return AppColors.warmBorderTint;
    }
    return const Color.fromRGBO(255, 255, 255, 0.06);
  }

  Widget _buildQuoteBar() {
    final displayText = isQuoteUnavailable ? 'Message unavailable' : quotedText!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 2,
            height: 16,
            decoration: BoxDecoration(
              color: const Color.fromRGBO(255, 255, 255, 0.15),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              displayText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                fontStyle: isQuoteUnavailable ? FontStyle.italic : FontStyle.normal,
                color: Color.fromRGBO(
                  255,
                  255,
                  255,
                  isQuoteUnavailable ? 0.20 : 0.30,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimestamp() {
    if (!isIncoming) {
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: 'You',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.tealAccent.withValues(alpha: 0.50),
              ),
            ),
            const TextSpan(
              text: ' \u00B7 ',
              style: TextStyle(
                fontSize: 11,
                color: Color.fromRGBO(255, 255, 255, 0.25),
              ),
            ),
            TextSpan(
              text: time,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: Color.fromRGBO(255, 255, 255, 0.25),
              ),
            ),
          ],
        ),
      );
    }

    return Text(
      time,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: Color.fromRGBO(255, 255, 255, 0.35),
      ),
    );
  }
}
