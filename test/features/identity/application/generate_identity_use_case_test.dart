import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/identity/application/generate_identity_use_case.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

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

const _fakeIdentityJson = {
  'peerId': '12D3KooWTestPeerId',
  'publicKey': 'publicKeyBase64',
  'privateKey': 'privateKeyBase64',
  'mnemonic12': 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
  'createdAt': '2024-01-01T00:00:00Z',
  'updatedAt': '2024-01-01T00:00:00Z',
};

const _fakeMlKemResponse = {
  'ok': true,
  'publicKey': 'mlkemPublicKeyBase64',
  'secretKey': 'mlkemSecretKeyBase64',
};

void main() {
  late _FakeIdentityRepo repo;
  late List<String> progressStages;

  setUp(() {
    repo = _FakeIdentityRepo();
    progressStages = [];
  });

  test('success: generates identity, runs ML-KEM keygen, saves to repo', () async {
    final result = await generateNewIdentity(
      callGenerate: () async => {'ok': true, 'identity': _fakeIdentityJson},
      callMlKemKeygen: () async => _fakeMlKemResponse,
      repo: repo,
      onProgress: (stage) => progressStages.add(stage),
    );

    expect(result, equals(GenerateIdentityResult.success));
    expect(repo.savedIdentity, isNotNull);
    expect(repo.savedIdentity!.peerId, equals('12D3KooWTestPeerId'));
    expect(repo.savedIdentity!.mlKemPublicKey, equals('mlkemPublicKeyBase64'));
    expect(repo.savedIdentity!.mlKemSecretKey, equals('mlkemSecretKeyBase64'));
    expect(progressStages, contains('generating_keys'));
    expect(progressStages, contains('saving'));
  });

  test('coreLibError: bridge returns ok=false', () async {
    final result = await generateNewIdentity(
      callGenerate: () async => {
        'ok': false,
        'errorCode': 'KEYGEN_FAILED',
        'errorMessage': 'Key generation failed',
      },
      callMlKemKeygen: () async => _fakeMlKemResponse,
      repo: repo,
    );

    expect(result, equals(GenerateIdentityResult.coreLibError));
    expect(repo.savedIdentity, isNull);
  });

  test('coreLibError: bridge throws exception', () async {
    final result = await generateNewIdentity(
      callGenerate: () async => throw Exception('Bridge crashed'),
      callMlKemKeygen: () async => _fakeMlKemResponse,
      repo: repo,
    );

    expect(result, equals(GenerateIdentityResult.coreLibError));
    expect(repo.savedIdentity, isNull);
  });

  test('coreLibError: response missing identity field', () async {
    final result = await generateNewIdentity(
      callGenerate: () async => {'ok': true},
      callMlKemKeygen: () async => _fakeMlKemResponse,
      repo: repo,
    );

    expect(result, equals(GenerateIdentityResult.coreLibError));
  });

  test('coreLibError: ML-KEM keygen fails', () async {
    final result = await generateNewIdentity(
      callGenerate: () async => {'ok': true, 'identity': _fakeIdentityJson},
      callMlKemKeygen: () async => {'ok': false, 'errorCode': 'MLKEM_FAILED'},
      repo: repo,
    );

    expect(result, equals(GenerateIdentityResult.coreLibError));
    expect(repo.savedIdentity, isNull);
  });

  test('coreLibError: ML-KEM keygen throws exception', () async {
    final result = await generateNewIdentity(
      callGenerate: () async => {'ok': true, 'identity': _fakeIdentityJson},
      callMlKemKeygen: () async {
        // Delay so the future error is caught by await, not the zone.
        await Future<void>.delayed(Duration.zero);
        throw Exception('ML-KEM crash');
      },
      repo: repo,
    );

    expect(result, equals(GenerateIdentityResult.coreLibError));
  });

  test('dbError: repo.saveIdentity throws', () async {
    repo.shouldThrowOnSave = true;

    final result = await generateNewIdentity(
      callGenerate: () async => {'ok': true, 'identity': _fakeIdentityJson},
      callMlKemKeygen: () async => _fakeMlKemResponse,
      repo: repo,
    );

    expect(result, equals(GenerateIdentityResult.dbError));
  });
}
