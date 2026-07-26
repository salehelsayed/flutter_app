import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/theme/app_theme.dart';
import 'package:flutter_app/core/utils/ring_avatar_generator.dart';
import 'package:flutter_app/features/feed/domain/models/feed_letter.dart';
import 'package:flutter_app/features/feed/domain/models/letter_line.dart';
import 'package:flutter_app/features/feed/domain/utils/group_sender_runs.dart';
import 'package:flutter_app/features/feed/presentation/widgets/letter_bubble.dart';
import 'package:flutter_app/features/feed/presentation/widgets/letter_card_group.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('letter_card_group_test');
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

  const maraPeer = 'peer-mara';
  const bobPeer = 'peer-bob';

  const letter = GroupLetter(
    groupId: 'g-1',
    groupName: 'The Crew',
    canWrite: true,
    runs: [
      SenderRun(
        senderPeerId: maraPeer,
        senderName: 'Mara',
        lines: [
          LetterLine(messageId: 'm1', text: 'mara one'),
          LetterLine(messageId: 'm2', text: 'mara two'),
        ],
      ),
      SenderRun(
        senderPeerId: bobPeer,
        senderName: 'Bob',
        lines: [LetterLine(messageId: 'b1', text: 'bob one')],
      ),
    ],
  );

  // Recursively collect every InlineSpan in a tree of TextSpans.
  List<TextSpan> flattenSpans(InlineSpan span) {
    final out = <TextSpan>[];
    if (span is TextSpan) {
      out.add(span);
      for (final child in span.children ?? const <InlineSpan>[]) {
        out.addAll(flattenSpans(child));
      }
    }
    return out;
  }

  // B1 + TC-17/TC-09: each sender run renders a size-32 photo-capable
  // UserAvatar keyed on the run's senderPeerId, an accent-coloured sender name
  // span, and all unread bubbles.
  testWidgets(
    'per run renders a size-32 UserAvatar (no glow/frame), an accent-coloured '
    'sender name span, and all unread bubbles (B1/TC-17/TC-09)',
    (tester) async {
      await tester.pumpWidget(mount(const LetterCardGroup(letter: letter)));
      await tester.pump();

      // One UserAvatar per run, each sized 32 and bare. On HEAD the runs wire
      // The group sender avatar is rendered by UserAvatar.
      final size32Avatars = find.byWidgetPredicate(
        (w) => w is UserAvatar && w.size == 32,
      );
      expect(size32Avatars, findsNWidgets(2));
      expect(
        tester
            .widgetList<UserAvatar>(size32Avatars)
            .every((a) => !a.showGlow && !a.showPhotoFrame),
        isTrue,
      );

      // The two runs use their own peerIds.
      final avatars = tester
          .widgetList<UserAvatar>(size32Avatars)
          .map((a) => a.peerId)
          .toSet();
      expect(avatars, {maraPeer, bobPeer});

      // Every unread line is rendered as a LetterBubble (no "N more").
      expect(find.byType(LetterBubble), findsNWidgets(3));
      final bubbles = tester
          .widgetList<LetterBubble>(find.byType(LetterBubble))
          .toList();
      expect(bubbles.every((b) => b.role == LetterBubbleRole.incoming), isTrue);
      expect(bubbles.map((b) => b.text).toList(), [
        'mara one',
        'mara two',
        'bob one',
      ]);

      // The sender-name span for each run is coloured with the per-peer accent.
      final spans = tester
          .widgetList<RichText>(find.byType(RichText))
          .expand((rt) => flattenSpans(rt.text))
          .toList();

      TextSpan spanFor(String name) => spans.firstWhere((s) => s.text == name);

      expect(
        spanFor('Mara').style?.color,
        RingAvatarGenerator.accentColorForPeerId(maraPeer),
      );
      expect(
        spanFor('Bob').style?.color,
        RingAvatarGenerator.accentColorForPeerId(bobPeer),
      );

      // The two accents differ (guards against a single constant colour).
      expect(
        RingAvatarGenerator.accentColorForPeerId(maraPeer),
        isNot(RingAvatarGenerator.accentColorForPeerId(bobPeer)),
      );

      // The group name appears in a meta span alongside the sender.
      expect(spans.any((s) => (s.text ?? '').contains('The Crew')), isTrue);
    },
  );

  // B1/TC-2: a sender run with a seeded avatar file renders its real photo,
  // while a run without one keeps the glyph fallback.
  testWidgets(
    'a sender run with a seeded avatar file renders its photo (B1/TC-2)',
    (tester) async {
      seedAvatar(maraPeer); // only Mara has a photo
      await tester.pumpWidget(mount(const LetterCardGroup(letter: letter)));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(find.byType(UserAvatar), findsNWidgets(2));
      // Exactly one run (Mara) resolves to an Image.file; Bob stays a glyph.
      expect(find.byType(Image), findsOneWidget);
    },
  );
}
