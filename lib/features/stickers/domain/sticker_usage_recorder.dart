abstract interface class StickerUsageRecorder {
  Future<void> recordSent(String stickerId);
}

final class NoopStickerUsageRecorder implements StickerUsageRecorder {
  const NoopStickerUsageRecorder();

  @override
  Future<void> recordSent(String stickerId) => Future<void>.value();
}
