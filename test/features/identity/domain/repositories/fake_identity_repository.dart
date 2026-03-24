import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

/// In-memory [IdentityRepository] for tests.
///
/// Stores a single identity, tracks call counts.
class FakeIdentityRepository implements IdentityRepository {
  IdentityModel? _identity;

  /// Convenience factory for creating a test identity with sensible defaults.
  static IdentityModel makeIdentity({
    String peerId = 'my-peer-id',
    String publicKey = 'pk-test',
    String privateKey = 'sk-test',
    String mnemonic12 = 'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
    String? mlKemPublicKey,
    String? mlKemSecretKey,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    return IdentityModel(
      peerId: peerId,
      publicKey: publicKey,
      privateKey: privateKey,
      mnemonic12: mnemonic12,
      mlKemPublicKey: mlKemPublicKey,
      mlKemSecretKey: mlKemSecretKey,
      createdAt: now,
      updatedAt: now,
    );
  }

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
