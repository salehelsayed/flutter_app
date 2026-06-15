/// Shared CLI test-peer fixture reader for device/integration harnesses.
///
/// The orchestrator (`run_benchmark_suite.dart` and the transport/wifi/recovery
/// runners) starts a real Go CLI test peer and writes its identity to a JSON
/// fixture file. The path is passed to the Flutter test process via the
/// `CLI_PEER_FIXTURE` dart-define; when absent it falls back to a well-known
/// location under the system temp directory.
///
/// This was previously duplicated verbatim across the benchmark harnesses
/// (as `_loadCliPeerFixture` / `_loadFixture`) and the transport, wifi and
/// group-recovery e2e tests. Consumers should import this single canonical
/// reader instead.
///
/// The fixture is an untyped JSON object; callers read the fields they need
/// (e.g. `fixture['peerId'] as String`, `fixture['publicKey'] as String?`,
/// `fixture['mlKemPublicKey'] as String?`). Returns `null` when the fixture is
/// missing or cannot be parsed (the standard "skip — run via orchestrator"
/// signal).
library;

import 'dart:convert';
import 'dart:io';

/// The configured CLI peer fixture path, supplied by the orchestrator via the
/// `CLI_PEER_FIXTURE` dart-define. Empty when not provided.
const String configuredCliPeerFixture = String.fromEnvironment(
  'CLI_PEER_FIXTURE',
  defaultValue: '',
);

/// Resolves the CLI peer fixture path: the `CLI_PEER_FIXTURE` dart-define when
/// set, otherwise `cli_peer_fixture.json` under the system temp directory.
String cliPeerFixturePath() => configuredCliPeerFixture.isNotEmpty
    ? configuredCliPeerFixture
    : '${Directory.systemTemp.path}/cli_peer_fixture.json';

/// Reads and parses the CLI test-peer fixture written by the orchestrator.
///
/// Returns the decoded JSON object, or `null` when the fixture file does not
/// exist or fails to parse (the canonical "no CLI peer — skip" signal).
Map<String, dynamic>? loadCliPeerFixture() {
  final file = File(cliPeerFixturePath());
  if (!file.existsSync()) return null;
  try {
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  } catch (e) {
    print('[TEST] Failed to parse CLI peer fixture: $e');
    return null;
  }
}
