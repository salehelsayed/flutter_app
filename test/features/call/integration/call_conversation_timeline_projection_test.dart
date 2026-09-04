import 'package:flutter_app/features/call/data/call_history_conversation_timeline_source.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/conversation/application/load_conversation_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_timeline_entry.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Messages implements MessageRepository {
  _Messages(this.rows);

  final List<ConversationMessage> rows;

  @override
  Future<List<ConversationMessage>> getMessagesForContact(
    String contactPeerId,
  ) async => rows
      .where((message) => message.contactPeerId == contactPeerId)
      .toList(growable: false);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _History implements CallHistoryRepository {
  _History(this.rows);

  final List<CallHistoryEntry> rows;
  int listCalls = 0;
  bool failLoads = false;

  @override
  Future<CallHistoryEntry?> getByCallId(CallId callId) async => null;

  @override
  Future<List<CallHistoryEntry>> listForContact(String contactPeerId) async {
    listCalls++;
    if (failLoads) throw StateError('history unavailable');
    return rows;
  }

  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) async {}
}

ConversationMessage _message({required String id, required DateTime at}) =>
    ConversationMessage(
      id: id,
      contactPeerId: 'contact-a',
      senderPeerId: 'contact-a',
      text: 'ordinary chat',
      timestamp: at.toUtc().toIso8601String(),
      status: 'delivered',
      isIncoming: true,
      createdAt: at.toUtc().toIso8601String(),
    );

CallHistoryEntry _call({
  required String id,
  required DateTime at,
  String contactPeerId = 'contact-a',
  CallHistoryStatus status = CallHistoryStatus.completed,
}) => CallHistoryEntry(
  callId: CallId.parse(id),
  contactAccountPeerId: contactPeerId,
  direction: CallDirection.incoming,
  terminalReason: status == CallHistoryStatus.missed
      ? CallEndReason.noAnswer
      : CallEndReason.remoteHangup,
  status: status,
  startedAt: at,
  connectedAt: status == CallHistoryStatus.missed
      ? null
      : at.add(const Duration(seconds: 1)),
  endedAt: at.add(const Duration(seconds: 11)),
  transportRoute: CallRouteClass.ephemeralMailbox,
  createdAt: at.add(const Duration(seconds: 11)),
  updatedAt: at.add(const Duration(seconds: 11)),
);

void main() {
  test(
    'typed production loader merges chat and privacy-safe call rows',
    () async {
      final start = DateTime.utc(2026, 8, 30, 12);
      final messages = _Messages(<ConversationMessage>[
        _message(id: 'message-one', at: start),
        _message(id: 'message-two', at: start.add(const Duration(minutes: 2))),
      ]);
      final history = _History(<CallHistoryEntry>[
        _call(
          id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
          at: start.add(const Duration(minutes: 1)),
        ),
      ]);

      final timeline = await loadConversationTimeline(
        messageRepo: messages,
        contactPeerId: 'contact-a',
        callTimelineSource: CallHistoryConversationTimelineSource(history),
        includeCalls: true,
      );

      expect(timeline.map((entry) => entry.stableId), <String>[
        'message:message-one',
        'call:bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        'message:message-two',
      ]);
      final call = timeline[1] as ConversationCallTimelineEntry;
      expect(call.status, ConversationCallStatus.completed);
      expect(call.duration, const Duration(seconds: 10));
      expect(call.toString(), isNot(contains(call.callId)));
      expect(call.toString(), isNot(contains(call.contactPeerId)));
      expect(history.listCalls, 1);
    },
  );

  test(
    'call projection is default-off and preserves message ordering',
    () async {
      final at = DateTime.utc(2026, 8, 30, 12);
      final original = <ConversationMessage>[
        _message(id: 'message-z', at: at),
        _message(id: 'message-a', at: at),
      ];
      final history = _History(<CallHistoryEntry>[
        _call(
          id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          at: at,
          status: CallHistoryStatus.missed,
        ),
      ])..failLoads = true;

      final timeline = await loadConversationTimeline(
        messageRepo: _Messages(original),
        contactPeerId: 'contact-a',
        callTimelineSource: CallHistoryConversationTimelineSource(history),
      );

      expect(
        timeline.whereType<ConversationMessageTimelineEntry>().map(
          (entry) => entry.message,
        ),
        orderedEquals(original),
      );
      expect(timeline.whereType<ConversationCallTimelineEntry>(), isEmpty);
      expect(history.listCalls, 0);
    },
  );

  test('enabled call projection cannot break ordinary chat loading', () async {
    final at = DateTime.utc(2026, 8, 30, 12);
    final history = _History(const <CallHistoryEntry>[])..failLoads = true;

    final timeline = await loadConversationTimeline(
      messageRepo: _Messages(<ConversationMessage>[
        _message(id: 'message-one', at: at),
      ]),
      contactPeerId: 'contact-a',
      callTimelineSource: CallHistoryConversationTimelineSource(history),
      includeCalls: true,
    );

    expect(timeline.single, isA<ConversationMessageTimelineEntry>());
    expect(history.listCalls, 1);
  });

  test('call source drops a repository row from another contact', () async {
    final at = DateTime.utc(2026, 8, 30, 12);
    final history = _History(<CallHistoryEntry>[
      _call(
        id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        at: at,
        contactPeerId: 'contact-b',
      ),
    ]);

    final timeline = await loadConversationTimeline(
      messageRepo: _Messages(const <ConversationMessage>[]),
      contactPeerId: 'contact-a',
      callTimelineSource: CallHistoryConversationTimelineSource(history),
      includeCalls: true,
    );

    expect(timeline, isEmpty);
  });
}
