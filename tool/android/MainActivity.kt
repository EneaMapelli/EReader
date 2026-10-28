package com.example.ereader.ereader

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream
import java.util.UUID
import java.util.concurrent.Executors

/** Retains transient content URIs only in native memory, never in Dart. */
class MainActivity : AudioServiceActivity() {
    private data class Source(val uri: Uri, val name: String,
        var stream: InputStream? = null, var done: Boolean = false)
    private val sources = LinkedHashMap<String, Source>()
    private val executor = Executors.newCachedThreadPool()
    private val ui = Handler(Looper.getMainLooper())
    private var bridge: MethodChannel? = null
    @Volatile private var destroyed = false

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        capture(intent)
    }

    override fun onNewIntent(value: Intent) {
        super.onNewIntent(value)
        setIntent(value)
        capture(value)
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        bridge = MethodChannel(engine.dartExecutor.binaryMessenger,
            "com.example.ereader/share_import")
        bridge?.setMethodCallHandler { call, result ->
            when (call.method) {
                "pending" -> {
                    val pending = synchronized(sources) {
                        sources.map { (id, item) ->
                            mapOf("id" to id, "name" to item.name)
                        }
                    }
                    result.success(pending)
                }
                "read" -> {
                    val id = call.argument<String>("id")
                    val item = synchronized(sources) { sources[id] }
                    if (item == null) {
                        result.error("expired", "Shared document unavailable", null)
                    } else {
                        executor.execute {
                            try {
                                val chunk = synchronized(item) {
                                    if (item.done) ByteArray(0) else {
                                        val input = item.stream
                                            ?: contentResolver.openInputStream(item.uri)
                                            ?: throw java.io.FileNotFoundException()
                                        item.stream = input
                                        val buffer = ByteArray(64 * 1024)
                                        val n = input.read(buffer)
                                        if (n < 0) {
                                            item.done = true
                                            input.close()
                                            item.stream = null
                                            ByteArray(0)
                                        } else buffer.copyOf(n)
                                    }
                                }
                                ui.post { result.success(chunk) }
                            } catch (_: Exception) {
                                ui.post { result.error("unavailable",
                                    "Shared document unavailable", null) }
                            }
                        }
                    }
                }
                "finish" -> {
                    val ids = call.argument<List<String>>("ids") ?: emptyList()
                    val retired = synchronized(sources) {
                        ids.mapNotNull { sources.remove(it) }
                    }
                    executor.execute {
                        retired.forEach { item ->
                            synchronized(item) {
                                try { item.stream?.close() } catch (_: Exception) {}
                                item.stream = null
                                item.done = true
                            }
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun capture(incoming: Intent?) {
        if (incoming == null ||
            (incoming.action != Intent.ACTION_SEND &&
             incoming.action != Intent.ACTION_SEND_MULTIPLE)) return
        val uris = LinkedHashSet<Uri>()
        if (incoming.action == Intent.ACTION_SEND)
            incoming.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let(uris::add)
        else
            incoming.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                ?.forEach(uris::add)
        incoming.clipData?.let { clip ->
            for (i in 0 until clip.itemCount.coerceAtMost(50))
                clip.getItemAt(i).uri?.let(uris::add)
        }
        // Clear the received Intent to prevent replay on Activity recreation.
        // URI grants are copied into native memory, not exposed to Flutter.
        val mime = incoming.type
        incoming.replaceExtras(Bundle())
        incoming.clipData = null
        incoming.action = Intent.ACTION_MAIN
        // Metadata queries for cloud providers can block: NEVER do them on
        // Android's main thread, even for a warm share of up to 50 documents.
        executor.execute {
            var added = false
            for (uri in uris.take(50)) {
                if (destroyed || uri.scheme != "content") continue
                val name = supportedName(uri, mime) ?: continue
                synchronized(sources) {
                    if (!destroyed && sources.size < 50) {
                        sources[UUID.randomUUID().toString()] = Source(uri, name)
                        added = true
                    }
                }
            }
            if (added) ui.post {
                if (!destroyed) bridge?.invokeMethod("sharedBooksAvailable", null)
            }
        }
    }

    private fun supportedName(uri: Uri, intentMime: String?): String? {
        var filename: String? = null
        var size: Long? = null
        try {
            contentResolver.query(uri,
                arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (nameIndex >= 0 && !cursor.isNull(nameIndex))
                        filename = cursor.getString(nameIndex)
                    if (sizeIndex >= 0 && !cursor.isNull(sizeIndex))
                        size = cursor.getLong(sizeIndex)
                }
            }
        } catch (_: Exception) {}
        val bytes = size
        if (bytes != null && (bytes < 1 || bytes > 100L * 1024L * 1024L))
            return null
        val mime = try { contentResolver.getType(uri) ?: intentMime }
            catch (_: Exception) { intentMime }
        val suffix = when (mime) {
            "application/epub+zip" -> "epub"
            "application/pdf" -> "pdf"
            "text/plain" -> "txt"
            else -> null
        }
        val clean = filename?.replace('\\', '/')?.substringAfterLast('/')
            ?.filter { !Character.isISOControl(it) }?.trim()?.take(160).orEmpty()
        if (clean.substringAfterLast('.', "").lowercase() in
            setOf("epub", "pdf", "txt") && clean.isNotEmpty()) return clean
        return suffix?.let { "Shared-book." + it }
    }

    override fun onDestroy() {
        destroyed = true
        bridge?.setMethodCallHandler(null)
        val retired = synchronized(sources) {
            val list = sources.values.toList()
            sources.clear()
            list
        }
        executor.execute {
            retired.forEach { item ->
                synchronized(item) {
                    try { item.stream?.close() } catch (_: Exception) {}
                    item.stream = null
                    item.done = true
                }
            }
        }
        executor.shutdown()
        super.onDestroy()
    }
}
