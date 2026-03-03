import 'package:flutter/material.dart';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';

/// Single row widget for a contact in the picker list.
///
/// Shows an avatar initial, username, truncated peer ID, and an add icon.
class ContactPickerRow extends StatelessWidget {
  final ContactModel contact;
  final VoidCallback onTap;
  final bool isSelected;

  const ContactPickerRow({
    super.key,
    required this.contact,
    required this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final truncatedPeerId = contact.peerId.length > 12
        ? '${contact.peerId.substring(0, 12)}...'
        : contact.peerId;

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            UserAvatar(peerId: contact.peerId, size: 36),
            const SizedBox(width: 12),
            // Name + truncated peerId
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.username,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    truncatedPeerId,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.4),
                    ),
                  ),
                ],
              ),
            ),
            // Selection icon
            Icon(
              isSelected ? Icons.check_circle : Icons.add_circle_outline,
              size: 20,
              color: isSelected
                  ? const Color(0xFF64B5F6)
                  : Colors.white.withOpacity(0.4),
            ),
          ],
        ),
      ),
    );
  }
}
