import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

void main() {
  group('FL_XS_01 - IdentityModel', () {
    final testJson = {
      'peerId': '12D3KooWTest',
      'publicKey': 'dGVzdC1wdWJsaWMta2V5',
      'privateKey': 'dGVzdC1wcml2YXRlLWtleQ==',
      'mnemonic12': 'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
      'createdAt': '2025-01-01T00:00:00.000Z',
      'updatedAt': '2025-01-01T00:00:00.000Z',
    };

    test('fromJson creates model correctly', () {
      final model = IdentityModel.fromJson(testJson);

      expect(model.peerId, '12D3KooWTest');
      expect(model.publicKey, 'dGVzdC1wdWJsaWMta2V5');
      expect(model.privateKey, 'dGVzdC1wcml2YXRlLWtleQ==');
      expect(model.mnemonic12, 'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12');
      expect(model.createdAt, '2025-01-01T00:00:00.000Z');
      expect(model.updatedAt, '2025-01-01T00:00:00.000Z');
    });

    test('toJson returns correct map', () {
      final model = IdentityModel.fromJson(testJson);
      final json = model.toJson();

      expect(json['peerId'], testJson['peerId']);
      expect(json['publicKey'], testJson['publicKey']);
      expect(json['privateKey'], testJson['privateKey']);
      expect(json['mnemonic12'], testJson['mnemonic12']);
      expect(json['createdAt'], testJson['createdAt']);
      expect(json['updatedAt'], testJson['updatedAt']);
    });

    test('round-trip JSON conversion', () {
      final model = IdentityModel.fromJson(testJson);
      final json = model.toJson();
      final model2 = IdentityModel.fromJson(json);

      expect(model2.peerId, model.peerId);
      expect(model2.publicKey, model.publicKey);
      expect(model2.privateKey, model.privateKey);
    });
  });
}
