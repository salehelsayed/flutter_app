import 'package:flutter_app/core/constants/network_constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rendezvousAddress uses /dns/ not /dns4/', () {
    expect(rendezvousAddress, isNot(contains('/dns4/')));
    expect(rendezvousAddress, contains('/dns/'));
  });
}
