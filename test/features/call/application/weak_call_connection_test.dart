import 'package:flutter_app/features/call/application/weak_call_connection.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late WeakCallConnection connection;

  setUp(() {
    connection = WeakCallConnection();
  });

  bool sample(CallQualityBand band, int? observation, int seconds) =>
      connection.observe(
        quality: band,
        observation: observation,
        elapsed: Duration(seconds: seconds),
      );

  test('weak and recovery require sustained fresh audio measurements', () {
    expect(sample(CallQualityBand.good, 1, 0), isFalse);
    expect(sample(CallQualityBand.poor, 2, 3), isFalse);
    expect(sample(CallQualityBand.poor, 2, 6), isFalse);
    expect(sample(CallQualityBand.poor, 3, 9), isTrue);
    expect(connection.isWeak, isTrue);

    expect(sample(CallQualityBand.good, 4, 12), isFalse);
    expect(sample(CallQualityBand.degraded, 5, 15), isFalse);
    expect(sample(CallQualityBand.good, 6, 18), isFalse);
    expect(sample(CallQualityBand.good, 7, 21), isFalse);
    expect(sample(CallQualityBand.good, 8, 24), isTrue);
    expect(connection.isWeak, isFalse);
  });

  test('missing or stale measurements do not create or retain a warning', () {
    expect(sample(CallQualityBand.poor, null, 0), isFalse);
    expect(sample(CallQualityBand.poor, 1, 3), isFalse);
    expect(sample(CallQualityBand.unknown, null, 6), isFalse);
    expect(sample(CallQualityBand.poor, 1, 9), isFalse);
    expect(connection.isWeak, isFalse);
    expect(sample(CallQualityBand.poor, 2, 12), isFalse);
    expect(sample(CallQualityBand.poor, 3, 18), isTrue);

    expect(sample(CallQualityBand.poor, 3, 30), isFalse);
    expect(connection.isWeak, isTrue);
    expect(sample(CallQualityBand.unknown, null, 33), isTrue);
    expect(sample(CallQualityBand.poor, 3, 36), isFalse);
    expect(connection.isWeak, isFalse);
  });

  test('reconnecting clears the old measurement and pending transition', () {
    expect(sample(CallQualityBand.poor, 1, 0), isFalse);
    connection.reset();
    expect(sample(CallQualityBand.poor, 2, 6), isFalse);
    expect(connection.isWeak, isFalse);
  });
}
