import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const String productionAudioCallFixtureGoToolchain = 'go1.25.0';
const String _fixtureProcessMode =
    'MKNOON_PRODUCTION_AUDIO_CALL_DEVICE_FIXTURE_PROCESS';
const String _fixtureHostEnvironment =
    'MKNOON_PRODUCTION_AUDIO_CALL_FIXTURE_HOST_IP';
const String _fixtureReadyPrefix =
    'MKNOON_PRODUCTION_AUDIO_CALL_FIXTURE_READY=';
const String _fixtureSchema = 'mknoon.plan399.production-audio-call-fixture.v1';
const String _oracleCredentialFileEnvironment =
    'CALL_AUDIO_ORACLE_CREDENTIALS_FILE';
const String _oracleResultFileEnvironment = 'CALL_AUDIO_ORACLE_RESULT_FILE';
const String _fixtureStopExecutableEnvironment =
    'PLAN399_FIXTURE_STOP_EXECUTABLE';
const String _fixtureHostOverrideEnvironment = 'PLAN399_FIXTURE_HOST_IP';
const String _oracleResultSchema = 'mknoon.call_audio_oracle.result.v1';
const String _coturnImage = 'coturn/coturn:4.17.2-r0';
const String _coturnDigest =
    'sha256:aa68aab64a3b929d57fc2924c98ea447bf996cf8dade2508e7b71eaf23f1f14e';
const String _coturnVersion = '4.17.2-r0';
const String _pionVersion = 'v4.2.19';

final class ProductionAudioCallOracleDirectionResult {
  const ProductionAudioCallOracleDirectionResult({
    required this.codecValid,
    required this.payloadCountExact,
    required this.payloadOrderExact,
    required this.payloadHashExact,
  });

  final bool codecValid;
  final bool payloadCountExact;
  final bool payloadOrderExact;
  final bool payloadHashExact;

  bool get passed =>
      codecValid && payloadCountExact && payloadOrderExact && payloadHashExact;

  Map<String, Object?> toSanitizedJson() => <String, Object?>{
    'codec_valid': codecValid,
    'payload_count_exact': payloadCountExact,
    'payload_order_exact': payloadOrderExact,
    'payload_hash_exact': payloadHashExact,
  };
}

final class ProductionAudioCallOracleRouteResult {
  const ProductionAudioCallOracleRouteResult({
    required this.relaySelected,
    required this.transportMatch,
  });

  final bool relaySelected;
  final bool transportMatch;

  bool get passed => relaySelected && transportMatch;

  Map<String, Object?> toSanitizedJson() => <String, Object?>{
    'relay_selected': relaySelected,
    'transport_match': transportMatch,
  };
}

/// Strict, secret-free output from the host-only known-Opus oracle.
final class ProductionAudioCallOracleResult {
  const ProductionAudioCallOracleResult._({
    required this.version,
    required this.pionVersion,
    required this.fixtureSha256,
    required this.turnAuthoritySha256,
    required this.fixtureInstanceSha256,
    required this.coturnImage,
    required this.coturnDigest,
    required this.expectedTransport,
    required this.aToB,
    required this.bToA,
    required this.peerARoute,
    required this.peerBRoute,
  });

  final int version;
  final String pionVersion;
  final String fixtureSha256;
  final String turnAuthoritySha256;
  final String fixtureInstanceSha256;
  final String coturnImage;
  final String coturnDigest;
  final String expectedTransport;
  final ProductionAudioCallOracleDirectionResult aToB;
  final ProductionAudioCallOracleDirectionResult bToA;
  final ProductionAudioCallOracleRouteResult peerARoute;
  final ProductionAudioCallOracleRouteResult peerBRoute;

  Map<String, Object?> toSanitizedJson() => <String, Object?>{
    'schema': _oracleResultSchema,
    'version': version,
    'passed': true,
    'pion_version': pionVersion,
    'fixture_sha256': fixtureSha256,
    'turn_authority_sha256': turnAuthoritySha256,
    'fixture_instance_sha256': fixtureInstanceSha256,
    'coturn': <String, Object?>{'image': coturnImage, 'digest': coturnDigest},
    'expected_transport': expectedTransport,
    'a_to_b': aToB.toSanitizedJson(),
    'b_to_a': bToA.toSanitizedJson(),
    'peer_a_route': peerARoute.toSanitizedJson(),
    'peer_b_route': peerBRoute.toSanitizedJson(),
    'cleanup_complete': true,
  };
}

final class _ProductionAudioCallFixtureReadiness {
  const _ProductionAudioCallFixtureReadiness({
    required this.multiaddr,
    required this.relayHost,
    required this.relayPort,
    required this.probeUrl,
    required this.fixtureIdentitySha256,
    required this.relayVersion,
    required this.relayBinarySha256,
    required this.turnHost,
    required this.turnPort,
    required this.turnTransport,
    required this.turnUrl,
    required this.coturnImage,
    required this.coturnDigest,
    required this.coturnVersion,
    required this.coturnLockSha256,
    required this.coturnContainerIdentitySha256,
    required this.oracleCredentialsFile,
    required this.oracleResultFile,
  });

  final String multiaddr;
  final String relayHost;
  final int relayPort;
  final String probeUrl;
  final String fixtureIdentitySha256;
  final String relayVersion;
  final String relayBinarySha256;
  final String turnHost;
  final int turnPort;
  final String turnTransport;
  final String turnUrl;
  final String coturnImage;
  final String coturnDigest;
  final String coturnVersion;
  final String coturnLockSha256;
  final String coturnContainerIdentitySha256;
  final String oracleCredentialsFile;
  final String oracleResultFile;
}

/// Owns one disposable production relay plus one digest-pinned coturn.
///
/// TURN authority material never enters this object. The two short-lived
/// oracle credentials remain in a private Go-owned file and are passed to the
/// oracle child by path only.
final class ProductionAudioCallLocalFixtureLease {
  ProductionAudioCallLocalFixtureLease._({
    required Process process,
    required _ProductionAudioCallFixtureReadiness readiness,
    required Map<String, String> childEnvironment,
    required String? stopExecutable,
    required StreamSubscription<String> stdoutSubscription,
    required StreamSubscription<String> stderrSubscription,
  }) : _process = process,
       _readiness = readiness,
       _childEnvironment = childEnvironment,
       _stopExecutable = stopExecutable,
       _stdoutSubscription = stdoutSubscription,
       _stderrSubscription = stderrSubscription;

  static Future<ProductionAudioCallLocalFixtureLease> start({
    required String goExecutable,
    required String hostIp,
    required Map<String, String> environment,
  }) async {
    if (!_isPrivateIpv4(hostIp)) {
      throw const FormatException(
        'Production audio-call fixture host must be a private LAN IPv4.',
      );
    }
    final childEnvironment =
        <String, String>{
            ...environment,
            'GOTOOLCHAIN': productionAudioCallFixtureGoToolchain,
            _fixtureProcessMode: '1',
            _fixtureHostEnvironment: hostIp,
            'DIRECT_INBOX_ACK_CUSTODY_ADMISSION_ENABLED': 'true',
            'DIRECT_MEDIA_BLOB_CUSTODY_ADMISSION_ENABLED': 'true',
          }
          ..remove('TURN_CREDENTIALS_ENABLED')
          ..remove('TURN_CREDENTIAL_URLS')
          ..remove('TURN_CREDENTIAL_PRIMARY_SECRET_B64')
          ..remove('TURN_CREDENTIAL_VERIFICATION_SECRETS_B64')
          ..remove(_oracleCredentialFileEnvironment)
          ..remove(_oracleResultFileEnvironment);
    final process = await Process.start(
      goExecutable,
      const <String>[
        'test',
        '-tags=integration',
        '.',
        '-run',
        r'^TestProductionAudioCallDeviceFixture_ProductionRelayTurnCredentialsCoturnAndTeardown$',
        '-count=1',
        '-v',
        '-timeout=45m',
      ],
      workingDirectory: 'go-relay-server',
      environment: childEnvironment,
    );
    final ready = Completer<Map<String, Object?>>();
    late final StreamSubscription<String> stdoutSubscription;
    stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final marker = line.indexOf(_fixtureReadyPrefix);
          if (marker < 0) {
            stderr.writeln('[plan399-fixture] $line');
            return;
          }
          if (ready.isCompleted) return;
          try {
            final decoded = jsonDecode(
              line.substring(marker + _fixtureReadyPrefix.length),
            );
            if (decoded is! Map) {
              throw const FormatException(
                'Production audio-call fixture readiness is not an object.',
              );
            }
            ready.complete(
              decoded.map<String, Object?>(
                (key, value) => MapEntry('$key', value),
              ),
            );
          } on Object catch (error, stackTrace) {
            ready.completeError(error, stackTrace);
          }
        });
    final stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => stderr.writeln('[plan399-fixture] $line'));
    unawaited(
      process.exitCode.then((code) {
        if (!ready.isCompleted) {
          ready.completeError(
            StateError(
              'Production audio-call fixture exited $code before readiness.',
            ),
          );
        }
      }),
    );

    try {
      final payload = await ready.future.timeout(const Duration(minutes: 10));
      final readiness = validateProductionAudioCallLocalFixtureReadiness(
        payload,
        expectedHost: hostIp,
      );
      await _requirePrivateRegularFile(readiness.oracleCredentialsFile);
      if (await File(readiness.oracleResultFile).exists()) {
        throw const FormatException(
          'Audio oracle result must be absent when the fixture becomes ready.',
        );
      }
      return ProductionAudioCallLocalFixtureLease._(
        process: process,
        readiness: readiness,
        childEnvironment: childEnvironment,
        stopExecutable:
            environment[_fixtureStopExecutableEnvironment]?.trim().isNotEmpty ==
                true
            ? environment[_fixtureStopExecutableEnvironment]!.trim()
            : null,
        stdoutSubscription: stdoutSubscription,
        stderrSubscription: stderrSubscription,
      );
    } on Object {
      await _terminateFixtureProcess(process);
      await stdoutSubscription.cancel();
      await stderrSubscription.cancel();
      rethrow;
    }
  }

  final Process _process;
  final _ProductionAudioCallFixtureReadiness _readiness;
  final Map<String, String> _childEnvironment;
  final String? _stopExecutable;
  final StreamSubscription<String> _stdoutSubscription;
  final StreamSubscription<String> _stderrSubscription;
  bool _oracleRan = false;
  bool _stopped = false;

  String get multiaddr => _readiness.multiaddr;
  String get fixtureIdentitySha256 => _readiness.fixtureIdentitySha256;
  String get probeUrl => _readiness.probeUrl;
  String get relayHost => _readiness.relayHost;
  int get relayPort => _readiness.relayPort;
  String get relayVersion => _readiness.relayVersion;
  String get relayBinarySha256 => _readiness.relayBinarySha256;
  String get turnHost => _readiness.turnHost;
  int get turnPort => _readiness.turnPort;
  String get turnTransport => _readiness.turnTransport;
  String get turnUrl => _readiness.turnUrl;
  String get coturnImage => _readiness.coturnImage;
  String get coturnDigest => _readiness.coturnDigest;
  String get coturnVersion => _readiness.coturnVersion;
  String get coturnLockSha256 => _readiness.coturnLockSha256;
  String get coturnContainerIdentitySha256 =>
      _readiness.coturnContainerIdentitySha256;

  Future<void> verifyAndroidPairAndReachability({
    required String adbExecutable,
    required List<String> devices,
  }) async {
    if (devices.length != 2 || devices.first == devices.last) {
      throw const FormatException(
        'Fixture reachability requires one physical Android followed by one '
        'distinct Android emulator.',
      );
    }
    final classifications = <String>[];
    for (final device in devices) {
      final result = await Process.run(adbExecutable, <String>[
        '-s',
        device,
        'shell',
        'getprop',
        'ro.kernel.qemu',
      ], environment: _childEnvironment).timeout(const Duration(seconds: 10));
      if (result.exitCode != 0) {
        throw StateError('Unable to classify Android target $device.');
      }
      classifications.add('${result.stdout}'.trim());
    }
    if (classifications.first == '1' || classifications.last != '1') {
      throw StateError(
        'Target order must be physical Android then Android emulator.',
      );
    }
    for (final device in devices) {
      for (final endpoint in <(String, int)>[
        (relayHost, relayPort),
        (turnHost, turnPort),
      ]) {
        final result = await Process.run(adbExecutable, <String>[
          '-s',
          device,
          'shell',
          'toybox',
          'nc',
          '-z',
          '-w',
          '5',
          endpoint.$1,
          '${endpoint.$2}',
        ], environment: _childEnvironment).timeout(const Duration(seconds: 10));
        if (result.exitCode != 0) {
          throw StateError(
            'Fixture endpoint ${endpoint.$1}:${endpoint.$2} is unreachable '
            'from Android target $device.',
          );
        }
      }
    }
  }

  Future<ProductionAudioCallOracleResult> runAudioOracle({
    String goExecutable = 'go',
  }) async {
    if (_stopped || _oracleRan) {
      throw StateError('The bounded audio oracle may run exactly once.');
    }
    _oracleRan = true;
    if (await File(_readiness.oracleResultFile).exists()) {
      throw StateError('Audio oracle result path was not exclusive.');
    }
    final oracleProcess = await Process.start(
      goExecutable,
      const <String>[
        'test',
        '-tags=integration',
        './...',
        '-run',
        r'^TestKnownOpusBothDirectionsOverRestAuthenticatedCoturn$',
        '-count=1',
        '-v',
        '-timeout=10m',
      ],
      workingDirectory: 'tool/call_audio_oracle',
      environment: <String, String>{
        ..._childEnvironment,
        'GOTOOLCHAIN': 'go1.25.0',
        _oracleCredentialFileEnvironment: _readiness.oracleCredentialsFile,
        _oracleResultFileEnvironment: _readiness.oracleResultFile,
      },
    );
    final stdoutDrained = oracleProcess.stdout.drain<void>();
    final stderrDrained = oracleProcess.stderr.drain<void>();
    late final int oracleExitCode;
    try {
      oracleExitCode = await oracleProcess.exitCode.timeout(
        const Duration(minutes: 10),
      );
    } on TimeoutException {
      await _terminateFixtureProcess(oracleProcess);
      await Future.wait<void>(<Future<void>>[stdoutDrained, stderrDrained]);
      throw StateError('Known-Opus relay-only audio oracle timed out.');
    }
    await Future.wait<void>(<Future<void>>[stdoutDrained, stderrDrained]);
    if (oracleExitCode != 0) {
      throw StateError(
        'Known-Opus relay-only audio oracle exited $oracleExitCode.',
      );
    }
    await _requirePrivateRegularFile(_readiness.oracleResultFile);
    final encoded = await File(
      _readiness.oracleResultFile,
    ).readAsString().timeout(const Duration(seconds: 5));
    if (encoded.length > 16 * 1024) {
      throw const FormatException('Audio oracle result exceeded its bound.');
    }
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) {
      throw const FormatException('Audio oracle result is not an object.');
    }
    final oracle = validateProductionAudioCallOracleResult(
      decoded.map<String, Object?>((key, value) => MapEntry('$key', value)),
      expectedTransport: turnTransport,
      expectedCoturnImage: coturnImage,
      expectedCoturnDigest: coturnDigest,
      expectedTurnAuthoritySha256: sha256
          .convert(utf8.encode(turnUrl))
          .toString(),
      expectedFixtureInstanceSha256: _readiness.coturnContainerIdentitySha256,
    );
    await File(_readiness.oracleCredentialsFile).delete();
    return oracle;
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    try {
      await _requestStop();
      final code = await _process.exitCode.timeout(const Duration(seconds: 30));
      if (code != 0) {
        throw StateError(
          'Production audio-call fixture exited $code during teardown.',
        );
      }
    } on Object catch (error) {
      await _terminateFixtureProcess(_process);
      throw StateError('Production audio-call fixture teardown failed: $error');
    } finally {
      await _stdoutSubscription.cancel();
      await _stderrSubscription.cancel();
    }
    final privateRoot = File(
      _readiness.oracleCredentialsFile,
    ).parent.absolute.path;
    if (await File(_readiness.oracleCredentialsFile).exists() ||
        await File(_readiness.oracleResultFile).exists() ||
        await Directory(privateRoot).exists()) {
      throw StateError('Production audio-call fixture private root survived.');
    }
  }

  Future<void> _requestStop() async {
    final injected = _stopExecutable;
    if (injected != null) {
      final result = await Process.run(injected, <String>[
        probeUrl,
      ], environment: _childEnvironment).timeout(const Duration(seconds: 10));
      if (result.exitCode != 0) {
        throw StateError('Injected fixture stop exited ${result.exitCode}.');
      }
      return;
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client
          .postUrl(Uri.parse(probeUrl))
          .timeout(const Duration(seconds: 5));
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      final status = response.statusCode;
      await response.drain<void>().timeout(const Duration(seconds: 5));
      if (status != HttpStatus.noContent) {
        throw StateError('Fixture stop returned HTTP $status.');
      }
    } finally {
      client.close(force: true);
    }
  }
}

/// Resolves the one LAN address advertised by both disposable fixture
/// endpoints. Public/DNS/loopback/link-local values are rejected before Go or
/// Docker starts.
Future<String> resolveProductionAudioCallLocalFixtureHostIp(
  Map<String, String> environment,
) async {
  final configured = environment[_fixtureHostOverrideEnvironment]?.trim();
  if (configured != null && configured.isNotEmpty) {
    if (!_isPrivateIpv4(configured)) {
      throw const FormatException(
        'PLAN399_FIXTURE_HOST_IP must be a private LAN IPv4.',
      );
    }
    return configured;
  }
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
    includeLinkLocal: false,
  );
  for (final interface in interfaces) {
    for (final address in interface.addresses) {
      if (!address.isLoopback &&
          !address.isLinkLocal &&
          _isPrivateIpv4(address.address)) {
        return address.address;
      }
    }
  }
  throw const FormatException(
    'No private non-loopback IPv4 is available for the local fixture.',
  );
}

// The strict parser is public only so its fail-closed boundary can be tested
// without starting Docker; the returned lease-readiness carrier stays private.
// ignore: library_private_types_in_public_api
_ProductionAudioCallFixtureReadiness
validateProductionAudioCallLocalFixtureReadiness(
  Map<String, Object?> payload, {
  required String expectedHost,
}) {
  _requireExactKeys(payload, const <String>{
    'schema',
    'multiaddr',
    'probeUrl',
    'fixtureIdentitySha256',
    'backend',
    'ephemeral',
    'ackCustodyAdmissionEnabled',
    'mediaCustodyAdmissionEnabled',
    'relayVersion',
    'relayBinarySha256',
    'turnHost',
    'turnPort',
    'turnTransport',
    'turnUrl',
    'coturnImage',
    'coturnDigest',
    'coturnVersion',
    'coturnLockSha256',
    'coturnContainerIdentitySha256',
    'oracleCredentialsFile',
    'oracleResultFile',
  });
  final multiaddr = payload['multiaddr'];
  final probeUrl = payload['probeUrl'];
  final fixtureIdentity = payload['fixtureIdentitySha256'];
  final relayVersion = payload['relayVersion'];
  final relayBinary = payload['relayBinarySha256'];
  final turnHost = payload['turnHost'];
  final turnPort = payload['turnPort'];
  final turnTransport = payload['turnTransport'];
  final turnUrl = payload['turnUrl'];
  final lockSha = payload['coturnLockSha256'];
  final containerSha = payload['coturnContainerIdentitySha256'];
  final credentialsFile = payload['oracleCredentialsFile'];
  final resultFile = payload['oracleResultFile'];
  if (payload['schema'] != _fixtureSchema ||
      payload['backend'] != 'redis' ||
      payload['ephemeral'] != true ||
      payload['ackCustodyAdmissionEnabled'] != true ||
      payload['mediaCustodyAdmissionEnabled'] != true ||
      multiaddr is! String ||
      probeUrl is! String ||
      fixtureIdentity is! String ||
      relayVersion is! String ||
      relayVersion.isEmpty ||
      relayBinary is! String ||
      turnHost != expectedHost ||
      turnPort is! int ||
      turnPort <= 0 ||
      turnPort > 65535 ||
      turnTransport != 'udp' ||
      turnUrl != 'turn:$expectedHost:$turnPort?transport=udp' ||
      payload['coturnImage'] != _coturnImage ||
      payload['coturnDigest'] != _coturnDigest ||
      payload['coturnVersion'] != _coturnVersion ||
      lockSha is! String ||
      containerSha is! String ||
      credentialsFile is! String ||
      resultFile is! String ||
      !_isLowerHexSha256(fixtureIdentity) ||
      !_isLowerHexSha256(relayBinary) ||
      !_isLowerHexSha256(lockSha) ||
      !_isLowerHexSha256(containerSha)) {
    throw const FormatException(
      'Production audio-call fixture readiness omitted a required '
      'production/dependency attestation.',
    );
  }
  final relayMatch = RegExp(
    r'^/ip4/([^/]+)/tcp/([1-9][0-9]*)/p2p/[A-Za-z0-9]+$',
  ).firstMatch(multiaddr);
  final relayPort = relayMatch == null
      ? null
      : int.tryParse(relayMatch.group(2)!);
  final parsedProbe = Uri.tryParse(probeUrl);
  if (relayMatch == null ||
      relayMatch.group(1) != expectedHost ||
      relayPort == null ||
      relayPort > 65535 ||
      parsedProbe == null ||
      parsedProbe.scheme != 'http' ||
      parsedProbe.host != expectedHost ||
      parsedProbe.port <= 0 ||
      !RegExp(r'^/[0-9a-f]{64}$').hasMatch(parsedProbe.path) ||
      parsedProbe.hasQuery ||
      parsedProbe.hasFragment) {
    throw const FormatException(
      'Production audio-call fixture did not announce exact local endpoints.',
    );
  }
  final credentials = File(credentialsFile).absolute.path;
  final result = File(resultFile).absolute.path;
  if (credentials != credentialsFile ||
      result != resultFile ||
      credentials == result ||
      File(credentials).parent.path != File(result).parent.path ||
      File(credentials).uri.pathSegments.last != 'oracle-credentials.json' ||
      File(result).uri.pathSegments.last != 'oracle-result.json') {
    throw const FormatException(
      'Production audio-call fixture private paths escaped one temp root.',
    );
  }
  return _ProductionAudioCallFixtureReadiness(
    multiaddr: multiaddr,
    relayHost: expectedHost,
    relayPort: relayPort,
    probeUrl: probeUrl,
    fixtureIdentitySha256: fixtureIdentity,
    relayVersion: relayVersion,
    relayBinarySha256: relayBinary,
    turnHost: turnHost as String,
    turnPort: turnPort,
    turnTransport: turnTransport as String,
    turnUrl: turnUrl as String,
    coturnImage: payload['coturnImage']! as String,
    coturnDigest: payload['coturnDigest']! as String,
    coturnVersion: payload['coturnVersion']! as String,
    coturnLockSha256: lockSha,
    coturnContainerIdentitySha256: containerSha,
    oracleCredentialsFile: credentials,
    oracleResultFile: result,
  );
}

ProductionAudioCallOracleResult validateProductionAudioCallOracleResult(
  Map<String, Object?> payload, {
  required String expectedTransport,
  required String expectedCoturnImage,
  required String expectedCoturnDigest,
  required String expectedTurnAuthoritySha256,
  required String expectedFixtureInstanceSha256,
}) {
  _requireExactKeys(payload, const <String>{
    'schema',
    'version',
    'passed',
    'pion_version',
    'fixture_sha256',
    'turn_authority_sha256',
    'fixture_instance_sha256',
    'coturn',
    'expected_transport',
    'a_to_b',
    'b_to_a',
    'peer_a_route',
    'peer_b_route',
    'cleanup_complete',
  });
  final coturn = _objectMap(payload['coturn'], 'coturn');
  _requireExactKeys(coturn, const <String>{'image', 'digest'});
  final aToB = _parseOracleDirection(payload['a_to_b'], 'a_to_b');
  final bToA = _parseOracleDirection(payload['b_to_a'], 'b_to_a');
  final peerA = _parseOracleRoute(payload['peer_a_route'], 'peer_a_route');
  final peerB = _parseOracleRoute(payload['peer_b_route'], 'peer_b_route');
  final fixtureSha = payload['fixture_sha256'];
  if (payload['schema'] != _oracleResultSchema ||
      payload['version'] != 1 ||
      payload['passed'] != true ||
      payload['pion_version'] != _pionVersion ||
      fixtureSha is! String ||
      !_isLowerHexSha256(fixtureSha) ||
      payload['turn_authority_sha256'] != expectedTurnAuthoritySha256 ||
      !_isLowerHexSha256(expectedTurnAuthoritySha256) ||
      payload['fixture_instance_sha256'] != expectedFixtureInstanceSha256 ||
      !_isLowerHexSha256(expectedFixtureInstanceSha256) ||
      coturn['image'] != expectedCoturnImage ||
      coturn['digest'] != expectedCoturnDigest ||
      payload['expected_transport'] != expectedTransport ||
      payload['cleanup_complete'] != true ||
      !aToB.passed ||
      !bToA.passed ||
      !peerA.passed ||
      !peerB.passed) {
    throw const FormatException(
      'Audio oracle result did not prove both exact relay-only directions.',
    );
  }
  return ProductionAudioCallOracleResult._(
    version: 1,
    pionVersion: _pionVersion,
    fixtureSha256: fixtureSha,
    turnAuthoritySha256: expectedTurnAuthoritySha256,
    fixtureInstanceSha256: expectedFixtureInstanceSha256,
    coturnImage: expectedCoturnImage,
    coturnDigest: expectedCoturnDigest,
    expectedTransport: expectedTransport,
    aToB: aToB,
    bToA: bToA,
    peerARoute: peerA,
    peerBRoute: peerB,
  );
}

ProductionAudioCallOracleDirectionResult _parseOracleDirection(
  Object? raw,
  String name,
) {
  final value = _objectMap(raw, name);
  _requireExactKeys(value, const <String>{
    'codec_valid',
    'payload_count_exact',
    'payload_order_exact',
    'payload_hash_exact',
  });
  for (final key in value.keys) {
    if (value[key] is! bool) {
      throw FormatException('Audio oracle $name.$key is not boolean.');
    }
  }
  return ProductionAudioCallOracleDirectionResult(
    codecValid: value['codec_valid']! as bool,
    payloadCountExact: value['payload_count_exact']! as bool,
    payloadOrderExact: value['payload_order_exact']! as bool,
    payloadHashExact: value['payload_hash_exact']! as bool,
  );
}

ProductionAudioCallOracleRouteResult _parseOracleRoute(
  Object? raw,
  String name,
) {
  final value = _objectMap(raw, name);
  _requireExactKeys(value, const <String>{'relay_selected', 'transport_match'});
  if (value['relay_selected'] is! bool || value['transport_match'] is! bool) {
    throw FormatException('Audio oracle $name route values are not boolean.');
  }
  return ProductionAudioCallOracleRouteResult(
    relaySelected: value['relay_selected']! as bool,
    transportMatch: value['transport_match']! as bool,
  );
}

Map<String, Object?> _objectMap(Object? raw, String name) {
  if (raw is! Map) {
    throw FormatException('Audio oracle $name is not an object.');
  }
  return raw.map<String, Object?>((key, value) => MapEntry('$key', value));
}

void _requireExactKeys(Map<String, Object?> value, Set<String> expected) {
  if (value.length != expected.length ||
      !value.keys.toSet().containsAll(expected)) {
    throw const FormatException('JSON allowlist changed unexpectedly.');
  }
}

bool _isLowerHexSha256(String value) =>
    RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

bool _isPrivateIpv4(String value) {
  if (!RegExp(
    r'^(?:0|[1-9][0-9]{0,2})(?:\.(?:0|[1-9][0-9]{0,2})){3}$',
  ).hasMatch(value)) {
    return false;
  }
  final parts = value.split('.').map(int.tryParse).toList(growable: false);
  if (parts.length != 4 ||
      parts.any((part) => part == null || part < 0 || part > 255)) {
    return false;
  }
  final first = parts[0]!;
  final second = parts[1]!;
  return first == 10 ||
      (first == 172 && second >= 16 && second <= 31) ||
      (first == 192 && second == 168);
}

Future<void> _requirePrivateRegularFile(String path) async {
  final stat = await File(path).stat();
  if (stat.type != FileSystemEntityType.file || stat.mode & 0x1ff != 0x180) {
    throw const FormatException(
      'Fixture private file must be regular and mode 0600.',
    );
  }
}

Future<void> _terminateFixtureProcess(Process process) async {
  process.kill(ProcessSignal.sigterm);
  try {
    await process.exitCode.timeout(const Duration(seconds: 10));
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode.timeout(const Duration(seconds: 10));
  }
}
