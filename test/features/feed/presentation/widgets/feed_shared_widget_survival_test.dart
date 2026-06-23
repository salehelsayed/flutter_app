import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/feed/presentation/widgets/quote_preview_bar.dart';
import 'package:flutter_app/features/feed/presentation/widgets/unread_count_badge.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// 134-P8 TC-38 — shared-widget survival.
///
/// The 134 feed redesign removed the feed's USAGES of [UnreadCountBadge] and
/// [QuotePreviewBar], but the widget files must SURVIVE: orbit
/// (friend_row / group_row) still mounts the badge and conversation
/// (compose_area) still mounts the quote bar. Importing them from their real
/// library paths and rendering them proves the files were not collateral
/// damage of the widget-cleanup pass.
void main() {
  Widget wrap(Widget child) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('UnreadCountBadge survives and renders its count', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const UnreadCountBadge(count: 3)));
    await tester.pump();

    expect(find.byType(UnreadCountBadge), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('QuotePreviewBar survives and renders its quoted text', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const QuotePreviewBar(text: 'Hello world')));
    await tester.pump();

    expect(find.byType(QuotePreviewBar), findsOneWidget);
    expect(find.text('Hello world'), findsOneWidget);
  });
}
