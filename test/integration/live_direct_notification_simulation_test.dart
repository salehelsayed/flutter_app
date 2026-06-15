import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import '../shared/fakes/one_to_one_test_user.dart';

/// 120 Phase G3 (SIMULATION): a deterministic, automated 2-party,
/// transport-and-lifecycle-aware simulation of the live-direct (1:1)
/// notification path. Converts the manual-only device proof into a regression
/// guard that catches a change in WHICH path a live message takes (relay/direct
/// notify+ack vs LAN `lan:` staging vs the FCM live-wins dedup), across
/// resumed/viewing lifecycle.
///
/// HEADER NOTE (plan 120 Risk "Simulation drift from main.dart"): the harness
/// MIRRORS the main.dart replay closures rather than booting `main()`, so it
/// CANNOT catch a `main.dart` wiring regression — that is Phase G1's job
/// (`main_replay_disposition_wiring_test.dart`). G1 + G3 are complementary.
///
/// Depends on Phase G2 (`test/flutter_test_config.dart`) for per-test gate
/// isolation; the per-sim unique-temp gate is ALSO passed explicitly into both
/// listeners via `remoteNotificationGate:` for determinism.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const aliceId = 'peer-alice';
  const bobId = 'peer-bob';

  late OneToOneTestUser alice;
  late OneToOneTestUser bob;
  late DateTime now;
  late Directory tempDir;
  late RecentRemoteNotificationGate gate;

  setUp(() async {
    flowEventLoggingEnabled = false;
    now = DateTime.utc(2026, 6, 13, 12);
    tempDir = await Directory.systemTemp.createTemp('one_to_one_sim');
    gate = RecentRemoteNotificationGate(filePath: '${tempDir.path}/gate.json');

    alice = OneToOneTestUser.create(
      peerId: aliceId,
      username: 'Alice',
      gate: gate,
      clock: () => now,
    );
    bob = OneToOneTestUser.create(
      peerId: bobId,
      username: 'Bob',
      gate: gate,
      clock: () => now,
    );
    // The receiver (alice) must know the sender (bob) so the listener resolves
    // a username and does not reject an unknown sender.
    alice.knowsContact(bob);
    bob.knowsContact(alice);
  });

  tearDown(() async {
    alice.dispose();
    bob.dispose();
    // Live notifications write dedup markers fire-and-forget; let them settle.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    try {
      await gate.clear();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {
      // Best-effort cleanup of an OS temp dir.
    }
  });

  Future<void> waitFor(
    bool Function() condition, {
    required String reason,
  }) async {
    for (var i = 0; i < 80; i++) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail(reason);
  }

  test(
    'relay direct message, recipient resumed-not-viewing -> one audible '
    'notification + sender confirmed',
    () async {
      final (:id, :nonce) = await DirectMessageRouter.deliver(
        bob,
        alice,
        'hello over relay',
        transport: 'relay',
        messageId: 'msg-relay-1',
      );

      await waitFor(
        () => alice.notificationService.shown.isNotEmpty,
        reason: 'a live relay direct message should notify',
      );

      // Notify + ack coexist on the live path.
      expect(alice.notificationService.shown, hasLength(1));
      expect(alice.notificationService.shown.single.silent, isFalse);
      expect(alice.notificationService.shown.single.contactPeerId, bobId);

      final confirms = alice.bridge.payloadsFor('message:confirm');
      expect(confirms, hasLength(1));
      expect(confirms.single, equals({'nonce': nonce, 'ok': true}));

      // The message took the live-direct path with transport == 'relay'
      // (mirrors p2p_service_impl_test.dart:1107), never the suppressing
      // recovery callback.
      expect(alice.liveDirectTransports, equals(['relay']));
      expect(alice.recoveredReplayCount, 0);
      expect(alice.messageRepo.lastSavedMessage?.id, id);
      await waitFor(
        () => alice.stagingRepo.entry('direct:$nonce') == null,
        reason: 'committed live direct entry should be deleted',
      );
    },
  );

  test(
    'direct transport behaves identically to relay (confirmNonce-gated, not '
    'transport-gated)',
    () async {
      await DirectMessageRouter.deliver(
        bob,
        alice,
        'hello over direct',
        transport: 'direct',
        messageId: 'msg-direct-1',
      );

      await waitFor(
        () => alice.notificationService.shown.isNotEmpty,
        reason: 'a live direct-transport message should notify identically',
      );

      expect(alice.notificationService.shown, hasLength(1));
      expect(alice.notificationService.shown.single.silent, isFalse);

      // Confirmed AND took the live-direct path showing transport == 'direct'.
      expect(alice.bridge.payloadsFor('message:confirm'), hasLength(1));
      expect(alice.liveDirectTransports, equals(['direct']));
      expect(alice.recoveredReplayCount, 0);
    },
  );

  test(
    'resumed + viewing the sender\'s conversation -> suppressed',
    () async {
      alice.conversationTracker.setActive(bobId);

      await DirectMessageRouter.deliver(
        bob,
        alice,
        'while viewing',
        transport: 'relay',
        messageId: 'msg-viewing-1',
      );

      // The message still routes through the live-direct (notify-capable) path
      // and confirms; the notification is suppressed by viewing_conversation.
      await waitFor(
        () => alice.bridge.payloadsFor('message:confirm').isNotEmpty,
        reason: 'a viewed-conversation message should still confirm the sender',
      );
      // Settle the fire-and-forget notification path before asserting absence.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(alice.notificationService.shown, isEmpty);
      expect(alice.liveDirectTransports, equals(['relay']));
      expect(alice.recoveredReplayCount, 0);
    },
  );

  test(
    'burst within the window -> one tone then silent',
    () async {
      await DirectMessageRouter.deliver(
        bob,
        alice,
        'burst one',
        transport: 'relay',
        messageId: 'msg-burst-1',
      );
      await waitFor(
        () => alice.notificationService.shown.length == 1,
        reason: 'first burst message should notify',
      );
      expect(alice.notificationService.shown.last.silent, isFalse);

      // Second message from the same sender, still inside the 30s window.
      now = now.add(const Duration(seconds: 5));
      await DirectMessageRouter.deliver(
        bob,
        alice,
        'burst two',
        transport: 'relay',
        messageId: 'msg-burst-2',
      );
      await waitFor(
        () => alice.notificationService.shown.length == 2,
        reason: 'second burst message should still update the notification',
      );

      // [audible, silent] — at most one tone per conversation per window.
      expect(
        alice.notificationService.shown.map((n) => n.silent).toList(),
        equals([false, true]),
      );
      // Both messages were still confirmed to the sender.
      expect(alice.bridge.payloadsFor('message:confirm'), hasLength(2));
    },
  );

  test(
    'LAN (wifi) takes the live-lan path, not the direct staging path',
    () async {
      final (:id, :nonce) = await DirectMessageRouter.deliver(
        bob,
        alice,
        'over wifi',
        transport: 'wifi',
        messageId: 'msg-wifi-1',
      );

      await waitFor(
        () => alice.notificationService.shown.isNotEmpty,
        reason: 'a live LAN message should notify',
      );
      expect(alice.notificationService.shown, hasLength(1));
      expect(alice.notificationService.shown.single.silent, isFalse);

      // Different branch: staged as `lan:<nonce>` and routed through the
      // live-LAN callback (NOT the direct staging path, NOT recovery, and
      // NEVER `message:confirm` — the LAN ack carries that confirmation).
      expect(alice.liveLanTransports, equals(['wifi']));
      expect(alice.liveDirectTransports, isEmpty);
      expect(alice.recoveredReplayCount, 0);
      expect(alice.bridge.payloadsFor('message:confirm'), isEmpty);
      expect(alice.messageRepo.lastSavedMessage?.id, id);
      await waitFor(
        () => alice.stagingRepo.entry('lan:$nonce') == null,
        reason: 'committed live LAN entry should be deleted',
      );
    },
  );

  test(
    'FCM-handoff dedup: after a live notify writes its marker, a late push for '
    'the same messageId is suppressed',
    () async {
      final delivered = await DirectMessageRouter.deliver(
        bob,
        alice,
        'live then late FCM',
        transport: 'relay',
        messageId: 'msg-handoff-1',
      );
      final id = delivered.id;

      await waitFor(
        () => alice.notificationService.shown.isNotEmpty,
        reason: 'the live notify must land before the late FCM arrives',
      );

      // The live-wins marker is written fire-and-forget AFTER the notification
      // is shown. Poll the shared gate: a late FCM for the same
      // (sender, messageId) consumes-and-suppresses (returns true) rather than
      // double-alerting.
      var suppressed = false;
      for (var i = 0; i < 80; i++) {
        suppressed = await gate.consumeIfRecentAnnouncement(
          payload: bobId,
          messageId: id,
        );
        if (suppressed) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(
        suppressed,
        isTrue,
        reason:
            'the live notify should have written a live-wins dedup marker for '
            'this messageId, so the late FCM suppresses instead of alerting',
      );
    },
  );
}
