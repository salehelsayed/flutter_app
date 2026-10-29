import 'dart:async';

import 'package:flutter_app/features/translate_preview/model_delivery_contract.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_core.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_platform.dart';
import 'package:flutter_app/features/translate_preview/on_device_ai.dart';
import 'package:flutter_app/features/translate_preview/translation_capability.dart';

PersistentModelDeliveryController? _controller;

/// One process-owned download, created only when the preview is enabled.
/// Its initial Unsupported state hides links until eligibility is known.
ModelDeliveryController? get productionTranslatePreviewDelivery {
  if (!translatePreviewEnabled) return null;
  return _controller ??= _createController();
}

PersistentModelDeliveryController _createController() {
  final controller = createProductionModelDeliveryController();
  unawaited(readTranslationCapability().then(controller.setCapability));
  return controller;
}
