# Flutter includes this file alongside its default release keep rules.
# Shorten package names for classes whose names are not kept.
-repackageclasses

# R8 9.3.16 can emit invalid monitor/catch-all bytecode when it inlines this
# synchronized backend into PendingNativeCallStore.replaceReceiptsCommitted.
# Preserve the backend's locking boundaries; shrinking and renaming stay on.
-keep,allowshrinking,allowobfuscation class com.mknoon.app.call.AndroidProtectedPendingNativeCallBackend {
    *;
}
