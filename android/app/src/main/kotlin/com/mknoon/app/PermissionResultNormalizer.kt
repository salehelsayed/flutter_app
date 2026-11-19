package com.mknoon.app

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat

internal class PermissionResultNormalizer(
    private val activity: Activity,
) : ActivityCompat.PermissionCompatDelegate {
    companion object {
        private const val PERMISSION_HANDLER_REQUEST_CODE = 24
    }

    internal data class Result(
        val permissions: Array<out String>,
        val grantResults: IntArray,
    )

    private var previous: ActivityCompat.PermissionCompatDelegate? = null
    private var installed = false
    private var requestedPermissions: Array<out String>? = null

    fun install() {
        if (installed) return
        previous = ActivityCompat.getPermissionCompatDelegate()
        installed = true
        ActivityCompat.setPermissionCompatDelegate(this)
    }

    fun dispose() {
        if (ActivityCompat.getPermissionCompatDelegate() === this) {
            var restore = previous
            while (restore is PermissionResultNormalizer && !restore.installed) {
                restore = restore.previous
            }
            ActivityCompat.setPermissionCompatDelegate(restore)
        }
        installed = false
        requestedPermissions = null
    }

    override fun requestPermissions(
        activity: Activity,
        permissions: Array<out String>,
        requestCode: Int,
    ): Boolean {
        val handled = previous?.requestPermissions(activity, permissions, requestCode) ?: false
        if (!handled && installed && activity === this.activity &&
            requestCode == PERMISSION_HANDLER_REQUEST_CODE
        ) {
            requestedPermissions = permissions.copyOf()
        }
        return handled
    }

    override fun onActivityResult(
        activity: Activity,
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ): Boolean = previous?.onActivityResult(activity, requestCode, resultCode, data) ?: false

    fun normalize(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Result {
        if (requestCode == PERMISSION_HANDLER_REQUEST_CODE) {
            val requested = requestedPermissions
            requestedPermissions = null
            if (permissions.isEmpty() && grantResults.isEmpty() && !requested.isNullOrEmpty()) {
                // Android cancellation omits the names. Complete the plugin's pending
                // request as denied rather than leaving its native request queue busy.
                return Result(requested, IntArray(requested.size) { PackageManager.PERMISSION_DENIED })
            }
        }
        return Result(permissions, grantResults)
    }
}
