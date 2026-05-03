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
