import 'package:flutter/material.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_navigation.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_info_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'AML-01 member and admin open received only group library while qa stays excluded',
    (tester) async {
      for (final role in [GroupRole.member, GroupRole.admin]) {
        var opens = 0;
        final announcement = _group(GroupType.announcement, role);
        await tester.pumpWidget(_app(announcement, () => opens++));
        await tester.tap(
          find.byKey(const ValueKey('group-shared-media-entry')),
        );
        expect(opens, 1);
        expect(
          await resolveGroupSharedMediaRoute(
            groupId: announcement.id,
            loadGroup: (_) async => announcement,
            includeAnnouncements: true,
          ),
          announcement,
        );
        expect(
          await resolveGroupSharedMediaRoute(
            groupId: announcement.id,
            loadGroup: (_) async => announcement,
          ),
          isNull,
          reason: 'discussion callers keep the old default policy',
        );
      }

      await tester.pumpWidget(
        _app(_group(GroupType.qa, GroupRole.admin), () {}),
      );
      expect(
        find.byKey(const ValueKey('group-shared-media-entry')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'AML-11 library actions preserve announcement authorization and transport silence',
    (tester) async {
      var opens = 0;
      await tester.pumpWidget(
        _app(_group(GroupType.announcement, GroupRole.member), () => opens++),
      );
      expect(
        find.byKey(const ValueKey('group-edit-details-button')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('group-shared-media-entry')));
      expect(opens, 1, reason: 'opening a local library is the only callback');
    },
  );
}

Widget _app(GroupModel group, VoidCallback onOpen) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: GroupInfoScreen(
    group: group,
    members: const [],
    isAdmin: group.myRole == GroupRole.admin,
    onBack: () {},
    onLeave: () {},
    onOpenSharedMedia: onOpen,
  ),
);

GroupModel _group(GroupType type, GroupRole role) => GroupModel(
  id: 'group-${type.name}-${role.name}',
  name: 'Group',
  type: type,
  topicName: 'topic',
  createdAt: DateTime.utc(2026, 7, 10),
  createdBy: 'admin',
  myRole: role,
);
