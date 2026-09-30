import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/debug/production_journeys/production_group_reaction_capture.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';

void main() {
  const reaction = MessageReaction(
    id: 'reaction',
    messageId: 'message',
    emoji: '🔥',
    senderPeerId: 'bob',
    timestamp: '2026-09-28T00:00:00Z',
    createdAt: '2026-09-28T00:00:01Z',
  );
  late StreamController<ReactionChange> stream;
  late ProductionGroupReactionCapture capture;
  void start() {
    stream = StreamController<ReactionChange>.broadcast(sync: true);
    capture = ProductionGroupReactionCapture(
      groupId: 'group',
      messageId: 'message',
      senderPeerId: 'bob',
      changes: stream.stream,
    );
  }

  void outcome({
    String group = 'group',
    String message = 'message',
    String sender = 'bob',
    String result = 'success',
  }) {
    String digest(String value) =>
        sha256.convert(utf8.encode(value)).toString();
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_SEND_RESULT',
      details: {
        'groupSha256': digest(group),
        'messageSha256': digest(message),
        'senderIdentitySha256': digest(sender),
        'outcome': result,
        'reactionId': 'reaction',
      },
    );
  }

  tearDown(() {
    capture.dispose();
    unawaited(stream.close());
    debugSetFlowEventSink(null);
  });

  test('captures exact outcome and real receiver stream independently', () {
    start();
    outcome(result: 'queuedForRetry');
    expect((capture.snapshot()['changes'] as List), isEmpty);
    stream.add(ReactionChange.upsert(reaction));
    final result = capture.snapshot();
    expect((result['outcomes'] as List).single['outcome'], 'queuedForRetry');
    expect((result['changes'] as List).single['reactionId'], 'reaction');
    (result['changes'] as List).clear();
    expect(capture.snapshot()['changes'], hasLength(1));
  });
  test('foreign group, target and sender cannot supply operation evidence', () {
    start();
    outcome(group: 'foreign');
    outcome(message: 'foreign');
    outcome(sender: 'foreign');
    stream.add(
      ReactionChange.removed(messageId: 'foreign', senderPeerId: 'bob'),
    );
    stream.add(
      ReactionChange.removed(messageId: 'message', senderPeerId: 'foreign'),
    );
    expect(capture.snapshot()['outcomes'], isEmpty);
    expect(capture.snapshot()['changes'], isEmpty);
  });
  test('overflow is failure rather than truncated passing evidence', () {
    start();
    for (var i = 0; i < 257; i++) {
      stream.add(ReactionChange.upsert(reaction));
    }
    expect(capture.snapshot, throwsStateError);
  });
  test('stream errors and disposal invalidate evidence', () {
    start();
    stream.addError(StateError('listener failed'), StackTrace.current);
    expect(capture.snapshot, throwsStateError);
    capture.dispose();
    capture.dispose();
    expect(capture.snapshot, throwsStateError);
  });
  test('expiry releases capture and refuses stale evidence', () {
    fakeAsync((clock) {
      start();
      clock.elapse(const Duration(minutes: 3));
      expect(capture.snapshot, throwsStateError);
    });
  });
}
