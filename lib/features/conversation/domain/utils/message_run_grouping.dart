/// Pure run-grouping logic shared by the 1:1 and group conversation screens.
///
/// A "run" is a sequence of consecutive same-sender message rows that should be
/// rendered as a single grouped conversation turn (one avatar/name in groups,
/// stacked corner radii, tightened spacing). This file holds only side-effect
/// free helpers so both screens compute identical run boundaries.
library;

/// The maximum gap between two same-sender messages that still keeps them in the
/// same run. A gap >= this threshold starts a fresh run.
const Duration kMessageRunGapThreshold = Duration(minutes: 5);

/// Which conversation surface a run belongs to. Drives chrome (avatar/name)
/// policy: groups show one avatar/name per incoming run; 1:1 shows none.
enum MessageRunSurface { oneToOne, group }

/// Returns `true` when [timestamp]/[senderPeerId] should start a NEW run
/// relative to the previously emitted message row.
///
/// A new run starts when ANY of the following holds:
/// - there is no previous message row ([prevSenderPeerId] is null);
/// - the caller flags a break ([prevBreaks]) because the previous emitted row
///   was a date separator OR a system/membership row;
/// - the current row is itself a system row ([isSystemRow]);
/// - the sender changed ([prevSenderPeerId] != [senderPeerId]);
/// - the previous timestamp is unknown ([prevTimestamp] is null) — fail-safe
///   to a break so chrome is shown;
/// - the absolute gap from the previous message is at least [gapThreshold].
bool messageRunStartsNewRun({
  required String senderPeerId,
  required DateTime timestamp,
  required bool isSystemRow,
  String? prevSenderPeerId,
  DateTime? prevTimestamp,
  required bool prevBreaks,
  Duration gapThreshold = kMessageRunGapThreshold,
}) {
  if (prevSenderPeerId == null) return true;
  if (prevBreaks) return true;
  if (isSystemRow) return true;
  if (prevSenderPeerId != senderPeerId) return true;
  if (prevTimestamp == null) return true;
  return timestamp.difference(prevTimestamp).abs() >= gapThreshold;
}

/// The per-balloon chrome (leading avatar + sender name) for a run position.
class MessageRunChrome {
  final bool showAvatar;
  final bool showSenderName;

  const MessageRunChrome({
    required this.showAvatar,
    required this.showSenderName,
  });
}

/// Computes whether a balloon should render the run's avatar + sender name.
///
/// Avatar/name are shown ONLY for the first incoming balloon of a run in a
/// GROUP surface. Outgoing balloons never show chrome, and 1:1 surfaces never
/// show chrome in either direction.
MessageRunChrome messageRunChrome({
  required MessageRunSurface surface,
  required bool isOutgoing,
  required bool isFirstInGroup,
}) {
  final show =
      surface == MessageRunSurface.group && !isOutgoing && isFirstInGroup;
  return MessageRunChrome(showAvatar: show, showSenderName: show);
}

/// The tight vertical gap kept BELOW a message that is not the last of its run,
/// so the stacked corner radii (`kBubbleStackRadius`) read as one connected
/// group instead of equally-spaced separate bubbles (137 follow-up).
const double kMessageRunTightSpacing = 3.0;

/// The bottom gap for a message row. Messages mid-run (not [isLastInGroup]) are
/// packed tightly ([kMessageRunTightSpacing]) so the run reads as one connected
/// stack; the LAST message of a run instead uses the surface's [runSeparation]
/// gap so adjacent runs stay visually distinct. Standalone messages and
/// system/break rows are last-in-run, so they always get [runSeparation].
double messageRunBottomSpacing({
  required bool isLastInGroup,
  required double runSeparation,
}) {
  return isLastInGroup ? runSeparation : kMessageRunTightSpacing;
}
