/// 361: the smallest injectable conversation modality policy.
///
/// The primary role allows everything (the incumbent default — construction
/// sites need no change). The restricted linked role authors blob-free text,
/// edit, delete and reactions only; media, voice and private modes are
/// refused at the composer surface.
class DirectConversationModalityGate {
  const DirectConversationModalityGate({
    this.allowsMediaAuthoring = true,
    this.allowsVoiceAuthoring = true,
    this.allowsPrivateModes = true,
  });

  /// The restricted linked blob-free surface.
  const DirectConversationModalityGate.linkedBlobFree()
    : allowsMediaAuthoring = false,
      allowsVoiceAuthoring = false,
      allowsPrivateModes = false;

  final bool allowsMediaAuthoring;
  final bool allowsVoiceAuthoring;
  final bool allowsPrivateModes;
}
