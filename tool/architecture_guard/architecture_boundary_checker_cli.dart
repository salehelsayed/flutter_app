import 'dart:io';

import 'package:path/path.dart' as p;

import 'architecture_boundary_checker.dart';

void main(List<String> arguments) {
  exitCode = runArchitectureBoundaryCheckerCli(arguments);
}

int runArchitectureBoundaryCheckerCli(List<String> arguments) {
  try {
    final options = _CliOptions.parse(arguments);
    final script = File.fromUri(Platform.script).absolute;
    final defaultRoot = script.parent.parent.parent.path;
    final requestedRoot = options.repoRoot ?? defaultRoot;
    if (!p.isAbsolute(requestedRoot)) {
      throw const FormatException('--repo-root must be an absolute path.');
    }
    final rootDirectory = Directory(p.normalize(requestedRoot));
    if (!rootDirectory.existsSync()) {
      throw FileSystemException(
        'Repository root does not exist.',
        rootDirectory.path,
      );
    }
    final repoRoot = rootDirectory.resolveSymbolicLinksSync();

    final requestedManifest =
        options.manifest ??
        p.join(
          repoRoot,
          'tool',
          'architecture_guard',
          'architecture_boundary_exceptions.json',
        );
    if (!p.isAbsolute(requestedManifest)) {
      throw const FormatException('--manifest must be an absolute path.');
    }
    final manifestFile = File(p.normalize(requestedManifest));
    if (!manifestFile.existsSync()) {
      throw FileSystemException(
        'Architecture boundary manifest does not exist.',
        manifestFile.path,
      );
    }
    final resolvedManifest = manifestFile.resolveSymbolicLinksSync();
    if (!p.isWithin(repoRoot, resolvedManifest)) {
      throw FormatException(
        'Architecture boundary manifest must be contained by --repo-root: '
        '$resolvedManifest',
      );
    }

    final manifest = ArchitectureBoundaryManifest.loadSync(
      File(resolvedManifest),
    );
    final result = ArchitectureBoundaryChecker(
      repoRoot: repoRoot,
      manifest: manifest,
    ).check();
    stdout.writeln(
      options.format == _OutputFormat.json
          ? result.toJsonText()
          : result.toText(),
    );
    return result.exitCodeFor(check: options.mode == _CliMode.check);
  } on Object catch (error) {
    stderr.writeln('architecture-boundaries: $error');
    stderr.writeln(_usage);
    return 2;
  }
}

enum _CliMode { report, check }

enum _OutputFormat { text, json }

class _CliOptions {
  const _CliOptions({
    required this.mode,
    required this.format,
    required this.repoRoot,
    required this.manifest,
  });

  factory _CliOptions.parse(List<String> arguments) {
    if (arguments.isEmpty) {
      throw const FormatException('A report or check mode is required.');
    }
    final mode = switch (arguments.first) {
      'report' => _CliMode.report,
      'check' => _CliMode.check,
      final value => throw FormatException('Unsupported mode: $value'),
    };
    String? repoRoot;
    String? manifest;
    var format = _OutputFormat.text;
    final seen = <String>{};
    for (var index = 1; index < arguments.length; index++) {
      final argument = arguments[index];
      late final String key;
      late final String value;
      final equals = argument.indexOf('=');
      if (equals >= 0) {
        key = argument.substring(0, equals);
        value = argument.substring(equals + 1);
      } else {
        key = argument;
        if (index + 1 >= arguments.length) {
          throw FormatException('Missing value for $key.');
        }
        value = arguments[++index];
      }
      if (!const <String>{
        '--repo-root',
        '--manifest',
        '--format',
      }.contains(key)) {
        throw FormatException('Unknown option: $key');
      }
      if (!seen.add(key)) {
        throw FormatException('Duplicate option: $key');
      }
      if (value.isEmpty || value.startsWith('--')) {
        throw FormatException('Missing value for $key.');
      }
      switch (key) {
        case '--repo-root':
          repoRoot = value;
        case '--manifest':
          manifest = value;
        case '--format':
          format = switch (value) {
            'text' => _OutputFormat.text,
            'json' => _OutputFormat.json,
            _ => throw FormatException('Unknown output format: $value'),
          };
      }
    }
    return _CliOptions(
      mode: mode,
      format: format,
      repoRoot: repoRoot,
      manifest: manifest,
    );
  }

  final _CliMode mode;
  final _OutputFormat format;
  final String? repoRoot;
  final String? manifest;
}

const String _usage =
    'Usage: dart tool/architecture_guard/'
    'architecture_boundary_checker_cli.dart <report|check> '
    '[--repo-root ABSOLUTE] [--manifest ABSOLUTE] '
    '[--format <text|json>]';
