import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/home/presentation/widgets/editable_username_widget.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
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
              child: UserAvatar(
                peerId: peerId,
                avatarBytes: avatarBytes,
                size: 42,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
