import 'package:flutter_app/core/inbox/inbox_staging_entry.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../shared/fakes/in_memory_inbox_staging_repository.dart';
import '../shared/fakes/lifecycle_bridge.dart';
import 'benchmark_harness.dart';

void main() {
  late BenchmarkHarness harness;
  late LifecycleBridge bridge;
  late InMemoryInboxStagingRepository inboxRepo;

  setUp(() {
    harness = BenchmarkHarness();
    bridge = LifecycleBridge();
    inboxRepo = InMemoryInboxStagingRepository();
  });

  tearDown(() {
    harness.dispose();
  });

  group('Benchmark: INBOX_DELIVERY_TIMING', () {
    test('E1: Fallback forward path emits INBOX_DELIVERY_TIMING', () async {
      // Seed an entry with no matching handler (messageType null → fallback)
      inboxRepo.seed(InboxStagingEntry(
        entryId: 'entry-001-abcdef',
        ownerPeerId: testPeerId,
        senderPeerId: 'sender-peer-1',
        relayTimestamp: '2026-04-01T00:00:00.000Z',
        envelope: '{"type":"chat_message","version":"1","payload":{"text":"hello"}}',
        stagedAt: '2026-04-01T00:00:00.000Z',
        messageType: 'unknown_type',
      ));

      final service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: inboxRepo,
      );

      // Start the node so drainOfflineInbox proceeds
      await service.startNodeCore(testBase64Key, testPeerId);

      final events = await harness.captureFlowEvents(() async {
        await service.drainOfflineInbox();
      });

      service.dispose();

      final timings = harness.filterEvents(events, 'INBOX_DELIVERY_TIMING');
      expect(timings, isNotEmpty,
          reason: 'Should emit INBOX_DELIVERY_TIMING on fallback forward');

      final details = timings.first['details'] as Map<String, dynamic>;
      expect(details['deliveryMs'], isA<int>());
      expect(details['deliveryMs'], greaterThanOrEqualTo(0));
      expect(details['messageId'], isA<String>());
      expect(details['messageId'], isNotEmpty);
    });

    test('E2: Chat message path emits INBOX_DELIVERY_TIMING', () async {
      inboxRepo.seed(InboxStagingEntry(
        entryId: 'entry-002-abcdef',
        ownerPeerId: testPeerId,
        senderPeerId: 'sender-peer-2',
        relayTimestamp: '2026-04-01T00:00:00.000Z',
        envelope: '{"type":"chat_message","version":"1","payload":{"text":"hi"}}',
        stagedAt: '2026-04-01T00:00:00.000Z',
        messageType: 'chat_message',
      ));

      final service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: inboxRepo,
        replayRecoveredInboxChatMessage: (message) async => (
          disposition: RecoveredInboxChatDisposition.committed,
          reasonCode: 'ok',
          reasonDetail: null,
        ),
      );

      await service.startNodeCore(testBase64Key, testPeerId);

      final events = await harness.captureFlowEvents(() async {
        await service.drainOfflineInbox();
      });

      service.dispose();

      final timings = harness.filterEvents(events, 'INBOX_DELIVERY_TIMING');
      expect(timings, isNotEmpty,
          reason: 'Should emit INBOX_DELIVERY_TIMING for chat_message');

      final details = timings.first['details'] as Map<String, dynamic>;
      expect(details['deliveryMs'], isA<int>());
      expect(details['deliveryMs'], greaterThanOrEqualTo(0));
      expect(details['messageId'], 'entry-00');
    });

    test('E3: Introduction path emits INBOX_DELIVERY_TIMING', () async {
      inboxRepo.seed(InboxStagingEntry(
        entryId: 'entry-003-abcdef',
        ownerPeerId: testPeerId,
        senderPeerId: 'sender-peer-3',
        relayTimestamp: '2026-04-01T00:00:00.000Z',
        envelope: '{"type":"introduction","version":"1","payload":{"text":"intro"}}',
        stagedAt: '2026-04-01T00:00:00.000Z',
        messageType: 'introduction',
      ));

      final service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: inboxRepo,
        replayRecoveredInboxIntroductionMessage: (message) async => (
          disposition: RecoveredInboxChatDisposition.committed,
          reasonCode: 'ok',
          reasonDetail: null,
        ),
      );

      await service.startNodeCore(testBase64Key, testPeerId);

      final events = await harness.captureFlowEvents(() async {
        await service.drainOfflineInbox();
      });

      service.dispose();

      final timings = harness.filterEvents(events, 'INBOX_DELIVERY_TIMING');
      expect(timings, isNotEmpty,
          reason: 'Should emit INBOX_DELIVERY_TIMING for introduction');

      final details = timings.first['details'] as Map<String, dynamic>;
      expect(details['deliveryMs'], isA<int>());
      expect(details['deliveryMs'], greaterThanOrEqualTo(0));
      expect(details['messageId'], 'entry-00');
    });

    test('E4: Retryable outcome does NOT emit INBOX_DELIVERY_TIMING', () async {
      inboxRepo.seed(InboxStagingEntry(
        entryId: 'entry-004-abcdef',
        ownerPeerId: testPeerId,
        senderPeerId: 'sender-peer-4',
        relayTimestamp: '2026-04-01T00:00:00.000Z',
        envelope: '{"type":"chat_message","version":"1","payload":{"text":"retry"}}',
        stagedAt: '2026-04-01T00:00:00.000Z',
        messageType: 'chat_message',
      ));

      final service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: inboxRepo,
        replayRecoveredInboxChatMessage: (message) async => (
          disposition: RecoveredInboxChatDisposition.retryable,
          reasonCode: 'decrypt_failed',
          reasonDetail: 'test failure',
        ),
      );

      await service.startNodeCore(testBase64Key, testPeerId);

      final events = await harness.captureFlowEvents(() async {
        await service.drainOfflineInbox();
      });

      service.dispose();

      final timings = harness.filterEvents(events, 'INBOX_DELIVERY_TIMING');
      expect(timings, isEmpty,
          reason: 'Should NOT emit INBOX_DELIVERY_TIMING for retryable');
    });

    test('E5: Batch of 5 entries emits 5 INBOX_DELIVERY_TIMING events',
        () async {
      for (var i = 0; i < 5; i++) {
        inboxRepo.seed(InboxStagingEntry(
          entryId: 'batch-${i.toString().padLeft(3, '0')}-abcdef',
          ownerPeerId: testPeerId,
          senderPeerId: 'sender-peer-batch',
          relayTimestamp: '2026-04-01T00:00:0$i.000Z',
          envelope: '{"type":"chat_message","version":"1","payload":{"text":"msg$i"}}',
          stagedAt: '2026-04-01T00:00:0$i.000Z',
          messageType: 'chat_message',
        ));
      }

      final service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: inboxRepo,
        replayRecoveredInboxChatMessage: (message) async => (
          disposition: RecoveredInboxChatDisposition.committed,
          reasonCode: 'ok',
          reasonDetail: null,
        ),
      );

      await service.startNodeCore(testBase64Key, testPeerId);

      final events = await harness.captureFlowEvents(() async {
        await service.drainOfflineInbox();
      });

      service.dispose();

      final timings = harness.filterEvents(events, 'INBOX_DELIVERY_TIMING');
      expect(timings, hasLength(5),
          reason: 'Should emit 5 INBOX_DELIVERY_TIMING events');

      for (final timing in timings) {
        final details = timing['details'] as Map<String, dynamic>;
        expect(details['deliveryMs'], isA<int>());
        expect(details['deliveryMs'], greaterThanOrEqualTo(0));
        expect(details['messageId'], isA<String>());
        expect(details['messageId'], isNotEmpty);
      }
    });

    test('E6: deliveryMs is within fast budget for in-memory fakes', () async {
      inboxRepo.seed(InboxStagingEntry(
        entryId: 'perf-001-abcdef',
        ownerPeerId: testPeerId,
        senderPeerId: 'sender-peer-perf',
        relayTimestamp: '2026-04-01T00:00:00.000Z',
        envelope: '{"type":"chat_message","version":"1","payload":{"text":"fast"}}',
        stagedAt: '2026-04-01T00:00:00.000Z',
        messageType: 'chat_message',
      ));

      final service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: inboxRepo,
        replayRecoveredInboxChatMessage: (message) async => (
          disposition: RecoveredInboxChatDisposition.committed,
          reasonCode: 'ok',
          reasonDetail: null,
        ),
      );

      await service.startNodeCore(testBase64Key, testPeerId);

      final events = await harness.captureFlowEvents(() async {
        await service.drainOfflineInbox();
      });

      service.dispose();

      final timings = harness.filterEvents(events, 'INBOX_DELIVERY_TIMING');
      expect(timings, isNotEmpty);

      final details = timings.first['details'] as Map<String, dynamic>;
      final deliveryMs = details['deliveryMs'] as int;
      expect(
        deliveryMs,
        lessThan(100),
        reason: 'Dart-side inbox delivery should be fast with fakes',
      );
    });

    test('E7: messageId is truncated to 8 characters', () async {
      inboxRepo.seed(InboxStagingEntry(
        entryId: 'abcdefghij-long-id',
        ownerPeerId: testPeerId,
        senderPeerId: 'sender-peer-trunc',
        relayTimestamp: '2026-04-01T00:00:00.000Z',
        envelope: '{"type":"chat_message","version":"1","payload":{"text":"trunc"}}',
        stagedAt: '2026-04-01T00:00:00.000Z',
        messageType: 'chat_message',
      ));

      final service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: inboxRepo,
        replayRecoveredInboxChatMessage: (message) async => (
          disposition: RecoveredInboxChatDisposition.committed,
          reasonCode: 'ok',
          reasonDetail: null,
        ),
      );

      await service.startNodeCore(testBase64Key, testPeerId);

      final events = await harness.captureFlowEvents(() async {
        await service.drainOfflineInbox();
      });

      service.dispose();

      final timings = harness.filterEvents(events, 'INBOX_DELIVERY_TIMING');
      expect(timings, isNotEmpty);

      final details = timings.first['details'] as Map<String, dynamic>;
      expect(details['messageId'], 'abcdefgh');
    });
  });
}
