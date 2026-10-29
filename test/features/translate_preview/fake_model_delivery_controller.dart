import 'package:flutter/material.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_contract.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Records each call the UI makes; tests move [state] by hand.
class FakeModelDeliveryController implements ModelDeliveryController {
  FakeModelDeliveryController(ModelDeliveryState initial)
    : state = ValueNotifier(initial);

  @override
  final ValueNotifier<ModelDeliveryState> state;

  @override
  final ValueNotifier<bool> allowMobileData = ValueNotifier(false);

  final calls = <String>[];
  int refreshCalls = 0;
  Future<void> Function()? onRefresh;

  @override
  Future<void> refresh() async {
    refreshCalls++;
    await onRefresh?.call();
  }

  @override
  Future<void> setAllowMobileData(bool allow) async {
    calls.add('setAllowMobileData($allow)');
    allowMobileData.value = allow;
  }

  @override
  Future<void> start({required bool allowMobileData}) async =>
      calls.add('start(allowMobileData: $allowMobileData)');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> resume() async => calls.add('resume');

  @override
  Future<void> retry() async => calls.add('retry');

  @override
  Future<void> remove() async => calls.add('remove');
}

Widget localizedApp(Widget home, {Locale locale = const Locale('en')}) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );
