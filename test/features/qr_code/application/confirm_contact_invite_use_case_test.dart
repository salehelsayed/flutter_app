import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/qr_code/application/confirm_contact_invite_use_case.dart';
import 'package:flutter_app/features/qr_code/application/contact_invite_link.dart';
import 'package:flutter_app/features/qr_code/application/parse_qr_payload_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/ed25519_contact_request_crypto.dart';

const _deadline = Duration(seconds: 3);
const _relay = '/dns/mknoun.xyz/tcp/4001/wss/p2p/relay';

Matcher _rejects(ContactInviteRejection reason) => isA<RejectedContactInvite>()
    .having((result) => result.reason, 'reason', reason);

enum _TransmitChange { blocked, key, expired }

void main() {
  final sender = TestEd25519Identity.fromSeedByte(0x42);
  final receiver = TestEd25519Identity.fromSeedByte(0x41);
  late _InviteHarness attempt;

  setUp(() => attempt = _InviteHarness(sender, receiver));

  test(
    'confirmation checks the signed issue time and signature again',
    () async {
      final link = attempt.link();
      final (previewResult, preview) = await parseContactInviteLink(
        link: link,
        bridge: attempt.bridge,
        ownPeerId: receiver.peerId,
      ).timeout(_deadline);
      expect(previewResult, ParseQRResult.success);
      expect(preview?.peerId, sender.peerId);

      attempt.now = attempt.issuedAt.add(const Duration(hours: 24, seconds: 1));
      expect(
        await attempt.confirm(link: link),
        _rejects(ContactInviteRejection.expired),
      );

      attempt.now = attempt.issuedAt.add(const Duration(minutes: 5));
      expect(
        await attempt.confirm(link: attempt.link(tamperName: true)),
        _rejects(ContactInviteRejection.invalid),
      );
      expect(attempt.bridge.verifyCalls, greaterThan(1));
      expect(attempt.lookups, 0);
      expect(attempt.saveAttempts, 0);
      expect(attempt.launched, isEmpty);
    },
  );

  test('uses the matching stored contact without writing over it', () async {
    final existing = attempt.existingContact;
    attempt.stored = existing;

    final result = await attempt.confirm();

    expect(result, isA<SavedContactInvite>());
    final saved = result as SavedContactInvite;
    expect(saved.save, InviteContactSave.existing);
    expect(saved.contact.toMap(), existing.toMap());
    expect(attempt.stored!.toMap(), existing.toMap());
    expect(attempt.saveAttempts, 0);
    expect(attempt.launched.single.toMap(), existing.toMap());
    expect(attempt.transmissions, 1);
    expect(saved.delivery.sendResult, SendContactRequestResult.success);
  });

  test('returns the newly saved contact and the actual send result', () async {
    final result = await attempt.confirm();

    expect(result, isA<SavedContactInvite>());
    final saved = result as SavedContactInvite;
    expect(saved.save, InviteContactSave.created);
    expect(saved.contact.peerId, sender.peerId);
    expect(saved.contact.publicKey, sender.publicKey);
    expect(saved.contact.username, 'Alice');
    expect(attempt.writes, 1);
    expect(attempt.launched.single.toMap(), attempt.stored!.toMap());
    expect(attempt.transmissions, 1);
    expect(saved.delivery.sendResult, SendContactRequestResult.success);
  });

  test(
    'rejects a mismatched key and a blocked row saved during admission',
    () async {
      final mismatched = attempt.existingContact.copyWith(
        publicKey: receiver.publicKey,
      );
      attempt.stored = mismatched;

      expect(
        await attempt.confirm(),
        _rejects(ContactInviteRejection.keyMismatch),
      );
      expect(attempt.stored!.toMap(), mismatched.toMap());
      expect(attempt.saveAttempts, 0);

      final blocked = attempt.existingContact.copyWith(isBlocked: true);
      attempt.stored = null;
      attempt.beforeSave = () => attempt.stored = blocked;
      expect(await attempt.confirm(), _rejects(ContactInviteRejection.blocked));
      expect(attempt.saveAttempts, 1);
      expect(attempt.stored!.toMap(), blocked.toMap());
      expect(attempt.writes, 0);
      expect(attempt.launched, isEmpty);
    },
  );

  test(
    'identity change during contact lookup prevents save and launch',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      attempt.beforeRead = () async {
        if (entered.isCompleted) return;
        entered.complete();
        await release.future.timeout(_deadline);
      };

      final pending = attempt.confirm();
      try {
        expect(
          await _reachedHold(entered, pending),
          isTrue,
          reason: 'contact lookup was skipped',
        );
        attempt.accountCurrent = false;
      } finally {
        release.complete();
      }

      expect(await pending, _rejects(ContactInviteRejection.stale));
      expect(attempt.saveAttempts, 0);
      expect(attempt.launched, isEmpty);
    },
  );

  test(
    'transmit rechecks the stored key, block and signed age after an awaited read',
    () async {
      for (final change in _TransmitChange.values) {
        final current = _InviteHarness(sender, receiver);
        current.stored = current.existingContact;
        final entered = Completer<void>();
        final release = Completer<void>();
        current.beforeRead = () async {
          if (!current.checkingTransmission || entered.isCompleted) return;
          entered.complete();
          await release.future.timeout(_deadline);
        };

        final pending = current.confirm();
        try {
          expect(
            await _reachedHold(entered, pending),
            isTrue,
            reason: 'transmit skipped stored contact for ${change.name}',
          );
          switch (change) {
            case _TransmitChange.blocked:
              current.stored = current.stored!.copyWith(isBlocked: true);
            case _TransmitChange.key:
              current.stored = current.stored!.copyWith(
                publicKey: receiver.publicKey,
              );
            case _TransmitChange.expired:
              current.now = current.issuedAt.add(
                const Duration(hours: 24, seconds: 1),
              );
          }
        } finally {
          release.complete();
        }

        final result = await pending;
        expect(result, isA<RejectedContactInvite>(), reason: change.name);
        expect(current.transmitPermitted, isFalse, reason: change.name);
        expect(current.transmissions, 0, reason: change.name);
        expect(current.writes, 0, reason: change.name);
      }
    },
  );

  test(
    'keeps local save distinct from send failure with or without retry custody',
    () async {
      attempt.sendResult = SendContactRequestResult.nodeNotRunning;

      final retry = await attempt.confirm();

      expect(retry, isA<SavedContactInvite>());
      final savedForRetry = retry as SavedContactInvite;
      expect(savedForRetry.save, InviteContactSave.created);
      expect(savedForRetry.delivery, (
        sendResult: SendContactRequestResult.nodeNotRunning,
        retryRetained: true,
      ));
      expect(savedForRetry.contact.toMap(), attempt.stored!.toMap());

      final failed = _InviteHarness(sender, receiver)..retainRetry = false;
      final result = await failed.confirm();

      expect(result, isA<SavedContactInvite>());
      final savedWithoutRetry = result as SavedContactInvite;
      expect(savedWithoutRetry.save, InviteContactSave.created);
      expect(savedWithoutRetry.delivery, (
        sendResult: null,
        retryRetained: false,
      ));
      expect(savedWithoutRetry.contact.toMap(), failed.stored!.toMap());
      expect(failed.transmissions, 0);
    },
  );
}

Future<bool> _reachedHold(
  Completer<void> entered,
  Future<ContactInviteConfirmation> pending,
) => Future.any([
  entered.future.then((_) => true),
  pending.then((_) => false),
]).timeout(_deadline);

final class _InviteHarness {
  _InviteHarness(this.sender, this.receiver);

  final TestEd25519Identity sender;
  final TestEd25519Identity receiver;
  final bridge = Ed25519ContactRequestBridge(Ed25519ContactRequestCryptoBus());
  final issuedAt = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
  late DateTime now = issuedAt.add(const Duration(minutes: 5));
  ContactModel? stored;
  var accountCurrent = true;
  var retainRetry = true;
  var checkingTransmission = false;
  bool? transmitPermitted;
  var sendResult = SendContactRequestResult.success;
  var lookups = 0;
  var saveAttempts = 0;
  var writes = 0;
  var transmissions = 0;
  final launched = <ContactModel>[];
  Future<void> Function()? beforeRead;
  void Function()? beforeSave;

  ContactModel get existingContact => ContactModel(
    peerId: sender.peerId,
    publicKey: sender.publicKey,
    rendezvous: _relay,
    username: 'Saved name',
    signature: 'previous-signature',
    scannedAt: issuedAt.subtract(const Duration(days: 2)).toIso8601String(),
    mlKemPublicKey: 'stored-ml-kem-key',
    isArchived: true,
  );

  String link({bool tamperName = false}) {
    final fields = SplayTreeMap<String, String>.from({
      'ns': sender.peerId,
      'pk': sender.publicKey,
      'rv': _relay,
      'ts': issuedAt.toIso8601String(),
      'un': 'Alice',
    });
    final signature = sender.signBase64(jsonEncode(fields));
    fields['sig'] = signature;
    if (tamperName) fields['un'] = 'Tampered';
    return buildContactInviteLink(jsonEncode(fields))!;
  }

  Future<ContactInviteConfirmation> confirm({String? link}) =>
      confirmContactInvite(
        link: link ?? this.link(),
        ownPeerId: receiver.peerId,
        isAccountCurrent: () => accountCurrent,
        bridge: bridge,
        loadContact: (peerId) async {
          lookups++;
          expect(peerId, sender.peerId);
          await beforeRead?.call().timeout(_deadline);
          return stored;
        },
        saveIfAbsent: (verified, {required canCommit}) async {
          saveAttempts++;
          beforeSave?.call();
          if (!canCommit()) return InviteContactSave.stale;
          if (stored != null) return InviteContactSave.existing;
          writes++;
          stored = verified;
          return InviteContactSave.created;
        },
        launch: (trusted, {required canQueue, required canTransmit}) async {
          launched.add(trusted);
          if (!canQueue() || !retainRetry) {
            return (sendResult: null, retryRetained: false);
          }
          checkingTransmission = true;
          try {
            final allowed = await canTransmit().timeout(_deadline);
            transmitPermitted = allowed;
            if (!allowed) return (sendResult: null, retryRetained: true);
            transmissions++;
            return (sendResult: sendResult, retryRetained: true);
          } finally {
            checkingTransmission = false;
          }
        },
        now: () => now,
      ).timeout(_deadline);
}
