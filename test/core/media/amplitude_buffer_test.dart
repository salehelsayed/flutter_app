import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/amplitude_buffer.dart';

void main() {
  group('AmplitudeBuffer', () {
    test('initializes with all zeros', () {
      final buffer = AmplitudeBuffer(size: 5);
      expect(buffer.values, [0.0, 0.0, 0.0, 0.0, 0.0]);
    });

    test('push() adds to end, shifts oldest out when full', () {
      final buffer = AmplitudeBuffer(size: 3);
      buffer.push(0.1);
      buffer.push(0.2);
      buffer.push(0.3);
      expect(buffer.values, [0.1, 0.2, 0.3]);

      buffer.push(0.4);
      expect(buffer.values, [0.2, 0.3, 0.4]);
    });

    test('values returns a copy (not reference)', () {
      final buffer = AmplitudeBuffer(size: 3);
      buffer.push(0.5);
      final copy = buffer.values;
      copy[0] = 0.99;
      expect(buffer.values[0], isNot(0.99));
    });

    test('reset() fills with zeros', () {
      final buffer = AmplitudeBuffer(size: 3);
      buffer.push(0.5);
      buffer.push(0.8);
      buffer.push(0.3);
      buffer.reset();
      expect(buffer.values, [0.0, 0.0, 0.0]);
    });

    test('push() clamps input to [0.0, 1.0]', () {
      final buffer = AmplitudeBuffer(size: 3);
      buffer.push(-0.5);
      buffer.push(1.5);
      buffer.push(0.5);
      expect(buffer.values, [0.0, 1.0, 0.5]);
    });

    test('partially filled buffer has zeros then values', () {
      final buffer = AmplitudeBuffer(size: 5);
      buffer.push(0.3);
      buffer.push(0.7);
      expect(buffer.values, [0.0, 0.0, 0.0, 0.3, 0.7]);
    });
  });
}
