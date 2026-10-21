import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/contact_request/presentation/widgets/contact_request_dialog.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../../shared/helpers/readability_test_helpers.dart';

void main() {
  Widget wrap(Widget child, {ThemeData? theme}) => MaterialApp(
    theme: theme,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  ContactRequestModel makeRequest({String username = 'alice'}) {
    return ContactRequestModel(
      peerId: 'peer-abc-def-123456',
      publicKey: 'pk-base64',
      rendezvous: '/ip4/127.0.0.1/tcp/4001',
      username: username,
      signature: 'sig-base64',
      receivedAt: '2024-01-01T00:00:00Z',
    );
  }

  group('ContactRequestDialog', () {
    for (final sample in const [
      (
        'ليلى\u202e Alpha 👩🏽‍💻\u202c',
        'ليلى Alpha 👩🏽‍💻',
        TextDirection.rtl,
      ),
      (
        'Alpha\u202d ليلى 👨‍👩‍👧‍👦\u202c',
        'Alpha ليلى 👨‍👩‍👧‍👦',
        TextDirection.ltr,
      ),
    ]) {
      group(
        'KNOWN GAP',
        () {
          testWidgets('CR-016 unsafe bidi name renders safely: ${sample.$3}', (
            tester,
          ) async {
            final request = makeRequest(username: sample.$1);
            await tester.pumpWidget(
              wrap(
                ContactRequestDialog(
                  request: request,
                  onAccept: () {},
                  onDecline: () {},
                ),
              ),
            );
            expect(
              request.username,
              sample.$1,
              reason: 'display safety must not rewrite signed request content',
            );
            expect(find.text(sample.$2), findsOneWidget);
            expect(find.text(sample.$1), findsNothing);
            expect(
              tester.widget<Text>(find.text(sample.$2)).textDirection,
              sample.$3,
            );
            expect(find.text('Accept').hitTestable(), findsOneWidget);
            expect(find.text('Decline').hitTestable(), findsOneWidget);
          });
        },
        skip:
            'KNOWN GAP: contact_request_dialog.dart:68 renders unsafe bidi controls. Run with --run-skipped for the desired display failure.',
      );
    }

    group(
      'KNOWN GAP',
      () {
        testWidgets(
          'CR-016 extreme emoji name keeps both narrow-view actions reachable',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = const Size(320, 568);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(tester.view.resetPhysicalSize);
            final username = List.filled(
              120,
              'ليلى 👩🏽‍💻 Alpha 👨‍👩‍👧‍👦',
            ).join(' ');
            var accepted = 0;
            var declined = 0;
            await tester.pumpWidget(
              wrap(
                ContactRequestDialog(
                  request: makeRequest(username: username),
                  onAccept: () => accepted++,
                  onDecline: () => declined++,
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.text('Accept').hitTestable(), findsOneWidget);
            expect(find.text('Decline').hitTestable(), findsOneWidget);
            await tester.tap(find.text('Accept'));
            await tester.pump();
            expect(accepted, 1);
            expect(declined, 0);
          },
        );
      },
      skip:
          'KNOWN GAP: contact_request_dialog.dart:59-76 overflows with extreme names. Run with --run-skipped for the desired reachable-actions failure.',
    );

    testWidgets(
      'CR-016 ACCESS-002 emoji consent labels targets and disabled actions',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(320, 568);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          var accepted = 0;
          var declined = 0;
          await tester.pumpWidget(
            wrap(
              ContactRequestDialog(
                request: makeRequest(username: '👩🏽‍💻 ليلى Alpha'),
                onAccept: () => accepted++,
                onDecline: () => declined++,
              ),
            ),
          );
          for (final label in ['Accept', 'Decline']) {
            final control = find.widgetWithText(
              label == 'Accept' ? ElevatedButton : OutlinedButton,
              label,
            );
            final size = tester.getSize(control);
            expect(size.width, greaterThanOrEqualTo(44));
            expect(size.height, greaterThanOrEqualTo(44));
            final data = tester.getSemantics(control).getSemanticsData();
            expect(data.label, label);
            expect(data.hasFlag(SemanticsFlag.isButton), isTrue);
            expect(data.hasFlag(SemanticsFlag.hasEnabledState), isTrue);
            expect(data.hasFlag(SemanticsFlag.isEnabled), isTrue);
            expect(data.hasAction(SemanticsAction.tap), isTrue);
          }
          await tester.tap(find.text('Decline'));
          await tester.pump();
          expect(declined, 1);
          expect(accepted, 0);
          expect(
            tester
                .widget<OutlinedButton>(find.byType(OutlinedButton))
                .onPressed,
            isNull,
          );
          expect(
            tester
                .widget<ElevatedButton>(find.byType(ElevatedButton))
                .onPressed,
            isNull,
          );
          for (final label in ['Accept', 'Decline']) {
            final node = tester.getSemantics(
              find.widgetWithText(
                label == 'Accept' ? ElevatedButton : OutlinedButton,
                label,
              ),
            );
            final data = node.getSemanticsData();
            expect(data.label, label);
            expect(data.hasFlag(SemanticsFlag.isButton), isTrue);
            expect(data.hasFlag(SemanticsFlag.hasEnabledState), isTrue);
            expect(data.hasFlag(SemanticsFlag.isEnabled), isFalse);
            expect(data.hasAction(SemanticsAction.tap), isFalse);
          }
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets('renders username from request', (tester) async {
      await tester.pumpWidget(
        wrap(
          ContactRequestDialog(
            request: makeRequest(username: 'bob'),
            onAccept: () {},
            onDecline: () {},
          ),
        ),
      );
      expect(find.text('bob'), findsOneWidget);
    });

    testWidgets('renders "wants to connect with you" text', (tester) async {
      await tester.pumpWidget(
        wrap(
          ContactRequestDialog(
            request: makeRequest(),
            onAccept: () {},
            onDecline: () {},
          ),
        ),
      );
      expect(find.text('wants to connect with you'), findsOneWidget);
    });

    testWidgets('renders Accept and Decline buttons', (tester) async {
      await tester.pumpWidget(
        wrap(
          ContactRequestDialog(
            request: makeRequest(),
            onAccept: () {},
            onDecline: () {},
          ),
        ),
      );
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
    });

    testWidgets('calls onAccept when Accept button pressed', (tester) async {
      var accepted = false;
      await tester.pumpWidget(
        wrap(
          ContactRequestDialog(
            request: makeRequest(),
            onAccept: () => accepted = true,
            onDecline: () {},
          ),
        ),
      );
      await tester.tap(find.text('Accept'));
      expect(accepted, isTrue);
    });

    testWidgets('calls onDecline when Decline button pressed', (tester) async {
      var declined = false;
      await tester.pumpWidget(
        wrap(
          ContactRequestDialog(
            request: makeRequest(),
            onAccept: () {},
            onDecline: () => declined = true,
          ),
        ),
      );
      await tester.tap(find.text('Decline'));
      expect(declined, isTrue);
    });

    testWidgets('Arabic username drives RTL direction', (tester) async {
      const username = 'ليلى';
      await tester.pumpWidget(
        wrap(
          ContactRequestDialog(
            request: makeRequest(username: username),
            onAccept: () {},
            onDecline: () {},
          ),
        ),
      );

      final usernameText = tester.widget<Text>(find.text(username));
      expect(usernameText.textDirection, TextDirection.rtl);
    });

    testWidgets('Arabic-first mixed username drives RTL direction', (
      tester,
    ) async {
      const username = 'ليلى Alpha';
      await tester.pumpWidget(
        wrap(
          ContactRequestDialog(
            request: makeRequest(username: username),
            onAccept: () {},
            onDecline: () {},
          ),
        ),
      );

      final usernameText = tester.widget<Text>(find.text(username));
      expect(usernameText.textDirection, TextDirection.rtl);
    });

    testWidgets('English-first mixed username stays LTR direction', (
      tester,
    ) async {
      const username = 'Alpha ليلى';
      await tester.pumpWidget(
        wrap(
          ContactRequestDialog(
            request: makeRequest(username: username),
            onAccept: () {},
            onDecline: () {},
          ),
        ),
      );

      final usernameText = tester.widget<Text>(find.text(username));
      expect(usernameText.textDirection, TextDirection.ltr);
    });

    testWidgets('uses readable light-background roles for dialog text', (
      tester,
    ) async {
      const colors = BackgroundReadableColors.representativeLight;
      await tester.pumpWidget(
        wrap(
          ContactRequestDialog(
            request: makeRequest(username: 'bob'),
            onAccept: () {},
            onDecline: () {},
          ),
          theme: ThemeData(extensions: const <ThemeExtension<dynamic>>[colors]),
        ),
      );

      final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(dialog.backgroundColor, colors.surfaceBase);

      final usernameText = tester.widget<Text>(find.text('bob'));
      final messageText = tester.widget<Text>(
        find.text('wants to connect with you'),
      );
      expectTextContrast(usernameText.style!.color!, colors.surfaceBase);
      expectTextContrast(messageText.style!.color!, colors.surfaceBase);
    });
  });
}
