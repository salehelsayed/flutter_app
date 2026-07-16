import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/sims/manifest.dart';
import '../../../tool/sims/planner.dart';
import '../../../tool/sims/scheduler.dart';
import '../../../tool/sims/verdict.dart';

CapabilitySpec _task(
  String id, {
  List<ResourceLock> resources = const <ResourceLock>[
    ResourceLock(name: 'host.cpu', access: ResourceAccess.read),
  ],
  List<String> dependencies = const <String>[],
  String? allowedNaReason,
}) => CapabilitySpec(
  id: id,
  owner: 'test',
  proofBoundaryId: 'boundary.$id',
  assertionIds: <String>['assert.$id'],
  lane: 'host-dart',
  modes: const <SimsMode>{SimsMode.major},
  families: const <String>{'test'},
  required: true,
  command: <String>['task', id],
  buildProfileId: 'host.flutter_tester',
  dependencies: dependencies,
  resources: resources,
  targetCapabilities: const <String>[],
  allowedNaReason: allowedNaReason,
  artifactRequired: false,
  artifactValidator: null,
  active: true,
  declaredBuildException: false,
);

SimsPlan _plan(List<CapabilitySpec> rows, {SimsMode mode = SimsMode.major}) =>
    SimsPlan(
      mode: mode,
      simultaneous: true,
      releaseEligibleCandidate: mode == SimsMode.major,
      manifestDigest: 'manifest',
      family: null,
      onlyId: null,
      rows: rows,
    );

Future<void> _waitUntil(
  bool Function() condition, {
  String reason = 'condition was not reached',
}) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail(reason);
}

void main() {
  test(
    'missing or unknown resource metadata is exclusive and invalid for major',
    () {
      final scheduler = SimsScheduler();
      expect(
        () => scheduler.validateOrThrow(
          _plan(<CapabilitySpec>[_task('missing', resources: const [])]),
        ),
        throwsStateError,
      );
      expect(
        () => scheduler.validateOrThrow(
          _plan(<CapabilitySpec>[
            _task(
              'unknown',
              resources: const <ResourceLock>[
                ResourceLock(name: 'unknown', access: ResourceAccess.exclusive),
              ],
            ),
          ]),
        ),
        throwsStateError,
      );
      expect(
        () => scheduler.validateOrThrow(
          _plan(<CapabilitySpec>[
            _task(
              'typo',
              resources: const <ResourceLock>[
                ResourceLock(
                  name: 'devcie:android-physical',
                  access: ResourceAccess.exclusive,
                ),
              ],
            ),
          ]),
        ),
        throwsStateError,
      );
    },
  );

  test('shared target build relay and performance locks never overlap', () {
    const cases = <List<ResourceLock>>[
      <ResourceLock>[
        ResourceLock(name: 'device:pixel', access: ResourceAccess.exclusive),
      ],
      <ResourceLock>[
        ResourceLock(name: 'build:android', access: ResourceAccess.write),
      ],
      <ResourceLock>[
        ResourceLock(
          name: 'relay-mutation:staging',
          access: ResourceAccess.exclusive,
        ),
      ],
      <ResourceLock>[
        ResourceLock(
          name: 'performance.global',
          access: ResourceAccess.exclusive,
        ),
      ],
    ];

    for (final locks in cases) {
      final left = _task('left', resources: locks);
      final right = _task('right', resources: locks);
      expect(resourcesAreCompatible(left, right), isFalse, reason: '$locks');
    }
  });

  test(
    'ready rows with disjoint host and device resources overlap within cap',
    () async {
      final rows = <CapabilitySpec>[
        _task('host'),
        _task(
          'device',
          resources: const <ResourceLock>[
            ResourceLock(
              name: 'device:pixel',
              access: ResourceAccess.exclusive,
            ),
          ],
        ),
      ];
      var running = 0;
      var maxRunning = 0;
      final result = await SimsScheduler(maxParallel: 2).run(
        _plan(rows),
        simultaneous: true,
        executor: (row) async {
          running += 1;
          if (running > maxRunning) maxRunning = running;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          running -= 1;
          return SimsVerdict.pass(row.id, assertionsAttempted: 1);
        },
      );
      expect(maxRunning, 2);
      expect(result.maxObservedConcurrency, 2);
    },
  );

  test(
    'capture validators wait for artifact while independent validator overlaps',
    () async {
      final rows = <CapabilitySpec>[
        _task(
          'capture',
          resources: const <ResourceLock>[
            ResourceLock(name: 'artifact:proof', access: ResourceAccess.write),
          ],
        ),
        _task(
          'validator',
          dependencies: const <String>['capture'],
          resources: const <ResourceLock>[
            ResourceLock(name: 'artifact:proof', access: ResourceAccess.read),
          ],
        ),
        _task(
          'independent-validator',
          resources: const <ResourceLock>[
            ResourceLock(name: 'artifact:other', access: ResourceAccess.read),
          ],
        ),
      ];
      final times = <String, DateTime>{};
      await SimsScheduler(maxParallel: 3).run(
        _plan(rows),
        simultaneous: true,
        executor: (row) async {
          times['${row.id}.start'] = DateTime.now();
          await Future<void>.delayed(const Duration(milliseconds: 15));
          times['${row.id}.end'] = DateTime.now();
          return SimsVerdict.pass(row.id, assertionsAttempted: 1);
        },
      );
      expect(
        times['validator.start']!.isBefore(times['capture.end']!),
        isFalse,
      );
      expect(
        times['independent-validator.start']!.isBefore(times['capture.end']!),
        isTrue,
      );
    },
  );

  test(
    'serial and simultaneous reconcile identical IDs verdicts and failures',
    () async {
      final rows = <CapabilitySpec>[_task('a'), _task('b')];
      Future<SimsVerdict> executor(CapabilitySpec row) async => row.id == 'b'
          ? SimsVerdict.fail(row.id, detail: 'injected')
          : SimsVerdict.pass(row.id, assertionsAttempted: 1);

      final scheduler = SimsScheduler(maxParallel: 2);
      final serial = await scheduler.run(
        _plan(rows),
        simultaneous: false,
        continueOnFailure: true,
        executor: executor,
      );
      final simultaneous = await scheduler.run(
        _plan(rows),
        simultaneous: true,
        continueOnFailure: true,
        executor: executor,
      );

      expect(scheduleResultsAreEquivalent(serial, simultaneous), isTrue);
      expect(serial.attemptedIds, serial.terminalIds);
      expect(simultaneous.attemptedIds, simultaneous.terminalIds);
    },
  );

  test(
    'policy-valid target N/A satisfies dependencies and does not fail-fast',
    () async {
      final rows = <CapabilitySpec>[
        _task('unavailable', allowedNaReason: targetUnavailableNaReason),
        _task(
          'dependent-unavailable',
          dependencies: const <String>['unavailable'],
          allowedNaReason: targetUnavailableNaReason,
        ),
        _task('independent'),
      ];
      final executed = <String>[];

      final result = await SimsScheduler(maxParallel: 1).run(
        _plan(rows),
        simultaneous: false,
        executor: (row) async {
          executed.add(row.id);
          if (row.allowedNaReason == targetUnavailableNaReason) {
            return SimsVerdict.notApplicable(
              row.id,
              blocker: SimsBlockerKind.targetUnavailable,
              targetCapabilityAvailable: false,
              reason: targetUnavailableNaReason,
            );
          }
          return SimsVerdict.pass(row.id, assertionsAttempted: 1);
        },
      );

      expect(executed, <String>[
        'unavailable',
        'dependent-unavailable',
        'independent',
      ]);
      expect(
        result.verdicts.map((verdict) => verdict.status),
        <SimsVerdictStatus>[
          SimsVerdictStatus.notApplicable,
          SimsVerdictStatus.notApplicable,
          SimsVerdictStatus.pass,
        ],
      );
    },
  );

  test(
    'a completed task replenishes its slot while a slow task runs',
    () async {
      final rows = <CapabilitySpec>[
        _task('slow'),
        _task('quick'),
        _task('replacement'),
      ];
      final gates = <String, Completer<SimsVerdict>>{
        for (final row in rows) row.id: Completer<SimsVerdict>(),
      };
      final started = <String>[];

      final run = SimsScheduler(maxParallel: 2, hostCapacity: 2).run(
        _plan(rows),
        simultaneous: true,
        executor: (row) {
          started.add(row.id);
          return gates[row.id]!.future;
        },
      );
      await _waitUntil(
        () => started.length == 2,
        reason: 'the initial two scheduler slots were not filled',
      );
      expect(started, <String>['slow', 'quick']);

      gates['quick']!.complete(
        SimsVerdict.pass('quick', assertionsAttempted: 1),
      );
      await _waitUntil(
        () => started.contains('replacement'),
        reason: 'the freed slot was not replenished',
      );
      expect(gates['slow']!.isCompleted, isFalse);

      gates['replacement']!.complete(
        SimsVerdict.pass('replacement', assertionsAttempted: 1),
      );
      gates['slow']!.complete(SimsVerdict.pass('slow', assertionsAttempted: 1));
      final result = await run;
      expect(result.maxObservedConcurrency, 2);
    },
  );

  test(
    'a dependent starts after its producer while an unrelated task runs',
    () async {
      final rows = <CapabilitySpec>[
        _task('producer'),
        _task('slow'),
        _task('dependent', dependencies: const <String>['producer']),
      ];
      final gates = <String, Completer<SimsVerdict>>{
        for (final row in rows) row.id: Completer<SimsVerdict>(),
      };
      final started = <String>[];

      final run = SimsScheduler(maxParallel: 2, hostCapacity: 2).run(
        _plan(rows),
        simultaneous: true,
        executor: (row) {
          started.add(row.id);
          return gates[row.id]!.future;
        },
      );
      await _waitUntil(() => started.length == 2);
      expect(started, <String>['producer', 'slow']);

      gates['producer']!.complete(
        SimsVerdict.pass('producer', assertionsAttempted: 1),
      );
      await _waitUntil(
        () => started.contains('dependent'),
        reason: 'dependent did not use the producer\'s freed slot',
      );
      expect(gates['slow']!.isCompleted, isFalse);

      gates['dependent']!.complete(
        SimsVerdict.pass('dependent', assertionsAttempted: 1),
      );
      gates['slow']!.complete(SimsVerdict.pass('slow', assertionsAttempted: 1));
      await run;
    },
  );

  test(
    'an incompatible ready head does not hide a later compatible task',
    () async {
      const pixel = <ResourceLock>[
        ResourceLock(name: 'device:pixel', access: ResourceAccess.exclusive),
      ];
      final rows = <CapabilitySpec>[
        _task('device-slow', resources: pixel),
        _task('device-queued', resources: pixel),
        _task('host-later'),
      ];
      final gates = <String, Completer<SimsVerdict>>{
        for (final row in rows) row.id: Completer<SimsVerdict>(),
      };
      final started = <String>[];

      final run = SimsScheduler(maxParallel: 2).run(
        _plan(rows),
        simultaneous: true,
        executor: (row) {
          started.add(row.id);
          return gates[row.id]!.future;
        },
      );
      await _waitUntil(() => started.length == 2);
      expect(started, <String>['device-slow', 'host-later']);

      gates['host-later']!.complete(
        SimsVerdict.pass('host-later', assertionsAttempted: 1),
      );
      await Future<void>.delayed(Duration.zero);
      expect(started, isNot(contains('device-queued')));

      gates['device-slow']!.complete(
        SimsVerdict.pass('device-slow', assertionsAttempted: 1),
      );
      await _waitUntil(() => started.contains('device-queued'));
      gates['device-queued']!.complete(
        SimsVerdict.pass('device-queued', assertionsAttempted: 1),
      );
      await run;
    },
  );

  test('host capacity is enforced across all active tasks', () async {
    final rows = <CapabilitySpec>[
      _task('host-slow'),
      _task('host-queued'),
      _task(
        'device',
        resources: const <ResourceLock>[
          ResourceLock(name: 'device:pixel', access: ResourceAccess.exclusive),
        ],
      ),
    ];
    final gates = <String, Completer<SimsVerdict>>{
      for (final row in rows) row.id: Completer<SimsVerdict>(),
    };
    final started = <String>[];

    final run = SimsScheduler(maxParallel: 3, hostCapacity: 1).run(
      _plan(rows),
      simultaneous: true,
      executor: (row) {
        started.add(row.id);
        return gates[row.id]!.future;
      },
    );
    await _waitUntil(() => started.length == 2);
    expect(started, <String>['host-slow', 'device']);

    gates['device']!.complete(
      SimsVerdict.pass('device', assertionsAttempted: 1),
    );
    await Future<void>.delayed(Duration.zero);
    expect(started, isNot(contains('host-queued')));

    gates['host-slow']!.complete(
      SimsVerdict.pass('host-slow', assertionsAttempted: 1),
    );
    await _waitUntil(() => started.contains('host-queued'));
    gates['host-queued']!.complete(
      SimsVerdict.pass('host-queued', assertionsAttempted: 1),
    );
    final result = await run;
    expect(result.maxObservedConcurrency, 2);
  });

  test(
    'fail-fast drains active work and traces undispatched rows afterwards',
    () async {
      final rows = <CapabilitySpec>[
        _task('failing'),
        _task('slow'),
        _task('never-started'),
      ];
      final gates = <String, Completer<SimsVerdict>>{
        'failing': Completer<SimsVerdict>(),
        'slow': Completer<SimsVerdict>(),
      };
      final started = <String>[];

      final run = SimsScheduler(maxParallel: 2).run(
        _plan(rows),
        simultaneous: true,
        executor: (row) {
          started.add(row.id);
          return gates[row.id]!.future;
        },
      );
      await _waitUntil(() => started.length == 2);
      gates['failing']!.complete(
        SimsVerdict.fail('failing', detail: 'injected failure'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(started, isNot(contains('never-started')));

      gates['slow']!.complete(SimsVerdict.pass('slow', assertionsAttempted: 1));
      final result = await run;
      expect(started, <String>['failing', 'slow']);
      expect(
        result.verdicts.singleWhere(
          (item) => item.capabilityId == 'never-started',
        ),
        isA<SimsVerdict>()
            .having(
              (verdict) => verdict.status,
              'status',
              SimsVerdictStatus.blocked,
            )
            .having(
              (verdict) => verdict.detail,
              'detail',
              'Fail-fast stopped new work after failing ended FAIL (product) '
                  'without satisfying its gate.',
            ),
      );
      final slowTrace = result.traces.singleWhere(
        (item) => item.capabilityId == 'slow',
      );
      final syntheticTrace = result.traces.singleWhere(
        (item) => item.capabilityId == 'never-started',
      );
      expect(syntheticTrace.startedAt.isBefore(slowTrace.endedAt), isFalse);
    },
  );

  test('fail-fast detail identifies a credential-blocked causal row', () async {
    final result = await SimsScheduler(maxParallel: 1).run(
      _plan(<CapabilitySpec>[_task('credential-gate'), _task('not-started')]),
      simultaneous: false,
      executor: (row) async => SimsVerdict.blocked(
        row.id,
        blocker: SimsBlockerKind.credentials,
        detail: 'credentials unavailable',
      ),
    );

    expect(result.causalFailureId, 'credential-gate');
    expect(
      result.verdicts
          .singleWhere((verdict) => verdict.capabilityId == 'not-started')
          .detail,
      'Fail-fast stopped new work after credential-gate ended BLOCKED '
      '(credentials) without satisfying its gate.',
    );
  });

  test(
    'causal failure ID ignores an earlier plan-order synthetic blocker',
    () async {
      const shared = <ResourceLock>[
        ResourceLock(name: 'artifact:shared', access: ResourceAccess.write),
      ];
      final rows = <CapabilitySpec>[
        _task('slow', resources: shared),
        _task('synthetic-earlier', resources: shared),
        _task('causal-later'),
      ];
      final slow = Completer<SimsVerdict>();
      final causal = Completer<SimsVerdict>();
      final started = <String>[];

      final run = SimsScheduler(maxParallel: 2, hostCapacity: 2).run(
        _plan(rows),
        simultaneous: true,
        executor: (row) {
          started.add(row.id);
          return switch (row.id) {
            'slow' => slow.future,
            'causal-later' => causal.future,
            _ => throw StateError('synthetic row was dispatched'),
          };
        },
      );
      await _waitUntil(() => started.length == 2);
      expect(started, <String>['slow', 'causal-later']);

      causal.complete(
        SimsVerdict.fail('causal-later', detail: 'causal failure'),
      );
      await Future<void>.delayed(Duration.zero);
      slow.complete(SimsVerdict.pass('slow', assertionsAttempted: 1));

      final result = await run;
      expect(result.causalFailureId, 'causal-later');
      expect(
        result.verdicts
            .singleWhere(
              (verdict) => verdict.capabilityId == 'synthetic-earlier',
            )
            .blocker,
        SimsBlockerKind.dependency,
      );
    },
  );

  test('continue-on-failure blocks the full dependency closure only', () async {
    final rows = <CapabilitySpec>[
      _task('root'),
      _task('child', dependencies: const <String>['root']),
      _task('grandchild', dependencies: const <String>['child']),
      _task('independent'),
    ];
    final executed = <String>[];

    final result = await SimsScheduler(maxParallel: 1).run(
      _plan(rows),
      simultaneous: false,
      continueOnFailure: true,
      executor: (row) async {
        executed.add(row.id);
        return row.id == 'root'
            ? SimsVerdict.fail(row.id, detail: 'injected failure')
            : SimsVerdict.pass(row.id, assertionsAttempted: 1);
      },
    );

    expect(executed, <String>['root', 'independent']);
    expect(result.verdicts.map((item) => item.status), <SimsVerdictStatus>[
      SimsVerdictStatus.fail,
      SimsVerdictStatus.blocked,
      SimsVerdictStatus.blocked,
      SimsVerdictStatus.pass,
    ]);
    expect(result.maxObservedConcurrency, 1);
  });

  test(
    'dependency-blocked traces are emitted after unrelated active work drains',
    () async {
      const pixel = <ResourceLock>[
        ResourceLock(name: 'device:pixel', access: ResourceAccess.exclusive),
      ];
      final rows = <CapabilitySpec>[
        _task('root'),
        _task('slow-device', resources: pixel),
        _task(
          'blocked-device',
          resources: pixel,
          dependencies: const <String>['root'],
        ),
      ];
      final gates = <String, Completer<SimsVerdict>>{
        'root': Completer<SimsVerdict>(),
        'slow-device': Completer<SimsVerdict>(),
      };
      final started = <String>[];

      final run = SimsScheduler(maxParallel: 2).run(
        _plan(rows),
        simultaneous: true,
        continueOnFailure: true,
        executor: (row) {
          started.add(row.id);
          return gates[row.id]!.future;
        },
      );
      await _waitUntil(() => started.length == 2);
      gates['root']!.complete(
        SimsVerdict.fail('root', detail: 'injected failure'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(started, isNot(contains('blocked-device')));

      gates['slow-device']!.complete(
        SimsVerdict.pass('slow-device', assertionsAttempted: 1),
      );
      final result = await run;
      final slowTrace = result.traces.singleWhere(
        (item) => item.capabilityId == 'slow-device',
      );
      final blockedTrace = result.traces.singleWhere(
        (item) => item.capabilityId == 'blocked-device',
      );
      expect(blockedTrace.startedAt.isBefore(slowTrace.endedAt), isFalse);
    },
  );

  test(
    'verdicts and traces remain in plan order after out-of-order completion',
    () async {
      final rows = <CapabilitySpec>[
        _task('first'),
        _task('second'),
        _task('third'),
      ];
      final gates = <String, Completer<SimsVerdict>>{
        for (final row in rows) row.id: Completer<SimsVerdict>(),
      };
      final started = <String>[];

      final run = SimsScheduler(maxParallel: 3, hostCapacity: 3).run(
        _plan(rows),
        simultaneous: true,
        executor: (row) {
          started.add(row.id);
          return gates[row.id]!.future;
        },
      );
      await _waitUntil(() => started.length == 3);
      gates['third']!.complete(
        SimsVerdict.pass('third', assertionsAttempted: 1),
      );
      gates['first']!.complete(
        SimsVerdict.pass('first', assertionsAttempted: 1),
      );
      gates['second']!.complete(
        SimsVerdict.pass('second', assertionsAttempted: 1),
      );

      final result = await run;
      expect(result.verdicts.map((item) => item.capabilityId), <String>[
        'first',
        'second',
        'third',
      ]);
      expect(result.traces.map((item) => item.capabilityId), <String>[
        'first',
        'second',
        'third',
      ]);
    },
  );
}
