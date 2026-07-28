import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/debug/group_media_disposable_transport_start.dart';
import 'package:flutter_app/core/debug/group_media_ios_disposable_profile.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/application/start_node_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/identity/domain/repositories/fake_identity_repository.dart';

const _accountPeerId = 'account-peer';
const _transportPeerId = 'transport-peer';
const _transportPrivateKey = 'transport-private-key';

final _accountIdentity = IdentityModel(
  peerId: _accountPeerId,
  publicKey: 'account-public-key',
  privateKey: 'account-private-key',
  mnemonic12: 'one two three four five six seven eight nine ten eleven twelve',
  mlKemPublicKey: 'account-ml-kem-public-key',
  mlKemSecretKey: 'account-ml-kem-secret-key',
  username: 'P269 Account',
  createdAt: '2026-07-22T00:00:00.000Z',
  updatedAt: '2026-07-22T00:00:00.000Z',
);

Map<String, dynamic> _generatedIdentity({
  String peerId = _transportPeerId,
  String privateKey = _transportPrivateKey,
}) => <String, dynamic>{
  'ok': true,
  'identity': <String, dynamic>{'peerId': peerId, 'privateKey': privateKey},
};

final class _TrackingSecureKeyStore implements SecureKeyStore {
  final Map<String, String> values = <String, String>{};
  int readCount = 0;
  int writeCount = 0;

  @override
  Future<bool> containsKey(String key) async => values.containsKey(key);

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async {
    readCount++;
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    writeCount++;
    values[key] = value;
  }
}

void main() {
  group('startGroupMediaDisposableTransportNode', () {
    late FakeIdentityRepository identityRepository;
    late _TrackingSecureKeyStore secureKeyStore;
    late String? currentTransportPeerId;
    late int generateCalls;
    late int startCalls;

    setUp(() {
      identityRepository = FakeIdentityRepository()..seed(_accountIdentity);
      secureKeyStore = _TrackingSecureKeyStore();
      currentTransportPeerId = null;
      generateCalls = 0;
      startCalls = 0;
    });

    Future<StartNodeResult> run({
      String profile = groupMediaAndroidDisposableBuildProfile,
      Future<Map<String, dynamic>> Function()? generateIdentity,
      Future<bool> Function(String privateKey, String peerId)? startNode,
    }) => startGroupMediaDisposableTransportNode(
      identityRepository: identityRepository,
      secureKeyStore: secureKeyStore,
      installedProfileId: profile,
      generateIdentity:
          generateIdentity ??
          () async {
            generateCalls++;
            return _generatedIdentity();
          },
      startNode:
          startNode ??
          (privateKey, peerId) async {
            startCalls++;
            currentTransportPeerId = peerId;
            return true;
          },
      currentTransportPeerId: () => currentTransportPeerId,
    );

    test(
      'P269 absent blob generates once persists one account-bound document and starts distinct transport',
      () async {
        String? startedPrivateKey;
        String? startedPeerId;

        final result = await run(
          startNode: (privateKey, peerId) async {
            startCalls++;
            startedPrivateKey = privateKey;
            startedPeerId = peerId;
            currentTransportPeerId = peerId;
            return true;
          },
        );

        expect(result, StartNodeResult.success);
        expect(generateCalls, 1);
        expect(startCalls, 1);
        expect(startedPrivateKey, _transportPrivateKey);
        expect(startedPeerId, _transportPeerId);
        expect(startedPeerId, isNot(_accountPeerId));
        expect(secureKeyStore.writeCount, 1);

        final stored =
            jsonDecode(
                  secureKeyStore
                      .values[groupMediaDisposableTransportIdentityStorageKey]!,
                )
                as Map<String, dynamic>;
        expect(stored, <String, dynamic>{
          'schema': groupMediaDisposableTransportIdentitySchema,
          'accountPeerId': _accountPeerId,
          'transportPeerId': _transportPeerId,
          'transportPrivateKey': _transportPrivateKey,
        });
      },
    );

    test(
      'P269 relaunch reuses the stored transport without invoking generation',
      () async {
        expect(await run(), StartNodeResult.success);
        expect(generateCalls, 1);
        expect(secureKeyStore.writeCount, 1);

        currentTransportPeerId = null;
        final relaunched = await run(
          profile: groupMediaIosDisposableBuildProfile,
          generateIdentity: () async {
            fail('generation must not run when the secure blob exists');
          },
        );

        expect(relaunched, StartNodeResult.success);
        expect(generateCalls, 1);
        expect(startCalls, 2);
        expect(secureKeyStore.writeCount, 1);
      },
    );

    test(
      'P269 existing malformed or wrong-account blob fails closed without replacement',
      () async {
        final invalidDocuments = <String>[
          '{malformed',
          jsonEncode(<String, String>{
            'schema': groupMediaDisposableTransportIdentitySchema,
            'accountPeerId': 'different-account',
            'transportPeerId': _transportPeerId,
            'transportPrivateKey': _transportPrivateKey,
          }),
          jsonEncode(<String, String>{
            'schema': groupMediaDisposableTransportIdentitySchema,
            'accountPeerId': _accountPeerId,
            'transportPeerId': _accountPeerId,
            'transportPrivateKey': _transportPrivateKey,
          }),
        ];

        for (final invalidDocument in invalidDocuments) {
          secureKeyStore
                  .values[groupMediaDisposableTransportIdentityStorageKey] =
              invalidDocument;
          final result = await run(
            generateIdentity: () async {
              fail('an existing authority document must never be regenerated');
            },
          );
          expect(result, StartNodeResult.bridgeError);
          expect(
            secureKeyStore
                .values[groupMediaDisposableTransportIdentityStorageKey],
            invalidDocument,
          );
        }

        expect(startCalls, 0);
        expect(secureKeyStore.writeCount, 0);
      },
    );

    test(
      'P269 generated account-equal identity and post-start current-peer mismatch both fail closed',
      () async {
        final accountEqual = await run(
          generateIdentity: () async {
            generateCalls++;
            return _generatedIdentity(peerId: _accountPeerId);
          },
        );
        expect(accountEqual, StartNodeResult.bridgeError);
        expect(startCalls, 0);
        expect(secureKeyStore.writeCount, 0);

        final currentMismatch = await run(
          startNode: (privateKey, peerId) async {
            startCalls++;
            currentTransportPeerId = 'unexpected-current-transport';
            return true;
          },
        );
        expect(currentMismatch, StartNodeResult.bridgeError);
        expect(startCalls, 1);
        expect(secureKeyStore.writeCount, 1);
      },
    );

    test(
      'P269 no identity migration block and non-profile calls have no credential side effects',
      () async {
        identityRepository = FakeIdentityRepository();
        expect(await run(), StartNodeResult.noIdentity);

        identityRepository.seed(_accountIdentity);
        final blocked = await startGroupMediaDisposableTransportNode(
          identityRepository: identityRepository,
          secureKeyStore: secureKeyStore,
          installedProfileId: groupMediaAndroidDisposableBuildProfile,
          generateIdentity: () async {
            fail('migration-blocked startup must not generate');
          },
          startNode: (_, _) async {
            fail('migration-blocked startup must not start');
          },
          currentTransportPeerId: () => null,
          accountMigrationNetworkGate:
              ({String? peerId, required String operation}) async {
                expect(peerId, _accountPeerId);
                expect(operation, 'p2p_start');
                return false;
              },
        );
        expect(blocked, StartNodeResult.accountMigrationBlocked);

        expect(
          await run(profile: 'production-profile'),
          StartNodeResult.bridgeError,
        );
        expect(generateCalls, 0);
        expect(startCalls, 0);
        expect(secureKeyStore.readCount, 0);
        expect(secureKeyStore.writeCount, 0);
      },
    );

    test('P269 generator and start failures return only bridgeError', () async {
      final generationFailure = await run(
        generateIdentity: () async => throw StateError(
          'sensitive generation diagnostics must not escape',
        ),
      );
      expect(generationFailure, StartNodeResult.bridgeError);

      final startFailure = await run(startNode: (_, _) async => false);
      expect(startFailure, StartNodeResult.bridgeError);
      expect(secureKeyStore.writeCount, 1);
    });

    test(
      'production bootstrap delegates disposable start only through the debug E2E root',
      () {
        final productionSource = File(
          'lib/app/bootstrap/production_application_bootstrap.dart',
        ).readAsStringSync();
        final applicationRootSource = File(
          'lib/app/application_root.dart',
        ).readAsStringSync();
        final compositionSource = File(
          'lib/debug/debug_e2e_composition_root.dart',
        ).readAsStringSync();
        final wiring = compositionSource;
        expect(
          wiring,
          contains('isAndroidDisposableProfile || isIosDisposableProfile'),
        );
        expect(
          wiring,
          contains('if (!activation.suppliesDisposableNodeStart) return null;'),
        );
        expect(
          RegExp(
            r'startGroupMediaDisposableTransportNode\s*\(',
          ).allMatches(wiring),
          hasLength(1),
        );
        expect(wiring, contains('generateIdentity:'));
        expect(wiring, contains('startNode: p2pService.startNode'));
        expect(
          productionSource,
          contains('debugE2EStartP2PNodeOverride:'),
          reason:
              'the bootstrap must pass only the nullable root-owned handoff',
        );
        expect(
          applicationRootSource,
          contains('startP2PNodeOverride: widget.debugE2EStartP2PNodeOverride'),
        );
        expect(
          productionSource,
          isNot(contains('startGroupMediaDisposableTransportNode(')),
        );
      },
    );
  });
}
