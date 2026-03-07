import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/home/application/identity_avatar_resolver.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

void main() {
  late Directory tempDir;

  IdentityModel buildIdentity({
    String peerId = 'peer-1',
    Uint8List? avatarBlob,
    String? avatarVersion = '2026-03-07T12:00:00.000Z',
  }) {
    return IdentityModel(
      peerId: peerId,
      publicKey: 'pk-$peerId',
      privateKey: 'sk-$peerId',
      mnemonic12:
          'one two three four five six seven eight nine ten eleven twelve',
      username: 'Alice',
      avatarBlob: avatarBlob,
      avatarVersion: avatarVersion,
      createdAt: '2026-03-07T10:00:00.000Z',
      updatedAt: '2026-03-07T10:00:00.000Z',
    );
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'identity_avatar_resolver_test',
    );
  });

  tearDown(() async {
    IdentityAvatarResolver.invalidatePeer('peer-1');
    IdentityAvatarResolver.invalidatePeer('peer-2');
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('returns avatar blob immediately when present', () async {
    final blob = Uint8List.fromList(<int>[1, 2, 3]);
    final resolved = await IdentityAvatarResolver.resolve(
      buildIdentity(avatarBlob: blob),
      documentsDirLoader: () async => tempDir.path,
    );

    expect(resolved, same(blob));
  });

  test('returns null when no avatar version and no blob exist', () async {
    final resolved = await IdentityAvatarResolver.resolve(
      buildIdentity(avatarVersion: null),
      documentsDirLoader: () async => tempDir.path,
    );

    expect(resolved, isNull);
  });

  test('reads avatar bytes from disk and caches misses/hits', () async {
    final identity = buildIdentity();
    final avatarsDir = Directory('${tempDir.path}/media/avatars')
      ..createSync(recursive: true);
    final file = File('${avatarsDir.path}/${identity.peerId}.jpg');
    await file.writeAsBytes(<int>[9, 8, 7]);

    final first = await IdentityAvatarResolver.resolve(
      identity,
      documentsDirLoader: () async => tempDir.path,
    );
    expect(first, Uint8List.fromList(<int>[9, 8, 7]));

    await file.writeAsBytes(<int>[1, 1, 1]);

    final second = await IdentityAvatarResolver.resolve(
      identity,
      documentsDirLoader: () async => tempDir.path,
    );
    expect(second, Uint8List.fromList(<int>[9, 8, 7]));
  });

  test('stale in-flight future does not pollute cache after invalidation',
      () async {
    final identity = buildIdentity();
    final avatarsDir = Directory('${tempDir.path}/media/avatars')
      ..createSync(recursive: true);
    final file = File('${avatarsDir.path}/${identity.peerId}.jpg');
    await file.writeAsBytes(<int>[10, 20, 30]);

    // First resolve — populates cache
    final first = await IdentityAvatarResolver.resolve(
      identity,
      documentsDirLoader: () async => tempDir.path,
    );
    expect(first, Uint8List.fromList(<int>[10, 20, 30]));

    // Write new file, invalidate, then resolve with new version
    await file.writeAsBytes(<int>[40, 50, 60]);
    IdentityAvatarResolver.invalidatePeer(identity.peerId);

    final updatedIdentity = buildIdentity(
      avatarVersion: '2026-03-07T14:00:00.000Z',
    );
    final second = await IdentityAvatarResolver.resolve(
      updatedIdentity,
      documentsDirLoader: () async => tempDir.path,
    );
    expect(second, Uint8List.fromList(<int>[40, 50, 60]));

    // Resolve again — should return cached new bytes, not stale
    final third = await IdentityAvatarResolver.resolve(
      updatedIdentity,
      documentsDirLoader: () async => tempDir.path,
    );
    expect(third, Uint8List.fromList(<int>[40, 50, 60]));
  });

  test('invalidatePeer forces a reload for a newer avatar version', () async {
    final identity = buildIdentity();
    final avatarsDir = Directory('${tempDir.path}/media/avatars')
      ..createSync(recursive: true);
    final file = File('${avatarsDir.path}/${identity.peerId}.jpg');
    await file.writeAsBytes(<int>[5, 4, 3]);

    final first = await IdentityAvatarResolver.resolve(
      identity,
      documentsDirLoader: () async => tempDir.path,
    );
    expect(first, Uint8List.fromList(<int>[5, 4, 3]));

    await file.writeAsBytes(<int>[2, 2, 2]);
    IdentityAvatarResolver.invalidatePeer(identity.peerId);

    final updated = await IdentityAvatarResolver.resolve(
      buildIdentity(avatarVersion: '2026-03-07T13:00:00.000Z'),
      documentsDirLoader: () async => tempDir.path,
    );
    expect(updated, Uint8List.fromList(<int>[2, 2, 2]));
  });
}
