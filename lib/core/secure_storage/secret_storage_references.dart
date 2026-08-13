const String secureStoreReferencePrefix = 'secure:';

String secureStoreReferenceForKey(String secureStoreKey) =>
    '$secureStoreReferencePrefix$secureStoreKey';

bool isSecureStoreReference(String? value) =>
    value != null && value.startsWith(secureStoreReferencePrefix);

String secureStoreKeyFromReference(String reference) =>
    reference.substring(secureStoreReferencePrefix.length);

String mediaAttachmentEncryptionKeyStoreName(String attachmentId) =>
    'media_attachment_encryption_key:${Uri.encodeComponent(attachmentId)}';

String groupKeyMaterialStoreName(String groupId, int keyGeneration) =>
    'group_key_material:${Uri.encodeComponent(groupId)}:$keyGeneration';

/// Stable staging address for one authenticated linked-group bootstrap.
///
/// The bootstrap id prevents an old/replayed snapshot from overwriting key
/// material owned by a newer accepted transition before SQL authority commits.
String groupLinkedBootstrapKeyMaterialStoreName(
  String groupId,
  int keyGeneration,
  String bootstrapId,
) =>
    'group_key_material:${Uri.encodeComponent(groupId)}:$keyGeneration:'
    'linked-bootstrap:${Uri.encodeComponent(bootstrapId)}';

/// Phase-unique staging address for an authenticated post-removal re-entry.
///
/// A retained shell can still have an old generation at the ordinary key
/// address. Using the accepted phase nonce prevents staging from overwriting
/// that retry-owned material before the SQL authority transaction commits.
String groupAcceptedKeyMaterialStoreName(
  String groupId,
  int keyGeneration,
  String bindingNonce,
) =>
    'group_key_material:${Uri.encodeComponent(groupId)}:$keyGeneration:'
    'accepted:${Uri.encodeComponent(bindingNonce)}';
