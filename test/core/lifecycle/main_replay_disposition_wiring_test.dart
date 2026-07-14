import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/main.dart' as app;

/// Phase G1 of plan 120 — lock the `main.dart` replay-closure wiring constants.
///
/// The literal 118 bug was a flipped `suppressNotification` boolean on one of
/// the three replay closures wired into `P2PServiceImpl(`. Every 118 behavioral
/// test injects its OWN spy/test closures into `P2PServiceImpl`; the real
/// `main.dart` closures are never exercised, so flipping a production constant
/// leaves the whole suite green.
///
/// This is the PRIMARY (recommended) strategy from plan 120 §G1: a source-text
/// wiring lock that mirrors `main_resume_group_upload_wiring_test.dart` — read
/// `lib/main.dart` as a string, slice each closure's argument block, and assert
/// the `suppressNotification:` token. We do NOT extract a builder function from
/// `main.dart` (doc 118 §"dropped Phase 0" rejected that as testing-the-mock;
/// it is the OQ-1 alternative, not the default).
///
/// Resilience: match on the closure label + the `suppressNotification:` token
/// within the sliced block, NOT exact whitespace/line numbers (those drift). An
/// intentional rename of a closure label requires updating this lock.
void main() {
  // The three replay-chat closure labels, in the order they appear in
  // `P2PServiceImpl(` in main.dart. Each block is sliced from its own label to
  // the NEXT label below, so the recovery block's `suppressNotification: true`
  // is never mistaken for a live block's value.
  const recoveredLabel = 'replayRecoveredInboxChatMessage:';
  const liveLanLabel = 'replayLiveLanChatMessage:';
  const liveDirectLabel = 'replayLiveDirectChatMessage:';
  // The next closure after the three chat closures (a non-chat boundary) —
  // used to bound the final (live-direct) block.
  const introLabel = 'replayRecoveredInboxIntroductionMessage:';

  Future<String> readMain() => File('lib/main.dart').readAsString();

  String sliceBlock(String source, String startLabel, String endLabel) {
    final start = source.indexOf(startLabel);
    expect(
      start,
      isNonNegative,
      reason: 'expected closure label "$startLabel" in lib/main.dart',
    );
    final end = source.indexOf(endLabel, start + startLabel.length);
    expect(
      end,
      greaterThan(start),
      reason: 'expected boundary label "$endLabel" after "$startLabel"',
    );
    return source.substring(start, end);
  }

  test(
    'main.dart wires replayLiveDirectChatMessage with suppressNotification: false',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final mainSource = await readMain();
      // Bound the live-direct block by the next (non-chat) closure label.
      final block = sliceBlock(mainSource, liveDirectLabel, introLabel);

      expect(
        block,
        contains('suppressNotification: false'),
        reason:
            'live direct (1:1) replay must be notify-capable; flipping this to '
            'true is the literal 118 regression (recipient gets no notification).',
      );
      expect(
        block,
        isNot(contains('suppressNotification: true')),
        reason: 'the live-direct block must not suppress notifications',
      );
    },
  );

  test(
    'main.dart wires replayLiveLanChatMessage with suppressNotification: false',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final mainSource = await readMain();
      // The live-LAN block is bounded by the next chat label (live-direct).
      final block = sliceBlock(mainSource, liveLanLabel, liveDirectLabel);

      expect(
        block,
        contains('suppressNotification: false'),
        reason:
            'live LAN replay must be notify-capable, mirroring the live-direct path',
      );
      expect(
        block,
        isNot(contains('suppressNotification: true')),
        reason: 'the live-LAN block must not suppress notifications',
      );
    },
  );

  test(
    'main.dart wires replayRecoveredInboxChatMessage with suppressNotification: true',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final mainSource = await readMain();
      // The recovery block is bounded by the next chat label (live-LAN).
      final block = sliceBlock(mainSource, recoveredLabel, liveLanLabel);

      expect(
        block,
        contains('suppressNotification: true'),
        reason:
            'recovered/store-and-forward inbox replay must suppress notifications '
            '(calm: a relay drain on resume must not re-alert for old messages).',
      );
      expect(
        block,
        isNot(contains('suppressNotification: false')),
        reason: 'the recovery block must suppress notifications',
      );
    },
  );

  test(
    'main.dart still wires all three replay-chat closures (deletion guard)',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final mainSource = await readMain();
      for (final label in const [
        recoveredLabel,
        liveLanLabel,
        liveDirectLabel,
      ]) {
        expect(
          mainSource.indexOf(label),
          isNonNegative,
          reason:
              'replay-chat closure "$label" must remain wired into P2PServiceImpl(',
        );
        // Exactly one occurrence — a duplicate label would break the slicing
        // contract above and likely indicates a copy/paste wiring error.
        expect(
          label.allMatches(mainSource).length,
          1,
          reason: 'expected exactly one "$label" wiring in lib/main.dart',
        );
      }
    },
  );

  test(
    'main reaction replay publishes the persisted change to the UI listener',
    () async {
      final mainSource = await readMain();
      final replayBlock = sliceBlock(
        mainSource,
        'Future<RecoveredInboxReplayOutcome> replayInboxReaction(',
        'ingestStagedPushEnvelopesUseCase.replayReactionMessage =',
      );

      expect(replayBlock, contains('final (result, change)'));
      expect(
        replayBlock,
        contains('publishPersistedReactionChange?.call(change)'),
        reason:
            'staged/live replay must update an already-mounted conversation '
            'without re-running persistence or notification policy',
      );
      expect(
        mainSource,
        contains(
          'publishPersistedReactionChange = '
          'reactionListener.publishPersistedChange',
        ),
      );
    },
  );
}
