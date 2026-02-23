import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

/// In-memory [IdentityRepository] for tests.
///
/// Stores a single identity, tracks call counts.
class FakeIdentityRepository implements IdentityRepository {
  IdentityModel? _identity;

  // Call tracking
  int loadIdentityCallCount = 0;
  int saveIdentityCallCount = 0;

  // Last arguments
  IdentityModel? lastSavedIdentity;

  /// Seed identity for testing.
  void seed(IdentityModel? identity) {
    _identity = identity;
  }

  @override
  Future<IdentityModel?> loadIdentity() async {
    loadIdentityCallCount++;
    return _identity;
  }

  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    saveIdentityCallCount++;
    lastSavedIdentity = identity;
    _identity = identity;
  }
}
