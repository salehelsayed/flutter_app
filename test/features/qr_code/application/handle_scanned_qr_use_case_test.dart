import 'dart:collection';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/qr_code/application/handle_scanned_qr_use_case.dart';

import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

void main() {
  late FakeBridge bridge;
  late FakeContactRepository contactRepo;
  late FakeIdentityRepository identityRepo;
  late FakeP2PService p2pService;

  const ownPeerId = 'own-peer-id-12345';

  final testIdentity = IdentityModel(
    peerId: ownPeerId,
    publicKey: 'own-public-key',
    privateKey: 'own-private-key',
    mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
    username: 'Alice',
    createdAt: DateTime.now().toUtc().toIso8601String(),
    updatedAt: DateTime.now().toUtc().toIso8601String(),
  );

  /// Builds a valid QR JSON string mimicking buildQRPayload output.
  String buildValidQRData({
    String peerId = 'scanned-peer-id',
    String publicKey = 'scanned-pk',
    String username = 'Bob',
  }) {
    final ts = DateTime.now().toUtc().toIso8601String();
    final payload = SplayTreeMap<String, dynamic>.from({
      'ns': peerId,
      'pk': publicKey,
      'rv': '/dns4/relay/tcp/443/p2p/relay',
      'ts': ts,
      'un': username,
    });
    // Add the signature field (will be verified by bridge)
    payload['sig'] = 'valid-sig';
    return jsonEncode(payload);
  }

  setUp(() {
    bridge = FakeBridge();
    contactRepo = FakeContactRepository();
    identityRepo = FakeIdentityRepository();
    p2pService = FakeP2PService();

    identityRepo.seed(testIdentity);

    // Make payload.verify return true by default
    bridge.responses['payload.verify'] = {'ok': true, 'valid': true};
    // Seed payload.sign + contactrequest.encrypt for v2 send
    bridge.responses['payload.sign'] = {'ok': true, 'signature': 'fakeSig'};
    bridge.responses['contactrequest.encrypt'] = {
      'ok': true,
      'ephemeralPublicKey': 'ephPubBase64',
      'ciphertext': 'ctBase64',
      'nonce': 'nonceBase64',
    };
  });

  group('handleScannedQR', () {
    test('returns invalidJson for malformed QR data', () async {
      final result = await handleScannedQR(
        qrData: 'not-valid-json{{{',
        bridge: bridge,
        contactRepo: contactRepo,
        identityRepo: identityRepo,
        p2pService: p2pService,
        ownPeerId: ownPeerId,
      );

      expect(result, HandleScannedQRResult.invalidJson);
    });

    test('returns success and adds contact for valid QR', () async {
      final qrData = buildValidQRData();

      final result = await handleScannedQR(
        qrData: qrData,
        bridge: bridge,
        contactRepo: contactRepo,
        identityRepo: identityRepo,
        p2pService: p2pService,
        ownPeerId: ownPeerId,
      );

      expect(result, HandleScannedQRResult.success);
      expect(contactRepo.addContactCallCount, 1);
      expect(contactRepo.lastAddedContact?.peerId, 'scanned-peer-id');
      expect(contactRepo.lastAddedContact?.username, 'Bob');
    });

    test('returns alreadyExists when contact exists', () async {
      // Pre-seed the contact
      final qrData = buildValidQRData();

      // First call adds it
      await handleScannedQR(
        qrData: qrData,
        bridge: bridge,
        contactRepo: contactRepo,
        identityRepo: identityRepo,
        p2pService: p2pService,
        ownPeerId: ownPeerId,
      );

      // Second call should return alreadyExists
      final result = await handleScannedQR(
        qrData: qrData,
        bridge: bridge,
        contactRepo: contactRepo,
        identityRepo: identityRepo,
        p2pService: p2pService,
        ownPeerId: ownPeerId,
      );

      expect(result, HandleScannedQRResult.alreadyExists);
    });

    test('returns selfScan when own peerId scanned', () async {
      final qrData = buildValidQRData(peerId: ownPeerId);

      final result = await handleScannedQR(
        qrData: qrData,
        bridge: bridge,
        contactRepo: contactRepo,
        identityRepo: identityRepo,
        p2pService: p2pService,
        ownPeerId: ownPeerId,
      );

      expect(result, HandleScannedQRResult.selfScan);
      expect(contactRepo.addContactCallCount, 0);
    });

    test('returns invalidSignature for tampered QR', () async {
      // Make verify return invalid
      bridge.responses['payload.verify'] = {'ok': true, 'valid': false};

      final qrData = buildValidQRData();

      final result = await handleScannedQR(
        qrData: qrData,
        bridge: bridge,
        contactRepo: contactRepo,
        identityRepo: identityRepo,
        p2pService: p2pService,
        ownPeerId: ownPeerId,
      );

      expect(result, HandleScannedQRResult.invalidSignature);
      expect(contactRepo.addContactCallCount, 0);
    });

    test('sends contact request in background on success', () async {
      final qrData = buildValidQRData();

      // The sendContactRequest will try to use p2pService which
      // has node not started, so it returns nodeNotRunning.
      // But handleScannedQR fires it off as fire-and-forget.
      final result = await handleScannedQR(
        qrData: qrData,
        bridge: bridge,
        contactRepo: contactRepo,
        identityRepo: identityRepo,
        p2pService: p2pService,
        ownPeerId: ownPeerId,
      );

      expect(result, HandleScannedQRResult.success);

      // Allow the fire-and-forget future to complete
      await Future.delayed(Duration.zero);
    });

    test('v2: sends encrypted envelope with contactrequest.encrypt', () async {
      // Use a running P2P service so sendContactRequest actually executes
      final runningP2P = FakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: ownPeerId,
        ),
      );
      runningP2P.storeInInboxResult = true;

      final qrData = buildValidQRData();

      final result = await handleScannedQR(
        qrData: qrData,
        bridge: bridge,
        contactRepo: contactRepo,
        identityRepo: identityRepo,
        p2pService: runningP2P,
        ownPeerId: ownPeerId,
      );

      expect(result, HandleScannedQRResult.success);

      // Allow the fire-and-forget future to complete
      await Future.delayed(const Duration(milliseconds: 200));

      // Verify contactrequest.encrypt was called (v2 path)
      expect(bridge.commandLog, contains('contactrequest.encrypt'));

      // Verify the command sequence: payload.sign then contactrequest.encrypt
      final signIdx = bridge.commandLog.indexOf('payload.sign');
      final encryptIdx = bridge.commandLog.indexOf('contactrequest.encrypt');
      expect(signIdx, greaterThanOrEqualTo(0));
      expect(encryptIdx, greaterThan(signIdx));

      // Verify the stored message is v2 envelope
      final storedMsg = runningP2P.lastStoreInInboxMessage;
      expect(storedMsg, isNotNull);
      final envelope = jsonDecode(storedMsg!) as Map<String, dynamic>;
      expect(envelope['type'], equals('contact_request'));
      expect(envelope['version'], equals('2'));
      expect(envelope['encrypted'], isA<Map>());
      expect(envelope.containsKey('payload'), isFalse);

      runningP2P.dispose();
    });

    test('success: calls downloadProfilePictureFn after adding contact',
        () async {
      final qrData = buildValidQRData();
      String? capturedPeerId;

      final result = await handleScannedQR(
        qrData: qrData,
        bridge: bridge,
        contactRepo: contactRepo,
        identityRepo: identityRepo,
        p2pService: p2pService,
        ownPeerId: ownPeerId,
        downloadProfilePictureFn: ({
          required bridge,
          required contactRepo,
          required ownerPeerId,
          required avatarVersion,
        }) async {
          capturedPeerId = ownerPeerId;
          return null;
        },
      );

      expect(result, HandleScannedQRResult.success);
      await Future.delayed(Duration.zero);
      expect(capturedPeerId, 'scanned-peer-id');
    });

    test('success: downloadProfilePictureFn failure does not affect result',
        () async {
      final qrData = buildValidQRData();

      final result = await handleScannedQR(
        qrData: qrData,
        bridge: bridge,
        contactRepo: contactRepo,
        identityRepo: identityRepo,
        p2pService: p2pService,
        ownPeerId: ownPeerId,
        downloadProfilePictureFn: ({
          required bridge,
          required contactRepo,
          required ownerPeerId,
          required avatarVersion,
        }) async {
          throw Exception('download failed');
        },
      );

      expect(result, HandleScannedQRResult.success);
      await Future.delayed(Duration.zero);
    });

    test('alreadyExists: does not call downloadProfilePictureFn', () async {
      final qrData = buildValidQRData();
      bool wasCalled = false;

      // First call adds the contact
      await handleScannedQR(
        qrData: qrData,
        bridge: bridge,
        contactRepo: contactRepo,
        identityRepo: identityRepo,
        p2pService: p2pService,
        ownPeerId: ownPeerId,
      );

      // Second call should return alreadyExists and NOT call download
      final result = await handleScannedQR(
        qrData: qrData,
        bridge: bridge,
        contactRepo: contactRepo,
        identityRepo: identityRepo,
        p2pService: p2pService,
        ownPeerId: ownPeerId,
        downloadProfilePictureFn: ({
          required bridge,
          required contactRepo,
          required ownerPeerId,
          required avatarVersion,
        }) async {
          wasCalled = true;
          return null;
        },
      );

      expect(result, HandleScannedQRResult.alreadyExists);
      await Future.delayed(Duration.zero);
      expect(wasCalled, isFalse);
    });
  });
}
