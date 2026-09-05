import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/call/data/call_history_conversation_timeline_source.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_timeline_entry.dart';

/// 405 follow-up: the conversation must learn that a call was just written.
///
/// Device 2026-09-05 (captures `fresh-260905221748`): every call logged
/// `CALL_TERMINAL_CLEANUP_RESULT`, so the row WAS projected, and no
/// `CHAT_CALL_TIMELINE_LOAD_SKIPPED` was emitted, so the read worked. The chat
/// still showed nothing new, because a call taken from inside the chat leaves
/// the screen mounted: nothing re-read the table. The source therefore carries
/// a change signal that fires AFTER the projector's insert.
void main() {
  CallHistoryEntry entry(String id) {
    final startedAt = DateTime.utc(2026, 2, 9, 15, 30);
    return CallHistoryEntry(
      callId: CallId.parse('a2f0a1d6-0000-4000-8000-00000000000$id'),
      contactAccountPeerId: '12D3KooWTestPeerId1234567890',
      direction: CallDirection.incoming,
      terminalReason: CallEndReason.callerCancelled,
      status: CallHistoryStatus.cancelled,
      startedAt: startedAt,
      endedAt: startedAt.add(const Duration(seconds: 20)),
      transportRoute: null,
      createdAt: startedAt,
      updatedAt: startedAt,
    );
  }

  test('TC-405-40 the source republishes the injected change signal', () async {
    final controller = StreamController<void>.broadcast();
    addTearDown(controller.close);
    final source = CallHistoryConversationTimelineSource(
      _Repository([entry('1')]),
      changes: controller.stream,
    );

    final seen = <void>[];
    final subscription = source.changes.listen(seen.add);
    addTearDown(subscription.cancel);

    controller.add(null);
    controller.add(null);
    await Future<void>.delayed(Duration.zero);

    expect(seen, hasLength(2));
  });

  test('TC-405-41 a source built without a signal never emits', () async {
    final source = CallHistoryConversationTimelineSource(
      _Repository([entry('1')]),
    );
    var emitted = false;
    final subscription = source.changes.listen((_) => emitted = true);
    addTearDown(subscription.cancel);

    await Future<void>.delayed(Duration.zero);

    expect(emitted, isFalse);
  });

  test('TC-405-42 rows still project after a change signal', () async {
    final controller = StreamController<void>.broadcast();
    addTearDown(controller.close);
    final source = CallHistoryConversationTimelineSource(
      _Repository([entry('1')]),
      changes: controller.stream,
    );

    final rows = await source.listCallsForContact(
      '12D3KooWTestPeerId1234567890',
    );

    expect(rows, hasLength(1));
    expect(rows.single.status, ConversationCallStatus.cancelled);
    expect(rows.single.direction, ConversationCallDirection.incoming);
  });
}

class _Repository implements CallHistoryRepository {
  _Repository(this.rows);

  final List<CallHistoryEntry> rows;

  @override
  Future<CallHistoryEntry?> getByCallId(CallId callId) async =>
      rows.where((row) => row.callId == callId).firstOrNull;

  @override
  Future<List<CallHistoryEntry>> listForContact(
    String contactAccountPeerId,
  ) async => rows
      .where((row) => row.contactAccountPeerId == contactAccountPeerId)
      .toList(growable: false);

  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) async => rows.add(entry);
}
