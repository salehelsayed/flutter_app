import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/app/bootstrap/call_wake_contact_key_backfill.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';
import 'package:flutter_app/features/call/domain/received_call_wake_handle_store.dart';
import 'package:flutter_app/features/contact_request/application/accept_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/retry_incomplete_key_exchanges_use_case.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_contact_request_repository.dart';

const _scannerPeerId = '12D3KooWScannerAccount0001';
const _scannedPeerId = '12D3KooWScannedAccount0002';
const _scannerPublicKey = 'scanner-public-key';
const _scannedPublicKey = 'scanned-public-key';
const _scannerPrivateKey = 'scanner-private-key';
const _scannedPrivateKey = 'scanned-private-key';
const _scannerMlKemKey = 'scanner-mlkem-public-key';
const _scannedMlKemKey = 'scanned-mlkem-public-key';

final class _IdentityRepo implements IdentityRepository {
  _IdentityRepo(this.identity);

  IdentityModel identity;

  @override
  Future<IdentityModel?> loadIdentity() async => identity;

  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    this.identity = identity;
  }
}

/// Shared deterministic crypto boundary for the two listener graphs.
///
/// The production send/receive code still assembles, canonicalizes, encrypts,
/// decrypts, reconstructs, and verifies every payload. This fake only supplies
/// deterministic native bridge results and rejects signatures whose verified
/// data differs from the exact data originally signed.
final class _CryptoBus {
  final Map<String, String> privateKeyByPublicKey = <String, String>{};
  final Map<String, String> plaintextByCiphertext = <String, String>{};
  var _nextCiphertext = 0;

  String signatureFor(String privateKey, String data) =>
      base64UrlEncode(utf8.encode('$privateKey\u0000$data'));

  String encrypt(String plaintext) {
    final ciphertext = 'ciphertext-${++_nextCiphertext}';
    plaintextByCiphertext[ciphertext] = plaintext;
    return ciphertext;
  }
}

final class _DeterministicBridge extends Bridge {
  _DeterministicBridge(this.bus);

  final _CryptoBus bus;
  final List<Map<String, dynamic>> encryptedPlaintexts =
      <Map<String, dynamic>>[];
  var verifiedPayloadCount = 0;

  @override
  bool get isInitialized => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<void> reinitialize() async {}

  @override
  void dispose() {}

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    final payload =
        request['payload'] as Map<String, dynamic>? ??
        const <String, dynamic>{};

    switch (request['cmd']) {
      case 'payload.sign':
        final data = payload['data'] as String;
        final privateKey = payload['privateKey'] as String;
        return jsonEncode(<String, Object>{
          'ok': true,
          'signature': bus.signatureFor(privateKey, data),
        });
      case 'payload.verify':
        final publicKey = payload['publicKey'] as String;
        final data = payload['data'] as String;
        final signature = payload['signature'] as String;
        final privateKey = bus.privateKeyByPublicKey[publicKey];
        final valid =
            privateKey != null &&
            signature == bus.signatureFor(privateKey, data);
        if (valid) verifiedPayloadCount += 1;
        return jsonEncode(<String, Object>{'ok': true, 'valid': valid});
      case 'contactrequest.encrypt':
        final plaintext = payload['plaintext'] as String;
        encryptedPlaintexts.add(jsonDecode(plaintext) as Map<String, dynamic>);
        final ciphertext = bus.encrypt(plaintext);
        return jsonEncode(<String, Object>{
          'ok': true,
          'ephemeralPublicKey': 'ephemeral-$ciphertext',
          'ciphertext': ciphertext,
          'nonce': 'nonce-$ciphertext',
        });
      case 'contactrequest.decrypt':
        final ciphertext = payload['ciphertext'] as String;
        final plaintext = bus.plaintextByCiphertext[ciphertext];
        return jsonEncode(<String, Object?>{
          'ok': plaintext != null,
          'plaintext': ?plaintext,
        });
      default:
        return jsonEncode(<String, Object>{'ok': true});
    }
  }
}

final class _InMemoryReceivedCallWakeHandleStore
    implements ReceivedCallWakeHandleStore {
  final Map<String, CallWakeHandleGrant> _grants =
      <String, CallWakeHandleGrant>{};

  @override
  Future<CallWakeHandleGrant?> readForIssuer(
    String issuerAccountPeerId,
  ) async => _grants[issuerAccountPeerId];

  @override
  Future<bool> storeIfStrictlyNewer({
    required String issuerAccountPeerId,
    required CallWakeHandleGrant grant,
    required int nowMs,
  }) async {
    if (!grant.isValidAt(nowMs)) return false;
    final prior = _grants[issuerAccountPeerId];
    if (prior != null && !grant.isStrictlyNewerThan(prior)) return false;
    _grants[issuerAccountPeerId] = grant;
    return true;
  }

  @override
  Future<void> removeForIssuer(String issuerAccountPeerId) async {
    _grants.remove(issuerAccountPeerId);
  }

  @override
  Future<void> clear() async => _grants.clear();
}

IdentityModel _identity({
  required String peerId,
  required String publicKey,
  required String privateKey,
  required String mlKemPublicKey,
}) {
  const timestamp = '2026-01-01T00:00:00.000Z';
  return IdentityModel(
    peerId: peerId,
    publicKey: publicKey,
    privateKey: privateKey,
    mnemonic12:
        'one two three four five six seven eight nine ten eleven twelve',
    mlKemPublicKey: mlKemPublicKey,
    mlKemSecretKey: 'secret-$mlKemPublicKey',
    username: 'User-$peerId',
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

Future<ContactModel?> _ignoreAvatarDownload({
  required Bridge bridge,
  required ContactRepository contactRepo,
  required String ownerPeerId,
  required String avatarVersion,
}) async => null;

void main() {
  test(
    'one scan backfills call wake after verified reciprocal installs ML-KEM',
    () async {
      final network = FakeP2PNetwork();
      final scannerP2p = FakeP2PService(
        peerId: _scannerPeerId,
        network: network,
      );
      final scannedP2p = FakeP2PService(
        peerId: _scannedPeerId,
        network: network,
      );
      addTearDown(scannerP2p.dispose);
      addTearDown(scannedP2p.dispose);

      final bus = _CryptoBus()
        ..privateKeyByPublicKey.addAll(<String, String>{
          _scannerPublicKey: _scannerPrivateKey,
          _scannedPublicKey: _scannedPrivateKey,
        });
      final scannerBridge = _DeterministicBridge(bus);
      final scannedBridge = _DeterministicBridge(bus);
      scannerP2p.directReplyBuilder = (targetPeerId, message, delivered) {
        final signedPlaintext = scannerBridge.encryptedPlaintexts.last;
        final challenge = signedPlaintext['cwr'];
        return SendMessageResult(
          sent: delivered,
          acked: delivered,
          reply: !delivered
              ? null
              : challenge is String
              ? jsonEncode(<String, String>{'callWakeReceipt': challenge})
              : 'received: $message',
        );
      };
      final scannerIdentityRepo = _IdentityRepo(
        _identity(
          peerId: _scannerPeerId,
          publicKey: _scannerPublicKey,
          privateKey: _scannerPrivateKey,
          mlKemPublicKey: _scannerMlKemKey,
        ),
      );
      final scannedIdentityRepo = _IdentityRepo(
        _identity(
          peerId: _scannedPeerId,
          publicKey: _scannedPublicKey,
          privateKey: _scannedPrivateKey,
          mlKemPublicKey: _scannedMlKemKey,
        ),
      );

      final scannerContacts = InMemoryContactRepository();
      final scannerRequests = InMemoryContactRequestRepository();
      final scannedContacts = InMemoryContactRepository();
      final scannedRequests = InMemoryContactRequestRepository();
      final receivedCallWakeHandles = _InMemoryReceivedCallWakeHandleStore();

      // A compact QR installs only the scanned account's ordinary public key.
      // The reciprocal contact request must supply its ML-KEM key later.
      scannerContacts.addTestContact(
        const ContactModel(
          peerId: _scannedPeerId,
          publicKey: _scannedPublicKey,
          rendezvous: '/dns4/relay.example/tcp/4001/p2p/$_scannedPeerId',
          username: 'Scanned',
          signature: 'qr-signature',
          scannedAt: '2026-01-01T00:00:00.000Z',
        ),
      );
      expect(
        (await scannerContacts.getContact(_scannedPeerId))?.mlKemPublicKey,
        isNull,
      );

      CallWakeHandleGrant? issuedGrant;
      final distributionPending = <String>{};
      final orchestration = <String>[];
      final backfillCompleted = Completer<bool>();
      final callWakeStored = Completer<void>();
      var retrySent = 0;
      var resolveCalls = 0;
      var callabilityRefreshes = 0;

      Future<CallWakeHandleGrant?> resolveScannerGrant(String peerId) async {
        expect(peerId, _scannedPeerId);
        resolveCalls += 1;
        return issuedGrant;
      }

      final scannerListener = ContactRequestListener(
        contactRequestStream: scannerP2p.messageStream,
        requestRepo: scannerRequests,
        contactRepo: scannerContacts,
        bridge: scannerBridge,
        getOwnPeerId: () => _scannerPeerId,
        getOwnPrivateKey: () async => _scannerPrivateKey,
        downloadProfilePictureFn: _ignoreAvatarDownload,
      );

      final scannedListener = ContactRequestListener(
        contactRequestStream: scannedP2p.messageStream,
        requestRepo: scannedRequests,
        contactRepo: scannedContacts,
        bridge: scannedBridge,
        getOwnPeerId: () => _scannedPeerId,
        getOwnPrivateKey: () async => _scannedPrivateKey,
        downloadProfilePictureFn: _ignoreAvatarDownload,
        receivedCallWakeHandleStore: receivedCallWakeHandles,
        onCallWakeHandleStored: () async {
          callabilityRefreshes += 1;
          if (!callWakeStored.isCompleted) callWakeStored.complete();
        },
        autoAcceptAndReciprocate: (peerId) async {
          final request = await scannedRequests.getRequest(peerId);
          if (request == null ||
              request.status != ContactRequestStatus.pending) {
            return AcceptContactRequestResult.notPending;
          }
          await scannedContacts.addContact(request.toContactModel());
          await scannedRequests.updateStatus(
            peerId,
            ContactRequestStatus.accepted,
          );
          final result = await sendContactRequest(
            p2pService: scannedP2p,
            identityRepo: scannedIdentityRepo,
            bridge: scannedBridge,
            targetPeerId: peerId,
            recipientPublicKey: request.publicKey,
          );
          expect(result, SendContactRequestResult.success);
          return AcceptContactRequestResult.success;
        },
      );

      addTearDown(scannerListener.dispose);
      addTearDown(scannedListener.dispose);

      final keyUpdateSubscription = scannerListener.contactKeyUpdatedStream
          .listen((updatedContact) {
            () async {
              try {
                expect(updatedContact.peerId, _scannedPeerId);
                expect(updatedContact.mlKemPublicKey, _scannedMlKemKey);
                final completed = await backfillCallWakeAfterContactKeyUpdate(
                  reconcileCallWakeEligibility: () async {
                    orchestration.add('reconcile');
                    final contact = await scannerContacts.getContact(
                      _scannedPeerId,
                    );
                    expect(contact?.mlKemPublicKey, _scannedMlKemKey);
                    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
                    issuedGrant = CallWakeHandleGrant(
                      handle: '0123456789abcdef0123456789abcdef',
                      recipientDevicePeerId: 'scanner-device-1',
                      deviceKeyEpoch: 1,
                      generation: 1,
                      issuedAtMs: nowMs - 1000,
                      expiresAtMs:
                          nowMs + const Duration(hours: 1).inMilliseconds,
                    );
                    distributionPending.add(_scannedPeerId);
                  },
                  hasPendingCallWakeDistribution: () async {
                    orchestration.add('pending');
                    return distributionPending.isNotEmpty;
                  },
                  retryCallWakeDistribution:
                      ({required trigger, required requireFresh}) async {
                        expect(requireFresh, isFalse);
                        orchestration.add('retry:$trigger');
                        retrySent = await retryIncompleteKeyExchanges(
                          contactRepo: scannerContacts,
                          identityRepo: scannerIdentityRepo,
                          p2pService: scannerP2p,
                          bridge: scannerBridge,
                          loadPendingCallWakeHandleContactIds: () async =>
                              distributionPending,
                          resolveCallWakeHandle: resolveScannerGrant,
                          onCallWakeHandleDistributed: (peerId, grant) async {
                            expect(peerId, _scannedPeerId);
                            expect(grant, issuedGrant);
                            distributionPending.remove(peerId);
                          },
                        );
                        return retrySent;
                      },
                );
                if (!backfillCompleted.isCompleted) {
                  backfillCompleted.complete(completed);
                }
              } catch (error, stackTrace) {
                if (!backfillCompleted.isCompleted) {
                  backfillCompleted.completeError(error, stackTrace);
                }
              }
            }();
          });
      addTearDown(keyUpdateSubscription.cancel);

      scannerListener.start();
      scannedListener.start();

      // The scan-side first request resolves no grant. Its verified delivery
      // causes the scanned account to auto-add and send the reciprocal.
      final firstSend = await sendContactRequest(
        p2pService: scannerP2p,
        identityRepo: scannerIdentityRepo,
        bridge: scannerBridge,
        targetPeerId: _scannedPeerId,
        recipientPublicKey: _scannedPublicKey,
        resolveCallWakeHandle: resolveScannerGrant,
      );
      expect(firstSend, SendContactRequestResult.success);

      expect(
        await backfillCompleted.future.timeout(const Duration(seconds: 2)),
        isTrue,
      );
      await callWakeStored.future.timeout(const Duration(seconds: 2));

      // The first scanner payload had no capability. The reciprocal was
      // signature-verified and installed the formerly absent ML-KEM key.
      expect(scannerBridge.encryptedPlaintexts, hasLength(2));
      expect(scannerBridge.encryptedPlaintexts.first, isNot(contains('cwh')));
      expect(scannerBridge.verifiedPayloadCount, 1);
      expect(
        (await scannerContacts.getContact(_scannedPeerId))?.mlKemPublicKey,
        _scannedMlKemKey,
      );

      // The key-update backfill issued a pending grant, selected the otherwise
      // complete contact in the real retry use case, and sent a cwh-bearing v2
      // key-exchange retry. Successful distribution drained only that pending
      // state, and the receiver accepted the exact signed grant.
      expect(orchestration, <String>[
        'reconcile',
        'pending',
        'retry:$callWakeContactKeyUpdatedTrigger',
      ]);
      expect(retrySent, 1);
      expect(resolveCalls, 2);
      expect(distributionPending, isEmpty);
      expect(
        scannerBridge.encryptedPlaintexts.last['cwh'],
        issuedGrant?.toCanonicalMap(),
      );
      expect(
        await receivedCallWakeHandles.readForIssuer(_scannerPeerId),
        issuedGrant,
      );
      expect(scannedBridge.verifiedPayloadCount, 2);
      expect(callabilityRefreshes, 1);
      expect(network.deliverCallCount, 3);
    },
  );
}
