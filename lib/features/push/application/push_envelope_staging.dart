import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/notifications/app_group_path_channel.dart';
import 'package:path_provider/path_provider.dart';

const String pushEnvelopeStagingDirectoryName = 'PushEnvelopeStaging';
const String _pushEnvelopeFilePrefix = 'nonce-v1-';
const String _pushEnvelopeFileExtension = '.json';
const String _hexDigits = '0123456789abcdef';

class StagedPushEnvelope {
  final String kind;
  final String kem;
  final String ciphertext;
  final String nonce;
  final String senderPeerId;
  final String? messageId;
  final String? eventId;
  final String? action;
  final String? targetMessageId;
  final bool identityResolutionPending;
  final int receivedAtMs;

  const StagedPushEnvelope({
    required this.kind,
    required this.kem,
    required this.ciphertext,
    required this.nonce,
    required this.senderPeerId,
    required this.messageId,
    this.eventId,
    this.action,
    this.targetMessageId,
    this.identityResolutionPending = false,
    required this.receivedAtMs,
  });

  String get id => nonce;

  Map<String, dynamic> toJson() {
    return {
      'kind': kind,
      'kem': kem,
      'ciphertext': ciphertext,
      'nonce': nonce,
      'senderPeerId': senderPeerId,
      'messageId': messageId,
      if (eventId != null) 'eventId': eventId,
      if (action != null) 'action': action,
      if (targetMessageId != null) 'targetMessageId': targetMessageId,
      if (identityResolutionPending)
        'identityResolutionPending': identityResolutionPending,
      'receivedAtMs': receivedAtMs,
    };
  }

  factory StagedPushEnvelope.fromJson(Map<String, dynamic> json) {
    String requiredString(String key) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) {
        return value;
      }
      throw FormatException('missing staged push envelope field $key');
    }

    final receivedAtMs = json['receivedAtMs'];
    if (receivedAtMs is! num) {
      throw const FormatException('missing staged push envelope receivedAtMs');
    }

    final messageId = json['messageId'];
    return StagedPushEnvelope(
      kind: requiredString('kind'),
      kem: requiredString('kem'),
      ciphertext: requiredString('ciphertext'),
      nonce: requiredString('nonce'),
      senderPeerId: requiredString('senderPeerId'),
      messageId: messageId is String && messageId.trim().isNotEmpty
          ? messageId
          : null,
      eventId: _optionalString(json['eventId']),
      action: _optionalString(json['action']),
      targetMessageId: _optionalString(json['targetMessageId']),
      identityResolutionPending: json['identityResolutionPending'] == true,
      receivedAtMs: receivedAtMs.toInt(),
    );
  }
}

String? _optionalString(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return value;
}

abstract class PushEnvelopeStagingStore {
  Future<void> stage(StagedPushEnvelope entry);

  Future<List<StagedPushEnvelope>> readAll();

  Future<void> clear(String id);

  Future<void> prune();
}

class FilePushEnvelopeStagingStore implements PushEnvelopeStagingStore {
  final Directory directory;
  final DateTime Function() now;
  final Duration ttl;
  final int maxEntries;
  final Duration malformedRetryWindow;

  FilePushEnvelopeStagingStore({
    required this.directory,
    DateTime Function()? now,
    this.ttl = const Duration(hours: 48),
    this.maxEntries = 64,
    this.malformedRetryWindow = const Duration(seconds: 2),
  }) : now = now ?? DateTime.now;

  static Future<FilePushEnvelopeStagingStore> openDefault({
    DateTime Function()? now,
    Duration ttl = const Duration(hours: 48),
    int maxEntries = 64,
    Duration malformedRetryWindow = const Duration(seconds: 2),
    AppGroupPathChannel? appGroupPathChannel,
  }) async {
    final directory = await resolvePushEnvelopeStagingDirectory(
      appGroupPathChannel: appGroupPathChannel,
    );
    return FilePushEnvelopeStagingStore(
      directory: directory,
      now: now,
      ttl: ttl,
      maxEntries: maxEntries,
      malformedRetryWindow: malformedRetryWindow,
    );
  }

  @override
  Future<void> stage(StagedPushEnvelope entry) async {
    await directory.create(recursive: true);
    final target = _fileForId(entry.id);
    final temp = File(
      '${target.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    await temp.writeAsString(jsonEncode(entry.toJson()), flush: true);
    try {
      await temp.rename(target.path);
    } on FileSystemException {
      if (await target.exists()) {
        await target.delete();
      }
      await temp.rename(target.path);
    }
    await prune();
  }

  @override
  Future<List<StagedPushEnvelope>> readAll() async {
    await prune();
    return _readEntries();
  }

  @override
  Future<void> clear(String id) async {
    final file = _fileForId(id);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<void> prune() async {
    await directory.create(recursive: true);
    final entries = await _readEntries();
    final nowMs = now().millisecondsSinceEpoch;
    final expired = entries
        .where((entry) {
          return nowMs - entry.receivedAtMs > ttl.inMilliseconds;
        })
        .toList(growable: false);
    for (final entry in expired) {
      await clear(entry.id);
    }

    final fresh = entries.where((entry) => !expired.contains(entry)).toList()
      ..sort(_compareEntry);
    final overflowCount = fresh.length - maxEntries;
    if (overflowCount > 0) {
      for (final entry in fresh.take(overflowCount)) {
        await clear(entry.id);
      }
    }
  }

  Future<List<StagedPushEnvelope>> _readEntries() async {
    if (!await directory.exists()) {
      return const [];
    }
    final files = await directory
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();
    final entries = <StagedPushEnvelope>[];
    for (final file in files) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('staged push envelope root is not map');
        }
        entries.add(StagedPushEnvelope.fromJson(decoded));
      } catch (_) {
        await _clearMalformedIfAged(file);
      }
    }
    entries.sort(_compareEntry);
    return entries;
  }

  Future<void> _clearMalformedIfAged(File file) async {
    try {
      final modifiedAt = await file.lastModified();
      final age = now().difference(modifiedAt);
      if (age > malformedRetryWindow) {
        await file.delete();
      }
    } catch (_) {
      // Best effort cleanup only; a later read/prune pass will retry.
    }
  }

  File _fileForId(String id) {
    return File(
      '${directory.path}${Platform.pathSeparator}'
      '${pushEnvelopeStagingFileNameForNonce(id)}',
    );
  }

  int _compareEntry(StagedPushEnvelope a, StagedPushEnvelope b) {
    final ts = a.receivedAtMs.compareTo(b.receivedAtMs);
    if (ts != 0) return ts;
    return a.id.compareTo(b.id);
  }
}

String pushEnvelopeStagingFileNameForNonce(String nonce) {
  return '$_pushEnvelopeFilePrefix${_hexUtf8(nonce)}'
      '$_pushEnvelopeFileExtension';
}

String _hexUtf8(String value) {
  final bytes = utf8.encode(value);
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer
      ..write(_hexDigits[(byte >> 4) & 0x0f])
      ..write(_hexDigits[byte & 0x0f]);
  }
  return buffer.toString();
}

Future<Directory> resolvePushEnvelopeStagingDirectory({
  AppGroupPathChannel? appGroupPathChannel,
}) async {
  final appGroupPath = await (appGroupPathChannel ?? AppGroupPathChannel())
      .containerPath();
  if (appGroupPath != null && appGroupPath.trim().isNotEmpty) {
    return Directory(
      '$appGroupPath${Platform.pathSeparator}$pushEnvelopeStagingDirectoryName',
    );
  }
  final supportDir = await getApplicationSupportDirectory();
  return Directory(
    '${supportDir.path}${Platform.pathSeparator}$pushEnvelopeStagingDirectoryName',
  );
}
