import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/handle_incoming_post_presence_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/contact_presence_snapshot.dart';

import '../../../shared/fakes/in_memory_contact_presence_snapshot_repository.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';

ContactModel _contact(String peerId, String username, {bool blocked = false}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/example.invalid/tcp/443',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: '2026-03-15T10:00:00.000Z',
    isBlocked: blocked,
  );
}

ChatMessage _message({
  required String from,
  required String timestamp,
  required Map<String, Object?> envelope,
}) {
  return ChatMessage(
    from: from,
    to: 'peer-self',
    content: jsonEncode(envelope),
    timestamp: timestamp,
    isIncoming: true,
  );
}

Map<String, Object?> _activePayload({
  String status = 'active',
  int? latE3 = 52520,
  int? lngE3 = 13405,
  Object? capturedAt = '2026-03-15T11:10:00.000Z',
  double? accuracyM = 120,
}) {
  return <String, Object?>{
    'status': status,
    'lat_e3': latE3,
    'lng_e3': lngE3,
    'captured_at': capturedAt,
    'accuracy_m': accuracyM,
  }..removeWhere((_, value) => value == null);
}

Map<String, Object?> _inactivePayload({
  String status = 'inactive',
  Object? capturedAt = '2026-03-15T11:10:00.000Z',
  String? reason = 'services_disabled',
}) {
  return <String, Object?>{
    'status': status,
    'captured_at': capturedAt,
    'reason': reason,
  }..removeWhere((_, value) => value == null);
}

Map<String, Object?> _presenceEnvelope({
  String type = 'post_presence_update',
  String senderPeerId = 'peer-bob',
  Object? createdAt = '2026-03-15T11:10:05.000Z',
  Map<String, Object?>? payload,
}) {
  return <String, Object?>{
    'type': type,
    'version': '1',
    'event_id': 'evt-$senderPeerId',
    'created_at': createdAt,
    'sender_peer_id': senderPeerId,
    'payload': payload ?? _activePayload(),
  }..removeWhere((_, value) => value == null);
}

void main() {
  late InMemoryContactRepository contacts;
  late InMemoryContactPresenceSnapshotRepository snapshots;

  setUp(() {
    contacts = InMemoryContactRepository();
    snapshots = InMemoryContactPresenceSnapshotRepository();
  });

  tearDown(() {
    snapshots.dispose();
  });

  group('handleIncomingPostPresence', () {
    test('persists a valid active presence snapshot', () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob'));
      final message = _message(
        from: 'peer-bob',
        timestamp: '2026-03-15T11:10:05.000Z',
        envelope: _presenceEnvelope(),
      );

      final (result, snapshot) = await handleIncomingPostPresence(
        message: message,
        contactRepo: contacts,
        snapshotRepo: snapshots,
      );

      expect(result, HandleIncomingPostPresenceResult.snapshotUpdated);
      expect(snapshot, isNotNull);
      expect(snapshot!.peerId, 'peer-bob');
      expect(snapshot.status, ContactPresenceSnapshotStatus.active);
      expect(snapshot.latE3, 52520);
      expect(snapshot.lngE3, 13405);
      expect(snapshot.accuracyM, 120);
      expect(snapshot.capturedAt, '2026-03-15T11:10:00.000Z');
      expect(snapshot.updatedAt, '2026-03-15T11:10:05.000Z');
      expect((await snapshots.load('peer-bob'))?.toMap(), snapshot.toMap());
    });

    test('falls back to message.timestamp when created_at is absent', () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob'));
      final message = _message(
        from: 'peer-bob',
        timestamp: '2026-03-15T11:10:42.000Z',
        envelope: _presenceEnvelope(createdAt: null),
      );

      final (result, snapshot) = await handleIncomingPostPresence(
        message: message,
        contactRepo: contacts,
        snapshotRepo: snapshots,
      );

      expect(result, HandleIncomingPostPresenceResult.snapshotUpdated);
      expect(snapshot, isNotNull);
      expect(snapshot!.updatedAt, '2026-03-15T11:10:42.000Z');
      expect((await snapshots.load('peer-bob'))?.updatedAt, snapshot.updatedAt);
    });

    test(
      'returns notPostPresenceUpdate for a different message type',
      () async {
        final message = _message(
          from: 'peer-bob',
          timestamp: '2026-03-15T11:10:05.000Z',
          envelope: _presenceEnvelope(type: 'chat_message'),
        );

        final (result, snapshot) = await handleIncomingPostPresence(
          message: message,
          contactRepo: contacts,
          snapshotRepo: snapshots,
        );

        expect(result, HandleIncomingPostPresenceResult.notPostPresenceUpdate);
        expect(snapshot, isNull);
        expect(await snapshots.load('peer-bob'), isNull);
      },
    );

    test('returns unknownSender when the sender is not a contact', () async {
      final message = _message(
        from: 'peer-bob',
        timestamp: '2026-03-15T11:10:05.000Z',
        envelope: _presenceEnvelope(),
      );

      final (result, snapshot) = await handleIncomingPostPresence(
        message: message,
        contactRepo: contacts,
        snapshotRepo: snapshots,
      );

      expect(result, HandleIncomingPostPresenceResult.unknownSender);
      expect(snapshot, isNull);
      expect(await snapshots.load('peer-bob'), isNull);
    });

    test('returns blockedSender when the sender contact is blocked', () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob', blocked: true));
      final message = _message(
        from: 'peer-bob',
        timestamp: '2026-03-15T11:10:05.000Z',
        envelope: _presenceEnvelope(),
      );

      final (result, snapshot) = await handleIncomingPostPresence(
        message: message,
        contactRepo: contacts,
        snapshotRepo: snapshots,
      );

      expect(result, HandleIncomingPostPresenceResult.blockedSender);
      expect(snapshot, isNull);
      expect(await snapshots.load('peer-bob'), isNull);
    });

    test(
      'returns staleSnapshot and preserves the existing newer snapshot',
      () async {
        contacts.addTestContact(_contact('peer-bob', 'Bob'));
        const existingSnapshot = ContactPresenceSnapshot(
          peerId: 'peer-bob',
          status: ContactPresenceSnapshotStatus.active,
          latE3: 52520,
          lngE3: 13405,
          capturedAt: '2026-03-15T11:15:00.000Z',
          accuracyM: 120,
          updatedAt: '2026-03-15T11:15:05.000Z',
        );
        await snapshots.save(existingSnapshot);

        final message = _message(
          from: 'peer-bob',
          timestamp: '2026-03-15T11:10:05.000Z',
          envelope: _presenceEnvelope(
            payload: _activePayload(
              latE3: 52524,
              lngE3: 13409,
              capturedAt: '2026-03-15T11:10:00.000Z',
              accuracyM: 90,
            ),
          ),
        );

        final (result, snapshot) = await handleIncomingPostPresence(
          message: message,
          contactRepo: contacts,
          snapshotRepo: snapshots,
        );

        expect(result, HandleIncomingPostPresenceResult.staleSnapshot);
        expect(snapshot, isNull);
        expect(
          (await snapshots.load('peer-bob'))?.toMap(),
          existingSnapshot.toMap(),
        );
      },
    );

    final invalidPayloadCases = <({String description, ChatMessage message})>[
      (
        description: 'sender mismatch',
        message: _message(
          from: 'peer-bob',
          timestamp: '2026-03-15T11:10:05.000Z',
          envelope: _presenceEnvelope(senderPeerId: 'peer-alice'),
        ),
      ),
      (
        description: 'malformed created_at timestamp',
        message: _message(
          from: 'peer-bob',
          timestamp: '2026-03-15T11:10:05.000Z',
          envelope: _presenceEnvelope(createdAt: 'not-an-iso-timestamp'),
        ),
      ),
      (
        description: 'missing payload',
        message: _message(
          from: 'peer-bob',
          timestamp: '2026-03-15T11:10:05.000Z',
          envelope: _presenceEnvelope(payload: null)..remove('payload'),
        ),
      ),
      (
        description: 'missing status',
        message: _message(
          from: 'peer-bob',
          timestamp: '2026-03-15T11:10:05.000Z',
          envelope: _presenceEnvelope(
            payload: _activePayload()..remove('status'),
          ),
        ),
      ),
      (
        description: 'unknown status',
        message: _message(
          from: 'peer-bob',
          timestamp: '2026-03-15T11:10:05.000Z',
          envelope: _presenceEnvelope(
            payload: _activePayload(status: 'paused'),
          ),
        ),
      ),
      (
        description: 'missing captured_at timestamp',
        message: _message(
          from: 'peer-bob',
          timestamp: '2026-03-15T11:10:05.000Z',
          envelope: _presenceEnvelope(
            payload: _activePayload(capturedAt: null),
          ),
        ),
      ),
      (
        description: 'malformed captured_at timestamp',
        message: _message(
          from: 'peer-bob',
          timestamp: '2026-03-15T11:10:05.000Z',
          envelope: _presenceEnvelope(
            payload: _activePayload(capturedAt: 'not-an-iso-timestamp'),
          ),
        ),
      ),
      (
        description: 'missing active coordinates',
        message: _message(
          from: 'peer-bob',
          timestamp: '2026-03-15T11:10:05.000Z',
          envelope: _presenceEnvelope(payload: _activePayload(latE3: null)),
        ),
      ),
      (
        description: 'missing inactive reason',
        message: _message(
          from: 'peer-bob',
          timestamp: '2026-03-15T11:10:05.000Z',
          envelope: _presenceEnvelope(payload: _inactivePayload(reason: null)),
        ),
      ),
      (
        description: 'unknown inactive reason',
        message: _message(
          from: 'peer-bob',
          timestamp: '2026-03-15T11:10:05.000Z',
          envelope: _presenceEnvelope(
            payload: _inactivePayload(reason: 'manual_pause'),
          ),
        ),
      ),
    ];

    for (final testCase in invalidPayloadCases) {
      test('returns invalidPayload for ${testCase.description}', () async {
        contacts.addTestContact(_contact('peer-bob', 'Bob'));

        final (result, snapshot) = await handleIncomingPostPresence(
          message: testCase.message,
          contactRepo: contacts,
          snapshotRepo: snapshots,
        );

        expect(result, HandleIncomingPostPresenceResult.invalidPayload);
        expect(snapshot, isNull);
        expect(await snapshots.load('peer-bob'), isNull);
      });
    }
  });
}
