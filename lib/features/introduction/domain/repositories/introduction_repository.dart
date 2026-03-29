import '../models/introduction_model.dart';

/// Repository interface for managing introductions.
abstract class IntroductionRepository {
  /// Saves an introduction to the database.
  ///
  /// If an introduction with the same ID already exists, it will be replaced.
  Future<void> saveIntroduction(IntroductionModel intro);

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
  Future<void> updateRecipientStatus(String id, IntroductionStatus status);

  /// Updates the introduced party's response status.
  Future<void> updateIntroducedStatus(String id, IntroductionStatus status);

  /// Updates the overall introduction status.
  Future<void> updateOverallStatus(String id, IntroductionOverallStatus status);

  /// Retrieves all pending introductions for a user (as recipient or introduced).
  Future<List<IntroductionModel>> getPendingIntroductionsForUser(String peerId);

  /// Returns the count of pending introductions for a user.
  Future<int> countPendingIntroductions(String peerId);
}
