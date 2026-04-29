import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';

/// Emoji categories for the full picker.
const _emojiCategories = <String, List<String>>{
  'Smileys': [
    '😀', '😃', '😄', '😁', '😅', '😂', '🤣', '😊',
    '😇', '🙂', '🙃', '😉', '😌', '😍', '🥰', '😘',
    '😗', '😙', '😚', '😋', '😛', '😜', '🤪', '😝',
    '🤑', '🤗', '🤭', '🤫', '🤔', '🤐', '🤨', '😐',
    '😑', '😶', '😏', '😒', '🙄', '😬', '🤥', '😌',
    '😔', '😪', '🤤', '😴', '😷', '🤒', '🤕', '🤢',
  ],
  'People': [
    '👋', '🤚', '🖐️', '✋', '🖖', '👌', '🤌', '🤏',
    '✌️', '🤞', '🤟', '🤘', '🤙', '👈', '👉', '👆',
    '🖕', '👇', '☝️', '👍', '👎', '✊', '👊', '🤛',
    '🤜', '👏', '🙌', '👐', '🤲', '🤝', '🙏', '💪',
  ],
  'Animals': [
    '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼',
    '🐻‍❄️', '🐨', '🐯', '🦁', '🐮', '🐷', '🐸', '🐵',
    '🐔', '🐧', '🐦', '🐤', '🦆', '🦅', '🦉', '🦇',
    '🐺', '🐗', '🐴', '🦄', '🐝', '🐛', '🦋', '🐌',
  ],
  'Food': [
    '🍎', '🍐', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓',
    '🫐', '🍈', '🍒', '🍑', '🥭', '🍍', '🥥', '🥝',
    '🍅', '🍆', '🥑', '🫑', '🥦', '🥬', '🥒', '🌶️',
    '🌽', '🥕', '🫒', '🧄', '🧅', '🥔', '🍠', '🍕',
  ],
  'Travel': [
    '🚗', '🚕', '🚙', '🚌', '🚎', '🏎️', '🚓', '🚑',
    '🚒', '🚐', '🛻', '🚚', '🚛', '🚜', '✈️', '🛫',
    '🛬', '🚀', '🛸', '⛵', '🚢', '🏠', '🏡', '🏢',
  ],
  'Objects': [
    '⌚', '📱', '💻', '⌨️', '🖥️', '🖨️', '🖱️', '💡',
    '🔦', '🕯️', '📷', '📸', '📹', '🎥', '📺', '📻',
    '🎵', '🎶', '🎤', '🎧', '🎸', '🥁', '🎹', '🎺',
  ],
  'Symbols': [
    '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍',
    '🤎', '💔', '❣️', '💕', '💞', '💓', '💗', '💖',
    '💘', '💝', '⭐', '🌟', '💫', '✨', '🔥', '💯',
    '✅', '❌', '⚡', '💢', '💬', '🏳️', '🏴', '🚩',
  ],
};

/// Shows a full emoji picker as a modal bottom sheet.
///
/// Returns the selected emoji string, or null if dismissed.
Future<String?> showFullEmojiPicker(BuildContext context) {
  final readableColors = context.backgroundReadableColors;

  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: readableColors.surfaceBase,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      side: BorderSide(color: readableColors.divider),
    ),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.4,
    ),
    builder: (context) => const _FullEmojiPicker(),
  );
}

class _FullEmojiPicker extends StatefulWidget {
  const _FullEmojiPicker();

  @override
  State<_FullEmojiPicker> createState() => _FullEmojiPickerState();
}

class _FullEmojiPickerState extends State<_FullEmojiPicker> {
  String _selectedCategory = _emojiCategories.keys.first;

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final selectedAccent = readableColors.isLightSurface
        ? const Color(0xFF16756F)
        : const Color(0xFF4ECDC4);
    final emojis = _emojiCategories[_selectedCategory] ?? [];

    return Column(
      children: [
        // Handle bar
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: readableColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        // Category tabs
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: _emojiCategories.keys.map((category) {
              final isSelected = category == _selectedCategory;
              return GestureDetector(
                onTap: () => setState(() => _selectedCategory = category),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? selectedAccent.withValues(alpha: 0.14)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    category,
                    style: TextStyle(
                      fontSize: 13,
                      color: isSelected
                          ? selectedAccent
                          : readableColors.textMuted,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        // Emoji grid
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 8,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: emojis.length,
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () => Navigator.of(context).pop(emojis[index]),
                child: Center(
                  child: Text(
                    emojis[index],
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
