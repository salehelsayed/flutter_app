import 'package:flutter/material.dart';

import 'package:flutter_app/features/posts/domain/models/post_model.dart';

class PostCard extends StatelessWidget {
  final PostModel post;
  final bool isFocused;

  const PostCard({super.key, required this.post, this.isFocused = false});

  @override
  Widget build(BuildContext context) {
    final borderColor = isFocused
        ? const Color(0xFF8FD6B5)
        : const Color.fromRGBO(255, 255, 255, 0.12);
    final scopeLabel = post.audience.scopeLabel;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF171A20),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: isFocused
                ? const Color.fromRGBO(143, 214, 181, 0.18)
                : const Color.fromRGBO(0, 0, 0, 0.12),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  post.authorUsername,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                _formatTimestamp(post.createdAt),
                style: const TextStyle(
                  color: Color.fromRGBO(255, 255, 255, 0.54),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const _Badge(label: 'Direct Friend'),
              if (scopeLabel != null) ...[
                const SizedBox(width: 8),
                _Badge(label: scopeLabel),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Text(
            post.text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _confirmationCopy(post),
            style: const TextStyle(
              color: Color.fromRGBO(255, 255, 255, 0.54),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTimestamp(String rawTimestamp) {
    final timestamp = DateTime.tryParse(rawTimestamp)?.toLocal();
    if (timestamp == null) {
      return rawTimestamp;
    }
    final hour = timestamp.hour == 0 || timestamp.hour == 12
        ? 12
        : timestamp.hour % 12;
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final meridiem = timestamp.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $meridiem';
  }

  static String _confirmationCopy(PostModel post) {
    return switch (post.audience.kind) {
      _ when post.audience.selectedPeerIds.isNotEmpty =>
        'Shared with ${post.audience.selectedPeerIds.length} people',
      _ => 'Shared with all friends',
    };
  }
}

class _Badge extends StatelessWidget {
  final String label;

  const _Badge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 255, 255, 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
