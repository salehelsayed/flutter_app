import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/home/presentation/widgets/editable_username_widget.dart';
import 'package:flutter_app/features/home/presentation/widgets/ring_avatar.dart';

/// Profile section displaying avatar with camera overlay and editable username.
class SettingsProfileSection extends StatelessWidget {
  final String? peerId;
  final Uint8List? avatarBytes;
  final String username;
  final VoidCallback? onPickAvatar;
  final ValueChanged<String>? onUsernameChanged;

  const SettingsProfileSection({
    super.key,
    this.peerId,
    this.avatarBytes,
    required this.username,
    this.onPickAvatar,
    this.onUsernameChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
      child: Column(
        children: [
          // Avatar with camera overlay
          SizedBox(
            width: 100,
            height: 100,
            child: Stack(
              children: [
                _buildAvatar(),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: onPickAvatar,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFF14B8A6),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF0A0A0F),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Editable username
          EditableUsernameWidget(
            username: username,
            onUsernameChanged: onUsernameChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    if (avatarBytes != null) {
      return ClipOval(
        child: Image.memory(
          avatarBytes!,
          width: 100,
          height: 100,
          fit: BoxFit.cover,
        ),
      );
    }

    if (peerId != null) {
      return RingAvatar(peerId: peerId!, size: 100);
    }

    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color.fromRGBO(255, 255, 255, 0.35),
        ),
        color: const Color.fromRGBO(22, 24, 30, 0.7),
      ),
      child: const Icon(
        Icons.person_outline_rounded,
        color: Color.fromRGBO(255, 255, 255, 0.8),
        size: 40,
      ),
    );
  }
}
