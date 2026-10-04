import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/debug/production_journeys/sims_runtime_protocol.dart';

import 'android_app_state_guard.dart';

Map<String, Object?> _object(Object? value) =>
    (value as Map).map((key, value) => MapEntry('$key', value));

final class ProductionJourneyPeer {
  ProductionJourneyPeer(
    this.device,
    this.invocation,
    this.output,
    this.runner, {
    required this.packageName,
  });
  final String packageName;
  final String device;
  final SimsRuntimeInvocation invocation;
  final Directory output;
  final AndroidHostProcessRunner runner;
  int sequence = 0;

  /// An iOS simulator target is a simulator UUID; Android targets are adb
  /// serials. Simulator app files live in the app's data container on this
  /// host, so they are read and written directly instead of through adb.
  bool get isIosSimulator => _simulatorId.hasMatch(device);
  static final _simulatorId = RegExp(
    r'^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$',
    caseSensitive: false,
  );
  String? _container;

  /// The simulator app's data container (its `Documents` is the app's
  /// documents directory). A reinstall gets a new container: call
  /// [forgetContainer] after installing.
  Future<String> dataContainer() async {
    if (_container case final known?) return known;
    final result = await simctl([
      'get_app_container',
      device,
      packageName,
      'data',
    ]);
    final path = '${result.stdout}'.trim();
    if (!path.startsWith('/') || !Directory(path).existsSync()) {
      throw StateError('simulator app container unavailable');
    }
    return _container = path;
  }

  void forgetContainer() => _container = null;

  Future<ProcessResult> simctl(
    List<String> args, {
    bool allowFailure = false,
  }) async {
    if (!isIosSimulator) throw StateError('simctl targets a simulator only');
    final result = await runner.run('xcrun', ['simctl', ...args]);
    if (result.exitCode != 0 && !allowFailure) {
      throw StateError('simctl operation failed: ${args.take(1).join(' ')}');
    }
    return result;
  }

  Future<ProcessResult> adb(
    List<String> args, {
    bool allowFailure = false,
  }) async {
    if (isIosSimulator) throw StateError('adb targets Android only');
    final result = await runner.run('adb', ['-s', device, ...args]);
    if (result.exitCode != 0 && !allowFailure) {
      throw StateError('ADB operation failed: ${args.take(2).join(' ')}');
    }
    return result;
  }

  Future<void> writeAppFile(String name, Map<String, Object?> value) async {
    final local = File(
      '${output.path}/${invocation.role}-${invocation.nonce}-${name.replaceAll('/', '-')}.staging',
    );
    await local.writeAsString(jsonEncode(value));
    if (isIosSimulator) {
      final target = File('${await dataContainer()}/Documents/$name');
      await target.parent.create(recursive: true);
      final staged = await local.copy('${target.path}.tmp');
      await staged.rename(target.path);
      return;
    }
    final remote = '/data/local/tmp/${invocation.nonce}.json';
    await adb(['push', local.path, remote]);
    try {
      await adb([
        'shell',
        'run-as',
        packageName,
        'mkdir',
        '-p',
        'app_flutter/production-journey',
      ]);
      await adb([
        'shell',
        'run-as',
        packageName,
        'cp',
        remote,
        'app_flutter/$name.tmp',
      ]);
      await adb([
        'shell',
        'run-as',
        packageName,
        'mv',
        'app_flutter/$name.tmp',
        'app_flutter/$name',
      ]);
    } finally {
      await adb(['shell', 'rm', '-f', remote], allowFailure: true);
    }
  }

  Future<Map<String, Object?>?> readAppFile(String name) async {
    if (isIosSimulator) {
      final file = File(
        '${await dataContainer()}/Documents/production-journey/$name',
      );
      if (!file.existsSync()) return null;
      try {
        return _object(jsonDecode(await file.readAsString()));
      } on FormatException {
        return null;
      }
    }
    final result = await adb([
      'exec-out',
      'run-as',
      packageName,
      'cat',
      'app_flutter/production-journey/$name',
    ], allowFailure: true);
    if (result.exitCode != 0) return null;
    try {
      return _object(jsonDecode('${result.stdout}'));
    } on FormatException {
      return null;
    }
  }

  Future<void> awaitReady() async {
    final ack = await waitForProductionObservation(
      'runtime acknowledgement',
      const Duration(minutes: 5),
      () => readAppFile('runtime-ack.json'),
    );
    if (!validateSimsRuntimeAck(ack, invocation).accepted) {
      throw StateError('runtime acknowledgement rejected');
    }
    await waitForProductionObservation(
      'production runtime readiness',
      const Duration(seconds: 60),
      () async {
        final ready = await command('readiness');
        return ready['productionRuntimeReady'] == true &&
                ready['foregroundPushBound'] == true
            ? ready
            : null;
      },
    );
    await waitForProductionObservation(
      'production online readiness',
      const Duration(seconds: 60),
      () async {
        final identity = await command('identity');
        return identity['online'] == true ? identity : null;
      },
    );
  }

  Future<Map<String, Object?>> command(
    String operation, [
    Map<String, Object?> args = const {},
  ]) => _command(operation, args, const Duration(seconds: 60));

  /// The production Firebase token is used only for one provider send. Keep
  /// its command result out of host evidence and remove the app-private reply
  /// after reading it.
  Future<String> claimProviderToken() async {
    try {
      final result = await _command(
        'provider_token',
        const {},
        const Duration(seconds: 60),
        persistReceipt: false,
      );
      final token = result['token'];
      if (token is! String || token.trim().isEmpty) {
        throw StateError('provider token unavailable');
      }
      return token;
    } finally {
      if (isIosSimulator) {
        final reply = File(
          '${await dataContainer()}/Documents/production-journey/command-result.json',
        );
        if (reply.existsSync()) await reply.delete();
      } else {
        await adb([
          'shell',
          'run-as',
          packageName,
          'rm',
          '-f',
          'app_flutter/production-journey/command-result.json',
        ], allowFailure: true);
      }
    }
  }

  // These retained protocol cases have an original three-minute stage bound.
  // Ordinary observation commands keep their existing one-minute bound.
  Future<Map<String, Object?>> routingProtocolCase(Map<String, Object?> args) =>
      _command('routing_protocol_case', args, const Duration(minutes: 3));

  Future<Map<String, Object?>> _command(
    String operation,
    Map<String, Object?> args,
    Duration timeout, {
    bool persistReceipt = true,
  }) async {
    final number = ++sequence;
    await writeAppFile('production-journey/command.json', {
      'invocation': invocation.toJson(),
      'sequence': number,
      'operation': operation,
      'arguments': args,
    });
    final receipt = await waitForProductionObservation(
      'command $operation',
      timeout,
      () async {
        final value = await readAppFile('command-result.json');
        if (value == null || value['sequence'] != number) return null;
        final identity = SimsRuntimeInvocation.fromJson(
          _object(value['invocation']),
        );
        if (!validateSimsRuntimeAck(
              SimsRuntimeAck.accept(identity).toJson(),
              invocation,
            ).accepted ||
            value['operation'] != operation) {
          throw StateError('stale command receipt');
        }
        return value;
      },
    );
    if (persistReceipt) {
      await File(
        '${output.path}/${invocation.role}-${invocation.nonce}-$number-$operation.json',
      ).writeAsString(jsonEncode(receipt));
    }
    if (receipt['ok'] != true) {
      throw StateError('production command failed: $operation');
    }
    return _object(receipt['result']);
  }

  Future<Map<String, Object?>> awaitMessage(
    String group,
    String message, {
    int? notificationCount,
  }) => waitForProductionObservation(
    'exact incoming message',
    const Duration(seconds: 30),
    () async {
      final value = await command('snapshot', {'groupId': group});
      final rows = (value['messages'] as List).cast<Map>();
      final present = rows.any(
        (row) => row['id'] == message && row['incoming'] == true,
      );
      return present &&
              (notificationCount == null ||
                  (value['notifications'] as List).length >= notificationCount)
          ? value
          : null;
    },
  );
}

Future<T> waitForProductionObservation<T>(
  String label,
  Duration timeout,
  Future<T?> Function() read,
) async {
  final elapsed = Stopwatch()..start();
  while (elapsed.elapsed < timeout) {
    final value = await read();
    if (elapsed.elapsed >= timeout) break;
    if (value != null) return value;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException(label, timeout);
}
