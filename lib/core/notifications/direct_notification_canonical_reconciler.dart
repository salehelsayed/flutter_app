import 'package:flutter_app/core/notifications/direct_notification_presentation_coordinator.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';

typedef DirectNotificationCanonicalContentResolver =
    Future<DirectNotificationCanonicalContentDecision> Function(
      String peerId,
      ConversationNotificationContentMetadata metadata,
    );
typedef DirectNotificationCanonicalReplacementLoader =
    Future<CanonicalConversationNotificationReplacement?> Function(
      String peerId,
      ConversationNotificationContentMetadata currentMetadata,
    );

enum DirectNotificationCanonicalContentDecision { keep, retire, unknown }

final class DirectNotificationCanonicalReconciliationRetryable
    implements Exception {
  const DirectNotificationCanonicalReconciliationRetryable();
}

/// Rebuilds or retires one direct stable card under both the in-process peer
/// lane and the durable cross-isolate generation CAS.
final class DirectNotificationCanonicalReconciler {
  DirectNotificationCanonicalReconciler({
    required DirectNotificationPresentationCoordinator coordinator,
    required ConversationNotificationGenerationCancellation
    generationCancellation,
    required ConversationNotificationGenerationReplacement
    generationReplacement,
    required DirectNotificationCanonicalContentResolver
    isCurrentContentCanonical,
    required DirectNotificationCanonicalReplacementLoader loadReplacement,
    this.maxGenerationAttempts = 3,
  }) : _coordinator = coordinator,
       _generationCancellation = generationCancellation,
       _generationReplacement = generationReplacement,
       _isCurrentContentCanonical = isCurrentContentCanonical,
       _loadReplacement = loadReplacement {
    if (maxGenerationAttempts <= 0) {
      throw ArgumentError.value(
        maxGenerationAttempts,
        'maxGenerationAttempts',
        'must be positive',
      );
    }
  }

  final DirectNotificationPresentationCoordinator _coordinator;
  final ConversationNotificationGenerationCancellation _generationCancellation;
  final ConversationNotificationGenerationReplacement _generationReplacement;
  final DirectNotificationCanonicalContentResolver _isCurrentContentCanonical;
  final DirectNotificationCanonicalReplacementLoader _loadReplacement;
  final int maxGenerationAttempts;

  Future<void> reconcile(String rawPeerId) {
    final peerId = rawPeerId.trim();
    if (peerId.isEmpty) {
      throw ArgumentError.value(rawPeerId, 'peerId', 'must not be empty');
    }
    return _coordinator.runForPeer(peerId, () => _reconcileInsideKey(peerId));
  }

  Future<void> _reconcileInsideKey(String peerId) async {
    for (var attempt = 0; attempt < maxGenerationAttempts; attempt++) {
      final metadata = await _generationCancellation
          .lookupConversationNotificationContentMetadata(peerId);
      if (metadata == null) return;
      final generation = metadata.generation?.trim();
      if (generation == null || generation.isEmpty) return;
      final decision = await _isCurrentContentCanonical(peerId, metadata);
      if (decision == DirectNotificationCanonicalContentDecision.unknown) {
        throw const DirectNotificationCanonicalReconciliationRetryable();
      }
      final replacement = await _loadReplacement(peerId, metadata);
      if (decision == DirectNotificationCanonicalContentDecision.keep &&
          replacement == null) {
        throw const DirectNotificationCanonicalReconciliationRetryable();
      }
      final mutated = replacement == null
          ? await _generationCancellation
                .cancelConversationNotificationGeneration(peerId, generation)
          : await _generationReplacement
                .replaceConversationNotificationGeneration(
                  peerId,
                  generation,
                  replacement,
                );
      if (mutated) return;
    }
    throw const DirectNotificationCanonicalReconciliationRetryable();
  }
}
