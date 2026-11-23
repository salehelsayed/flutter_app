package com.mknoon.app

import android.app.Application
import android.content.Context
import android.content.SharedPreferences
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Looper
import androidx.work.Configuration
import androidx.work.ListenableWorker
import androidx.work.NetworkType
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.WorkerFactory
import androidx.work.WorkerParameters
import androidx.work.testing.WorkManagerTestInitHelper
import com.bbflight.background_downloader.BDPlugin
import com.bbflight.background_downloader.BaseDirectory
import com.bbflight.background_downloader.DownloadTaskWorker
import com.bbflight.background_downloader.Task
import com.bbflight.background_downloader.TaskOptions
import com.bbflight.background_downloader.TaskStatus
import com.bbflight.background_downloader.Updates
import java.io.Closeable
import java.io.File
import java.io.IOException
import java.net.InetAddress
import java.net.ServerSocket
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowNetworkCapabilities

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], application = Application::class)
@LooperMode(LooperMode.Mode.PAUSED)
@Suppress("DEPRECATION")
class TranslatorDownloadWorkManagerTest {
    @Test
    fun `translator resumes the same constrained work from the exact saved offset`() {
        val app: Application = RuntimeEnvironment.getApplication()
        val prefs = android.preference.PreferenceManager.getDefaultSharedPreferences(app)
        prefs.edit().putInt(BDPlugin.keyConfigRequestTimeout, WAIT_SECONDS.toInt()).commit()
        val connectivity = app.getSystemService(ConnectivityManager::class.java)
        val network = checkNotNull(connectivity.activeNetwork)
        val capabilities = ShadowNetworkCapabilities.newInstance()
        shadowOf(capabilities).addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        shadowOf(capabilities).addCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        shadowOf(connectivity).setNetworkCapabilities(network, capabilities)

        val executor = Executors.newSingleThreadExecutor()
        val taskExecutor = Executors.newSingleThreadExecutor()
        val factory = DownloadWorkers()
        val configuration = Configuration.Builder()
            .setExecutor(executor)
            .setTaskExecutor(taskExecutor)
            .setWorkerFactory(factory)
            .build()
        WorkManagerTestInitHelper.initializeTestWorkManager(
            app,
            configuration,
            WorkManagerTestInitHelper.ExecutorsMode.PRESERVE_EXECUTORS,
        )
        val manager = WorkManager.getInstance(app)
        val driver = checkNotNull(WorkManagerTestInitHelper.getTestDriver(app))
        val taskId = "translator-held-${UUID.randomUUID()}"
        val tag = "taskId=$taskId"
        fun scheduled() = manager.getWorkInfosByTag(tag).get(WAIT_SECONDS, TimeUnit.SECONDS)

        try {
            RangeFixture().use { server ->
                val task = Task(
                    taskId = taskId,
                    url = server.url,
                    filename = "gemma-4-E2B-it.litertlm",
                    headers = mapOf("Accept-Encoding" to "identity"),
                    directory = "gemma_translation",
                    baseDirectory = BaseDirectory.applicationSupport,
                    group = "mknoon_gemma_translation",
                    updates = Updates.statusAndProgress,
                    allowPause = true,
                    options = TaskOptions(null, null, null, null, appManagedRecovery = true),
                    taskType = "DownloadTask",
                )
                val enqueued = executor.submit<Boolean> {
                    runBlocking { BDPlugin.doEnqueue(app, task, null, null) }
                }.get(WAIT_SECONDS, TimeUnit.SECONDS)
                assertTrue("the actual download request was accepted", enqueued)
                val initial = scheduled().single()
                assertEquals(NetworkType.CONNECTED, initial.constraints.requiredNetworkType)
                driver.setAllConstraintsMet(initial.id)

                await("the real download worker wrote the first response's prefix") {
                    BDPlugin.remainingBytesToDownload[taskId] == (server.payload.size - PREFIX_BYTES).toLong()
                }
                val partial = app.filesDir.listFiles().orEmpty().single {
                    it.name.startsWith("com.bbflight.background_downloader") &&
                        it.length() == PREFIX_BYTES.toLong()
                }
                assertArrayEquals(server.payload.copyOf(PREFIX_BYTES), partial.readBytes())
                assertEquals(1, server.requests.size)
                assertNull(server.requests.single()["range"])

                shadowOf(connectivity).setDefaultNetworkActive(false)
                driver.stopRunningWorkWithReason(initial.id, WorkInfo.STOP_REASON_CONSTRAINT_CONNECTIVITY)
                val firstWorker = factory.attempts.single()
                await("the first worker received the connectivity stop") { firstWorker.isStopped }
                assertEquals(WorkInfo.STOP_REASON_CONSTRAINT_CONNECTIVITY, firstWorker.stopReason)
                server.releasePrefix.countDown()

                await("the download recorded its post-stop status") {
                    val status = storedStatus(prefs, taskId)
                    status == TaskStatus.waitingToRetry.ordinal || status == TaskStatus.failed.ordinal
                }
                val held = scheduled().single()
                assertEquals(initial.id, held.id)
                assertEquals(
                    "keep the original WorkRequest scheduled after connectivity loss",
                    WorkInfo.State.ENQUEUED,
                    held.state,
                )
                assertEquals("the partial is still intact while held", PREFIX_BYTES.toLong(), partial.length())

                shadowOf(connectivity).setDefaultNetworkActive(true)
                driver.setAllConstraintsMet(initial.id)
                await("the original request made its resumed HTTP request") { server.requests.size == 2 }
                assertEquals("bytes=$PREFIX_BYTES-", server.requests[1]["range"])
                assertEquals(VALIDATOR, server.requests[1]["if-range"])
                assertEquals(listOf(initial.id, initial.id), factory.attempts.map { it.id })
                await("the resumed worker completed the original request") {
                    scheduled().single().state == WorkInfo.State.SUCCEEDED
                }
                val destination = File(task.filePath(app))
                assertArrayEquals(server.payload, destination.readBytes())
                assertEquals(listOf(initial.id), scheduled().map { it.id })
            }
        } finally {
            shadowOf(connectivity).setDefaultNetworkActive(true)
            manager.cancelAllWorkByTag(tag).result.get(WAIT_SECONDS, TimeUnit.SECONDS)
            WorkManagerTestInitHelper.closeWorkDatabase()
            executor.shutdownNow()
            taskExecutor.shutdownNow()
        }
    }

    private fun storedStatus(prefs: SharedPreferences, taskId: String): Int {
        val records = JSONObject(prefs.getString(BDPlugin.keyStatusUpdateMap, "{}") ?: "{}")
        val update = records.optString(taskId)
        return if (update.isEmpty()) -1 else JSONObject(update).optInt("taskStatus", -1)
    }

    private fun await(description: String, condition: () -> Boolean) {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(WAIT_SECONDS)
        do {
            shadowOf(Looper.getMainLooper()).idle()
            if (condition()) return
            Thread.sleep(10)
        } while (System.nanoTime() < deadline)
        throw AssertionError("Timed out waiting for $description")
    }

    private class DownloadWorkers : WorkerFactory() {
        val attempts = CopyOnWriteArrayList<DownloadTaskWorker>()

        override fun createWorker(
            appContext: Context,
            workerClassName: String,
            workerParameters: WorkerParameters,
        ): ListenableWorker? {
            if (workerClassName != DownloadTaskWorker::class.java.name) return null
            return DownloadTaskWorker(appContext, workerParameters).also { attempts += it }
        }
    }

    private class RangeFixture : Closeable {
        val payload = ByteArray(4 * PREFIX_BYTES) { (it % 251).toByte() }
        val requests = CopyOnWriteArrayList<Map<String, String>>()
        val releasePrefix = CountDownLatch(1)
        // The runner looks up ETag and Accept-Ranges by their exact spelling.
        private val socket = ServerSocket(0, 2, InetAddress.getByName("127.0.0.1"))
        private val executor = Executors.newSingleThreadExecutor()
        val url = "http://127.0.0.1:${socket.localPort}/model"

        init {
            executor.execute {
                try {
                    serve(first = true)
                    serve(first = false)
                } catch (_: IOException) {
                    // Closing the fixture also interrupts an unneeded second accept.
                }
            }
        }

        private fun serve(first: Boolean) {
            socket.accept().use { peer ->
                peer.soTimeout = TimeUnit.SECONDS.toMillis(WAIT_SECONDS).toInt()
                val input = peer.getInputStream().bufferedReader(Charsets.US_ASCII)
                check(input.readLine()?.startsWith("GET /model ") == true)
                val headers = buildMap {
                    while (true) {
                        val line = input.readLine() ?: error("Unfinished HTTP request")
                        if (line.isEmpty()) break
                        put(line.substringBefore(':').lowercase(), line.substringAfter(':').trim())
                    }
                }
                requests += headers
                val start = if (first) 0 else PREFIX_BYTES
                val status = if (first) "200 OK" else "206 Partial Content"
                val range = if (first) "" else "Content-Range: bytes $start-${payload.lastIndex}/${payload.size}\r\n"
                val response = "HTTP/1.1 $status\r\nContent-Length: ${payload.size - start}\r\n" +
                    "ETag: $VALIDATOR\r\nAccept-Ranges: bytes\r\n${range}Connection: close\r\n\r\n"
                peer.getOutputStream().apply {
                    write(response.toByteArray(Charsets.US_ASCII))
                    write(payload, start, if (first) PREFIX_BYTES else payload.size - start)
                    flush()
                }
                if (first) releasePrefix.await(WAIT_SECONDS, TimeUnit.SECONDS)
            }
        }

        override fun close() {
            releasePrefix.countDown()
            socket.close()
            executor.shutdownNow()
        }
    }

    private companion object {
        const val WAIT_SECONDS = 3L
        const val PREFIX_BYTES = 32 * 1024
        const val VALIDATOR = "\"translator-model-v1\""
    }
}
