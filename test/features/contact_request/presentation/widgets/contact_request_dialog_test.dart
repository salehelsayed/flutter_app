import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/contact_request/presentation/widgets/contact_request_dialog.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';

import '../../../../shared/helpers/readability_test_helpers.dart';

void main() {
  Widget wrap(Widget child, {ThemeData? theme}) => MaterialApp(
    theme: theme,
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
