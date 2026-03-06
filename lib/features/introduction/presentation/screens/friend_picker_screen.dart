import 'package:flutter/material.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';

/// Pure UI bottom sheet for selecting friends to introduce.
///
/// Displays a searchable list of available friends with circle checkboxes.
/// The parent wired widget manages selection state and triggers the send action.
class FriendPickerScreen extends StatelessWidget {
  final String recipientUsername;
  final List<ContactModel> availableFriends;
  final Set<String> selectedPeerIds;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onToggleFriend;
  final VoidCallback onSend;
  final VoidCallback onClose;

  const FriendPickerScreen({
    super.key,
    required this.recipientUsername,
    required this.availableFriends,
    required this.selectedPeerIds,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onToggleFriend,
    required this.onSend,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final filtered = availableFriends
        .where((c) =>
            c.username.toLowerCase().contains(searchQuery.toLowerCase()))
        .toList();

    final selectionCount = selectedPeerIds.length;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0B0D11),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0x33FFFFFF),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Introduce to $recipientUsername',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Color(0xF2FFFFFF),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(
                    Icons.close,
                    size: 20,
                    color: Color(0x66FFFFFF),
                  ),
                ),
              ],
            ),
          ),

          // Search field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0x14FFFFFF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x1FFFFFFF)),
              ),
              child: TextField(
                onChanged: onSearchChanged,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xF2FFFFFF),
                ),
                decoration: InputDecoration(
                  hintText: 'Search friends...',
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
            ),
          ),

          // Friends list
          Flexible(
            child: filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      searchQuery.isEmpty
                          ? 'No friends available to introduce'
                          : 'No friends matching "$searchQuery"',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final friend = filtered[index];
                      final isSelected =
                          selectedPeerIds.contains(friend.peerId);
                      return _FriendPickerRow(
                        friend: friend,
                        isSelected: isSelected,
                        onTap: () => onToggleFriend(friend.peerId),
                      );
                    },
                  ),
          ),

          // Bottom action bar
          Container(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              12 + MediaQuery.of(context).padding.bottom,
            ),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Color(0x14FFFFFF)),
              ),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: selectionCount > 0 ? onSend : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1DB954),
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: const Color(0x331DB954),
                  disabledForegroundColor: Colors.black.withValues(alpha: 0.4),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  selectionCount > 0
                      ? 'Introduce ($selectionCount)'
                      : 'Introduce',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single friend row with a circle checkbox for selection.
class _FriendPickerRow extends StatelessWidget {
  final ContactModel friend;
  final bool isSelected;
  final VoidCallback onTap;

  const _FriendPickerRow({
    required this.friend,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            UserAvatar(peerId: friend.peerId, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                friend.username,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xF2FFFFFF),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            // Circle checkbox
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? const Color(0xFF1DB954)
                    : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF1DB954)
                      : const Color(0x66FFFFFF),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 14, color: Colors.black)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
