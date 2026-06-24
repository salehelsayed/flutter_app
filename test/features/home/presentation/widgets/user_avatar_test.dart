import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/home/presentation/widgets/ring_avatar.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('user_avatar_test');
    UserAvatar.setDocumentsDir(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('Image.memory gets unique key when avatarBytes changes', (
    tester,
  ) async {
    final bytesA = Uint8List.fromList(<int>[1, 2, 3]);
    final bytesB = Uint8List.fromList(<int>[4, 5, 6]);

    await tester.pumpWidget(
      _wrap(UserAvatar(peerId: 'abc', avatarBytes: bytesA, size: 42)),
    );

    final imageA = tester.widget<Image>(find.byType(Image));
    final keyA = imageA.key as ValueKey;

    await tester.pumpWidget(
      _wrap(UserAvatar(peerId: 'abc', avatarBytes: bytesB, size: 42)),
    );

    final imageB = tester.widget<Image>(find.byType(Image));
    final keyB = imageB.key as ValueKey;

    expect(keyA, isNot(equals(keyB)),
        reason: 'Different bytes must produce different Image keys');
  });

  testWidgets('renders ring avatar when no file exists', (tester) async {
    await tester.pumpWidget(_wrap(const UserAvatar(peerId: 'missing-peer')));
    await tester.pumpAndSettle();

    expect(find.byType(RingAvatar), findsOneWidget);
  });

  testWidgets('resolves file avatar path asynchronously outside build', (
    tester,
  ) async {
    const peerId = 'peer-file';
    final avatarsDir = Directory('${tempDir.path}/media/avatars')
      ..createSync(recursive: true);
    final avatarFile = File('${avatarsDir.path}/$peerId.jpg');
    avatarFile.writeAsBytesSync(<int>[0, 1, 2, 3]);

    final listenable = UserAvatar.avatarPathListenable(peerId);

    await tester.pumpWidget(_wrap(const UserAvatar(peerId: peerId)));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    expect(listenable.value, contains('$peerId.jpg'));
  });

  testWidgets('invalidatePeer reloads a newly written avatar path', (
    tester,
  ) async {
    const peerId = 'late-avatar-peer';

    await tester.pumpWidget(_wrap(const UserAvatar(peerId: peerId)));
    await tester.pumpAndSettle();
    expect(find.byType(RingAvatar), findsOneWidget);

    final listenable = UserAvatar.avatarPathListenable(peerId);
    expect(listenable.value, isNull);

    final avatarsDir = Directory('${tempDir.path}/media/avatars')
      ..createSync(recursive: true);
    final avatarFile = File('${avatarsDir.path}/$peerId.jpg');
    avatarFile.writeAsBytesSync(<int>[0, 1, 2, 3]);

    UserAvatar.invalidatePeer(peerId);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    expect(listenable.value, contains('$peerId.jpg'));
  });

  // ---------------------------------------------------------------------------
  // 156 QW-4 (images-media-1): decode sized to display via cacheWidth/Height.
  // ---------------------------------------------------------------------------
  testWidgets(
    'TC-06: Image.memory avatar sets cacheWidth/cacheHeight to round(size*dpr)',
    (tester) async {
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetDevicePixelRatio);

      final bytes = Uint8List.fromList(<int>[1, 2, 3]);
      await tester.pumpWidget(
        _wrap(UserAvatar(peerId: 'abc', avatarBytes: bytes, size: 42)),
      );

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<ResizeImage>());
      final resize = image.image as ResizeImage;
      expect(resize.width, (42 * 3.0).round()); // 126
      expect(resize.height, (42 * 3.0).round());
    },
  );

  testWidgets(
    'TC-07: Image.file avatar sets cacheWidth/cacheHeight to round(size*dpr)',
    (tester) async {
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetDevicePixelRatio);

      const peerId = 'peer-file-cache';
      final avatarsDir = Directory('${tempDir.path}/media/avatars')
        ..createSync(recursive: true);
      File('${avatarsDir.path}/$peerId.jpg').writeAsBytesSync(<int>[0, 1, 2, 3]);

      await tester.pumpWidget(
        _wrap(const UserAvatar(peerId: peerId, size: 50)),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<ResizeImage>());
      final resize = image.image as ResizeImage;
      expect(resize.width, (50 * 2.0).round()); // 100
      expect(resize.height, (50 * 2.0).round());
    },
  );
}
