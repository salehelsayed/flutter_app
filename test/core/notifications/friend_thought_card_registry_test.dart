import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/friend_thought_card_registry.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('friend-thought-cards-');
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  test(
    'a newer card for the same friend retires the previous one once',
    () async {
      final registry = FriendThoughtCardRegistry(directory: directory);

      expect(
        await registry.claim(senderPeerId: 'peer-bob', cardKey: 'post:bob-1'),
        (current: true, retired: null),
      );
      expect(
        await registry.claim(senderPeerId: 'peer-bob', cardKey: 'post:bob-2'),
        (current: true, retired: 'post:bob-1'),
      );
      expect(
        await registry.claim(senderPeerId: 'peer-bob', cardKey: 'post:bob-2'),
        (current: true, retired: null),
        reason: 'a replayed claim must not retire the card it just recorded',
      );
    },
  );

  test('a card behind the newest is superseded, not restored', () async {
    final registry = FriendThoughtCardRegistry(directory: directory);
    await registry.claim(senderPeerId: 'peer-bob', cardKey: 'post:bob-1');
    await registry.claim(senderPeerId: 'peer-bob', cardKey: 'post:bob-2');

    expect(
      await registry.claim(senderPeerId: 'peer-bob', cardKey: 'post:bob-1'),
      (current: false, retired: null),
    );
    expect(
      await registry.claim(senderPeerId: 'peer-bob', cardKey: 'post:bob-3'),
      (current: true, retired: 'post:bob-2'),
      reason: 'the superseded claim must not have become the current card',
    );
  });

  test('each friend holds a slot of their own', () async {
    final registry = FriendThoughtCardRegistry(directory: directory);
    await registry.claim(senderPeerId: 'peer-bob', cardKey: 'post:bob-1');

    expect(
      await registry.claim(senderPeerId: 'peer-cat', cardKey: 'post:cat-1'),
      (current: true, retired: null),
    );
    expect(
      await registry.claim(senderPeerId: 'peer-bob', cardKey: 'post:bob-2'),
      (current: true, retired: 'post:bob-1'),
    );
  });

  test('a second isolate sees the slot through the shared directory', () async {
    final background = FriendThoughtCardRegistry(directory: directory);
    final foreground = FriendThoughtCardRegistry(directory: directory);
    await background.claim(senderPeerId: 'peer-bob', cardKey: 'post:bob-1');

    expect(
      await foreground.claim(senderPeerId: 'peer-bob', cardKey: 'post:bob-2'),
      (current: true, retired: 'post:bob-1'),
    );
    expect(
      await background.claim(senderPeerId: 'peer-bob', cardKey: 'post:bob-2'),
      (current: true, retired: null),
    );
  });

  test('the slot directory names no peer id', () async {
    await FriendThoughtCardRegistry(
      directory: directory,
    ).claim(senderPeerId: 'peer-bob', cardKey: 'post:bob-1');

    final names = directory
        .listSync()
        .map((entity) => entity.uri.pathSegments.last)
        .where((name) => !name.startsWith('.'))
        .toList();
    expect(names, hasLength(1));
    expect(names.single, matches(RegExp(r'^[0-9a-f]{64}$')));
  });
}
