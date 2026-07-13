package com.mknoon.background_push_crypto

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.ArgumentMatchers.any
import org.mockito.Mockito.mock
import org.mockito.Mockito.verify
import org.mockito.Mockito.`when`
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class BackgroundPushCryptoPluginTest {
    @Test
    fun `registers on headless engine without replacing main callback`() {
        val messenger = mock(BinaryMessenger::class.java)
        val binding = mock(FlutterPlugin.FlutterPluginBinding::class.java)
        `when`(binding.binaryMessenger).thenReturn(messenger)
        val native = RecordingNative("{\"ok\":true,\"plaintext\":\"{}\"}")
        val plugin = BackgroundPushCryptoPlugin(
            native = native,
            executeWork = { work -> work() },
            postResult = { work -> work() },
        )

        plugin.onAttachedToEngine(binding)

        verify(messenger).setMessageHandler(
            any(String::class.java),
            any(BinaryMessenger.BinaryMessageHandler::class.java),
        )
        val nativeMethods = BackgroundPushCryptoNative::class.java.declaredMethods
            .map { method -> method.name }
            .sorted()
        assertEquals(listOf("decryptGroupMessage", "decryptMessage", "verifyPayload"), nativeMethods)
        assertFalse(nativeMethods.any { method ->
            method.contains("initialize", ignoreCase = true) ||
                method.contains("callback", ignoreCase = true)
        })

        val result = CapturingResult()
        plugin.onMethodCall(MethodCall("decryptMessage", "{\"secretKey\":\"s\"}"), result)
        assertEquals("{\"secretKey\":\"s\"}", native.messageInput)
        assertEquals("{\"ok\":true,\"plaintext\":\"{}\"}", result.successValue)
    }

    @Test
    fun groupDecryptMatchesGoFixture() {
        val native = RecordingNative(
            response = "{\"ok\":true,\"plaintext\":\"{\\\"emoji\\\":\\\"👍\\\"}\"}",
        )
        val plugin = BackgroundPushCryptoPlugin(
            native = native,
            executeWork = { work -> work() },
            postResult = { work -> work() },
        )
        val input =
            "{\"groupKey\":\"group-secret\",\"ciphertext\":\"group-ciphertext\",\"nonce\":\"group-nonce\"}"
        val result = CapturingResult()

        plugin.onMethodCall(MethodCall("decryptGroup", input), result)

        assertEquals(input, native.groupInput)
        assertEquals(
            "{\"ok\":true,\"plaintext\":\"{\\\"emoji\\\":\\\"👍\\\"}\"}",
            result.successValue,
        )
    }

    @Test
    fun verifyPayloadUsesStatelessGoBridgeMethod() {
        val native = RecordingNative(response = "{\"ok\":true,\"valid\":true}")
        val plugin = BackgroundPushCryptoPlugin(
            native = native,
            executeWork = { work -> work() },
            postResult = { work -> work() },
        )
        val input =
            "{\"publicKey\":\"sender-key\",\"data\":\"canonical\",\"signature\":\"sig\"}"
        val result = CapturingResult()

        plugin.onMethodCall(MethodCall("verifyPayload", input), result)

        assertEquals(input, native.verifyInput)
        assertEquals("{\"ok\":true,\"valid\":true}", result.successValue)
    }

    private class RecordingNative(private val response: String) : BackgroundPushCryptoNative {
        var messageInput: String? = null
        var groupInput: String? = null
        var verifyInput: String? = null

        override fun decryptMessage(argumentsJson: String): String {
            messageInput = argumentsJson
            return response
        }

        override fun decryptGroupMessage(argumentsJson: String): String {
            groupInput = argumentsJson
            return response
        }

        override fun verifyPayload(argumentsJson: String): String {
            verifyInput = argumentsJson
            return response
        }
    }

    private class CapturingResult : MethodChannel.Result {
        var successValue: Any? = null

        override fun success(result: Any?) {
            successValue = result
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            throw AssertionError("unexpected native error: $errorCode $errorMessage")
        }

        override fun notImplemented() {
            throw AssertionError("method unexpectedly not implemented")
        }
    }
}
