import 'package:flutter/material.dart';

/// Individual message bubble within an expanded thread card.
///
/// Shows message text with a right-aligned timestamp. Unread messages
/// have a brighter background and teal-tinted border.
class MessageBubble extends StatelessWidget {
  final String text;
  final String time;
  final bool isUnread;

  const MessageBubble({
    super.key,
    required this.text,
    required this.time,
    this.isUnread = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: isUnread
            ? const Color.fromRGBO(255, 255, 255, 0.07)
            : const Color.fromRGBO(255, 255, 255, 0.04),
        border: Border.all(
          color: isUnread
              ? const Color.fromRGBO(78, 205, 196, 0.2)
              : const Color.fromRGBO(255, 255, 255, 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: Color.fromRGBO(255, 255, 255, 0.88),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              time,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: Color.fromRGBO(255, 255, 255, 0.35),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
