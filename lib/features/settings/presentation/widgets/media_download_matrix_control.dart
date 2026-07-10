import 'package:flutter/material.dart';

import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/settings/domain/models/media_download_preferences.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// The tri-state a user picks per (lane, media type). It projects onto the
/// two persisted network booleans: `off` disables both, `wifi` enables only
/// Wi-Fi, `all` enables Wi-Fi and cellular. A stored cellular-only matrix
/// (unreachable from this UI, but valid in the codec) reads back as [all].
enum MediaDownloadNetworkChoice { off, wifi, all }

/// 229: focused settings control for the per-lane / per-type / per-network
/// automatic-download matrix.
class MediaDownloadMatrixControl extends StatelessWidget {
  const MediaDownloadMatrixControl({
    super.key,
    required this.preferences,
    required this.onChanged,
    this.errorText,
  });

  final MediaDownloadPreferences preferences;
  final ValueChanged<MediaDownloadPreferences> onChanged;
  final String? errorText;

  static MediaDownloadNetworkChoice choiceFor(
    MediaDownloadPreferences preferences,
    MediaConversationKind kind,
    String mediaType,
  ) {
    final cellular = preferences.isAutoDownloadEnabled(
      kind: kind,
      mediaType: mediaType,
      network: MediaDownloadNetwork.cellular,
    );
    if (cellular) return MediaDownloadNetworkChoice.all;
    final wifi = preferences.isAutoDownloadEnabled(
      kind: kind,
      mediaType: mediaType,
      network: MediaDownloadNetwork.wifi,
    );
    return wifi
        ? MediaDownloadNetworkChoice.wifi
        : MediaDownloadNetworkChoice.off;
  }

  static MediaDownloadPreferences applyChoice(
    MediaDownloadPreferences preferences,
    MediaConversationKind kind,
    String mediaType,
    MediaDownloadNetworkChoice choice,
  ) {
    return preferences
        .copyWithChoice(
          kind: kind,
          mediaType: mediaType,
          network: MediaDownloadNetwork.wifi,
          enabled: choice != MediaDownloadNetworkChoice.off,
        )
        .copyWithChoice(
          kind: kind,
          mediaType: mediaType,
          network: MediaDownloadNetwork.cellular,
          enabled: choice == MediaDownloadNetworkChoice.all,
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final readableColors = context.backgroundReadableColors;

    String laneLabel(MediaConversationKind kind) => switch (kind) {
          MediaConversationKind.oneToOne => l10n.settings_media_lane_direct,
          MediaConversationKind.discussion =>
            l10n.settings_media_lane_discussions,
          MediaConversationKind.announcement =>
            l10n.settings_media_lane_announcements,
        };
    String typeLabel(String mediaType) => switch (mediaType) {
          'image' => l10n.settings_media_type_image,
          'video' => l10n.settings_media_type_video,
          'audio' => l10n.settings_media_type_audio,
          _ => l10n.settings_media_type_file,
        };
    String choiceLabel(MediaDownloadNetworkChoice choice) => switch (choice) {
          MediaDownloadNetworkChoice.off => l10n.settings_media_network_off,
          MediaDownloadNetworkChoice.wifi => l10n.settings_media_network_wifi,
          MediaDownloadNetworkChoice.all => l10n.settings_media_network_all,
        };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.settings_media_auto_download,
            style: TextStyle(
              color: readableColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.settings_media_auto_download_desc,
            style: TextStyle(
              color: readableColors.textMuted,
              fontSize: 12,
              height: 1.3,
            ),
          ),
          if (errorText != null) ...[
            const SizedBox(height: 8),
            Text(
              errorText!,
              key: const ValueKey('media-download-save-error'),
              style: const TextStyle(
                color: Color(0xFFff6b6b),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          for (final kind in MediaConversationKind.values) ...[
            const SizedBox(height: 16),
            Text(
              laneLabel(kind),
              style: TextStyle(
                color: readableColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            for (final type in kMediaDownloadPreferenceTypes) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      typeLabel(type),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: readableColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Flexible(
                    flex: 3,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SegmentedButton<MediaDownloadNetworkChoice>(
                    key: ValueKey('media-download-${kind.name}-$type'),
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    segments: [
                      for (final choice in MediaDownloadNetworkChoice.values)
                        ButtonSegment(
                          value: choice,
                          label: Text(
                            choiceLabel(choice),
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                    ],
                        selected: {choiceFor(preferences, kind, type)},
                        onSelectionChanged: (selection) => onChanged(
                          applyChoice(
                            preferences,
                            kind,
                            type,
                            selection.single,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}
