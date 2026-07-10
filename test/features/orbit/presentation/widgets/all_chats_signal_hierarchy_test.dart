import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_group.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/friend_row.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/group_row.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  const light = BackgroundReadableColors.representativeLight;
  const existingPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 14);

  OrbitFriend makeFriend() => OrbitFriend(
    contact: ContactModel(
      peerId: 'peer-1234567890',
      publicKey: 'pk-1',
      rendezvous: '/dns4/relay/tcp/443',
      username: 'Alice',
      signature: 'sig-1',
      scannedAt: '2026-01-01T00:00:00.000Z',
    ),
    messageCount: 5,
    unreadCount: 2,
  );

  OrbitGroup makeGroup() => OrbitGroup(
    group: GroupModel(
      id: 'g-1',
      name: 'Team',
      type: GroupType.chat,
      topicName: 'topic-g1',
      createdAt: DateTime.utc(2026, 1, 1),
      createdBy: 'peer-admin',
      myRole: GroupRole.admin,
    ),
    unreadCount: 1,
  );

  Widget wrap(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(extensions: const [light]),
    home: Scaffold(body: child),
  );

  Container rowSurface(WidgetTester tester, Type rowType) {
    return tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(rowType),
            matching: find.byType(Container),
          ),
        )
        .firstWhere((c) {
          final d = c.decoration;
          return d is BoxDecoration && d.color == light.surfaceSubtle;
        });
  }

  testWidgets(
    'Signal friend and group rows use warm fills and surfaceBorder at '
    'existing geometry',
    (tester) async {
      // FriendRow.
      await tester.pumpWidget(
        wrap(FriendRow(friend: makeFriend(), onTap: () {})),
      );
      await tester.pumpAndSettle();

      final friend = rowSurface(tester, FriendRow);
      final friendDeco = friend.decoration! as BoxDecoration;
      // Filled warm surface, not paper white.
      expect(friendDeco.color, light.surfaceSubtle);
      expect(friendDeco.color, const Color(0xFFE1DCE5));
      // Decorative surfaceBorder, not the stronger control border.
      expect((friendDeco.border! as Border).top.color, light.surfaceBorder);
      expect((friendDeco.border! as Border).top.color, const Color(0xFFB3ACBD));
      expect((friendDeco.border! as Border).top.color, isNot(light.border));
      // Existing geometry unchanged.
      expect(friendDeco.borderRadius, BorderRadius.circular(16));
      expect(friend.padding, existingPadding);

      // GroupRow.
      await tester.pumpWidget(wrap(GroupRow(group: makeGroup(), onTap: () {})));
      await tester.pumpAndSettle();

      final group = rowSurface(tester, GroupRow);
      final groupDeco = group.decoration! as BoxDecoration;
      expect(groupDeco.color, light.surfaceSubtle);
      expect((groupDeco.border! as Border).top.color, light.surfaceBorder);
      expect((groupDeco.border! as Border).top.color, isNot(light.border));
      expect(groupDeco.borderRadius, BorderRadius.circular(16));
      expect(group.padding, existingPadding);
    },
  );
}
