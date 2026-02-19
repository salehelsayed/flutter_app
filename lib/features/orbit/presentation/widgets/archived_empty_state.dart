import 'package:flutter/material.dart';

/// Empty state shown when the archived tab has no friends.
class ArchivedEmptyState extends StatelessWidget {
  const ArchivedEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0x0FFFFFFF), // rgba(255,255,255,0.06)
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.archive_outlined,
                size: 24,
                color: Color(0x40FFFFFF), // rgba(255,255,255,0.25)
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No archived friends yet',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Swipe left on a friend to archive them.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.25),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
