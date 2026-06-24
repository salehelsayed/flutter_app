import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/conversation/domain/utils/message_run_grouping.dart';

void main() {
  // A fixed base timestamp used across the gap-based cases.
  final base = DateTime.utc(2026, 6, 21, 12, 0, 0);

  group('messageRunStartsNewRun', () {
    // TC-01 — sender-change break.
    test('returns true when sender changes', () {
      final result = messageRunStartsNewRun(
        senderPeerId: 'B',
        timestamp: base.add(const Duration(minutes: 1)),
        isSystemRow: false,
        prevSenderPeerId: 'A',
        prevTimestamp: base,
        prevBreaks: false,
      );
      expect(result, isTrue);
    });

    // TC-02 — same sender within threshold continues the run.
    test('returns false for same sender within threshold', () {
      final result = messageRunStartsNewRun(
        senderPeerId: 'A',
        timestamp: base.add(const Duration(minutes: 4, seconds: 59)),
        isSystemRow: false,
        prevSenderPeerId: 'A',
        prevTimestamp: base,
        prevBreaks: false,
      );
      expect(result, isFalse);
    });

    // TC-03 — boundary table at the 5-minute threshold.
    group('breaks at exactly/over 5 minutes (boundary table)', () {
      bool runFor(Duration gap) => messageRunStartsNewRun(
            senderPeerId: 'A',
            timestamp: base.add(gap),
            isSystemRow: false,
            prevSenderPeerId: 'A',
            prevTimestamp: base,
            prevBreaks: false,
          );

      test('4:59 -> false (continues)', () {
        expect(runFor(const Duration(minutes: 4, seconds: 59)), isFalse);
      });

      test('5:00 -> true (breaks at the boundary)', () {
        expect(runFor(const Duration(minutes: 5)), isTrue);
      });

      test('5:01 -> true (breaks over the boundary)', () {
        expect(runFor(const Duration(minutes: 5, seconds: 1)), isTrue);
      });
    });

    // TC-04 — date separator (prevBreaks) forces a break even when the
    // sender is unchanged and the gap is tiny.
    test('returns true after a date separator (prevBreaks=true)', () {
      final result = messageRunStartsNewRun(
        senderPeerId: 'A',
        timestamp: base.add(const Duration(seconds: 30)),
        isSystemRow: false,
        prevSenderPeerId: 'A',
        prevTimestamp: base,
        prevBreaks: true,
      );
      expect(result, isTrue);
    });

    // TC-05 — system row breaks in both directions.
    group('system row breaks the run', () {
      test('current row is a system row -> true', () {
        final result = messageRunStartsNewRun(
          senderPeerId: 'A',
          timestamp: base.add(const Duration(seconds: 30)),
          isSystemRow: true,
          prevSenderPeerId: 'A',
          prevTimestamp: base,
          prevBreaks: false,
        );
        expect(result, isTrue);
      });

      test('previous row was a system row (prevBreaks) -> true', () {
        // The caller sets prevBreaks=true when the previous emitted row was a
        // system row, so the next ordinary message starts a fresh run.
        final result = messageRunStartsNewRun(
          senderPeerId: 'A',
          timestamp: base.add(const Duration(seconds: 30)),
          isSystemRow: false,
          prevSenderPeerId: 'A',
          prevTimestamp: base,
          prevBreaks: true,
        );
        expect(result, isTrue);
      });
    });
  });

  group('messageRunChrome', () {
    // TC-06 — chrome policy: avatar+name only for group, incoming, first.
    test('group incoming first-in-run shows avatar and name', () {
      final chrome = messageRunChrome(
        surface: MessageRunSurface.group,
        isOutgoing: false,
        isFirstInGroup: true,
      );
      expect(chrome.showAvatar, isTrue);
      expect(chrome.showSenderName, isTrue);
    });

    test('group incoming non-first hides both', () {
      final chrome = messageRunChrome(
        surface: MessageRunSurface.group,
        isOutgoing: false,
        isFirstInGroup: false,
      );
      expect(chrome.showAvatar, isFalse);
      expect(chrome.showSenderName, isFalse);
    });

    test('group outgoing first hides both', () {
      final chrome = messageRunChrome(
        surface: MessageRunSurface.group,
        isOutgoing: true,
        isFirstInGroup: true,
      );
      expect(chrome.showAvatar, isFalse);
      expect(chrome.showSenderName, isFalse);
    });

    test('group outgoing non-first hides both', () {
      final chrome = messageRunChrome(
        surface: MessageRunSurface.group,
        isOutgoing: true,
        isFirstInGroup: false,
      );
      expect(chrome.showAvatar, isFalse);
      expect(chrome.showSenderName, isFalse);
    });

    test('1:1 incoming first hides both (no avatars in 1:1)', () {
      final chrome = messageRunChrome(
        surface: MessageRunSurface.oneToOne,
        isOutgoing: false,
        isFirstInGroup: true,
      );
      expect(chrome.showAvatar, isFalse);
      expect(chrome.showSenderName, isFalse);
    });

    test('1:1 outgoing first hides both', () {
      final chrome = messageRunChrome(
        surface: MessageRunSurface.oneToOne,
        isOutgoing: true,
        isFirstInGroup: true,
      );
      expect(chrome.showAvatar, isFalse);
      expect(chrome.showSenderName, isFalse);
    });

    test('1:1 incoming non-first hides both', () {
      final chrome = messageRunChrome(
        surface: MessageRunSurface.oneToOne,
        isOutgoing: false,
        isFirstInGroup: false,
      );
      expect(chrome.showAvatar, isFalse);
      expect(chrome.showSenderName, isFalse);
    });
  });

  group('kMessageRunGapThreshold', () {
    // TC-07 — the named threshold constant is exactly 5 minutes.
    test('equals 5 minutes', () {
      expect(kMessageRunGapThreshold, const Duration(minutes: 5));
    });
  });

  // TC-159-02 — the run-grouping pass consumes the model-cached DateTime
  // (1:1 `ConversationMessage.parsedTimestamp`, group `GroupMessage.timestamp`),
  // never a fresh inline parse, and the 1:1 malformed-timestamp case routes to
  // the documented fail-safe run-break.
  group('TC-159-02 run-grouping consumes the model DateTime', () {
    ConversationMessage convMsg({
      required String id,
      required String senderPeerId,
      required String timestamp,
    }) => ConversationMessage(
      id: id,
      contactPeerId: 'c1',
      senderPeerId: senderPeerId,
      text: 'hi',
      timestamp: timestamp,
      status: 'sent',
      isIncoming: true,
      createdAt: timestamp,
    );

    GroupMessage groupMsg({
      required String id,
      required String senderPeerId,
      required DateTime timestamp,
    }) => GroupMessage(
      id: id,
      groupId: 'g1',
      senderPeerId: senderPeerId,
      text: 'hi',
      timestamp: timestamp,
      createdAt: timestamp,
    );

    test('1:1 grouping reads parsedTimestamp — same-sender 4:59 gap continues', () {
      final prev = convMsg(
        id: 'a',
        senderPeerId: 'A',
        timestamp: '2026-06-21T12:00:00.000Z',
      );
      final next = convMsg(
        id: 'b',
        senderPeerId: 'A',
        timestamp: '2026-06-21T12:04:59.000Z',
      );
      final startsNewRun = messageRunStartsNewRun(
        senderPeerId: next.senderPeerId,
        timestamp:
            next.parsedTimestamp ?? DateTime.fromMillisecondsSinceEpoch(0),
        isSystemRow: false,
        prevSenderPeerId: prev.senderPeerId,
        prevTimestamp: prev.parsedTimestamp,
        prevBreaks: false,
      );
      expect(startsNewRun, isFalse);
    });

    test('1:1 grouping reads parsedTimestamp — same-sender 5:00 gap breaks', () {
      final prev = convMsg(
        id: 'a',
        senderPeerId: 'A',
        timestamp: '2026-06-21T12:00:00.000Z',
      );
      final next = convMsg(
        id: 'b',
        senderPeerId: 'A',
        timestamp: '2026-06-21T12:05:00.000Z',
      );
      final startsNewRun = messageRunStartsNewRun(
        senderPeerId: next.senderPeerId,
        timestamp:
            next.parsedTimestamp ?? DateTime.fromMillisecondsSinceEpoch(0),
        isSystemRow: false,
        prevSenderPeerId: prev.senderPeerId,
        prevTimestamp: prev.parsedTimestamp,
        prevBreaks: false,
      );
      expect(startsNewRun, isTrue);
    });

    test(
      '1:1 malformed timestamp → parsedTimestamp null → epoch-0 fail-safe break',
      () {
        final prev = convMsg(
          id: 'a',
          senderPeerId: 'A',
          timestamp: '2026-06-21T12:00:00.000Z',
        );
        final next = convMsg(
          id: 'b',
          senderPeerId: 'A',
          timestamp: 'not-a-date',
        );
        // The screen substitutes epoch-0 when parsedTimestamp is null, which is
        // > 5 min from any real prev timestamp → forces a run break.
        expect(next.parsedTimestamp, isNull);
        final startsNewRun = messageRunStartsNewRun(
          senderPeerId: next.senderPeerId,
          timestamp:
              next.parsedTimestamp ?? DateTime.fromMillisecondsSinceEpoch(0),
          isSystemRow: false,
          prevSenderPeerId: prev.senderPeerId,
          prevTimestamp: prev.parsedTimestamp,
          prevBreaks: false,
        );
        expect(startsNewRun, isTrue);
      },
    );

    test('group grouping reads the model DateTime directly (no re-parse)', () {
      final base = DateTime.utc(2026, 6, 21, 12, 0, 0);
      final prev = groupMsg(id: 'a', senderPeerId: 'A', timestamp: base);
      final next = groupMsg(
        id: 'b',
        senderPeerId: 'A',
        timestamp: base.add(const Duration(minutes: 5)),
      );
      // GroupMessage.timestamp is already a DateTime — fed straight in.
      expect(next.timestamp, isA<DateTime>());
      final startsNewRun = messageRunStartsNewRun(
        senderPeerId: next.senderPeerId,
        timestamp: next.timestamp,
        isSystemRow: false,
        prevSenderPeerId: prev.senderPeerId,
        prevTimestamp: prev.timestamp,
        prevBreaks: false,
      );
      expect(startsNewRun, isTrue);
    });
  });

  group('messageRunBottomSpacing (137 follow-up)', () {
    test('a non-last (mid-run) message uses the tight intra-run gap', () {
      expect(
        messageRunBottomSpacing(isLastInGroup: false, runSeparation: 16),
        kMessageRunTightSpacing,
      );
      // The separation value is irrelevant for a non-last message.
      expect(
        messageRunBottomSpacing(isLastInGroup: false, runSeparation: 12),
        kMessageRunTightSpacing,
      );
    });

    test('the last message of a run uses the surface separation gap', () {
      expect(
        messageRunBottomSpacing(isLastInGroup: true, runSeparation: 16),
        16,
      );
      expect(
        messageRunBottomSpacing(isLastInGroup: true, runSeparation: 12),
        12,
      );
    });

    test('the tight gap is strictly smaller than a typical separation', () {
      expect(kMessageRunTightSpacing, lessThan(12));
    });
  });
}
