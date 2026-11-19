import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/diagnostics/active_identity_reporter.dart';
import 'package:flutter_app/features/identity/application/generate_identity_use_case.dart';
import 'package:flutter_app/features/identity/application/restore_identity_use_case.dart';
import 'package:flutter_app/features/identity/data/repositories/identity_repository_impl.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';

const _limit = Duration(seconds: 2);
const _account = 'b15-fresh-local-account';
const _binding =
    'v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _occurredAt = 1794937200123;
const _mnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const _identity = <String, dynamic>{
  'peerId': _account,
  'publicKey': 'public-in-memory-fixture',
  'privateKey': 'private-in-memory-fixture-not-a-real-key',
  'mnemonic12': _mnemonic,
  'createdAt': '2026-11-17T17:00:00Z',
  'updatedAt': '2026-11-17T17:00:00Z',
};
const _mlKem = <String, dynamic>{
  'ok': true,
  'publicKey': 'public-mlkem-fixture',
  'secretKey': 'private-mlkem-fixture-not-a-real-key',
};

Future<T> _bounded<T>(Future<T> f) => f.timeout(_limit);

final class _LocalBridge implements Bridge {
  final requests = <Map<String, dynamic>>[];
  int revision = 0;
  @override
  bool get isInitialized => true;

  List<Map<String, dynamic>> operations(String op) =>
      requests.where((request) => request['op'] == op).toList();

  @override
  Future<String> send(String raw) async {
    final envelope = jsonDecode(raw) as Map<String, dynamic>;
    expect(envelope['cmd'], 'active_identity_reporter_v1');
    final p = Map<String, dynamic>.from(envelope['payload'] as Map);
    requests.add(p);
    if (p['op'] == 'configure') revision++;
    return jsonEncode({
      'ok': true,
      'data': {
        'revision': p['op'] == 'configure' ? revision : p['revision'],
        'consentEpoch': p['consentEpoch'],
        if (p['op'] == 'configure')
          'configured': p['enabled'] == true && p['accountPeerId'] == _account,
        if (p['op'] == 'mark') 'accepted': true,
      },
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _LocalBridge bridge;
  late ActiveIdentityReporter reporter;
  late IdentityRepositoryImpl repository;
  late List<String> events;
  late List<String> creations;
  late Map<String, Object?>? row;
  late bool failDatabase;
  late bool failBinding;
  Completer<void>? databaseEntered;
  Completer<void>? databaseRelease;

  setUp(() async {
    events = [];
    creations = [];
    row = null;
    failDatabase = false;
    failBinding = false;
    databaseEntered = null;
    databaseRelease = null;
    bridge = _LocalBridge();
    reporter = ActiveIdentityReporter(
      statePath: '/unused-b15-registration.json',
    );
    reporter.attachBridge(bridge);
    await _bounded(reporter.observeConsent((enabled: true, consentEpoch: 91)));
    repository = IdentityRepositoryImpl(
      secureKeyStore: FakeSecureKeyStore(),
      dbLoadIdentityRow: () async => row,
      dbUpsertIdentityRow: (value) async {
        events.add('database-entered');
        databaseEntered?.complete();
        if (databaseRelease != null) await _bounded(databaseRelease!.future);
        if (failDatabase) throw StateError('public-fixture-database-failure');
        row = value;
        events.add('database-committed');
      },
      publishCanonicalAccountBinding: (_) async {
        if (failBinding) throw StateError('public-fixture-binding-failure');
        events.add('canonical-binding-committed');
      },
      observeLoadedIdentity: (identity) {
        if (identity == null) return reporter.retire();
        reporter.observeIdentity(
          accountPeerId: identity.peerId,
          rootPrivateKeyBase64: identity.privateKey,
          profileBinding: _binding,
        );
        events.add('committed-owner-observed');
      },
    );
  });

  tearDown(() async {
    if (databaseRelease != null && !databaseRelease!.isCompleted) {
      databaseRelease!.complete();
    }
    await _bounded(reporter.dispose());
  });

  void onCommitted(String account) {
    events.add('fresh-creation');
    creations.add(account);
    final capture = reporter.captureOwner(expectedAccountPeerId: account);
    if (capture != null)
      reporter.markCaptured(capture, occurredAtUnixMillis: _occurredAt);
  }

  Future<GenerateIdentityResult> generate({
    void Function(String)? observe,
    Future<Map<String, dynamic>> Function()? keygen,
  }) async {
    final generate = () async => <String, dynamic>{
      'ok': true,
      'identity': _identity,
    };
    final mlKem = keygen ?? (() async => _mlKem);
    // The old signature still runs the REAL generation/repository path in RED.
    // Catch only synchronous argument adaptation, never an async body error.
    late Future<GenerateIdentityResult> pending;
    try {
      pending = Function.apply(generateNewIdentity, [], {
        #callGenerate: generate,
        #callMlKemKeygen: mlKem,
        #repo: repository,
        #onFreshIdentityCommitted: observe ?? onCommitted,
      }) as Future<GenerateIdentityResult>;
    } on NoSuchMethodError {
      pending = generateNewIdentity(
        callGenerate: generate,
        callMlKemKeygen: mlKem,
        repo: repository,
      );
    }
    final result = await _bounded(pending);
    await _bounded(Future<void>.delayed(Duration.zero));
    return result;
  }

  test(
    'B15R-001 fresh offline creation marks active only after canonical commit',
    () async {
      expect(await generate(), GenerateIdentityResult.success);
      expect(creations, [_account]);
      expect(
        events.indexOf('fresh-creation'),
        greaterThan(events.indexOf('canonical-binding-committed')),
      );
      expect(
        events.indexOf('fresh-creation'),
        greaterThan(events.indexOf('committed-owner-observed')),
      );
      expect(bridge.operations('mark'), hasLength(1));
      expect(bridge.operations('mark').single, {
        'version': 1,
        'op': 'mark',
        'revision': 2,
        'consentEpoch': 91,
        'profileBinding': _binding,
        'accountPeerId': _account,
        'occurredAtUnixMillis': _occurredAt,
      });
      expect(bridge.operations('markWeekly'), isEmpty);
      expect(bridge.operations('flush'), isEmpty);
    },
  );

  test('B15R-002 held database commit cannot notify or mark early', () async {
    databaseEntered = Completer<void>();
    databaseRelease = Completer<void>();
    final pending = generate();
    await _bounded(databaseEntered!.future);
    expect(creations, isEmpty);
    expect(bridge.operations('mark'), isEmpty);
    databaseRelease!.complete();
    expect(await pending, GenerateIdentityResult.success);
    expect(creations, [_account]);
    expect(bridge.operations('mark'), hasLength(1));
  });

  test(
    'B15R-003 failed canonical binding is not a committed registration',
    () async {
      failBinding = true;
      expect(await generate(), GenerateIdentityResult.dbError);
      expect(creations, isEmpty);
      expect(bridge.operations('mark'), isEmpty);
    },
  );

  test(
    'B15R-004 failed identity database write never creates activity',
    () async {
      failDatabase = true;
      expect(await generate(), GenerateIdentityResult.dbError);
      expect(creations, isEmpty);
      expect(bridge.operations('mark'), isEmpty);
    },
  );

  test(
    'B15R-005 failed key generation never creates registration activity',
    () async {
      expect(
        await generate(keygen: () async => {'ok': false}),
        GenerateIdentityResult.coreLibError,
      );
      expect(row, isNull);
      expect(creations, isEmpty);
      expect(bridge.operations('mark'), isEmpty);
    },
  );

  test(
    'B15R-006 real mnemonic restore does not become fresh creation',
    () async {
      final result = await _bounded(
        restoreIdentityFromMnemonic(
          input: _mnemonic,
          callRestore: (_) async => {'ok': true, 'identity': _identity},
          callMlKemKeygen: () async => _mlKem,
          repo: repository,
        ),
      );
      expect(result, RestoreIdentityResult.success);
      expect(creations, isEmpty);
      expect(bridge.operations('mark'), isEmpty);
    },
  );

  test(
    'B15R-007 optional fresh observer failure cannot undo committed creation',
    () async {
      final result = await generate(
        observe: (account) {
          creations.add(account);
          throw StateError('private-observer-fixture-must-not-escape');
        },
      );
      expect(result, GenerateIdentityResult.success);
      expect(row?['peer_id'], _account);
      expect(creations, [_account]);
      expect(bridge.operations('mark'), isEmpty);
    },
  );

  test(
    'B15R-008 diagnostics OFF at creation commit never marks activity',
    () async {
      await _bounded(
        reporter.observeConsent((enabled: false, consentEpoch: 92)),
      );
      expect(await generate(), GenerateIdentityResult.success);
      expect(creations, [_account]);
      expect(bridge.operations('mark'), isEmpty);
    },
  );

  test(
    'B15R-009 later identity load or metadata save cannot repeat registration',
    () async {
      expect(await generate(), GenerateIdentityResult.success);
      expect(creations, [_account]);
      final loaded = await _bounded(repository.loadIdentity());
      await _bounded(repository.saveIdentity(loaded!));
      await _bounded(Future<void>.delayed(Duration.zero));
      expect(creations, [_account]);
      expect(bridge.operations('mark'), hasLength(1));
      expect(bridge.operations('markWeekly'), isEmpty);
    },
  );
}
