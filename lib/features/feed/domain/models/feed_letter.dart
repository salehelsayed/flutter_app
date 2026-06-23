import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/models/letter_line.dart';
import 'package:flutter_app/features/feed/domain/utils/group_sender_runs.dart';

/// View-model for a single pending-reply "letter" rendered in the redesigned
/// Feed inbox.
///
/// Sealed so call sites can exhaustively switch over the three letter kinds:
/// [OneToOneLetter], [GroupLetter], and [SystemLetter].
sealed class FeedLetter {
  const FeedLetter();
}

/// A 1:1 pending-reply letter.
///
/// [lines] is derived from the UNCAPPED unread incoming messages of the source
/// thread (never the capped `previewMessages`). Each line carries its body text
/// AND its media so the feed can render images/voice/video the same way the
/// 1:1 chat does.
class OneToOneLetter extends FeedLetter {
  final String peerId;
  final String displayName;
  final List<LetterLine> lines;

  const OneToOneLetter({
    required this.peerId,
    required this.displayName,
    required this.lines,
  });

  factory OneToOneLetter.fromThread(ThreadFeedItem item) {
    return OneToOneLetter(
      peerId: item.contactPeerId,
      displayName: item.contactUsername,
      lines: item.unreadMessages
          .map(
            (m) => LetterLine(messageId: m.id, text: m.text, media: m.media),
          )
          .toList(),
    );
  }

  /// The body texts of each line (back-compat convenience for callers/tests
  /// that only care about the text content).
  List<String> get texts => lines.map((l) => l.text).toList();

  /// True when more than one unread line is stacked in this letter.
  bool get isStacked => lines.length > 1;
}

/// A group pending-reply letter, with consecutive same-sender lines collapsed
/// into [runs].
class GroupLetter extends FeedLetter {
  final String groupId;
  final String groupName;
  final bool canWrite;
  final List<SenderRun> runs;

  const GroupLetter({
    required this.groupId,
    required this.groupName,
    required this.canWrite,
    required this.runs,
  });

  factory GroupLetter.fromThread(GroupThreadFeedItem item) {
    return GroupLetter(
      groupId: item.groupId,
      groupName: item.groupName,
      canWrite: item.canWrite,
      runs: groupSenderRuns(item.unreadMessages),
    );
  }
}

/// A system letter representing a new connection or an introduction.
class SystemLetter extends FeedLetter {
  final String contactPeerId;
  final String displayName;
  final String? introducedBy;
  final String? introducedByPeerId;

  const SystemLetter({
    required this.contactPeerId,
    required this.displayName,
    this.introducedBy,
    this.introducedByPeerId,
  });

  factory SystemLetter.fromConnection(ConnectionFeedItem item) {
    return SystemLetter(
      contactPeerId: item.contactPeerId,
      displayName: item.contactUsername,
      introducedBy: item.introducedBy,
      introducedByPeerId: item.introducedByPeerId,
    );
  }

  /// True when this letter represents an introduction (carries an introducer).
  bool get isIntroduction => introducedBy != null;
}
