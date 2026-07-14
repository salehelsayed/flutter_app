import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/conversation/application/received_media_action_controller.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// 231: presentation-only sheets for the direct received-media actions.
///
/// Both sheets render supplied values and pop a choice — no repository,
/// controller, service, transport, or platform-channel access lives here.

/// Photos/Files destination chooser shown after Save on either the bubble
/// overlay or the typed viewer. Pops the picked [MediaEgressDestination]
/// (never `share`), or null when dismissed.
class DirectMediaSaveDestinationSheet extends StatelessWidget {
  static const sheetKey = ValueKey('direct-media-save-destination-sheet');
  static const photosActionKey = ValueKey('direct-media-save-photos');
  static const filesActionKey = ValueKey('direct-media-save-files');

  const DirectMediaSaveDestinationSheet({super.key});

  static Future<MediaEgressDestination?> show(BuildContext context) {
    return showModalBottomSheet<MediaEgressDestination>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const DirectMediaSaveDestinationSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final readable = context.backgroundReadableColors;
    final isLight = readable.isLightSurface;
    final sheetSurface = isLight
        ? readable.surfaceRaised
        : const Color.fromRGBO(18, 20, 28, 0.96);
    final sheetBorder = isLight
        ? readable.surfaceBorder
        : const Color.fromRGBO(255, 255, 255, 0.10);
    final promptColor = isLight
        ? readable.textPrimary
        : const Color.fromRGBO(255, 255, 255, 0.94);
    final maxHeight = MediaQuery.of(context).size.height * 0.72;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              key: sheetKey,
              decoration: BoxDecoration(
                color: sheetSurface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: sheetBorder),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.media_save_destination_prompt,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: promptColor,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SheetAction(
                        key: photosActionKey,
                        icon: Icons.photo_library_outlined,
                        label: l10n.media_save_destination_photos,
                        onTap: () => Navigator.of(
                          context,
                        ).pop(MediaEgressDestination.photos),
                      ),
                      const SizedBox(height: 10),
                      _SheetAction(
                        key: filesActionKey,
                        icon: Icons.folder_outlined,
                        label: l10n.media_save_destination_files,
                        onTap: () => Navigator.of(
                          context,
                        ).pop(MediaEgressDestination.files),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Local Info sheet for one direct received attachment: owning-message
/// sender/direction/date plus current attachment MIME, size, dimensions or
/// duration, and download/integrity state. Values come from persisted
/// metadata handed in by the caller — never key/nonce material or a raw path.
class DirectReceivedMediaInfoSheet extends StatelessWidget {
  static const sheetKey = ValueKey('direct-media-info-sheet');
  static const senderValueKey = ValueKey('direct-media-info-sender');
  static const directionValueKey = ValueKey('direct-media-info-direction');
  static const dateValueKey = ValueKey('direct-media-info-date');
  static const typeValueKey = ValueKey('direct-media-info-type');
  static const sizeValueKey = ValueKey('direct-media-info-size');
  static const dimensionsValueKey = ValueKey('direct-media-info-dimensions');
  static const durationValueKey = ValueKey('direct-media-info-duration');
  static const stateValueKey = ValueKey('direct-media-info-state');

  const DirectReceivedMediaInfoSheet({
    super.key,
    required this.info,
    required this.senderLabel,
  });

  final DirectReceivedMediaInfo info;
  final String senderLabel;

  static Future<void> show(
    BuildContext context, {
    required DirectReceivedMediaInfo info,
    required String senderLabel,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          DirectReceivedMediaInfoSheet(info: info, senderLabel: senderLabel),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final readable = context.backgroundReadableColors;
    final isLight = readable.isLightSurface;
    final sheetSurface = isLight
        ? readable.surfaceRaised
        : const Color.fromRGBO(18, 20, 28, 0.96);
    final sheetBorder = isLight
        ? readable.surfaceBorder
        : const Color.fromRGBO(255, 255, 255, 0.10);
    final titleColor = isLight
        ? readable.textPrimary
        : const Color.fromRGBO(255, 255, 255, 0.94);
    final maxHeight = MediaQuery.of(context).size.height * 0.72;

    final state = info.isPrivacyMinimized
        ? info.privateInfo!.state.wireValue
        : info.isIntegrityFailed
        ? l10n.media_info_state_unverified
        : info.isDownloaded
        ? l10n.media_info_state_downloaded
        : l10n.media_info_state_not_downloaded;
    final rows = <Widget>[
      _InfoRow(
        label: l10n.media_info_sender,
        value: senderLabel,
        valueKey: senderValueKey,
      ),
      _InfoRow(
        label: l10n.media_info_direction,
        value: info.isIncoming
            ? l10n.media_info_direction_incoming
            : l10n.media_info_direction_outgoing,
        valueKey: directionValueKey,
      ),
      _InfoRow(
        label: l10n.media_info_date,
        value: _formatTimestamp(info.timestamp),
        valueKey: dateValueKey,
      ),
      _InfoRow(
        label: l10n.media_info_type,
        value: info.isPrivacyMinimized
            ? l10n.private_media_notification_body
            : info.mime,
        valueKey: typeValueKey,
      ),
      if (!info.isPrivacyMinimized)
        _InfoRow(
          label: l10n.media_info_size,
          value: _formatBytes(info.sizeBytes),
          valueKey: sizeValueKey,
        ),
      if (!info.isPrivacyMinimized &&
          info.mediaType != 'video' &&
          info.width != null &&
          info.height != null)
        _InfoRow(
          label: l10n.media_info_dimensions,
          value: '${info.width} × ${info.height}',
          valueKey: dimensionsValueKey,
        ),
      if (!info.isPrivacyMinimized &&
          info.mediaType == 'video' &&
          info.durationMs != null)
        _InfoRow(
          label: l10n.media_info_duration,
          value: _formatDurationMs(info.durationMs!),
          valueKey: durationValueKey,
        ),
      _InfoRow(
        label: l10n.media_info_state,
        value: state,
        valueKey: stateValueKey,
      ),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              key: sheetKey,
              decoration: BoxDecoration(
                color: sheetSurface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: sheetBorder),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.media_info_title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: titleColor,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 14),
                      for (var i = 0; i < rows.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 14,
                            thickness: 1,
                            color: readable.divider,
                          ),
                        rows[i],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final readable = context.backgroundReadableColors;
    final isLight = readable.isLightSurface;
    final chipFill = isLight
        ? readable.surfaceSubtle
        : const Color.fromRGBO(255, 255, 255, 0.05);
    final chipBorder = isLight
        ? readable.surfaceBorder
        : const Color.fromRGBO(255, 255, 255, 0.08);
    final color = isLight
        ? readable.textSecondary
        : const Color.fromRGBO(255, 255, 255, 0.86);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: chipFill,
            border: Border.all(color: chipBorder),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.valueKey,
  });

  final String label;
  final String value;
  final ValueKey<String> valueKey;

  @override
  Widget build(BuildContext context) {
    final readable = context.backgroundReadableColors;
    final isLight = readable.isLightSurface;
    final labelColor = isLight
        ? readable.textSecondary
        : const Color.fromRGBO(255, 255, 255, 0.60);
    final valueColor = isLight
        ? readable.textPrimary
        : const Color.fromRGBO(255, 255, 255, 0.90);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: labelColor,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: KeyedSubtree(
            key: valueKey,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _formatTimestamp(String isoTimestamp) {
  final parsed = DateTime.tryParse(isoTimestamp);
  if (parsed == null) return isoTimestamp;
  final local = parsed.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
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

String _formatDurationMs(int durationMs) {
  final totalSeconds = (durationMs / 1000).round();
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
