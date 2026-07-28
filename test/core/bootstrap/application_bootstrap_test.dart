import 'dart:async';

import 'package:flutter/widgets.dart';
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

void main() {
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
