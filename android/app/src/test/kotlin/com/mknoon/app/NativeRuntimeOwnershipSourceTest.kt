package com.mknoon.app

import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeRuntimeOwnershipSourceTest {
    @Test
    fun `GoBridge uses process host and deterministic detach instead of per engine initialize`() {
        val source = sourceFile("GoBridge.kt").readText()

        assertTrue(source.contains("runtimeHost.registerOwner("))
        assertTrue(source.contains("methodChannel.setMethodCallHandler(null)"))
        assertTrue(source.contains("eventChannel.setStreamHandler(null)"))
        assertTrue(source.contains("runtimeHost.unregister(ownerToken)"))
        assertFalse(source.contains("GoMknoon.initialize("))
        assertFalse(source.contains("Executors.newCachedThreadPool"))
    }

    @Test
    fun `MainActivity retains the engine for Dart DB close acknowledgement`() {
        val source = sourceFile("MainActivity.kt").readText()
        val cleanupStart = source.indexOf("override fun cleanUpFlutterEngine")
        val retain = source.indexOf("retainEngineForCanonicalShutdown = true", cleanupStart)
        val request = source.indexOf("requestCanonicalRuntimeShutdown(", cleanupStart)
        val goDispose = source.indexOf("goBridge?.dispose()", request)
        val leaseDispose = source.indexOf("canonicalRuntimeLeaseBridge?.dispose()", request)

        assertTrue(cleanupStart >= 0)
        assertTrue(retain > cleanupStart)
        assertTrue(request > retain)
        assertTrue(goDispose > request)
        assertTrue(leaseDispose > goDispose)
        assertTrue(source.contains("mknoon/canonical_runtime_shutdown"))
        assertTrue(source.contains("reply[\"databaseClosed\"] == true"))
        assertTrue(source.contains("override fun shouldDestroyEngineWithHost"))
        assertTrue(source.contains("shutdown_timeout_retained"))
        assertTrue(source.contains("retainedCanonicalRuntimeEngine = flutterEngine"))
        val retainStart = source.indexOf(
            "private fun retainCanonicalRuntimeEngineAfterFailedShutdown",
        )
        val finishStart = source.indexOf(
            "private fun finishCanonicalRuntimeEngineCleanup",
            retainStart,
        )
        val failedPath = source.substring(retainStart, finishStart)
        assertFalse(failedPath.contains("goBridge?.dispose()"))
        assertFalse(failedPath.contains("canonicalRuntimeLeaseBridge?.dispose()"))
        assertFalse(failedPath.contains("flutterEngine.destroy()"))
        assertTrue(source.contains("role = CanonicalRuntimeLeaseBroker.Role.FOREGROUND"))
    }

    @Test
    fun `production Dart shutdown quiesces Go closes DB and releases through one handshake`() {
        val source = repoFile(
            "lib/app/bootstrap/production_application_bootstrap.dart",
        ).readText()
        val owner = repoFile(
            "lib/app/bootstrap/foreground_canonical_runtime_startup.dart",
        ).readText()
        val construct = source.indexOf("ForegroundCanonicalRuntimeStartup<Database>(")
        val closeCallback = source.indexOf("await database.close().timeout", construct)
        // Since beta 2026-09-25 the shutdown runs through
        // CanonicalRuntimeShutdownSequence, which ends a live call (and sends
        // its terminate) before it delegates to the runtime session.
        val sequence = source.indexOf("CanonicalRuntimeShutdownSequence(", closeCallback)
        val delegate = source.indexOf("canonicalWritableRuntimeSession?.shutdown()", sequence)
        val shutdownStart = source.indexOf("Future<bool> shutdownCanonicalRuntime()", delegate)
        val viaSequence = source.indexOf("canonicalRuntimeShutdownSequence.shutdown()", shutdownStart)
        val channel = source.indexOf("'mknoon/canonical_runtime_shutdown'", viaSequence)
        val open = source.indexOf("await canonicalWritableRuntimeSession.open(", channel)

        assertTrue(construct >= 0)
        assertTrue(closeCallback > construct)
        assertTrue(sequence > closeCallback)
        assertTrue(delegate > sequence)
        assertTrue(shutdownStart > delegate)
        assertTrue(viaSequence > shutdownStart)
        assertTrue(channel > viaSequence)
        assertTrue("shutdown handler must exist before acquisition/open", open > channel)
        assertTrue(source.contains("isDatabaseOpen: (database) => database.isOpen"))
        assertTrue(source.contains("'databaseClosed': canonicalWritableRuntimeSession.databaseClosed"))
        assertTrue(source.contains("await shutdownCanonicalRuntime();"))
        assertTrue(source.contains("'leaseState': snapshot.state.name"))

        val cancel = owner.indexOf("_cancelled = true;", owner.indexOf("Future<bool> shutdown()"))
        val cleanup = owner.indexOf("_shutdownOwnedRuntime()", cancel)
        val settle = owner.indexOf("await _opening;", cleanup)
        val drain = owner.indexOf("_session.drainCloseRelease(", settle)
        val quiesce = owner.indexOf("await _gateway.quiesceRuntime()", drain)
        val close = owner.indexOf("await _closeDatabase(_database);", quiesce)
        val closed = owner.indexOf("if (!databaseClosed)", close)
        val released = owner.indexOf("state.state == CanonicalRuntimeLeaseState.released", closed)
        assertTrue(cancel >= 0)
        assertTrue(cleanup > cancel)
        assertTrue(settle > cleanup)
        assertTrue(drain > settle)
        assertTrue(quiesce > drain)
        assertTrue(close > quiesce)
        assertTrue(closed > close)
        assertTrue(released > closed)

    }

    private fun sourceFile(name: String): File = sequenceOf(
        File("src/main/kotlin/com/mknoon/app/$name"),
        File("android/app/src/main/kotlin/com/mknoon/app/$name"),
    ).firstOrNull(File::isFile) ?: error("Cannot locate $name")

    private fun repoFile(relativePath: String): File = sequenceOf(
        File(relativePath),
        File("../$relativePath"),
        File("../../$relativePath"),
    ).firstOrNull(File::isFile) ?: error("Cannot locate $relativePath")
}
