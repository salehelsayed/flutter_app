/// Built-in trust anchors for the SE-41 version file.
library;

import 'version_file_verifier.dart';

// TODO(SE-41 O2): the owner generates k1 and backup k2 offline and pastes
// ONLY the base64 public keys here. While a key is empty it is skipped, so no
// file can verify and the decision stays `none`. Never put a private key in
// the app or the repo.
const String updateCheckK1PublicKeyBase64 = '';
const String updateCheckK2PublicKeyBase64 = '';

// TODO(SE-41 O1): the static host is not set up yet (T3). Placeholder only;
// the `.invalid` TLD can never resolve.
const String updateCheckVersionFileUrl =
    'https://update-check.invalid/mknoon/version.json';

/// The ranked built-in keys: k1 rank 1, k2 rank 2. Empty placeholders are
/// left out.
List<TrustedVersionKey> builtInVersionKeys() => [
  if (updateCheckK1PublicKeyBase64.isNotEmpty)
    TrustedVersionKey.fromBase64(
      keyId: 'k1',
      rank: 1,
      publicKeyBase64: updateCheckK1PublicKeyBase64,
    ),
  if (updateCheckK2PublicKeyBase64.isNotEmpty)
    TrustedVersionKey.fromBase64(
      keyId: 'k2',
      rank: 2,
      publicKeyBase64: updateCheckK2PublicKeyBase64,
    ),
];
