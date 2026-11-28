import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/android_production_audio_call_campaign.dart';

const _package = androidProductionKilledCalleeAppPackage;

void main() {
  test('Telecom proof accepts only exact owned calls in current mCalls', () {
    final live = androidProductionKilledCalleeTelecomCalls('''
Telecom:
  mCalls:
    [Call id=TC@1, state=RINGING, tpac=ComponentInfo{$_package/.Connection}, cmgr=null, handle=***]
    [Call id=TC@2, state=RINGING, tpac=ComponentInfo{$_package.other/.Connection}, cmgr=null, handle=***]
    [Call id=TC@3, state=DISCONNECTED, tpac=ComponentInfo{$_package/.Connection}, cmgr=null, handle=***]
  Historical calls:
    [Call id=TC@4, state=RINGING, tpac=ComponentInfo{$_package/.Connection}, cmgr=null, handle=***]
''');

    expect(live, {'TC@1': 'RINGING'});
    expect(
      androidProductionKilledCalleeTelecomCalls('''
Telecom:
  mCalls:
  Historical calls:
    [Call id=TC@1, state=RINGING, tpac=ComponentInfo{$_package/.Connection}, cmgr=null, handle=***]
'''),
      isEmpty,
    );
  });

  test('unsupported current Telecom formats cannot prove release', () {
    expect(
      androidProductionKilledCalleeTelecomCalls('''
Telecom:
  Calls:
    [Call id=TC@1, state=RINGING, tpac=ComponentInfo{$_package/.Connection}, cmgr=null]
'''),
      isNull,
    );
    expect(
      androidProductionKilledCalleeTelecomCalls('''
Telecom:
  mCalls:
    [Call id=TC@1, state=RINGING, owner=$_package]
'''),
      isNull,
    );
  });

  test(
    'caller ringing proof is scoped to one PID and ordered invite window',
    () {
      final priorRing = _transition(11, 'remoteRinging', 'ringing');
      final wrongPidRing = _transition(12, 'remoteRinging', 'ringing');
      final invite = _transition(11, 'outgoingInviteReady', 'inviting');
      final currentRing = _transition(11, 'remoteRinging', 'ringing');
      final terminal = _transition(11, 'userEnded', 'ending');
      final log = [
        priorRing,
        _mark('a'),
        priorRing,
        invite,
        wrongPidRing,
        _mark('a-cancel'),
        currentRing,
        _mark('b'),
        invite,
        currentRing,
      ];

      final a = androidProductionKilledCalleeFlowRows(
        log.join('\n'),
        11,
        window: 'a',
        before: 'a-cancel',
      );
      expect(a, hasLength(2));
      expect(androidProductionKilledCalleeCallerState(a), 'inviting');
      expect(
        androidProductionKilledCalleeCallerState(
          androidProductionKilledCalleeFlowRows(
            log.join('\n'),
            11,
            window: 'b',
          ),
        ),
        'ringing',
      );
      expect(
        androidProductionKilledCalleeCallerState(
          androidProductionKilledCalleeFlowRows(
            [...log, terminal].join('\n'),
            11,
            window: 'b',
          ),
        ),
        'terminal',
      );
      expect(
        androidProductionKilledCalleeFlowRows(log.join('\n'), 11, window: 'c'),
        isEmpty,
      );
    },
  );
}

String _mark(String marker) =>
    '11-29 10:12:13.500  99  99 I MknoonVC059: $marker';

String _transition(int pid, String trigger, String state) =>
    '11-29 10:12:13.500  $pid  99 I flutter : [FLOW] '
    '{"event":"CALL_STATE_TRANSITION","details":'
    '{"trigger":"$trigger","state":"$state"}}';
