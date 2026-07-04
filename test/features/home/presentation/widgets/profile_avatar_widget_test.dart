import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/home/presentation/widgets/profile_avatar_widget.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('ProfileAvatarWidget', () {
    testWidgets('renders UserAvatar when no avatarBytes but peerId provided',
        (tester) async {
      await tester.pumpWidget(
          wrap(const ProfileAvatarWidget(peerId: 'peer-123')));
      expect(find.byType(UserAvatar), findsOneWidget);
    });

    testWidgets(
        'renders placeholder "?" when no avatarBytes and no peerId',
        (tester) async {
      await tester.pumpWidget(wrap(const ProfileAvatarWidget()));
      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('renders camera button when onCameraPressed is provided',
        (tester) async {
      await tester.pumpWidget(wrap(ProfileAvatarWidget(
        peerId: 'peer-123',
        onCameraPressed: () {},
      )));
      expect(find.byIcon(Icons.camera_alt), findsOneWidget);
    });

    testWidgets('hides camera button when onCameraPressed is null',
        (tester) async {
      await tester.pumpWidget(
          wrap(const ProfileAvatarWidget(peerId: 'peer-123')));
      expect(find.byIcon(Icons.camera_alt), findsNothing);
    });

    testWidgets('calls onCameraPressed when camera button tapped',
        (tester) async {
      var cameraTapped = false;
      await tester.pumpWidget(wrap(ProfileAvatarWidget(
        peerId: 'peer-123',
        onCameraPressed: () => cameraTapped = true,
      )));
      await tester.tap(find.byIcon(Icons.camera_alt));
      expect(cameraTapped, isTrue);
    });

    // 156 QW-4 (images-media-2, folded in): the onboarding profile avatar
    // decodes at display size via cacheWidth/cacheHeight. Memory-only (no
    // file/GIF branch).
    testWidgets(
      'TC-08b: Image.memory sets cacheWidth/cacheHeight to round(size*dpr)',
      (tester) async {
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.resetDevicePixelRatio);

        final bytes = Uint8List.fromList(<int>[1, 2, 3]);
        await tester.pumpWidget(
          wrap(ProfileAvatarWidget(avatarBytes: bytes, size: 80)),
        );

        final image = tester.widget<Image>(find.byType(Image));
        expect(image.image, isA<ResizeImage>());
        final resize = image.image as ResizeImage;
        expect(resize.width, (80 * 3.0).round()); // 240
        expect(resize.height, (80 * 3.0).round());
        // TC-200-05: aspect-safe decode (fit) on the profile avatar surface.
        expect(resize.policy, ResizeImagePolicy.fit);
        expect(resize.imageProvider, isA<MemoryImage>());
      },
    );
  });
}
