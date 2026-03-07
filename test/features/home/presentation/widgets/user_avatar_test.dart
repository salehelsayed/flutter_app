import 'dart:io';

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

    expect(listenable.value, endsWith('$peerId.jpg'));
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

    expect(listenable.value, endsWith('$peerId.jpg'));
  });
}
