import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_timeline_entry.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// 405: the chat row for one terminal call.
///
/// Call rows share the conversation timeline with messages but are not
/// messages: they are never sent, retried through the outbox, or stored in
/// `messages.wire_envelope`. The row reads only the privacy-safe projection
/// (direction, status, duration) — never a call handle, route or signal.

/// Formats connected talk time as `m:ss`, or `h:mm:ss` once past an hour.
String formatCallDuration(Duration duration) {
  final total = duration.isNegative ? Duration.zero : duration;
  final seconds = total.inSeconds.remainder(60).toString().padLeft(2, '0');
  final hours = total.inHours;
  if (hours == 0) return '${total.inMinutes}:$seconds';
  final minutes = total.inMinutes.remainder(60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}

/// The direction-aware status line.
///
/// The same stored status means different things to each side. A caller who
/// hangs up before the callee answers stores `cancelled` locally while the
/// callee stores `missed`, and a `declined` row is "you declined" on the
/// device that declined but "call declined" on the caller's.
String callTimelineStatusLabel(
  ConversationCallTimelineEntry entry,
  AppLocalizations l10n,
) {
  final isIncoming = entry.direction == ConversationCallDirection.incoming;
  return switch (entry.status) {
    ConversationCallStatus.completed => l10n.call_row_voice_call,
    ConversationCallStatus.missed =>
      isIncoming ? l10n.call_row_missed : l10n.call_row_no_answer,
    ConversationCallStatus.declined =>
      isIncoming ? l10n.call_row_you_declined : l10n.call_row_declined,
    ConversationCallStatus.busy =>
      isIncoming ? l10n.call_row_missed : l10n.call_row_busy,
    ConversationCallStatus.cancelled =>
      isIncoming ? l10n.call_row_missed : l10n.call_row_cancelled,
    ConversationCallStatus.failed => l10n.call_row_failed,
  };
}

/// The full row text. Talk time is appended only for a call that connected,
/// so a stray duration on an unconnected row can never surface.
String callTimelineRowText(
  ConversationCallTimelineEntry entry,
  AppLocalizations l10n,
) {
  final label = callTimelineStatusLabel(entry, l10n);
  final duration = entry.duration;
  if (duration == null || entry.status != ConversationCallStatus.completed) {
    return label;
  }
  return l10n.call_row_with_duration(label, formatCallDuration(duration));
}

IconData _callTimelineIcon(ConversationCallTimelineEntry entry) {
  final isIncoming = entry.direction == ConversationCallDirection.incoming;
  return switch (entry.status) {
    ConversationCallStatus.completed =>
      isIncoming ? Icons.call_received : Icons.call_made,
    ConversationCallStatus.missed ||
    ConversationCallStatus.busy ||
    ConversationCallStatus.cancelled =>
      isIncoming ? Icons.call_missed : Icons.call_missed_outgoing,
    ConversationCallStatus.declined => Icons.call_end,
    ConversationCallStatus.failed => Icons.error_outline,
  };
}

class CallTimelineRow extends StatelessWidget {
  const CallTimelineRow({super.key, required this.entry});

  final ConversationCallTimelineEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final readableColors = context.backgroundReadableColors;
    final text = callTimelineRowText(entry, l10n);

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: readableColors.surfaceSubtle,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: readableColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _callTimelineIcon(entry),
              size: 14,
              color: readableColors.textMuted,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: readableColors.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
