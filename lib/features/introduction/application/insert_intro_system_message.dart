import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:uuid/uuid.dart';

/// Inserts a system message into the conversation history.
///
/// System messages use `transport = 'system'` to distinguish them from
/// regular chat messages. The conversation screen renders these as centered
/// muted bubbles via [IntroSystemMessage] instead of [LetterCard].
///
/// Three system message types for introductions:
/// 1. Introducer sends: "You introduced [name] to [recipient]"
/// 2. Recipient or introduced party receives a role-aware intro summary.
/// 3. Mutual acceptance: "You and [name] are now connected — introduced by X"
Future<void> insertIntroSystemMessage({
  required MessageRepository messageRepo,
  required String contactPeerId,
  required String text,
  required String ownPeerId,
}) async {
  final now = DateTime.now().toUtc().toIso8601String();
  final id = const Uuid().v4();

  emitFlowEvent(
    layer: 'UC',
    event: 'INSERT_INTRO_SYSTEM_MESSAGE',
    details: {
      'contactPeerId': contactPeerId.length > 10
          ? contactPeerId.substring(0, 10)
          : contactPeerId,
      'text': text,
    },
  );

  final message = ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: ownPeerId,
    text: text,
    timestamp: now,
    status: 'delivered',
    isIncoming: false,
    createdAt: now,
    transport: 'system',
  );

  await messageRepo.saveMessage(message);
}
