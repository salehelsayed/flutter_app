import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/features/conversation/presentation/screens/direct_private_media_viewer.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

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
    'protected and disappearing image and video placeholders show compact sender-attributed body',
    (tester) async {
      final policies = <PrivateMediaPolicy>[
        const PrivateMediaPolicy.protected(),
        PrivateMediaPolicy.disappearing(3600),
      ];
      const kinds = <PrivateMediaAttachmentKind>[
        PrivateMediaAttachmentKind.image,
        PrivateMediaAttachmentKind.video,
      ];
      for (final policy in policies) {
        for (final kind in kinds) {
          await pumpPlaceholder(
            tester,
            DirectPrivateMediaOpenPlaceholder(
              onOpen: () {},
              policy: policy,
              kind: kind,
              contactDisplayName: 'pixel',
            ),
          );

          expect(
            find.text("pixel doesn't allow saving or sharing."),
            findsOneWidget,
            reason: '${policy.mode}:$kind',
          );
          expect(
            find.textContaining('You can view it again.'),
            findsNothing,
            reason: '${policy.mode}:$kind',
          );
        }
      }
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

  testWidgets(
    'compact received bodies render literal ar and de copy without old lead-ins and remain RTL-safe',
    (tester) async {
      final policies = <PrivateMediaPolicy>[
        const PrivateMediaPolicy.protected(),
        PrivateMediaPolicy.disappearing(3600),
      ];
      const kinds = <PrivateMediaAttachmentKind>[
        PrivateMediaAttachmentKind.image,
        PrivateMediaAttachmentKind.video,
      ];
      for (final locale in const <Locale>[Locale('ar'), Locale('de')]) {
        final isArabic = locale.languageCode == 'ar';
        final contactName = isArabic ? 'ليلى' : 'Pixel';
        final expected = isArabic
            ? 'ليلى لا يسمح بالحفظ أو المشاركة.'
            : 'Pixel erlaubt kein Speichern oder Teilen.';
        final oldLeadIn = isArabic
            ? 'يمكنك مشاهدته مجددًا.'
            : 'Du kannst es erneut ansehen.';
        final expectedDirection = isArabic
            ? TextDirection.rtl
            : TextDirection.ltr;

        for (final policy in policies) {
          for (final kind in kinds) {
            final key = ValueKey(
              'compact-${locale.languageCode}-${policy.mode.name}-${kind.name}',
            );
            await pumpPlaceholder(
              tester,
              KeyedSubtree(
                key: key,
                child: DirectPrivateMediaOpenPlaceholder(
                  onOpen: () {},
                  policy: policy,
                  kind: kind,
                  contactDisplayName: contactName,
                ),
              ),
              locale: locale,
            );

            expect(
              find.text(expected),
              findsOneWidget,
              reason: '${locale.languageCode}:${policy.mode}:$kind',
            );
            expect(
              find.textContaining(oldLeadIn),
              findsNothing,
              reason: '${locale.languageCode}:${policy.mode}:$kind',
            );
            expect(
              Directionality.of(tester.element(find.byKey(key))),
              expectedDirection,
            );
            expect(tester.takeException(), isNull);
          }
        }
      }
    },
  );
}
