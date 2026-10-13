import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_app/features/call/application/foreground_call_capability.dart';
import 'package:flutter_app/features/call/domain/call_audio_output_device.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/presentation/widgets/call_audio_output_picker.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

final _id = CallId.parse('22222222-2222-4222-8222-222222222222');
CallAudioOutputDevice _device(
  String id, {
  bool selected = false,
  CallAudioOutputRoute route = CallAudioOutputRoute.bluetooth,
}) => CallAudioOutputDevice(
  id: id,
  name: 'Synthetic headset $id',
  route: route,
  selected: selected,
);
Widget _harness(_Picker owner, {VoidCallback? close}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: CallAudioOutputPicker(
      callId: _id,
      capability: owner,
      onClose: close ?? () {},
    ),
  ),
);
void main() {
  testWidgets(
    'selection stays observed while pending, and errors preserve the real route',
    (tester) async {
      final owner = _Picker()
        ..devices = [_device('A', selected: true), _device('B')];
      await tester.pumpWidget(_harness(owner));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic headset A'), findsOneWidget);
      expect(find.text('Synthetic headset B'), findsOneWidget);
      final gate = Completer<ForegroundCallActionResult>();
      owner.selection = gate.future;
      await tester.tap(find.text('Synthetic headset B'));
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('call-output-choice-0')),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('call-output-choice-1')),
          matching: find.byIcon(Icons.check),
        ),
        findsNothing,
      );
      gate.complete(ForegroundCallActionResult.failed);
      await tester.pumpAndSettle();
      expect(owner.selections, ['B']);
      expect(find.text('Audio output could not be changed'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('call-output-choice-0')),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
      owner.selection = Future.value(ForegroundCallActionResult.applied);
      owner.devices = [_device('A'), _device('B', selected: true)];
      await tester.tap(find.text('Synthetic headset B'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('call-output-choice-1')),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'hot-plug refresh observes fallback and disposal discards a late inventory',
    (tester) async {
      final owner = _Picker()
        ..devices = [_device('A', selected: true), _device('B')];
      await tester.pumpWidget(_harness(owner));
      await tester.pumpAndSettle();
      owner.devices = [
        _device('speaker', selected: true, route: CallAudioOutputRoute.speaker),
      ];
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('Synthetic headset A'), findsNothing);
      expect(find.text('Speaker'), findsOneWidget);
      expect(owner.selections, isEmpty);
      final gate = Completer<List<CallAudioOutputDevice>>();
      owner.inventory = gate.future;
      await tester.tap(find.byTooltip('Refresh audio outputs'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      gate.complete([_device('late')]);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'removing a device during a tap cannot select the replacement row',
    (tester) async {
      final owner = _Picker()..devices = [_device('A'), _device('B')];
      await tester.pumpWidget(_harness(owner));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Synthetic headset A')),
      );
      owner.devices = [_device('B')];
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(owner.selections, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('enumeration failure is coarse and refresh can recover', (
    tester,
  ) async {
    final owner = _Picker()..failRead = true;
    await tester.pumpWidget(_harness(owner));
    await tester.pumpAndSettle();
    expect(find.text('Audio output could not be changed'), findsOneWidget);
    expect(find.textContaining('private failure'), findsNothing);
    owner.failRead = false;
    owner.devices = [_device('A', selected: true)];
    await tester.tap(find.byTooltip('Refresh audio outputs'));
    await tester.pumpAndSettle();
    expect(find.text('Synthetic headset A'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

class _Picker implements ForegroundCallAudioPickerCapability {
  List<CallAudioOutputDevice> devices = [];
  Future<List<CallAudioOutputDevice>>? inventory;
  Future<ForegroundCallActionResult> selection = Future.value(
    ForegroundCallActionResult.applied,
  );
  bool failRead = false;
  final selections = <String>[];
  @override
  Future<List<CallAudioOutputDevice>> outputDevices(CallId id) async {
    if (failRead) throw StateError('private failure');
    if (inventory != null) return await inventory!;
    return devices;
  }

  @override
  Future<ForegroundCallActionResult> selectOutputDevice(
    CallId id,
    String output,
  ) {
    selections.add(output);
    return selection;
  }
}
