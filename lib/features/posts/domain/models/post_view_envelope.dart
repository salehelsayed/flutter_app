import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/thought_lifetime.dart';
import 'package:flutter_app/features/posts/domain/models/thought_view_receipt.dart';

/// An additive encrypted first-view receipt. Older peers can ignore its type.
class PostViewEnvelope {
  static const type = 'post_view';

  const PostViewEnvelope({
    required this.eventId,
    required this.receipt,
    required this.postCreatedAt,
  });

  final String eventId;
  final ThoughtViewReceipt receipt;
  final DateTime postCreatedAt;

  Future<String> toEncryptedJson({
    required Bridge bridge,
    required String recipientMlKemPublicKey,
  }) async {
    if (recipientMlKemPublicKey.isEmpty) {
      throw StateError('Thought view encryption key is unavailable.');
    }
    final result = await callEncryptMessage(
      bridge: bridge,
      recipientMlKemPublicKey: recipientMlKemPublicKey,
      plaintext: jsonEncode({
        ...receipt.toMap(),
        'post_created_at': postCreatedAt.toUtc().toIso8601String(),
      }),
    );
    final kem = result['kem'];
    final ciphertext = result['ciphertext'];
    final nonce = result['nonce'];
    if (result['ok'] != true ||
        kem is! String ||
        kem.isEmpty ||
        ciphertext is! String ||
        ciphertext.isEmpty ||
        nonce is! String ||
        nonce.isEmpty) {
      throw StateError('Thought view encryption failed.');
    }
    return jsonEncode({
      'type': type,
      'version': '2',
      'event_id': eventId,
      'sender_peer_id': receipt.viewerPeerId,
      'post_id': receipt.postId,
      'created_at': receipt.viewedAt,
      'post_created_at': postCreatedAt.toUtc().toIso8601String(),
      'encrypted': {'kem': kem, 'ciphertext': ciphertext, 'nonce': nonce},
    });
  }

  /// Only used on this device's already-owned encrypted outbox envelope.
  static DateTime? queuedExpiry(String raw) {
    final outer = _parseOuter(raw);
    final created = DateTime.tryParse(
      outer?['post_created_at'] as String? ?? '',
    );
    return created == null ? null : ThoughtLifetime.expiresAt(created);
  }

  static Future<PostViewEnvelope?> fromEncryptedJson({
    required String raw,
    required String authenticatedSender,
    required Bridge bridge,
    required String ownMlKemSecretKey,
  }) async {
    try {
      final outer = _parseOuter(raw);
      if (outer == null || outer['sender_peer_id'] != authenticatedSender) {
        return null;
      }
      final encrypted = outer['encrypted'] as Map<String, dynamic>;
      final result = await callDecryptMessage(
        bridge: bridge,
        ownMlKemSecretKey: ownMlKemSecretKey,
        kem: encrypted['kem'] as String,
        ciphertext: encrypted['ciphertext'] as String,
        nonce: encrypted['nonce'] as String,
      );
      if (result['ok'] != true) return null;
      final inner =
          jsonDecode(result['plaintext'] as String) as Map<String, dynamic>;
      if (inner['post_id'] != outer['post_id'] ||
          inner['viewer_peer_id'] != authenticatedSender ||
          inner['viewed_at'] != outer['created_at'] ||
          inner['post_created_at'] != outer['post_created_at']) {
        return null;
      }
      return PostViewEnvelope(
        eventId: outer['event_id'] as String,
        receipt: ThoughtViewReceipt.fromMap(inner),
        postCreatedAt: DateTime.parse(
          inner['post_created_at'] as String,
        ).toUtc(),
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _parseOuter(String raw) {
    try {
      final outer = jsonDecode(raw) as Map<String, dynamic>;
      if (outer['type'] != type || outer['version'] != '2') return null;
      for (final field in [
        'event_id',
        'sender_peer_id',
        'post_id',
        'created_at',
        'post_created_at',
      ]) {
        if (outer[field] is! String || (outer[field] as String).isEmpty)
          return null;
      }
      if (DateTime.tryParse(outer['created_at'] as String) == null ||
          DateTime.tryParse(outer['post_created_at'] as String) == null)
        return null;
      final encrypted = outer['encrypted'] as Map<String, dynamic>;
      for (final field in ['kem', 'ciphertext', 'nonce']) {
        if (encrypted[field] is! String || (encrypted[field] as String).isEmpty)
          return null;
      }
      return outer;
    } catch (_) {
      return null;
    }
  }
}
