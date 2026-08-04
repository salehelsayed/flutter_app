import 'package:flutter_app/core/notifications/canonical_runtime_lease.dart';
import 'package:flutter_app/core/notifications/dropped_push_recovery_bridge.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('foreground worker and fcm ownership matrix', () async {
    final gateway = _FakeLeaseGateway();
    final session = CanonicalWritableRuntimeSession(gateway: gateway);

    final opened = await session.acquireThenOpen(
      binding: 'v1:foreground',
      openDatabase: () async {
        gateway.trace.add('openDatabase');
        return 'database';
      },
    );

    expect(opened, 'database');
    expect(gateway.trace, [
      'acquire:v1:foreground',
      'openDatabase',
      'attachRuntime',
    ]);
    expect(session.hasWritableLease, isTrue);
    expect(
      const FirebaseReadOnlyRuntimePolicy().mayAcquireWritableLease,
      isFalse,
    );
  });

  test('database close fences transfer', () async {
    final gateway = _FakeLeaseGateway();
    final session = CanonicalWritableRuntimeSession(gateway: gateway);
    await session.acquireThenOpen(
      binding: 'v1:account-a',
      openDatabase: () async => Object(),
    );
    gateway.trace.clear();

    await session.drainCloseRelease(
      stopRuntime: () async => gateway.trace.add('stopRuntime'),
      closeDatabase: () async => gateway.trace.add('closeDatabase'),
    );

    expect(gateway.trace, [
      'beginDrain',
      'stopRuntime',
      'closeDatabase',
      'release:true',
    ]);
    expect(session.hasWritableLease, isFalse);
  });

  test('database close failure retains draining ownership', () async {
    final gateway = _FakeLeaseGateway();
    final session = CanonicalWritableRuntimeSession(gateway: gateway);
    await session.acquireThenOpen(
      binding: 'v1:account-a',
      openDatabase: () async => Object(),
    );
    gateway.trace.clear();

    await expectLater(
      session.drainCloseRelease(
        stopRuntime: () async => gateway.trace.add('stopRuntime'),
        closeDatabase: () async {
          gateway.trace.add('closeDatabase');
          throw StateError('SQLCipher close failed');
        },
      ),
      throwsStateError,
    );

    expect(gateway.trace, [
      'beginDrain',
      'stopRuntime',
      'closeDatabase',
      'release:false',
    ]);
    expect(session.hasWritableLease, isTrue);
    expect(session.state, CanonicalRuntimeLeaseState.draining);
  });

  test(
    'Go quiescence failure skips database close and never transfers',
    () async {
      final gateway = _FakeLeaseGateway();
      final session = CanonicalWritableRuntimeSession(gateway: gateway);
      await session.acquireThenOpen(
        binding: 'v1:account-a',
        openDatabase: () async => Object(),
      );
      gateway.trace.clear();

      await expectLater(
        session.drainCloseRelease(
          stopRuntime: () async {
            gateway.trace.add('stopRuntime');
            throw StateError('Go did not quiesce');
          },
          closeDatabase: () async => gateway.trace.add('closeDatabase'),
        ),
        throwsStateError,
      );

      expect(gateway.trace, ['beginDrain', 'stopRuntime', 'release:false']);
      expect(session.hasWritableLease, isTrue);
      expect(session.state, CanonicalRuntimeLeaseState.draining);
    },
  );

  test(
    'open failure without close acknowledgement retains ownership',
    () async {
      final gateway = _FakeLeaseGateway();
      final session = CanonicalWritableRuntimeSession(gateway: gateway);

      await expectLater(
        session.acquireThenOpen<Object>(
          binding: 'v1:account-a',
          openDatabase: () async => throw StateError('open failed'),
        ),
        throwsStateError,
      );

      expect(gateway.trace, [
        'acquire:v1:account-a',
        'beginDrain',
        'release:false',
      ]);
      expect(session.hasWritableLease, isTrue);
      expect(session.state, CanonicalRuntimeLeaseState.draining);
    },
  );

  test(
    'open failure releases only after explicit partial-open cleanup',
    () async {
      final gateway = _FakeLeaseGateway();
      final session = CanonicalWritableRuntimeSession(gateway: gateway);

      await expectLater(
        session.acquireThenOpen<Object>(
          binding: 'v1:account-a',
          openDatabase: () async => throw StateError('open failed'),
          closeAfterOpenFailure: () async {
            gateway.trace.add('closePartialDatabase');
            return true;
          },
        ),
        throwsStateError,
      );

      expect(gateway.trace, [
        'acquire:v1:account-a',
        'beginDrain',
        'closePartialDatabase',
        'release:true',
      ]);
      expect(session.hasWritableLease, isFalse);
    },
  );

  test(
    'runtime attaches only after DB open and attach failure closes first',
    () async {
      final gateway = _FakeLeaseGateway()..attachSucceeds = false;
      final session = CanonicalWritableRuntimeSession(gateway: gateway);

      await expectLater(
        session.acquireThenOpen<String>(
          binding: 'v1:account-a',
          openDatabase: () async {
            gateway.trace.add('openDatabase');
            return 'database';
          },
          closeDatabaseOnRuntimeAttachFailure: (database) async {
            gateway.trace.add('closeDatabase:$database');
            return true;
          },
        ),
        throwsStateError,
      );

      expect(gateway.trace, [
        'acquire:v1:account-a',
        'openDatabase',
        'attachRuntime',
        'beginDrain',
        'closeDatabase:database',
        'release:true',
      ]);
      expect(session.hasWritableLease, isFalse);
    },
  );

  test(
    'opaque install account binding is stable rotates and never enables work',
    () async {
      final secureStore = _MemorySecureKeyStore();
      final lease = _FakeLeaseGateway();
      final publisher = _FakeDroppedPushBindingPublisher();
      final overlayBindings = <String?>[];
      final bindings = CanonicalRuntimeBindingCoordinator(
        secureKeyStore: secureStore,
        leaseGateway: lease,
        droppedPushBindingPublisher: publisher,
        rebindPendingNotificationOverlay: (binding) async {
          overlayBindings.add(binding);
        },
        createInstallationId: () => 'installation-secret-123',
      );

      final startupA = await bindings.loadStartupBinding();
      final startupB = await bindings.loadStartupBinding();
      expect(startupA.leaseBinding, startupB.leaseBinding);
      expect(startupA.hasAccount, isFalse);
      expect(startupA.leaseBinding, startsWith('v1:'));
      expect(startupA.leaseBinding, isNot(contains('installation-secret-123')));

      await lease.acquire(startupA.leaseBinding);
      lease.trace.clear();
      final accountA = await bindings.publishAccount('raw-peer-A');
      final accountB = await bindings.publishAccount('raw-peer-B');
      expect(accountA, isNot(accountB));
      expect(accountA, isNot(contains('raw-peer-A')));
      expect(accountB, isNot(contains('raw-peer-B')));
      expect(
        await secureStore.read(canonicalRuntimeAccountBindingStorageKey),
        accountB,
      );
      expect(publisher.publications, [
        (binding: accountA, activateRecoveryWork: false),
        (binding: accountB, activateRecoveryWork: false),
      ]);

      final provisional = await bindings.retireAccount();
      expect(provisional, startsWith('v1:'));
      expect(provisional, isNot(accountB));
      expect(
        await secureStore.read(canonicalRuntimeAccountBindingStorageKey),
        isNull,
      );
      expect(publisher.publications.last, (
        binding: null,
        activateRecoveryWork: false,
      ));
      expect(overlayBindings, [null, null, accountA, accountB, null]);
      expect(lease.trace.where((entry) => entry.startsWith('rebind:')), [
        'rebind:$accountA',
        'rebind:$accountB',
        'rebind:$provisional',
      ]);
    },
  );

  test('primary authority commits before the derived overlay rebind', () async {
    final secureStore = _MemorySecureKeyStore();
    final lease = _FakeLeaseGateway();
    final publisher = _FakeDroppedPushBindingPublisher();
    final observations =
        <
          ({
            String? binding,
            bool secureCommitted,
            bool nativeCommitted,
            bool leaseCommitted,
          })
        >[];
    var observeCutovers = false;
    final bindings = CanonicalRuntimeBindingCoordinator(
      secureKeyStore: secureStore,
      leaseGateway: lease,
      droppedPushBindingPublisher: publisher,
      rebindPendingNotificationOverlay: (binding) async {
        if (!observeCutovers) return;
        observations.add((
          binding: binding,
          secureCommitted:
              await secureStore.read(
                canonicalRuntimeAccountBindingStorageKey,
              ) ==
              binding,
          nativeCommitted:
              publisher.publications.isNotEmpty &&
              publisher.publications.last.binding == binding,
          leaseCommitted: binding == null
              ? lease.binding != null
              : lease.binding == binding,
        ));
      },
      createInstallationId: () => 'installation-secret-123',
    );
    final startup = await bindings.loadStartupBinding();
    await lease.acquire(startup.leaseBinding);
    observeCutovers = true;

    final account = await bindings.publishAccount('raw-peer-A');
    final provisional = await bindings.retireAccount();

    expect(observations, [
      (
        binding: account,
        secureCommitted: true,
        nativeCommitted: true,
        leaseCommitted: true,
      ),
      (
        binding: null,
        secureCommitted: true,
        nativeCommitted: true,
        leaseCommitted: true,
      ),
    ]);
    expect(lease.binding, provisional);
  });

  test('overlay failure cannot roll back or fail primary authority', () async {
    final secureStore = _MemorySecureKeyStore();
    final lease = _FakeLeaseGateway();
    final publisher = _FakeDroppedPushBindingPublisher();
    final bindings = CanonicalRuntimeBindingCoordinator(
      secureKeyStore: secureStore,
      leaseGateway: lease,
      droppedPushBindingPublisher: publisher,
      rebindPendingNotificationOverlay: (_) async {
        throw StateError('overlay unavailable');
      },
      createInstallationId: () => 'installation-secret-123',
    );
    final startup = await bindings.loadStartupBinding();
    await lease.acquire(startup.leaseBinding);
    lease.trace.clear();

    final account = await bindings.publishAccount('raw-peer-A');

    expect(
      await secureStore.read(canonicalRuntimeAccountBindingStorageKey),
      account,
    );
    expect(publisher.publications.last.binding, account);
    expect(lease.binding, account);

    final provisional = await bindings.retireAccount();
    expect(
      await secureStore.read(canonicalRuntimeAccountBindingStorageKey),
      isNull,
    );
    expect(publisher.publications.last.binding, isNull);
    expect(lease.binding, provisional);
  });
}

class _FakeLeaseGateway implements CanonicalRuntimeLeaseGateway {
  final List<String> trace = [];
  bool active = false;
  CanonicalRuntimeLeaseState currentState = CanonicalRuntimeLeaseState.released;
  int generation = 0;
  String? binding;
  bool attachSucceeds = true;

  @override
  Future<bool> attachRuntime() async {
    trace.add('attachRuntime');
    return attachSucceeds;
  }

  @override
  Future<CanonicalRuntimeLeaseSnapshot> acquire(String value) async {
    trace.add('acquire:$value');
    if (active) throw StateError('owned');
    active = true;
    currentState = CanonicalRuntimeLeaseState.active;
    binding = value;
    generation += 1;
    return snapshot();
  }

  @override
  Future<bool> beginDrain() async {
    trace.add('beginDrain');
    if (!active) return false;
    currentState = CanonicalRuntimeLeaseState.draining;
    return true;
  }

  @override
  Future<CanonicalRuntimeLeaseSnapshot> rebind(String value) async {
    trace.add('rebind:$value');
    if (!active || currentState != CanonicalRuntimeLeaseState.active) {
      throw StateError('not active');
    }
    binding = value;
    return snapshot();
  }

  @override
  Future<bool> quiesceRuntime() async {
    trace.add('quiesceRuntime');
    return true;
  }

  @override
  Future<bool> release({required bool databaseClosed}) async {
    trace.add('release:$databaseClosed');
    if (!active ||
        currentState != CanonicalRuntimeLeaseState.draining ||
        !databaseClosed) {
      return false;
    }
    active = false;
    currentState = CanonicalRuntimeLeaseState.released;
    binding = null;
    return true;
  }

  @override
  Future<CanonicalRuntimeLeaseSnapshot> status() async => snapshot();

  CanonicalRuntimeLeaseSnapshot snapshot() => CanonicalRuntimeLeaseSnapshot(
    state: currentState,
    generation: active ? generation : null,
    binding: binding,
    role: active ? 'FOREGROUND' : null,
    maximumConcurrentWritableOwners: active ? 1 : 0,
  );
}

class _FakeDroppedPushBindingPublisher
    implements DroppedPushRecoveryBindingPublisher {
  final List<({String? binding, bool activateRecoveryWork})> publications = [];

  @override
  Future<bool> setCurrentBinding(
    String? binding, {
    required bool activateRecoveryWork,
  }) async {
    publications.add((
      binding: binding,
      activateRecoveryWork: activateRecoveryWork,
    ));
    return true;
  }
}

class _MemorySecureKeyStore implements SecureKeyStore {
  final Map<String, String> values = {};

  @override
  Future<bool> containsKey(String key) async => values.containsKey(key);

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
