import 'dart:convert';

import 'package:flutter_app/core/notifications/canonical_runtime_lease.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';

const String sharedIosNseInboxTransportKey = 'nse_inbox_transport_v1';

const int iosNseInboxTransportSchemaVersion = 1;
const int iosNseInboxMaxRelayMultiaddrs = 8;
const int iosNseInboxMaxRelayMultiaddrBytes = 512;
const int iosNseInboxMaxRelayMultiaddrsBytes = 8192;

/// Exact physical transport material made read-only to the iOS NSE.
///
/// The logical account and opaque binding are comparison facts. Networking
/// always uses [transportPeerId], [transportPrivateKeyBase64], and the exact
/// order-preserving runtime relay list.
final class IosNseInboxTransportSnapshot {
  const IosNseInboxTransportSnapshot({
    required this.opaqueBinding,
    required this.logicalAccountPeerId,
    required this.transportPeerId,
    required this.transportPrivateKeyBase64,
    required this.relayMultiaddrs,
    required this.projectionRevision,
  });

  final String opaqueBinding;
  final String logicalAccountPeerId;
  final String transportPeerId;
  final String transportPrivateKeyBase64;
  final List<String> relayMultiaddrs;
  final int projectionRevision;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': iosNseInboxTransportSchemaVersion,
    'opaqueBinding': opaqueBinding,
    'logicalAccountPeerId': logicalAccountPeerId,
    'transportPeerId': transportPeerId,
    'transportPrivateKeyBase64': transportPrivateKeyBase64,
    'relayMultiaddrs': relayMultiaddrs,
    'projectionRevision': projectionRevision,
  };

  static IosNseInboxTransportSnapshot? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> ||
          decoded.keys.toSet().difference(_transportKeys).isNotEmpty ||
          decoded.keys.length != _transportKeys.length ||
          decoded['schemaVersion'] != iosNseInboxTransportSchemaVersion ||
          !isCanonicalRuntimeOpaqueBinding(decoded['opaqueBinding'])) {
        return null;
      }
      final logicalAccountPeerId = _strictIosNsePeerId(
        decoded['logicalAccountPeerId'],
      );
      final transportPeerId = _strictIosNsePeerId(decoded['transportPeerId']);
      final privateKey = _strictString(decoded['transportPrivateKeyBase64']);
      final revision = decoded['projectionRevision'];
      final relays = _strictRelayList(decoded['relayMultiaddrs']);
      if (logicalAccountPeerId == null ||
          transportPeerId == null ||
          privateKey == null ||
          !_isCanonicalBase64(privateKey) ||
          revision is! int ||
          revision <= 0 ||
          revision > localNotificationLedgerMaxSignedInt64 ||
          relays == null ||
          relays.isEmpty) {
        return null;
      }
      return IosNseInboxTransportSnapshot(
        opaqueBinding: decoded['opaqueBinding']! as String,
        logicalAccountPeerId: logicalAccountPeerId,
        transportPeerId: transportPeerId,
        transportPrivateKeyBase64: privateKey,
        relayMultiaddrs: List<String>.unmodifiable(relays),
        projectionRevision: revision,
      );
    } on Object {
      return null;
    }
  }
}

const Set<String> _transportKeys = <String>{
  'schemaVersion',
  'opaqueBinding',
  'logicalAccountPeerId',
  'transportPeerId',
  'transportPrivateKeyBase64',
  'relayMultiaddrs',
  'projectionRevision',
};

/// The sole Dart writer/retirement owner for `nse_inbox_transport_v1`.
final class IosNseInboxTransportProjection {
  IosNseInboxTransportProjection({required SecureKeyStore store})
    : _store = store;

  final SecureKeyStore _store;
  Future<void> _tail = Future<void>.value();

  Future<IosNseInboxTransportSnapshot> publishAndReadBack({
    required String opaqueBinding,
    required String logicalAccountPeerId,
    required String transportPeerId,
    required String transportPrivateKeyBase64,
    required Iterable<String> relayMultiaddrs,
  }) => _serialize(() async {
    if (!isCanonicalRuntimeOpaqueBinding(opaqueBinding)) {
      throw const FormatException('invalid opaque runtime binding');
    }
    final logical = _requiredIosNsePeerId(
      logicalAccountPeerId,
      'logicalAccountPeerId',
    );
    final transport = _requiredIosNsePeerId(transportPeerId, 'transportPeerId');
    final privateKey = _requiredString(
      transportPrivateKeyBase64,
      'transportPrivateKeyBase64',
    );
    if (!_isCanonicalBase64(privateKey)) {
      throw const FormatException(
        'transport private key is not canonical base64',
      );
    }
    final relays = _canonicalRelayList(relayMultiaddrs);
    final currentBytes = await _store.read(sharedIosNseInboxTransportKey);
    final current = IosNseInboxTransportSnapshot.tryParse(currentBytes);
    final currentRevision = current?.projectionRevision ?? 0;
    if (currentRevision >= localNotificationLedgerMaxSignedInt64) {
      throw StateError('iOS NSE transport projection revision exhausted');
    }
    final snapshot = IosNseInboxTransportSnapshot(
      opaqueBinding: opaqueBinding,
      logicalAccountPeerId: logical,
      transportPeerId: transport,
      transportPrivateKeyBase64: privateKey,
      relayMultiaddrs: relays,
      projectionRevision: currentRevision + 1,
    );
    // A physical key, peer, binding, account, or effective relay change is an
    // authority-generation change. Remove and reread the old private-key
    // document before publishing its replacement so a crash/failure can only
    // leave opaque wake unavailable, never eligible under stale bytes.
    if (currentBytes != null && !_sameTransportAuthority(snapshot, current)) {
      await _retireAssumingSerialized();
    }
    final bytes = jsonEncode(snapshot.toJson());
    await _store.write(sharedIosNseInboxTransportKey, bytes);
    final readBackBytes = await _store.read(sharedIosNseInboxTransportKey);
    final readBack = IosNseInboxTransportSnapshot.tryParse(readBackBytes);
    if (readBackBytes != bytes || !_sameTransport(snapshot, readBack)) {
      await _retireAssumingSerialized();
      throw StateError('iOS NSE transport projection read-back failed');
    }
    return snapshot;
  });

  Future<IosNseInboxTransportSnapshot?> read() => _serialize(
    () async => IosNseInboxTransportSnapshot.tryParse(
      await _store.read(sharedIosNseInboxTransportKey),
    ),
  );

  Future<bool> isBindingQualified({
    required String? opaqueBinding,
    required String? logicalAccountPeerId,
    required String? transportPeerId,
    Iterable<String>? relayMultiaddrs,
  }) => _serialize(() async {
    if (!isCanonicalRuntimeOpaqueBinding(opaqueBinding)) return false;
    final current = IosNseInboxTransportSnapshot.tryParse(
      await _store.read(sharedIosNseInboxTransportKey),
    );
    final logical = _strictIosNsePeerId(logicalAccountPeerId);
    final transport = _strictIosNsePeerId(transportPeerId);
    if (current == null ||
        logical == null ||
        transport == null ||
        current.opaqueBinding != opaqueBinding ||
        current.logicalAccountPeerId != logical ||
        current.transportPeerId != transport) {
      return false;
    }
    if (relayMultiaddrs == null) return true;
    List<String> expected;
    try {
      expected = _canonicalRelayList(relayMultiaddrs);
    } on Object {
      return false;
    }
    return _sameStrings(current.relayMultiaddrs, expected);
  });

  Future<void> retireAndReadBack() => _serialize(_retireAssumingSerialized);

  Future<void> _retireAssumingSerialized() async {
    await _store.delete(sharedIosNseInboxTransportKey);
    if (await _store.read(sharedIosNseInboxTransportKey) != null) {
      throw StateError('iOS NSE transport projection retirement failed');
    }
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

/// Runs an account/role/migration authority mutation only after the shared
/// physical credential has been durably retired. A null projection is the
/// Android/default-off zero-work path.
Future<T> runWithRetiredIosNseTransportAuthority<T>({
  required IosNseInboxTransportProjection? projection,
  required Future<T> Function() mutateAuthority,
}) async {
  await projection?.retireAndReadBack();
  return mutateAuthority();
}

typedef OpaqueWakeConsumerReadBack = Future<bool> Function();

/// The one production platform predicate applied to paired opaque/outcome
/// capability registration. Plan 373 supplies iOS; Android deliberately has no
/// reader until Plan 375 and therefore remains false.
final class OpaqueWakePlatformConsumerReadiness {
  const OpaqueWakePlatformConsumerReadiness({
    required this.admissionEnabled,
    this.readIosConsumer,
    this.readAndroidConsumer,
  });

  final bool admissionEnabled;
  final OpaqueWakeConsumerReadBack? readIosConsumer;
  final OpaqueWakeConsumerReadBack? readAndroidConsumer;

  Future<bool> isReadyFor(String? platform) async {
    if (!admissionEnabled) return false;
    final reader = switch (platform?.trim().toLowerCase()) {
      'ios' => readIosConsumer,
      'android' => readAndroidConsumer,
      _ => null,
    };
    if (reader == null) return false;
    try {
      return await reader();
    } on Object {
      return false;
    }
  }
}

String _requiredString(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty || normalized != value) {
    throw ArgumentError.value(value, name, 'must be non-empty and canonical');
  }
  return normalized;
}

String? _strictString(Object? value) {
  if (value is! String || value.isEmpty || value != value.trim()) return null;
  return value;
}

/// Exact peer-string shape accepted by the iOS credential reader.
///
/// Dart intentionally does not approximate libp2p's multibase parser. The Go
/// bridge remains the peer-identity authority; this boundary enforces the
/// native reader's byte/control/whitespace contract so Dart cannot advertise
/// readiness for projection bytes that the NSE will reject.
bool isNativeCompatibleIosNsePeerId(Object? value) =>
    _strictIosNsePeerId(value) != null;

String _requiredIosNsePeerId(String value, String name) {
  if (!isNativeCompatibleIosNsePeerId(value)) {
    throw ArgumentError.value(value, name, 'invalid iOS NSE peer identifier');
  }
  return value;
}

String? _strictIosNsePeerId(Object? value) {
  if (value is! String ||
      value.isEmpty ||
      value != value.trim() ||
      utf8.encode(value).length > 256 ||
      value.runes.any(
        (rune) =>
            rune <= 0x1f ||
            rune == 0x7f ||
            (rune >= 0x80 && rune <= 0x9f) ||
            _isUnicodeWhitespace(rune),
      )) {
    return null;
  }
  return value;
}

bool _isUnicodeWhitespace(int rune) =>
    rune == 0x20 ||
    (rune >= 0x09 && rune <= 0x0d) ||
    rune == 0x85 ||
    rune == 0xa0 ||
    rune == 0x1680 ||
    (rune >= 0x2000 && rune <= 0x200a) ||
    rune == 0x2028 ||
    rune == 0x2029 ||
    rune == 0x202f ||
    rune == 0x205f ||
    rune == 0x3000;

bool _isCanonicalBase64(String value) {
  try {
    final decoded = base64Decode(value);
    return decoded.length == 64 && base64Encode(decoded) == value;
  } on Object {
    return false;
  }
}

List<String> _canonicalRelayList(Iterable<String> values) {
  final result = <String>[];
  final seen = <String>{};
  var byteCount = 0;
  for (final value in values) {
    final relay = _requiredString(value, 'relayMultiaddrs');
    final relayBytes = utf8.encode(relay).length;
    if (!_isCanonicalRelayMultiaddr(relay) ||
        relayBytes > iosNseInboxMaxRelayMultiaddrBytes) {
      throw const FormatException('invalid relay multiaddr');
    }
    if (!seen.add(relay)) continue;
    byteCount += relayBytes;
    if (result.length >= iosNseInboxMaxRelayMultiaddrs ||
        byteCount > iosNseInboxMaxRelayMultiaddrsBytes) {
      throw const FormatException('relay multiaddr set exceeds bounds');
    }
    result.add(relay);
  }
  if (result.isEmpty) throw const FormatException('relay multiaddrs are empty');
  return List<String>.unmodifiable(result);
}

/// A conservative Dart preflight for the runtime relay addresses. The Go
/// multiaddr parser remains the final network authority, but malformed bytes
/// never qualify capability read-back in Dart.
bool _isCanonicalRelayMultiaddr(String value) {
  if (!value.startsWith('/') ||
      value.endsWith('/') ||
      value.codeUnits.any((unit) => unit < 0x21 || unit > 0x7e)) {
    return false;
  }
  final segments = value.substring(1).split('/');
  if (segments.any((segment) => segment.isEmpty)) return false;
  const hostProtocols = <String>{
    'dns',
    'dns4',
    'dns6',
    'dnsaddr',
    'ip4',
    'ip6',
  };
  if (segments.length < 6 || !hostProtocols.contains(segments.first)) {
    return false;
  }
  final p2pIndex = segments.lastIndexOf('p2p');
  if (p2pIndex < 2 || p2pIndex != segments.length - 2) return false;
  return segments.contains('tcp') || segments.contains('udp');
}

List<String>? _strictRelayList(Object? value) {
  if (value is! List || value.any((element) => element is! String)) return null;
  try {
    final source = value.cast<String>();
    final canonical = _canonicalRelayList(source);
    return _sameStrings(source, canonical) ? canonical : null;
  } on Object {
    return null;
  }
}

bool _sameStrings(Iterable<String> left, Iterable<String> right) {
  final a = left.toList(growable: false);
  final b = right.toList(growable: false);
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

bool _sameTransport(
  IosNseInboxTransportSnapshot left,
  IosNseInboxTransportSnapshot? right,
) =>
    right != null &&
    left.opaqueBinding == right.opaqueBinding &&
    left.logicalAccountPeerId == right.logicalAccountPeerId &&
    left.transportPeerId == right.transportPeerId &&
    left.transportPrivateKeyBase64 == right.transportPrivateKeyBase64 &&
    _sameStrings(left.relayMultiaddrs, right.relayMultiaddrs) &&
    left.projectionRevision == right.projectionRevision;

bool _sameTransportAuthority(
  IosNseInboxTransportSnapshot left,
  IosNseInboxTransportSnapshot? right,
) =>
    right != null &&
    left.opaqueBinding == right.opaqueBinding &&
    left.logicalAccountPeerId == right.logicalAccountPeerId &&
    left.transportPeerId == right.transportPeerId &&
    left.transportPrivateKeyBase64 == right.transportPrivateKeyBase64 &&
    _sameStrings(left.relayMultiaddrs, right.relayMultiaddrs);
