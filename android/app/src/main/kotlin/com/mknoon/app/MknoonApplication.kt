package com.mknoon.app

import android.app.Application
import com.mknoon.app.call.MknoonCallAudioSessionOwnership

/**
 * Runs before every FlutterEngine this process hosts: the activity engine,
 * the headless admission, recovery and update engines, and FlutterFire's
 * background engine. Process-wide policies that must precede all of them
 * live here.
 */
class MknoonApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        MknoonCallAudioSessionOwnership.applyProcessPolicy(
            telecomLaneCompiledIn = BuildConfig.ENABLE_ANDROID_NATIVE_CALLS,
        )
    }
}
