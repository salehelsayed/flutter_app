import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/features/push/application/push_envelope_staging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late DateTime now;

  setUp(() async {
    now = DateTime.utc(2026, 7, 9, 12);
    dir = await Directory.systemTemp.createTemp('push-envelope-staging-test-');
  });

  tearDown(() async {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  StagedPushEnvelope envelope({
    required String nonce,
    String? messageId = 'msg-1',
    String senderPeerId = 'peer-alice',
    int? receivedAtMs,
  }) {
    return StagedPushEnvelope(
      kind: 'chat',
      kem: 'kem-$nonce',
      ciphertext: 'cipher-$nonce',
      nonce: nonce,
      senderPeerId: senderPeerId,
      messageId: messageId,
      receivedAtMs: receivedAtMs ?? now.millisecondsSinceEpoch,
    );
  }

  test(
    'stage/readAll/clear round-trips across store re-instantiation; prune keeps fresh and uses nonce id',
    () async {
      final store = FilePushEnvelopeStagingStore(
        directory: dir,
        now: () => now,
        ttl: const Duration(hours: 48),
        maxEntries: 2,
      );
      await store.stage(envelope(nonce: 'nonce-a', messageId: null));
      await store.stage(envelope(nonce: 'nonce-b'));

      final reopened = FilePushEnvelopeStagingStore(
        directory: dir,
        now: () => now,
        ttl: const Duration(hours: 48),
        maxEntries: 2,
      );
      final entries = await reopened.readAll();
      expect(entries.map((e) => e.nonce), ['nonce-a', 'nonce-b']);
      expect(entries.first.id, 'nonce-a');
      expect(entries.first.messageId, isNull);

      await reopened.clear('nonce-a');
      expect((await reopened.readAll()).map((e) => e.nonce), ['nonce-b']);

      await reopened.stage(envelope(nonce: 'old', receivedAtMs: 1));
      await reopened.stage(
        envelope(
          nonce: 'fresh-extra',
          receivedAtMs: now.millisecondsSinceEpoch + 1,
        ),
      );
      final pruned = await reopened.readAll();
      expect(pruned.map((e) => e.nonce), ['nonce-b', 'fresh-extra']);
    },
  );

  test(
    'old malformed file is cleared, but a torn file younger than the retry window is retained',
    () async {
      final store = FilePushEnvelopeStagingStore(
        directory: dir,
        now: () => now,
        malformedRetryWindow: const Duration(seconds: 5),
      );
      final young = File('${dir.path}/young.json');
      final old = File('${dir.path}/old.json');
      await young.writeAsString('{"kind":"chat",');
      await old.writeAsString('{"kind":"chat",');
      await old.setLastModified(now.subtract(const Duration(minutes: 1)));

      final retained = await store.readAllWithStatus();
      expect(retained.entries, isEmpty);
      expect(retained.retainedUnreadableFinalFiles, 1);
      expect(await young.exists(), isTrue);
      expect(await old.exists(), isFalse);

      await young.setLastModified(now.subtract(const Duration(minutes: 1)));
      final afterAgedCleanup = await store.readAllWithStatus();
      expect(afterAgedCleanup.entries, isEmpty);
      expect(afterAgedCleanup.retainedUnreadableFinalFiles, 0);
      expect(await young.exists(), isFalse);

      final normalEmpty = await store.readAllWithStatus();
      expect(normalEmpty.entries, isEmpty);
      expect(normalEmpty.retainedUnreadableFinalFiles, 0);
    },
  );

  test('writes pinned JSON schema', () async {
    final store = FilePushEnvelopeStagingStore(directory: dir, now: () => now);
    await store.stage(envelope(nonce: 'schema', messageId: null));

    final files = await dir
        .list()
        .where((e) => e is File)
        .cast<File>()
        .toList();
    expect(files, hasLength(1));
    final json = jsonDecode(await files.single.readAsString()) as Map;
    expect(
      json.keys,
      containsAll(<String>[
        'kind',
        'kem',
        'ciphertext',
        'nonce',
        'senderPeerId',
        'messageId',
        'receivedAtMs',
      ]),
    );
    expect(json['messageId'], isNull);
  });

  test('base64 nonce file keys are injective and clearable', () async {
    final store = FilePushEnvelopeStagingStore(directory: dir, now: () => now);
    const base64Nonce = 'a+b/c=';
    const sanitizedCollision = 'a_b_c_';

    expect(
      pushEnvelopeStagingFileNameForNonce(base64Nonce),
      'nonce-v1-612b622f633d.json',
    );
    expect(
      pushEnvelopeStagingFileNameForNonce(sanitizedCollision),
      'nonce-v1-615f625f635f.json',
    );
    expect(
      pushEnvelopeStagingFileNameForNonce(base64Nonce),
      isNot(pushEnvelopeStagingFileNameForNonce(sanitizedCollision)),
    );

    await store.stage(envelope(nonce: base64Nonce));
    await store.stage(envelope(nonce: sanitizedCollision));

    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.json'))
        .cast<File>()
        .toList();
    expect(files.map((f) => f.uri.pathSegments.last).toSet(), {
      'nonce-v1-612b622f633d.json',
      'nonce-v1-615f625f635f.json',
    });
    expect((await store.readAll()).map((e) => e.nonce), [
      base64Nonce,
      sanitizedCollision,
    ]);

    await store.clear(base64Nonce);
    expect((await store.readAll()).map((e) => e.nonce), [sanitizedCollision]);
  });
}
