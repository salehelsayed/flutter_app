import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Whether flow event logging is enabled.
/// Defaults to kDebugMode — disabled in profile/release builds.
bool flowEventLoggingEnabled = kDebugMode;

typedef FlowEventSink = void Function(Map<String, dynamic> payload);

FlowEventSink? _flowEventTestSink;
const _redacted = '[redacted]';

@visibleForTesting
void debugSetFlowEventSink(FlowEventSink? sink) {
  _flowEventTestSink = sink;
}

Map<String, dynamic> sanitizeFlowEventDetails(Map<String, dynamic> details) {
  return details.map(
    (key, value) => MapEntry(key, _sanitizeDiagnosticValue(key, value)),
  );
}

String sanitizeDiagnosticText(Object? value) {
  if (value == null) return '';
  return _redactSensitiveText(value.toString());
}

Object? _sanitizeDiagnosticValue(String key, Object? value) {
  if (_isSensitiveKey(key)) return _redacted;
  if (value is String) {
    if (_isPeerIdKey(key) && value.length > 12) return _redacted;
    return _redactSensitiveText(value);
  }
  if (value is Map) {
    return value.map(
      (nestedKey, nestedValue) => MapEntry(
        nestedKey.toString(),
        _sanitizeDiagnosticValue(nestedKey.toString(), nestedValue),
      ),
    );
  }
  if (value is Iterable) {
    return value
        .map((entry) => _sanitizeDiagnosticValue(key, entry))
        .toList(growable: false);
  }
  return value;
}

bool _isSensitiveKey(String key) {
  final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  const sensitiveFragments = [
    'privatekey',
    'secretkey',
    'secret',
    'mnemonic',
    'ciphertext',
    'plaintext',
    'signature',
    'nonce',
    'groupkey',
    'keymaterial',
    'publickey',
    'multiaddr',
    'relayaddresses',
    'listenaddresses',
    'circuitaddresses',
  ];
  return sensitiveFragments.any(normalized.contains);
}

bool _isPeerIdKey(String key) {
  final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return normalized == 'peerid' || normalized.endsWith('peerid');
}

String _redactSensitiveText(String value) {
  final withoutMultiaddrs = value.replaceAll(
    RegExp(
      r'/(?:ip4|ip6|dns|dns4|dns6|tcp|udp|quic-v1|ws|wss|p2p-circuit|p2p)(?:/[^\s,\]\)}"]+)+',
      caseSensitive: false,
    ),
    '[redacted:multiaddr]',
  );
  return withoutMultiaddrs.replaceAllMapped(
    RegExp(
      r'\b(privateKeyHex|privateKey|secretKey|mlKemSecretKey|mnemonic12?|ciphertext|plaintext|signature|nonce|groupKey|keyMaterial)\b\s*[:=]\s*([^,\s}\]]+)',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}=$_redacted',
  );
}

void emitFlowEvent({
  required String layer,
  required String event,
  required Map<String, dynamic> details,
}) {
  final sanitizedDetails = sanitizeFlowEventDetails(details);
  final payload = {
    'ts': DateTime.now().toUtc().toIso8601String(),
    'milestone': 'M1_IDENTITY_INIT',
    'layer': layer,
    'event': event,
    'details': sanitizedDetails,
  };
  _flowEventTestSink?.call(payload);

  if (!flowEventLoggingEnabled) return;
  debugPrint('[FLOW] ${jsonEncode(payload)}');
}
