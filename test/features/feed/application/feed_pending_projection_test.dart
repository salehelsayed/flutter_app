import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/feed/application/feed_pending_projection.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';

void main() {
  final captured = <Map<String, dynamic>>[];

  setUp(() {
    captured.clear();
    debugSetFlowEventSink(captured.add);
  });
  tearDown(() {
    debugSetFlowEventSink(null);
  });

  ThreadMessage line({
    required String id,
    required int tsMs,
    bool incoming = true,
    bool unread = true,
    bool deleted = false,
  }) {
    return ThreadMessage(
      id: id,
      text: 'line-$id',
      time: '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(tsMs),
      isUnread: unread,
      isIncoming: incoming,
      isDeleted: deleted,
    );
  }

  ThreadFeedItem thread(String peerId, List<ThreadMessage> messages) {
    return ThreadFeedItem(
      id: 'thread_$peerId',
      timestamp: messages.last.timestamp,
      contactPeerId: peerId,
      contactUsername: peerId,
      messages: messages,
    );
  }

  List<Map<String, dynamic>> eventsNamed(String name) =>
      captured.where((e) => e['event'] == name).toList();

  test('TC-01: keeps only the pending thread (excludes read/answered/cleared)',
      () {
    // (a) unread incoming → pending
    final a = thread('A', [line(id: 'a1', tsMs: 100)]);
    // (b) all read → not pending
    final b = thread('B', [line(id: 'b1', tsMs: 100, unread: false)]);
    // (c) answered after the newest incoming → not pending
    final c = thread('C', [
      line(id: 'c1', tsMs: 100),
      line(id: 'c2', tsMs: 200, incoming: false, unread: false),
    ]);
    // (d) cleared (watermark == newest incoming) → not pending
    final d = thread('D', [line(id: 'd1', tsMs: 100)]);

    final result = projectPendingFeed(
      [a, b, c, d],
      <(String, String), int>{('contact', 'D'): 100},
    );

    expect(result, <FeedItem>[a]);
    expect(eventsNamed('FEED_PENDING_PROJECTED').single['details']['kept'], 1);
  });

  test('TC-02: a cleared thread (watermark >= newest incoming) is excluded',
      () {
    final d = thread('D', [line(id: 'd1', tsMs: 100)]);

    final result = projectPendingFeed(
      [d],
      <(String, String), int>{('contact', 'D'): 150},
    );

    expect(result, isEmpty);
    expect(eventsNamed('FEED_RESURFACE'), isEmpty);
    expect(eventsNamed('FEED_PENDING_PROJECTED').single['details']['kept'], 0);
  });

  test('TC-03: a cleared thread re-surfaces when a newer incoming arrives', () {
    // watermark 150; an incoming at 200 (> 150) re-surfaces it.
    final d = thread('D', [
      line(id: 'd1', tsMs: 100),
      line(id: 'd2', tsMs: 200),
    ]);

    final result = projectPendingFeed(
      [d],
      <(String, String), int>{('contact', 'D'): 150},
    );

    expect(result, <FeedItem>[d]);
    // Distinct-event discriminator: RESURFACE AND NOT kept:0.
    expect(eventsNamed('FEED_RESURFACE'), isNotEmpty);
    expect(
      eventsNamed('FEED_PENDING_PROJECTED').single['details']['kept'],
      isNot(0),
    );
  });

  test('connection letter: dropped iff a cleared row is present (presence)', () {
    final conn = ConnectionFeedItem(
      id: 'connection_Z',
      timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      contactPeerId: 'Z',
      contactUsername: 'Zed',
    );

    expect(
      projectPendingFeed([conn], const <(String, String), int>{}),
      <FeedItem>[conn],
      reason: 'no cleared row → shown',
    );
    expect(
      projectPendingFeed(
        [conn],
        <(String, String), int>{('connection', 'Z'): 1},
      ),
      isEmpty,
      reason: 'cleared row present → dropped',
    );
  });

  test('connection letter is suppressed when a 1:1 thread exists for the peer',
      () {
    final conn = ConnectionFeedItem(
      id: 'connection_A',
      timestamp: DateTime.fromMillisecondsSinceEpoch(50),
      contactPeerId: 'A',
      contactUsername: 'Alice',
    );
    final t = thread('A', [line(id: 'a1', tsMs: 100)]);

    final result = projectPendingFeed(
      [conn, t],
      const <(String, String), int>{},
    );

    // Only the thread letter — never a "tap to say hi" card for a peer we
    // already have a conversation with.
    expect(result, <FeedItem>[t]);
    expect(result.whereType<ConnectionFeedItem>(), isEmpty);
  });
}
