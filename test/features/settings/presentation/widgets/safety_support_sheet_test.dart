import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/settings/presentation/widgets/safety_support_sheet.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  Future<void> pumpSheet(
    WidgetTester tester, {
    Future<bool> Function(Uri)? openUrl,
    Future<void> Function(String)? copyText,
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SafetySupportSheet(
              openUrl: openUrl ?? (_) async => true,
              copyText: copyText ?? (_) async {},
            ),
          ),
        ),
      ),
    );
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final target = find.byKey(ValueKey(key));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pump();
  }

  testWidgets('email action opens only the developer address and a subject', (
    tester,
  ) async {
    final opened = <Uri>[];
    await pumpSheet(
      tester,
      openUrl: (uri) async {
        opened.add(uri);
        return true;
      },
    );
    expect(opened, isEmpty);

    await tap(tester, 'safety-support-email');

    expect(opened, hasLength(1));
    expect(opened.single.scheme, 'mailto');
    expect(opened.single.path, 'saleh.m.elsayed@proton.me');
    expect(opened.single.queryParameters, {'subject': 'mknoon safety report'});
    expect(opened.single.query, 'subject=mknoon%20safety%20report');
  });

  for (final throws in [false, true]) {
    testWidgets('unavailable mail app (throws=$throws) keeps a copy fallback', (
      tester,
    ) async {
      final copied = <String>[];
      await pumpSheet(
        tester,
        openUrl: (_) async {
          if (throws) throw PlatformException(code: 'unavailable');
          return false;
        },
        copyText: (text) async => copied.add(text),
      );

      await tap(tester, 'safety-support-email');

      expect(find.text('saleh.m.elsayed@proton.me'), findsOneWidget);
      expect(
        find.textContaining('Couldn’t open an email app.'),
        findsOneWidget,
      );
      await tap(tester, 'safety-support-copy-email');
      expect(copied, ['saleh.m.elsayed@proton.me']);
      expect(find.text('Email address copied.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('failed clipboard write keeps the selectable contact', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      copyText: (_) async => throw PlatformException(code: 'unavailable'),
    );

    await tap(tester, 'safety-support-copy-email');

    expect(find.textContaining('Couldn’t copy the address.'), findsOneWidget);
    expect(
      tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((text) => text.data),
      contains('saleh.m.elsayed@proton.me'),
    );
    expect(find.text('Email address copied.'), findsNothing);
  });

  testWidgets('standards action opens the published page with a URL fallback', (
    tester,
  ) async {
    Uri? opened;
    await pumpSheet(
      tester,
      openUrl: (uri) async {
        opened = uri;
        return false;
      },
    );

    await tap(tester, 'safety-support-standards');

    expect(opened.toString(), 'https://mknoon.space/child-safety');
    expect(find.textContaining('Couldn’t open a browser.'), findsOneWidget);
    expect(find.text('https://mknoon.space/child-safety'), findsOneWidget);
  });

  testWidgets(
    'pending launch is single-flight and may finish after dismissal',
    (tester) async {
      final pending = Completer<bool>();
      var launches = 0;
      await pumpSheet(
        tester,
        openUrl: (_) {
          launches++;
          return pending.future;
        },
      );

      await tap(tester, 'safety-support-email');
      await tap(tester, 'safety-support-email');
      expect(launches, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete(false);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in ['en', 'de', 'ar']) {
    testWidgets('$language support remains usable at 320px and 1.5x text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pumpSheet(tester, locale: Locale(language));

      final context = tester.element(find.byType(SafetySupportSheet));
      expect(
        Directionality.of(context),
        language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      );
      expect(
        find.text(AppLocalizations.of(context)!.settings_safety_support_title),
        findsOneWidget,
      );
      await tap(tester, 'safety-support-standards');
      expect(tester.takeException(), isNull);
    });
  }
}
