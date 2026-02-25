import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contact_request/presentation/widgets/contact_request_dialog.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

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
      await tester.pumpWidget(wrap(ContactRequestDialog(
        request: makeRequest(username: 'bob'),
        onAccept: () {},
        onDecline: () {},
      )));
      expect(find.text('bob'), findsOneWidget);
    });

    testWidgets('renders "wants to connect with you" text', (tester) async {
      await tester.pumpWidget(wrap(ContactRequestDialog(
        request: makeRequest(),
        onAccept: () {},
        onDecline: () {},
      )));
      expect(find.text('wants to connect with you'), findsOneWidget);
    });

    testWidgets('renders Accept and Decline buttons', (tester) async {
      await tester.pumpWidget(wrap(ContactRequestDialog(
        request: makeRequest(),
        onAccept: () {},
        onDecline: () {},
      )));
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
    });

    testWidgets('calls onAccept when Accept button pressed', (tester) async {
      var accepted = false;
      await tester.pumpWidget(wrap(ContactRequestDialog(
        request: makeRequest(),
        onAccept: () => accepted = true,
        onDecline: () {},
      )));
      await tester.tap(find.text('Accept'));
      expect(accepted, isTrue);
    });

    testWidgets('calls onDecline when Decline button pressed', (tester) async {
      var declined = false;
      await tester.pumpWidget(wrap(ContactRequestDialog(
        request: makeRequest(),
        onAccept: () {},
        onDecline: () => declined = true,
      )));
      await tester.tap(find.text('Decline'));
      expect(declined, isTrue);
    });
  });
}
