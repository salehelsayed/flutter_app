import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/home/presentation/widgets/editable_username_widget.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_profile_section.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  testWidgets('renders RingAvatar when peerId provided, no avatarBytes', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(
      const SettingsProfileSection(
        peerId: '12D3KooWTestPeer123',
        username: 'Alice',
      ),
    ));

    // RingAvatar renders a CustomPaint
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('mknoon/'), findsOneWidget);
    expect(find.text('@Alice'), findsOneWidget);
  });

  testWidgets('renders Image.memory when avatarBytes provided', (
    tester,
  ) async {
    // 1x1 transparent PNG
    final bytes = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00,
      0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00,
      0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
      0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x62,
      0x00, 0x00, 0x00, 0x02, 0x00, 0x01, 0xE5, 0x27, 0xDE, 0xFC, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);

    await tester.pumpWidget(wrap(
      SettingsProfileSection(
        avatarBytes: bytes,
        username: 'Bob',
      ),
    ));

    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('renders fallback person icon when neither peerId nor avatar', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(
      const SettingsProfileSection(username: 'Charlie'),
    ));

    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
  });

  testWidgets('shows teal camera button overlay', (tester) async {
    await tester.pumpWidget(wrap(
      const SettingsProfileSection(
        peerId: '12D3KooWTestPeer123',
        username: 'Alice',
      ),
    ));

    expect(find.byIcon(Icons.camera_alt), findsOneWidget);
  });

  testWidgets('shows mknoon/@username text', (tester) async {
    await tester.pumpWidget(wrap(
      const SettingsProfileSection(
        peerId: '12D3KooWTestPeer123',
        username: 'Dana',
      ),
    ));

    expect(find.text('mknoon/'), findsOneWidget);
    expect(find.text('@Dana'), findsOneWidget);
  });

  testWidgets('tapping camera button calls onPickAvatar', (tester) async {
    var tapped = false;
    await tester.pumpWidget(wrap(
      SettingsProfileSection(
        peerId: '12D3KooWTestPeer123',
        username: 'Alice',
        onPickAvatar: () => tapped = true,
      ),
    ));

    await tester.tap(find.byIcon(Icons.camera_alt));
    expect(tapped, isTrue);
  });

  testWidgets('renders EditableUsernameWidget', (tester) async {
    await tester.pumpWidget(wrap(
      const SettingsProfileSection(
        peerId: '12D3KooWTestPeer123',
        username: 'Alice',
      ),
    ));

    expect(find.byType(EditableUsernameWidget), findsOneWidget);
  });

  testWidgets('tapping edit icon enters editing mode', (tester) async {
    String? changed;
    await tester.pumpWidget(wrap(
      SettingsProfileSection(
        peerId: '12D3KooWTestPeer123',
        username: 'Alice',
        onUsernameChanged: (v) => changed = v,
      ),
    ));

    // Tap to enter editing mode (edit icon is part of EditableUsernameWidget)
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pump();

    // TextField should appear
    expect(find.byType(TextField), findsOneWidget);

    // Type a new name and submit
    await tester.enterText(find.byType(TextField), 'Bob');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(changed, 'Bob');
  });
}
