import 'dart:io';

import 'package:path/path.dart' as p;

import 'runtime_root_inventory.dart';

void main(List<String> arguments) {
  final parsed = _CliOptions.tryParse(arguments);
  if (parsed == null) {
    exitCode = 2;
    return;
  }

  try {
    final manifestFile = File(parsed.manifestPath);
    if (!manifestFile.existsSync()) {
      stderr.writeln('Missing runtime-roots manifest: ${manifestFile.path}');
      exitCode = 2;
      return;
    }
    final manifest = RuntimeRootsManifest.loadSync(manifestFile);
    final result = RuntimeRootInventory(
      repoRoot: parsed.repoRoot,
      manifest: manifest,
    ).scan();
    stdout.write(
      parsed.format == _OutputFormat.json
          ? result.renderJson()
          : result.renderText(),
    );
    exitCode = result.exitCodeFor(check: parsed.mode == _Mode.check);
  } on Object catch (error, stackTrace) {
    stderr.writeln('Runtime-root inventory failed: $error');
    if (Platform.environment['RUNTIME_ROOTS_DEBUG'] == '1') {
      stderr.writeln(stackTrace);
    }
    exitCode = 2;
  }
}

enum _Mode { report, check }

enum _OutputFormat { text, json }

class _CliOptions {
  const _CliOptions({
    required this.mode,
    required this.format,
    required this.repoRoot,
    required this.manifestPath,
  });

  final _Mode mode;
  final _OutputFormat format;
  final String repoRoot;
  final String manifestPath;

  static _CliOptions? tryParse(List<String> arguments) {
    void usage([String? message]) {
      if (message != null) stderr.writeln(message);
      stderr.writeln(
        'Usage: dart tool/runtime_roots/runtime_root_inventory_cli.dart '
        '<report|check> [--format <text|json>] '
        '[--repo-root <path>] [--manifest <path>]',
      );
    }

    if (arguments.isEmpty) {
      usage('Missing report/check mode.');
      return null;
    }
    final mode = switch (arguments.first) {
      'report' => _Mode.report,
      'check' => _Mode.check,
      _ => null,
    };
    if (mode == null) {
      usage('Unknown mode: ${arguments.first}');
      return null;
    }

    _OutputFormat format = _OutputFormat.text;
    String? repoRootOverride;
    String? manifestOverride;
    final seen = <String>{};
    var index = 1;
    while (index < arguments.length) {
      final raw = arguments[index];
      String option;
      String? value;
      final equals = raw.indexOf('=');
      if (equals > 0) {
        option = raw.substring(0, equals);
        value = raw.substring(equals + 1);
      } else {
        option = raw;
      }
      if (!const <String>{
        '--format',
        '--repo-root',
        '--manifest',
      }.contains(option)) {
        usage('Unknown option: $raw');
        return null;
      }
      if (!seen.add(option)) {
        usage('Duplicate option: $option');
        return null;
      }
      if (value == null) {
        index++;
        if (index >= arguments.length || arguments[index].startsWith('--')) {
          usage('Missing value for $option.');
          return null;
        }
        value = arguments[index];
      }
      if (value.isEmpty) {
        usage('Empty value for $option.');
        return null;
      }
      switch (option) {
        case '--format':
          if (value != 'text' && value != 'json') {
            usage('Unknown format: $value');
            return null;
          }
          format = value == 'json' ? _OutputFormat.json : _OutputFormat.text;
        case '--repo-root':
          repoRootOverride = value;
        case '--manifest':
          manifestOverride = value;
      }
      index++;
    }

    final script = File.fromUri(Platform.script).absolute;
    final defaultRepoRoot = script.parent.parent.parent.path;
    final repoRoot = p.normalize(
      p.absolute(repoRootOverride ?? defaultRepoRoot),
    );
    final manifestPath = p.normalize(
      p.absolute(
        manifestOverride == null
            ? p.join(repoRoot, 'tool', 'runtime_roots', 'runtime_roots.json')
            : (p.isAbsolute(manifestOverride)
                  ? manifestOverride
                  : p.join(repoRoot, manifestOverride)),
      ),
    );
    return _CliOptions(
      mode: mode,
      format: format,
      repoRoot: repoRoot,
      manifestPath: manifestPath,
    );
  }
}
