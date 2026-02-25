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
  });
}
