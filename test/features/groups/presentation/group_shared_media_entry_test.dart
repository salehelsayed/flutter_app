import 'package:flutter/material.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_navigation.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_info_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('GML-01 shared media entry keeps discussion default policy', (
    tester,
  ) async {
    var openCount = 0;

    Future<void> pump(GroupModel group) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GroupInfoScreen(
            group: group,
            members: const [],
            isAdmin: true,
            onBack: () {},
            onLeave: () {},
            onOpenSharedMedia: () => openCount++,
          ),
        ),
      );
      await tester.pump();
    }

    await pump(_group(type: GroupType.chat));
    expect(
      find.byKey(const ValueKey('group-shared-media-entry')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('group-shared-media-entry')));
    expect(openCount, 1);

    await pump(_group(type: GroupType.announcement));
    expect(
      find.byKey(const ValueKey('group-shared-media-entry')),
      findsOneWidget,
    );

    for (final group in <GroupModel>[
      _group(type: GroupType.qa),
      _group(type: GroupType.chat, isDissolved: true),
    ]) {
      await pump(group);
      expect(
        find.byKey(const ValueKey('group-shared-media-entry')),
        findsNothing,
      );
    }
    expect(openCount, 1);

    var mediaQueries = 0;
    for (final candidate in <GroupModel?>[
      _group(type: GroupType.announcement),
      _group(type: GroupType.qa),
      _group(type: GroupType.chat, isDissolved: true),
      null,
    ]) {
      final resolved = await resolveGroupSharedMediaRoute(
        groupId: candidate?.id ?? 'missing',
        loadGroup: (_) async => candidate,
      );
      if (resolved != null) mediaQueries++;
    }
    expect(mediaQueries, 0, reason: 'rejected routes never build/query media');
  });

  testWidgets(
    'GML-12 announcements expose local media without write authorization',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GroupInfoScreen(
            group: _group(type: GroupType.announcement),
            members: const [],
            isAdmin: true,
            onBack: () {},
            onLeave: () {},
            onOpenSharedMedia: () {},
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('group-shared-media-entry')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('group-mute-switch')), findsOneWidget);
    },
  );
}

GroupModel _group({required GroupType type, bool isDissolved = false}) {
  return GroupModel(
    id: 'group-${type.name}-${isDissolved ? 'dissolved' : 'active'}',
    name: 'Test group',
    type: type,
    topicName: 'topic-${type.name}',
    createdAt: DateTime.utc(2026, 1, 1),
    createdBy: 'admin',
    myRole: GroupRole.admin,
    isDissolved: isDissolved,
  );
}
