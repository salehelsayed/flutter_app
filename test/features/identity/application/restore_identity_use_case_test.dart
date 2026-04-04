import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/identity/application/restore_identity_use_case.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/test_user.dart';

class _FakeIdentityRepo implements IdentityRepository {
  IdentityModel? savedIdentity;
  bool shouldThrowOnSave = false;

  @override
  Future<IdentityModel?> loadIdentity() async => savedIdentity;

  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    if (shouldThrowOnSave) throw Exception('DB write failed');
    savedIdentity = identity;
  }
}

const _validMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

final _fakeIdentityResponse = {
  'ok': true,
  'identity': {
    'peerId': '12D3KooWTestRestore',
    'publicKey': 'publicKeyBase64',
    'privateKey': 'privateKeyBase64',
    'mnemonic12': _validMnemonic,
    'createdAt': '2024-01-01T00:00:00Z',
    'updatedAt': '2024-01-01T00:00:00Z',
  },
};

const _fakeMlKemResponse = {
  'ok': true,
  'publicKey': 'mlkemPub',
  'secretKey': 'mlkemSec',
};

void main() {
  late _FakeIdentityRepo repo;
  late List<String> progressStages;
  late String? lastRestoredMnemonic;

  setUp(() {
    repo = _FakeIdentityRepo();
    progressStages = [];
    lastRestoredMnemonic = null;
  });

  Future<Map<String, dynamic>> fakeRestore(String mnemonic) async {
    lastRestoredMnemonic = mnemonic;
    return _fakeIdentityResponse;
  }

  test('success: restores identity with normalized mnemonic', () async {
    final result = await restoreIdentityFromMnemonic(
      input:
          '  Abandon  ABANDON   abandon abandon abandon abandon abandon abandon abandon abandon abandon about  ',
      callRestore: fakeRestore,
      callMlKemKeygen: () async => _fakeMlKemResponse,
      repo: repo,
      onProgress: (s) => progressStages.add(s),
    );

    expect(result, equals(RestoreIdentityResult.success));
    expect(repo.savedIdentity, isNotNull);
    expect(repo.savedIdentity!.peerId, equals('12D3KooWTestRestore'));
    expect(repo.savedIdentity!.mlKemPublicKey, equals('mlkemPub'));
    // Verify normalization: lowercase, trimmed, single spaces
    expect(lastRestoredMnemonic, equals(_validMnemonic));
    expect(progressStages, contains('generating_keys'));
    expect(progressStages, contains('saving'));
  });

  test('invalidMnemonicFormat: too few words', () async {
    final result = await restoreIdentityFromMnemonic(
      input: 'only three words',
      callRestore: fakeRestore,
      callMlKemKeygen: () async => _fakeMlKemResponse,
      repo: repo,
    );

    expect(result, equals(RestoreIdentityResult.invalidMnemonicFormat));
    expect(repo.savedIdentity, isNull);
  });

  test('invalidMnemonicFormat: too many words', () async {
    final result = await restoreIdentityFromMnemonic(
      input: 'a b c d e f g h i j k l m',
      callRestore: fakeRestore,
      callMlKemKeygen: () async => _fakeMlKemResponse,
      repo: repo,
    );

    expect(result, equals(RestoreIdentityResult.invalidMnemonicFormat));
  });

  test('invalidMnemonicCore: bridge returns INVALID_MNEMONIC', () async {
    final result = await restoreIdentityFromMnemonic(
      input: _validMnemonic,
      callRestore: (_) async => {
        'ok': false,
        'errorCode': 'INVALID_MNEMONIC',
        'errorMessage': 'Not a valid BIP39 mnemonic',
      },
      callMlKemKeygen: () async => _fakeMlKemResponse,
      repo: repo,
    );

    expect(result, equals(RestoreIdentityResult.invalidMnemonicCore));
  });

  test('coreLibError: bridge returns other error', () async {
    final result = await restoreIdentityFromMnemonic(
      input: _validMnemonic,
      callRestore: (_) async => {
        'ok': false,
        'errorCode': 'INTERNAL_ERROR',
        'errorMessage': 'Something went wrong',
      },
      callMlKemKeygen: () async => _fakeMlKemResponse,
      repo: repo,
    );

    expect(result, equals(RestoreIdentityResult.coreLibError));
  });

  test('coreLibError: bridge throws exception', () async {
    final result = await restoreIdentityFromMnemonic(
      input: _validMnemonic,
      callRestore: (_) async => throw Exception('Bridge crashed'),
      callMlKemKeygen: () async => _fakeMlKemResponse,
      repo: repo,
    );

    expect(result, equals(RestoreIdentityResult.coreLibError));
  });

  test('coreLibError: ML-KEM keygen fails', () async {
    final result = await restoreIdentityFromMnemonic(
      input: _validMnemonic,
      callRestore: fakeRestore,
      callMlKemKeygen: () async => {'ok': false, 'errorCode': 'MLKEM_FAIL'},
      repo: repo,
    );

    expect(result, equals(RestoreIdentityResult.coreLibError));
  });

  test('dbError: repo.saveIdentity throws', () async {
    repo.shouldThrowOnSave = true;

    final result = await restoreIdentityFromMnemonic(
      input: _validMnemonic,
      callRestore: fakeRestore,
      callMlKemKeygen: () async => _fakeMlKemResponse,
      repo: repo,
    );

    expect(result, equals(RestoreIdentityResult.dbError));
  });

  test(
    'success: restored identity can receive queued messages after device recovery',
    () async {
      final result = await restoreIdentityFromMnemonic(
        input: _validMnemonic,
        callRestore: fakeRestore,
        callMlKemKeygen: () async => _fakeMlKemResponse,
        repo: repo,
      );

      expect(result, RestoreIdentityResult.success);
      final restoredIdentity = repo.savedIdentity;
      expect(restoredIdentity, isNotNull);

      final network = FakeP2PNetwork();
      final alice = TestUser.create(
        peerId: 'alice-restore-sender',
        username: 'Alice',
        network: network,
      );
      final restoredUser = TestUser.create(
        peerId: restoredIdentity!.peerId,
        username: 'Recovered',
        network: network,
      );

      alice.addContact(restoredUser);
      restoredUser.addContact(alice);

      alice.start();
      restoredUser.start();
      restoredUser.p2pService.setOnline(false);

      try {
        final (sendResult, _) = await alice.sendMessage(
          restoredUser.peerId,
          'Welcome back after restore',
        );
        expect(sendResult, SendChatMessageResult.success);

        restoredUser.p2pService.setOnline(true);
        final drained = await restoredUser.drainOfflineInbox();
        expect(drained, 1);

        await Future<void>.delayed(const Duration(milliseconds: 100));

        final restoredConversation = await restoredUser.loadConversationWith(
          alice.peerId,
        );
        expect(restoredConversation, hasLength(1));
        expect(restoredConversation.single.isIncoming, isTrue);
        expect(restoredConversation.single.text, 'Welcome back after restore');
        expect(restoredConversation.single.senderPeerId, alice.peerId);
      } finally {
        alice.dispose();
        restoredUser.dispose();
      }
    },
  );
}
