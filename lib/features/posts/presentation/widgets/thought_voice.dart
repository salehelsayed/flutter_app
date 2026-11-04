import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/posts/application/post_media_draft.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/audio_player_widget.dart';

const _recordRed = Color(0xFFF87171);

/// A Thought recording in the sheet: "recording" and the time, live bars,
/// then Cancel, a red stop and a pause.
class ThoughtRecordingCard extends StatelessWidget {
  const ThoughtRecordingCard({
    super.key = const ValueKey('thought-voice-recording'),
    required this.elapsed,
    required this.amplitudes,
    required this.paused,
    required this.onCancel,
    required this.onStop,
    this.onPauseToggle,
  });

  final Duration elapsed;
  final List<double> amplitudes;
  final bool paused;
  final VoidCallback onCancel;
  final VoidCallback onStop;

  /// Null when the recorder cannot pause.
  final VoidCallback? onPauseToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final rc = context.backgroundReadableColors;
    final seconds = elapsed.inSeconds;
    final time =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          decoration: BoxDecoration(
            color: rc.composerInputFill,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: rc.accent.withValues(alpha: .45)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: paused ? rc.textMuted : _recordRed,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.thought_voice_recording,
                    style: TextStyle(color: rc.textSecondary, fontSize: 12),
                  ),
                  const Spacer(),
                  Text(
                    time,
                    style: TextStyle(
                      color: rc.textPrimary,
                      fontSize: 13,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ExcludeSemantics(
                child: SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      for (final level in amplitudes)
                        Expanded(
                          child: Center(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 90),
                              margin: const EdgeInsets.symmetric(
                                horizontal: 1.5,
                              ),
                              height: 4 + 40 * level.clamp(0.0, 1.0),
                              decoration: BoxDecoration(
                                color: paused ? rc.textMuted : rc.accent,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(
                    onPressed: onCancel,
                    style: TextButton.styleFrom(
                      foregroundColor: rc.textSecondary,
                      minimumSize: const Size(64, 44),
                    ),
                    child: Text(l10n.btn_cancel),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: l10n.compose_voice_stop,
                    onPressed: onStop,
                    constraints: const BoxConstraints.tightFor(
                      width: 56,
                      height: 56,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: _recordRed,
                      foregroundColor: const Color(0xFF2A0B0B),
                    ),
                    icon: const Icon(Icons.stop_rounded, size: 28),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 64,
                    child: onPauseToggle == null
                        ? null
                        : IconButton(
                            tooltip: paused
                                ? l10n.thought_voice_resume
                                : l10n.thought_voice_pause,
                            onPressed: onPauseToggle,
                            constraints: const BoxConstraints.tightFor(
                              width: 44,
                              height: 44,
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: rc.surfaceSubtle,
                              foregroundColor: rc.textPrimary,
                            ),
                            icon: Icon(
                              paused ? Icons.mic_rounded : Icons.pause_rounded,
                              size: 22,
                            ),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 5, left: 2),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: rc.textMuted,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.thought_voice_limit,
                style: TextStyle(color: rc.textMuted, fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The recorded voice note as friends will see it, with an X to discard it.
class ThoughtVoiceCard extends StatelessWidget {
  const ThoughtVoiceCard({
    super.key = const ValueKey('thought-voice-card'),
    required this.draft,
    required this.caption,
    required this.onRemove,
  });

  final PostMediaDraft draft;

  /// The caption line above the player.
  final TextEditingController caption;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final rc = context.backgroundReadableColors;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: rc.composerInputFill,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: rc.accent.withValues(alpha: .3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, end: 44),
            child: TextField(
              key: const ValueKey('thought-voice-caption'),
              controller: caption,
              maxLength: PostMediaAttachmentModel.maxCaptionLength,
              buildCounter:
                  (
                    _, {
                    required currentLength,
                    required isFocused,
                    maxLength,
                  }) => null,
              maxLines: 2,
              minLines: 1,
              style: TextStyle(color: rc.textSecondary, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                hintText: l10n.thought_voice_caption_hint,
                hintStyle: TextStyle(color: rc.placeholderText, fontSize: 13),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: AudioPlayerWidget(
                  key: ValueKey('thought-voice-player-${draft.localFilePath}'),
                  attachment: MediaAttachment(
                    id: 'thought-voice-draft',
                    messageId: 'thought-draft',
                    mime: draft.mime,
                    size: 0,
                    mediaType: 'audio',
                    durationMs: draft.durationMs,
                    localPath: draft.localFilePath,
                    downloadStatus: 'done',
                    createdAt: '',
                    waveform: draft.waveform,
                  ),
                ),
              ),
              IconButton(
                tooltip: l10n.thought_voice_remove,
                onPressed: onRemove,
                icon: Icon(Icons.close_rounded, color: rc.iconSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A voice note's caption where friends and the author see it, above the
/// player.
class ThoughtVoiceCaption extends StatelessWidget {
  const ThoughtVoiceCaption(this.text, {super.key, this.color});

  final String text;

  /// Defaults to the theme's secondary text.
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(start: 4, bottom: 4),
    child: Text(
      text,
      style: TextStyle(
        color: color ?? context.backgroundReadableColors.textSecondary,
        fontSize: 13,
        height: 1.35,
      ),
    ),
  );
}
