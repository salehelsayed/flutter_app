import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/theme/app_theme.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/models/feed_letter.dart';
import 'package:flutter_app/features/feed/presentation/widgets/letter_bubble.dart';
import 'package:flutter_app/features/feed/presentation/widgets/letter_card_system.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('letter_card_system_test');
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

  Widget mount(Widget card, {Locale locale = const Locale('en')}) {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: card),
    );
  }

  const connection = SystemLetter(
    contactPeerId: 'peer-sys',
    displayName: 'Newbie',
  );

  const introduction = SystemLetter(
    contactPeerId: 'peer-sys-2',
    displayName: 'Newbie',
    introducedBy: 'Alice',
    introducedByPeerId: 'peer-alice',
  );

  SystemLetter savedContact(String? key, {bool introduced = false}) =>
      SystemLetter.fromConnection(
        ConnectionFeedItem.fromContact(
          ContactModel(
            peerId: 'bl11-saved-contact',
            publicKey: 'identity-key',
            rendezvous: '/dns4/relay/tcp/443',
            username: 'Newbie',
            signature: 'signature',
            scannedAt: '2026-11-12T10:00:00Z',
            mlKemPublicKey: key,
            introducedBy: introduced ? 'Alice' : null,
          ),
        ),
      );

  const waitingLabels = {
    'en': 'Waiting for secure connection',
    'ar': 'في انتظار اتصال آمن',
    'de': 'Warten auf eine sichere Verbindung',
  };
  for (final entry in waitingLabels.entries) {
    testWidgets('BL11 Feed does not verify a keyless contact in ${entry.key}', (
      tester,
    ) async {
      for (final key in <String?>[null, '', '  \n ']) {
        await tester.pumpWidget(
          mount(
            LetterCardSystem(letter: savedContact(key)),
            locale: Locale(entry.key),
          ),
        );
        await tester.pump();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(LetterCardSystem)),
        )!;
        expect(find.text(entry.value), findsOneWidget);
        expect(find.text(l10n.feed_connected), findsNothing);
        expect(find.byIcon(Icons.verified), findsNothing);
      }

      await tester.pumpWidget(
        mount(
          LetterCardSystem(letter: savedContact('reciprocal-key')),
          locale: Locale(entry.key),
        ),
      );
      await tester.pump();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(LetterCardSystem)),
      )!;
      expect(find.text(entry.value), findsNothing);
      expect(find.text(l10n.feed_connected), findsOneWidget);
      expect(find.byIcon(Icons.verified), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        mount(
          LetterCardSystem(letter: savedContact(null)),
          locale: Locale(entry.key),
        ),
      );
      await tester.pump();
      expect(find.text(entry.value), findsOneWidget);
    });
  }

  testWidgets('BL11 keyless introduction keeps its provenance and action', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      mount(
        LetterCardSystem(
          letter: savedContact(null, introduced: true),
          onSendMessage: () => taps++,
        ),
      ),
    );
    await tester.pump();
    expect(find.text(waitingLabels['en']!), findsOneWidget);
    expect(find.text('Introduced by Alice'), findsOneWidget);
    expect(find.byIcon(Icons.verified), findsNothing);
    await tester.tap(find.text('tap to say hi'));
    expect(taps, 1);
  });

  // B1 + TC-18: new-connection variant renders a size-40 photo-capable
  // UserAvatar, a Connected label, and a single system green LetterBubble.
  testWidgets(
    'connection renders a size-40 UserAvatar (no glow/frame), a Connected '
    'label, and a single system green LetterBubble (B1/TC-18)',
    (tester) async {
      await tester.pumpWidget(
        mount(const LetterCardSystem(letter: connection)),
      );
      await tester.pump();

      // A photo-capable UserAvatar keyed on the contact peerId, sized 40, bare.
      // The system sender avatar is rendered by UserAvatar.
      final avatar = tester.widget<UserAvatar>(find.byType(UserAvatar));
      expect(avatar.peerId, 'peer-sys');
      expect(avatar.size, 40);
      expect(avatar.showGlow, isFalse);
      expect(avatar.showPhotoFrame, isFalse);

      // Muted "Connected"-style label.
      expect(find.text('Connected'), findsOneWidget);

      // Exactly one system bubble.
      final bubbles = tester
          .widgetList<LetterBubble>(find.byType(LetterBubble))
          .toList();
      expect(bubbles.length, 1);
      expect(bubbles.single.role, LetterBubbleRole.system);
      expect(bubbles.single.text, 'tap to say hi');

      // The introduction label must NOT appear for a plain connection.
      expect(find.textContaining('Introduced by'), findsNothing);
    },
  );

  // B1/TC-3: a seeded avatar file renders the real photo on the system card.
  testWidgets(
    'system card renders the contact photo when the avatar file exists '
    '(B1/TC-3)',
    (tester) async {
      seedAvatar('peer-sys');
      await tester.pumpWidget(
        mount(const LetterCardSystem(letter: connection)),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(find.byType(UserAvatar), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    },
  );

  // TC-18: introduction variant.
  testWidgets('introduction renders an "Introduced by Alice" label (TC-18)', (
    tester,
  ) async {
    await tester.pumpWidget(
      mount(const LetterCardSystem(letter: introduction)),
    );
    await tester.pump();

    expect(find.text('Introduced by Alice'), findsOneWidget);
    // Not the plain-connection label.
    expect(find.text('Connected'), findsNothing);
  });

  // TC-18b: tapping the system bubble fires onSendMessage.
  testWidgets('tapping the system bubble invokes onSendMessage (TC-18b)', (
    tester,
  ) async {
    var called = false;
    await tester.pumpWidget(
      mount(
        LetterCardSystem(
          letter: connection,
          onSendMessage: () => called = true,
        ),
      ),
    );
    await tester.pump();

    expect(called, isFalse);
    await tester.tap(find.text('tap to say hi'));
    await tester.pump();

    expect(called, isTrue);
  });
}
