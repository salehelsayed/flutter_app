import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/identity/data/repositories/identity_repository_impl.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

import '../../../../core/secure_storage/fake_secure_key_store.dart';

const _limit = Duration(seconds: 2);
const _observerSecret = 'b294-observer-private-error-sentinel';
Future<T> _bounded<T>(Future<T> future) => future.timeout(_limit);

IdentityModel _identity(String account, {String username = 'name'}) => IdentityModel(
  peerId: '12D3KooWB294RepositoryLogicalRoot$account',
  publicKey: 'root-public-$account',
  privateKey: 'b294-root-private-key-$account',
  mnemonic12: 'b294 mnemonic remains outside observer logs',
  username: username,
  createdAt: '2026-11-15T12:00:00Z',
  updatedAt: '2026-11-15T12:00:00Z',
);

Map<String, Object?> _row(IdentityModel identity) => {
  'peer_id': identity.peerId,
  'public_key': identity.publicKey,
  'private_key': null,
  'mnemonic12': null,
  'ml_kem_public_key': null,
  'ml_kem_secret_key': null,
  'username': identity.username,
  'avatar_blob': null,
  'avatar_version': null,
  'created_at': identity.createdAt,
  'updated_at': identity.updatedAt,
};

final class _ObservedSecrets implements SecureKeyStore {
  final FakeSecureKeyStore backing = FakeSecureKeyStore();
  final List<String> events;
  int reads = 0;

  _ObservedSecrets(this.events);

  Future<void> seed(IdentityModel identity) async {
    await backing.write(identityPrivateKeyStorageKey, identity.privateKey);
    await backing.write(identityMnemonic12StorageKey, identity.mnemonic12);
  }

  @override
  Future<String?> read(String key) async {
    reads++;
    return backing.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    events.add('secret-write');
    await backing.write(key, value);
  }

  @override
  Future<void> delete(String key) => backing.delete(key);

  @override
  Future<bool> containsKey(String key) => backing.containsKey(key);
}

void main() {
  late List<String> events;
  late _ObservedSecrets secrets;
  late Map<String, Object?>? stored;
  late int loads;
  late bool failUpsert;
  FutureOr<void> Function(IdentityModel?)? observe;
  Future<void> Function()? retireNative;
  late IdentityRepositoryImpl repository;

  setUp(() {
    events = [];
    secrets = _ObservedSecrets(events);
    stored = null;
    loads = 0;
    failUpsert = false;
    observe = null;
    retireNative = null;
    repository = IdentityRepositoryImpl(
      dbLoadIdentityRow: () async {
        loads++;
        return stored;
      },
      dbUpsertIdentityRow: (row) async {
        events.add('database-commit');
        if (failUpsert) throw StateError('b294 forced write failure');
        stored = row;
      },
      secureKeyStore: secrets,
      publishCanonicalAccountBinding: (_) async {
        events.add('canonical-binding-commit');
      },
      retireIosNseInboxTransport: () async {
        events.add('native-retire');
        await retireNative?.call();
      },
      observeLoadedIdentity: (identity) {
        final observer = observe;
        if (observer != null) return observer(identity);
      },
    );
  });

  Future<void> seedA() async {
    stored = _row(_identity('A'));
    await _bounded(secrets.seed(_identity('A')));
  }

  test('loaded-root observer runs after cache and canonical binding commit', () async {
    await seedA();
    final seen = <IdentityModel?>[];
    final cacheReads = <Future<IdentityModel?>>[];
    var reentered = false;
    observe = (identity) {
      events.add('observed');
      seen.add(identity);
      if (identity != null && !reentered) {
        reentered = true;
        cacheReads.add(repository.loadIdentity());
      }
    };
    final root = await _bounded(repository.loadIdentity());
    expect(seen.whereType<IdentityModel>(), hasLength(1));
    expect(seen.whereType<IdentityModel>().single, same(root));
    expect(seen.whereType<IdentityModel>().single.privateKey, _identity('A').privateKey);
    expect(events.indexOf('canonical-binding-commit'), lessThan(events.indexOf('observed')));
    expect(cacheReads, hasLength(1));
    expect(await _bounded(cacheReads.single), same(root));
    expect(loads, 1, reason: 'Observer must not reenter an uncached root load');
    final count = seen.length;
    await _bounded(repository.loadIdentity());
    expect(seen.length, count, reason: 'Cache reads are not new activity or binding changes');
  });

  test('saved root is observed only after SQL and cached snapshot are committed', () async {
    final seen = <IdentityModel?>[];
    final cacheReads = <Future<IdentityModel?>>[];
    observe = (identity) {
      seen.add(identity);
      if (identity != null) {
        events.add('observed-committed-root');
        cacheReads.add(repository.loadIdentity());
      }
    };
    final root = _identity('A');
    await _bounded(repository.saveIdentity(root));
    expect(seen.whereType<IdentityModel>(), [same(root)]);
    expect(events.indexOf('database-commit'), lessThan(events.indexOf('observed-committed-root')));
    expect(events.indexOf('canonical-binding-commit'), lessThan(events.indexOf('observed-committed-root')));
    expect(await _bounded(cacheReads.single), same(root));
    expect(loads, 0);
    expect(stored!['private_key'], isNull);
  });

  test('replacement retires observer before first credential-changing await', () async {
    await seedA();
    final seen = <IdentityModel?>[];
    observe = (identity) {
      seen.add(identity);
      events.add(identity == null ? 'observe-retired' : 'observe-root');
    };
    await _bounded(repository.loadIdentity());
    expect(seen.whereType<IdentityModel>(), isNotEmpty,
        reason: 'Positive root publication control precedes retirement assertions');
    seen.clear();
    events.clear();
    final entered = Completer<void>();
    final release = Completer<void>();
    Future<void>? saving;
    retireNative = () async {
      entered.complete();
      await _bounded(release.future);
    };
    try {
      saving = repository.saveIdentity(_identity('B'));
      await _bounded(entered.future);
      expect(seen, [isNull]);
      expect(events.first, 'observe-retired');
      expect(events, isNot(contains('secret-write')));
      release.complete();
      await _bounded(saving);
      expect(seen.last?.peerId, _identity('B').peerId);
    } finally {
      if (!release.isCompleted) release.complete();
      if (saving != null) await _bounded(saving);
    }
  });

  test('invalidateCache retires synchronously and import publishes fresh root', () async {
    await seedA();
    final seen = <IdentityModel?>[];
    observe = seen.add;
    await _bounded(repository.loadIdentity());
    expect(seen.whereType<IdentityModel>(), isNotEmpty);
    seen.clear();
    repository.invalidateCache();
    expect(seen, [isNull]);
    stored = _row(_identity('B'));
    await _bounded(secrets.seed(_identity('B')));
    await _bounded(repository.loadIdentity());
    expect(seen.last?.peerId, _identity('B').peerId);
  });

  test('replacement awaits bounded null-observer attempt before secret writes', () async {
    await seedA();
    final seen = <IdentityModel?>[];
    observe = seen.add;
    await _bounded(repository.loadIdentity());
    expect(seen.whereType<IdentityModel>(), isNotEmpty);
    events.clear();
    final entered = Completer<void>();
    final release = Completer<void>();
    Future<void>? saving;
    observe = (identity) {
      seen.add(identity);
      if (identity == null) {
        events.add('observer-retire');
        entered.complete();
        return release.future;
      }
    };
    try {
      var complete = false;
      saving = repository.saveIdentity(_identity('B')).whenComplete(() => complete = true);
      await _bounded(entered.future);
      expect(events, ['observer-retire']);
      expect(complete, isFalse);
      release.complete();
      await _bounded(saving);
      expect(complete, isTrue);
      expect(seen.last?.peerId, _identity('B').peerId);
    } finally {
      if (!release.isCompleted) release.complete();
      if (saving != null) await _bounded(saving);
    }
  });

  test('null-observer timeout cannot fail or indefinitely block identity save', () async {
    await seedA();
    final seen = <IdentityModel?>[];
    observe = seen.add;
    await _bounded(repository.loadIdentity());
    expect(seen.whereType<IdentityModel>(), isNotEmpty);
    events.clear();
    final release = Completer<void>();
    Future<void>? saving;
    var retireCalls = 0;
    observe = (identity) {
      if (identity == null) {
        retireCalls++;
        return release.future;
      }
    };
    try {
      fakeAsync((clock) {
        try {
          var complete = false;
          saving = repository.saveIdentity(_identity('B')).whenComplete(() => complete = true);
          clock.flushMicrotasks();
          expect(retireCalls, 1);
          expect(events, isEmpty);
          expect(complete, isFalse);
          clock.elapse(_limit);
          clock.flushMicrotasks();
          expect(complete, isTrue);
          expect(stored!['peer_id'], _identity('B').peerId);
        } finally {
          if (!release.isCompleted) release.complete();
          clock.flushMicrotasks();
        }
      });
      if (saving != null) await _bounded(saving!);
    } finally {
      if (!release.isCompleted) release.complete();
      if (saving != null) await _bounded(saving!);
    }
  });

  test('same-root metadata save publishes snapshot without retiring pending owner', () async {
    await seedA();
    final seen = <IdentityModel?>[];
    observe = seen.add;
    await _bounded(repository.loadIdentity());
    expect(seen.whereType<IdentityModel>(), isNotEmpty);
    seen.clear();
    final renamed = _identity('A', username: 'renamed');
    await _bounded(repository.saveIdentity(renamed));
    expect(seen, [same(renamed)]);
    expect(seen, isNot(contains(isNull)));
  });

  test('failed replacement leaves reporter retired and never publishes B', () async {
    await seedA();
    final seen = <IdentityModel?>[];
    observe = seen.add;
    await _bounded(repository.loadIdentity());
    expect(seen.whereType<IdentityModel>(), isNotEmpty);
    seen.clear();
    failUpsert = true;
    await expectLater(_bounded(repository.saveIdentity(_identity('B'))), throwsStateError);
    expect(seen, [isNull]);
    expect((await _bounded(repository.loadIdentity()))?.peerId, _identity('A').peerId,
        reason: 'Existing warm-cache failure behavior remains unchanged');
  });

  test('missing row and unavailable root secrets publish retirement', () async {
    final seen = <IdentityModel?>[];
    observe = seen.add;
    expect(await _bounded(repository.loadIdentity()), isNull);
    expect(seen, isNotEmpty);
    expect(seen.last, isNull);
    stored = _row(_identity('A'));
    repository.invalidateCache();
    seen.clear();
    await expectLater(_bounded(repository.loadIdentity()), throwsA(isA<IdentitySecretsUnavailableException>()));
    expect(seen, isNotEmpty);
    expect(seen.last, isNull);
  });

  test('throwing observer is failure-isolated and cannot leak its private error', () async {
    await seedA();
    final captured = <Map<String, dynamic>>[];
    final lease = installScopedE2EFlowEventSink(captured.add);
    var calls = 0;
    observe = (_) {
      calls++;
      throw StateError(_observerSecret);
    };
    try {
      expect((await _bounded(repository.loadIdentity()))?.peerId, _identity('A').peerId);
      expect(calls, greaterThan(0), reason: 'Observer must execute before isolation/privacy can pass');
      await _bounded(repository.saveIdentity(_identity('A', username: 'new name')));
      repository.invalidateCache();
      expect(jsonEncode(captured), isNot(contains(_observerSecret)));
      expect(jsonEncode(captured), isNot(contains(_identity('A').privateKey)));
    } finally {
      lease.release();
    }
  });

  test('rejected async observer is caught after commit and synchronous invalidation', () async {
    await seedA();
    final captured = <Map<String, dynamic>>[];
    final lease = installScopedE2EFlowEventSink(captured.add);
    var calls = 0;
    observe = (_) {
      calls++;
      return Future<void>.error(StateError(_observerSecret));
    };
    try {
      expect((await _bounded(repository.loadIdentity()))?.peerId, _identity('A').peerId);
      expect(calls, greaterThan(0));
      repository.invalidateCache();
      await _bounded(Future<void>.delayed(Duration.zero));
      expect(calls, greaterThan(1));
      expect(jsonEncode(captured), isNot(contains(_observerSecret)));
    } finally {
      lease.release();
    }
  });
}
