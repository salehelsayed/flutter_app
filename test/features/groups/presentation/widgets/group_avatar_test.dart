import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/presentation/widgets/group_avatar.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  // 156 QW-4 (images-media-1, group surface): GroupAvatar must decode at display
  // size via cacheWidth/cacheHeight on BOTH the memory and (non-gif) file
  // branches; the gif file branch stays exempt so animation survives.
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('group_avatar_test');
    UserAvatar.setDocumentsDir(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets(
    'TC-08: Image.memory sets cacheWidth/cacheHeight to round(size*dpr)',
    (tester) async {
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetDevicePixelRatio);

      final bytes = Uint8List.fromList(<int>[1, 2, 3]);
      await tester.pumpWidget(
        _wrap(GroupAvatar(
          groupId: 'g1',
          name: 'Group',
          avatarBytes: bytes,
          size: 48,
        )),
      );

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<ResizeImage>());
      final resize = image.image as ResizeImage;
      expect(resize.width, (48 * 3.0).round()); // 144
      expect(resize.height, (48 * 3.0).round());
    },
  );

  testWidgets(
    'TC-08: Image.file (non-gif) sets cacheWidth/cacheHeight to round(size*dpr)',
    (tester) async {
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetDevicePixelRatio);

      final file = File('${tempDir.path}/group-photo.jpg')
        ..writeAsBytesSync(<int>[0, 1, 2, 3]);

      await tester.pumpWidget(
        _wrap(GroupAvatar(
          groupId: 'g2',
          name: 'Group',
          avatarPath: file.path,
          size: 40,
        )),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<ResizeImage>());
      final resize = image.image as ResizeImage;
      expect(resize.width, (40 * 2.0).round()); // 80
      expect(resize.height, (40 * 2.0).round());
    },
  );

  testWidgets(
    'Image.file (gif) is EXEMPT from cacheWidth (animation survives)',
    (tester) async {
      // Guard lock (not RED-first): a .gif must NOT be routed through
      // ResizeImage, which would collapse it to first-frame. Mutating the impl
      // to apply cacheWidth unconditionally re-reds this.
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetDevicePixelRatio);

      final file = File('${tempDir.path}/group-photo.gif')
        ..writeAsBytesSync(<int>[0, 1, 2, 3]);

      await tester.pumpWidget(
        _wrap(GroupAvatar(
          groupId: 'g3',
          name: 'Group',
          avatarPath: file.path,
          size: 40,
        )),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isNot(isA<ResizeImage>()));
    },
  );
}
