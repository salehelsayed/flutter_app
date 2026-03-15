import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/post_presence_listener.dart';
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

ChatMessage _presenceMessage({
  required String senderPeerId,
  required String status,
  int? latE3,
  int? lngE3,
  double? accuracyM,
  String? reason,
  String capturedAt = '2026-03-15T11:10:00.000Z',
}) {
  return ChatMessage(
    from: senderPeerId,
    to: 'peer-self',
    content: jsonEncode(<String, Object?>{
      'type': 'post_presence_update',
      'version': '1',
      'event_id': 'evt-$senderPeerId-$status',
      'created_at': capturedAt,
      'sender_peer_id': senderPeerId,
      'payload': <String, Object?>{
        'status': status,
        'lat_e3': latE3,
        'lng_e3': lngE3,
        'captured_at': capturedAt,
        'accuracy_m': accuracyM,
        'reason': reason,
      }..removeWhere((_, value) => value == null),
    }),
    timestamp: capturedAt,
    isIncoming: true,
  );
}

void main() {
  late StreamController<ChatMessage> controller;
  late InMemoryContactRepository contacts;
  late InMemoryContactPresenceSnapshotRepository snapshots;
  late PostPresenceListener listener;

  setUp(() {
    controller = StreamController<ChatMessage>.broadcast();
    contacts = InMemoryContactRepository();
    snapshots = InMemoryContactPresenceSnapshotRepository();
    listener = PostPresenceListener(
      postPresenceStream: controller.stream,
      contactRepo: contacts,
      snapshotRepo: snapshots,
    )..start();
  });

  tearDown(() async {
    listener.dispose();
    snapshots.dispose();
    await controller.close();
  });

  test('persists active direct-friend presence snapshots', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob'));

    controller.add(
      _presenceMessage(
        senderPeerId: 'peer-bob',
        status: 'active',
        latE3: 52520,
        lngE3: 13405,
        accuracyM: 120,
      ),
    );

    final snapshot = await listener.incomingPresenceStream.first.timeout(
      const Duration(seconds: 1),
    );
    expect(snapshot.peerId, 'peer-bob');
    expect((await snapshots.load('peer-bob'))?.latE3, 52520);
  });

  test('ignores presence updates from unknown senders', () async {
    controller.add(
      _presenceMessage(
        senderPeerId: 'peer-unknown',
        status: 'active',
        latE3: 52520,
        lngE3: 13405,
        accuracyM: 120,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(await snapshots.load('peer-unknown'), isNull);
  });

  test('inactive updates clear previously stored coordinates', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob'));
    await snapshots.save(
      const ContactPresenceSnapshot(
        peerId: 'peer-bob',
        status: ContactPresenceSnapshotStatus.active,
        latE3: 52520,
        lngE3: 13405,
        capturedAt: '2026-03-15T11:10:00.000Z',
        accuracyM: 120,
        updatedAt: '2026-03-15T11:10:05.000Z',
      ),
    );

    controller.add(
      _presenceMessage(
        senderPeerId: 'peer-bob',
        status: 'inactive',
        reason: 'services_disabled',
        capturedAt: '2026-03-15T11:20:00.000Z',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final snapshot = await snapshots.load('peer-bob');
    expect(snapshot, isNotNull);
    expect(snapshot!.status, ContactPresenceSnapshotStatus.inactive);
    expect(snapshot.latE3, isNull);
    expect(snapshot.lngE3, isNull);
  });
}
