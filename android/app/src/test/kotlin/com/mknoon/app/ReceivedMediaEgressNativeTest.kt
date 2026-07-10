package com.mknoon.app

import android.app.Activity
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.OutputStream
import java.nio.file.Files
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Robolectric
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ReceivedMediaEgressNativeTest {
    @Test
    fun `share intent is ordered read-only and truthful for one and many`() {
        val one = ReceivedMediaEgressContracts.buildShareIntent(
            listOf(Uri.parse("content://com.mknoon.app.received-media/a")),
            listOf("image/jpeg"),
        )
        assertEquals(Intent.ACTION_SEND, one.action)
        assertTrue(one.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0)
        assertFalse(one.flags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION != 0)

        val uris = listOf(
            Uri.parse("content://com.mknoon.app.received-media/a"),
            Uri.parse("content://com.mknoon.app.received-media/b"),
        )
        val many = ReceivedMediaEgressContracts.buildShareIntent(uris, listOf("image/jpeg", "video/mp4"))
        assertEquals(Intent.ACTION_SEND_MULTIPLE, many.action)
        assertEquals("*/*", many.type)
        assertEquals(2, many.clipData!!.itemCount)
    }

    @Test
    fun `provider opens real Flutter Documents media and rejects sibling or write access`() {
        val context: Context = RuntimeEnvironment.getApplication()
        val documents = ReceivedMediaEgressProvider.documentsDirectory(context)
        val literalRoot = File(documents, "media").apply {
            deleteRecursively()
            mkdirs()
        }
        val source = File(literalRoot, "provider-proof.jpg").apply {
            parentFile!!.mkdirs()
            writeBytes(byteArrayOf(1, 4, 9))
        }
        val uri = ReceivedMediaEgressProvider.uriForFile(context, source)
        assertEquals("${context.packageName}.received-media", uri.authority)
        assertArrayEquals(byteArrayOf(1, 4, 9), context.contentResolver.openInputStream(uri)!!.readBytes())

        val intent = ReceivedMediaEgressContracts.buildShareIntent(listOf(uri), listOf("image/jpeg"))
        assertEquals(uri, intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))
        assertTrue(intent.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0)

        val outside = File(documents, "pending_uploads/secret.jpg").apply {
            parentFile!!.mkdirs()
            writeBytes(byteArrayOf(8))
        }
        assertThrows(IllegalArgumentException::class.java) {
            ReceivedMediaEgressProvider.uriForFile(context, outside)
        }
        assertThrows(Exception::class.java) {
            context.contentResolver.openFileDescriptor(uri, "w")
        }
    }

    @Test
    fun `provider rejects a symlinked literal root when creating and opening URI`() {
        val context: Context = RuntimeEnvironment.getApplication()
        val documents = ReceivedMediaEgressProvider.documentsDirectory(context)
        val literalRoot = File(documents, "media").apply { deleteRecursively() }
        val outsideParent = Files.createTempDirectory("egress-provider-outside").toFile()
        val outsideNamedMedia = File(outsideParent, "media").apply { mkdirs() }
        val outsideSource = File(outsideNamedMedia, "escape.jpg").apply { writeBytes(byteArrayOf(6, 2, 6)) }
        Files.createSymbolicLink(literalRoot.toPath(), outsideNamedMedia.toPath())

        assertThrows(IllegalArgumentException::class.java) {
            ReceivedMediaEgressProvider.uriForFile(context, outsideSource)
        }
        val crafted = Uri.parse("content://${context.packageName}.received-media/media/escape.jpg")
        assertThrows(Exception::class.java) {
            context.contentResolver.openInputStream(crafted)
        }

        literalRoot.delete()
        outsideParent.deleteRecursively()
    }

    @Test
    fun `parser rejects malformed envelopes and busy is ordered per input`() {
        val arguments = mapOf(
            "requestId" to "safe_1",
            "destination" to "files",
            "items" to listOf(
                mapOf("attachmentId" to "a", "sourcePath" to "/a", "mime" to "image/jpeg", "displayName" to "a.jpg"),
                mapOf("attachmentId" to "b", "sourcePath" to "/b", "mime" to "video/mp4", "displayName" to "b.mp4"),
            ),
        )
        val request = ReceivedMediaEgressContracts.parse(arguments)
        assertNotNull(request)
        val items = ReceivedMediaEgressContracts.busyEnvelope(request!!)["items"] as List<*>
        assertEquals(listOf("a", "b"), items.map { (it as Map<*, *>)["attachmentId"] })
        assertTrue(items.all { (it as Map<*, *>)["outcome"] == "busy" })
        assertNull(ReceivedMediaEgressContracts.parse(arguments + ("extra" to true)))
        assertNull(ReceivedMediaEgressContracts.parse(arguments + ("requestId" to "../unsafe")))
    }

    @Test
    fun `partial rollback publication and restart sweep are causally invocation scoped`() {
        assertEquals(".mknoon-egress-safe_1-0.part", ReceivedMediaEgressContracts.stagingName("safe_1", 0))
        assertEquals(".mknoon-egress-safe_1-1.part", ReceivedMediaEgressContracts.stagingName("safe_1", 1))
        assertTrue(ReceivedMediaEgressContracts.isManagedStagingName(".mknoon-egress-safe_1-9.part"))
        assertFalse(ReceivedMediaEgressContracts.isManagedStagingName("mknoon-egress-safe_1-9.part"))
        assertFalse(ReceivedMediaEgressContracts.isManagedStagingName(".mknoon-egress-../-9.part"))
        assertFalse(ReceivedMediaEgressContracts.isValidRequestId("../unsafe"))

        val source = File.createTempFile("egress-source", ".jpg").apply { writeBytes(byteArrayOf(2, 3, 5)) }
        val store = FakeScopedStore()
        val saver = ReceivedMediaScopedSaver(store)
        val request = NativeEgressRequest(
            "safe_1",
            "photos",
            listOf(NativeEgressItem("a", source.path, "image/jpeg", "a.jpg")),
        )
        saver.save(request, request.items.single(), 0)
        assertEquals(1, store.inserts.size)
        assertEquals(1, store.updates.size)
        assertEquals(0, store.deletes.size)
        assertEquals(1, store.inserts.single().second.getAsInteger(MediaStore.MediaColumns.IS_PENDING))
        assertEquals(0, store.updates.single().second.getAsInteger(MediaStore.MediaColumns.IS_PENDING))
        assertArrayEquals(source.readBytes(), store.output.toByteArray())

        store.updateCount = 0
        assertThrows(IllegalStateException::class.java) { saver.save(request, request.items.single(), 1) }
        assertEquals(1, store.deletes.size)

        store.pending += ScopedPendingRow(Uri.parse("content://proof/owned"), ".mknoon-egress-safe_1-9.part")
        store.pending += ScopedPendingRow(Uri.parse("content://proof/foreign"), "foreign.pending")
        saver.sweep()
        assertEquals(
            listOf("Pictures/Mknoon/", "Movies/Mknoon/", "Download/Mknoon/"),
            store.queriedRelativePaths,
        )
        assertTrue(store.deletes.contains(Uri.parse("content://proof/owned")))
        assertFalse(store.deletes.contains(Uri.parse("content://proof/foreign")))
    }

    @Test
    fun `api bands select scoped or legacy storage without broad permission`() {
        assertEquals(ReceivedMediaEgressContracts.StorageBand.LEGACY, ReceivedMediaEgressContracts.storageBand(28))
        assertEquals(ReceivedMediaEgressContracts.StorageBand.SCOPED, ReceivedMediaEgressContracts.storageBand(29))
        assertTrue(ReceivedMediaEgressContracts.needsLegacyPermission(28))
        assertFalse(ReceivedMediaEgressContracts.needsLegacyPermission(29))
    }

    @Test
    fun `busy gate permits one operation and ignores late release`() {
        val gate = ReceivedMediaEgressBusyGate()
        assertTrue(gate.tryBegin())
        assertFalse(gate.tryBegin())
        gate.end()
        gate.end()
        assertFalse(gate.isBusy())
        assertTrue(gate.tryBegin())
    }

    @Test
    fun `actual handler drives api28 permission busy and one shot completion`() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        var permissionRequests = 0
        var saves = 0
        val handler = ReceivedMediaEgressHandler(
            activity = activity,
            messenger = null,
            sdkInt = 28,
            legacyPermissionGranted = { false },
            requestLegacyPermission = { permissionRequests++ },
            legacyStore = ReceivedMediaLegacyStore(directoryForType = { Files.createTempDirectory("legacy-unused").toFile() }),
            saveItemOverride = { _, _, _ -> saves++ },
            operationExecutor = { it() },
            mainExecutor = { it() },
        )
        val first = CapturingResult()
        handler.onMethodCall(MethodCall("perform", nativeArguments("permission", "files")), first)
        assertEquals(1, permissionRequests)
        assertNull(first.value)

        val concurrent = CapturingResult()
        handler.onMethodCall(MethodCall("perform", nativeArguments("concurrent", "files")), concurrent)
        assertEquals("busy", (concurrent.value as Map<*, *>)["outcome"])

        assertTrue(handler.onRequestPermissionsResult(9727, intArrayOf(PackageManager.PERMISSION_GRANTED)))
        assertEquals(1, saves)
        assertEquals("saved", (first.value as Map<*, *>)["outcome"])
        assertFalse(handler.onRequestPermissionsResult(1, intArrayOf()))
    }

    @Test
    fun `actual handler retains share busy until resume and presents once per operation`() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        var presentations = 0
        val source = providerSource(activity, "share-lifecycle.jpg")
        val handler = ReceivedMediaEgressHandler(
            activity = activity,
            messenger = null,
            sdkInt = 34,
            presentShare = { presentations++ },
            operationExecutor = { it() },
            mainExecutor = { it() },
        )
        val first = CapturingResult()
        handler.onMethodCall(MethodCall("perform", nativeArguments("share_one", "share", source.path)), first)
        assertEquals("presented", (first.value as Map<*, *>)["outcome"])
        val second = CapturingResult()
        handler.onMethodCall(MethodCall("perform", nativeArguments("share_two", "share", source.path)), second)
        assertEquals("busy", (second.value as Map<*, *>)["outcome"])
        assertEquals(1, presentations)

        handler.onResume()
        val third = CapturingResult()
        handler.onMethodCall(MethodCall("perform", nativeArguments("share_three", "share", source.path)), third)
        assertEquals("presented", (third.value as Map<*, *>)["outcome"])
        assertEquals(2, presentations)
    }

    @Test
    fun `actual handler preserves successful sibling when a later save rolls back`() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val completed = mutableListOf<String>()
        val handler = ReceivedMediaEgressHandler(
            activity = activity,
            messenger = null,
            sdkInt = 34,
            saveItemOverride = { _, item, index ->
                if (index == 1) error("copy failed")
                completed += item.attachmentId
            },
            operationExecutor = { it() },
            mainExecutor = { it() },
        )
        val result = CapturingResult()
        handler.onMethodCall(
            MethodCall("perform", nativeArguments("siblings", "photos", itemCount = 2)),
            result,
        )
        assertEquals(listOf("a"), completed)
        val envelope = result.value as Map<*, *>
        assertEquals("partial", envelope["outcome"])
        assertEquals(listOf("saved", "platformFailure"),
            (envelope["items"] as List<*>).map { (it as Map<*, *>)["outcome"] })
    }

    @Test
    fun `fresh actual handler sweeps only exact legacy staging markers`() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val root = Files.createTempDirectory("legacy-sweep").toFile()
        val pictures = File(root, Environment.DIRECTORY_PICTURES).apply { mkdirs() }
        val owned = File(pictures, ".mknoon-egress-restart_1-0.part").apply { writeText("partial") }
        val successful = File(pictures, "kept.jpg").apply { writeText("saved") }
        val nearMiss = File(pictures, "mknoon-egress-restart_1-0.part").apply { writeText("foreign") }
        val store = ReceivedMediaLegacyStore(directoryForType = { type -> File(root, type) })

        ReceivedMediaEgressHandler(
            activity = activity,
            messenger = null,
            sdkInt = 28,
            legacyStore = store,
            operationExecutor = { it() },
            mainExecutor = { it() },
        )

        assertFalse(owned.exists())
        assertTrue(successful.exists())
        assertTrue(nearMiss.exists())
        root.deleteRecursively()
    }

    private fun providerSource(context: Context, name: String): File {
        val root = File(ReceivedMediaEgressProvider.documentsDirectory(context), "media").apply {
            deleteRecursively()
            mkdirs()
        }
        return File(root, name).apply { writeBytes(byteArrayOf(1, 2, 3)) }
    }

    private fun nativeArguments(
        requestId: String,
        destination: String,
        sourcePath: String = File.createTempFile("egress-input", ".jpg").apply { writeBytes(byteArrayOf(1)) }.path,
        itemCount: Int = 1,
    ): Map<String, Any> = mapOf(
        "requestId" to requestId,
        "destination" to destination,
        "items" to (0 until itemCount).map { index ->
            mapOf(
                "attachmentId" to ('a'.code + index).toChar().toString(),
                "sourcePath" to sourcePath,
                "mime" to "image/jpeg",
                "displayName" to "${('a'.code + index).toChar()}.jpg",
            )
        },
    )
}

private class CapturingResult : MethodChannel.Result {
    var value: Any? = null
    override fun success(result: Any?) { value = result }
    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        value = mapOf("errorCode" to errorCode)
    }
    override fun notImplemented() { value = "notImplemented" }
}

private class FakeScopedStore : ReceivedMediaScopedStore {
    val inserts = mutableListOf<Pair<Uri, ContentValues>>()
    val updates = mutableListOf<Pair<Uri, ContentValues>>()
    val deletes = mutableListOf<Uri>()
    val pending = mutableListOf<ScopedPendingRow>()
    val queriedRelativePaths = mutableListOf<String>()
    val output = ByteArrayOutputStream()
    var updateCount = 1
    private var ordinal = 0

    override fun insert(collection: Uri, values: ContentValues): Uri {
        inserts += collection to ContentValues(values)
        return Uri.parse("content://proof/${ordinal++}")
    }
    override fun openOutput(uri: Uri): OutputStream = output
    override fun update(uri: Uri, values: ContentValues): Int {
        updates += uri to ContentValues(values)
        return updateCount
    }
    override fun delete(uri: Uri): Int { deletes += uri; return 1 }
    override fun pendingRows(collection: Uri, relativePath: String): List<ScopedPendingRow> {
        queriedRelativePaths += relativePath
        return pending.toList()
    }
}
