import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_app/core/theme/app_theme.dart';
import 'package:flutter_app/features/contact_profile/presentation/screens/contact_profile_screen.dart';
import 'package:flutter_app/features/contact_request/presentation/pending_contact_retry_scope.dart';
import 'package:flutter_app/features/contacts/application/direct_contact_device_trust.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/conversation_header.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/models/feed_letter.dart';
import 'package:flutter_app/features/feed/presentation/widgets/letter_card_system.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/friend_row.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../conversation/domain/repositories/fake_message_repository.dart';
import '../support/interest_retry_fixture.dart';

void main() {
  late Directory avatars;
  setUp(() {
    avatars = Directory.systemTemp.createTempSync('interest-retry-');
    UserAvatar.setDocumentsDir(avatars.path);
  });
  tearDown(() => avatars.deleteSync(recursive: true));

  Widget surface(String name, InterestRetryFixture f) => switch (name) {
    'Orbit' => FriendRow(
      friend: OrbitFriend(contact: f.contact, messageCount: 0),
      onTap: () {},
    ),
    'chat' => ConversationHeader(
      contactPeerId: interestPeer,
      contactUsername: 'Alice',
      isWaitingForSecureConnection: true,
      onBack: () {},
      onSearch: () {},
      onOverflow: () {},
    ),
    _ => LetterCardSystem(
      letter: SystemLetter.fromConnection(
        ConnectionFeedItem.fromContact(f.contact),
      ),
    ),
  };

  for (final name in ['Orbit', 'chat', 'Feed']) {
    for (final locale in ['en', 'ar', 'de']) {
      testWidgets('E3 $name stopped hint $locale wraps and clears on restart', (
        tester,
      ) async {
        final f = InterestRetryFixture();
        final retrier = f.retrier();
        tester.view.reset();
        tester.view.physicalSize = const Size(320, 1400);
        tester.view.devicePixelRatio = 1;
        try {
          await withClock(Clock(() => f.now), () async {
            await retrier.refreshRetryStatus();
            await tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.darkTheme,
                locale: Locale(locale),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(2)),
                  child: PendingContactRetryScope(
                    retrier: retrier,
                    child: child!,
                  ),
                ),
                home: Scaffold(body: surface(name, f)),
              ),
            );
            await tester.pump();
            final hint = find.text(approvedInterestHints[locale]!);
            expect(hint, findsOneWidget);
            final text = tester.widget<Text>(hint);
            expect(text.maxLines, isNull);
            expect(text.overflow, isNot(TextOverflow.ellipsis));
            final paragraph = tester.renderObject<RenderParagraph>(hint);
            expect(paragraph.didExceedMaxLines, isFalse);
            final rect = tester.getRect(hint);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(320));
            expect(tester.takeException(), isNull);
            expect(await retrier.retryOnInterest(interestPeer), 1);
            await tester.pump();
            expect(hint, findsNothing);
          });
        } finally {
          // Dispose widget animations and retry expiry timer before binding verification.
          await tester.pumpWidget(const SizedBox.shrink());
          retrier.dispose();
          f.dispose();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        }
      });
    }
  }

  for (final entry in ['chat', 'profile']) {
    testWidgets('E3 real $entry opening restarts once across repeated routes', (
      tester,
    ) async {
      final f = InterestRetryFixture();
      final retrier = f.retrier();
      final messages = FakeMessageRepository();
      final listener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messages,
        contactRepo: f.contacts,
      );
      Widget route() => entry == 'chat'
          ? ConversationWired(
              contact: f.contact,
              identityRepo: f.identities,
              messageRepo: messages,
              chatMessageListener: listener,
              p2pService: f.transport,
              contactRepo: f.contacts,
            )
          : ContactProfileScreen(
              contact: f.contact,
              directDeviceTrust: const UnavailableDirectContactDeviceTrust(),
            );
      try {
        await withClock(Clock(() => f.now), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.darkTheme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (_, child) =>
                  PendingContactRetryScope(retrier: retrier, child: child!),
              home: Builder(
                builder: (context) => TextButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute<void>(builder: (_) => route())),
                  child: const Text('open'),
                ),
              ),
            ),
          );
          for (var i = 0; i < 2; i++) {
            await tester.tap(find.text('open'));
            // Bounded pumping: profile and ambient background animate continuously.
            for (var frame = 0; frame < 12; frame++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
            expect(f.transport.storeInInboxCallCount, 1);
            final context = tester.element(
              find.byType(
                entry == 'chat' ? ConversationWired : ContactProfileScreen,
              ),
            );
            Navigator.of(context).pop();
            await tester.pump(const Duration(milliseconds: 500));
          }
          expect(tester.takeException(), isNull);
        });
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        retrier.dispose();
        f.dispose();
      }
    });
  }
}
