# Flutter includes this file alongside its default release keep rules.
# Shorten package names for classes whose names are not kept.
-repackageclasses

# flutter_local_notifications reads its cache through anonymous Gson TypeTokens.
# R8 full mode needs both signatures and their owning classes kept.
-keepattributes Signature
-keep,allowobfuscation class com.google.gson.reflect.TypeToken
-keep,allowobfuscation class * extends com.google.gson.reflect.TypeToken

# ML Kit discovers these registrars by reflection. R8 full mode does not
# implicitly preserve their no-arg constructors when keeping the classes.
-keep class com.google.mlkit.** implements com.google.firebase.components.ComponentRegistrar {
    <init>();
}

# R8 9.3.16 can emit invalid monitor/catch-all bytecode when it inlines this
# synchronized backend into PendingNativeCallStore.replaceReceiptsCommitted.
# Preserve the backend's locking boundaries; shrinking and renaming stay on.
-keep,allowshrinking,allowobfuscation class com.mknoon.app.call.AndroidProtectedPendingNativeCallBackend {
    *;
}
