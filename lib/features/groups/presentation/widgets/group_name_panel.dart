import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

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
    final readableColors = context.backgroundReadableColors;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          decoration: BoxDecoration(
            color: readableColors.glassSurface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(
              top: BorderSide(color: readableColors.glassBorder, width: 0.5),
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
                  color: readableColors.divider,
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
                  color: readableColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              // Group name input
              TextField(
                controller: nameController,
                style: TextStyle(
                  color: readableColors.textPrimary,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context)!.group_name_optional,
                  hintStyle: TextStyle(
                    color: readableColors.placeholderText,
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: readableColors.inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Start button
              _buildStartButton(context),
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
    final totalWidth = count == 0 ? 0.0 : avatarSize + (count - 1) * overlap;

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

  Widget _buildStartButton(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final start = readableColors.isLightSurface
        ? const Color(0xFF0F5F9C)
        : const Color(0xFF64B5F6);
    final end = readableColors.isLightSurface
        ? const Color(0xFF65348A)
        : const Color(0xFFAB47BC);
    final onAccent = readableColors.isLightSurface
        ? Colors.white
        : Colors.black;

    if (isCreating) {
      return SizedBox(
        height: 48,
        child: Center(
          child: CircularProgressIndicator(color: readableColors.iconPrimary),
        ),
      );
    }

    return GestureDetector(
      onTap: onStartGroup,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [start, end]),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people, color: onAccent, size: 18),
            const SizedBox(width: 8),
            Text(
              'Start group chat',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: onAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
