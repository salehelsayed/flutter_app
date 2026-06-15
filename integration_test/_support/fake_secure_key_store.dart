/// Canonical shared [FakeSecureKeyStore] for integration_test harnesses.
///
/// This is the single source of truth for an in-memory [SecureKeyStore] used
/// across the `integration_test/` suite. It re-exports the already-canonical
/// fake that lives under `test/core/secure_storage/fake_secure_key_store.dart`
/// so there is exactly ONE implementation in the repo (no fork).
///
/// Consumers that previously declared an inline `_FakeSecureKeyStore` (a plain
/// 4-method in-memory map) should import this file and use [FakeSecureKeyStore].
///
/// NOTE: The disk-persistence variant in `group_multi_device_real_harness.dart`
/// (`_FakeSecureKeyStore({String? dbName})` backed by a JSON file) is NOT a
/// simple in-memory copy — it carries harness-local persistence behavior and is
/// out of scope for this re-export.
library;

export 'package:flutter_app/core/secure_storage/secure_key_store.dart'
    show SecureKeyStore;
export '../../test/core/secure_storage/fake_secure_key_store.dart'
    show FakeSecureKeyStore;
