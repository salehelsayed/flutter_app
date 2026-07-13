package com.mknoon.background_push_crypto

import android.os.Handler
import android.os.Looper
import bridge.Bridge
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

internal interface BackgroundPushCryptoNative {
    fun decryptMessage(argumentsJson: String): String
    fun decryptGroupMessage(argumentsJson: String): String
    fun verifyPayload(argumentsJson: String): String
}

private object GoBackgroundPushCryptoNative : BackgroundPushCryptoNative {
    override fun decryptMessage(argumentsJson: String): String =
        Bridge.decryptMessage(argumentsJson)

    override fun decryptGroupMessage(argumentsJson: String): String =
        Bridge.groupDecryptMessage(argumentsJson)

    override fun verifyPayload(argumentsJson: String): String =
        Bridge.verifyPayload(argumentsJson)
}

class BackgroundPushCryptoPlugin() : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var native: BackgroundPushCryptoNative = GoBackgroundPushCryptoNative
    private var executeWork: ((() -> Unit) -> Unit) = { work -> executor.execute(work) }
    private var postResult: ((() -> Unit) -> Unit) = { work ->
        Handler(Looper.getMainLooper()).post(work)
    }

    internal constructor(
        native: BackgroundPushCryptoNative,
        executeWork: ((() -> Unit) -> Unit) = { work -> work() },
        postResult: ((() -> Unit) -> Unit) = { work -> work() },
    ) : this() {
        this.native = native
        this.executeWork = executeWork
        this.postResult = postResult
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val operation = when (call.method) {
            "decryptMessage" -> native::decryptMessage
            "decryptGroup" -> native::decryptGroupMessage
            "verifyPayload" -> native::verifyPayload
            else -> {
                result.notImplemented()
                return
            }
        }
        val arguments = call.arguments as? String
        if (arguments.isNullOrBlank()) {
            result.error("BAD_ARGUMENTS", "encrypted message JSON is required", null)
            return
        }

        executeWork {
            try {
                val response = operation(arguments)
                postResult { result.success(response) }
            } catch (error: Throwable) {
                postResult {
                    result.error(
                        "CRYPTO_FAILED",
                        error.message ?: "background crypto operation failed",
                        null,
                    )
                }
            }
        }
    }

    private companion object {
        const val CHANNEL_NAME = "com.mknoon/background_push_crypto"
        val executor: ExecutorService = Executors.newCachedThreadPool()
    }
}
