// Canonical filesystem-polling signal-file coordination for two-device
// integration harnesses and their CLI orchestrators (124 Phase 2).
//
// WHY THIS EXISTS
// ---------------
// Many alice/bob app harnesses (`*_harness.dart`) coordinate with their
// `scripts/run_*.dart` orchestrators by writing/reading tiny files in a shared
// directory and polling for their appearance. The same `_sig` / `_writeSignal`
// / `_writeJson` / `_waitForSignal` / `_waitForJson` helpers were copy-pasted
// into ~20 files, each with a slightly different filename prefix
// (`smoke_`, `nsmoke_`, `notifopen_`, `fgpush_`, `gsmoke_`, `gmp_`, `gp_`,
// `h_`, `md004_`, ...). A harness writer and its orchestrator reader are
// COUPLED through the exact on-disk filename: if the two sides ever disagree
// on a single byte of the path, the file is never seen, the poll loop runs to
// its deadline, and the two-device run hangs or fails opaquely.
//
// This library is the ONE canonical implementation. It is pure
// `dart:io` + `dart:convert` (NO Flutter, NO package:flutter_app imports) so it
// can be imported by BOTH the `flutter test` harnesses AND the
// `dart run scripts/run_*.dart` orchestrators.
//
// BYTE-IDENTICAL GUARANTEE
// ------------------------
// `SignalDir` reproduces the EXACT path each family currently produces:
//
//   <dir>/<prefix><runId>_<name>      (prefixed families)
//
// e.g. routing smoke -> `<dir>/smoke_<runId>_<name>`. Construct a `SignalDir`
// with the family's `prefix` and the run's `runId`; `path(name)` yields the
// identical string the inline `_sig(name)` used to. Families that key by run
// id all match this shape — see `signal_files.md`-equivalent mapping in the
// 124 plan / the EXTRACT for this task for the per-family prefix table.
//
// Flat (non-prefixed, non-run-keyed) families — `transport_e2e_test.dart`,
// `wifi_relay_fallback_smoke_test.dart`, `group_recovery_cli_e2e_test.dart`,
// `soak_e2e_test.dart` and `scripts/run_soak_e2e.dart` — write plain
// `<dir>/<name>` and frequently use SEPARATE read/write dirs. Use a
// `SignalDir` with an empty prefix and empty runId for those, or the
// `SignalDir.flat(dir)` convenience; `path('foo.json')` then yields
// `<dir>/foo.json`, byte-identical to the old `'$_dir/$name'`.
//
// POLL SEMANTICS (preserved as the DEFAULT)
// -----------------------------------------
// The historical loop is: check `File(path).existsSync()` (for JSON, also
// decode), else `await Future.delayed(250ms)`, until a deadline, then throw
// `TimeoutException`. The two benchmark scripts (`gp_`, `h_`) polled at 200ms.
// The canonical default poll interval is 250ms; pass `pollInterval` to match a
// 200ms caller exactly. Default timeouts varied per call site (120s / 300s /
// 3min / 5min / 6min / 10min) and were always passed explicitly at the wait
// site — callers keep passing their own `timeout`, so behavior is unchanged.
//
// LOUD TIMEOUT + OPTIONAL SCHEMA CHECK (the new, opt-in safety)
// -------------------------------------------------------------
// The plan flagged a hang risk in older 500ms-no-timeout variants. Every wait
// here ALWAYS has a finite deadline and throws a descriptive
// `SignalTimeoutException` (a `TimeoutException` subtype) naming the role, the
// signal, the full path, and the elapsed time — so a stuck two-device run
// fails loud instead of silently. `waitForJson` accepts an optional `validate`
// callback: if the decoded map fails validation it is treated as not-yet-ready
// (the file may still be mid-write by the peer), so partial/garbage reads do
// not crash early — matching the existing `try/catch (_) {}` retry behavior in
// the orchestrators, but now with an explicit hook.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Thrown when a signal does not appear before its deadline. Subtype of
/// [TimeoutException] so existing `on TimeoutException` handlers still catch it,
/// but carries the role / signal name / full path / elapsed for loud diagnosis.
class SignalTimeoutException extends TimeoutException {
  SignalTimeoutException({
    required this.role,
    required this.name,
    required this.path,
    required Duration elapsed,
    this.lastError,
  }) : super(
          _buildMessage(
            role: role,
            name: name,
            path: path,
            elapsed: elapsed,
            lastError: lastError,
          ),
          elapsed,
        );

  /// Caller-supplied label (e.g. `'alice'`, `'Orchestrator'`, `'bob(group)'`).
  final String role;

  /// Logical signal name (e.g. `'s5_go'`, `'bob_identity.json'`).
  final String name;

  /// The full on-disk path that was polled.
  final String path;

  /// The most recent decode/IO error seen while polling JSON, if any.
  final Object? lastError;

  static String _buildMessage({
    required String role,
    required String name,
    required String path,
    required Duration elapsed,
    Object? lastError,
  }) {
    final secs = (elapsed.inMilliseconds / 1000).toStringAsFixed(1);
    final base =
        '$role: timed out after ${secs}s waiting for signal: $name (path=$path)';
    return lastError == null ? base : '$base; last error: $lastError';
  }
}

/// The default poll interval used historically by almost every consumer.
const Duration kSignalPollInterval = Duration(milliseconds: 250);

/// Builds the EXACT on-disk path for one signal family and run, then
/// reads/writes/polls signal files at those paths.
///
/// Path layout reproduced byte-for-byte:
///   - prefixed/run-keyed:  `<dir>/<prefix><runId>_<name>`
///   - flat:                `<dir>/<name>`  (empty prefix + empty runId)
///
/// `dir` is stored as a plain string (the caller may pass either a
/// `Directory.path` or a literal like `/tmp`); it is joined with `/` exactly as
/// the inline helpers did (no `path.join`, to stay byte-identical on the POSIX
/// targets these harnesses run on).
class SignalDir {
  SignalDir({
    required String dir,
    this.prefix = '',
    this.runId = '',
    this.role = 'role',
    this.pollInterval = kSignalPollInterval,
  }) : dir = _stripTrailingSlash(dir);

  /// Convenience for a [Directory] (uses `directory.path`).
  factory SignalDir.forDirectory(
    Directory directory, {
    String prefix = '',
    String runId = '',
    String role = 'role',
    Duration pollInterval = kSignalPollInterval,
  }) =>
      SignalDir(
        dir: directory.path,
        prefix: prefix,
        runId: runId,
        role: role,
        pollInterval: pollInterval,
      );

  /// Convenience for the FLAT (non-prefixed, non-run-keyed) families. Produces
  /// `<dir>/<name>`, byte-identical to the old `'$_dir/$name'`.
  factory SignalDir.flat(
    String dir, {
    String role = 'role',
    Duration pollInterval = kSignalPollInterval,
  }) =>
      SignalDir(dir: dir, role: role, pollInterval: pollInterval);

  /// Shared directory the signal files live in (trailing slash stripped).
  final String dir;

  /// Family prefix, e.g. `'smoke_'`, `'nsmoke_'`, `'fgpush_'`, `'gmp_'`,
  /// `'gp_'`, `'h_'`, `'md004_'`. Empty for flat families.
  final String prefix;

  /// Per-run isolation token (`SMOKE_RUN_ID` / `runId`). Empty for flat
  /// families.
  final String runId;

  /// Label used in timeout messages (the old helpers baked role text into the
  /// `TimeoutException` string, e.g. `'$_role(group)'`).
  final String role;

  /// Poll cadence. Default 250ms; pass `Duration(milliseconds: 200)` to match
  /// the two benchmark orchestrators exactly.
  final Duration pollInterval;

  static String _stripTrailingSlash(String d) =>
      (d.length > 1 && d.endsWith('/')) ? d.substring(0, d.length - 1) : d;

  /// The canonical replacement for the inline `_sig(name)`.
  ///
  /// For a routing-smoke `SignalDir(dir: '/tmp', prefix: 'smoke_', runId: 'r1')`
  /// this returns `/tmp/smoke_r1_s5_go` for `name = 's5_go'` — byte-identical
  /// to the old `'$_sharedDir/smoke_${_runId}_$name'`.
  String path(String name) => '$dir/$prefix$runId$name';

  /// Returns a copy with a different [role] label (useful when one process
  /// writes as "alice" but logs waits as "bob").
  SignalDir withRole(String newRole) => SignalDir(
        dir: dir,
        prefix: prefix,
        runId: runId,
        role: newRole,
        pollInterval: pollInterval,
      );

  // -------------------------------------------------------------------------
  // Writers (synchronous, matching the inline helpers' `writeAsStringSync`).
  // -------------------------------------------------------------------------

  /// Writes raw text to the signal file. Mirrors the inline
  /// `_writeSignal(name, content)` (and the `_writeSignal(name)` 'ok' variant —
  /// pass `content: 'ok'`).
  ///
  /// `createDir` mirrors the flat CLI harnesses that did
  /// `Directory(_writeDir).createSync(recursive: true)` before each write; it
  /// is off by default so the prefixed `/tmp`-style callers stay unchanged.
  void writeSignal(String name, {String content = 'ok', bool createDir = false}) {
    if (createDir) {
      Directory(dir).createSync(recursive: true);
    }
    File(path(name)).writeAsStringSync(content);
  }

  /// Writes a JSON object. Mirrors `_writeJson` / `_writeJsonSignal` /
  /// `_writeTimingSignal`.
  void writeJson(
    String name,
    Map<String, dynamic> data, {
    bool createDir = false,
  }) {
    writeSignal(name, content: jsonEncode(data), createDir: createDir);
  }

  /// True if the signal file currently exists. Mirrors the soak
  /// `_signalExists` helper.
  bool exists(String name) => File(path(name)).existsSync();

  /// Reads the file's text if present, else null (mirrors soak `_readSignal`).
  String? read(String name) {
    final file = File(path(name));
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  /// Deletes the signal file if present (idempotent).
  void delete(String name) {
    final file = File(path(name));
    if (file.existsSync()) file.deleteSync();
  }

  // -------------------------------------------------------------------------
  // Waiters (poll + finite deadline + loud throw).
  // -------------------------------------------------------------------------

  /// Polls until the signal file exists, then returns. Throws
  /// [SignalTimeoutException] (a [TimeoutException]) when [timeout] elapses.
  /// Default poll interval and timeout match the historical helpers.
  Future<void> waitForSignal(
    String name, {
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final p = path(name);
    final file = File(p);
    final start = DateTime.now();
    final deadline = start.add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (file.existsSync()) return;
      await Future<void>.delayed(pollInterval);
    }
    throw SignalTimeoutException(
      role: role,
      name: name,
      path: p,
      elapsed: DateTime.now().difference(start),
    );
  }

  /// Polls until the signal file exists AND decodes to a `Map<String,dynamic>`
  /// (and, if [validate] is supplied, passes validation), then returns the map.
  ///
  /// A file that exists but does not yet decode — or fails [validate] — is
  /// treated as NOT-YET-READY and retried, matching the orchestrators'
  /// `try { jsonDecode(...) } catch (_) {}` retry loop (the peer may be
  /// mid-write). The last decode/validation error is attached to the thrown
  /// [SignalTimeoutException] for diagnosis.
  Future<Map<String, dynamic>> waitForJson(
    String name, {
    Duration timeout = const Duration(seconds: 120),
    bool Function(Map<String, dynamic> value)? validate,
  }) async {
    final p = path(name);
    final file = File(p);
    final start = DateTime.now();
    final deadline = start.add(timeout);
    Object? lastError;
    while (DateTime.now().isBefore(deadline)) {
      if (file.existsSync()) {
        try {
          final decoded =
              jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
          if (validate == null || validate(decoded)) {
            return decoded;
          }
          lastError = StateError('schema validation failed for signal: $name');
        } on FormatException catch (e) {
          lastError = e;
        } on FileSystemException catch (e) {
          lastError = e;
        } on TypeError catch (e) {
          lastError = e;
        }
      }
      await Future<void>.delayed(pollInterval);
    }
    throw SignalTimeoutException(
      role: role,
      name: name,
      path: p,
      elapsed: DateTime.now().difference(start),
      lastError: lastError,
    );
  }
}
