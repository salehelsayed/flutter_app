import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_app/app/bootstrap/application_bootstrap.dart';
import 'package:flutter_app/app/bootstrap/foreground_canonical_runtime_startup.dart';
import 'package:flutter_app/core/notifications/canonical_runtime_lease.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('startup-lease-test');
  late _Broker broker;
  late Duration now;
  late int opens;
  late bool databaseOpen;
  late List<Completer<void>> delays;

  ForegroundCanonicalRuntimeStartup<String> startup({
    Future<void> Function()? retry,
    Future<void> Function(Duration)? delay,
    CanonicalRuntimeLeaseGateway? gateway,
    Future<void> Function(String)? close,
  }) => ForegroundCanonicalRuntimeStartup<String>(
    gateway:
        gateway ?? MethodChannelCanonicalRuntimeLeaseGateway(channel: channel),
    closeDatabase:
        close ??
        (_) async {
          databaseOpen = false;
        },
    isDatabaseOpen: (_) => databaseOpen,
    waitForRetry: retry,
    waitBudget: const Duration(seconds: 1),
    pollInterval: const Duration(milliseconds: 250),
    elapsed: () => now,
    delay:
        delay ??
        (duration) {
          now += duration;
          final gate = Completer<void>();
          delays.add(gate);
          return gate.future;
        },
  );

  Future<String> open() async {
    opens++;
    expect(broker.owner, 'foreground');
    databaseOpen = true;
    return 'db';
  }

  setUp(() {
    broker = _Broker();
    now = Duration.zero;
    opens = 0;
    databaseOpen = false;
    delays = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, broker.call);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'typed native contention waits for owner release before one writable open',
    () async {
      final owner = startup();
      final operation = owner.open(binding: 'binding', openDatabase: open);
      await _flush();
      expect(opens, 0);
      expect(broker.owner, 'headless');
      expect(broker.calls, ['acquire']);
      broker.owner = null;
      delays.single.complete();
      expect(await operation, 'db');
      expect(opens, 1);
      expect(broker.maximumOwners, 1);
      expect(broker.calls, ['acquire', 'acquire', 'attachRuntime']);
      expect(await owner.shutdown(), isTrue);
      expect(databaseOpen, isFalse);
      expect(broker.owner, isNull);
    },
  );

  test(
    'permanent contention pauses once and Retry resumes same preparation',
    () async {
      final retry = Completer<void>();
      var prompts = 0;
      final owner = startup(
        retry: () {
          prompts++;
          return retry.future;
        },
        delay: (duration) async {
          now += duration;
        },
      );
      final operation = owner.open(binding: 'binding', openDatabase: open);
      await _flush();
      expect(prompts, 1);
      expect(opens, 0);
      expect(broker.owner, 'headless');
      final attempts = broker.calls.length;
      await _flush();
      expect(broker.calls.length, attempts);
      broker.owner = null;
      retry.complete();
      expect(await operation, 'db');
      expect(opens, 1);
      expect(prompts, 1);
    },
  );

  test(
    'unknown or denied bridge error is never retried or called contention',
    () async {
      for (final code in ['owner_denied', 'bridge_unavailable']) {
        broker.errorCode = code;
        final owner = startup();
        await expectLater(
          owner.open(binding: 'binding', openDatabase: open),
          throwsA(isA<PlatformException>().having((e) => e.code, 'code', code)),
        );
        expect(delays, isEmpty);
        expect(opens, 0);
      }
    },
  );

  test(
    'shutdown during denied wait cannot release the headless owner',
    () async {
      final owner = startup();
      final operation = owner.open(binding: 'binding', openDatabase: open);
      final assertion = expectLater(
        operation,
        throwsA(isA<ApplicationBootstrapCancelled>()),
      );
      await _flush();
      expect(await owner.shutdown(), isFalse);
      await assertion;
      expect(broker.owner, 'headless');
      expect(opens, 0);
      expect(broker.calls, ['acquire', 'status']);
      broker.owner = null;
      expect(await owner.shutdown(), isTrue);
    },
  );

  test(
    'shutdown while recovery UI waits abandons no retry timer or DB owner',
    () async {
      final retry = Completer<void>();
      var prompts = 0;
      final owner = startup(
        retry: () {
          prompts++;
          return retry.future;
        },
        delay: (duration) async {
          now += duration;
        },
      );
      final operation = owner.open(binding: 'binding', openDatabase: open);
      final assertion = expectLater(
        operation,
        throwsA(isA<ApplicationBootstrapCancelled>()),
      );
      await _flush();
      expect(prompts, 1);
      expect(await owner.shutdown(), isFalse);
      await assertion;
      final attempts = broker.calls.length;
      broker.owner = null;
      retry.complete();
      await _flush();
      expect(broker.calls.length, attempts);
      expect(opens, 0);
    },
  );

  test('late canceled grant is retired before any database open', () async {
    final grant = Completer<void>();
    broker.owner = null;
    broker.acquireGate = grant;
    final owner = startup();
    final operation = owner.open(binding: 'binding', openDatabase: open);
    final assertion = expectLater(
      operation,
      throwsA(isA<ApplicationBootstrapCancelled>()),
    );
    await _flush();
    final shutdown = owner.shutdown();
    grant.complete();
    expect(await shutdown, isTrue);
    await assertion;
    expect(opens, 0);
    expect(broker.owner, isNull);
    expect(broker.calls, ['acquire', 'beginDrain', 'release', 'status']);
  });

  test(
    'late grant after bounded window releases and pauses for explicit Retry',
    () async {
      final grant = Completer<void>();
      final retry = Completer<void>();
      broker.owner = null;
      broker.acquireGate = grant;
      var prompts = 0;
      final owner = startup(
        retry: () {
          prompts++;
          return retry.future;
        },
      );
      final operation = owner.open(binding: 'binding', openDatabase: open);
      await _flush();
      now = const Duration(seconds: 2);
      grant.complete();
      await _flush();
      expect(opens, 0);
      expect(broker.owner, isNull);
      expect(prompts, 1);
      broker.acquireGate = null;
      retry.complete();
      expect(await operation, 'db');
      expect(opens, 1);
    },
  );

  test(
    'successor starts only after canceled predecessor grant has retired',
    () async {
      final grant = Completer<void>();
      broker.owner = null;
      broker.acquireGate = grant;
      final predecessor = startup();
      final first = predecessor.open(binding: 'binding', openDatabase: open);
      final assertion = expectLater(
        first,
        throwsA(isA<ApplicationBootstrapCancelled>()),
      );
      await _flush();
      final retiring = predecessor.shutdown();
      grant.complete();
      expect(await retiring, isTrue);
      await assertion;
      broker.acquireGate = null;
      final successor = startup();
      expect(
        await successor.open(binding: 'binding', openDatabase: open),
        'db',
      );
      expect(opens, 1);
      expect(broker.maximumOwners, 1);
    },
  );

  test(
    'shutdown during DB open awaits exact handle before releasing',
    () async {
      broker.owner = null;
      final opened = Completer<String>();
      final owner = startup();
      final operation = owner.open(
        binding: 'binding',
        openDatabase: () {
          opens++;
          databaseOpen = true;
          return opened.future;
        },
      );
      final assertion = expectLater(
        operation,
        throwsA(isA<ApplicationBootstrapCancelled>()),
      );
      await _flush();
      final shutdown = owner.shutdown();
      await _flush();
      expect(broker.owner, 'foreground');
      expect(databaseOpen, isTrue);
      opened.complete('db');
      expect(await shutdown, isTrue);
      await assertion;
      expect(databaseOpen, isFalse);
      expect(broker.owner, isNull);
    },
  );

  test(
    'unknown partial open never falsely acknowledges database closure',
    () async {
      broker.owner = null;
      final owner = startup();
      await expectLater(
        owner.open(
          binding: 'binding',
          openDatabase: () async {
            throw StateError('unknown partial handle');
          },
        ),
        throwsStateError,
      );
      expect(await owner.shutdown(), isFalse);
      expect(broker.owner, 'foreground');
      expect(owner.databaseClosed, isFalse);
    },
  );

  test(
    'shutdown before startup prevents any later acquisition or open',
    () async {
      broker.owner = null;
      final owner = startup();
      expect(await owner.shutdown(), isTrue);
      expect(
        () => owner.open(binding: 'binding', openDatabase: open),
        throwsA(isA<ApplicationBootstrapCancelled>()),
      );
      expect(broker.calls, ['status']);
      expect(opens, 0);
    },
  );

  test(
    'close failure retains exact draining owner until a later proven close',
    () async {
      broker.owner = null;
      var closeAllowed = false;
      final owner = startup(
        close: (_) async {
          if (!closeAllowed) throw StateError('close unavailable');
          databaseOpen = false;
        },
      );
      await owner.open(binding: 'binding', openDatabase: open);
      expect(await owner.shutdown(), isFalse);
      expect(broker.owner, 'foreground');
      expect(broker.draining, isTrue);
      expect(databaseOpen, isTrue);
      closeAllowed = true;
      expect(await owner.shutdown(), isTrue);
      expect(databaseOpen, isFalse);
      expect(broker.owner, isNull);
    },
  );

  test('duplicate start is rejected without a second writable open', () async {
    broker.owner = null;
    final owner = startup();
    await owner.open(binding: 'binding', openDatabase: open);
    expect(
      () => owner.open(binding: 'binding', openDatabase: open),
      throwsStateError,
    );
    expect(opens, 1);
  });
}

Future<void> _flush() async {
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _Broker {
  String? owner = 'headless';
  String? errorCode;
  Completer<void>? acquireGate;
  int maximumOwners = 1;
  final calls = <String>[];
  bool draining = false;

  Map<String, Object?> get snapshot => {
    'state': owner == null
        ? 'RELEASED'
        : draining
        ? 'DRAINING'
        : 'ACTIVE',
    'generation': owner == null ? null : 1,
    'binding': owner == null ? null : 'binding',
    'role': owner == 'foreground' ? 'FOREGROUND' : 'RECOVERY',
    'maximumConcurrentWritableOwners': maximumOwners,
  };

  Future<Object?> call(MethodCall call) async {
    calls.add(call.method);
    switch (call.method) {
      case 'acquire':
        if (errorCode != null) throw PlatformException(code: errorCode!);
        if (owner != null) {
          throw PlatformException(code: 'lease_unavailable', details: snapshot);
        }
        await acquireGate?.future;
        expect(owner, isNull);
        owner = 'foreground';
        draining = false;
        return snapshot;
      case 'attachRuntime':
        return owner == 'foreground' && !draining;
      case 'beginDrain':
        expect(owner, 'foreground');
        draining = true;
        return true;
      case 'quiesceRuntime':
        return owner == 'foreground' && draining;
      case 'release':
        expect(owner, 'foreground');
        expect(draining, isTrue);
        if ((call.arguments as Map)['databaseClosed'] != true) return false;
        owner = null;
        return true;
      case 'status':
        return snapshot;
      default:
        throw StateError('unexpected method');
    }
  }
}
