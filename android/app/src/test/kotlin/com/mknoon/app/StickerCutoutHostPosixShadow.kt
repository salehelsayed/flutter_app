package com.mknoon.app

import android.system.ErrnoException
import android.system.OsConstants
import android.system.StructStat
import java.io.FileDescriptor
import java.io.FileInputStream
import java.io.IOException
import java.lang.invoke.MethodHandles
import java.lang.invoke.MethodType
import java.lang.reflect.Field
import java.nio.channels.FileChannel
import java.nio.file.AccessDeniedException
import java.nio.file.FileAlreadyExistsException
import java.nio.file.FileSystemLoopException
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.NoSuchFileException
import java.nio.file.NotDirectoryException
import java.nio.file.OpenOption
import java.nio.file.Path
import java.nio.file.Paths
import java.nio.file.StandardOpenOption
import java.nio.file.attribute.FileTime
import java.nio.file.attribute.PosixFilePermission
import java.nio.file.attribute.PosixFilePermissions
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.annotation.Resetter
import org.robolectric.shadows.ShadowLinux

/**
 * Test-only repair for Robolectric 4.13's synthetic lstat/fstat/open behavior.
 * Uses real Unix host attributes, descriptors and atomic FileChannel creation.
 * Only the operations/metadata used by the cutout bridge are implemented here.
 */
@Implements(className = "libcore.io.Linux", minSdk = 26, isInAndroidSdk = false)
class StickerCutoutHostPosixShadow : ShadowLinux() {
    @Implementation
    public override fun stat(path: String): StructStat = readStat(path, follow = true)

    @Implementation
    public override fun lstat(path: String): StructStat = readStat(path, follow = false)

    @Implementation
    public override fun fstat(fd: FileDescriptor): StructStat {
        if (!fd.valid()) throw ErrnoException("fstat", OsConstants.EBADF)
        return HostDescriptors.fstat(fd)
    }

    @Implementation
    protected fun dup(fd: FileDescriptor): FileDescriptor {
        if (!fd.valid()) throw ErrnoException("dup", OsConstants.EBADF)
        return HostDescriptors.dup(fd).also { ownedDuplicates.add(it) }
    }

    @Implementation
    protected fun lseek(fd: FileDescriptor, offset: Long, whence: Int): Long {
        if (!fd.valid()) throw ErrnoException("lseek", OsConstants.EBADF)
        return HostDescriptors.lseek(fd, offset, whence)
    }

    @Implementation
    public override fun open(path: String, flags: Int, mode: Int): FileDescriptor {
        val target = Paths.get(path)
        val options = linkedSetOf<OpenOption>()
        when (flags and OsConstants.O_ACCMODE) {
            OsConstants.O_RDONLY -> options.add(StandardOpenOption.READ)
            OsConstants.O_WRONLY -> options.add(StandardOpenOption.WRITE)
            OsConstants.O_RDWR -> {
                options.add(StandardOpenOption.READ)
                options.add(StandardOpenOption.WRITE)
            }
            else -> throw ErrnoException("open", OsConstants.EINVAL)
        }
        if (flags and OsConstants.O_CREAT != 0) {
            options.add(if (flags and OsConstants.O_EXCL != 0) StandardOpenOption.CREATE_NEW else StandardOpenOption.CREATE)
        }
        if (flags and OsConstants.O_NOFOLLOW != 0) options.add(LinkOption.NOFOLLOW_LINKS)
        if (flags and OsConstants.O_TRUNC != 0) options.add(StandardOpenOption.TRUNCATE_EXISTING)
        if (flags and OsConstants.O_APPEND != 0) options.add(StandardOpenOption.APPEND)
        val permissions = PosixFilePermission.values().filterIndexed { index, _ -> mode and (1 shl (8 - index)) != 0 }.toSet()
        val channel = try {
            // No existence/symlink precheck: the host open syscall decides.
            FileChannel.open(target, options, PosixFilePermissions.asFileAttribute(permissions))
        } catch (error: IOException) {
            throw errno("open", target, error, flags and OsConstants.O_NOFOLLOW != 0)
        }
        try {
            val descriptor = HostDescriptors.descriptor(channel)
            ownedChannels[descriptor] = channel
            return descriptor
        } catch (error: Throwable) {
            channel.close()
            throw error
        }
    }

    @Implementation
    protected fun close(fd: FileDescriptor) = closeHostDescriptor(fd)

    private fun readStat(path: String, follow: Boolean): StructStat {
        val target = Paths.get(path)
        val attributes = try {
            if (follow) Files.readAttributes(target, "unix:*")
            else Files.readAttributes(target, "unix:*", LinkOption.NOFOLLOW_LINKS)
        } catch (error: IOException) {
            throw errno(if (follow) "stat" else "lstat", target, error)
        }
        return StructStat(
            attributes.number("dev").toLong(), attributes.number("ino").toLong(),
            androidMode(attributes.number("mode").toInt()), attributes.number("nlink").toLong(),
            attributes.number("uid").toInt(), attributes.number("gid").toInt(), attributes.number("rdev").toLong(),
            attributes.number("size").toLong(), attributes.seconds("lastAccessTime"),
            attributes.seconds("lastModifiedTime"), attributes.seconds("ctime"), 0, 0,
        )
    }

    private fun Map<String, Any>.number(name: String): Number = getValue(name) as Number
    private fun Map<String, Any>.seconds(name: String): Long = (getValue(name) as FileTime).to(TimeUnit.SECONDS)

    private fun errno(operation: String, path: Path, error: IOException, nofollow: Boolean = false): ErrnoException {
        val code = when (error) {
            is NoSuchFileException -> OsConstants.ENOENT
            is FileAlreadyExistsException -> OsConstants.EEXIST
            is AccessDeniedException -> OsConstants.EACCES
            is NotDirectoryException -> OsConstants.ENOTDIR
            is FileSystemLoopException -> OsConstants.ELOOP
            // The JDK adds NOFOLLOW context to ELOOP and converts it to a
            // FileSystemException. Classify only after the real open failed.
            else -> if (nofollow && Files.isSymbolicLink(path)) OsConstants.ELOOP else OsConstants.EIO
        }
        return ErrnoException(operation, code, error)
    }

    companion object {
        private val ownedChannels = ConcurrentHashMap<FileDescriptor, FileChannel>()
        private val ownedDuplicates = ConcurrentHashMap.newKeySet<FileDescriptor>()

        // BlockGuardOs intercepts Os.close before Linux on Robolectric 4.13.
        // Both fixture entry points must release the same real descriptor owner.
        internal fun closeHostDescriptor(fd: FileDescriptor) {
            ownedDuplicates.remove(fd)
            if (!fd.valid()) throw ErrnoException("close", OsConstants.EBADF)
            val channel = ownedChannels.remove(fd)
            if (channel != null) channel.close() else FileInputStream(fd).close()
        }

        @JvmStatic
        @Resetter
        fun reset() {
            ownedChannels.values.forEach { channel -> runCatching { channel.close() } }
            ownedChannels.clear()
            ownedDuplicates.forEach { fd -> if (fd.valid()) runCatching { FileInputStream(fd).close() } }
            ownedDuplicates.clear()
        }

        /** Robolectric uses synthetic S_IF* constants; permission bits are Unix. */
        private fun androidMode(hostMode: Int): Int {
            val type = when (hostMode and 0xf000) {
                0x1000 -> OsConstants.S_IFIFO
                0x2000 -> OsConstants.S_IFCHR
                0x4000 -> OsConstants.S_IFDIR
                0x6000 -> OsConstants.S_IFBLK
                0x8000 -> OsConstants.S_IFREG
                0xa000 -> OsConstants.S_IFLNK
                0xc000 -> OsConstants.S_IFSOCK
                else -> 0
            }
            return type or (hostMode and 0x0fff)
        }
    }

    /**
     * JDK UnixFileAttributes.get(int) performs native fstat on the actual open
     * descriptor. Never substitutes pathname attributes after rename/unlink.
     * Trusted lookup is confined to these test fixtures; no JVM flags needed.
     */
    private object HostDescriptors {
        private val lookup = trustedLookup()
        private val attributesClass = Class.forName("sun.nio.fs.UnixFileAttributes")
        private val fdGetter = lookup.findGetter(FileDescriptor::class.java, "fd", Int::class.javaPrimitiveType!!)
        private val fstatHandle = lookup.findStatic(attributesClass, "get", MethodType.methodType(attributesClass, Int::class.javaPrimitiveType!!))
        private val unixDispatcher = Class.forName("sun.nio.fs.UnixNativeDispatcher")
        private val fileDispatcher = Class.forName("sun.nio.ch.FileDispatcherImpl")
        private val dupHandle = lookup.findStatic(unixDispatcher, "dup", MethodType.methodType(Int::class.javaPrimitiveType!!, Int::class.javaPrimitiveType!!))
        private val closeRawHandle = lookup.findStatic(unixDispatcher, "close", MethodType.methodType(Void.TYPE, Int::class.javaPrimitiveType!!))
        private val newFdHandle = lookup.findStatic(Class.forName("sun.nio.ch.IOUtil"), "newFD", MethodType.methodType(FileDescriptor::class.java, Int::class.javaPrimitiveType!!))
        private val seekHandle = lookup.findStatic(fileDispatcher, "seek0", MethodType.methodType(Long::class.javaPrimitiveType!!, FileDescriptor::class.java, Long::class.javaPrimitiveType!!))
        private val sizeHandle = lookup.findStatic(fileDispatcher, "size0", MethodType.methodType(Long::class.javaPrimitiveType!!, FileDescriptor::class.java))

        fun descriptor(channel: FileChannel): FileDescriptor =
            lookup.unreflectGetter(channel.javaClass.getDeclaredField("fd")).invokeWithArguments(channel) as FileDescriptor

        fun dup(fd: FileDescriptor): FileDescriptor {
            val raw = try {
                dupHandle.invokeWithArguments(fdGetter.invokeWithArguments(fd)) as Int
            } catch (error: Throwable) {
                if (error.javaClass.name != "sun.nio.fs.UnixException") throw error
                val errno = lookup.findVirtual(error.javaClass, "errno", MethodType.methodType(Int::class.javaPrimitiveType!!))
                    .invokeWithArguments(error) as Int
                val code = when (errno) {
                    9 -> OsConstants.EBADF
                    23 -> OsConstants.ENFILE
                    24 -> OsConstants.EMFILE
                    else -> OsConstants.EIO
                }
                throw ErrnoException("dup", code, error)
            }
            try {
                // A distinct host FD shares the original open-file description;
                // no pathname is resolved or reopened.
                return newFdHandle.invokeWithArguments(raw) as FileDescriptor
            } catch (error: Throwable) {
                closeRawHandle.invokeWithArguments(raw)
                throw error
            }
        }

        @Synchronized
        fun lseek(fd: FileDescriptor, offset: Long, whence: Int): Long {
            try {
                val base = when (whence) {
                    OsConstants.SEEK_SET -> 0L
                    OsConstants.SEEK_CUR -> seekHandle.invokeWithArguments(fd, -1L) as Long
                    OsConstants.SEEK_END -> sizeHandle.invokeWithArguments(fd) as Long
                    else -> throw ErrnoException("lseek", OsConstants.EINVAL)
                }
                val target = try { Math.addExact(base, offset) }
                catch (error: ArithmeticException) { throw ErrnoException("lseek", OsConstants.EOVERFLOW, error) }
                if (target < 0) throw ErrnoException("lseek", OsConstants.EINVAL)
                if (whence == OsConstants.SEEK_CUR && offset == 0L) return base
                // JDK seek0 performs real absolute lseek. CUR/END translation
                // is scoped to this serial regular-file fixture, not atomic
                // relative seeks racing external readers or file growth.
                return seekHandle.invokeWithArguments(fd, target) as Long
            } catch (error: IOException) {
                throw ErrnoException("lseek", if (fd.valid()) OsConstants.EIO else OsConstants.EBADF, error)
            }
        }

        fun fstat(fd: FileDescriptor): StructStat {
            val number = (fdGetter.invokeWithArguments(fd) as Number).toInt()
            if (number < 0) throw ErrnoException("fstat", OsConstants.EBADF)
            val attributes = try {
                requireNotNull(fstatHandle.invokeWithArguments(number))
            } catch (error: Throwable) {
                if (error.javaClass.name != "sun.nio.fs.UnixException") throw error
                val errno = lookup.findVirtual(error.javaClass, "errno", MethodType.methodType(Int::class.javaPrimitiveType!!))
                    .invokeWithArguments(error) as Int
                // EBADF is 9 on both supported Unix host families (Darwin/Linux).
                throw ErrnoException("fstat", if (errno == 9) OsConstants.EBADF else OsConstants.EIO, error)
            }
            return StructStat(
                long(attributes, "dev"), long(attributes, "ino"), androidMode(int(attributes, "mode")),
                int(attributes, "nlink").toLong(), int(attributes, "uid"), int(attributes, "gid"), long(attributes, "rdev"),
                long(attributes, "size"), time(attributes, "lastAccessTime"), time(attributes, "lastModifiedTime"),
                time(attributes, "ctime"), 0, 0,
            )
        }

        private fun int(attributes: Any, name: String): Int =
            lookup.findVirtual(attributesClass, name, MethodType.methodType(Int::class.javaPrimitiveType!!)).invokeWithArguments(attributes) as Int
        private fun long(attributes: Any, name: String): Long =
            lookup.findVirtual(attributesClass, name, MethodType.methodType(Long::class.javaPrimitiveType!!)).invokeWithArguments(attributes) as Long
        private fun time(attributes: Any, name: String): Long =
            (lookup.findVirtual(attributesClass, name, MethodType.methodType(FileTime::class.java)).invokeWithArguments(attributes) as FileTime).to(TimeUnit.SECONDS)

        private fun trustedLookup(): MethodHandles.Lookup {
            val unsafeClass = Class.forName("sun.misc.Unsafe")
            val unsafe = unsafeClass.getDeclaredField("theUnsafe").apply { isAccessible = true }.get(null)
            val field = MethodHandles.Lookup::class.java.getDeclaredField("IMPL_LOOKUP")
            val base = unsafeClass.getMethod("staticFieldBase", Field::class.java).invoke(unsafe, field)
            val offset = unsafeClass.getMethod("staticFieldOffset", Field::class.java).invoke(unsafe, field) as Long
            return unsafeClass.getMethod("getObject", Any::class.java, Long::class.javaPrimitiveType!!)
                .invoke(unsafe, base, offset) as MethodHandles.Lookup
        }
    }
}
