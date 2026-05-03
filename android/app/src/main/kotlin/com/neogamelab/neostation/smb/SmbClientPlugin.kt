package com.neogamelab.neostation.smb

import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import jcifs.CIFSContext
import jcifs.config.PropertyConfiguration
import jcifs.context.BaseContext
import jcifs.smb.NtlmPasswordAuthenticator
import jcifs.smb.SmbException
import jcifs.smb.SmbFile
import java.io.IOException
import java.util.Properties
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * SMB client plugin backed by JCIFS-NG.
 *
 * Method channel: `fr.idarius.idastation/smb`.
 *
 * Connections are identified by an opaque connectionId (UUID string) returned
 * from `connect`. All subsequent operations require a valid connectionId.
 *
 * Errors are reported via Result.error with codes:
 *   SMB_AUTH_FAILED, SMB_HOST_UNREACHABLE, SMB_SHARE_NOT_FOUND,
 *   SMB_PATH_NOT_FOUND, SMB_ACCESS_DENIED, SMB_TIMEOUT, SMB_UNKNOWN.
 */
class SmbClientPlugin : FlutterPlugin, MethodCallHandler {
    companion object {
        private const val TAG = "SmbClientPlugin"
        private const val CHANNEL = "fr.idarius.idastation/smb"
    }

    private lateinit var channel: MethodChannel

    private data class Connection(val context: CIFSContext, val rootUrl: String)

    private val connections = ConcurrentHashMap<String, Connection>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        connections.clear()
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        try {
            when (call.method) {
                "connect" -> connect(call, result)
                "disconnect" -> disconnect(call, result)
                "listDirectory" -> listDirectory(call, result)
                "fileExists" -> fileExists(call, result)
                "stat" -> stat(call, result)
                "mkdirs" -> mkdirs(call, result)
                "readFile" -> readFile(call, result)
                "writeFile" -> writeFile(call, result)
                "delete" -> delete(call, result)
                else -> result.notImplemented()
            }
        } catch (e: Throwable) {
            Log.e(TAG, "Uncaught error in ${call.method}", e)
            result.error("SMB_UNKNOWN", e.message ?: e.javaClass.simpleName, null)
        }
    }

    // ── connect ──────────────────────────────────────────────────────────────

    private fun connect(call: MethodCall, result: Result) {
        val host = call.argument<String>("host") ?: return result.error("SMB_UNKNOWN", "missing host", null)
        val share = call.argument<String>("share") ?: return result.error("SMB_UNKNOWN", "missing share", null)
        val user = call.argument<String>("user") ?: return result.error("SMB_UNKNOWN", "missing user", null)
        val pass = call.argument<String>("pass") ?: return result.error("SMB_UNKNOWN", "missing pass", null)
        val domain = call.argument<String>("domain") ?: "WORKGROUP"

        Thread {
            try {
                val props = Properties().apply {
                    put("jcifs.smb.client.minVersion", "SMB1")
                    put("jcifs.smb.client.maxVersion", "SMB311")
                    put("jcifs.smb.client.responseTimeout", "10000")
                    put("jcifs.smb.client.soTimeout", "10000")
                }
                val baseContext = BaseContext(PropertyConfiguration(props))
                val auth = NtlmPasswordAuthenticator(domain, user, pass)
                val context = baseContext.withCredentials(auth)
                val rootUrl = "smb://$host/$share/"

                // Validate by listing root (cheap operation that exercises auth + share existence)
                val root = SmbFile(rootUrl, context)
                root.list()  // throws if auth fails or share doesn't exist

                val id = UUID.randomUUID().toString()
                connections[id] = Connection(context, rootUrl)
                runOnMain { result.success(id) }
            } catch (e: SmbException) {
                runOnMain { reportSmbError(result, e) }
            } catch (e: IOException) {
                runOnMain { reportIoError(result, e) }
            } catch (e: Throwable) {
                Log.e(TAG, "connect failed", e)
                runOnMain { result.error("SMB_UNKNOWN", e.message, null) }
            }
        }.start()
    }

    // ── disconnect ───────────────────────────────────────────────────────────

    private fun disconnect(call: MethodCall, result: Result) {
        val id = call.argument<String>("connectionId") ?: return result.error("SMB_UNKNOWN", "missing connectionId", null)
        connections.remove(id)
        result.success(null)
    }

    // ── listDirectory ────────────────────────────────────────────────────────

    private fun listDirectory(call: MethodCall, result: Result) {
        val id = call.argument<String>("connectionId") ?: return result.error("SMB_UNKNOWN", "missing connectionId", null)
        val path = call.argument<String>("path") ?: ""
        val conn = connections[id] ?: return result.error("SMB_UNKNOWN", "unknown connectionId", null)

        Thread {
            try {
                val dir = SmbFile(conn.rootUrl + sanitize(path), conn.context)
                if (!dir.exists() || !dir.isDirectory) {
                    runOnMain { result.success(emptyList<Map<String, Any>>()) }
                    return@Thread
                }
                val entries = dir.listFiles().map { f ->
                    mapOf(
                        "name" to f.name.trimEnd('/'),
                        "isDir" to f.isDirectory,
                        "size" to (if (f.isFile) f.length() else 0L),
                        "modifiedAt" to f.lastModified()
                    )
                }
                runOnMain { result.success(entries) }
            } catch (e: SmbException) {
                runOnMain { reportSmbError(result, e) }
            } catch (e: Throwable) {
                Log.e(TAG, "listDirectory failed: $path", e)
                runOnMain { result.error("SMB_UNKNOWN", e.message, null) }
            }
        }.start()
    }

    // ── fileExists ───────────────────────────────────────────────────────────

    private fun fileExists(call: MethodCall, result: Result) {
        val id = call.argument<String>("connectionId") ?: return result.error("SMB_UNKNOWN", "missing connectionId", null)
        val path = call.argument<String>("path") ?: return result.error("SMB_UNKNOWN", "missing path", null)
        val conn = connections[id] ?: return result.error("SMB_UNKNOWN", "unknown connectionId", null)

        Thread {
            try {
                val f = SmbFile(conn.rootUrl + sanitize(path), conn.context)
                runOnMain { result.success(f.exists()) }
            } catch (e: SmbException) {
                runOnMain { reportSmbError(result, e) }
            } catch (e: Throwable) {
                runOnMain { result.error("SMB_UNKNOWN", e.message, null) }
            }
        }.start()
    }

    // ── stat ─────────────────────────────────────────────────────────────────

    private fun stat(call: MethodCall, result: Result) {
        val id = call.argument<String>("connectionId") ?: return result.error("SMB_UNKNOWN", "missing connectionId", null)
        val path = call.argument<String>("path") ?: return result.error("SMB_UNKNOWN", "missing path", null)
        val conn = connections[id] ?: return result.error("SMB_UNKNOWN", "unknown connectionId", null)

        Thread {
            try {
                val f = SmbFile(conn.rootUrl + sanitize(path), conn.context)
                if (!f.exists()) {
                    runOnMain { result.success(null) }
                    return@Thread
                }
                runOnMain {
                    result.success(mapOf(
                        "size" to (if (f.isFile) f.length() else 0L),
                        "modifiedAt" to f.lastModified(),
                        "isDir" to f.isDirectory
                    ))
                }
            } catch (e: Throwable) {
                runOnMain { result.error("SMB_UNKNOWN", e.message, null) }
            }
        }.start()
    }

    // ── mkdirs ───────────────────────────────────────────────────────────────

    private fun mkdirs(call: MethodCall, result: Result) {
        val id = call.argument<String>("connectionId") ?: return result.error("SMB_UNKNOWN", "missing connectionId", null)
        val path = call.argument<String>("path") ?: return result.error("SMB_UNKNOWN", "missing path", null)
        val conn = connections[id] ?: return result.error("SMB_UNKNOWN", "unknown connectionId", null)

        Thread {
            try {
                val sanitizedPath = sanitize(path).let { if (it.endsWith("/")) it else "$it/" }
                val d = SmbFile(conn.rootUrl + sanitizedPath, conn.context)
                if (!d.exists()) d.mkdirs()
                runOnMain { result.success(null) }
            } catch (e: SmbException) {
                runOnMain { reportSmbError(result, e) }
            } catch (e: Throwable) {
                runOnMain { result.error("SMB_UNKNOWN", e.message, null) }
            }
        }.start()
    }

    // ── readFile ─────────────────────────────────────────────────────────────

    private fun readFile(call: MethodCall, result: Result) {
        val id = call.argument<String>("connectionId") ?: return result.error("SMB_UNKNOWN", "missing connectionId", null)
        val path = call.argument<String>("path") ?: return result.error("SMB_UNKNOWN", "missing path", null)
        val conn = connections[id] ?: return result.error("SMB_UNKNOWN", "unknown connectionId", null)

        Thread {
            try {
                val f = SmbFile(conn.rootUrl + sanitize(path), conn.context)
                if (!f.exists()) {
                    runOnMain { result.error("SMB_PATH_NOT_FOUND", "file not found: $path", null) }
                    return@Thread
                }
                val bytes = f.inputStream.use { it.readBytes() }
                runOnMain { result.success(bytes) }
            } catch (e: SmbException) {
                runOnMain { reportSmbError(result, e) }
            } catch (e: Throwable) {
                runOnMain { result.error("SMB_UNKNOWN", e.message, null) }
            }
        }.start()
    }

    // ── writeFile ────────────────────────────────────────────────────────────

    private fun writeFile(call: MethodCall, result: Result) {
        val id = call.argument<String>("connectionId") ?: return result.error("SMB_UNKNOWN", "missing connectionId", null)
        val path = call.argument<String>("path") ?: return result.error("SMB_UNKNOWN", "missing path", null)
        val bytes = call.argument<ByteArray>("bytes") ?: return result.error("SMB_UNKNOWN", "missing bytes", null)
        val conn = connections[id] ?: return result.error("SMB_UNKNOWN", "unknown connectionId", null)

        Thread {
            try {
                // Ensure parent dirs exist
                val parent = sanitize(path).substringBeforeLast('/', missingDelimiterValue = "")
                if (parent.isNotEmpty()) {
                    val dir = SmbFile(conn.rootUrl + parent + "/", conn.context)
                    if (!dir.exists()) dir.mkdirs()
                }
                val f = SmbFile(conn.rootUrl + sanitize(path), conn.context)
                f.outputStream.use { it.write(bytes) }
                runOnMain { result.success(null) }
            } catch (e: SmbException) {
                runOnMain { reportSmbError(result, e) }
            } catch (e: Throwable) {
                runOnMain { result.error("SMB_UNKNOWN", e.message, null) }
            }
        }.start()
    }

    // ── delete ───────────────────────────────────────────────────────────────

    private fun delete(call: MethodCall, result: Result) {
        val id = call.argument<String>("connectionId") ?: return result.error("SMB_UNKNOWN", "missing connectionId", null)
        val path = call.argument<String>("path") ?: return result.error("SMB_UNKNOWN", "missing path", null)
        val conn = connections[id] ?: return result.error("SMB_UNKNOWN", "unknown connectionId", null)

        Thread {
            try {
                val f = SmbFile(conn.rootUrl + sanitize(path), conn.context)
                if (!f.exists()) {
                    runOnMain { result.error("SMB_PATH_NOT_FOUND", "file not found: $path", null) }
                    return@Thread
                }
                f.delete()
                runOnMain { result.success(null) }
            } catch (e: SmbException) {
                runOnMain { reportSmbError(result, e) }
            } catch (e: Throwable) {
                runOnMain { result.error("SMB_UNKNOWN", e.message, null) }
            }
        }.start()
    }

    // ── helpers ──────────────────────────────────────────────────────────────

    private fun sanitize(path: String): String {
        // Strip leading slashes; replace backslashes with forward.
        return path.trimStart('/', '\\').replace('\\', '/')
    }

    private fun reportSmbError(result: Result, e: SmbException) {
        val msg = e.message ?: e.javaClass.simpleName
        val code = when {
            msg.contains("LOGON_FAILURE", ignoreCase = true) -> "SMB_AUTH_FAILED"
            msg.contains("ACCESS_DENIED", ignoreCase = true) -> "SMB_ACCESS_DENIED"
            msg.contains("BAD_NETWORK_NAME", ignoreCase = true) -> "SMB_SHARE_NOT_FOUND"
            msg.contains("OBJECT_NAME_NOT_FOUND", ignoreCase = true) -> "SMB_PATH_NOT_FOUND"
            else -> "SMB_UNKNOWN"
        }
        result.error(code, msg, null)
    }

    private fun reportIoError(result: Result, e: IOException) {
        val msg = e.message ?: e.javaClass.simpleName
        val code = when {
            msg.contains("timed out", ignoreCase = true) || msg.contains("timeout", ignoreCase = true) -> "SMB_TIMEOUT"
            msg.contains("unreachable", ignoreCase = true) || msg.contains("connection refused", ignoreCase = true) -> "SMB_HOST_UNREACHABLE"
            else -> "SMB_UNKNOWN"
        }
        result.error(code, msg, null)
    }

    private fun runOnMain(block: () -> Unit) {
        android.os.Handler(android.os.Looper.getMainLooper()).post(block)
    }
}
