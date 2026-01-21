import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

/// Repository interface for identity persistence operations.
///
/// This abstract class defines the contract for storing and retrieving
/// the user's identity from the local database. There is at most one
/// active identity at any time.
abstract class IdentityRepository {
  /// Loads the current identity from persistent storage.
  ///
  /// Returns the [IdentityModel] if an identity exists in the database,
  /// or `null` if no identity has been created or restored yet.
  ///
  /// This method is typically called at app startup to determine
  /// whether to show the onboarding flow or proceed to the main app.
  Future<IdentityModel?> loadIdentity();

  /// Saves the given identity to persistent storage.
  ///
  /// The [identity] parameter contains all identity data including
  /// the peer ID, keys, mnemonic, and timestamps.
  ///
  /// This method performs an upsert operation: if an identity already
  /// exists, it will be replaced with the new one. There is only ever
  /// one active identity row (id = 1) in the database.
  ///
  /// Throws an exception if the save operation fails.
  Future<void> saveIdentity(IdentityModel identity);
}
