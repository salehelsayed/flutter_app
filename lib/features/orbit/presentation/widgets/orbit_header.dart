import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';

/// Right-aligned user avatar header for the Orbit screen.
class OrbitHeader extends StatelessWidget {
  final String? userPeerId;
  final Uint8List? avatarBytes;

  const OrbitHeader({super.key, required this.userPeerId, this.avatarBytes});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16, top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          UserAvatar(
            peerId: userPeerId,
            avatarBytes: avatarBytes,
            size: 44,
          ),
        ],
      ),
    );
  }
}
