package com.mknoon.app

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File
import java.io.FileNotFoundException

/** Read-only, capability-style provider for the three received-media roots. */
class ReceivedMediaEgressProvider : ContentProvider() {
    companion object {
        private val rootNames = setOf("media", "local_media", "post_media")

        internal fun documentsDirectory(context: Context): File =
            context.getDir("flutter", Context.MODE_PRIVATE).absoluteFile

        private fun literalRoot(context: Context, name: String): File {
            require(name in rootNames) { "unknown received-media root" }
            val documents = documentsDirectory(context)
            val literal = File(documents, name).absoluteFile.normalize()
            val canonical = literal.canonicalFile
            val canonicalLiteral = File(documents.canonicalFile, name).absoluteFile.normalize()
            // The root name is part of the capability. A symlinked root must
            // not gain authority merely because its target is also named
            // media/local_media/post_media or currently sits below Documents.
            require(canonical.path == canonicalLiteral.path && canonical.isDirectory) {
                "received-media root is not literal"
            }
            return canonical
        }

        internal fun uriForFile(context: Context, file: File): Uri {
            val candidate = file.canonicalFile
            val root = rootNames.asSequence()
                .mapNotNull { name -> runCatching { literalRoot(context, name) }.getOrNull() }
                .firstOrNull { candidate.isWithin(it) }
                ?: throw IllegalArgumentException("outside received-media roots")
            val relative = candidate.relativeTo(root).invariantSeparatorsPath
            require(relative.isNotEmpty() && candidate.isFile) { "media source is not a file" }
            return Uri.Builder()
                .scheme("content")
                .authority("${context.packageName}.received-media")
                .appendPath(root.name)
                .apply { relative.split('/').forEach(::appendPath) }
                .build()
        }

        private fun File.isWithin(root: File): Boolean =
            path == root.path || path.startsWith(root.path + File.separator)
    }

    override fun onCreate(): Boolean = true

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw FileNotFoundException("read-only provider")
        return ParcelFileDescriptor.open(resolve(uri), ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun getType(uri: Uri): String? = when (resolve(uri).extension.lowercase()) {
        "jpg", "jpeg" -> "image/jpeg"
        "png" -> "image/png"
        "gif" -> "image/gif"
        "webp" -> "image/webp"
        "heic" -> "image/heic"
        "mp4" -> "video/mp4"
        "mov" -> "video/quicktime"
        "webm" -> "video/webm"
        else -> null
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        val file = resolve(uri)
        val columns = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val cursor = MatrixCursor(columns)
        cursor.addRow(columns.map { column ->
            when (column) {
                OpenableColumns.DISPLAY_NAME -> file.name
                OpenableColumns.SIZE -> file.length()
                else -> null
            }
        })
        return cursor
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? =
        throw UnsupportedOperationException("read-only provider")

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int =
        throw UnsupportedOperationException("read-only provider")

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = throw UnsupportedOperationException("read-only provider")

    private fun resolve(uri: Uri): File {
        val context = context ?: throw FileNotFoundException("provider unavailable")
        if (uri.scheme != "content" || uri.authority != "${context.packageName}.received-media") {
            throw FileNotFoundException("wrong provider authority")
        }
        val segments = uri.pathSegments
        if (segments.size < 2 || segments.first() !in rootNames || segments.drop(1).any { it == "." || it == ".." }) {
            throw FileNotFoundException("invalid media URI")
        }
        val root = try {
            literalRoot(context, segments.first())
        } catch (_: Exception) {
            throw FileNotFoundException("received-media root unavailable")
        }
        val candidate = segments.drop(1).fold(root, ::File).canonicalFile
        if (!candidate.isWithin(root) || !candidate.isFile) throw FileNotFoundException("media unavailable")
        return candidate
    }
}
