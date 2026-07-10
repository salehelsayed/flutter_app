import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// 235: privacy-minimized Info sheet for one received group media attachment.
///
/// Renders ONLY the approved fields: kind, size when known, sender display
/// identity, sent time, transfer/integrity state, and caption. Storage,
/// crypto, and transport internals — local path, content/thumbnail hashes,
/// encryption key/nonce/scheme, peer or relay diagnostics — must NEVER render
/// here (TC-235-12 locks this with sentinel secrets).
class GroupMediaInfoSheet extends StatelessWidget {
  static const sheetKey = ValueKey('group-media-info-sheet');

  final MediaAttachment attachment;
  final String senderDisplayName;
  final DateTime sentAt;
  final String? caption;

  const GroupMediaInfoSheet({
    super.key,
    required this.attachment,
    required this.senderDisplayName,
    required this.sentAt,
    this.caption,
  });

  static Future<void> show(
    BuildContext context, {
    required MediaAttachment attachment,
    required String senderDisplayName,
    required DateTime sentAt,
    String? caption,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => GroupMediaInfoSheet(
        attachment: attachment,
        senderDisplayName: senderDisplayName,
        sentAt: sentAt,
        caption: caption,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final sentLabel = intl.DateFormat.yMMMd(
      locale,
    ).add_jm().format(sentAt.toLocal());
    final trimmedCaption = caption?.trim();

    return SafeArea(
      child: Padding(
        key: GroupMediaInfoSheet.sheetKey,
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.group_media_info_title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            _InfoRow(
              label: l10n.group_media_info_kind,
              value: _kindLabel(l10n),
              valueKey: const ValueKey('group-media-info-kind'),
              icon: attachment.mediaType == 'video'
                  ? Icons.videocam_outlined
                  : Icons.image_outlined,
            ),
            _InfoRow(
              label: l10n.group_media_info_sender,
              value: senderDisplayName,
              valueKey: const ValueKey('group-media-info-sender'),
            ),
            _InfoRow(
              label: l10n.group_media_info_sent_time,
              value: sentLabel,
              valueKey: const ValueKey('group-media-info-sent-time'),
            ),
            if (attachment.size > 0)
              _InfoRow(
                label: l10n.group_media_info_size,
                value: _formatBytes(attachment.size),
                valueKey: const ValueKey('group-media-info-size'),
              ),
            _InfoRow(
              label: l10n.group_media_info_state,
              value: _stateLabel(l10n),
              valueKey: const ValueKey('group-media-info-state'),
            ),
            if (trimmedCaption != null && trimmedCaption.isNotEmpty)
              _InfoRow(
                label: l10n.group_media_info_caption,
                value: trimmedCaption,
                valueKey: const ValueKey('group-media-info-caption'),
              ),
          ],
        ),
      ),
    );
  }

  String _kindLabel(AppLocalizations l10n) => attachment.mediaType == 'video'
      ? l10n.group_media_info_kind_video
      : l10n.group_media_info_kind_image;

  String _stateLabel(AppLocalizations l10n) {
    if (GroupMediaIntegrityPolicy.isQuarantinedGroupMedia(attachment)) {
      return l10n.media_could_not_verify;
    }
    if (attachment.downloadStatus == kMediaDownloadStatusEvicted) {
      return l10n.media_local_copy_removed;
    }
    if (GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia(attachment)) {
      return l10n.group_media_info_state_available;
    }
    if (attachment.downloadStatus == kMediaDownloadStatusPending ||
        attachment.downloadStatus == kMediaDownloadStatusDownloading) {
      return l10n.group_media_info_state_pending;
    }
    return l10n.group_media_info_state_unavailable;
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  final rendered = value >= 100 || value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$rendered ${units[unitIndex]}';
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Key valueKey;
  final IconData? icon;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.valueKey,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(
                color: textTheme.bodySmall?.color?.withValues(alpha: 0.7),
              ),
            ),
          ),
          if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 6)],
          Expanded(
            child: Text(value, key: valueKey, style: textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
