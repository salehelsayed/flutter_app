package com.mknoon.app

import android.system.OsConstants
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.shadows.ShadowOsConstants
import org.robolectric.util.ReflectionHelpers

/** Preserve Robolectric's constants, then restore omitted file-operation values. */
@Implements(OsConstants::class)
class StickerCutoutHostOsConstantsShadow {
    companion object {
        @JvmStatic
        @Implementation
        fun initConstants() {
            ReflectionHelpers.callStaticMethod<Void>(ShadowOsConstants::class.java, "initConstants")
            // Distinct from every open flag populated by Robolectric 4.13.
            // The POSIX shadow translates this bit to host NOFOLLOW_LINKS.
            ReflectionHelpers.setStaticField(OsConstants::class.java, "O_NOFOLLOW", 0x20000)
            ReflectionHelpers.setStaticField(OsConstants::class.java, "SEEK_SET", 0)
            ReflectionHelpers.setStaticField(OsConstants::class.java, "SEEK_CUR", 1)
            ReflectionHelpers.setStaticField(OsConstants::class.java, "SEEK_END", 2)
        }
    }
}
