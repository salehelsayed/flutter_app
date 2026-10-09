import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/app/bootstrap/application_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';

enum _FailurePhase { factory, prepare, build, launch, post }

final class _FakeHost implements ApplicationHost {
  _FakeHost(
    this.trace, {
    this.failure,
    this.expectedRoot,
    this.traceMicrotaskAfterLaunch = false,
  });

  final List<String> trace;
  final Object? failure;
  final Widget? expectedRoot;
  final bool traceMicrotaskAfterLaunch;
  Widget? launchedRoot;

  @override
  void initializeBinding() {
    trace.add('binding');
  }

  @override
  void launch(Widget rootWidget) {
    trace.add('launch');
    launchedRoot = rootWidget;
    if (expectedRoot != null) {
      expect(identical(rootWidget, expectedRoot), isTrue);
    }
    if (traceMicrotaskAfterLaunch) {
      scheduleMicrotask(() => trace.add('microtask:after-launch'));
    }
    if (failure != null) throw failure!;
  }
}

final class _CallLaunchHost extends _FakeHost
    implements IncomingCallLaunchHost {
  _CallLaunchHost(super.trace, {required this.incomingCall});

  final bool incomingCall;

  @override
  Future<void> showIncomingCallLaunchFrame() async {
    trace.add('call-frame?');
    if (incomingCall) launch(incomingCallLaunchFrame);
  }
}

final class _FakeBootstrap implements ApplicationBootstrap {
  _FakeBootstrap(this.trace, this.prepared, {this.failure});

  final List<String> trace;
  final PreparedApplication prepared;
  final Object? failure;

  @override
  Future<PreparedApplication> prepare() async {
    trace.add('prepare');
    if (failure != null) throw failure!;
    return prepared;
  }
}

final class _FakePrepared implements PreparedApplication {
  _FakePrepared(this.trace, this.root, {this.buildFailure, this.postFailure});

  final List<String> trace;
  final Widget root;
  final Object? buildFailure;
  final Object? postFailure;

  @override
  Future<Widget> buildRootWidget() async {
    trace.add('build:start');
    await Future<void>.value();
    trace.add('build:end');
    if (buildFailure != null) throw buildFailure!;
    return root;
  }

  @override
  void afterRunApp() {
    trace.add('post');
    if (postFailure != null) throw postFailure!;
  }
}

final class _RecoverableBootstrap
    implements ApplicationBootstrap, RecoverableApplicationBootstrap {
  _RecoverableBootstrap(this.prepared);
  final PreparedApplication prepared;
  final finish = Completer<void>();
  int preparations = 0;
  int retries = 0;

  @override
  Future<PreparedApplication> prepare() => throw StateError('wrong path');

  @override
  Future<PreparedApplication> prepareWithRecovery({
    required Future<void> Function() waitForRetry,
  }) async {
    preparations++;
    await waitForRetry();
    retries++;
    await finish.future;
    return prepared;
  }
}

void main() {
  testWidgets(
    'bounded startup failure exposes Retry and resumes one preparation',
    (tester) async {
      final trace = <String>[];
      const root = SizedBox(key: ValueKey('recovered-root'));
      final bootstrap = _RecoverableBootstrap(_FakePrepared(trace, root));
      final host = _FakeHost(trace);
      final operation = runApplicationBootstrap(
        bootstrapFactory: () => bootstrap,
        host: host,
      );
      await tester.pumpWidget(host.launchedRoot!);
      expect(find.text('Failed to initialize'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(bootstrap.preparations, 1);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(bootstrap.retries, 1);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      bootstrap.finish.complete();
      await operation;
      await tester.pumpWidget(host.launchedRoot!);
      expect(find.byKey(const ValueKey('recovered-root')), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(bootstrap.preparations, 1);
      expect(trace.where((event) => event == 'post'), hasLength(1));
    },
  );

  test('a call launch draws its frame before preparation starts', () async {
    // O6 (beta 2026-10-08): the native incoming-call surface cannot draw
    // until Flutter's first frame, which otherwise waits for prepare().
    final trace = <String>[];
    const root = SizedBox(key: ValueKey('root'));
    final host = _CallLaunchHost(trace, incomingCall: true);
    await runApplicationBootstrap(
      bootstrapFactory: () => _FakeBootstrap(trace, _FakePrepared(trace, root)),
      host: host,
    );
    expect(trace, [
      'binding',
      'call-frame?',
      'launch',
      'prepare',
      'build:start',
      'build:end',
      'launch',
      'post',
    ]);
    expect(identical(host.launchedRoot, root), isTrue);

    final ordinary = <String>[];
    await runApplicationBootstrap(
      bootstrapFactory: () =>
          _FakeBootstrap(ordinary, _FakePrepared(ordinary, root)),
      host: _CallLaunchHost(ordinary, incomingCall: false),
    );
    expect(ordinary.where((event) => event == 'launch'), hasLength(1));
  });

  test('intentional startup cancellation launches no completed app', () async {
    final trace = <String>[];
    final host = _FakeHost(trace);
    await runApplicationBootstrap(
      bootstrapFactory: () => _FakeBootstrap(
        trace,
        _FakePrepared(trace, const SizedBox()),
        failure: const ApplicationBootstrapCancelled(),
      ),
      host: host,
    );
    expect(host.launchedRoot, isNull);
    expect(trace, ['binding', 'prepare']);
  });

  test(
    'runs binding bootstrap creation prepare root launch and post-launch in order',
    () async {
      final trace = <String>[];
      const root = SizedBox(key: ValueKey('DTR-14-root'));
      final prepared = _FakePrepared(trace, root);
      final bootstrap = _FakeBootstrap(trace, prepared);
      final host = _FakeHost(
        trace,
        expectedRoot: root,
        traceMicrotaskAfterLaunch: true,
      );

      await runApplicationBootstrap(
        bootstrapFactory: () {
          trace.add('bootstrap:create');
          return bootstrap;
        },
        host: host,
      );

      expect(identical(host.launchedRoot, root), isTrue);
      expect(
        trace,
        orderedEquals(const [
          'binding',
          'bootstrap:create',
          'prepare',
          'build:start',
          'build:end',
          'launch',
          'post',
        ]),
        reason:
            'launch and afterRunApp must remain synchronous; awaiting either '
            'would let the launch microtask overtake post',
      );
      await Future<void>.delayed(Duration.zero);
      expect(trace.last, 'microtask:after-launch');
    },
  );

  test('propagates each phase failure without running later phases', () async {
    for (final phase in _FailurePhase.values) {
      final trace = <String>[];
      final error = StateError('DTR-14 ${phase.name} failure');
      const root = SizedBox.shrink();
      final prepared = _FakePrepared(
        trace,
        root,
        buildFailure: phase == _FailurePhase.build ? error : null,
        postFailure: phase == _FailurePhase.post ? error : null,
      );
      final bootstrap = _FakeBootstrap(
        trace,
        prepared,
        failure: phase == _FailurePhase.prepare ? error : null,
      );
      final host = _FakeHost(
        trace,
        failure: phase == _FailurePhase.launch ? error : null,
      );

      Object? caught;
      try {
        await runApplicationBootstrap(
          bootstrapFactory: () {
            trace.add('bootstrap:create');
            if (phase == _FailurePhase.factory) throw error;
            return bootstrap;
          },
          host: host,
        );
      } catch (failure) {
        caught = failure;
      }
      expect(identical(caught, error), isTrue, reason: phase.name);

      final expected = switch (phase) {
        _FailurePhase.factory => const ['binding', 'bootstrap:create'],
        _FailurePhase.prepare => const [
          'binding',
          'bootstrap:create',
          'prepare',
        ],
        _FailurePhase.build => const [
          'binding',
          'bootstrap:create',
          'prepare',
          'build:start',
          'build:end',
        ],
        _FailurePhase.launch => const [
          'binding',
          'bootstrap:create',
          'prepare',
          'build:start',
          'build:end',
          'launch',
        ],
        _FailurePhase.post => const [
          'binding',
          'bootstrap:create',
          'prepare',
          'build:start',
          'build:end',
          'launch',
          'post',
        ],
      };
      expect(trace, orderedEquals(expected), reason: phase.name);
    }
  });
}
