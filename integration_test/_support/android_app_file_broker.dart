import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef AndroidBrokerDelay = Future<void> Function(Duration duration);
typedef AndroidBrokerLogger = void Function(String message);
typedef AndroidAdbCommandRunner =
    Future<ProcessResult> Function(
      String deviceId,
      List<String> arguments, {
      Encoding? stdoutEncoding,
    });

var _androidReadFrameSequence = 0;

Future<ProcessResult> _runAndroidAdbCommand(
  String deviceId,
  List<String> arguments, {
  Encoding? stdoutEncoding,
}) {
  return Process.run('adb', <String>[
    '-s',
    deviceId,
    ...arguments,
  ], stdoutEncoding: stdoutEncoding);
}

String _nextAndroidReadFrameNonce() {
  return '${pid}_${DateTime.now().microsecondsSinceEpoch}_'
      '${_androidReadFrameSequence++}';
}

final class AndroidAppFileTransportException implements Exception {
  const AndroidAppFileTransportException(this.message);

  final String message;

  @override
  String toString() => 'AndroidAppFileTransportException: $message';
}

final class AndroidSignalProtocolException implements Exception {
  const AndroidSignalProtocolException(this.message);

  final String message;

  @override
  String toString() => 'AndroidSignalProtocolException: $message';
}

final class AndroidAppFileReadFrameCodec {
  AndroidAppFileReadFrameCodec(this.nonce) {
    if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(nonce)) {
      throw ArgumentError.value(nonce, 'nonce', 'must be shell-marker safe');
    }
  }

  final String nonce;

  String get missingMarker => '__MKNOON_APP_FILE_${nonce}_MISSING__';

  String get presentPrefixMarker => '__MKNOON_APP_FILE_${nonce}_PRESENT__';

  String get presentSuffixMarker => '__MKNOON_APP_FILE_${nonce}_END__';

  String get errorMarker => '__MKNOON_APP_FILE_${nonce}_ERROR__';

  List<int> get missingFrame => utf8.encode(missingMarker);

  List<int> get errorFrame => utf8.encode(errorMarker);

  List<int> encodePresentFrame(List<int> bytes) {
    return <int>[
      ...utf8.encode(presentPrefixMarker),
      ...bytes,
      ...utf8.encode(presentSuffixMarker),
    ];
  }

  List<int>? decode(List<int> framedBytes) {
    if (_sameBytes(framedBytes, missingFrame)) return null;
    if (_sameBytes(framedBytes, errorFrame)) {
      throw const AndroidAppFileTransportException(
        'Android app-file read returned an explicit error frame',
      );
    }
    final prefix = utf8.encode(presentPrefixMarker);
    final suffix = utf8.encode(presentSuffixMarker);
    if (_startsWithBytes(framedBytes, prefix) &&
        _endsWithBytes(framedBytes, suffix) &&
        framedBytes.length >= prefix.length + suffix.length) {
      return framedBytes.sublist(
        prefix.length,
        framedBytes.length - suffix.length,
      );
    }
    final preview = utf8
        .decode(framedBytes.take(160).toList(), allowMalformed: true)
        .replaceAll('\n', r'\n');
    throw AndroidAppFileTransportException(
      'Malformed framed Android app-file read; stdout="$preview"',
    );
  }
}

abstract interface class AndroidAppFileTransport {
  Future<bool> isPackageInstalled(String deviceId);

  Future<void> forceStopApp(String deviceId);

  Future<String?> appProcessId(String deviceId);

  Future<String> appDataDirectory(String deviceId);

  Future<void> ensureDirectory(String deviceId, String relativeDirectory);

  Future<void> deleteFile(
    String deviceId,
    String relativeDirectory,
    String fileName,
  );

  Future<Set<String>> listFiles(String deviceId, String relativeDirectory);

  Future<List<int>?> readFile(
    String deviceId,
    String relativeDirectory,
    String fileName,
  );

  Future<void> writeFileAtomically(
    String deviceId,
    String relativeDirectory,
    String fileName,
    List<int> bytes,
  );
}

final class AdbRunAsAppFileTransport implements AndroidAppFileTransport {
  AdbRunAsAppFileTransport({
    required this.appPackage,
    this.commandTimeout = const Duration(seconds: 20),
    AndroidAdbCommandRunner? commandRunner,
    String Function()? readFrameNonceFactory,
  }) : _commandRunner = commandRunner ?? _runAndroidAdbCommand,
       _readFrameNonceFactory =
           readFrameNonceFactory ?? _nextAndroidReadFrameNonce;

  final String appPackage;
  final Duration commandTimeout;
  final AndroidAdbCommandRunner _commandRunner;
  final String Function() _readFrameNonceFactory;

  Future<ProcessResult> _adb(
    String deviceId,
    List<String> arguments, {
    Encoding? stdoutEncoding = utf8,
  }) {
    return _commandRunner(
      deviceId,
      arguments,
      stdoutEncoding: stdoutEncoding,
    ).timeout(commandTimeout);
  }

  void _requireSafeRelativeDirectory(String value) {
    if (value.isEmpty ||
        value.startsWith('/') ||
        value.split('/').contains('..') ||
        !RegExp(r'^[A-Za-z0-9_.\-/]+$').hasMatch(value)) {
      throw ArgumentError.value(value, 'relativeDirectory');
    }
  }

  void _requireSafeFileName(String value) {
    if (value.isEmpty || !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(value)) {
      throw ArgumentError.value(value, 'fileName');
    }
  }

  @override
  Future<bool> isPackageInstalled(String deviceId) async {
    final result = await _adb(deviceId, <String>[
      'shell',
      'pm',
      'path',
      appPackage,
    ]);
    return result.exitCode == 0 &&
        result.stdout.toString().trim().startsWith('package:');
  }

  @override
  Future<void> forceStopApp(String deviceId) async {
    final result = await _adb(deviceId, <String>[
      'shell',
      'am',
      'force-stop',
      appPackage,
    ]);
    if (result.exitCode != 0) {
      throw AndroidAppFileTransportException(
        'force-stop failed on $deviceId: ${result.stderr}',
      );
    }
  }

  @override
  Future<String?> appProcessId(String deviceId) async {
    final result = await _adb(deviceId, <String>['shell', 'pidof', appPackage]);
    if (result.exitCode != 0) return null;
    final value = result.stdout.toString().trim();
    return value.isEmpty ? null : value;
  }

  @override
  Future<String> appDataDirectory(String deviceId) async {
    final result = await _adb(deviceId, <String>[
      'shell',
      'run-as',
      appPackage,
      'pwd',
    ]);
    final value = result.stdout.toString().trim();
    if (result.exitCode != 0 || !value.startsWith('/')) {
      throw AndroidAppFileTransportException(
        'resolve app data directory failed on $deviceId: ${result.stderr}',
      );
    }
    return value;
  }

  @override
  Future<void> ensureDirectory(
    String deviceId,
    String relativeDirectory,
  ) async {
    _requireSafeRelativeDirectory(relativeDirectory);
    final result = await _adb(deviceId, <String>[
      'shell',
      'run-as',
      appPackage,
      'mkdir',
      '-p',
      relativeDirectory,
    ]);
    if (result.exitCode != 0) {
      throw AndroidAppFileTransportException(
        'mkdir $relativeDirectory failed on $deviceId: ${result.stderr}',
      );
    }
  }

  @override
  Future<void> deleteFile(
    String deviceId,
    String relativeDirectory,
    String fileName,
  ) async {
    _requireSafeRelativeDirectory(relativeDirectory);
    _requireSafeFileName(fileName);
    final result = await _adb(deviceId, <String>[
      'shell',
      'run-as',
      appPackage,
      'rm',
      '-f',
      '$relativeDirectory/$fileName',
    ]);
    if (result.exitCode != 0) {
      throw AndroidAppFileTransportException(
        'delete $relativeDirectory/$fileName failed on $deviceId: '
        '${result.stderr}',
      );
    }
  }

  @override
  Future<Set<String>> listFiles(
    String deviceId,
    String relativeDirectory,
  ) async {
    _requireSafeRelativeDirectory(relativeDirectory);
    final result = await _adb(deviceId, <String>[
      'shell',
      'run-as',
      appPackage,
      'ls',
      '-1',
      relativeDirectory,
    ]);
    if (result.exitCode != 0) {
      throw AndroidAppFileTransportException(
        'list $relativeDirectory failed on $deviceId: ${result.stderr}',
      );
    }
    return result.stdout
        .toString()
        .split('\n')
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toSet();
  }

  @override
  Future<List<int>?> readFile(
    String deviceId,
    String relativeDirectory,
    String fileName,
  ) async {
    _requireSafeRelativeDirectory(relativeDirectory);
    _requireSafeFileName(fileName);
    final codec = AndroidAppFileReadFrameCodec(_readFrameNonceFactory());
    final path = '$relativeDirectory/$fileName';
    final shellScript =
        'path="\$1"; '
        'if [ ! -e "\$path" ]; then '
        "printf '%s' '${codec.missingMarker}'; exit 0; "
        'fi; '
        'if [ ! -f "\$path" ]; then '
        "printf '%s' '${codec.errorMarker}'; exit 41; "
        'fi; '
        "printf '%s' '${codec.presentPrefixMarker}'; "
        'if ! cat "\$path"; then exit 42; fi; '
        "printf '%s' '${codec.presentSuffixMarker}'";
    final result = await _adb(deviceId, <String>[
      'exec-out',
      'run-as',
      appPackage,
      'sh',
      '-c',
      shellScript,
      'mknoon-read',
      path,
    ], stdoutEncoding: null);
    if (result.stdout is! List<int>) {
      throw AndroidAppFileTransportException(
        'Framed read $path on $deviceId returned non-binary stdout',
      );
    }
    if (result.exitCode != 0) {
      throw AndroidAppFileTransportException(
        'Framed read $path failed on $deviceId with '
        'exitCode=${result.exitCode}: ${result.stderr}',
      );
    }
    return codec.decode(result.stdout as List<int>);
  }

  @override
  Future<void> writeFileAtomically(
    String deviceId,
    String relativeDirectory,
    String fileName,
    List<int> bytes,
  ) async {
    _requireSafeRelativeDirectory(relativeDirectory);
    _requireSafeFileName(fileName);
    await ensureDirectory(deviceId, relativeDirectory);
    final pendingName = '.$fileName.host_pending';
    var promoted = false;
    try {
      final process = await Process.start('adb', <String>[
        '-s',
        deviceId,
        'shell',
        'run-as',
        appPackage,
        'tee',
        '$relativeDirectory/$pendingName',
      ]);
      final stdoutDone = process.stdout.drain<void>();
      final stderrDone = process.stderr.transform(utf8.decoder).join();
      process.stdin.add(bytes);
      await process.stdin.close();
      late final int exitCode;
      try {
        exitCode = await process.exitCode.timeout(commandTimeout);
      } on TimeoutException {
        process.kill();
        throw AndroidAppFileTransportException(
          'write $relativeDirectory/$fileName timed out on $deviceId',
        );
      }
      await stdoutDone;
      final stderrText = await stderrDone;
      if (exitCode != 0) {
        throw AndroidAppFileTransportException(
          'write $relativeDirectory/$fileName failed on $deviceId: $stderrText',
        );
      }
      final promote = await _adb(deviceId, <String>[
        'shell',
        'run-as',
        appPackage,
        'mv',
        '$relativeDirectory/$pendingName',
        '$relativeDirectory/$fileName',
      ]);
      if (promote.exitCode != 0) {
        throw AndroidAppFileTransportException(
          'promote $relativeDirectory/$fileName failed on $deviceId: '
          '${promote.stderr}',
        );
      }
      promoted = true;
    } finally {
      if (!promoted) {
        try {
          await deleteFile(deviceId, relativeDirectory, pendingName);
        } catch (_) {}
      }
    }
  }
}

Future<void> prepareAndroidAppForFreshLaunch({
  required AndroidAppFileTransport transport,
  required String deviceId,
  required String configDirectory,
  required String configFileName,
  Duration timeout = const Duration(seconds: 30),
  Duration pollInterval = const Duration(milliseconds: 200),
  AndroidBrokerDelay delay = Future<void>.delayed,
}) async {
  if (!await transport.isPackageInstalled(deviceId)) return;
  await transport.forceStopApp(deviceId);
  final deadline = DateTime.now().add(timeout);
  while (await transport.appProcessId(deviceId) != null) {
    if (!DateTime.now().isBefore(deadline)) {
      throw TimeoutException(
        'Timed out waiting for $deviceId app process to stop before launch',
        timeout,
      );
    }
    await delay(pollInterval);
  }
  await transport.deleteFile(deviceId, configDirectory, configFileName);
  final pendingName = '.$configFileName.host_pending';
  await transport.deleteFile(deviceId, configDirectory, pendingName);
  final staleBytes = await transport.readFile(
    deviceId,
    configDirectory,
    configFileName,
  );
  if (staleBytes != null) {
    throw StateError(
      'Stale Android runtime config remained on $deviceId after deletion',
    );
  }
  final stalePendingBytes = await transport.readFile(
    deviceId,
    configDirectory,
    pendingName,
  );
  if (stalePendingBytes != null) {
    throw StateError(
      'Stale pending Android runtime config remained on $deviceId after '
      'deletion',
    );
  }
}

Future<String> stageAndroidAppFileAfterLaunch({
  required AndroidAppFileTransport transport,
  required String deviceId,
  required String relativeDirectory,
  required String fileName,
  required Future<List<int>> Function(String processId) bytesForProcess,
  required Future<int> launchedProcessExitCode,
  Future<void> Function(String processId)? prepareForWrite,
  Duration timeout = const Duration(minutes: 15),
  Duration retryInterval = const Duration(milliseconds: 250),
  Duration stableReadDelay = const Duration(milliseconds: 40),
  AndroidBrokerDelay delay = Future<void>.delayed,
  AndroidBrokerLogger? log,
}) async {
  int? processExitCode;
  Object? processExitError;
  unawaited(
    launchedProcessExitCode.then<void>(
      (value) => processExitCode = value,
      onError: (Object error, StackTrace _) => processExitError = error,
    ),
  );
  final deadline = DateTime.now().add(timeout);
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    if (processExitError != null) {
      throw StateError(
        'Flutter process failed before Android runtime config staging: '
        '$processExitError',
      );
    }
    if (processExitCode != null) {
      throw StateError(
        'Flutter process exited with code $processExitCode before Android '
        'runtime config staging completed on $deviceId',
      );
    }
    try {
      final processId = await transport.appProcessId(deviceId);
      if (processId == null) {
        await delay(retryInterval);
        continue;
      }
      await prepareForWrite?.call(processId);
      final bytes = await bytesForProcess(processId);
      await transport.writeFileAtomically(
        deviceId,
        relativeDirectory,
        fileName,
        bytes,
      );
      final first = await transport.readFile(
        deviceId,
        relativeDirectory,
        fileName,
      );
      await delay(stableReadDelay);
      final second = await transport.readFile(
        deviceId,
        relativeDirectory,
        fileName,
      );
      if (_sameBytes(first, bytes) && _sameBytes(second, bytes)) {
        return processId;
      }
      lastError = StateError(
        'Android runtime config did not survive an exact stable read',
      );
    } catch (error) {
      lastError = error;
      log?.call('Android runtime config staging retry on $deviceId: $error');
    }
    await delay(retryInterval);
  }
  throw TimeoutException(
    'Timed out staging Android runtime config on $deviceId'
    '${lastError == null ? '' : '; last error: $lastError'}',
    timeout,
  );
}

final class AndroidAppSignalBroker {
  AndroidAppSignalBroker({
    required this.transport,
    required this.deviceIds,
    required this.hostDirectory,
    required this.remoteDirectory,
    required this.filePrefix,
    this.maximumSignalBytes = 8 * 1024 * 1024,
    this.pollInterval = const Duration(milliseconds: 500),
    this.stableReadDelay = const Duration(milliseconds: 40),
    this.delay = Future<void>.delayed,
    this.log,
  });

  final AndroidAppFileTransport transport;
  final List<String> deviceIds;
  final Directory hostDirectory;
  final String remoteDirectory;
  final String filePrefix;
  final int maximumSignalBytes;
  final Duration pollInterval;
  final Duration stableReadDelay;
  final AndroidBrokerDelay delay;
  final AndroidBrokerLogger? log;
  final Map<String, Map<String, List<int>>> _confirmedDeviceBytes =
      <String, Map<String, List<int>>>{};
  Future<void> _operationQueue = Future<void>.value();
  final Completer<void> _stopSignal = Completer<void>();
  bool _stopRequested = false;

  void stop() {
    if (_stopRequested) return;
    _stopRequested = true;
    _stopSignal.complete();
  }

  Future<void> run() async {
    while (!_stopRequested) {
      try {
        await synchronizeOnce();
      } on AndroidSignalProtocolException {
        rethrow;
      } catch (error) {
        log?.call('Android signal synchronization retry: $error');
      }
      if (_stopRequested) break;
      await _delayOrStop(pollInterval);
    }
  }

  Future<void> synchronizeOnce() {
    return _serialize<void>(_synchronizeOnceUnlocked);
  }

  /// Pulls one exact final signal from its source device into the host
  /// directory without waiting for another full multi-device broker pass.
  ///
  /// The pull is serialized with background and final synchronization so the
  /// broker never races its own pending-file promotion paths.
  Future<bool> drainSignalToHost({
    required String deviceId,
    required String name,
    Duration timeout = const Duration(minutes: 3),
    Duration retryInterval = const Duration(milliseconds: 100),
  }) async {
    if (!deviceIds.contains(deviceId)) {
      throw ArgumentError.value(deviceId, 'deviceId', 'is not brokered');
    }
    _requireFinalSignalName(name);
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
    if (retryInterval <= Duration.zero) {
      throw ArgumentError.value(
        retryInterval,
        'retryInterval',
        'must be positive',
      );
    }

    final deadline = DateTime.now().add(timeout);
    Object? lastError;
    while (!_stopRequested && DateTime.now().isBefore(deadline)) {
      final remaining = deadline.difference(DateTime.now());
      try {
        final pulled = await _serialize<bool>(
          () => _drainSignalToHostUnlocked(deviceId, name),
        ).timeout(remaining);
        if (pulled) return true;
      } on AndroidSignalProtocolException {
        rethrow;
      } on TimeoutException {
        return false;
      } catch (error) {
        lastError = error;
        log?.call('Android targeted signal drain retry for $name: $error');
      }
      if (_stopRequested) return false;
      final retryRemaining = deadline.difference(DateTime.now());
      if (retryRemaining <= Duration.zero) break;
      await _delayOrStop(
        retryInterval < retryRemaining ? retryInterval : retryRemaining,
      );
    }
    if (lastError != null) {
      log?.call(
        'Android targeted signal drain exhausted for $name: $lastError',
      );
    }
    return false;
  }

  /// Publishes one terminal host signal and atomically delivers it to exactly
  /// one target without reading it back or traversing other brokered devices.
  ///
  /// The caller must first complete its final held-alive synchronization, stop
  /// the broker, and await [run]. A prior target may uninstall immediately
  /// after delivery; this operation never revisits it while releasing later
  /// targets.
  Future<void> deliverTerminalHostSignalToDevice({
    required String deviceId,
    required String name,
    required List<int> bytes,
  }) async {
    if (!deviceIds.contains(deviceId)) {
      throw ArgumentError.value(deviceId, 'deviceId', 'is not brokered');
    }
    _requireFinalSignalName(name);
    _requireWithinLimit(name, bytes);
    if (!_stopRequested) {
      throw StateError(
        'Android signal broker must be stopped before terminal delivery',
      );
    }
    hostDirectory.createSync(recursive: true);
    await _publishHostBytes('orchestrator', name, bytes);
    await transport.writeFileAtomically(deviceId, remoteDirectory, name, bytes);
  }

  Future<void> _synchronizeOnceUnlocked() async {
    if (_stopRequested) return;
    hostDirectory.createSync(recursive: true);
    final filesByDevice = <String, Set<String>>{};
    for (final deviceId in deviceIds) {
      if (_stopRequested) return;
      await transport.ensureDirectory(deviceId, remoteDirectory);
      if (_stopRequested) return;
      final allNames = await transport.listFiles(deviceId, remoteDirectory);
      if (_stopRequested) return;
      final names = <String>{};
      final deviceCache = _confirmedDeviceBytes.putIfAbsent(
        deviceId,
        () => <String, List<int>>{},
      );
      for (final name in allNames) {
        if (!name.startsWith(filePrefix)) continue;
        if (_isTransientSignalArtifact(name)) continue;
        _requireFinalSignalName(name, location: deviceId);
        names.add(name);
      }
      deviceCache.removeWhere((name, _) => !names.contains(name));
      for (final name in names) {
        if (_stopRequested) return;
        await _pullStable(deviceId, name);
      }
      filesByDevice[deviceId] = names;
    }

    if (_stopRequested) return;
    final hostFiles = hostDirectory
        .listSync()
        .whereType<File>()
        .where((file) {
          final name = file.uri.pathSegments.last;
          return _isFinalSignalArtifact(name);
        })
        .toList(growable: false);
    for (final hostFile in hostFiles) {
      if (_stopRequested) return;
      final name = hostFile.uri.pathSegments.last;
      _requireFinalSignalName(name, location: 'host');
      final hostBytes = await hostFile.readAsBytes();
      _requireWithinLimit(name, hostBytes);
      for (final deviceId in deviceIds) {
        if (_stopRequested) return;
        final deviceNames = filesByDevice[deviceId]!;
        if (deviceNames.contains(name)) {
          final targetBytes =
              _confirmedDeviceBytes[deviceId]?[name] ??
              await _readStable(deviceId, name);
          if (targetBytes == null) continue;
          _confirmedDeviceBytes[deviceId]![name] = targetBytes;
          if (!_sameBytes(targetBytes, hostBytes)) {
            throw AndroidSignalProtocolException(
              '$name conflicts between host and $deviceId',
            );
          }
          continue;
        }
        await transport.writeFileAtomically(
          deviceId,
          remoteDirectory,
          name,
          hostBytes,
        );
        if (_stopRequested) return;
        final writtenBytes = await _readStable(deviceId, name);
        if (writtenBytes == null || !_sameBytes(writtenBytes, hostBytes)) {
          throw AndroidSignalProtocolException(
            '$name was not atomically reproduced on $deviceId',
          );
        }
        _confirmedDeviceBytes[deviceId]![name] = writtenBytes;
        deviceNames.add(name);
      }
    }
  }

  Future<void> _pullStable(String deviceId, String name) async {
    final deviceCache = _confirmedDeviceBytes[deviceId]!;
    final bytes = deviceCache[name] ?? await _readStable(deviceId, name);
    if (bytes == null) return;
    deviceCache[name] = bytes;
    await _publishHostBytes(deviceId, name, bytes);
  }

  Future<bool> _drainSignalToHostUnlocked(String deviceId, String name) async {
    if (_stopRequested) return false;
    hostDirectory.createSync(recursive: true);
    final deviceCache = _confirmedDeviceBytes.putIfAbsent(
      deviceId,
      () => <String, List<int>>{},
    );
    final bytes = deviceCache[name] ?? await _readStable(deviceId, name);
    if (bytes == null || _stopRequested) return false;
    deviceCache[name] = bytes;
    await _publishHostBytes(deviceId, name, bytes);
    return true;
  }

  Future<void> _publishHostBytes(
    String deviceId,
    String name,
    List<int> bytes,
  ) async {
    final destination = File('${hostDirectory.path}/$name');
    if (destination.existsSync()) {
      final hostBytes = await destination.readAsBytes();
      _requireWithinLimit(name, hostBytes);
      if (!_sameBytes(hostBytes, bytes)) {
        throw AndroidSignalProtocolException(
          '$name conflicts between $deviceId and the host capture',
        );
      }
      return;
    }
    final safeDeviceId = deviceId.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final pending = File('${hostDirectory.path}/.$name.$safeDeviceId.pending');
    await pending.writeAsBytes(bytes, flush: true);
    if (destination.existsSync()) {
      await pending.delete();
      final hostBytes = await destination.readAsBytes();
      if (!_sameBytes(hostBytes, bytes)) {
        throw AndroidSignalProtocolException(
          '$name raced with conflicting host bytes',
        );
      }
    } else {
      await pending.rename(destination.path);
    }
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _operationQueue = _operationQueue.then<void>((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  Future<void> _delayOrStop(Duration duration) async {
    if (_stopRequested) return;
    await Future.any<void>(<Future<void>>[delay(duration), _stopSignal.future]);
  }

  bool _isFinalSignalArtifact(String name) {
    return name.startsWith(filePrefix) && !_isTransientSignalArtifact(name);
  }

  bool _isTransientSignalArtifact(String name) {
    return name.contains('.tmp.') || name.contains('.host_pending');
  }

  void _requireFinalSignalName(String name, {String? location}) {
    if (!name.startsWith(filePrefix) ||
        _isTransientSignalArtifact(name) ||
        !_safeFileName.hasMatch(name)) {
      throw AndroidSignalProtocolException(
        'Unsafe or non-final $filePrefix signal name'
        '${location == null ? '' : ' on $location'}: $name',
      );
    }
  }

  Future<List<int>?> _readStable(String deviceId, String name) async {
    final first = await transport.readFile(deviceId, remoteDirectory, name);
    if (first == null) return null;
    _requireWithinLimit(name, first);
    await delay(stableReadDelay);
    final second = await transport.readFile(deviceId, remoteDirectory, name);
    if (second == null) return null;
    _requireWithinLimit(name, second);
    return _sameBytes(first, second) ? second : null;
  }

  void _requireWithinLimit(String name, List<int> bytes) {
    if (bytes.length > maximumSignalBytes) {
      throw AndroidSignalProtocolException(
        '$name exceeds $maximumSignalBytes bytes',
      );
    }
  }
}

final RegExp _safeFileName = RegExp(r'^[A-Za-z0-9_.-]+$');

bool _startsWithBytes(List<int> bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var index = 0; index < prefix.length; index++) {
    if (bytes[index] != prefix[index]) return false;
  }
  return true;
}

bool _endsWithBytes(List<int> bytes, List<int> suffix) {
  if (bytes.length < suffix.length) return false;
  final offset = bytes.length - suffix.length;
  for (var index = 0; index < suffix.length; index++) {
    if (bytes[offset + index] != suffix[index]) return false;
  }
  return true;
}

bool _sameBytes(List<int>? left, List<int>? right) {
  if (left == null || right == null || left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
