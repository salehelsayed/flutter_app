import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';

/// Bottom panel showing overlapping avatars, names, group name input,
/// and a "Start group chat" button.
class GroupNamePanel extends StatelessWidget {
  final List<ContactModel> selectedContacts;
  final TextEditingController nameController;
  final VoidCallback onStartGroup;
  final bool isCreating;

  const GroupNamePanel({
    super.key,
    required this.selectedContacts,
    required this.nameController,
    required this.onStartGroup,
    this.isCreating = false,
  });

  String get _namesText {
    if (selectedContacts.length <= 2) {
      return selectedContacts.map((c) => c.username).join(', ');
    }
    final firstTwo = selectedContacts.take(2).map((c) => c.username).join(', ');
    return '$firstTwo +${selectedContacts.length - 2}';
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(
              top: BorderSide(
                color: Colors.white.withOpacity(0.12),
                width: 0.5,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              // Overlapping avatars
              _buildAvatarRow(),
              const SizedBox(height: 8),
              // Names
              Text(
                _namesText,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 12),
              // Group name input
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context)!.group_name_optional,
                  hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.35),
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                ),
              ),
              const SizedBox(height: 12),
              // Start button
              _buildStartButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarRow() {
    const double avatarSize = 36;
    const double overlap = 24;
    final count = selectedContacts.length;
    final totalWidth =
        count == 0 ? 0.0 : avatarSize + (count - 1) * overlap;

    return SizedBox(
      height: avatarSize,
      width: totalWidth,
      child: Stack(
        children: [
          for (var i = 0; i < count; i++)
            Positioned(
              left: i * overlap,
              child: UserAvatar(
                peerId: selectedContacts[i].peerId,
                size: avatarSize,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStartButton() {
    if (isCreating) {
      return const SizedBox(
        height: 48,
        child: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return GestureDetector(
      onTap: onStartGroup,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF64B5F6), Color(0xFFAB47BC)],
          ),
          borderRadius: BorderRadius.circular(28),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text(
              'Start group chat',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
