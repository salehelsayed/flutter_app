import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'artifact_evidence.dart';
import 'build_orchestrator.dart';
import 'checkpoint.dart';
import 'device_binding.dart';
import 'executor.dart';
import 'live_device_preparer.dart';
import 'live_device_resolver.dart';
import 'manifest.dart';
import 'planner.dart';
import 'report.dart';
import 'scheduler.dart';
import 'verdict.dart';
import 'verification.dart';

enum SimsOutputFormat { text, json, tsv }

final class SimsCliOptions {
  const SimsCliOptions({
    required this.mode,
    required this.listOnly,
    required this.format,
    required this.simultaneous,
    required this.onlyId,
    required this.family,
    required this.lane,
    required this.continueOnFailure,
    required this.fixAsYouGo,
    required this.resume,
    required this.prepareBuilds,
  });

  factory SimsCliOptions.parse(List<String> arguments) {
    var mode = SimsMode.major;
    var modeSeen = false;
    var listOnly = false;
    var format = SimsOutputFormat.text;
    var simultaneous = false;
    var continueOnFailure = false;
    var fixAsYouGo = false;
    var resume = false;
    var prepareBuilds = false;
    String? onlyId;
    String? family;
    String? lane;

    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (const <String>{'major', 'full', 'smoke'}.contains(argument)) {
        if (modeSeen) throw FormatException('Mode may be specified only once.');
        mode = SimsModeName.parse(argument);
        modeSeen = true;
        continue;
      }
      switch (argument) {
        case '--list' || '--dry-run':
          listOnly = true;
        case '--simultaneous' || '--parallel':
          simultaneous = true;
        case '--continue-on-failure':
          continueOnFailure = true;
        case '--fix-as-you-go':
          fixAsYouGo = true;
        case '--resume':
          resume = true;
        case '--prepare-builds':
          prepareBuilds = true;
        case '--format':
          format = _parseFormat(_nextValue(arguments, ++index, '--format'));
        case '--only':
          onlyId = _nextValue(arguments, ++index, '--only');
        case '--family':
          family = _nextValue(arguments, ++index, '--family');
        case '--lane':
          lane = _nextValue(arguments, ++index, '--lane');
        case '-h' || '--help':
          throw const _HelpRequested();
        default:
          if (argument.startsWith('--format=')) {
            format = _parseFormat(argument.substring('--format='.length));
          } else if (argument.startsWith('--only=')) {
            onlyId = _nonempty(argument.substring('--only='.length), '--only');
          } else if (argument.startsWith('--family=')) {
            family = _nonempty(
              argument.substring('--family='.length),
              '--family',
            );
          } else if (argument.startsWith('--lane=')) {
            lane = _nonempty(argument.substring('--lane='.length), '--lane');
          } else {
            throw FormatException('Unknown sims argument: $argument');
          }
      }
    }

    if (fixAsYouGo && continueOnFailure) {
      throw const FormatException(
        '--fix-as-you-go is fail-fast and cannot be combined with '
        '--continue-on-failure.',
      );
    }
    if (resume && (onlyId != null || family != null || lane != null)) {
      throw const FormatException(
        '--resume cannot be combined with --only, --family, or --lane.',
      );
    }

    return SimsCliOptions(
      mode: mode,
      listOnly: listOnly,
      format: format,
      simultaneous: simultaneous,
      onlyId: onlyId,
      family: family,
      lane: lane,
      continueOnFailure: continueOnFailure,
      fixAsYouGo: fixAsYouGo,
      resume: resume,
      prepareBuilds: prepareBuilds,
    );
  }

  final SimsMode mode;
  final bool listOnly;
  final SimsOutputFormat format;
  final bool simultaneous;
  final String? onlyId;
  final String? family;
  final String? lane;
  final bool continueOnFailure;
  final bool fixAsYouGo;
  final bool resume;
  final bool prepareBuilds;
}

void _validateCheckpointWorkflowOptions(SimsCliOptions options) {
  if (options.fixAsYouGo &&
      (options.mode != SimsMode.major ||
          options.family != null ||
          options.lane != null ||
          options.onlyId != null ||
          options.prepareBuilds)) {
    throw const FormatException(
      '--fix-as-you-go is restricted to the canonical unfiltered major plan.',
    );
  }
  if (options.resume &&
      (options.mode != SimsMode.major || options.prepareBuilds)) {
    throw const FormatException(
      '--resume is restricted to the canonical unfiltered major plan.',
    );
  }
}

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.isNotEmpty && arguments.first == 'devices') {
      exitCode = await _runDevicesCommand(arguments.skip(1).toList());
      return;
    }
    if (arguments.isNotEmpty &&
        simsVerificationCommands.contains(arguments.first)) {
      exitCode = await runSimsVerificationCommand(arguments);
      return;
    }
    final options = SimsCliOptions.parse(arguments);
    _validateCheckpointWorkflowOptions(options);
    final manifestPath =
        Platform.environment['SIMS_MANIFEST'] ??
        'tool/sims/critical_features.json';
    final manifest = SimsManifest.loadSync(File(manifestPath));
    if (options.onlyId != null && RegExp(r'^\d+$').hasMatch(options.onlyId!)) {
      throw const FormatException(
        '--only requires a stable capability ID, not a numeric plan position.',
      );
    }
    var plan = SimsPlanner(manifest).compile(
      mode: options.mode,
      family: options.family,
      lane: options.lane,
      onlyId: options.onlyId,
      simultaneous: options.simultaneous,
    );
    if (options.listOnly && !options.prepareBuilds) {
      _writePlan(plan, options.format);
      return;
    }

    final checkpointFile = _checkpointPath();
    SimsCheckpoint? checkpoint;
    if (checkpointFile.existsSync()) {
      checkpoint = SimsCheckpoint.loadSync(checkpointFile);
    }
    final checkpointFlowRequested =
        options.resume ||
        (options.onlyId != null && options.onlyId == checkpoint?.failedId);
    if (checkpointFlowRequested && checkpoint == null) {
      throw StateError('No sims checkpoint exists for retry/resume.');
    }
    if (checkpointFlowRequested &&
        (options.mode != SimsMode.major ||
            options.family != null ||
            options.lane != null)) {
      throw StateError(
        'Checkpoint retry/resume is restricted to the canonical unfiltered '
        'major plan.',
      );
    }
    final checkpointPlan = checkpointFlowRequested
        ? SimsPlanner(
            manifest,
          ).compile(mode: SimsMode.major, simultaneous: options.simultaneous)
        : plan;
    final checkpointPlanRows = checkpointPlan.rows;
    final checkpointNeedsFullInventory =
        checkpointFlowRequested && _hasSymbolicDeviceResources(checkpointPlan);

    SimsDevicePlanBinding? deviceBinding;
    SimsDevicePlanBinding? checkpointValidationBinding;
    SimsLiveDeviceInventory? discoveredInventory;
    if (_hasSymbolicDeviceResources(plan) || checkpointNeedsFullInventory) {
      discoveredInventory = await SimsLiveDeviceDiscovery().discover();
    }
    // Resume continuity is measured from the read-only inventory observed on
    // entry. Device preparation below is an intentional Sims-owned mutation;
    // validating its post-boot inventory against the pre-boot checkpoint would
    // reject the very preparation that makes the remaining plan executable.
    final checkpointValidationDeviceDigest = checkpointNeedsFullInventory
        ? simsLiveDeviceInventoryDigest(discoveredInventory!)
        : null;
    if (checkpointNeedsFullInventory) {
      checkpointValidationBinding = SimsDevicePlanBinding.bind(
        checkpointPlan,
        discoveredInventory!,
        processEnvironment: Platform.environment,
        blockPreparationRequired: false,
      );
    }
    if (_hasSymbolicDeviceResources(plan)) {
      final unresolvedPlan = plan;
      var inventory = discoveredInventory!;
      deviceBinding = SimsDevicePlanBinding.bind(
        unresolvedPlan,
        inventory,
        processEnvironment: Platform.environment,
        blockPreparationRequired: !options.listOnly,
      );
      if (deviceBinding.preparationTargets.isNotEmpty && !options.listOnly) {
        final preparation = await SimsLiveDevicePreparer().prepare(
          deviceBinding.preparationTargets,
        );
        if (preparation.succeeded) {
          inventory = await SimsLiveDeviceDiscovery().discover();
          discoveredInventory = inventory;
          deviceBinding = SimsDevicePlanBinding.bind(
            unresolvedPlan,
            inventory,
            processEnvironment: Platform.environment,
          );
        } else {
          stderr.writeln(
            'Live target preparation failed closed: ${preparation.detail}',
          );
        }
      }
      plan = deviceBinding.plan;
    }

    final skippedBuildProfiles =
        deviceBinding?.skippedBuildProfiles ?? const <String>{};
    final selectedBuildProfileIds = plan.rows
        .map((row) => row.buildProfileId)
        .where(
          (profileId) =>
              !skippedBuildProfiles.contains(profileId) &&
              (manifest.buildProfileById(profileId)?.buildRequired ?? false),
        )
        .toSet();
    final buildPreparation = await SimsBuildOrchestrator().prepare(
      manifest,
      plan,
      skipProfileIds: skippedBuildProfiles,
    );
    if (options.prepareBuilds) {
      plan = _buildOnlyPlan(plan);
    }

    final suiteSourceOverride = Platform.environment['SIMS_SUITE_SOURCE_DIGEST']
        ?.trim();
    final sourceDigest = computeSimsSourceClosureDigest(
      environment: <String, String>{
        ...Platform.environment,
        if (suiteSourceOverride != null && suiteSourceOverride.isNotEmpty)
          'SIMS_SOURCE_DIGEST': suiteSourceOverride,
      },
      allowTestOverride:
          Platform
              .environment['SIMS_TEST_ALLOW_SUITE_SOURCE_DIGEST_OVERRIDE'] ==
          '1',
    );
    final deviceDigest = checkpointNeedsFullInventory
        ? simsLiveDeviceInventoryDigest(discoveredInventory!)
        : deviceBinding?.inventoryDigest ?? _deviceStateDigest();
    if (checkpointFlowRequested) {
      final state = checkpoint!;
      final validation = state.validateResume(
        manifestDigest: manifest.digest,
        sourceDigest: sourceDigest,
        deviceDigest: checkpointValidationDeviceDigest ?? deviceDigest,
        buildArtifactDigests: buildPreparation.report.artifactDigests,
        relevantBuildProfileIds: options.onlyId == state.failedId
            ? selectedBuildProfileIds
            : null,
        allowRepairInputChanges: options.onlyId == state.failedId,
        currentTargetAssignments: checkpointValidationBinding?.assignments,
        currentTargetStateDigests:
            checkpointValidationBinding?.targetStateDigests,
      );
      if (!validation.isValid) {
        throw StateError(
          'Checkpoint digest changed: ${validation.reasons.join('; ')}',
        );
      }
    }

    final selection = _executionSelection(
      plan,
      options: options,
      checkpoint: checkpointFlowRequested ? checkpoint : null,
      checkpointPlanRows: checkpointPlanRows,
    );
    plan = selection.reportPlan;

    final maxParallel = _positiveEnvironmentInt('SIMS_MAX_PARALLEL', 4);
    final hostCapacity = _positiveEnvironmentInt('SIMS_HOST_CONCURRENCY', 4);
    final processExecutor = SimsProcessExecutor(
      environment: <String, String>{
        ...Platform.environment,
        ...?deviceBinding?.environment,
      },
      environmentByCapabilityId:
          deviceBinding?.environmentByCapabilityId ??
          const <String, Map<String, String>>{},
      preparedArtifacts: buildPreparation.artifacts,
      buildFailures: buildPreparation.failures,
      preflightVerdicts:
          deviceBinding?.preflightVerdicts ?? const <String, SimsVerdict>{},
    );
    final schedule =
        await SimsScheduler(
          maxParallel: maxParallel,
          hostCapacity: hostCapacity,
        ).run(
          selection.dispatchPlan,
          simultaneous: options.simultaneous,
          // Build preparation is an inventory operation: one unavailable
          // profile must not hide the independent profiles that were built,
          // reused, or blocked. Ordinary execution keeps its fail-fast
          // default unless the caller explicitly requests continuation.
          continueOnFailure: options.continueOnFailure || options.prepareBuilds,
          executor: (row) async => (await processExecutor.execute(row)).verdict,
        );

    final verdictById = <String, SimsVerdict>{
      for (final verdict in selection.priorVerdicts)
        verdict.capabilityId: verdict,
      for (final verdict in schedule.verdicts) verdict.capabilityId: verdict,
    };
    final verdicts = plan.rows
        .map((row) => verdictById[row.id])
        .whereType<SimsVerdict>()
        .toList(growable: false);
    final attemptedIds = verdicts
        .map((verdict) => verdict.capabilityId)
        .toSet();

    final cleanFullRun =
        plan.releaseEligibleCandidate &&
        !options.continueOnFailure &&
        !options.fixAsYouGo &&
        !options.resume &&
        !options.prepareBuilds;
    final assessment = SimsVerdictEvaluator().evaluate(
      plan: plan,
      attemptedIds: attemptedIds,
      verdicts: verdicts,
      cleanFullRun: cleanFullRun,
      diagnosticContinuation: options.continueOnFailure,
    );
    final report = SimsReport(
      plan: plan,
      attemptedIds: attemptedIds,
      verdicts: verdicts,
      assessment: assessment,
      buildReport: buildPreparation.report,
      cleanFullRun: cleanFullRun,
      diagnosticContinuation: options.continueOnFailure,
      generatedAt: DateTime.now().toUtc(),
      sourceDigest: sourceDigest,
      schedule: schedule,
      deviceAssignments: deviceBinding?.assignments ?? const <String, String>{},
      deviceInventoryDigest: discoveredInventory == null
          ? null
          : simsLiveDeviceInventoryDigest(discoveredInventory),
    );
    final reportPath = _reportPath();
    _writeJsonAtomically(reportPath, report.toJson());
    _writeReport(report, options.format, reportPath: reportPath.path);

    final suitePassed =
        buildPreparation.failures.isEmpty &&
        report.validationErrors.isEmpty &&
        plan.rows
            .where((row) => row.required)
            .every((row) => verdictById[row.id]?.satisfies(row) ?? false);

    if ((options.fixAsYouGo || checkpointFlowRequested) && !suitePassed) {
      _persistFailureCheckpoint(
        checkpointFile,
        plan: plan,
        verdictById: verdictById,
        manifestDigest: manifest.digest,
        sourceDigest: sourceDigest,
        deviceDigest: deviceDigest,
        targetAssignments: <String, String>{
          if (checkpointFlowRequested && checkpoint != null)
            ...checkpoint.targetAssignments,
          ...?deviceBinding?.assignments,
          if (deviceBinding == null && !checkpointNeedsFullInventory)
            ..._targetAssignments(),
        },
        targetStateDigests: <String, String>{
          if (checkpointFlowRequested && checkpoint != null)
            ...checkpoint.targetStateDigests,
          ...?deviceBinding?.targetStateDigests,
        },
        buildArtifactDigests: <String, String>{
          if (checkpointFlowRequested && checkpoint != null)
            ...checkpoint.buildArtifactDigests,
          ...buildPreparation.report.artifactDigests,
        },
        priorCheckpoint: checkpointFlowRequested ? checkpoint : null,
        checkpointPlanRows: checkpointPlanRows,
        preferredFailureId: schedule.causalFailureId,
      );
    } else if (checkpointFlowRequested && checkpoint != null && suitePassed) {
      _persistProgressCheckpoint(
        checkpointFile,
        checkpoint: checkpoint,
        plan: plan,
        verdictById: verdictById,
        manifestDigest: manifest.digest,
        sourceDigest: sourceDigest,
        deviceDigest: deviceDigest,
        buildArtifactDigests: <String, String>{
          ...checkpoint.buildArtifactDigests,
          ...buildPreparation.report.artifactDigests,
        },
        targetAssignments: <String, String>{
          ...checkpoint.targetAssignments,
          ...?deviceBinding?.assignments,
          if (deviceBinding == null && !checkpointNeedsFullInventory)
            ..._targetAssignments(),
        },
        targetStateDigests: <String, String>{
          ...checkpoint.targetStateDigests,
          ...?deviceBinding?.targetStateDigests,
        },
        checkpointPlanRows: checkpointPlanRows,
      );
    } else if (suitePassed && cleanFullRun && checkpointFile.existsSync()) {
      checkpointFile.deleteSync();
    }
    if (!suitePassed) exitCode = 1;
  } on _HelpRequested {
    stdout.writeln(_usage);
  } on FormatException catch (error) {
    stderr.writeln('Invalid sims plan: ${error.message}');
    stderr.writeln(_usage);
    exitCode = 64;
  } on StateError catch (error) {
    stderr.writeln('Unable to compile or execute sims plan: ${error.message}');
    exitCode = 65;
  } on FileSystemException catch (error) {
    stderr.writeln('Unable to read/write sims state: ${error.message}');
    exitCode = 66;
  }
}

final class _ExecutionSelection {
  const _ExecutionSelection({
    required this.reportPlan,
    required this.dispatchPlan,
    required this.priorVerdicts,
  });

  final SimsPlan reportPlan;
  final SimsPlan dispatchPlan;
  final List<SimsVerdict> priorVerdicts;
}

_ExecutionSelection _executionSelection(
  SimsPlan plan, {
  required SimsCliOptions options,
  required SimsCheckpoint? checkpoint,
  required List<CapabilitySpec> checkpointPlanRows,
}) {
  if (options.resume) {
    final state = checkpoint!;
    final failedIndex = plan.rows.indexWhere((row) => row.id == state.failedId);
    if (failedIndex < 0) {
      throw StateError(
        'Checkpoint capability is absent from the current plan: '
        '${state.failedId}',
      );
    }
    final failedRow = plan.rows[failedIndex];
    final priorVerdicts = _priorCheckpointVerdicts(checkpointPlanRows, state);
    final exactFailedVerdicts = state.passedVerdicts
        .where((verdict) => verdict.capabilityId == state.failedId)
        .toList(growable: false);
    if (!state.passedIds.contains(state.failedId) ||
        exactFailedVerdicts.length != 1 ||
        exactFailedVerdicts.single.status != SimsVerdictStatus.pass ||
        !exactFailedVerdicts.single.satisfies(failedRow)) {
      throw StateError(
        'Checkpoint failed ID lacks an exact satisfying PASS. Run --only '
        '${state.failedId} before --resume.',
      );
    }
    final passed = state.passedIds.toSet();
    final dispatchRows = plan.rows
        .skip(failedIndex + 1)
        .where((row) => !passed.contains(row.id))
        .toList(growable: false);
    final dispatchIds = dispatchRows.map((row) => row.id).toSet();
    final normalizedDispatch = <CapabilitySpec>[
      for (final row in dispatchRows)
        row.copyWith(
          dependencies: row.dependencies
              .where(dispatchIds.contains)
              .toList(growable: false),
        ),
    ];
    return _ExecutionSelection(
      reportPlan: _copyPlan(plan, rows: plan.rows, releaseEligible: false),
      dispatchPlan: _copyPlan(
        plan,
        rows: normalizedDispatch,
        releaseEligible: false,
      ),
      priorVerdicts: priorVerdicts,
    );
  }

  if (checkpoint != null && options.onlyId == checkpoint.failedId) {
    final failed = plan.rows.where((row) => row.id == checkpoint.failedId);
    if (failed.length != 1) {
      throw StateError(
        'Checkpoint retry capability is absent from the selected plan: '
        '${checkpoint.failedId}',
      );
    }
    final selectedIds = plan.selectedIds;
    final priorVerdicts =
        _priorCheckpointVerdicts(checkpointPlanRows, checkpoint)
            .where((verdict) => selectedIds.contains(verdict.capabilityId))
            .toList(growable: false);
    final priorById = <String, SimsVerdict>{
      for (final verdict in priorVerdicts) verdict.capabilityId: verdict,
    };
    for (final dependency in plan.rows.where(
      (row) => row.id != checkpoint.failedId,
    )) {
      if (!(priorById[dependency.id]?.satisfies(dependency) ?? false)) {
        throw StateError(
          'Checkpoint retry dependency lacks satisfying prior evidence: '
          '${dependency.id}',
        );
      }
    }
    return _ExecutionSelection(
      reportPlan: _copyPlan(plan, rows: plan.rows, releaseEligible: false),
      dispatchPlan: _copyPlan(
        plan,
        rows: <CapabilitySpec>[
          failed.single.copyWith(dependencies: const <String>[]),
        ],
        releaseEligible: false,
      ),
      priorVerdicts: List<SimsVerdict>.unmodifiable(priorVerdicts),
    );
  }

  return _ExecutionSelection(
    reportPlan: plan,
    dispatchPlan: plan,
    priorVerdicts: const <SimsVerdict>[],
  );
}

SimsPlan _copyPlan(
  SimsPlan source, {
  required List<CapabilitySpec> rows,
  required bool releaseEligible,
}) => SimsPlan(
  mode: source.mode,
  simultaneous: source.simultaneous,
  releaseEligibleCandidate: releaseEligible,
  manifestDigest: source.manifestDigest,
  family: source.family,
  onlyId: source.onlyId,
  lane: source.lane,
  rows: List<CapabilitySpec>.unmodifiable(rows),
);

List<SimsVerdict> _priorCheckpointVerdicts(
  List<CapabilitySpec> rows,
  SimsCheckpoint checkpoint,
) {
  final stored = <String, SimsVerdict>{
    for (final verdict in checkpoint.passedVerdicts)
      verdict.capabilityId: verdict,
  };
  if (stored.length != checkpoint.passedVerdicts.length) {
    throw StateError('Checkpoint contains duplicate prior verdict IDs.');
  }
  final result = <SimsVerdict>[];
  for (final row in rows.where(
    (row) => checkpoint.passedIds.contains(row.id),
  )) {
    var verdict = stored[row.id];
    if (verdict == null) {
      if (row.artifactRequired && row.command.first != '@prepare-build') {
        throw StateError(
          'Checkpoint lacks artifact evidence for prior row ${row.id}.',
        );
      }
      verdict = SimsVerdict.pass(
        row.id,
        assertionsAttempted: row.assertionIds.isEmpty
            ? 1
            : row.assertionIds.length,
        artifactPresent: true,
        detail: 'Preserved from a legacy validated sims checkpoint.',
      );
    }
    if (!verdict.satisfies(row)) {
      throw StateError(
        'Checkpoint prior verdict no longer satisfies ${row.id}.',
      );
    }
    final evidence = verdict.artifactEvidence;
    if (evidence != null) {
      final audit = auditSimsArtifactEvidence(
        evidence: evidence,
        expectedValidatorIds: row.artifactValidators,
      );
      if (!audit.isValid) {
        throw StateError(
          'Checkpoint prior evidence for ${row.id} is invalid: '
          '${audit.detail}',
        );
      }
    }
    result.add(verdict);
  }
  if (result.length != checkpoint.passedIds.length) {
    throw StateError('Checkpoint contains prior IDs absent from the plan.');
  }
  return List<SimsVerdict>.unmodifiable(result);
}

void _persistFailureCheckpoint(
  File checkpointFile, {
  required SimsPlan plan,
  required Map<String, SimsVerdict> verdictById,
  required String manifestDigest,
  required String sourceDigest,
  required String deviceDigest,
  required Map<String, String> targetAssignments,
  required Map<String, String> targetStateDigests,
  required Map<String, String> buildArtifactDigests,
  required SimsCheckpoint? priorCheckpoint,
  required List<CapabilitySpec> checkpointPlanRows,
  required String? preferredFailureId,
}) {
  CapabilitySpec? failed;
  if (preferredFailureId != null) {
    for (final row in plan.rows) {
      if (row.id != preferredFailureId) continue;
      final verdict = verdictById[row.id];
      if (verdict != null && !verdict.satisfies(row)) failed = row;
      break;
    }
  }
  if (failed == null) {
    for (final row in plan.rows.where((row) => row.required)) {
      final verdict = verdictById[row.id];
      if (verdict != null && !verdict.satisfies(row)) {
        failed = row;
        break;
      }
    }
  }
  if (failed == null) return;
  final failedIndex = plan.rows.indexWhere((row) => row.id == failed!.id);
  final priorVerdicts = priorCheckpoint == null
      ? const <SimsVerdict>[]
      : _priorCheckpointVerdicts(checkpointPlanRows, priorCheckpoint);
  final passed = <String>{...?priorCheckpoint?.passedIds};
  passed.removeAll(_transitiveDependentIds(checkpointPlanRows, failed.id));
  for (final row in plan.rows.take(failedIndex)) {
    if (verdictById[row.id]?.satisfies(row) ?? false) passed.add(row.id);
  }
  final passedIds = <String>[
    for (final row in checkpointPlanRows)
      if (passed.contains(row.id)) row.id,
  ];
  if (passedIds.length != passed.length) {
    throw StateError(
      'Checkpoint contains prior IDs absent from the current major plan.',
    );
  }
  final exactVerdicts = <String, SimsVerdict>{
    for (final verdict in priorVerdicts) verdict.capabilityId: verdict,
    for (final entry in verdictById.entries) entry.key: entry.value,
  };
  final passedVerdicts = <SimsVerdict>[
    for (final id in passedIds)
      exactVerdicts[id] ??
          (throw StateError(
            'Checkpoint lacks exact verdict evidence for $id.',
          )),
  ];
  final failedVerdict = verdictById[failed.id]!;
  final checkpointFailedIndex = checkpointPlanRows.indexWhere(
    (row) => row.id == failed!.id,
  );
  if (checkpointFailedIndex < 0) {
    throw StateError(
      'Failed capability is absent from the current major plan: ${failed.id}',
    );
  }
  SimsCheckpoint(
    failedId: failed.id,
    manifestDigest: manifestDigest,
    sourceDigest: sourceDigest,
    deviceDigest: deviceDigest,
    buildArtifactDigests: buildArtifactDigests,
    redactedCommand: redactCommand(failed.command),
    targetAssignments: targetAssignments,
    targetStateDigests: targetStateDigests,
    logPaths: <String>[
      'build/sims/logs/'
          '${failed.id.replaceAll(RegExp('[^A-Za-z0-9_.-]'), '_')}.log',
    ],
    failureClass: _failureClass(failedVerdict),
    passedIds: passedIds,
    passedVerdicts: passedVerdicts,
    nextId: checkpointFailedIndex + 1 < checkpointPlanRows.length
        ? checkpointPlanRows[checkpointFailedIndex + 1].id
        : null,
    createdAt: DateTime.now().toUtc(),
    finalCleanRunRequired: true,
  ).saveSync(checkpointFile);
}

Set<String> _transitiveDependentIds(List<CapabilitySpec> rows, String rootId) {
  final invalidated = <String>{rootId};
  var changed = true;
  while (changed) {
    changed = false;
    for (final row in rows) {
      if (invalidated.contains(row.id) ||
          !row.dependencies.any(invalidated.contains)) {
        continue;
      }
      invalidated.add(row.id);
      changed = true;
    }
  }
  return invalidated;
}

void _persistProgressCheckpoint(
  File checkpointFile, {
  required SimsCheckpoint checkpoint,
  required SimsPlan plan,
  required Map<String, SimsVerdict> verdictById,
  required String manifestDigest,
  required String sourceDigest,
  required String deviceDigest,
  required Map<String, String> buildArtifactDigests,
  required Map<String, String> targetAssignments,
  required Map<String, String> targetStateDigests,
  required List<CapabilitySpec> checkpointPlanRows,
}) {
  final passed = checkpoint.passedIds.toSet();
  for (final row in plan.rows) {
    if (verdictById[row.id]?.satisfies(row) ?? false) passed.add(row.id);
  }
  final orderedPassed = <String>[
    for (final row in checkpointPlanRows)
      if (passed.contains(row.id)) row.id,
  ];
  if (orderedPassed.length != passed.length) {
    throw StateError(
      'Checkpoint contains prior IDs absent from the current major plan.',
    );
  }
  final exactVerdicts = <String, SimsVerdict>{
    for (final verdict in _priorCheckpointVerdicts(
      checkpointPlanRows,
      checkpoint,
    ))
      verdict.capabilityId: verdict,
    for (final entry in verdictById.entries) entry.key: entry.value,
  };
  SimsCheckpoint(
    failedId: checkpoint.failedId,
    manifestDigest: manifestDigest,
    sourceDigest: sourceDigest,
    deviceDigest: deviceDigest,
    buildArtifactDigests: buildArtifactDigests,
    redactedCommand: checkpoint.redactedCommand,
    targetAssignments: targetAssignments,
    targetStateDigests: targetStateDigests,
    logPaths: checkpoint.logPaths,
    failureClass: checkpoint.failureClass,
    passedIds: orderedPassed,
    passedVerdicts: <SimsVerdict>[
      for (final id in orderedPassed) exactVerdicts[id]!,
    ],
    nextId: checkpoint.nextId,
    createdAt: DateTime.now().toUtc(),
    finalCleanRunRequired: true,
  ).saveSync(checkpointFile);
}

SimsFailureClass _failureClass(SimsVerdict verdict) =>
    switch (verdict.blocker) {
      SimsBlockerKind.product => SimsFailureClass.product,
      SimsBlockerKind.test => SimsFailureClass.test,
      SimsBlockerKind.harness => SimsFailureClass.harness,
      SimsBlockerKind.flake => SimsFailureClass.flake,
      _ => SimsFailureClass.environment,
    };

File _checkpointPath() {
  final configured = Platform.environment['SIMS_CHECKPOINT_PATH']?.trim();
  return File(
    configured == null || configured.isEmpty
        ? 'build/sims/latest/checkpoint.json'
        : configured,
  );
}

String _deviceStateDigest() {
  final assignments = _targetAssignments();
  return sha256.convert(utf8.encode(canonicalJson(assignments))).toString();
}

Map<String, String> _targetAssignments() {
  const names = <String>[
    'ANDROID_SERIAL',
    'RELIABILITY_SINGLE_DEVICE_ID',
    'RELIABILITY_MULTI_DEVICE_IDS',
    'IOS_NOTIFICATION_TAP_DEVICES',
    'SIMULATOR_DEVICE',
    'IOS_SECONDARY_SIMULATOR_DEVICE',
  ];
  final result = <String, String>{};
  for (final name in names) {
    final value = Platform.environment[name]?.trim();
    if (value != null && value.isNotEmpty) result[name] = value;
  }
  return result;
}

SimsPlan _buildOnlyPlan(SimsPlan plan) {
  final rows = plan.rows
      .where((row) => row.command.first == '@prepare-build')
      .toList(growable: false);
  if (rows.isEmpty) {
    throw StateError('No selected capability requires a prepared build.');
  }
  return SimsPlan(
    mode: plan.mode,
    simultaneous: plan.simultaneous,
    releaseEligibleCandidate: false,
    manifestDigest: plan.manifestDigest,
    family: plan.family,
    onlyId: plan.onlyId,
    lane: plan.lane,
    rows: rows,
  );
}

void _writePlan(SimsPlan plan, SimsOutputFormat format) {
  switch (format) {
    case SimsOutputFormat.json:
      stdout.writeln(jsonEncode(plan.toJson()));
    case SimsOutputFormat.tsv:
      stdout.writeln('id\tlane\tbuildProfile\trequired\tcommand');
      for (final row in plan.rows) {
        stdout.writeln(
          '${row.id}\t${row.lane}\t${row.buildProfileId}\t'
          '${row.required}\t${row.command.join(' ')}',
        );
      }
    case SimsOutputFormat.text:
      stdout.writeln(
        'Sims ${plan.mode.wireName} plan (${plan.rows.length} capabilities)',
      );
      for (final row in plan.rows) {
        stdout.writeln(
          '${row.id}\t${row.lane}\t${row.buildProfileId}\t'
          '${row.command.join(' ')}',
        );
      }
  }
}

void _writeReport(
  SimsReport report,
  SimsOutputFormat format, {
  required String reportPath,
}) {
  switch (format) {
    case SimsOutputFormat.json:
      stdout.writeln(jsonEncode(report.toJson()));
    case SimsOutputFormat.tsv:
      stdout.writeln('id\tstatus\tattempts\tartifactPresent');
      for (final verdict in report.verdicts) {
        stdout.writeln(
          '${verdict.capabilityId}\t${verdict.status.wireName}\t'
          '${verdict.assertionsAttempted}\t${verdict.artifactPresent}',
        );
      }
    case SimsOutputFormat.text:
      for (final verdict in report.verdicts) {
        stdout.writeln(
          '${verdict.status.wireName}\t${verdict.capabilityId}\t'
          'assertions=${verdict.assertionsAttempted}',
        );
      }
      stdout.writeln(
        'Builds: actual=${report.buildReport.actualBuilds}, '
        'requested=${report.buildReport.requestedProfiles}, '
        'cacheHits=${report.buildReport.hits}, '
        'elapsed=${_formatElapsedMs(report.buildReport.totalElapsedMs)}',
      );
      for (final entry in report.buildReport.profileElapsedMs.entries) {
        final outcome = report.buildReport.builtProfileIds.contains(entry.key)
            ? 'built'
            : report.buildReport.cacheHitProfileIds.contains(entry.key)
            ? 'cache-hit'
            : report.buildReport.failedProfileIds.contains(entry.key)
            ? 'failed'
            : 'checked';
        stdout.writeln(
          '  $outcome\t${entry.key}\t${_formatElapsedMs(entry.value)}',
        );
      }
      stdout.writeln(
        'Sims report: $reportPath '
        '(releaseEligible=${report.assessment.releaseEligible})',
      );
  }
}

String _formatElapsedMs(int milliseconds) {
  if (milliseconds < 1000) return '${milliseconds}ms';
  final seconds = milliseconds / 1000;
  if (seconds < 60) return '${seconds.toStringAsFixed(1)}s';
  final minutes = seconds ~/ 60;
  final remainder = seconds - (minutes * 60);
  return '${minutes}m${remainder.toStringAsFixed(1)}s';
}

File _reportPath() {
  final configured = Platform.environment['SIMS_REPORT_PATH']?.trim();
  return File(
    configured == null || configured.isEmpty
        ? 'build/sims/latest/report.json'
        : configured,
  );
}

bool _hasSymbolicDeviceResources(SimsPlan plan) => plan.rows.any(
  (row) => row.resources.any(
    (resource) =>
        resource.name.startsWith('device:') ||
        resource.name.startsWith('device-control:'),
  ),
);

Future<int> _runDevicesCommand(List<String> arguments) async {
  String? firstKind;
  var format = SimsOutputFormat.text;
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    switch (argument) {
      case '--first':
        firstKind = _nextValue(arguments, ++index, '--first');
      case '--format':
        format = _parseFormat(_nextValue(arguments, ++index, '--format'));
      case '-h' || '--help':
        stdout.writeln(
          'Usage: dart tool/sims/sims.dart devices '
          '[--first android-physical|android-emulator|ios-physical|ios-simulator] '
          '[--format text|json|tsv]',
        );
        return 0;
      default:
        if (argument.startsWith('--first=')) {
          firstKind = _nonempty(
            argument.substring('--first='.length),
            '--first',
          );
        } else if (argument.startsWith('--format=')) {
          format = _parseFormat(argument.substring('--format='.length));
        } else {
          throw FormatException('Unknown devices option: $argument');
        }
    }
  }

  final inventory = await SimsLiveDeviceDiscovery().discover();
  if (firstKind != null) {
    final matches = inventory.targets.where(
      (target) => switch (firstKind) {
        'android-physical' =>
          target.platform == SimsLiveDevicePlatform.android &&
              target.kind == SimsLiveDeviceKind.physical,
        'android-emulator' => target.isAndroidEmulator,
        'ios-physical' =>
          target.platform == SimsLiveDevicePlatform.ios &&
              target.kind == SimsLiveDeviceKind.physical,
        'ios-simulator' => target.isIosSimulator,
        _ => throw FormatException('Unknown target kind: $firstKind'),
      },
    );
    if (matches.isEmpty) {
      stderr.writeln(
        'No $firstKind target is available under the live device policy.',
      );
      return 1;
    }
    final target = matches.first;
    final id = target.runtimeId ?? target.launchId;
    if (id == null) {
      stderr.writeln('The selected $firstKind target has no usable ID.');
      return 1;
    }
    stdout.writeln(id);
    return 0;
  }

  switch (format) {
    case SimsOutputFormat.json:
      stdout.writeln(jsonEncode(inventory.toJson()));
    case SimsOutputFormat.tsv:
      stdout.writeln('id\tplatform\tkind\tavailability\tname');
      for (final target in inventory.targets) {
        stdout.writeln(
          '${target.runtimeId ?? target.launchId ?? ''}\t'
          '${target.platform.name}\t${target.kind.name}\t'
          '${target.availability.name}\t${target.name}',
        );
      }
    case SimsOutputFormat.text:
      for (final target in inventory.targets) {
        stdout.writeln(
          '${target.runtimeId ?? target.launchId ?? '<no-id>'}\t'
          '${target.platform.name}/${target.kind.name}\t'
          '${target.availability.name}\t${target.name}',
        );
      }
  }
  return 0;
}

void _writeJsonAtomically(File file, Map<String, Object?> json) {
  file.parent.createSync(recursive: true);
  final temporary = File('${file.path}.tmp');
  temporary.writeAsStringSync('${jsonEncode(json)}\n', flush: true);
  temporary.renameSync(file.path);
}

int _positiveEnvironmentInt(String name, int fallback) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) return fallback;
  final parsed = int.tryParse(value);
  if (parsed == null || parsed < 1 || parsed > 64) {
    throw FormatException('$name must be between 1 and 64.');
  }
  return parsed;
}

SimsOutputFormat _parseFormat(String value) => switch (value) {
  'text' => SimsOutputFormat.text,
  'json' => SimsOutputFormat.json,
  'tsv' => SimsOutputFormat.tsv,
  _ => throw FormatException('Unknown sims output format: $value'),
};

String _nextValue(List<String> arguments, int index, String option) {
  if (index >= arguments.length) {
    throw FormatException('$option requires a value.');
  }
  return _nonempty(arguments[index], option);
}

String _nonempty(String value, String option) {
  if (value.trim().isEmpty) throw FormatException('$option requires a value.');
  return value.trim();
}

final class _HelpRequested implements Exception {
  const _HelpRequested();
}

const _usage =
    'Usage: dart tool/sims/sims.dart '
    '[major|full|smoke] [--list] [--format text|json|tsv] '
    '[--simultaneous] [--continue-on-failure] [--prepare-builds] '
    '[--fix-as-you-go|--resume] [--only id] [--family name] [--lane name]\n'
    '       dart tool/sims/sims.dart verify-plan <plan.json>\n'
    '       dart tool/sims/sims.dart verify-schedule-equivalence '
    '<serial.json> <simultaneous.json>\n'
    '       dart tool/sims/sims.dart verify-report <report.json> '
    '[--require-mode major] [--require-clean-full-run]\n'
    '       dart tool/sims/sims.dart verify-analyzer-delta <before> <after>';
