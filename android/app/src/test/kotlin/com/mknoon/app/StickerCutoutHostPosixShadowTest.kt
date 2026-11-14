package com.mknoon.app

import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import java.io.FileDescriptor
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.attribute.PosixFilePermission
import java.util.concurrent.CyclicBarrier
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.shadow.api.Shadow
import org.robolectric.util.ReflectionHelpers

/** Independent controls must pass before cutout results count as RED or GREEN. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], shadows = [StickerCutoutHostPosixShadow::class, StickerCutoutHostOsConstantsShadow::class, StickerCutoutHostBlockGuardOsShadow::class])
class StickerCutoutHostPosixShadowTest {
    @get:Rule val temporary = TemporaryFolder()
    private val libcore = Class.forName("libcore.io.Libcore")
    private var previousRawOs: Any? = null
    private var previousOs: Any? = null

    @Before
    fun installOsInstancesForCurrentShadowMap() {
        // Robolectric reuses this sandbox across classes and changes dispatch,
        // but Libcore retains OS instances with the previous class's shadows.
        previousRawOs = ReflectionHelpers.getStaticField<Any>(libcore, "rawOs")
        previousOs = ReflectionHelpers.getStaticField<Any>(libcore, "os")
        Shadow.directInitialize(libcore)
    }

    @After
    fun closeOnlyShadowOwnedDescriptors() {
        try {
            StickerCutoutHostPosixShadow.reset()
        } finally {
            // Restore the original chain so later classes keep their own OS.
            previousRawOs?.let { ReflectionHelpers.setStaticField(libcore, "rawOs", it) }
            previousOs?.let { ReflectionHelpers.setStaticField(libcore, "os", it) }
            previousRawOs = null
            previousOs = null
        }
    }

    @Test
    fun lstatReportsMissingPathsAndPreservesSymlinkIdentity() {
        val missing = temporary.root.toPath().resolve("missing")
        assertErrno(OsConstants.ENOENT) { Os.lstat(missing.toString()) }
        val target = temporary.newFile("target").apply { writeBytes(byteArrayOf(1, 2, 3, 4)) }
        val link = temporary.root.toPath().resolve("link")
        Files.createSymbolicLink(link, target.toPath())
        val regular = Os.lstat(target.path)
        val symbolic = Os.lstat(link.toString())
        val followed = Os.stat(link.toString())
        val host = Files.readAttributes(target.toPath(), "unix:*", LinkOption.NOFOLLOW_LINKS)
        assertTrue(OsConstants.S_ISREG(regular.st_mode))
        assertTrue(OsConstants.S_ISLNK(symbolic.st_mode))
        assertNotEquals(regular.st_ino, symbolic.st_ino)
        assertEquals((host.getValue("dev") as Number).toLong(), regular.st_dev)
        assertEquals((host.getValue("ino") as Number).toLong(), regular.st_ino)
        assertEquals(4L, regular.st_size)
        assertEquals(regular.st_dev, followed.st_dev)
        assertEquals(regular.st_ino, followed.st_ino)
        assertTrue(OsConstants.S_ISDIR(Os.lstat(temporary.root.path).st_mode))

        target.delete()
        assertTrue("dangling symlink still exists for lstat", OsConstants.S_ISLNK(Os.lstat(link.toString()).st_mode))
        assertErrno(OsConstants.ENOENT) { Os.stat(link.toString()) }
    }

    @Test
    fun fstatUsesTheOpenDescriptorAfterPathReplacementAndRejectsClosedDescriptors() {
        val source = temporary.newFile("source").apply { writeBytes(byteArrayOf(4, 5, 6)) }
        val renamed = temporary.root.toPath().resolve("renamed")
        lateinit var descriptor: FileDescriptor
        FileInputStream(source).use { stream ->
            descriptor = stream.fd
            val original = Os.fstat(descriptor)
            assertTrue(OsConstants.S_ISREG(original.st_mode))
            assertEquals(3L, original.st_size)
            assertEquals(Os.stat(source.path).st_ino, original.st_ino)
            Files.move(source.toPath(), renamed)
            source.writeBytes(ByteArray(19) { 9 })
            val stillOpen = Os.fstat(descriptor)
            assertEquals(original.st_dev, stillOpen.st_dev)
            assertEquals(original.st_ino, stillOpen.st_ino)
            assertEquals(3L, stillOpen.st_size)
            assertNotEquals(Os.stat(source.path).st_ino, stillOpen.st_ino)
            assertEquals(19L, Os.stat(source.path).st_size)
            Files.delete(renamed)
            assertEquals("unlinked open inode is still queryable", original.st_ino, Os.fstat(descriptor).st_ino)
            assertEquals(4, stream.read())
        }
        assertFalse(descriptor.valid())
        assertErrno(OsConstants.EBADF) { Os.fstat(descriptor) }
    }

    @Test
    fun nofollowOpenAndExclusiveCreationPreserveCallerFiles() {
        val canary = temporary.newFile("canary").apply { writeText("unchanged") }
        val original = canary.readBytes()
        val link = temporary.root.toPath().resolve("link")
        Files.createSymbolicLink(link, canary.toPath())
        // No O_CREAT/O_EXCL here: this independently exercises O_NOFOLLOW.
        assertErrno(OsConstants.ELOOP) { Os.open(link.toString(), OsConstants.O_WRONLY or OsConstants.O_NOFOLLOW, 0x180) }
        assertErrno(OsConstants.EEXIST) { Os.open(canary.path, CREATE_FLAGS, 0x180) }
        assertErrno(OsConstants.EEXIST) { Os.open(link.toString(), CREATE_FLAGS, 0x180) }
        assertArrayEquals(original, canary.readBytes())
        assertTrue(Files.isSymbolicLink(link))

        val created = temporary.root.toPath().resolve("created")
        val descriptor = Os.open(created.toString(), CREATE_FLAGS, 0x180)
        FileOutputStream(descriptor).use { stream ->
            stream.write(byteArrayOf(7, 8, 9))
            stream.flush()
            assertEquals(3L, Os.fstat(descriptor).st_size)
            assertEquals(Os.lstat(created.toString()).st_ino, Os.fstat(descriptor).st_ino)
        }
        assertArrayEquals(byteArrayOf(7, 8, 9), Files.readAllBytes(created))
        assertEquals(setOf(PosixFilePermission.OWNER_READ, PosixFilePermission.OWNER_WRITE), Files.getPosixFilePermissions(created))
    }

    @Test
    fun concurrentExclusiveCreatorsHaveExactlyOneWinner() {
        val target = temporary.root.toPath().resolve("one-owner")
        val start = CyclicBarrier(3)
        val pool = Executors.newFixedThreadPool(2)
        try {
            val attempts = (1..2).map { marker ->
                pool.submit<Int> {
                    start.await(5, TimeUnit.SECONDS)
                    try {
                        val descriptor = Os.open(target.toString(), CREATE_FLAGS, 0x180)
                        FileOutputStream(descriptor).use { it.write(marker) }
                        marker
                    } catch (error: ErrnoException) {
                        assertEquals(OsConstants.EEXIST, error.errno)
                        0
                    }
                }
            }
            start.await(5, TimeUnit.SECONDS)
            val results = attempts.map { it.get(5, TimeUnit.SECONDS) }
            assertEquals(1, results.count { it != 0 })
            assertEquals(1, results.count { it == 0 })
            assertArrayEquals(byteArrayOf(results.single { it != 0 }.toByte()), Files.readAllBytes(target))
        } finally {
            pool.shutdownNow()
            assertTrue("only fixture threads may remain, and they must finish", pool.awaitTermination(5, TimeUnit.SECONDS))
        }
    }

    @Test
    fun dupSharesOffsetsAndRetainsIdentityAfterRenameAndOriginalClose() {
        val source = temporary.newFile("dup-source").apply { writeBytes(byteArrayOf(10, 11, 12, 13, 14, 15)) }
        val renamed = temporary.root.toPath().resolve("dup-renamed")
        FileInputStream(source).use { original ->
            val identity = Os.fstat(original.fd)
            val duplicate = Os.dup(original.fd)
            assertNotSame(original.fd, duplicate)
            FileInputStream(duplicate).use { copy ->
                assertEquals(10, original.read())
                assertEquals("dup shares the kernel offset", 11, copy.read())
                assertEquals(2L, original.channel.position())
                Files.move(source.toPath(), renamed)
                source.writeBytes(ByteArray(19) { 99 })
                assertEquals(identity.st_dev, Os.fstat(duplicate).st_dev)
                assertEquals(identity.st_ino, Os.fstat(duplicate).st_ino)
                assertEquals(6L, Os.fstat(duplicate).st_size)
                assertNotEquals(Os.stat(source.path).st_ino, Os.fstat(duplicate).st_ino)
                original.close()
                assertFalse(original.fd.valid())
                assertTrue("closing the original must preserve its duplicate", duplicate.valid())
                assertEquals(12, copy.read())
                Files.delete(renamed)
                assertEquals(identity.st_ino, Os.fstat(duplicate).st_ino)
                assertEquals(13, copy.read())
            }
            assertFalse(duplicate.valid())
            assertErrno(OsConstants.EBADF) { Os.dup(duplicate) }
        }
    }

    @Test
    fun lseekModesMoveTheSharedOffsetAndRejectInvalidPositions() {
        val bytes = byteArrayOf(20, 21, 22, 23, 24, 25)
        val source = temporary.newFile("seek-source").apply { writeBytes(bytes) }
        FileInputStream(source).use { original ->
            val duplicate = Os.dup(original.fd)
            FileInputStream(duplicate).use { copy ->
                assertEquals(2L, Os.lseek(duplicate, 2, OsConstants.SEEK_SET))
                assertEquals(22, original.read())
                assertEquals(3L, Os.lseek(duplicate, 0, OsConstants.SEEK_CUR))
                assertEquals(1L, Os.lseek(original.fd, -2, OsConstants.SEEK_CUR))
                assertEquals(21, copy.read())
                assertEquals(2L, original.channel.position())
                assertEquals(5L, Os.lseek(duplicate, -1, OsConstants.SEEK_END))
                assertEquals(25, original.read())
                assertEquals(6L, Os.lseek(duplicate, 0, OsConstants.SEEK_END))
                assertEquals(-1, copy.read())
                assertEquals(7L, Os.lseek(duplicate, 1, OsConstants.SEEK_CUR))
                assertEquals(-1, original.read())
                assertErrno(OsConstants.EINVAL) { Os.lseek(duplicate, 0, -42) }
                assertErrno(OsConstants.EINVAL) { Os.lseek(duplicate, -1, OsConstants.SEEK_SET) }
                assertErrno(OsConstants.EINVAL) { Os.lseek(duplicate, -100, OsConstants.SEEK_CUR) }
                assertEquals("failed seeks must preserve the shared position", 7L, original.channel.position())
                Os.close(duplicate)
                assertFalse(duplicate.valid())
                assertTrue("closing the duplicate must preserve the original", original.fd.valid())
                assertErrno(OsConstants.EBADF) { Os.lseek(duplicate, 0, OsConstants.SEEK_CUR) }
                assertEquals(0L, Os.lseek(original.fd, 0, OsConstants.SEEK_SET))
                assertEquals(20, original.read())
            }
        }
        assertArrayEquals(bytes, source.readBytes())
    }

    private fun assertErrno(expected: Int, operation: () -> Any?) {
        try {
            operation()
            fail("expected errno $expected")
        } catch (error: ErrnoException) {
            assertEquals(expected, error.errno)
        }
    }

    private companion object {
        val CREATE_FLAGS = OsConstants.O_WRONLY or OsConstants.O_CREAT or OsConstants.O_EXCL or OsConstants.O_NOFOLLOW
    }
}
