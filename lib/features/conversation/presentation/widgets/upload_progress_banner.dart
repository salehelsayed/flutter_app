import 'package:flutter/material.dart';

import 'package:flutter_app/core/media/pending_composer_media.dart';

class UploadProgressViewState {
  final int sentBytes;
  final int totalBytes;

  const UploadProgressViewState({
    required this.sentBytes,
    required this.totalBytes,
  });

  double get progress {
    if (totalBytes <= 0) return 0;
    final clamped = sentBytes.clamp(0, totalBytes);
    return clamped / totalBytes;
  }

  String get progressLabel =>
      '${formatPendingComposerBudgetBytes(sentBytes)} / '
      '${formatPendingComposerBudgetBytes(totalBytes)}';
}

class UploadProgressBanner extends StatelessWidget {
  final UploadProgressViewState state;
  final VoidCallback? onCancel;

  const UploadProgressBanner({super.key, required this.state, this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('upload-progress-banner'),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x29FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Uploading media',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            state.progressLabel,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              key: const ValueKey('upload-progress-indicator'),
              value: state.progress,
              minHeight: 6,
              backgroundColor: const Color(0x1FFFFFFF),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF4ECDC4),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Keep the app open until the upload completes',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (onCancel != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('upload-progress-cancel-button'),
                onPressed: onCancel,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFFB4A9),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text('Cancel'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
