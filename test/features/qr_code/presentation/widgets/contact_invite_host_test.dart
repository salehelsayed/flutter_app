import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/qr_code/application/confirm_contact_invite_use_case.dart';
import 'package:flutter_app/features/qr_code/application/contact_invite_intake.dart';
import 'package:flutter_app/features/qr_code/application/parse_qr_payload_use_case.dart';
import 'package:flutter_app/features/qr_code/presentation/widgets/contact_invite_host.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _link = 'https://invite.mknoon.xyz/i/v1#c2lnbmVk';
const _ownPeerId = 'receiver';
const _deadline = Duration(seconds: 2);
const _channel = MethodChannel('mknoon/contact_invites');
const _channelEntry = {'kind': 'link', 'url': _link};
const _inviter = ContactModel(
  peerId: 'sender',
  publicKey: 'key',
  rendezvous: '/dns4/fixture',
  username: 'Alice',
  signature: 'signature',
  scannedAt: '2026-11-24T00:00:00.000Z',
);
const _saved = SavedContactInvite(
  contact: _inviter,
  save: InviteContactSave.created,
  delivery: (sendResult: SendContactRequestResult.success, retryRetained: true),
);

void main() {
  testWidgets('retains a cold link until the eligible account home mounts', (
    tester,
  ) async {
    final harness = await _mount(tester, initiallyReady: false);

    expect(find.text('Setup'), findsOneWidget);
    expect(harness.previews, isEmpty);
    expect(harness.confirms, isEmpty);
    expect(harness.saved, isEmpty);

    harness.account.value = _ownPeerId;
    harness.homeReady.value = true;
    await _flush(tester);

    expect(harness.previews, [(_link, _ownPeerId)]);
    expect(find.text('Connect with Alice?'), findsOneWidget);
    expect(harness.confirms, isEmpty);
    expect(harness.saved, isEmpty);

    await tester.tap(find.text('Send request'));
    await _flush(tester);

    expect(harness.confirms, [(_link, _ownPeerId)]);
    expect(harness.saved, [_saved]);
    expect(find.text('Ready home'), findsOneWidget);
    expect(find.text('Connect with Alice?'), findsNothing);
  });

  testWidgets('retirement removes the owned invite and keeps another dialog', (
    tester,
  ) async {
    final harness = await _mount(tester, initiallyReady: true);
    expect(find.text('Connect with Alice?'), findsOneWidget);

    unawaited(
      showDialog<void>(
        context: harness.navigatorKey.currentContext!,
        builder: (_) => const AlertDialog(title: Text('Unrelated dialog')),
      ),
    );
    await _flush(tester);
    expect(find.text('Unrelated dialog'), findsOneWidget);

    harness.account.value = null;
    await _flush(tester);

    expect(find.text('Unrelated dialog'), findsOneWidget);
    expect(find.text('Connect with Alice?', skipOffstage: false), findsNothing);
    expect(harness.confirms, isEmpty);
    expect(harness.saved, isEmpty);
  });
}

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<_Harness> _mount(
  WidgetTester tester, {
  required bool initiallyReady,
}) async {
  final harness = _Harness(initiallyReady);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var read = false;
  messenger.setMockMethodCallHandler(_channel, (call) {
    expect(call.method, 'takePending');
    final reply = read ? null : _channelEntry;
    read = true;
    return SynchronousFuture<Object?>(reply);
  });
  addTearDown(() {
    harness.intake.dispose();
    harness.account.dispose();
    harness.homeReady.dispose();
    messenger.setMockMethodCallHandler(_channel, null);
  });

  final start = harness.intake.start();
  await tester.pump();
  await start.timeout(_deadline);
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: harness.navigatorKey,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (_, child) => ContactInviteHost(
        intake: harness.intake,
        accountPeerId: harness.account,
        navigatorKey: harness.navigatorKey,
        preview: (link, ownPeerId) async {
          harness.previews.add((link, ownPeerId));
          return (ParseQRResult.success, _inviter);
        },
        confirm: (link, ownPeerId, isCurrent) async {
          expect(isCurrent(), isTrue);
          harness.confirms.add((link, ownPeerId));
          return _saved;
        },
        child: child!,
      ),
      home: ValueListenableBuilder<bool>(
        valueListenable: harness.homeReady,
        builder: (_, ready, _) => ready
            ? ContactInviteHome(
                ownPeerId: _ownPeerId,
                onSaved: harness.saved.add,
                child: const Scaffold(body: Text('Ready home')),
              )
            : const Scaffold(body: Text('Setup')),
      ),
    ),
  );
  await _flush(tester);
  return harness;
}

class _Harness {
  _Harness(bool initiallyReady)
    : account = ValueNotifier<String?>(initiallyReady ? _ownPeerId : null),
      homeReady = ValueNotifier(initiallyReady);

  final navigatorKey = GlobalKey<NavigatorState>();
  final intake = ContactInviteIntake(channel: _channel);
  final ValueNotifier<String?> account;
  final ValueNotifier<bool> homeReady;
  final previews = <(String, String)>[];
  final confirms = <(String, String)>[];
  final saved = <SavedContactInvite>[];
}
