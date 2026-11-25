package com.it_nomads.fluttersecurestorage

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import com.it_nomads.fluttersecurestorage.ciphers.StorageCipher
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

@RunWith(RobolectricTestRunner::class)
class SecureStorageMutationCommitTest {
    @Test
    fun failedDeleteCommitReportsErrorWithoutResettingStorage() {
        val application = RuntimeEnvironment.getApplication()
        val backing = application.getSharedPreferences("bl86_commit_failure", Context.MODE_PRIVATE)
        assertTrue(backing.edit().putString("sentinel", "preserved").commit())
        val editorCalls = mutableListOf<String>()
        val preferences = object : SharedPreferences by backing {
            override fun edit(): SharedPreferences.Editor {
                val editor = backing.edit()
                return object : SharedPreferences.Editor by editor {
                    override fun commit(): Boolean {
                        editorCalls += "commit"
                        return false
                    }

                    override fun apply() {
                        editorCalls += "apply"
                        editor.apply()
                    }

                    override fun clear(): SharedPreferences.Editor {
                        editorCalls += "clear"
                        editor.clear()
                        return this
                    }
                }
            }
        }
        val context = object : ContextWrapper(application) {
            override fun getApplicationContext(): Context = this

            override fun getSharedPreferences(name: String?, mode: Int): SharedPreferences =
                preferences
        }
        val options = mapOf("resetOnError" to "true")
        val storage = FlutterSecureStorage(context, options)
        // Use the legacy branch to inject a failed editor commit without AndroidKeyStore.
        FlutterSecureStorage::class.java.getDeclaredField("storageCipher").apply {
            isAccessible = true
            set(storage, object : StorageCipher {
                override fun encrypt(input: ByteArray): ByteArray = input
                override fun decrypt(input: ByteArray): ByteArray = input
            })
        }
        val plugin = FlutterSecureStoragePlugin()
        FlutterSecureStoragePlugin::class.java.getDeclaredField("secureStorage").apply {
            isAccessible = true
            set(plugin, storage)
        }

        var errors = 0
        val result = object : MethodChannel.Result {
            override fun success(result: Any?) = fail("A failed commit returned success")

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                assertEquals("Exception encountered", errorCode)
                assertEquals("delete", errorMessage)
                assertTrue(errorDetails.toString().contains("CommitFailedException"))
                errors++
            }

            override fun notImplemented() = fail("The delete method was unavailable")
        }
        val call = MethodCall("delete", mapOf("key" to "target", "options" to options))
        val targetKey = storage.addPrefixToKey("target")
        assertTrue(backing.edit().putString(targetKey, "target value").commit())

        plugin.MethodRunner(call, result).run()

        assertEquals(1, errors)
        assertEquals(listOf("commit"), editorCalls)
        assertEquals("preserved", backing.getString("sentinel", null))
    }
}
