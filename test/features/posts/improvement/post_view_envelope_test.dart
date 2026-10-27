import 'dart:convert';

import 'package:flutter_app/features/posts/domain/models/post_view_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/thought_view_receipt.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/recording_fake_bridge.dart';

void main() {
  late RecordingFakeBridge bridge;
  late String inner;
  final envelope = PostViewEnvelope(
    eventId: 'view-1',
    postCreatedAt: DateTime.utc(2026, 10, 27, 10),
    receipt: const ThoughtViewReceipt(
      postId: 'thought-1',
      viewerPeerId: 'sam',
      viewedAt: '2026-10-27T12:00:00.000Z',
    ),
  );

  setUp(() {
    bridge = RecordingFakeBridge();
    bridge.whenCommand('message.encrypt', (payload) {
      expect(payload!['recipientPublicKey'], 'author-key');
      inner = payload['plaintext'] as String;
      return jsonEncode({
        'ok': true,
        'kem': 'kem',
        'ciphertext': 'opaque-view-ciphertext',
        'nonce': 'nonce',
      });
    });
    bridge.whenCommand(
      'message.decrypt',
      (_) => jsonEncode({'ok': true, 'plaintext': inner}),
    );
  });

  Future<String> wire() => envelope.toEncryptedJson(
    bridge: bridge,
    recipientMlKemPublicKey: 'author-key',
  );
  Future<PostViewEnvelope?> receive(String raw, {String sender = 'sam'}) =>
      PostViewEnvelope.fromEncryptedJson(
        raw: raw,
        authenticatedSender: sender,
        bridge: bridge,
        ownMlKemSecretKey: 'author-secret',
      );

  test(
    'an explicit view travels only through the encrypted message bridge',
    () async {
      final raw = await wire();
      final outer = jsonDecode(raw) as Map<String, dynamic>;
      expect(bridge.calledCommands, ['message.encrypt']);
      expect(outer['type'], 'post_view');
      expect(outer['version'], '2');
      expect(outer['encrypted']['ciphertext'], 'opaque-view-ciphertext');
      expect(outer.containsKey('payload'), isFalse);
      expect(outer.containsKey('viewer_peer_id'), isFalse);
      expect(outer.containsKey('viewed_at'), isFalse);
      final decoded = await receive(raw);
      expect(decoded!.receipt.toMap(), envelope.receipt.toMap());
      expect(decoded.postCreatedAt, envelope.postCreatedAt);
    },
  );

  test(
    'a missing key or encryption error cannot create a plaintext receipt',
    () async {
      await expectLater(
        envelope.toEncryptedJson(bridge: bridge, recipientMlKemPublicKey: ''),
        throwsStateError,
      );
      expect(bridge.calledCommands, isEmpty);
      bridge.whenCommand('message.encrypt', (_) => '{"ok":false}');
      await expectLater(wire(), throwsStateError);
    },
  );

  test(
    'malformed successful encryption response cannot leave the device',
    () async {
      for (final field in ['kem', 'ciphertext', 'nonce']) {
        bridge.whenCommand(
          'message.encrypt',
          (_) => jsonEncode({
            'ok': true,
            'kem': 'kem',
            'ciphertext': 'cipher',
            'nonce': 'nonce',
            field: '',
          }),
        );
        await expectLater(wire(), throwsStateError);
      }
    },
  );

  test('an authenticated transport cannot claim another viewer', () async {
    final raw = await wire();
    expect(await receive(raw, sender: 'mallory'), isNull);
    expect(bridge.calledCommands, ['message.encrypt']);
  });

  test(
    'swapped post, actor, or time metadata is rejected after decryption',
    () async {
      final raw = await wire();
      final originalInner = inner;
      for (final entry in {
        'post_id': 'other-thought',
        'viewer_peer_id': 'other-viewer',
        'viewed_at': '2026-10-27T13:00:00.000Z',
        'post_created_at': '2026-10-27T09:00:00.000Z',
      }.entries) {
        inner = jsonEncode({
          ...jsonDecode(originalInner) as Map<String, dynamic>,
          entry.key: entry.value,
        });
        expect(await receive(raw), isNull, reason: entry.key);
      }
    },
  );

  test(
    'plaintext, unknown version and failed decryption produce no view',
    () async {
      final raw = await wire();
      final outer = jsonDecode(raw) as Map<String, dynamic>;
      expect(
        await receive(
          jsonEncode({
            ...outer,
            'version': '1',
            'payload': envelope.receipt.toMap(),
          }),
        ),
        isNull,
      );
      expect(await receive(jsonEncode({...outer, 'version': '3'})), isNull);
      bridge.whenCommand('message.decrypt', (_) => '{"ok":false}');
      expect(await receive(raw), isNull);
    },
  );

  test(
    'queued receipt expires with the thought fixed 24-hour lifetime',
    () async {
      final raw = await wire();
      expect(
        PostViewEnvelope.queuedExpiry(raw),
        DateTime.utc(2026, 10, 28, 10),
      );
      expect(PostViewEnvelope.queuedExpiry('{}'), isNull);
      expect(
        PostViewEnvelope.queuedExpiry(
          jsonEncode({
            ...jsonDecode(raw) as Map<String, dynamic>,
            'post_created_at': 'bad',
          }),
        ),
        isNull,
      );
    },
  );
}
