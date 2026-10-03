package com.dropit.phone

import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.util.Log
import java.io.File
import java.io.FileNotFoundException

/**
 * A single browsable item exposed to the Mac.
 */
data class FsEntry(
    val name: String,
    /** Opaque path the Mac passes back, e.g. "saf:<treeId>/relative/path" or "file:/storage/...". */
    val path: String,
    val isDirectory: Boolean,
    val size: Long,
    val modified: Long,
    val isHidden: Boolean,
    val isSymlink: Boolean = false
)

/**
 * Bridges the phone's storage to the Mac.
 *
 * Two access models are supported, mirroring what the user chose:
 *
 *  - SAF (default, all Android versions): the user grants access to specific folders with
 *    the system folder picker. We keep the tree URIs and address files inside them with
 *    document ids. No broad storage permission is required.
 *  - All-files access (opt-in, Android 11+): the user grants MANAGE_EXTERNAL_STORAGE from
 *    Settings and we then serve the real filesystem, which reaches places SAF hides.
 *
 * Paths handed to the Mac are opaque strings; this class is the only thing that turns them
 * back into real storage operations, so the phone can never be tricked into touching a
 * location it was not granted.
 */
class StorageBridge(private val context: Context) {

    private val prefs = context.getSharedPreferences("dropit", Context.MODE_PRIVATE)
    private val resolver: ContentResolver = context.contentResolver

    /** treeUri -> human readable label, as chosen in the system folder picker. */
    private val sharedTrees: MutableMap<String, String> = linkedMapOf()

    init {
        loadSavedTrees()
    }

    // ---------------------------------------------------------------- permissions

    fun hasAllFilesAccess(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return true
        return Environment.isExternalStorageManager()
    }

    fun allFilesAccessIntent(): Intent? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        return Intent(android.provider.Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
            data = Uri.parse("package:${context.packageName}")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
    }

    // ---------------------------------------------------------------- SAF trees

    private fun loadSavedTrees() {
        val set = prefs.getStringSet(KEY_TREES, emptySet()) ?: emptySet()
        for (uriText in set) {
            val uri = runCatching { Uri.parse(uriText) }.getOrNull() ?: continue
            if (!canReadTree(uri)) continue
            sharedTrees[uriText] = displayNameFor(uri)
        }
    }

    private fun saveTrees() {
        prefs.edit().putStringSet(KEY_TREES, sharedTrees.keys.toSet()).apply()
    }

    private fun canReadTree(treeUri: Uri): Boolean = runCatching {
        resolver.takePersistableUriPermission(
            treeUri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        )
        true
    }.getOrElse { false }

    /** Called from onActivityResult after the user picks a folder. */
    fun addSharedTree(treeUri: Uri, label: String?): Boolean {
        val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
            Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
        val granted = runCatching {
            resolver.takePersistableUriPermission(treeUri, flags)
            true
        }.getOrElse { false }
        if (!granted) return false
        sharedTrees[treeUri.toString()] = label ?: displayNameFor(treeUri)
        saveTrees()
        return true
    }

    fun removeSharedTree(treeUriText: String) {
        sharedTrees.remove(treeUriText)
        runCatching {
            resolver.releasePersistableUriPermission(
                Uri.parse(treeUriText),
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        }
        saveTrees()
    }

    fun treeLabels(): List<Pair<String, String>> = sharedTrees.toList()

    // ---------------------------------------------------------------- path encoding

    /**
     * Paths look like:
     *   saf:<treeId-relative-path>   inside a folder the user shared
     *   file:/storage/emulated/0/...  real filesystem paths (all-files access only)
     */
    private fun encodeSafPath(treeUriText: String, docId: String): String = "saf:$docId@$treeUriText"

    private fun encodeFilePath(file: File): String = "file:" + file.absolutePath

    fun roots(): List<FsEntry> = buildList {
        for ((uriText, label) in sharedTrees) {
            val name = label.ifBlank { Uri.parse(uriText).lastPathSegment ?: uriText }
            add(FsEntry(name = name, path = "safroot:$uriText", isDirectory = true, size = 0, modified = 0, isHidden = false))
        }
        if (hasAllFilesAccess()) {
            val external = Environment.getExternalStorageDirectory()
            if (external != null && external.isDirectory) {
                val f = File(external.absolutePath)
                add(
                    FsEntry(
                        name = f.name.ifBlank { "Internal storage" },
                        path = "fsroot:/",
                        isDirectory = true,
                        size = 0,
                        modified = f.lastModified(),
                        isHidden = false
                    )
                )
            }
        }
    }

    // ---------------------------------------------------------------- navigation

    fun list(path: String): List<FsEntry> {
        return when {
            path.isEmpty() -> roots()
            path.startsWith("safroot:") -> listSafRoot(path.removePrefix("safroot:"))
            path.startsWith("saf:") -> listSaf(path)
            path.startsWith("fsroot:") -> listFsRoot()
            path.startsWith("file:") -> listFile(File(path.removePrefix("file:")))
            else -> throw FsException("Unsupported path", 400)
        }
    }

    private fun listSafRoot(treeUriText: String): List<FsEntry> {
        val rootDoc = runCatching {
            DocumentsContract.buildDocumentUriUsingTree(treeUriText.uri(), DocumentsContract.getTreeDocumentId(treeUriText.uri()))
        }.getOrElse { throw FsException("Shared folder is no longer available", 404) }
        // The top of a shared folder has nowhere to go up to.
        return querySafDirectory(treeUriText, rootDoc, includeParent = false)
    }

    private fun listSaf(path: String): List<FsEntry> {
        val body = path.removePrefix("saf:")
        val at = body.lastIndexOf('@')
        if (at <= 0) throw FsException("Malformed path", 400)
        val docId = body.substring(0, at)
        val treeUriText = body.substring(at + 1)
        val docUri = runCatching { DocumentsContract.buildDocumentUriUsingTree(treeUriText.uri(), docId) }
            .getOrElse { throw FsException("File not found", 404) }
        return querySafDirectory(treeUriText, docUri, includeParent = true)
    }

    private fun querySafDirectory(treeUriText: String, docUri: Uri, includeParent: Boolean): List<FsEntry> {
        val children = runCatching { DocumentsContract.buildChildDocumentsUriUsingTree(treeUriText.uri(), DocumentsContract.getDocumentId(docUri)) }
            .getOrElse { throw FsException("Cannot read this folder", 403) }
        val out = mutableListOf<FsEntry>()
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED
        )
        resolver.query(children, projection, null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val childId = cursor.getString(0) ?: continue
                val name = cursor.getString(1) ?: continue
                val mime = cursor.getString(2) ?: "application/octet-stream"
                val size = if (cursor.isNull(3)) 0L else cursor.getLong(3)
                val modified = if (cursor.isNull(4)) 0L else cursor.getLong(4)
                val isDir = mime == DocumentsContract.Document.MIME_TYPE_DIR
                out.add(
                    FsEntry(
                        name = name,
                        path = encodeSafPath(treeUriText, childId),
                        isDirectory = isDir,
                        size = if (isDir) 0 else size,
                        modified = modified,
                        isHidden = name.startsWith(".")
                    )
                )
            }
        }
        val parent = if (includeParent) pathForSafParent(treeUriText, docUri) else ""
        return sortEntries(out, includeParent = includeParent, parentPath = parent)
    }

    private fun pathForSafParent(treeUriText: String, docUri: Uri): String {
        val docId = runCatching { DocumentsContract.getDocumentId(docUri) }.getOrNull() ?: return ""
        val parent = docId.substringBeforeLast('/', missingDelimiterValue = "")
        return if (parent.isEmpty()) "safroot:$treeUriText" else encodeSafPath(treeUriText, parent)
    }

    private fun listFsRoot(): List<FsEntry> {
        requireAllFilesAccess()
        val dataDir = File("/data")
        val out = mutableListOf<FsEntry>()
        // /data is not readable without root, so only offer the parts that are.
        for (child in dataDir.listFiles() ?: emptyArray()) {
            out.add(fileEntry(child))
        }
        val storage = File("/storage")
        for (child in storage.listFiles() ?: emptyArray()) {
            out.add(fileEntry(child))
        }
        return sortEntries(out, includeParent = true, parentPath = "")
    }

    private fun listFile(dir: File): List<FsEntry> {
        val resolved = requireReadable(dir)
        if (!resolved.isDirectory) throw FsException("Not a folder", 400)
        val out = resolved.listFiles()?.map { fileEntry(it) } ?: emptyList()
        return sortEntries(out, includeParent = true, parentPath = encodeFilePath(resolved.parentFile ?: resolved))
    }

    private fun fileEntry(file: File) = FsEntry(
        name = file.name,
        path = encodeFilePath(file),
        isDirectory = file.isDirectory,
        size = if (file.isDirectory) 0 else file.length(),
        modified = file.lastModified(),
        isHidden = file.name.startsWith(".")
    )

    private fun sortEntries(entries: List<FsEntry>, includeParent: Boolean, parentPath: String): List<FsEntry> {
        val out = mutableListOf<FsEntry>()
        if (includeParent && parentPath.isNotEmpty()) {
            out.add(FsEntry("..", parentPath, isDirectory = true, size = 0, modified = 0, isHidden = false))
        }
        out.addAll(
            entries.sortedWith(
                compareByDescending<FsEntry> { it.isDirectory }
                    .thenByDescending { it.isHidden }
                    .thenBy { it.name.lowercase() }
            )
        )
        return out
    }

    // ---------------------------------------------------------------- file access

    fun openRead(path: String): FsInput {
        return when {
            path.startsWith("saf:") -> {
                val (uri, name) = safDocument(path)
                FsInput(FsEntry(name = name, path = path, isDirectory = false, size = -1, modified = 0, isHidden = false), uri)
            }
            path.startsWith("file:") -> {
                val file = requireReadable(File(path.removePrefix("file:")))
                if (!file.isFile) throw FsException("Not a file", 400)
                FsInput(
                    FsEntry(file.name, path, isDirectory = false, size = file.length(), modified = file.lastModified(), isHidden = false),
                    Uri.fromFile(file)
                )
            }
            else -> throw FsException("Unsupported path", 400)
        }
    }

    /** A file ready to be streamed, plus the size the Mac should be told about. */
    class FsInput(val entry: FsEntry, val uri: Uri) {
        val name: String get() = entry.name
        val size: Long get() = entry.size
    }

    class FsException(message: String, val status: Int) : Exception(message)

    fun readStream(path: String): Pair<FsInput, java.io.InputStream> {
        val input = openRead(path)
        val stream = runCatching { resolver.openInputStream(input.uri) }.getOrNull()
            ?: throw FsException("Cannot read file", 404)
        return input to stream
    }

    fun writeStream(path: String, name: String?): java.io.OutputStream {
        return when {
            // Write into a SAF folder: path is a directory, name is the new file.
            path.startsWith("saf:") && name != null -> {
                val parentDoc = safDocId(path)
                val (treeText, parentId) = splitSaf(path)
                val parentUri = DocumentsContract.buildDocumentUriUsingTree(treeText, parentId)
                val newUri = DocumentsContract.createDocument(resolver, parentUri, "application/octet-stream", name)
                    ?: throw FsException("Cannot create file", 403)
                resolver.openOutputStream(newUri, "wt")
                    ?: throw FsException("Cannot create file", 403)
            }
            path.startsWith("saf:") -> {
                // Overwrite an existing SAF document.
                val existing = openRead(path)
                resolver.openOutputStream(existing.uri, "wt") ?: throw FsException("Cannot write file", 403)
            }
            path.startsWith("file:") && name != null -> {
                requireAllFilesAccess()
                val dir = requireWritable(File(path.removePrefix("file:")))
                File(dir, name).outputStream()
            }
            path.startsWith("file:") -> {
                requireAllFilesAccess()
                requireWritable(File(path.removePrefix("file:"))).outputStream()
            }
            else -> throw FsException("Unsupported path", 400)
        }
    }

    fun createDirectory(path: String, name: String): String {
        if (name.isBlank() || name.contains('/') || name.contains('\\') || name == "." || name == "..") {
            throw FsException("Invalid folder name", 400)
        }
        return when {
            path.startsWith("saf:") || path.isEmpty() && sharedTrees.isNotEmpty() && path.startsWith("safroot:") -> {
                val (treeText, parentId) = if (path.startsWith("safroot:")) {
                    val t = parseTree(path.removePrefix("safroot:"))
                    t to DocumentsContract.getTreeDocumentId(t)
                } else {
                    splitSaf(path)
                }
                val parentUri = DocumentsContract.buildDocumentUriUsingTree(treeText, parentId)
                val newUri = DocumentsContract.createDocument(resolver, parentUri, DocumentsContract.Document.MIME_TYPE_DIR, name)
                    ?: throw FsException("Cannot create folder", 403)
                newUri.toString()
            }
            path.startsWith("file:") || path.startsWith("fsroot:") -> {
                requireAllFilesAccess()
                val base = if (path.startsWith("fsroot:")) File("/storage") else File(path.removePrefix("file:"))
                val dir = File(base, name)
                if (dir.exists()) throw FsException("Already exists", 409)
                if (!dir.mkdirs()) throw FsException("Cannot create folder", 403)
                encodeFilePath(dir)
            }
            else -> throw FsException("Unsupported path", 400)
        }
    }

    fun rename(path: String, newName: String): String {
        if (newName.isBlank() || newName.contains('/') || newName.contains('\\')) {
            throw FsException("Invalid name", 400)
        }
        return when {
            path.startsWith("saf:") -> {
                val (treeText, docId) = splitSaf(path)
                val parentId = docId.substringBeforeLast('/', missingDelimiterValue = "")
                val parentUri = DocumentsContract.buildDocumentUriUsingTree(treeText, parentId)
                val newUri = DocumentsContract.renameDocument(resolver, DocumentsContract.buildDocumentUriUsingTree(treeText, docId), newName)
                    ?: throw FsException("Cannot rename", 403)
                encodeSafPath(treeText.toString(), DocumentsContract.getDocumentId(newUri))
            }
            path.startsWith("file:") -> {
                requireAllFilesAccess()
                val file = requireWritable(File(path.removePrefix("file:")))
                val target = File(file.parentFile, newName)
                if (target.exists()) throw FsException("Already exists", 409)
                if (!file.renameTo(target)) throw FsException("Cannot rename", 403)
                encodeFilePath(target)
            }
            else -> throw FsException("Unsupported path", 400)
        }
    }

    fun delete(path: String) {
        when {
            path.startsWith("saf:") -> {
                val (treeText, docId) = splitSaf(path)
                val uri = DocumentsContract.buildDocumentUriUsingTree(treeText, docId)
                if (!DocumentsContract.deleteDocument(resolver, uri)) throw FsException("Cannot delete", 403)
            }
            path.startsWith("file:") -> {
                requireAllFilesAccess()
                val file = requireWritable(File(path.removePrefix("file:")))
                if (!file.delete()) throw FsException("Cannot delete", 403)
            }
            else -> throw FsException("Unsupported path", 400)
        }
    }

    fun isDirectory(path: String): Boolean = when {
        path.startsWith("safroot:") -> true
        path.startsWith("saf:") -> {
            val (treeText, docId) = splitSaf(path)
            val uri = DocumentsContract.buildDocumentUriUsingTree(treeText, docId)
            resolver.query(uri, arrayOf(DocumentsContract.Document.COLUMN_MIME_TYPE), null, null, null)?.use {
                if (it.moveToFirst()) it.getString(0) == DocumentsContract.Document.MIME_TYPE_DIR else false
            } ?: false
        }
        path.startsWith("fsroot:") -> true
        path.startsWith("file:") -> File(path.removePrefix("file:")).isDirectory
        else -> false
    }

    // ---------------------------------------------------------------- guards

    private fun requireAllFilesAccess() {
        if (!hasAllFilesAccess()) throw FsException("All-files access is not enabled on this device", 403)
    }

    /** Rejects anything that is not inside storage the user actually granted. */
    private fun requireReadable(file: File): File {
        requireAllFilesAccess()
        val canonical = runCatching { file.canonicalFile }.getOrElse { file.absoluteFile }
        val canonicalPath = canonical.path
        if (canonicalPath.contains("/../") || canonical.path != canonicalPath) {
            throw FsException("Invalid path", 400)
        }
        if (!canonical.exists()) throw FsException("No such file or folder", 404)
        return canonical
    }

    private fun requireWritable(file: File): File {
        val canonical = requireReadable(file)
        if (!canonical.canWrite()) throw FsException("Folder is not writable", 403)
        return canonical
    }

    private fun splitSaf(path: String): Pair<Uri, String> {
        val body = path.removePrefix("saf:")
        val at = body.lastIndexOf('@')
        if (at <= 0) throw FsException("Malformed path", 400)
        return Uri.parse(body.substring(at + 1)) to body.substring(0, at)
    }

    private fun parseTree(uriText: String): Uri = Uri.parse(uriText)

    private fun safDocId(path: String): String = splitSaf(path).second

    private fun safDocument(path: String): Pair<Uri, String> {
        val (treeUri, docId) = splitSaf(path)
        val uri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
        val name = resolver.query(uri, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) ?: "file" else "file"
        } ?: "file"
        return uri to name
    }

    private fun String.uri(): Uri = Uri.parse(this)

    private fun displayNameFor(treeUri: Uri): String = runCatching {
        val docId = DocumentsContract.getTreeDocumentId(treeUri)
        val uri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
        resolver.query(uri, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) ?: "Folder" else "Folder"
        } ?: "Folder"
    }.getOrElse { treeUri.lastPathSegment ?: "Folder" }

    companion object {
        private const val KEY_TREES = "shared_trees"
    }
}
