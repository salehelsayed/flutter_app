// FDC-S4 — iOS pause-flush feasibility spike: host coverage for the Option-A
// bounded pause-flush prototype (the logic that is host-testable; the OS
// background-grant budget is device-only and lives in the RESULTS doc).
//
// Locks: the flush is OFF by default (invariant preserved), deposit-first /
// mark-failed-only-on-reject ordering, newest-first cap, the overall ceiling,
// the background-assertion begin/end lifecycle, and the flow-event instruments.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/lifecycle/handle_app_paused.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';

import '../../shared/fakes/in_memory_message_repository.dart';
import '../services/fake_p2p_service.dart';
import '../bridge/fake_bridge.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// A [FakeBridge] that grants an iOS-style background task for `bg:begin`
/// (returns a RAW task-id string, which `callBgBegin` accepts) and records the
/// `bg:end` task ids. An empty [grantTaskId] simulates the OS refusing the
/// assertion (Android / low-power), which `callBgBegin` maps to `null`.
class _FlushFakeBridge extends FakeBridge {
  _FlushFakeBridge({this.grantTaskId = '7'});

  final String grantTaskId;
  int bgBeginCount = 0;
  final List<String> bgEndTaskIds = [];

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'bg:begin') {
      bgBeginCount++;
      commandLog.add(cmd!);
      sentMessages.add(message);
      // Raw (non-JSON) string → callBgBegin treats it as the granted task id.
      return grantTaskId;
    }
    if (cmd == 'bg:end') {
      final payload = parsed['payload'] as Map<String, dynamic>?;
      final taskId = payload?['taskId'] as String?;
      if (taskId != null) bgEndTaskIds.add(taskId);
      commandLog.add(cmd!);
      sentMessages.add(message);
      return jsonEncode({'ok': true});
    }
    return super.send(message);
  }
}

/// Builds a `sending` outgoing row. [createdAt] drives the newest-first flush
/// ordering; [contactPeerId] is the deposit recipient.
ConversationMessage sendingMsg({
  required String id,
  required String contactPeerId,
  required String createdAt,
  String? wireEnvelope = 'env',
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'me',
    text: 'hi',
    timestamp: createdAt,
    status: 'sending',
    isIncoming: false,
    createdAt: createdAt,
    wireEnvelope: wireEnvelope,
  );
}

/// ISO-8601 timestamp at second [s] (controls newest-first ordering).
String at(int s) => '2026-01-01T00:00:${s.toString().padLeft(2, '0')}.000Z';

Future<String> statusOf(InMemoryMessageRepository repo, String id) async =>
    (await repo.getMessage(id))!.status;

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  group('FDC-S4 pause-flush — DISABLED (default): invariant preserved', () {
    test('omitting the flush params = legacy local-DB-only mark-failed',
        () async {
      final repo = InMemoryMessageRepository();
      await repo.saveMessage(
        sendingMsg(id: 'm1', contactPeerId: 'a', createdAt: at(1)),
      );

      final result = await handleAppPaused(messageRepo: repo);

      expect(result.flushDepositedCount, 0);
      expect(result.transitionedCount, 1);
      expect(await statusOf(repo, 'm1'), 'failed');
    });

    test('enablePauseFlush:false does NO network even when deps are provided',
        () async {
      final repo = InMemoryMessageRepository();
      await repo.saveMessage(
        sendingMsg(id: 'm1', contactPeerId: 'a', createdAt: at(1)),
      );
      final p2p = FakeP2PService();
      final bridge = _FlushFakeBridge();

      final result = await handleAppPaused(
        messageRepo: repo,
        p2pService: p2p,
        bridge: bridge,
        enablePauseFlush: false,
      );

      // No assertion taken, no deposit attempted — the "no network on pause"
      // invariant holds, and every row is marked failed as before.
      expect(bridge.bgBeginCount, 0);
      expect(p2p.storeInInboxCallCount, 0);
      expect(result.flushDepositedCount, 0);
      expect(await statusOf(repo, 'm1'), 'failed');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('FDC-S4 pause-flush — ENABLED: deposit-first / mark-on-reject', () {
    test('accepted deposit leaves the row in CUSTODY (not marked failed)',
        () async {
      final repo = InMemoryMessageRepository();
      await repo.saveMessage(
        sendingMsg(
          id: 'm1',
          contactPeerId: 'peer-a',
          createdAt: at(1),
          wireEnvelope: 'envelope-1',
        ),
      );
      final p2p = FakeP2PService()..storeInInboxResult = true;
      final bridge = _FlushFakeBridge();

      final result = await handleAppPaused(
        messageRepo: repo,
        p2pService: p2p,
        bridge: bridge,
        enablePauseFlush: true,
      );

      // Deposited to the recipient with the row's wire envelope.
      expect(p2p.storeInInboxLog.single.toPeerId, 'peer-a');
      expect(p2p.storeInInboxLog.single.message, 'envelope-1');
      // In custody → NOT marked failed.
      expect(result.flushDepositedCount, 1);
      expect(result.transitionedCount, 0);
      expect(await statusOf(repo, 'm1'), 'sending');
      // Assertion taken before the deposit and released after.
      expect(bridge.commandLog, containsAllInOrder(['bg:begin', 'bg:end']));
      expect(bridge.bgEndTaskIds, ['7']);
    });

    test('rejected deposit (storeInInbox=false) is marked FAILED', () async {
      final repo = InMemoryMessageRepository();
      await repo.saveMessage(
        sendingMsg(id: 'm1', contactPeerId: 'peer-a', createdAt: at(1)),
      );
      final p2p = FakeP2PService()..storeInInboxResult = false;
      final bridge = _FlushFakeBridge();

      final result = await handleAppPaused(
        messageRepo: repo,
        p2pService: p2p,
        bridge: bridge,
        enablePauseFlush: true,
      );

      expect(p2p.storeInInboxCallCount, 1);
      expect(result.flushDepositedCount, 0);
      expect(result.transitionedCount, 1);
      expect(await statusOf(repo, 'm1'), 'failed');
    });

    test('a throwing deposit is marked failed AND the assertion is released',
        () async {
      final repo = InMemoryMessageRepository();
      await repo.saveMessage(
        sendingMsg(id: 'm1', contactPeerId: 'peer-a', createdAt: at(1)),
      );
      final p2p = FakeP2PService()
        ..onStoreInInbox =
            (_, _, {int? timeoutMs}) async => throw StateError('bridge down');
      final bridge = _FlushFakeBridge();

      final result = await handleAppPaused(
        messageRepo: repo,
        p2pService: p2p,
        bridge: bridge,
        enablePauseFlush: true,
      );

      expect(result.flushDepositedCount, 0);
      expect(await statusOf(repo, 'm1'), 'failed');
      // finally{} released the bg assertion despite the throw.
      expect(bridge.bgEndTaskIds, ['7']);
    });

    test('rows without a wire envelope are not deposited (fall through)',
        () async {
      final repo = InMemoryMessageRepository();
      await repo.saveMessage(
        sendingMsg(id: 'with', contactPeerId: 'peer-a', createdAt: at(2)),
      );
      await repo.saveMessage(
        sendingMsg(
          id: 'without',
          contactPeerId: 'peer-b',
          createdAt: at(1),
          wireEnvelope: null,
        ),
      );
      final p2p = FakeP2PService()..storeInInboxResult = true;
      final bridge = _FlushFakeBridge();

      final result = await handleAppPaused(
        messageRepo: repo,
        p2pService: p2p,
        bridge: bridge,
        enablePauseFlush: true,
      );

      expect(p2p.storeInInboxLog.map((e) => e.toPeerId), ['peer-a']);
      expect(result.flushDepositedCount, 1);
      expect(await statusOf(repo, 'with'), 'sending');
      expect(await statusOf(repo, 'without'), 'failed');
    });

    test('mixed accept/reject in one flush: each row routed by its deposit',
        () async {
      final repo = InMemoryMessageRepository();
      await repo.saveMessage(
        sendingMsg(id: 'a', contactPeerId: 'peer-a', createdAt: at(3)),
      );
      await repo.saveMessage(
        sendingMsg(id: 'b', contactPeerId: 'peer-b', createdAt: at(2)),
      );
      await repo.saveMessage(
        sendingMsg(id: 'c', contactPeerId: 'peer-c', createdAt: at(1)),
      );
      // peer-b's deposit is rejected; peer-a and peer-c are accepted — the cap
      // covers all three, so the routing is purely per-deposit.
      final p2p = FakeP2PService()
        ..onStoreInInbox =
            (toPeerId, _, {int? timeoutMs}) async => toPeerId != 'peer-b';
      final bridge = _FlushFakeBridge();

      final result = await handleAppPaused(
        messageRepo: repo,
        p2pService: p2p,
        bridge: bridge,
        enablePauseFlush: true,
      );

      expect(result.flushDepositedCount, 2);
      expect(result.transitionedCount, 1);
      expect(await statusOf(repo, 'a'), 'sending'); // accepted → custody
      expect(await statusOf(repo, 'c'), 'sending'); // accepted → custody
      expect(await statusOf(repo, 'b'), 'failed'); // rejected → failed
    });

    test('no depositable rows → never touches the bridge', () async {
      final repo = InMemoryMessageRepository();
      await repo.saveMessage(
        sendingMsg(
          id: 'm1',
          contactPeerId: 'peer-a',
          createdAt: at(1),
          wireEnvelope: null,
        ),
      );
      final p2p = FakeP2PService();
      final bridge = _FlushFakeBridge();

      final result = await handleAppPaused(
        messageRepo: repo,
        p2pService: p2p,
        bridge: bridge,
        enablePauseFlush: true,
      );

      expect(bridge.bgBeginCount, 0);
      expect(p2p.storeInInboxCallCount, 0);
      expect(result.flushDepositedCount, 0);
      expect(await statusOf(repo, 'm1'), 'failed');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('FDC-S4 pause-flush — bounds (cap + ceiling)', () {
    test('deposits only the newest `cap` rows, newest-first; rest → failed',
        () async {
      final repo = InMemoryMessageRepository();
      // 8 rows; createdAt seconds 1..8. Newest-first = peer-08..peer-01.
      for (var s = 1; s <= 8; s++) {
        await repo.saveMessage(
          sendingMsg(
            id: 'm$s',
            contactPeerId: 'peer-0$s',
            createdAt: at(s),
          ),
        );
      }
      final p2p = FakeP2PService()..storeInInboxResult = true;
      final bridge = _FlushFakeBridge();

      final result = await handleAppPaused(
        messageRepo: repo,
        p2pService: p2p,
        bridge: bridge,
        enablePauseFlush: true,
        // default cap = kPauseFlushCap (5)
      );

      // The 5 newest, in newest-first order.
      expect(
        p2p.storeInInboxLog.map((e) => e.toPeerId).toList(),
        ['peer-08', 'peer-07', 'peer-06', 'peer-05', 'peer-04'],
      );
      expect(result.flushDepositedCount, 5);
      // The 3 oldest, beyond the cap, keep today's mark-failed behaviour.
      expect(result.transitionedCount, 3);
      expect(await statusOf(repo, 'm1'), 'failed');
      expect(await statusOf(repo, 'm2'), 'failed');
      expect(await statusOf(repo, 'm3'), 'failed');
      expect(await statusOf(repo, 'm8'), 'sending');
    });

    test('per-message budget is passed as storeInInbox timeoutMs', () async {
      final repo = InMemoryMessageRepository();
      await repo.saveMessage(
        sendingMsg(id: 'm1', contactPeerId: 'peer-a', createdAt: at(1)),
      );
      final p2p = FakeP2PService()..storeInInboxResult = true;
      final bridge = _FlushFakeBridge();

      await handleAppPaused(
        messageRepo: repo,
        p2pService: p2p,
        bridge: bridge,
        enablePauseFlush: true,
        perMessageBudget: const Duration(seconds: 3),
        overallCeiling: const Duration(seconds: 8),
      );

      expect(p2p.storeInInboxLog.single.timeoutMs, 3000);
    });

    test('overall ceiling stops the loop; remaining rows → failed', () async {
      final repo = InMemoryMessageRepository();
      for (var s = 1; s <= 5; s++) {
        await repo.saveMessage(
          sendingMsg(id: 'm$s', contactPeerId: 'peer-0$s', createdAt: at(s)),
        );
      }
      // Virtual clock: each deposit "takes" 4s. With an 8s ceiling, exactly two
      // deposits fit (0→4→8); the third trips the ceiling before it starts.
      var clock = 0;
      final p2p = FakeP2PService()
        ..onStoreInInbox = (_, _, {int? timeoutMs}) async {
          clock += 4000;
          return true;
        };
      final bridge = _FlushFakeBridge();

      final events = <Map<String, dynamic>>[];
      debugSetFlowEventSink(events.add);
      addTearDown(() => debugSetFlowEventSink(null));

      final result = await handleAppPaused(
        messageRepo: repo,
        p2pService: p2p,
        bridge: bridge,
        enablePauseFlush: true,
        overallCeiling: const Duration(seconds: 8),
        nowMs: () => clock,
      );

      expect(p2p.storeInInboxCallCount, 2);
      expect(result.flushDepositedCount, 2);
      // m08, m07 deposited (custody); m06..m04 within cap but past the ceiling,
      // plus nothing beyond cap here → 3 marked failed.
      expect(result.transitionedCount, 3);
      expect(bridge.bgEndTaskIds, ['7']); // assertion released after the ceiling
      // The COMPLETE event reports the ceiling trip.
      final complete = events.firstWhere(
        (e) => e['event'] == 'APP_LIFECYCLE_PAUSE_FLUSH_COMPLETE',
      );
      expect(complete['details']['expired'], true);
      expect(complete['details']['skipped'], 3);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('FDC-S4 pause-flush — assertion-refused (Android / low-power)', () {
    test('flush still runs without an assertion when bgBegin is refused',
        () async {
      final repo = InMemoryMessageRepository();
      await repo.saveMessage(
        sendingMsg(id: 'm1', contactPeerId: 'peer-a', createdAt: at(1)),
      );
      final p2p = FakeP2PService()..storeInInboxResult = true;
      final bridge = _FlushFakeBridge(grantTaskId: ''); // OS refuses

      final result = await handleAppPaused(
        messageRepo: repo,
        p2pService: p2p,
        bridge: bridge,
        enablePauseFlush: true,
      );

      // No assertion held, but the bounded deposit still proceeds.
      expect(p2p.storeInInboxCallCount, 1);
      expect(result.flushDepositedCount, 1);
      expect(await statusOf(repo, 'm1'), 'sending');
      // callBgEnd(null) is a no-op → no bg:end recorded.
      expect(bridge.bgEndTaskIds, isEmpty);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('FDC-S4 pause-flush — flow-event instruments', () {
    final events = <Map<String, dynamic>>[];

    setUp(() {
      events.clear();
      debugSetFlowEventSink(events.add);
    });
    tearDown(() => debugSetFlowEventSink(null));

    test('emits BEGIN / per-deposit DEPOSIT / COMPLETE with expected fields',
        () async {
      final repo = InMemoryMessageRepository();
      await repo.saveMessage(
        sendingMsg(id: 'm1', contactPeerId: 'peer-a', createdAt: at(2)),
      );
      await repo.saveMessage(
        sendingMsg(id: 'm2', contactPeerId: 'peer-b', createdAt: at(1)),
      );
      final p2p = FakeP2PService()..storeInInboxResult = true;
      final bridge = _FlushFakeBridge();

      await handleAppPaused(
        messageRepo: repo,
        p2pService: p2p,
        bridge: bridge,
        enablePauseFlush: true,
      );

      Map<String, dynamic> first(String name) =>
          events.firstWhere((e) => e['event'] == name);
      List<Map<String, dynamic>> all(String name) =>
          events.where((e) => e['event'] == name).toList();

      final begin = first('APP_LIFECYCLE_PAUSE_FLUSH_BEGIN');
      expect(begin['details']['taskGranted'], true);
      expect(begin['details']['sendingCount'], 2);
      expect(begin['details']['flushing'], 2);

      final deposits = all('APP_LIFECYCLE_PAUSE_FLUSH_DEPOSIT');
      expect(deposits, hasLength(2));
      expect(deposits.every((e) => e['details']['ok'] == true), isTrue);
      expect(deposits.every((e) => e['details']['id'] != null), isTrue);
      expect(deposits.every((e) => e['details']['ms'] is int), isTrue);

      // One in-custody marker per accepted row (the deposit-first skip).
      final custody = all('APP_LIFECYCLE_PAUSE_FLUSH_IN_CUSTODY');
      expect(custody, hasLength(2));

      final complete = first('APP_LIFECYCLE_PAUSE_FLUSH_COMPLETE');
      expect(complete['details']['deposited'], 2);
      expect(complete['details']['skipped'], 0);
      expect(complete['details']['cappedOut'], 0);
      expect(complete['details']['expired'], false);
    });
  });
}
