package com.mknoon.app

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import java.lang.reflect.Proxy
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class PermissionCancellationNativeTest {
    private lateinit var activity: Activity
    private lateinit var normalizer: PermissionResultNormalizer
    private var original: ActivityCompat.PermissionCompatDelegate? = null

    @Before
    fun setUp() {
        original = ActivityCompat.getPermissionCompatDelegate()
        ActivityCompat.setPermissionCompatDelegate(null)
        activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        shadowOf(activity.application).denyPermissions(
            Manifest.permission.CAMERA,
            Manifest.permission.RECORD_AUDIO,
        )
        normalizer = PermissionResultNormalizer(activity).also { it.install() }
    }

    @After
    fun tearDown() {
        normalizer.dispose()
        ActivityCompat.setPermissionCompatDelegate(original)
    }

    @Test
    fun `cancelled camera request settles and does not poison already granted microphone`() {
        val plugin = PermissionPlugin(activity)
        plugin.request(listOf(1))
        val result = normalizer.normalize(24, emptyArray(), intArrayOf())
        plugin.deliver(24, result)
        shadowOf(activity.application).grantPermissions(Manifest.permission.RECORD_AUDIO)
        plugin.request(listOf(7))

        assertEquals("Camera cancellation must complete its actual plugin callback; errors=${plugin.errors}", 2, plugin.results.size)
        assertEquals(0, plugin.results[0][1])
        assertEquals(1, plugin.results[1][7])
        assertTrue("A cancelled camera request must not leave the real native permission queue busy", plugin.errors.isEmpty())
    }

    @Test
    fun `cancelled combined camera and microphone request drains all requested names`() {
        val plugin = PermissionPlugin(activity)
        plugin.request(listOf(1, 7))
        plugin.deliver(24, normalizer.normalize(24, emptyArray(), intArrayOf()))
        shadowOf(activity.application).grantPermissions(Manifest.permission.RECORD_AUDIO)
        plugin.request(listOf(7))

        assertEquals("Cancellation must drain both native pending permission names; errors=${plugin.errors}", 2, plugin.results.size)
        assertEquals(0, plugin.results[0][1])
        assertEquals(0, plugin.results[0][7])
        assertEquals(1, plugin.results[1][7])
        assertTrue(plugin.errors.isEmpty())
    }

    @Test
    fun `normal grant and denial reach actual plugin unchanged`() {
        for (grant in listOf(PackageManager.PERMISSION_GRANTED, PackageManager.PERMISSION_DENIED)) {
            shadowOf(activity.application).denyPermissions(Manifest.permission.CAMERA)
            val plugin = PermissionPlugin(activity)
            plugin.request(listOf(1))
            if (grant == PackageManager.PERMISSION_GRANTED) {
                shadowOf(activity.application).grantPermissions(Manifest.permission.CAMERA)
            }
            val names = arrayOf(Manifest.permission.CAMERA)
            val grants = intArrayOf(grant)
            val normalized = normalizer.normalize(24, names, grants)
            assertSame(names, normalized.permissions)
            assertSame(grants, normalized.grantResults)
            plugin.deliver(24, normalized)
            assertEquals(1, plugin.results.size)
            assertEquals(if (grant == PackageManager.PERMISSION_GRANTED) 1 else 0, plugin.results.single()[1])
            assertTrue(plugin.errors.isEmpty())
        }
    }

    @Test
    fun `unowned cancellation and egress callback remain untouched`() {
        val names = emptyArray<String>()
        val grants = intArrayOf()
        val unowned = normalizer.normalize(24, names, grants)
        assertSame(names, unowned.permissions)
        assertSame(grants, unowned.grantResults)
        normalizer.requestPermissions(activity, arrayOf(Manifest.permission.CAMERA), 24)
        val egress = normalizer.normalize(9727, names, grants)
        assertSame(names, egress.permissions)
        assertSame(grants, egress.grantResults)
    }

    @Test
    fun `another activity cannot supply a cancellation binding`() {
        val other = Robolectric.buildActivity(Activity::class.java).setup().get()
        assertFalse(normalizer.requestPermissions(other, arrayOf(Manifest.permission.CAMERA), 24))
        val result = normalizer.normalize(24, emptyArray(), intArrayOf())
        assertTrue(result.permissions.isEmpty())
        assertTrue(result.grantResults.isEmpty())
    }

    @Test
    fun `capture preserves prior delegate decisions and activity results`() {
        normalizer.dispose()
        val previous = RecordingDelegate()
        ActivityCompat.setPermissionCompatDelegate(previous)
        normalizer = PermissionResultNormalizer(activity).also { it.install() }
        previous.consumesRequest = true
        assertTrue(normalizer.requestPermissions(activity, arrayOf(Manifest.permission.CAMERA), 24))
        assertTrue(normalizer.normalize(24, emptyArray(), intArrayOf()).permissions.isEmpty())
        previous.consumesRequest = false
        assertFalse(normalizer.requestPermissions(activity, arrayOf(Manifest.permission.CAMERA), 24))
        val data = Intent("previous-result")
        assertTrue(normalizer.onActivityResult(activity, 123, Activity.RESULT_OK, data))
        assertEquals(2, previous.requests)
        assertSame(data, previous.resultData)
        normalizer.dispose()
        assertSame(previous, ActivityCompat.getPermissionCompatDelegate())
    }

    @Test
    fun `disposing old owner preserves successor delegate`() {
        val successor = PermissionResultNormalizer(activity).also { it.install() }
        normalizer.dispose()
        assertSame(successor, ActivityCompat.getPermissionCompatDelegate())
        successor.dispose()
        assertEquals("Successor teardown must skip its disposed owned predecessor", null, ActivityCompat.getPermissionCompatDelegate())
    }

    @Test
    fun `MainActivity installs and closes its actual narrow permission registration`() {
        normalizer.dispose()
        val main = Robolectric.buildActivity(MainActivity::class.java).get()
        fun invoke(name: String) = MainActivity::class.java.getDeclaredMethod(name)
            .apply { isAccessible = true }.invoke(main)
        try {
            invoke("setupPermissionResultNormalizer")
            assertTrue(ActivityCompat.getPermissionCompatDelegate() is PermissionResultNormalizer)
        } finally {
            invoke("closePermissionResultNormalizer")
        }
        assertEquals(null, ActivityCompat.getPermissionCompatDelegate())
    }

    private class RecordingDelegate : ActivityCompat.PermissionCompatDelegate {
        var consumesRequest = false
        var requests = 0
        var resultData: Intent? = null
        override fun requestPermissions(activity: Activity, permissions: Array<out String>, requestCode: Int): Boolean {
            requests++
            return consumesRequest
        }
        override fun onActivityResult(activity: Activity, requestCode: Int, resultCode: Int, data: Intent?): Boolean {
            resultData = data
            return true
        }
    }

    private class PermissionPlugin(activity: Activity) {
        val results = mutableListOf<Map<Int, Int>>()
        val errors = mutableListOf<String>()
        private val type = Class.forName("com.baseflow.permissionhandler.PermissionManager")
        private val target = type.getDeclaredConstructor(Context::class.java)
            .apply { isAccessible = true }.newInstance(activity)
        private val successType = Class.forName("com.baseflow.permissionhandler.PermissionManager\$RequestPermissionsSuccessCallback")
        private val errorType = Class.forName("com.baseflow.permissionhandler.ErrorCallback")

        init {
            type.getDeclaredMethod("setActivity", Activity::class.java)
                .apply { isAccessible = true }.invoke(target, activity)
        }

        fun request(groups: List<Int>) {
            val success = Proxy.newProxyInstance(successType.classLoader, arrayOf(successType)) { _, method, args ->
                if (method.name == "onSuccess") {
                    @Suppress("UNCHECKED_CAST")
                    val result = args!![0] as Map<Int, Int>
                    results.add(result.toMap())
                }
                null
            }
            val error = Proxy.newProxyInstance(errorType.classLoader, arrayOf(errorType)) { _, method, args ->
                if (method.name == "onError") errors.add("${args!![0]}: ${args[1]}")
                null
            }
            type.getDeclaredMethod("requestPermissions", List::class.java, successType, errorType)
                .apply { isAccessible = true }.invoke(target, groups, success, error)
        }

        fun deliver(code: Int, result: PermissionResultNormalizer.Result) {
            type.getDeclaredMethod("onRequestPermissionsResult", Int::class.javaPrimitiveType, Array<String>::class.java, IntArray::class.java)
                .apply { isAccessible = true }.invoke(target, code, result.permissions, result.grantResults)
        }
    }
}
