import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/friend_row.dart';

OrbitFriend _makeFriend({
  int unreadCount = 3,
  String? lastActivity,
  String username = 'Alice',
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
  );
}

void main() {
  group('FriendRow', () {
    Text _textFor(WidgetTester tester, String text) {
      final finder = find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == text,
        description: 'Text("$text")',
      );
      expect(finder, findsOneWidget);
      return tester.widget<Text>(finder);
    }

    testWidgets('shows unread badge by default when unreadCount > 0',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FriendRow(
              friend: _makeFriend(unreadCount: 3),
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // UnreadCountBadge renders the count as text
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('hides unread badge when hideUnreadBadge is true',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FriendRow(
              friend: _makeFriend(unreadCount: 3),
              hideUnreadBadge: true,
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The count text should not appear
      expect(find.text('3'), findsNothing);
    });

    testWidgets('shows chevron when no unread messages', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FriendRow(
              friend: _makeFriend(unreadCount: 0),
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('Arabic lastActivity drives RTL', (tester) async {
      const lastActivity = 'مرحبا';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FriendRow(
              friend: _makeFriend(lastActivity: lastActivity, unreadCount: 0),
              onTap: () {},
            ),
          ),
        ),
      );

      expect(_textFor(tester, lastActivity).textDirection, TextDirection.rtl);
    });

    testWidgets('Arabic-first mixed lastActivity drives RTL', (tester) async {
      const lastActivity = 'مرحبا Hello 123';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FriendRow(
              friend: _makeFriend(lastActivity: lastActivity, unreadCount: 0),
              onTap: () {},
            ),
          ),
        ),
      );

      expect(_textFor(tester, lastActivity).textDirection, TextDirection.rtl);
    });

    testWidgets('English-first mixed lastActivity drives LTR', (tester) async {
      const lastActivity = 'Hello مرحبا 123';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FriendRow(
              friend: _makeFriend(lastActivity: lastActivity, unreadCount: 0),
              onTap: () {},
            ),
          ),
        ),
      );

      expect(_textFor(tester, lastActivity).textDirection, TextDirection.ltr);
    });
  });
}
