import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/models/letter_line.dart';

/// A consecutive run of incoming bubbles from a single sender within a group
/// thread.
class SenderRun {
  /// Stable sender key: [ThreadMessage.senderPeerId] when present, otherwise
  /// [ThreadMessage.senderUsername], otherwise the empty string.
  final String senderPeerId;

  /// Display name: [ThreadMessage.senderUsername] when present, else empty.
  final String senderName;

  /// The run's consecutive bubble lines (text + media), in order.
  final List<LetterLine> lines;

  const SenderRun({
    required this.senderPeerId,
    required this.senderName,
    required this.lines,
  });

  /// The body texts of each line (back-compat convenience).
  List<String> get texts => lines.map((l) => l.text).toList();
}

/// Collapses CONSECUTIVE same-sender INCOMING (non-deleted) lines into runs,
/// preserving order, with NO cap.
///
/// Outgoing and deleted messages are dropped. Runs are keyed by
/// `senderPeerId ?? senderUsername` so that a new run starts whenever the
/// effective sender changes.
List<SenderRun> groupSenderRuns(List<ThreadMessage> messages) {
  final runs = <SenderRun>[];

  String? currentKey;
  String? currentName;
  List<LetterLine>? currentLines;

  void flush() {
    if (currentLines != null) {
      runs.add(
        SenderRun(
          senderPeerId: currentKey ?? '',
          senderName: currentName ?? '',
          lines: currentLines!,
        ),
      );
    }
    currentKey = null;
    currentName = null;
    currentLines = null;
  }

  for (final message in messages) {
    if (!message.isIncoming || message.isDeleted) {
      continue;
    }

    final key = message.senderPeerId ?? message.senderUsername ?? '';
    final name = message.senderUsername ?? '';

    if (currentLines == null || key != currentKey) {
      flush();
      currentKey = key;
      currentName = name;
      currentLines = <LetterLine>[];
    }

    currentLines!.add(
      LetterLine(messageId: message.id, text: message.text, media: message.media),
    );
  }

  flush();

  return runs;
}
