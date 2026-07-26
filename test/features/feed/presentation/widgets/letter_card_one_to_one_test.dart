import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/theme/app_theme.dart';
import 'package:flutter_app/features/feed/domain/models/feed_letter.dart';
import 'package:flutter_app/features/feed/domain/models/letter_line.dart';
import 'package:flutter_app/features/feed/presentation/widgets/letter_bubble.dart';
import 'package:flutter_app/features/feed/presentation/widgets/letter_card_one_to_one.dart';
import 'package:flutter_app/features/home/presentation/widgets/ring_avatar.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('letter_card_1to1_test');
    UserAvatar.setDocumentsDir(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  void seedAvatar(String peerId) {
    final dir = Directory('${tempDir.path}/media/avatars')
      ..createSync(recursive: true);
    File('${dir.path}/$peerId.jpg').writeAsBytesSync(<int>[0, 1, 2, 3]);
  }

  Widget mount(Widget card) {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(body: card),
    );
  }

  const letter = OneToOneLetter(
    peerId: 'peer-1to1',
    displayName: 'Contact Name',
    lines: [
      LetterLine(messageId: 'm1', text: 'first unread'),
      LetterLine(messageId: 'm2', text: 'second unread'),
    ],
  );

  // B1 + TC-16/TC-09: identity is carried by a photo-capable UserAvatar (size
  // 40, bare Feed look), one LetterBubble per text, and no contact-name header.
  testWidgets(
    'renders a size-40 UserAvatar (no glow/frame), one LetterBubble per text, '
    'and no name header (B1/TC-16/TC-09)',
    (tester) async {
      await tester.pumpWidget(mount(const LetterCardOneToOne(letter: letter)));
      await tester.pump();

      // A photo-capable UserAvatar keyed on the contact peerId, sized 40, with
      // the bare Feed look. The card wires UserAvatar directly
      // -> no UserAvatar -> red.
      final avatar = tester.widget<UserAvatar>(find.byType(UserAvatar));
      expect(avatar.peerId, 'peer-1to1');
      expect(avatar.size, 40);
      expect(avatar.showGlow, isFalse);
      expect(avatar.showPhotoFrame, isFalse);

      // One LetterBubble per unread text.
      expect(find.byType(LetterBubble), findsNWidgets(2));
      final bubbles = tester
          .widgetList<LetterBubble>(find.byType(LetterBubble))
          .toList();
      expect(bubbles.every((b) => b.role == LetterBubbleRole.incoming), isTrue);
      expect(bubbles.map((b) => b.text).toList(), [
        'first unread',
        'second unread',
      ]);

      // No contact-name header Text.
      expect(find.text('Contact Name'), findsNothing);

      // B1 fallback: with no avatar file on disk, the glyph RingAvatar shows
      // and no photo Image is mounted.
      expect(find.byType(RingAvatar), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    },
  );

  // B1/TC-1: the real photo renders when the avatar file exists.
  testWidgets(
    'renders the contact photo when the avatar file exists (B1/TC-1)',
    (tester) async {
      seedAvatar('peer-photo');
      await tester.pumpWidget(
        mount(
          const LetterCardOneToOne(
            letter: OneToOneLetter(
              peerId: 'peer-photo',
              displayName: 'Has Photo',
              lines: [LetterLine(messageId: 'm1', text: 'hi')],
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(find.byType(UserAvatar), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    },
  );

  // B1/TC-4: a card photo refreshes live (without a remount) when a friend
  // changes their picture and UserAvatar.invalidatePeer fires — the Image.file
  // ValueKey (the ?v=N cache-bust suffix) advances.
  testWidgets(
    'a card photo refreshes live when UserAvatar.invalidatePeer fires (B1/TC-4)',
    (tester) async {
      seedAvatar('peer-live');
      await tester.pumpWidget(
        mount(
          const LetterCardOneToOne(
            letter: OneToOneLetter(
              peerId: 'peer-live',
              displayName: 'Live',
              lines: [LetterLine(messageId: 'm1', text: 'hi')],
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      final keyBefore =
          (tester.widget<Image>(find.byType(Image)).key as ValueKey).value
              as String;

      // Friend replaces their photo at the same path; invalidate busts cache.
      seedAvatar('peer-live');
      UserAvatar.invalidatePeer('peer-live');
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      final keyAfter =
          (tester.widget<Image>(find.byType(Image)).key as ValueKey).value
              as String;
      expect(keyAfter, isNot(keyBefore));
    },
  );

  // The focused flag forwards to the incoming bubbles.
  testWidgets('forwards focused flag to its LetterBubbles', (tester) async {
    await tester.pumpWidget(
      mount(const LetterCardOneToOne(letter: letter, focused: true)),
    );
    await tester.pump();

    final bubbles = tester
        .widgetList<LetterBubble>(find.byType(LetterBubble))
        .toList();
    expect(bubbles.every((b) => b.focused), isTrue);
  });
}
