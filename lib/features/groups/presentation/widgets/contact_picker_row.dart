import 'package:flutter/material.dart';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';

/// Single row widget for a contact in the picker list.
///
/// Shows an avatar initial, username, truncated peer ID, and an add icon.
class ContactPickerRow extends StatelessWidget {
  final ContactModel contact;
  final VoidCallback onTap;

  const ContactPickerRow({
    super.key,
    required this.contact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final initial = contact.username.isNotEmpty
        ? contact.username[0].toUpperCase()
        : '?';
    final truncatedPeerId = contact.peerId.length > 12
        ? '${contact.peerId.substring(0, 12)}...'
        : contact.peerId;

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // Avatar placeholder
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  initial,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
              ),
            ),
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
            // Add icon
            Icon(
              Icons.add_circle_outline,
              size: 20,
              color: Colors.white.withOpacity(0.4),
            ),
          ],
        ),
      ),
    );
  }
}
