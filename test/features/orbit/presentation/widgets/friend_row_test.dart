import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/media_preview_descriptor.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/friend_row.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

OrbitFriend _makeFriend({
  int unreadCount = 3,
  String? lastActivity,
  String username = 'Alice',
  MediaPreviewDescriptor? latestMedia,
  bool isLatestDeleted = false,
}) {
  return OrbitFriend(
    contact: ContactModel(
      peerId: 'peer-1234567890',
      publicKey: 'pk-1',
      rendezvous: '/dns4/relay/tcp/443',
      username: username,
      signature: 'sig-1',
      scannedAt: '2026-01-01T00:00:00.000Z',
    ),
    messageCount: 5,
    lastActivity: lastActivity,
    unreadCount: unreadCount,
    latestMedia: latestMedia,
    isLatestDeleted: isLatestDeleted,
  );
}

void main() {
  group('FriendRow', () {
    Widget wrap(Widget child) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

    Text _textFor(WidgetTester tester, String text) {
      final finder = find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == text,
        description: 'Text("$text")',
      );
      expect(finder, findsOneWidget);
      return tester.widget<Text>(finder);
    }

    testWidgets('shows unread badge by default when unreadCount > 0', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(FriendRow(friend: _makeFriend(unreadCount: 3), onTap: () {})),
      );
      await tester.pumpAndSettle();

      // UnreadCountBadge renders the count as text
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('hides unread badge when hideUnreadBadge is true', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          FriendRow(
            friend: _makeFriend(unreadCount: 3),
            hideUnreadBadge: true,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The count text should not appear
      expect(find.text('3'), findsNothing);
    });

    testWidgets('shows chevron when no unread messages', (tester) async {
      await tester.pumpWidget(
        wrap(FriendRow(friend: _makeFriend(unreadCount: 0), onTap: () {})),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('Arabic lastActivity drives RTL', (tester) async {
      const lastActivity = 'مرحبا';

      await tester.pumpWidget(
        wrap(
          FriendRow(
            friend: _makeFriend(lastActivity: lastActivity, unreadCount: 0),
            onTap: () {},
          ),
        ),
      );

      expect(_textFor(tester, lastActivity).textDirection, TextDirection.rtl);
    });

    testWidgets('Arabic-first mixed lastActivity drives RTL', (tester) async {
      const lastActivity = 'مرحبا Hello 123';

      await tester.pumpWidget(
        wrap(
          FriendRow(
            friend: _makeFriend(lastActivity: lastActivity, unreadCount: 0),
            onTap: () {},
          ),
        ),
      );

      expect(_textFor(tester, lastActivity).textDirection, TextDirection.rtl);
    });

    testWidgets('English-first mixed lastActivity drives LTR', (tester) async {
      const lastActivity = 'Hello مرحبا 123';

      await tester.pumpWidget(
        wrap(
          FriendRow(
            friend: _makeFriend(lastActivity: lastActivity, unreadCount: 0),
            onTap: () {},
          ),
        ),
      );

      expect(_textFor(tester, lastActivity).textDirection, TextDirection.ltr);
    });

    testWidgets('media-only voice note shows a localized label', (tester) async {
      await tester.pumpWidget(
        wrap(
          FriendRow(
            friend: _makeFriend(
              lastActivity: '',
              unreadCount: 0,
              latestMedia: const MediaPreviewDescriptor(
                type: 'audio',
                count: 1,
              ),
            ),
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Voice message'), findsOneWidget);
    });

    testWidgets('multiple images show a counted label', (tester) async {
      await tester.pumpWidget(
        wrap(
          FriendRow(
            friend: _makeFriend(
              lastActivity: '',
              unreadCount: 0,
              latestMedia: const MediaPreviewDescriptor(
                type: 'image',
                count: 2,
              ),
            ),
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 photos'), findsOneWidget);
    });

    testWidgets('caption wins over the media label', (tester) async {
      await tester.pumpWidget(
        wrap(
          FriendRow(
            friend: _makeFriend(
              lastActivity: 'My caption',
              unreadCount: 0,
              latestMedia: const MediaPreviewDescriptor(
                type: 'image',
                count: 1,
              ),
            ),
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('My caption'), findsOneWidget);
      expect(find.text('Photo'), findsNothing);
    });

    testWidgets('deleted latest shows the deleted placeholder', (tester) async {
      await tester.pumpWidget(
        wrap(
          FriendRow(
            friend: _makeFriend(
              lastActivity: null,
              unreadCount: 0,
              isLatestDeleted: true,
            ),
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('This message was deleted'), findsOneWidget);
    });

    testWidgets('Arabic locale media label is RTL', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: FriendRow(
              friend: _makeFriend(
                lastActivity: '',
                unreadCount: 0,
                latestMedia: const MediaPreviewDescriptor(
                  type: 'audio',
                  count: 1,
                ),
              ),
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(_textFor(tester, 'رسالة صوتية').textDirection, TextDirection.rtl);
    });
  });
}
