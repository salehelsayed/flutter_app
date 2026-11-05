import 'package:flutter/material.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/presentation/widgets/compose_post_sheet.dart';
import 'package:flutter_app/features/posts/presentation/widgets/thought_audience.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';

ContactModel _friend(String name) => ContactModel(
  peerId: 'peer-$name',
  publicKey: 'pk-$name',
  rendezvous: 'rendezvous',
  username: name,
  signature: 'signature',
  scannedAt: '2026-11-01T00:00:00.000Z',
);

void main() {
  Widget scene(Locale locale) => MaterialApp(
    locale: locale,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(2)),
      child: child!,
    ),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: ComposePostSheet(
        thoughtsOnly: true,
        eligibleContacts: [_friend('layla'), _friend('omar'), _friend('nour')],
        recentPicks: ThoughtRecentPicks(FakeSecureKeyStore()),
        onSubmitWithOutcome: (_) async =>
            ComposePostSubmitOutcome.keepSheetOpen,
      ),
    ),
  );

  void onScreen(WidgetTester tester, Finder part, Size screen) {
    final rect = tester.getRect(part);
    expect(rect.left, greaterThanOrEqualTo(-0.5), reason: '$part');
    expect(rect.right, lessThanOrEqualTo(screen.width + 0.5), reason: '$part');
  }

  for (final locale in const [Locale('en'), Locale('de'), Locale('ar')]) {
    testWidgets('double-size text at 360 px: the composer header and the '
        'people picker stay on screen (${locale.languageCode})', (
      tester,
    ) async {
      const screen = Size(360, 780);
      tester.view.physicalSize = screen * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(scene(locale));
      await tester.pumpAndSettle();
      final share = find.byKey(const ValueKey('thought-composer-share'));
      onScreen(tester, find.byKey(const ValueKey('thought-composer-cancel')), screen);
      onScreen(tester, share, screen);
      final shareSize = tester.getSize(share);
      expect(shareSize.width, greaterThanOrEqualTo(72));
      expect(shareSize.height, greaterThanOrEqualTo(36));

      await tester.tap(find.byKey(const ValueKey('thought-audience-chip')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('thought-audience-select')));
      await tester.pumpAndSettle();
      onScreen(tester, find.byKey(const ValueKey('thought-pick-cancel')), screen);
      onScreen(tester, find.byKey(const ValueKey('thought-pick-done')), screen);
      onScreen(tester, find.byKey(const ValueKey('thought-pick-peer-layla')), screen);
      expect(tester.takeException(), isNull, reason: 'no row overflows');
    });
  }
}
