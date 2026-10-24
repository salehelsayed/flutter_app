# Flutter includes this file alongside its default release keep rules.
# Shorten package names for classes whose names are not kept.
-repackageclasses

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
