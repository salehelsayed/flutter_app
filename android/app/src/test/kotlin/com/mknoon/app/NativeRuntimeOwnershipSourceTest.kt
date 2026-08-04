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
        val shutdownStart = source.indexOf("Future<bool> shutdownCanonicalRuntime()")
        val drain = source.indexOf("writableSession.drainCloseRelease(", shutdownStart)
        val quiesce = source.indexOf("canonicalRuntimeLeaseGateway!.quiesceRuntime()", drain)
        val close = source.indexOf("db.close().timeout", quiesce)
        val channel = source.indexOf("'mknoon/canonical_runtime_shutdown'", close)

        assertTrue(shutdownStart >= 0)
        assertTrue(drain > shutdownStart)
        assertTrue(quiesce > drain)
        assertTrue(close > quiesce)
        assertTrue(channel > close)
        assertTrue(source.contains("'databaseClosed': !db.isOpen"))
        assertTrue(source.contains("await shutdownCanonicalRuntime();"))
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
