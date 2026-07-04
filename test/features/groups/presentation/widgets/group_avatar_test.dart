import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

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
      // TC-200-01: aspect-safe decode (fit), not the default exact that squashes
      // non-square sources; errorBuilder fallback preserved through the rewrite.
      expect(resize.policy, ResizeImagePolicy.fit);
      expect(resize.imageProvider, isA<MemoryImage>());
      expect(image.errorBuilder, isNotNull);
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
      // TC-200-02: aspect-safe decode (fit) on the non-gif file branch.
      expect(resize.policy, ResizeImagePolicy.fit);
      expect(resize.imageProvider, isA<FileImage>());
      expect(image.errorBuilder, isNotNull);
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

  testWidgets(
    'TC-200-07: oversized non-square avatar bytes decode with preserved aspect',
    (tester) async {
      // The source MUST exceed the decode target box (144x144) in BOTH dims,
      // otherwise ResizeImage (allowUpscaling:false) clamps to intrinsic dims
      // and both exact + fit decode identically — a vacuous, always-green test.
      // 288x144 (2:1) is safely above the box.
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetDevicePixelRatio);

      late Uint8List pngBytes;
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 288, 144),
          Paint()..color = const Color(0xFF3366CC),
        );
        final uiImage = await recorder.endRecording().toImage(288, 144);
        final data = await uiImage.toByteData(
          format: ui.ImageByteFormat.png,
        );
        pngBytes = data!.buffer.asUint8List();
      });

      await tester.pumpWidget(
        _wrap(GroupAvatar(
          groupId: 'g-aspect',
          name: 'Group',
          avatarBytes: pngBytes,
          size: 48, // dpr 3.0 -> decode target 144
        )),
      );

      final provider = tester.widget<Image>(find.byType(Image)).image;
      late ui.Image decoded;
      await tester.runAsync(() async {
        final completer = Completer<ui.Image>();
        final stream = provider.resolve(const ImageConfiguration());
        late ImageStreamListener listener;
        listener = ImageStreamListener(
          (info, _) {
            if (!completer.isCompleted) completer.complete(info.image);
            stream.removeListener(listener);
          },
          onError: (error, _) {
            if (!completer.isCompleted) completer.completeError(error);
          },
        );
        stream.addListener(listener);
        decoded = await completer.future;
      });

      // exact policy (HEAD) squashes 288x144 -> 144x144 (ratio 1.0).
      // fit policy (fixed) decodes 144x72 (ratio 2.0), preserving aspect.
      expect(decoded.width / decoded.height, closeTo(2.0, 0.05));
    },
  );
}
