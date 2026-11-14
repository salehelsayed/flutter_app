package com.mknoon.app

import java.io.FileDescriptor
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.shadows.ShadowBlockGuardOs

/** Routes Robolectric 4.13's no-op BlockGuardOs.close to the real host owner. */
@Implements(className = "libcore.io.BlockGuardOs", minSdk = 26, isInAndroidSdk = false)
class StickerCutoutHostBlockGuardOsShadow : ShadowBlockGuardOs() {
    @Implementation
    protected override fun close(fd: FileDescriptor) {
        StickerCutoutHostPosixShadow.closeHostDescriptor(fd)
    }
}
