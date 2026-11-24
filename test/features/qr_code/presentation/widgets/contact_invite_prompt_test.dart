import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/qr_code/application/confirm_contact_invite_use_case.dart';
import 'package:flutter_app/features/qr_code/application/contact_invite_intake.dart';
import 'package:flutter_app/features/qr_code/application/parse_qr_payload_use_case.dart';
import 'package:flutter_app/features/qr_code/presentation/widgets/contact_invite_prompt.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _link = 'https://invite.mknoon.xyz/i/v1#c2lnbmVk';
const _alice = ContactModel(
  peerId: 'alice-peer',
  publicKey: 'alice-key',
  rendezvous: 'relay',
  username: 'Alice',
  signature: 'signature',
  scannedAt: '2026-11-24T00:00:00Z',
);
const _saved = SavedContactInvite(
  contact: _alice,
  save: InviteContactSave.created,
  delivery: (
    sendResult: SendContactRequestResult.success,
    retryRetained: false,
  ),
);

Future<void> _finishDialogTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> _openPrompt(
  WidgetTester tester, {
  required ContactInviteEntry entry,
  required Future<(ParseQRResult, ContactModel?)> Function(String) preview,
  required Future<ContactInviteConfirmation> Function(String) confirm,
  required List<SavedContactInvite?> results,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              unawaited(
                showDialog<SavedContactInvite>(
                  context: context,
                  builder: (_) => ContactInvitePrompt(
                    entry: entry,
                    preview: preview,
                    confirm: confirm,
                    isCurrent: () => true,
                  ),
                ).then(results.add),
              );
            },
            child: const Text('Open prompt'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open prompt'));
  await _finishDialogTransition(tester);
}

void main() {
  testWidgets('a link previews Alice and Cancel sends no request', (
    tester,
  ) async {
    final previews = <String>[];
    final confirmations = <String>[];
    final results = <SavedContactInvite?>[];

    await _openPrompt(
      tester,
      entry: const OpenContactInvite(_link),
      preview: (link) async {
        previews.add(link);
        return (ParseQRResult.success, _alice);
      },
      confirm: (link) async {
        confirmations.add(link);
        return _saved;
      },
      results: results,
    );

    expect(find.text('Connect with Alice?'), findsOneWidget);
    expect(previews, [_link]);
    expect(confirmations, isEmpty);

    await tester.tap(find.text('Cancel'));
    await _finishDialogTransition(tester);

    expect(confirmations, isEmpty);
    expect(results, [null]);
  });

  testWidgets('paste requires Continue and an explicit Send only once', (
    tester,
  ) async {
    final previews = <String>[];
    final confirmations = <String>[];
    final results = <SavedContactInvite?>[];
    final pending = Completer<ContactInviteConfirmation>();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var clipboardReads = 0;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') clipboardReads++;
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await _openPrompt(
      tester,
      entry: const PasteContactInvite(),
      preview: (link) async {
        previews.add(link);
        return (ParseQRResult.success, _alice);
      },
      confirm: (link) {
        confirmations.add(link);
        return pending.future.timeout(const Duration(seconds: 2));
      },
      results: results,
    );

    expect(find.byType(TextField), findsOneWidget);
    expect(previews, isEmpty);
    expect(clipboardReads, 0);
    await tester.enterText(find.byType(TextField), _link);
    await tester.pump();
    expect(previews, isEmpty);
    expect(confirmations, isEmpty);
    expect(clipboardReads, 0);

    await tester.tap(find.text('Continue'));
    await _finishDialogTransition(tester);
    expect(previews, [_link]);
    expect(find.text('Connect with Alice?'), findsOneWidget);
    expect(confirmations, isEmpty);

    final send = find.text('Send request');
    await tester.tap(send);
    await tester.tap(send);
    await tester.pump();
    final confirmationsWhileHeld = List<String>.of(confirmations);
    final resultsWhileHeld = List<SavedContactInvite?>.of(results);
    pending.complete(_saved);
    await _finishDialogTransition(tester);

    expect(confirmationsWhileHeld, [_link]);
    expect(resultsWhileHeld, isEmpty);
    expect(confirmations, [_link]);
    expect(results, [_saved]);
  });

  for (final (status, message) in [
    (ParseQRResult.expired, 'This invite link has expired. Ask for a new one.'),
    (ParseQRResult.invalidJson, 'This invite link is invalid.'),
  ]) {
    testWidgets('a ${status.name} preview offers no Send action', (
      tester,
    ) async {
      final confirmations = <String>[];
      final results = <SavedContactInvite?>[];

      await _openPrompt(
        tester,
        entry: const OpenContactInvite(_link),
        preview: (_) async => (status, null),
        confirm: (link) async {
          confirmations.add(link);
          return _saved;
        },
        results: results,
      );

      expect(find.text(message), findsOneWidget);
      expect(find.text('Send request'), findsNothing);
      expect(confirmations, isEmpty);
      expect(results, isEmpty);
    });
  }
}
