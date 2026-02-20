import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/home/presentation/widgets/editable_username_widget.dart';
import 'package:flutter_app/features/home/presentation/widgets/ring_avatar.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';

/// Feed header showing the handle and user avatar.
class FeedHeader extends StatelessWidget {
  final String username;
  final Uint8List? avatarBytes;
  final String? peerId;
  final ValueChanged<String>? onUsernameChanged;
  final P2PService? p2pService;
  final VoidCallback? onAvatarTap;

  const FeedHeader({
    super.key,
    required this.username,
    this.avatarBytes,
    this.peerId,
    this.onUsernameChanged,
    this.p2pService,
    this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    final displayUsername = username.trim().isEmpty ? 'Username' : username;

    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: EditableUsernameWidget(
              username: displayUsername,
              onUsernameChanged: onUsernameChanged,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (p2pService != null) ...[
              ConnectionStatusIndicator(p2pService: p2pService!),
              const SizedBox(width: 8),
            ],
            GestureDetector(
              onTap: onAvatarTap,
              child: _HeaderAvatar(peerId: peerId, avatarBytes: avatarBytes),
            ),
          ],
        ),
      ],
    );
  }
}

class _HeaderAvatar extends StatelessWidget {
  final String? peerId;
  final Uint8List? avatarBytes;

  const _HeaderAvatar({required this.peerId, required this.avatarBytes});

  @override
  Widget build(BuildContext context) {
    if (peerId != null) {
      return RingAvatar(peerId: peerId!, size: 42);
    }

    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.35)),
        color: const Color.fromRGBO(22, 24, 30, 0.7),
      ),
      child: avatarBytes != null
          ? ClipOval(
              child: Image.memory(
                avatarBytes!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.person_outline_rounded,
                  color: Color.fromRGBO(255, 255, 255, 0.8),
                ),
              ),
            )
          : const Icon(
              Icons.person_outline_rounded,
              color: Color.fromRGBO(255, 255, 255, 0.8),
              size: 20,
            ),
    );
  }
}
