import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/notifications/canonical_recovery_runtime.dart';
import 'package:flutter_app/core/notifications/canonical_runtime_lease.dart';

final class HeadlessCanonicalRecoveryInvocation {
  const HeadlessCanonicalRecoveryInvocation({
    required this.reason,
    required this.nativeReason,
    required this.nonce,
    required this.binding,
    required this.generation,
  });

  final CanonicalRecoveryReason reason;
  final String nativeReason;
  final String nonce;
  final String binding;
  final int? generation;

  factory HeadlessCanonicalRecoveryInvocation.parse(List<String> arguments) {
    if (arguments.length != 4) {
      throw const FormatException(
        'headless recovery requires reason, nonce, binding, and generation',
      );
    }
    final nativeReason = arguments[0];
    final reason = switch (nativeReason) {
      'deleted_batch' => CanonicalRecoveryReason.deletedBatch,
      'fixed_wake' => CanonicalRecoveryReason.fixedWake,
      'periodic_sweep' => CanonicalRecoveryReason.periodicSweep,
      _ => throw FormatException('unsupported recovery reason: $nativeReason'),
    };
    final nonce = arguments[1].trim();
    final binding = arguments[2].trim();
    if (nonce.isEmpty || binding.isEmpty) {
      throw const FormatException(
        'recovery nonce and binding must not be blank',
      );
    }
    final rawGeneration = arguments[3].trim();
    final generation = rawGeneration.isEmpty
        ? null
        : int.tryParse(rawGeneration);
    if (rawGeneration.isNotEmpty && (generation == null || generation <= 0)) {
      throw const FormatException('recovery generation must be positive');
    }
    if ((reason != CanonicalRecoveryReason.periodicSweep &&
            generation == null) ||
        (reason == CanonicalRecoveryReason.periodicSweep &&
            generation != null)) {
      throw const FormatException(
        'recovery reason and generation do not agree',
      );
    }
    return HeadlessCanonicalRecoveryInvocation(
      reason: reason,
      nativeReason: nativeReason,
      nonce: nonce,
      binding: binding,
      generation: generation,
    );
  }

  Map<String, Object?> identityPayload() => <String, Object?>{
    'reason': nativeReason,
    'nonce': nonce,
    'binding': binding,
    'generation': generation,
  };
}

final class HeadlessCanonicalRecoveryCleanup {
  const HeadlessCanonicalRecoveryCleanup({
    required this.databaseClosed,
    required this.leaseReleased,
  });

  final bool databaseClosed;
  final bool leaseReleased;
}

final class HeadlessCanonicalRecoveryRunReport {
  const HeadlessCanonicalRecoveryRunReport({
    required this.result,
    required this.databaseClosed,
    required this.leaseReleased,
  });

  final CanonicalRecoveryResult result;
  final bool databaseClosed;
  final bool leaseReleased;
}

typedef RunHeadlessCanonicalRecovery =
    Future<HeadlessCanonicalRecoveryRunReport> Function({
      required HeadlessCanonicalRecoveryInvocation invocation,
      required bool Function() isStopRequested,
    });

typedef LoadHeadlessCanonicalLeaseReleased = Future<bool> Function();

abstract interface class HeadlessCanonicalRecoveryResultChannel {
  void registerCancelHandler(void Function() onCancel);

  Future<void> send({
    required String method,
    required Map<String, Object?> payload,
  });

  void dispose();
}

final class MethodChannelHeadlessCanonicalRecoveryResultChannel
    implements HeadlessCanonicalRecoveryResultChannel {
  MethodChannelHeadlessCanonicalRecoveryResultChannel({
    MethodChannel channel = const MethodChannel(
      'mknoon/headless_canonical_recovery',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  void registerCancelHandler(void Function() onCancel) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'cancel') {
        throw MissingPluginException(
          'Unsupported headless recovery method: ${call.method}',
        );
      }
      onCancel();
      return true;
    });
  }

  @override
  Future<void> send({
    required String method,
    required Map<String, Object?> payload,
  }) => _channel.invokeMethod<void>(method, payload);

  @override
  void dispose() => _channel.setMethodCallHandler(null);
}

/// Dedicated non-UI engine entrypoint body. Native owns the hard timeout and
/// accepts a completion only when the echoed invocation identity matches.
Future<void> runAndroidHeadlessCanonicalRecovery(
  List<String> arguments, {
  required RunHeadlessCanonicalRecovery runRecovery,
  required Future<HeadlessCanonicalRecoveryCleanup> Function()
  emergencyShutdown,
  HeadlessCanonicalRecoveryResultChannel? resultChannel,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final invocation = HeadlessCanonicalRecoveryInvocation.parse(arguments);
  final channel =
      resultChannel ?? MethodChannelHeadlessCanonicalRecoveryResultChannel();
  var stopRequested = false;
  channel.registerCancelHandler(() => stopRequested = true);
  var method = 'complete';
  late HeadlessCanonicalRecoveryRunReport report;
  try {
    report = await runRecovery(
      invocation: invocation,
      isStopRequested: () => stopRequested,
    );
  } catch (error) {
    method = 'failed';
    HeadlessCanonicalRecoveryCleanup cleanup;
    try {
      cleanup = await emergencyShutdown();
    } catch (_) {
      cleanup = const HeadlessCanonicalRecoveryCleanup(
        databaseClosed: false,
        leaseReleased: false,
      );
    }
    report = HeadlessCanonicalRecoveryRunReport(
      result: CanonicalRecoveryResult(
        disposition: CanonicalRecoveryDisposition.retry,
        generation: invocation.generation,
        failureReason: 'headless_entrypoint_failed:${error.runtimeType}',
      ),
      databaseClosed: cleanup.databaseClosed,
      leaseReleased: cleanup.leaseReleased,
    );
  }

  try {
    await channel.send(
      method: method,
      payload: <String, Object?>{
        ...invocation.identityPayload(),
        'disposition': report.result.disposition.name,
        'databaseClosed': report.databaseClosed,
        'leaseReleased': report.leaseReleased,
        'failureReason': report.result.failureReason,
      },
    );
  } finally {
    channel.dispose();
  }
}

/// AOT-visible safety boundary while the non-UI production dependency graph is
/// still being extracted. It never opens SQLCipher, acquires a lease, drains,
/// acknowledges, or claims success. Production binding publication keeps work
/// disabled; an accidentally forced request exits as a truthful retry instead
/// of timing out with an ownerless retained engine.
Future<HeadlessCanonicalRecoveryRunReport>
runUnavailableHeadlessCanonicalRecovery({
  required HeadlessCanonicalRecoveryInvocation invocation,
  required bool Function() isStopRequested,
  LoadHeadlessCanonicalLeaseReleased? loadLeaseReleased,
}) async {
  final leaseReleased = await _loadLeaseReleasedFailClosed(
    loadLeaseReleased ?? _platformLeaseReleased,
  );
  return HeadlessCanonicalRecoveryRunReport(
    result: CanonicalRecoveryResult(
      disposition: CanonicalRecoveryDisposition.retry,
      generation: invocation.generation,
      failureReason: 'headless_composition_unavailable',
    ),
    databaseClosed: true,
    leaseReleased: leaseReleased,
  );
}

Future<HeadlessCanonicalRecoveryCleanup>
cleanupUnavailableHeadlessCanonicalRecovery({
  LoadHeadlessCanonicalLeaseReleased? loadLeaseReleased,
}) async => HeadlessCanonicalRecoveryCleanup(
  databaseClosed: true,
  leaseReleased: await _loadLeaseReleasedFailClosed(
    loadLeaseReleased ?? _platformLeaseReleased,
  ),
);

Future<bool> _loadLeaseReleasedFailClosed(
  LoadHeadlessCanonicalLeaseReleased loadLeaseReleased,
) async {
  try {
    return await loadLeaseReleased();
  } catch (_) {
    return false;
  }
}

Future<bool> _platformLeaseReleased() async =>
    (await MethodChannelCanonicalRuntimeLeaseGateway().status()).state ==
    CanonicalRuntimeLeaseState.released;
