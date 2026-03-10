import 'package:flutter_app/core/constants/network_constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RENDEZVOUS_ADDRESS uses /dns/ not /dns4/', () {
    expect(RENDEZVOUS_ADDRESS, isNot(contains('/dns4/')));
    expect(RENDEZVOUS_ADDRESS, contains('/dns/'));
  });
}
