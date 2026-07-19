import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/features/conversation/presentation/screens/direct_private_media_viewer.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/l10n/app_localizations_ar.dart';

void main() {
  Future<void> pumpPlaceholder(
    WidgetTester tester,
    Widget child, {
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Directionality(
            textDirection: locale.languageCode == 'ar'
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: child,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'protected placeholder shows sender-attributed reassurance body',
    (tester) async {
      await pumpPlaceholder(
        tester,
        const DirectPrivateMediaOpenPlaceholder(
          onOpen: null,
          policy: PrivateMediaPolicy.protected(),
          contactDisplayName: 'Layla',
        ),
      );

      expect(
        find.text(
          "You can view it again. Layla doesn't allow saving or sharing.",
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'outgoing placeholder explains recipient-only view without screenshot claim',
    (tester) async {
      await pumpPlaceholder(
        tester,
        const DirectPrivateMediaOutgoingPlaceholder(
          policy: PrivateMediaPolicy.protected(),
          contactDisplayName: 'Layla',
        ),
      );

      expect(
        find.text(
          "Only Layla can view it. They can't save or share it.\n"
          'You can reopen it once here after sending.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('screenshot'), findsNothing);
    },
  );

  testWidgets('reassurance bodies render localized and RTL-safe under ar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const contactName = 'ليلى';
    await pumpPlaceholder(
      tester,
      const SingleChildScrollView(
        child: Column(
          key: ValueKey('private-media-arabic-bodies'),
          children: <Widget>[
            DirectPrivateMediaOpenPlaceholder(
              onOpen: null,
              policy: PrivateMediaPolicy.protected(),
              contactDisplayName: contactName,
            ),
            DirectPrivateMediaOutgoingPlaceholder(
              policy: PrivateMediaPolicy.protected(),
              contactDisplayName: contactName,
            ),
          ],
        ),
      ),
      locale: const Locale('ar'),
    );

    final ar = AppLocalizationsAr();
    expect(
      find.text(ar.private_media_protected_body_received(contactName)),
      findsOneWidget,
    );
    expect(
      find.text(
        '${ar.private_media_outgoing_body(contactName)}\n'
        '${ar.private_media_disclosure_reopen}',
      ),
      findsOneWidget,
    );
    expect(
      Directionality.of(
        tester.element(
          find.byKey(const ValueKey('private-media-arabic-bodies')),
        ),
      ),
      TextDirection.rtl,
    );
    expect(tester.takeException(), isNull);
  });
}
