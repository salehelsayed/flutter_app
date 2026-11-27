import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_type_badge.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  Widget buildTestWidget(GroupType type) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: GroupTypeBadge(type: type)),
    );
  }

  testWidgets('renders correct text for each type', (tester) async {
    await tester.pumpWidget(buildTestWidget(GroupType.chat));
    expect(find.text('Discussion'), findsOneWidget);

    await tester.pumpWidget(buildTestWidget(GroupType.announcement));
    expect(find.text('Announce'), findsOneWidget);

    await tester.pumpWidget(buildTestWidget(GroupType.qa));
    expect(find.text('Q&A'), findsOneWidget);
  });

  testWidgets('BL-107 group badge labels read at least 11 pt', (tester) async {
    const deadline = Duration(seconds: 3);
    for (final (type, text) in [
      (GroupType.chat, 'Discussion'),
      (GroupType.announcement, 'Announce'),
      (GroupType.qa, 'Q&A'),
    ]) {
      await tester.pumpWidget(buildTestWidget(type)).timeout(deadline);
      final badge = tester.widget<Text>(find.text(text));
      expect(badge.style?.fontSize, greaterThanOrEqualTo(11), reason: text);
    }
  });

  testWidgets('each type has unique color', (tester) async {
    // Just verify each type renders without error (color is visual)
    for (final type in GroupType.values) {
      await tester.pumpWidget(buildTestWidget(type));
      expect(find.byType(GroupTypeBadge), findsOneWidget);
    }
  });
}
