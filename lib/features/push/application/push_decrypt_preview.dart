import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/push/application/background_push_notification_fallback.dart';

typedef DecryptOneToOnePush =
    Future<String> Function({
      required String kem,
      required String ciphertext,
      required String nonce,
    });

typedef DecryptGroupPush =
    Future<String> Function({
      required String groupId,
      required int keyEpoch,
      required String ciphertext,
      required String nonce,
    });

Future<BackgroundPushNotificationFallback> resolveBackgroundPushNotification(
  RemoteMessage message, {
  DecryptOneToOnePush? decryptOneToOne,
  DecryptGroupPush? decryptGroup,
}) async {
  final fallback = buildBackgroundPushFallbackNotification(message);
  final data = message.data;
  final type = _trimToNull(data['type']?.toString());

  if (type == 'new_message') {
    return _resolveOneToOnePreview(
      data,
      fallback,
      decryptOneToOne: decryptOneToOne,
    );
  }
  if (type == 'group_message') {
    return _resolveGroupPreview(data, fallback, decryptGroup: decryptGroup);
  }

  return fallback;
}

Future<BackgroundPushNotificationFallback> _resolveOneToOnePreview(
  Map<String, dynamic> data,
  BackgroundPushNotificationFallback fallback, {
  required DecryptOneToOnePush? decryptOneToOne,
}) async {
  final kem = _trimToNull(data['kem']?.toString());
  final ciphertext = _trimToNull(data['ciphertext']?.toString());
  final nonce = _trimToNull(data['nonce']?.toString());
  if (decryptOneToOne == null ||
      kem == null ||
      ciphertext == null ||
      nonce == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_ANDROID_DATA_DECRYPT_FAIL',
      details: {'kind': 'chat', 'reason': 'missing_chat_decrypt_input'},
    );
    return fallback;
  }

  try {
    final plaintext = await decryptOneToOne(
      kem: kem,
      ciphertext: ciphertext,
      nonce: nonce,
    );
    final payload = MessagePayload.fromDecryptedJson(plaintext);
    if (payload == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PUSH_ANDROID_DATA_DECRYPT_FAIL',
        details: {'kind': 'chat', 'reason': 'invalid_chat_plaintext'},
      );
      return fallback;
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_ANDROID_DATA_DECRYPT_OK',
      details: {'kind': 'chat'},
    );
    return BackgroundPushNotificationFallback(
      title: _trimToNull(payload.senderUsername) ?? fallback.title,
      body: pushPreviewBody(payload.text, payload.media),
      payload: fallback.payload,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_ANDROID_DATA_DECRYPT_FAIL',
      details: {'kind': 'chat', 'reason': 'chat_decrypt_error'},
    );
    return fallback;
  }
}

Future<BackgroundPushNotificationFallback> _resolveGroupPreview(
  Map<String, dynamic> data,
  BackgroundPushNotificationFallback fallback, {
  required DecryptGroupPush? decryptGroup,
}) async {
  final groupId = _trimToNull(data['groupId']?.toString());
  final ciphertext = _trimToNull(data['ciphertext']?.toString());
  final nonce = _trimToNull(data['nonce']?.toString());
  final keyEpoch = int.tryParse(data['keyEpoch']?.toString() ?? '');
  if (decryptGroup == null ||
      groupId == null ||
      keyEpoch == null ||
      ciphertext == null ||
      nonce == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_ANDROID_DATA_DECRYPT_FAIL',
      details: {'kind': 'group', 'reason': 'missing_group_decrypt_input'},
    );
    return fallback;
  }

  try {
    final plaintext = await decryptGroup(
      groupId: groupId,
      keyEpoch: keyEpoch,
      ciphertext: ciphertext,
      nonce: nonce,
    );
    final payload = jsonDecode(plaintext) as Map<String, dynamic>;
    final senderUsername = _trimToNull(payload['senderUsername']?.toString());
    final text = payload['text']?.toString() ?? '';
    final media = payload['media'] as List<dynamic>?;
    final preview = pushPreviewBody(text, media);
    final body = senderUsername == null ? preview : '$senderUsername: $preview';

    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_ANDROID_DATA_DECRYPT_OK',
      details: {'kind': 'group'},
    );
    return BackgroundPushNotificationFallback(
      title: fallback.title,
      body: body,
      payload: fallback.payload,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_ANDROID_DATA_DECRYPT_FAIL',
      details: {'kind': 'group', 'reason': 'group_decrypt_error'},
    );
    return fallback;
  }
}

String pushPreviewBody(String text, List<dynamic>? media) {
  final trimmed = text.trim();
  if (trimmed.isNotEmpty) {
    return _capPreview(trimmed);
  }
  if (media == null || media.isEmpty) {
    return 'Message';
  }

  final types = media
      .whereType<Map>()
      .map((item) => item['mediaType']?.toString())
      .whereType<String>()
      .toList();
  if (types.isEmpty) {
    return 'Media';
  }
  final first = types.first;
  if (types.any((type) => type != first)) {
    return 'Media';
  }
  return switch (first) {
    'image' => 'Photo',
    'video' => 'Video',
    'audio' => 'Voice message',
    'file' => 'File',
    _ => 'Media',
  };
}

String _capPreview(String text, {int maxScalars = 140}) {
  final scalars = text.runes.toList();
  if (scalars.length <= maxScalars) {
    return text;
  }
  return String.fromCharCodes(scalars.take(maxScalars));
}

String? _trimToNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}
