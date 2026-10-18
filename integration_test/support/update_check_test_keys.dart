// Deterministic SE41 TEST keys for host drivers and Flutter fixture tests.
// Never import this file from lib/ or ship these private fixtures in an app.

import 'dart:typed_data';
import 'package:pinenacl/ed25519.dart' as nacl;

final nacl.SigningKey testOnlyK1 = nacl.SigningKey.fromSeed(
  Uint8List.fromList(List<int>.filled(32, 0x11)),
);

final nacl.SigningKey testOnlyK2 = nacl.SigningKey.fromSeed(
  Uint8List.fromList(List<int>.filled(32, 0x22)),
);

final nacl.SigningKey testOnlyRogue = nacl.SigningKey.fromSeed(
  Uint8List.fromList(List<int>.filled(32, 0x99)),
);
