import 'package:flutter_app/core/database/encrypted_db_opener.dart';
import 'package:flutter_test/flutter_test.dart';

/// 218 SC-6 (host, seam) — the cipher-mode marker + decision logic are pure
/// functions, so the wiring is testable WITHOUT a SQLCipher device. The device
/// suite (db_raw_key_migration_proof_test.dart) proves the real cipher behavior;
/// this pins the seam: marker domain {absent, raw} and the (mode, dbExists)
/// decision table (§G2). Auto-discovered (test/core/**).
void main() {
  group('218 SC-6 cipher-mode marker + decision seam', () {
    const hex =
        'a1b2c3d4e5f6071829304152637485960f1e2d3c4b5a69788796a5b4c3d2e1f0';

    group('marker parse/format — domain {absent, raw}, NO pass: value', () {
      test('bare <hex> parses as absent (legacy passphrase, pre-218 format)', () {
        final r = parseCipherKeyRecord(hex);
        expect(r.mode, CipherKeyMode.absent);
        expect(r.hex, hex);
      });

      test('"raw:<hex>" parses as raw', () {
        final r = parseCipherKeyRecord('raw:$hex');
        expect(r.mode, CipherKeyMode.raw);
        expect(r.hex, hex);
      });

      test('format is the inverse of parse', () {
        expect(formatCipherKeyRecord(CipherKeyMode.absent, hex), hex);
        expect(formatCipherKeyRecord(CipherKeyMode.raw, hex), 'raw:$hex');
        for (final mode in CipherKeyMode.values) {
          final round = parseCipherKeyRecord(formatCipherKeyRecord(mode, hex));
          expect(round.mode, mode);
          expect(round.hex, hex);
        }
      });

      test('there is no "pass:" marker — pass:<hex> is treated as bare/absent',
          () {
        // A hypothetical pass: value must NOT be a recognized mode; it just
        // isn't the raw prefix, so it degrades to absent (and would then fail
        // the 64-hex validity check below).
        final r = parseCipherKeyRecord('pass:$hex');
        expect(r.mode, CipherKeyMode.absent);
      });
    });

    group('64-hex validity — malformed is a FAILING signal (§I2)', () {
      test('a real 64-hex key is valid', () {
        expect(isValid256BitHexKey(hex), isTrue);
      });
      test('63 / 65 chars, non-hex, empty, and prefixed are invalid', () {
        expect(isValid256BitHexKey(hex.substring(1)), isFalse); // 63
        expect(isValid256BitHexKey('${hex}0'), isFalse); // 65
        expect(isValid256BitHexKey('z${hex.substring(1)}'), isFalse); // non-hex
        expect(isValid256BitHexKey(''), isFalse);
        expect(isValid256BitHexKey('raw:$hex'), isFalse); // must strip first
      });
    });

    group('decision table (mode, dbFileExists) — §G2', () {
      test('(raw, exists) → openRaw (2nd steady launch, SC-5 fast path)', () {
        expect(
          decideCipherOpenAction(mode: CipherKeyMode.raw, dbFileExists: true),
          CipherOpenAction.openRaw,
        );
      });
      test('(raw, absent) → createRaw (reinstall; key survived keystore)', () {
        expect(
          decideCipherOpenAction(mode: CipherKeyMode.raw, dbFileExists: false),
          CipherOpenAction.createRaw,
        );
      });
      test('(absent, exists) → rekeyToRaw (legacy passphrase DB migrates once)',
          () {
        expect(
          decideCipherOpenAction(
            mode: CipherKeyMode.absent,
            dbFileExists: true,
          ),
          CipherOpenAction.rekeyToRaw,
        );
      });
      test('(absent, absent) → createRaw (fresh install)', () {
        expect(
          decideCipherOpenAction(
            mode: CipherKeyMode.absent,
            dbFileExists: false,
          ),
          CipherOpenAction.createRaw,
        );
      });
    });
  });
}
