import '../../../core/diagnostics/app_diagnostics.dart';
import '../domain/sticker_usage_recorder.dart';

final class AppDiagnosticStickerUsageRecorder implements StickerUsageRecorder {
  AppDiagnosticStickerUsageRecorder({AppDiagnostics? diagnostics})
    : _diagnostics = diagnostics ?? AppDiagnostics.instance;

  final AppDiagnostics _diagnostics;

  @override
  Future<void> recordSent(String stickerId) async {
    try {
      _diagnostics.recordStickerSent(stickerId);
    } catch (_) {
      // Optional diagnostics cannot fail an admitted send.
    }
  }
}
