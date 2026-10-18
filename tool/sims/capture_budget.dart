import 'dart:convert';
import 'dart:io';

const simsStreamCaptureBytes = 8 * 1024 * 1024;
const simsRunCaptureBytes = 256 * 1024 * 1024;

final class EvidenceCapacityFailure implements Exception {
  const EvidenceCapacityFailure(this.boundary, this.limit, this.retained);
  final String boundary;
  final int limit;
  final int retained;

  @override
  String toString() =>
      'evidence_capacity: $boundary limit=$limit retained=$retained';
}

/// Shared by a run's cooperating captures, with no environment override.
final class EvidenceCaptureBudget {
  EvidenceCaptureBudget({this.limitBytes = simsRunCaptureBytes}) {
    if (limitBytes <= 0) {
      throw ArgumentError.value(limitBytes, 'limitBytes');
    }
  }
  final int limitBytes;
  int _used = 0;
  int get usedBytes => _used;
  int get remainingBytes => limitBytes - _used;

  int claimPrefix(int requested) {
    if (requested < 0) {
      throw ArgumentError.value(requested, 'requested');
    }
    final allowed = requested < remainingBytes ? requested : remainingBytes;
    _used += allowed;
    return allowed;
  }

  void reserveWhole(int bytes, String boundary) {
    if (bytes < 0) {
      throw ArgumentError.value(bytes, 'bytes');
    }
    if (bytes > remainingBytes) {
      throw EvidenceCapacityFailure(boundary, limitBytes, _used);
    }
    _used += bytes;
  }
}

/// One synchronous writer keeps cursor reads independent of IOSink.flush.
/// The whole stream is retained on disk; each in-memory window is bounded.
final class BoundedDiagnosticFile {
  BoundedDiagnosticFile(
    this.file, {
    required this.budget,
    this.limitBytes = simsRunCaptureBytes,
    this.windowLimitBytes = simsStreamCaptureBytes,
  }) {
    if (limitBytes <= 0 || windowLimitBytes <= 0) {
      throw ArgumentError('Diagnostic limits must be positive.');
    }
    if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('Diagnostic capture requires a fresh file.');
    }
    file.parent.createSync(recursive: true);
    _writer = file.openSync(mode: FileMode.write);
    final permissions = Process.runSync('chmod', ['600', file.path]);
    if (permissions.exitCode != 0) {
      _writer.closeSync();
      throw StateError('Private diagnostic permissions unavailable.');
    }
  }
  final File file;
  final EvidenceCaptureBudget budget;
  final int limitBytes;
  final int windowLimitBytes;
  late final RandomAccessFile _writer;
  int _written = 0;
  bool _closed = false;
  EvidenceCapacityFailure? _failure;
  EvidenceCapacityFailure? get failure => _failure;

  void add(List<int> chunk) {
    if (_failure != null) {
      throw _failure!;
    }
    if (_closed) {
      throw StateError('Diagnostic writer is closed.');
    }
    final room = limitBytes - _written;
    final requested = chunk.length < room ? chunk.length : room;
    final accepted = budget.claimPrefix(requested);
    _writer.writeFromSync(chunk, 0, accepted);
    _written += accepted;
    if (accepted < chunk.length) {
      _failure = EvidenceCapacityFailure(
        accepted < requested ? 'diagnostic_run' : 'diagnostic_file',
        accepted < requested ? budget.limitBytes : limitBytes,
        accepted < requested ? budget.usedBytes : _written,
      );
      throw _failure!;
    }
  }

  void _requireComplete() {
    if (_failure != null) {
      throw _failure!;
    }
    if (file.lengthSync() != _written) {
      throw StateError('Diagnostic file changed outside its owned writer.');
    }
  }

  int get cursor {
    _requireComplete();
    return _written;
  }

  String readSince(int offset) {
    _requireComplete();
    if (offset < 0 || offset > _written) {
      throw const FormatException('Diagnostic cursor is outside this stream.');
    }
    final length = _written - offset;
    if (length > windowLimitBytes) {
      _failure = EvidenceCapacityFailure(
        'diagnostic_window',
        windowLimitBytes,
        0,
      );
      throw _failure!;
    }
    final reader = file.openSync();
    try {
      reader.setPositionSync(offset);
      final bytes = reader.readSync(length);
      if (bytes.length != length) {
        throw StateError('Diagnostic window is incomplete.');
      }
      return utf8.decode(bytes, allowMalformed: true);
    } finally {
      reader.closeSync();
    }
  }

  void close() {
    if (!_closed) {
      _closed = true;
      try {
        _writer.flushSync();
      } finally {
        _writer.closeSync();
      }
    }
  }
}

final class ScreenshotCaptureBudget {
  ScreenshotCaptureBudget({
    required this.budget,
    this.maxCount = 128,
    this.limitBytes = 128 * 1024 * 1024,
    this.fileLimitBytes = 20 * 1024 * 1024,
  });
  final EvidenceCaptureBudget budget;
  final int maxCount;
  final int limitBytes;
  final int fileLimitBytes;
  int _count = 0;
  int _bytes = 0;
  final Map<String, int> _files = {};
  int get count => _count;
  int get usedBytes => _bytes;

  /// Audit outputs from external screenshot producers between capabilities.
  /// No link is followed, and previously counted files are never charged twice.
  Future<void> checkDirectory(Directory directory) async {
    if (!directory.existsSync()) return;
    await for (final entry in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entry is! File ||
          !RegExp(
            r'\.(png|jpe?g|webp)$',
            caseSensitive: false,
          ).hasMatch(entry.path)) {
        continue;
      }
      final bytes = entry.lengthSync();
      final previous = _files[entry.absolute.path];
      if (previous == null) {
        reserve(bytes);
      } else if (bytes > previous) {
        final growth = bytes - previous;
        if (bytes > fileLimitBytes || growth > limitBytes - _bytes) {
          throw EvidenceCapacityFailure('screenshot_bytes', limitBytes, _bytes);
        }
        budget.reserveWhole(growth, 'screenshot_run');
        _bytes += growth;
      }
      _files[entry.absolute.path] = bytes;
    }
  }

  void reserve(int bytes) {
    if (bytes < 0) {
      throw ArgumentError.value(bytes, 'bytes');
    }
    if (_count >= maxCount) {
      throw EvidenceCapacityFailure('screenshot_count', maxCount, _count);
    }
    if (bytes > fileLimitBytes) {
      throw EvidenceCapacityFailure('screenshot_file', fileLimitBytes, 0);
    }
    if (bytes > limitBytes - _bytes) {
      throw EvidenceCapacityFailure('screenshot_bytes', limitBytes, _bytes);
    }
    budget.reserveWhole(bytes, 'screenshot_run');
    _count++;
    _bytes += bytes;
  }
}
