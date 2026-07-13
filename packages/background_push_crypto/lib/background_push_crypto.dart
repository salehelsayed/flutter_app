import 'dart:convert';

import 'package:flutter/services.dart';

/// Minimal Android-only bridge used by the Firebase Messaging headless engine.
///
/// This channel deliberately exposes only stateless payload decryption and
/// signature verification. Node lifecycle, event callbacks, transport, and
/// persistence stay owned by the app's normal Go bridge, so registering this
/// plugin on a background engine cannot replace the foreground callback.
class BackgroundPushCrypto {
  const BackgroundPushCrypto({
    MethodChannel channel = const MethodChannel(channelName),
  }) : _channel = channel;

  static const String channelName = 'com.mknoon/background_push_crypto';

  final MethodChannel _channel;

  Future<Map<String, dynamic>> decryptMessage({
    required String secretKey,
    required String kem,
    required String ciphertext,
    required String nonce,
  }) async {
    final response = await _channel.invokeMethod<String>(
      'decryptMessage',
      jsonEncode(<String, String>{
        'secretKey': secretKey,
        'kem': kem,
        'ciphertext': ciphertext,
        'nonce': nonce,
      }),
    );
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> decryptGroup({
    required String groupKey,
    required String ciphertext,
    required String nonce,
  }) async {
    final response = await _channel.invokeMethod<String>(
      'decryptGroup',
      jsonEncode(<String, String>{
        'groupKey': groupKey,
        'ciphertext': ciphertext,
        'nonce': nonce,
      }),
    );
    return _decodeResponse(response);
  }

  /// Verifies an Ed25519 signature without depending on the foreground Go
  /// MethodChannel. This is stateless and safe to register in FlutterFire's
  /// headless engine alongside the decrypt methods.
  Future<Map<String, dynamic>> verifyPayload({
    required String publicKey,
    required String data,
    required String signature,
  }) async {
    final response = await _channel.invokeMethod<String>(
      'verifyPayload',
      jsonEncode(<String, String>{
        'publicKey': publicKey,
        'data': data,
        'signature': signature,
      }),
    );
    return _decodeResponse(response);
  }

  Map<String, dynamic> _decodeResponse(String? response) {
    if (response == null) {
      throw const FormatException('Background crypto returned no response.');
    }
    final decoded = jsonDecode(response);
    if (decoded is! Map) {
      throw const FormatException(
        'Background crypto response must be a JSON object.',
      );
    }
    return decoded.cast<String, dynamic>();
  }
}
