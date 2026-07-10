package com.mknoon.app

import android.Manifest
import android.app.Activity
import android.content.ClipData
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.OutputStream

internal class ReceivedMediaEgressBusyGate {
    private var active = false
    @Synchronized fun tryBegin(): Boolean {
        if (active) return false
        active = true
        return true
    }
    @Synchronized fun end() { active = false }
    @Synchronized fun isBusy() = active
}

internal data class ScopedPendingRow(val uri: Uri, val displayName: String)

internal interface ReceivedMediaScopedStore {
    fun insert(collection: Uri, values: ContentValues): Uri?
    fun openOutput(uri: Uri): OutputStream?
    fun update(uri: Uri, values: ContentValues): Int
    fun delete(uri: Uri): Int
    fun pendingRows(collection: Uri, relativePath: String): List<ScopedPendingRow>
}

internal class AndroidReceivedMediaScopedStore(private val activity: Activity) : ReceivedMediaScopedStore {
    private val resolver get() = activity.contentResolver
    override fun insert(collection: Uri, values: ContentValues) = resolver.insert(collection, values)
    override fun openOutput(uri: Uri) = resolver.openOutputStream(uri, "w")
    override fun update(uri: Uri, values: ContentValues) = resolver.update(uri, values, null, null)
    override fun delete(uri: Uri) = resolver.delete(uri, null, null)
    override fun pendingRows(collection: Uri, relativePath: String): List<ScopedPendingRow> {
        val rows = mutableListOf<ScopedPendingRow>()
        resolver.query(
            collection,
            arrayOf(MediaStore.MediaColumns._ID, MediaStore.MediaColumns.DISPLAY_NAME),
            "${MediaStore.MediaColumns.IS_PENDING}=1 AND ${MediaStore.MediaColumns.RELATIVE_PATH}=?",
            arrayOf(relativePath),
            null,
        )?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            val nameColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
            while (cursor.moveToNext()) {
                rows += ScopedPendingRow(
                    Uri.withAppendedPath(collection, cursor.getLong(idColumn).toString()),
                    cursor.getString(nameColumn),
                )
            }
        }
        return rows
    }
}

internal class ReceivedMediaScopedSaver(private val store: ReceivedMediaScopedStore) {
    data class Target(val collection: Uri, val relativePath: String)

    fun target(destination: String, mime: String): Target = when {
        destination == "files" -> Target(MediaStore.Downloads.EXTERNAL_CONTENT_URI, "Download/Mknoon/")
        mime.startsWith("image/") -> Target(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, "Pictures/Mknoon/")
        else -> Target(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, "Movies/Mknoon/")
    }

    fun save(request: NativeEgressRequest, item: NativeEgressItem, index: Int) {
        val target = target(request.destination, item.mime)
        val uri = store.insert(target.collection, ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, ReceivedMediaEgressContracts.stagingName(request.requestId, index))
            put(MediaStore.MediaColumns.MIME_TYPE, item.mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, target.relativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }) ?: error("insert failed")
        try {
            FileInputStream(File(item.sourcePath)).use { input ->
                store.openOutput(uri)!!.use { output -> input.copyTo(output) }
            }
            val updated = store.update(uri, ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, item.displayName)
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            })
            check(updated == 1) { "publish update did not affect exactly one row" }
        } catch (error: Exception) {
            store.delete(uri)
            throw error
        }
    }

    fun sweep() {
        listOf(
            Target(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, "Pictures/Mknoon/"),
            Target(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, "Movies/Mknoon/"),
            Target(MediaStore.Downloads.EXTERNAL_CONTENT_URI, "Download/Mknoon/"),
        ).forEach { target ->
            store.pendingRows(target.collection, target.relativePath)
                .filter { ReceivedMediaEgressContracts.isManagedStagingName(it.displayName) }
                .forEach { store.delete(it.uri) }
        }
    }
}

internal class ReceivedMediaLegacyStore(
    private val directoryForType: (String) -> File = { type ->
        File(Environment.getExternalStoragePublicDirectory(type), "Mknoon")
    },
    private val publish: (File) -> Unit = {},
) {
    fun save(request: NativeEgressRequest, item: NativeEgressItem, index: Int) {
        val type = when {
            request.destination == "files" -> Environment.DIRECTORY_DOWNLOADS
            item.mime.startsWith("image/") -> Environment.DIRECTORY_PICTURES
            else -> Environment.DIRECTORY_MOVIES
        }
        val directory = directoryForType(type).apply { mkdirs() }
        val finalFile = uniqueFile(directory, item.displayName)
        val stage = File(directory, ReceivedMediaEgressContracts.stagingName(request.requestId, index))
        try {
            FileInputStream(File(item.sourcePath)).use { input ->
                stage.outputStream().use { input.copyTo(it) }
            }
            if (!stage.renameTo(finalFile)) error("commit failed")
            publish(finalFile)
        } catch (error: Exception) {
            stage.delete()
            throw error
        }
    }

    fun sweep() {
        listOf(Environment.DIRECTORY_PICTURES, Environment.DIRECTORY_MOVIES, Environment.DIRECTORY_DOWNLOADS)
            .map(directoryForType)
            .forEach { directory ->
                directory.listFiles()
                    ?.filter { ReceivedMediaEgressContracts.isManagedStagingName(it.name) }
                    ?.forEach(File::delete)
            }
    }

    private fun uniqueFile(directory: File, displayName: String): File {
        var candidate = File(directory, displayName)
        var ordinal = 1
        val dot = displayName.lastIndexOf('.')
        val stem = if (dot > 0) displayName.substring(0, dot) else displayName
        val ext = if (dot > 0) displayName.substring(dot) else ""
        while (candidate.exists()) candidate = File(directory, "$stem-$ordinal$ext").also { ordinal++ }
        return candidate
    }
}

internal object ReceivedMediaEgressContracts {
    private val requestId = Regex("^[A-Za-z0-9_-]{1,64}$")
    private val staging = Regex("^\\.mknoon-egress-[A-Za-z0-9_-]{1,64}-[0-9]+\\.part$")
    private val allowedMimes = setOf(
        "image/jpeg", "image/png", "image/gif", "image/webp", "image/heic",
        "video/mp4", "video/quicktime", "video/webm",
    )
    enum class StorageBand { LEGACY, SCOPED }

    fun isValidRequestId(value: String) = requestId.matches(value)
    fun stagingName(requestId: String, index: Int): String {
        require(isValidRequestId(requestId))
        return ".mknoon-egress-$requestId-$index.part"
    }
    fun isManagedStagingName(value: String) = staging.matches(value)
    fun storageBand(sdk: Int) = if (sdk >= 29) StorageBand.SCOPED else StorageBand.LEGACY
    fun needsLegacyPermission(sdk: Int) = storageBand(sdk) == StorageBand.LEGACY

    fun buildShareIntent(uris: List<Uri>, mimes: List<String>): Intent {
        require(uris.isNotEmpty() && uris.size == mimes.size)
        val commonMime = if (mimes.all { it.startsWith("image/") }) "image/*"
            else if (mimes.all { it.startsWith("video/") }) "video/*" else "*/*"
        val intent = Intent(if (uris.size == 1) Intent.ACTION_SEND else Intent.ACTION_SEND_MULTIPLE)
        intent.type = commonMime
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        intent.clipData = ClipData("Mknoon received media", arrayOf(commonMime), ClipData.Item(uris.first())).also { clip ->
            uris.drop(1).forEach { clip.addItem(ClipData.Item(it)) }
        }
        if (uris.size == 1) intent.putExtra(Intent.EXTRA_STREAM, uris.first())
        else intent.putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))
        return intent
    }

    fun parse(arguments: Any?): NativeEgressRequest? {
        val map = arguments as? Map<*, *> ?: return null
        if (map.keys != setOf("requestId", "destination", "items")) return null
        val requestId = map["requestId"] as? String ?: return null
        val destination = map["destination"] as? String ?: return null
        val rawItems = map["items"] as? List<*> ?: return null
        if (!isValidRequestId(requestId) || destination !in setOf("photos", "files", "share") || rawItems.isEmpty() || rawItems.size > 10) return null
        val ids = mutableSetOf<String>()
        val items = rawItems.map { raw ->
            val item = raw as? Map<*, *> ?: return null
            if (item.keys != setOf("attachmentId", "sourcePath", "mime", "displayName")) return null
            val id = item["attachmentId"] as? String ?: return null
            val source = item["sourcePath"] as? String ?: return null
            val mime = item["mime"] as? String ?: return null
            val display = item["displayName"] as? String ?: return null
            if (id.isBlank() || !ids.add(id) || source.isBlank() || mime !in allowedMimes ||
                display.isBlank() || display.contains('/') || display.contains('\\')) return null
            NativeEgressItem(id, source, mime, display)
        }
        return NativeEgressRequest(requestId, destination, items)
    }

    fun busyEnvelope(request: NativeEgressRequest): Map<String, Any> = mapOf(
        "requestId" to request.requestId,
        "outcome" to "busy",
        "items" to if (request.destination == "share") emptyList<Map<String, Any>>() else request.items.map {
            mapOf<String, Any>("attachmentId" to it.attachmentId, "outcome" to "busy")
        },
    )
}

internal data class NativeEgressItem(
    val attachmentId: String,
    val sourcePath: String,
    val mime: String,
    val displayName: String,
)

internal data class NativeEgressRequest(
    val requestId: String,
    val destination: String,
    val items: List<NativeEgressItem>,
)

internal class ReceivedMediaEgressHandler(
    private val activity: Activity,
    messenger: BinaryMessenger?,
    private val sdkInt: Int = Build.VERSION.SDK_INT,
    private val legacyPermissionGranted: () -> Boolean = {
        activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
    },
    private val requestLegacyPermission: () -> Unit = {
        activity.requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), permissionCode)
    },
    private val presentShare: (Intent) -> Unit = { intent -> activity.startActivity(Intent.createChooser(intent, null)) },
    scopedStore: ReceivedMediaScopedStore = AndroidReceivedMediaScopedStore(activity),
    legacyStore: ReceivedMediaLegacyStore = ReceivedMediaLegacyStore(
        publish = { file -> activity.sendBroadcast(Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE, Uri.fromFile(file))) },
    ),
    private val saveItemOverride: ((NativeEgressRequest, NativeEgressItem, Int) -> Unit)? = null,
    private val operationExecutor: (() -> Unit) -> Unit = { work -> Thread(work).start() },
    private val mainExecutor: (() -> Unit) -> Unit = { work -> activity.runOnUiThread(work) },
) {
    companion object {
        private const val channelName = "mknoon/received_media_egress"
        private const val permissionCode = 9727
    }

    private val channel = messenger?.let { MethodChannel(it, channelName) }
    private val busyGate = ReceivedMediaEgressBusyGate()
    private val scopedSaver = ReceivedMediaScopedSaver(scopedStore)
    private val legacyStore = legacyStore
    private var waitingForShareResume = false
    private var pendingPermission: Pair<NativeEgressRequest, MethodChannel.Result>? = null

    init {
        try { legacyStore.sweep() } catch (_: Exception) { /* best-effort exact-marker recovery */ }
        if (sdkInt >= 29) {
            try { scopedSaver.sweep() } catch (_: Exception) { /* never fail channel registration */ }
        }
        channel?.setMethodCallHandler(::onMethodCall)
    }

    internal fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "perform") {
            result.notImplemented()
            return
        }
        val request = ReceivedMediaEgressContracts.parse(call.arguments)
        if (request == null) {
            result.error("invalid_arguments", "invalid request", null)
            return
        }
        if (!busyGate.tryBegin()) {
            result.success(ReceivedMediaEgressContracts.busyEnvelope(request))
            return
        }
        when (request.destination) {
            "share" -> share(request, result)
            "photos", "files" -> {
                if (ReceivedMediaEgressContracts.needsLegacyPermission(sdkInt) &&
                    !legacyPermissionGranted()
                ) {
                    pendingPermission = request to result
                    requestLegacyPermission()
                } else save(request, result)
            }
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != permissionCode) return false
        val pending = pendingPermission ?: return true
        pendingPermission = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) save(pending.first, pending.second)
        else {
            val items = pending.first.items.map { itemResult(it.attachmentId, "permissionDenied") }
            pending.second.success(envelope(pending.first.requestId, "permissionDenied", items))
            busyGate.end()
        }
        return true
    }

    fun onResume() {
        if (waitingForShareResume) {
            waitingForShareResume = false
            busyGate.end()
        }
    }

    private fun share(request: NativeEgressRequest, result: MethodChannel.Result) {
        try {
            val uris = request.items.map {
                ReceivedMediaEgressProvider.uriForFile(activity, File(it.sourcePath))
            }
            val intent = ReceivedMediaEgressContracts.buildShareIntent(uris, request.items.map { it.mime })
            presentShare(intent)
            waitingForShareResume = true
            result.success(envelope(request.requestId, "presented", emptyList()))
        } catch (_: Exception) {
            busyGate.end()
            result.success(envelope(request.requestId, "platformFailure", emptyList()))
        }
    }

    private fun save(request: NativeEgressRequest, result: MethodChannel.Result) {
        operationExecutor {
            val itemResults = request.items.mapIndexed { index, item ->
                val outcome = try {
                    val override = saveItemOverride
                    if (override != null) override(request, item, index)
                    else if (sdkInt >= 29) scopedSaver.save(request, item, index)
                    else legacyStore.save(request, item, index)
                    "saved"
                } catch (_: java.io.FileNotFoundException) { "missingFile" }
                catch (_: SecurityException) { "permissionDenied" }
                catch (_: Exception) { "platformFailure" }
                itemResult(item.attachmentId, outcome)
            }
            val outcomes = itemResults.map { it["outcome"] }
            val aggregate = when {
                outcomes.all { it == "saved" } -> "saved"
                outcomes.any { it == "saved" } -> "partial"
                outcomes.any { it == "platformFailure" } -> "platformFailure"
                outcomes.any { it == "permissionDenied" } -> "permissionDenied"
                else -> "rejected"
            }
            mainExecutor {
                busyGate.end()
                result.success(envelope(request.requestId, aggregate, itemResults))
            }
        }
    }

    private fun itemResult(id: String, outcome: String) = mapOf<String, Any>("attachmentId" to id, "outcome" to outcome)
    private fun envelope(requestId: String, outcome: String, items: List<Map<String, Any>>) =
        mapOf<String, Any>("requestId" to requestId, "outcome" to outcome, "items" to items)
}
