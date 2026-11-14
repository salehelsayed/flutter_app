package com.mknoon.app

import android.content.Context
import android.graphics.Bitmap
import android.os.Build
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailabilityLight
import com.google.android.gms.common.moduleinstall.ModuleInstall
import com.google.android.gms.common.moduleinstall.ModuleInstallClient
import com.google.android.gms.tasks.Task
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.segmentation.subject.SubjectSegmentation
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenter
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenterOptions
import java.util.concurrent.Executor
import java.util.concurrent.atomic.AtomicBoolean

/** Created only by the bridge's guarded lazy factory; no install-time download. */
internal class MlKitStickerCutoutClient private constructor(
    private val segmenter: SubjectSegmenter,
    private val modules: ModuleInstallClient,
) : StickerCutoutClient {
    private val closed = AtomicBoolean(false)

    override fun areModulesAvailable(): Task<Boolean> {
        check(!closed.get())
        return modules.areModulesAvailable(segmenter).continueWith<Boolean>(DIRECT) { task ->
            task.result.areModulesAvailable()
        }
    }

    override fun deferredInstall(): Task<Void> {
        check(!closed.get())
        return modules.deferredInstall(segmenter)
    }

    override fun process(uprightBitmap: Bitmap): Task<Bitmap?> {
        check(!closed.get())
        return segmenter.process(InputImage.fromBitmap(uprightBitmap, 0)).continueWith<Bitmap?>(DIRECT) { task ->
            task.result.foregroundBitmap
        }
    }

    override fun close() {
        if (closed.compareAndSet(false, true)) segmenter.close()
    }

    companion object {
        private val DIRECT = Executor { it.run() }

        fun create(context: Context): StickerCutoutClient? {
            if (Build.VERSION.SDK_INT < 24) return null
            val application = context.applicationContext
            if (GoogleApiAvailabilityLight.getInstance().isGooglePlayServicesAvailable(application) != ConnectionResult.SUCCESS) {
                return null
            }
            val modules = ModuleInstall.getClient(application)
            val options = SubjectSegmenterOptions.Builder().enableForegroundBitmap().build()
            return MlKitStickerCutoutClient(SubjectSegmentation.getClient(options), modules)
        }
    }
}
