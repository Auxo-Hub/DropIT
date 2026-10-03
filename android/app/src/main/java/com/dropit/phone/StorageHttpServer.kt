package com.dropit.phone

import android.util.Log
import java.io.BufferedOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * A tiny HTTP server that exposes this phone's storage to the Mac.
 *
 * It is written directly on sockets rather than pulling in a web-server library so the
 * APK carries no third-party dependencies. The API mirrors the one the Mac already
 * serves for its own folders, so the Mac can drive both with the same code.
 *
 * Routes (all require the session token, or a request from the paired Mac):
 *   GET  /status
 *   GET  /fs/roots
 *   GET  /fs/list?path=
 *   GET  /fs/read?path=[&download=1]      (supports Range)
 *   POST /fs/write?path=&name=
 *   POST /fs/mkdir    {"path":"...","name":"..."}
 *   POST /fs/rename   {"path":"...","name":"..."}
 *   POST /fs/delete   {"path":"..."}
 */
class StorageHttpServer(
    private val storage: StorageBridge,
    private val auth: AuthGate,
    private val onStateChange: (Int) -> Unit
) {
    private val running = AtomicBoolean(false)
    private var serverSocket: ServerSocket? = null
    private var boundPort: Int = 0
    private val workers = Executors.newFixedThreadPool(6)

    val port: Int get() = boundPort

    fun start(): Int {
        if (running.getAndSet(true)) return boundPort
        val socket = ServerSocket()
        socket.reuseAddress = true
        socket.bind(InetSocketAddress(0)) // OS-assigned port
        boundPort = socket.localPort
        serverSocket = socket
        onStateChange(boundPort)

        Thread({
            while (running.get()) {
                try {
                    val client = socket.accept()
                    workers.execute { handle(client) }
                } catch (e: IOException) {
                    if (running.get()) Log.w(TAG, "accept failed", e)
                }
            }
        }, "dropit-http-accept").apply { isDaemon = true }.start()
        return boundPort
    }

    fun stop() {
        running.set(false)
        runCatching { serverSocket?.close() }
        workers.shutdownNow()
        boundPort = 0
    }

    // ------------------------------------------------------------------ routing

    private fun handle(client: Socket) {
        client.use { socket ->
            socket.tcpNoDelay = true
            socket.soTimeout = 30_000
            val input = socket.getInputStream()
            val output = BufferedOutputStream(socket.getOutputStream())

            val request = readRequest(input) ?: return
            if (request.method == "OPTIONS") {
                writeEmpty(output, 204)
                return
            }
            if (!auth.isAllowed(request.token, request.header("x-dropit-mac"))) {
                writeJson(output, 403, """{"error":"This phone only accepts requests from the paired Mac"}""")
                return
            }

            try {
                route(request, input, output)
            } catch (e: StorageBridge.FsException) {
                writeJson(output, e.status, """{"error":${jsonString(e.message ?: "Error")}}""")
            } catch (e: Exception) {
                Log.w(TAG, "request failed: ${request.path}", e)
                writeJson(output, 500, """{"error":${jsonString(e.message ?: "Internal error")}}""")
            }
        }
    }

    private fun route(request: Request, input: InputStream, output: OutputStream) {
        when {
            request.path == "/status" -> writeJson(
                output, 200,
                """{"app":"DropitPhone","port":$boundPort,"allFilesAccess":${storage.hasAllFilesAccess()},"sharedFolders":${storage.treeLabels().size}}"""
            )

            request.path == "/fs/roots" -> {
                val roots = storage.roots()
                writeJson(output, 200, """{"roots":${entriesJson(roots)}}""")
            }

            request.path == "/fs/list" -> {
                val path = request.query("path") ?: ""
                val entries = storage.list(path)
                writeJson(output, 200, """{"path":${jsonString(path)},"entries":${entriesJson(entries)}}""")
            }

            request.path == "/fs/read" -> {
                val path = request.query("path") ?: throw StorageBridge.FsException("path is required", 400)
                serveFile(path, request.query("download") == "1", request.header("range"), output)
            }

            request.path == "/fs/write" && request.method == "POST" -> {
                val path = request.query("path") ?: throw StorageBridge.FsException("path is required", 400)
                val name = request.query("name")
                val stream = storage.writeStream(path, name)
                var written = 0L
                stream.use { out ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val n = input.read(buffer)
                        if (n <= 0) break
                        out.write(buffer, 0, n)
                        written += n
                    }
                }
                writeJson(output, 200, """{"status":"ok","size":$written}""")
            }

            request.path == "/fs/mkdir" && request.method == "POST" -> {
                val body = readBodyAsText(request, input)
                val created = storage.createDirectory(body.optString("path", ""), body.optString("name", ""))
                writeJson(output, 200, """{"status":"ok","path":${jsonString(created)}}""")
            }

            request.path == "/fs/rename" && request.method == "POST" -> {
                val body = readBodyAsText(request, input)
                val renamed = storage.rename(body.optString("path", ""), body.optString("name", ""))
                writeJson(output, 200, """{"status":"ok","path":${jsonString(renamed)}}""")
            }

            request.path == "/fs/delete" && request.method == "POST" -> {
                val body = readBodyAsText(request, input)
                storage.delete(body.optString("path", ""))
                writeJson(output, 200, """{"status":"ok"}""")
            }

            else -> writeJson(output, 404, """{"error":"Not found"}""")
        }
    }

    private fun serveFile(path: String, asAttachment: Boolean, rangeHeader: String?, output: OutputStream) {
        val (input, stream) = storage.readStream(path)
        val total = if (input.size >= 0) input.size else -1L

        stream.use { source ->
            var start = 0L
            var endExclusive = total
            if (total > 0) {
                parseRange(rangeHeader, total)?.let { (s, e) ->
                    start = s
                    endExclusive = e + 1
                }
            }
            if (total > 0 && endExclusive > total) endExclusive = total
            if (start > 0) source.skip(start)

            val length = if (total > 0) (endExclusive - start).coerceAtLeast(0) else -1
            val partial = rangeHeader != null && start > 0
            val status = if (partial) "206 Partial Content" else "200 OK"

            val builder = StringBuilder()
            builder.append("HTTP/1.1 ").append(status).append("\r\n")
            builder.append("Content-Type: ").append(mimeFor(input.name)).append("\r\n")
            if (length >= 0) builder.append("Content-Length: ").append(length).append("\r\n")
            if (partial) builder.append("Content-Range: bytes ").append(start).append('-').append(endExclusive - 1).append('/').append(total).append("\r\n")
            builder.append("Accept-Ranges: bytes\r\n")
            builder.append("Access-Control-Allow-Origin: *\r\n")
            if (asAttachment) {
                builder.append("Content-Disposition: attachment; filename=\"").append(input.name.replace('"', '_')).append("\"\r\n")
            }
            builder.append("Connection: close\r\n\r\n")
            output.write(builder.toString().toByteArray(Charsets.UTF_8))

            val buffer = ByteArray(64 * 1024)
            var sent = 0L
            while (length < 0 || sent < length) {
                val want = if (length < 0) buffer.size.toLong() else minOf(buffer.size.toLong(), length - sent)
                val n = source.read(buffer, 0, want.toInt())
                if (n <= 0) break
                output.write(buffer, 0, n)
                sent += n
            }
            output.flush()
        }
    }

    // ------------------------------------------------------------------ parsing

    private class Request(val method: String, val path: String, val headers: Map<String, String>) {
        val queryParams: Map<String, String> = parseQuery(path)
        fun query(name: String): String? = queryParams[name]?.let { urlDecode(it) }
        fun header(name: String): String? = headers[name.lowercase()]
        val token: String? get() = query("token")
    }

    private fun readRequest(input: InputStream): Request? {
        val head = StringBuilder()
        while (true) {
            val line = readLine(input) ?: return null
            if (line.isEmpty()) break
            head.append(line).append("\n")
            if (head.length > 64 * 1024) return null
        }
        val lines = head.toString().trim().lines().filter { it.isNotBlank() }
        if (lines.isEmpty()) return null
        val parts = lines[0].split(" ")
        if (parts.size < 2) return null
        val headers = mutableMapOf<String, String>()
        for (line in lines.drop(1)) {
            val idx = line.indexOf(':')
            if (idx > 0) headers[line.substring(0, idx).trim().lowercase()] = line.substring(idx + 1).trim()
        }
        return Request(parts[0].uppercase(), parts[1], headers)
    }

    private fun readLine(input: InputStream): String? {
        val builder = StringBuilder()
        while (true) {
            val ch = input.read()
            if (ch == -1) return if (builder.isEmpty()) null else builder.toString()
            if (ch == '\n'.code) return builder.toString().removeSuffix("\r")
            builder.append(ch.toChar())
            if (builder.length > 16 * 1024) return null
        }
    }

    private fun readBodyAsText(request: Request, input: InputStream): JsonObject {
        val length = request.header("content-length")?.toIntOrNull() ?: return JsonObject(emptyMap())
        val buffer = ByteArray(length.coerceIn(0, 1_048_576))
        var read = 0
        while (read < buffer.size) {
            val n = input.read(buffer, read, buffer.size - read)
            if (n <= 0) break
            read += n
        }
        return JsonObject.parse(String(buffer, 0, read, Charsets.UTF_8))
    }

    private fun parseRange(header: String?, total: Long): Pair<Long, Long>? {
        if (header == null || total <= 0) return null
        val spec = header.trim().lowercase()
        if (!spec.startsWith("bytes=")) return null
        val value = spec.removePrefix("bytes=")
        if (value.contains(',')) return null
        val dash = value.indexOf('-')
        if (dash < 0) return null
        val first = value.substring(0, dash).toLongOrNull() ?: return null
        if (first < 0) {
            val suffix = value.substring(dash + 1).toLongOrNull() ?: return null
            if (suffix <= 0) return null
            val start = maxOf(0, total - suffix)
            return start to total - 1
        }
        if (first >= total) return null
        val last = value.substring(dash + 1).toLongOrNull() ?: (total - 1)
        val end = minOf(last, total - 1)
        if (end < first) return null
        return first to end
    }

    // ------------------------------------------------------------------ responses

    private fun writeJson(out: OutputStream, status: Int, body: String) {
        val bytes = body.toByteArray(Charsets.UTF_8)
        val header = "HTTP/1.1 ${statusText(status)}\r\n" +
            "Content-Type: application/json\r\n" +
            "Content-Length: ${bytes.size}\r\n" +
            "Access-Control-Allow-Origin: *\r\n" +
            "Access-Control-Allow-Headers: *\r\n" +
            "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n" +
            "Connection: close\r\n\r\n"
        out.write(header.toByteArray(Charsets.UTF_8))
        out.write(bytes)
        out.flush()
    }

    private fun writeEmpty(out: OutputStream, status: Int) {
        out.write("HTTP/1.1 ${statusText(status)}\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".toByteArray(Charsets.UTF_8))
        out.flush()
    }

    private fun statusText(status: Int) = when (status) {
        200 -> "200 OK"
        204 -> "204 No Content"
        400 -> "400 Bad Request"
        403 -> "403 Forbidden"
        404 -> "404 Not Found"
        409 -> "409 Conflict"
        else -> "500 Internal Server Error"
    }

    private fun entriesJson(entries: List<FsEntry>): String = entries.joinToString(",", "[", "]") { entry ->
        """{"name":${jsonString(entry.name)},"path":${jsonString(entry.path)},""" +
            """"isDirectory":${entry.isDirectory},"size":${entry.size},""" +
            """"formattedSize":${jsonString(formatBytes(entry.size))},""" +
            """"modified":${entry.modified},"isHidden":${entry.isHidden},"isSymlink":${entry.isSymlink}}}"""
    }

    companion object {
        private const val TAG = "DropitPhone"
        private const val MAX_UPLOAD = 4L * 1024 * 1024 * 1024

        fun formatBytes(bytes: Long): String {
            if (bytes <= 0) return "0 B"
            val units = arrayOf("B", "KB", "MB", "GB", "TB")
            var value = bytes.toDouble()
            var unit = 0
            while (value >= 1024 && unit < units.size - 1) {
                value /= 1024
                unit++
            }
            return String.format("%.1f %s", value, units[unit])
        }

        private fun mimeFor(name: String): String {
            val ext = name.substringAfterLast('.', "").lowercase()
            return when (ext) {
                "txt", "log", "md" -> "text/plain; charset=utf-8"
                "html", "htm" -> "text/html; charset=utf-8"
                "css" -> "text/css; charset=utf-8"
                "js", "json" -> "application/json"
                "xml" -> "application/xml"
                "csv" -> "text/csv; charset=utf-8"
                "jpg", "jpeg" -> "image/jpeg"
                "png" -> "image/png"
                "gif" -> "image/gif"
                "webp" -> "image/webp"
                "heic" -> "image/heic"
                "svg" -> "image/svg+xml"
                "mp4" -> "video/mp4"
                "mov" -> "video/quicktime"
                "mp3" -> "audio/mpeg"
                "wav" -> "audio/wav"
                "m4a" -> "audio/mp4"
                "pdf" -> "application/pdf"
                "zip" -> "application/zip"
                else -> "application/octet-stream"
            }
        }

        private fun parseQuery(path: String): Map<String, String> {
            val idx = path.indexOf('?')
            if (idx < 0) return emptyMap()
            return path.substring(idx + 1).split("&").mapNotNull { pair ->
                if (pair.isEmpty()) return@mapNotNull null
                val eq = pair.indexOf('=')
                if (eq < 0) pair to "" else pair.substring(0, eq) to pair.substring(eq + 1)
            }.toMap()
        }

        private fun urlDecode(value: String): String = runCatching {
            java.net.URLDecoder.decode(value, "UTF-8")
        }.getOrElse { value }

        private fun jsonString(value: String): String {
            val out = StringBuilder("\"")
            for (ch in value) {
                when (ch) {
                    '"' -> out.append("\\\"")
                    '\\' -> out.append("\\\\")
                    '\n' -> out.append("\\n")
                    '\r' -> out.append("\\r")
                    '\t' -> out.append("\\t")
                    else -> if (ch < ' ') out.append("\\u%04x".format(ch.code)) else out.append(ch)
                }
            }
            out.append("\"")
            return out.toString()
        }
    }
}

/** Minimal JSON object reader for the small bodies this protocol uses. */
class JsonObject(private val values: Map<String, String>) {
    fun optString(key: String, fallback: String = ""): String = values[key] ?: fallback

    companion object {
        /**
         * JSON producers differ on escaping: Foundation escapes "/" as "\/", so a path
         * such as "DCIM/Camera" can arrive as "DCIM\/Camera". Unescape defensively.
         */
        private fun unescape(raw: String): String {
            val out = StringBuilder(raw.length)
            var i = 0
            while (i < raw.length) {
                val ch = raw[i]
                if (ch != '\\' || i == raw.length - 1) { out.append(ch); i++; continue }
                when (val next = raw[i + 1]) {
                    '"' -> { out.append('"'); i += 2 }
                    '\\' -> { out.append('\\'); i += 2 }
                    '/' -> { out.append('/'); i += 2 }
                    'n' -> { out.append('\n'); i += 2 }
                    'r' -> { out.append('\r'); i += 2 }
                    't' -> { out.append('\t'); i += 2 }
                    'u' -> {
                        if (i + 5 < raw.length) {
                            val hex = raw.substring(i + 2, i + 6)
                            val code = hex.toIntOrNull(16)
                            if (code != null) { out.append(code.toChar()); i += 6 } else { out.append(ch); i++ }
                        } else { out.append(ch); i++ }
                    }
                    else -> { out.append(ch).append(next); i += 2 }
                }
            }
            return out.toString()
        }

        fun parse(text: String): JsonObject {
            val map = mutableMapOf<String, String>()
            val regex = Regex("\"([^\"]+)\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"")
            for (match in regex.findAll(text)) {
                val key = match.groupValues[1]
                val value = unescape(match.groupValues[2])
                map[key] = value
            }
            return JsonObject(map)
        }
    }
}
