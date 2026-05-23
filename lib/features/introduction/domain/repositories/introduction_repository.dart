import '../models/introduction_model.dart';
import '../models/introduction_outbox_delivery.dart';
import '../models/pending_introduction_response.dart';

/// Repository interface for managing introductions.
abstract class IntroductionRepository {
  /// Saves an introduction to the database.
  ///
  /// If an introduction with the same ID already exists, it will be replaced.
  Future<void> saveIntroduction(IntroductionModel intro);

  /// Atomically saves an introduction and its initial durable outbound rows.
  Future<void> saveIntroductionWithOutboxDeliveries(
    IntroductionModel intro,
    List<IntroductionOutboxDelivery> deliveries,
  );

  /// Atomically replaces old same-pair introductions with a new intro,
  /// migrates staged responses from the replaced IDs, and stages outbox rows.
  Future<void> replaceIntroductionWithPendingResponseMigration({
    required IntroductionModel intro,
    required List<IntroductionOutboxDelivery> deliveries,
    required List<String> replacedIntroductionIds,
  });

  /// Atomically saves a local intro response and its outbound fan-out rows.
  Future<bool> saveIntroductionResponseWithOutboxDeliveries({
    required String introductionId,
    required bool isRecipient,
    required IntroductionStatus responseStatus,
    required IntroductionOverallStatus overallStatus,
    required String respondedAt,
    required List<IntroductionOutboxDelivery> deliveries,
  });

  /// Retrieves an introduction by its ID.
  ///
  /// Returns null if no introduction with the given ID exists.
  Future<IntroductionModel?> getIntroduction(String id);

  /// Deletes an introduction by its ID.
  Future<void> deleteIntroduction(String id);

  /// Retrieves all introductions where the user is the recipient.
  Future<List<IntroductionModel>> getIntroductionsByRecipient(
    String recipientId,
  );

  /// Retrieves all introductions where the user is the introduced party.
  Future<List<IntroductionModel>> getIntroductionsByIntroduced(
    String introducedId,
  );

  /// Retrieves all introductions where the user is the introducer.
  Future<List<IntroductionModel>> getIntroductionsByIntroducer(
    String introducerId,
  );

  /// Retrieves introductions for a specific recipient from a specific introducer.
  Future<List<IntroductionModel>> getIntroductionsForRecipientAndIntroducer(
    String recipientId,
    String introducerId,
  );

  /// Updates the recipient's response status.
  Future<bool> updateRecipientStatus(String id, IntroductionStatus status);

  /// Updates the introduced party's response status.
  Future<bool> updateIntroducedStatus(String id, IntroductionStatus status);

  /// Updates the overall introduction status.
  Future<void> updateOverallStatus(String id, IntroductionOverallStatus status);

  /// Retrieves all pending introductions for a user (as recipient or introduced).
  Future<List<IntroductionModel>> getPendingIntroductionsForUser(String peerId);

  /// Returns the count of pending introductions for a user.
  Future<int> countPendingIntroductions(String peerId);

  /// Durably stages an intro response that arrived before the intro row.
  Future<void> savePendingResponse(PendingIntroductionResponse response);

  /// Loads staged intro responses for a single introduction.
  Future<List<PendingIntroductionResponse>> loadPendingResponses(
    String introductionId,
  );

  /// Deletes a single staged intro response after successful replay.
  Future<void> deletePendingResponse(String responseKey);

  /// Upserts one durable outbound intro delivery row.
  Future<void> saveOutboxDelivery(IntroductionOutboxDelivery delivery);

  /// Loads all outbox rows for a single introduction.
  Future<List<IntroductionOutboxDelivery>> loadOutboxDeliveriesForIntroduction(
    String introductionId,
  );

  /// Loads retryable outbound intro delivery rows.
  Future<List<IntroductionOutboxDelivery>> loadRetryableOutboxDeliveries({
    Duration olderThan = const Duration(seconds: 60),
    int limit = 100,
  });

  /// Deletes one durable outbound intro delivery row.
  Future<void> deleteOutboxDelivery(String deliveryId);

  /// Deletes all durable outbound intro delivery rows for an introduction.
  Future<void> deleteOutboxDeliveriesForIntroduction(String introductionId);
}
