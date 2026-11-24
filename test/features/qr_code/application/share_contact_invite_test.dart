import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/features/qr_code/application/build_qr_payload_use_case.dart';
import 'package:flutter_app/features/qr_code/application/share_contact_invite.dart';
import 'package:flutter_test/flutter_test.dart';

const _deadline = Duration(seconds: 2);
const _firstQr =
    '{"ns":"sender","pk":"key","rv":"/dns/fixture","sig":"one","ts":"2026-11-24T14:00:00.000Z","un":"Alice"}';
const _laterQr =
    '{"ns":"sender","pk":"key","rv":"/dns/fixture","sig":"two","ts":"2026-11-24T14:01:00.000Z","un":"Alice"}';

String _encoded(String raw) =>
    'https://invite.mknoon.xyz/i/v1#${base64Url.encode(utf8.encode(raw)).replaceAll('=', '')}';

void main() {
  test(
    'each explicit share presents the newly signed legacy QR bytes',
    () async {
      final links = <String>[];
      var signed = 0;
      Future<ContactInviteShareResult> share() => shareContactInvite(
        isCurrent: () => true,
        buildQr: () async {
          signed++;
          return (
            BuildQRPayloadResult.success,
            signed == 1 ? _firstQr : _laterQr,
          );
        },
        present: (link) async {
          links.add(link);
          return true;
        },
      ).timeout(_deadline);

      expect(await share(), ContactInviteShareResult.presented);
      expect(await share(), ContactInviteShareResult.presented);
      expect(signed, 2);
      expect(links, [_encoded(_firstQr), _encoded(_laterQr)]);
    },
  );

  test('retirement during signing prevents opening the chooser', () async {
    final entered = Completer<void>();
    final release = Completer<(BuildQRPayloadResult, String?)>();
    var live = true;
    var presented = false;
    final share = shareContactInvite(
      isCurrent: () => live,
      buildQr: () {
        entered.complete();
        return release.future.timeout(_deadline);
      },
      present: (_) async {
        presented = true;
        return true;
      },
    ).timeout(_deadline);

    try {
      final reachedSigning = await Future.any([
        entered.future.then((_) => true),
        share.then((_) => false),
      ]).timeout(_deadline);
      expect(reachedSigning, isTrue, reason: 'signing was skipped');
      live = false;
    } finally {
      release.complete((BuildQRPayloadResult.success, _firstQr));
    }

    expect(await share, ContactInviteShareResult.unavailable);
    expect(presented, isFalse);
  });

  test(
    'an invalid or refused share reports failure without pretending it opened',
    () async {
      var presentations = 0;
      Future<ContactInviteShareResult> share(String qr) => shareContactInvite(
        isCurrent: () => true,
        buildQr: () async => (BuildQRPayloadResult.success, qr),
        present: (_) async {
          presentations++;
          return false;
        },
      ).timeout(_deadline);

      expect(await share('{}'), ContactInviteShareResult.failed);
      expect(presentations, 0);
      expect(await share(_firstQr), ContactInviteShareResult.failed);
      expect(presentations, 1);
    },
  );
}
