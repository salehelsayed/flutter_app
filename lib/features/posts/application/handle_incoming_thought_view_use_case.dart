import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/domain/models/post_view_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/thought_view_receipt.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';
import 'package:flutter_app/features/posts/domain/repositories/thought_view_repository.dart';

/// Attributes only a decrypted receipt from the authenticated, known viewer.
/// The repository atomically requires our live thought and original recipient.
Future<bool> handleIncomingThoughtView({
  required ChatMessage message,
  required String localPeerId,
  required PostRepository postRepo,
  required ContactRepository contactRepo,
  required Bridge bridge,
  required String ownMlKemSecretKey,
  DateTime Function()? nowProvider,
}) async {
  if (postRepo is! ThoughtViewRepository || localPeerId.isEmpty) return false;
  final envelope = await PostViewEnvelope.fromEncryptedJson(
    raw: message.content,
    authenticatedSender: message.from,
    bridge: bridge,
    ownMlKemSecretKey: ownMlKemSecretKey,
  );
  if (envelope == null || message.from == localPeerId) return false;
  final contact = await contactRepo.getContact(message.from);
  if (contact == null || contact.isBlocked || contact.isArchived) return false;
  final now = (nowProvider ?? DateTime.now)().toUtc();
  final viewed = DateTime.tryParse(envelope.receipt.viewedAt)?.toUtc();
  if (viewed == null) return false;
  return (postRepo as ThoughtViewRepository).recordIncomingThoughtView(
    receipt: ThoughtViewReceipt(
      postId: envelope.receipt.postId,
      viewerPeerId: message.from,
      viewedAt: (viewed.isAfter(now) ? now : viewed).toIso8601String(),
    ),
    localPeerId: localPeerId,
    nowIso: now.toIso8601String(),
  );
}
