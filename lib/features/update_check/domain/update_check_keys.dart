/// Built-in trust anchors for the SE-41 version file.
library;

import 'version_file_verifier.dart';

// SE-41 O2: the owner generated k1 and backup k2 offline (2026-10-11). Only
// the base64 public keys live here; the private keys never enter the app or
// the repo. k2 is for a k1 compromise or a planned rotation only: once a k2
// file is accepted, k1 is never trusted again (see the runbook).
const String updateCheckK1PublicKeyBase64 =
    'iB9ZHd/taLzLSsxFbbC0mX/wzAmzps0b9uH0KVwI/sw=';
const String updateCheckK2PublicKeyBase64 =
    'tG2VAI6qIJtUTKe2T09c+K50Ks6pqjJDuVFkiDasXEg=';

// SE-41 O1: the static host (Caddy on 51.20.131.205, no access log). Every
// shipped build fetches this exact URL for good, so never change it casually.
const String updateCheckVersionFileUrl =
    'https://updates.mknoon.xyz/mknoon/version.json';

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
