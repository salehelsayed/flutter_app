import 'package:flutter/material.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';

/// Compact version of the connection origin marker.
///
/// Shown at the top of the conversation after the first message is sent.
/// Smaller than the empty state: 48px avatar, 15px "Connected!", 12px date.
class CompactOriginMarker extends StatelessWidget {
  final String contactPeerId;
  final String connectionDate;

  const CompactOriginMarker({
    super.key,
    required this.contactPeerId,
    required this.connectionDate,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          UserAvatar(peerId: contactPeerId, size: 48),
          const SizedBox(height: 4),
          const Text(
            'Connected!',
            style: TextStyle(
              fontSize: 15,
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
            connectionDate,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: Color.fromRGBO(255, 255, 255, 0.35),
            ),
          ),
        ],
      ),
    );
  }
}
