package com.example.geneapp

import android.app.Activity
import android.content.*
import android.net.Uri
import android.os.*
import android.os.storage.StorageManager
import android.os.storage.StorageVolume
import android.provider.DocumentsContract
import android.system.Os
import android.system.OsConstants
import com.example.geneapp.snp.*
import com.example.geneapp.usb.*
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.*
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.Executors

/** Permission/worker adapter only. All counting and probability arithmetic are native C. */
class SnpComputePlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler, PluginRegistry.ActivityResultListener {
    private lateinit var context: Context
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val gate = SnpJobGate()
    @Volatile private var opening: CancellationSignal? = null
    private var binding: ActivityPluginBinding? = null
    private var sink: EventChannel.EventSink? = null
    private var attached = false
    private var receiverRegistered = false
    private var revision = 0L
    @Volatile private var sourceRevision = 0L
    private var jobId: String? = null
    private var jobCompleted = 0
    private var jobTotal = 0
    private var sources = emptyMap<String, SnpSource>()
    private var selected: String? = null
    private var picker: MethodChannel.Result? = null
    private var pickerVolume: String? = null
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context?, i: Intent?) { invalidate("USB_REMOVED"); sources = emptyMap() }
    }
    private external fun nativeCompute(idx: Int, ids: Int, sequence: String, ref: String, alt: String, token: Long): String
    // Called from JNI in the worker. No UI state is accessed from that thread.
    fun isCancelled(token: Long): Boolean = !gate.current(token) || Thread.currentThread().isInterrupted
    companion object { init { System.loadLibrary("geneedge_snp") } }

    override fun onAttachedToEngine(b: FlutterPlugin.FlutterPluginBinding) {
        context = b.applicationContext; attached = true
        methods = MethodChannel(b.binaryMessenger, "geneedge/snp_compute"); methods.setMethodCallHandler(this)
        events = EventChannel(b.binaryMessenger, "geneedge/snp_compute/events"); events.setStreamHandler(this)
    }
    override fun onDetachedFromEngine(b: FlutterPlugin.FlutterPluginBinding) {
        stopActivity(); attached = false; methods.setMethodCallHandler(null); events.setStreamHandler(null)
        sink = null; worker.shutdownNow()
    }
    override fun onAttachedToActivity(b: ActivityPluginBinding) {
        binding = b; b.addActivityResultListener(this)
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_MEDIA_EJECT); addAction(Intent.ACTION_MEDIA_UNMOUNTED)
            addAction(Intent.ACTION_MEDIA_REMOVED); addAction(Intent.ACTION_MEDIA_BAD_REMOVAL); addAction(Intent.ACTION_MEDIA_MOUNTED)
            addDataScheme("file")
        }
        if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        else context.registerReceiver(receiver, filter)
        receiverRegistered = true
    }
    private fun stopActivity() {
        invalidate("CANCELLED"); binding?.removeActivityResultListener(this); binding = null
        if (receiverRegistered) { context.unregisterReceiver(receiver); receiverRegistered = false }
        picker?.error("CANCELLED", "Selection cancelled", null); picker = null; pickerVolume = null
    }
    override fun onDetachedFromActivityForConfigChanges() = stopActivity()
    override fun onReattachedToActivityForConfigChanges(b: ActivityPluginBinding) = onAttachedToActivity(b)
    override fun onDetachedFromActivity() = stopActivity()
    override fun onListen(args: Any?, eventSink: EventChannel.EventSink) { sink = eventSink }
    override fun onCancel(args: Any?) { invalidate("CANCELLED"); sink = null }
    private fun invalidate(code: String) {
        gate.invalidate(); opening?.cancel(); sourceRevision++; selected = null
        emit(mapOf("status" to "invalidated", "errorCode" to code))
    }
    private fun emit(data: Map<String, Any?>) { if (attached) sink?.success(
        mapOf("jobId" to jobId, "completed" to jobCompleted, "total" to jobTotal) + data + ("revision" to ++revision)) }
    private fun volumes(): List<StorageVolume> = context.getSystemService(StorageManager::class.java).storageVolumes.filter {
        !it.isPrimary && it.isRemovable && it.uuid != null && it.state in listOf(Environment.MEDIA_MOUNTED, Environment.MEDIA_MOUNTED_READ_ONLY)
    }
    private fun valid(uri: Uri, requested: String? = null): Boolean = try {
        uri.scheme == "content" && DocumentsContract.isTreeUri(uri) && GeneSourcePolicy.accepts(uri.authority,
            DocumentsContract.getTreeDocumentId(uri), volumes().mapNotNull { it.uuid }.toSet(), requested)
    } catch (_: Exception) { false }
    private fun authorized(uri: Uri): Boolean = context.contentResolver.persistedUriPermissions.any {
        it.isReadPermission && valid(it.uri) && DocumentsContract.getTreeDocumentId(it.uri) == DocumentsContract.getTreeDocumentId(uri)
    }
    private fun snapshot(): Map<String, Any?> = mapOf("revision" to revision, "selectedSourceId" to selected,
        "sources" to sources.map { (id, s) -> mapOf("id" to id, "label" to s.folder.name) },
        "volumes" to volumes().map { v -> mapOf("id" to v.uuid, "label" to v.getDescription(context), "authorized" to
            context.contentResolver.persistedUriPermissions.any { it.isReadPermission && valid(it.uri, v.uuid) }) })
    private fun failure(e: Exception): String = when(e) {
        is SnpFailure -> e.code; is SecurityException -> "PERMISSION_DENIED"; else -> "IO_ERROR"
    }
    private fun discover(result: MethodChannel.Result) {
        val token = sourceRevision
        worker.execute {
            try {
                val roots = context.contentResolver.persistedUriPermissions.filter { it.isReadPermission && valid(it.uri) }.map {
                    val doc = DocumentsContract.buildDocumentUriUsingTree(it.uri, DocumentsContract.getTreeDocumentId(it.uri))
                    GeneEntry(doc.toString(), DocumentsContract.getTreeDocumentId(it.uri), true)
                }
                val found = SnpSourceScanner(AndroidSnpTree(context)).scan(roots) { token != sourceRevision }
                main.post {
                    if (!attached || token != sourceRevision) result.error("CANCELLED", "Source changed", null)
                    else {
                        sources = found.associateBy { it.folder.uri }
                        if (selected != null && !sources.containsKey(selected)) invalidate("USB_REMOVED")
                        revision++; result.success(snapshot())
                    }
                }
            } catch(e: Exception) { main.post { result.error(failure(e), "Unable to discover USB source", null) } }
        }
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when(call.method) {
                "sources" -> discover(result)
                "requestAccess" -> requestAccess(call.argument<String>("volumeId"), result)
                "pickPanel" -> {
                    if (picker != null) throw SnpFailure("BUSY")
                    val activity = binding?.activity ?: throw SnpFailure("CANCELLED")
                    picker = result; pickerVolume = null
                    try { activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        type = "*/*"; addCategory(Intent.CATEGORY_OPENABLE); flags = Intent.FLAG_GRANT_READ_URI_PERMISSION
                    }, 61906) } catch(e: Exception) { picker = null; throw e }
                }
                "selectSource" -> {
                    val id = call.argument<String>("sourceId") ?: throw SnpFailure("INVALID_FORMAT")
                    if (!sources.containsKey(id) || !valid(Uri.parse(id)) || !authorized(Uri.parse(id))) throw SnpFailure("PERMISSION_DENIED")
                    invalidate("CANCELLED"); selected = id; result.success(snapshot())
                }
                "run" -> run(call, result)
                "cancel" -> { gate.invalidate(); opening?.cancel(); emit(mapOf("status" to "cancelled")); result.success(null) }
                else -> result.notImplemented()
            }
        } catch(e: Exception) { result.error(failure(e), "SNP operation rejected", null) }
    }
    private fun requestAccess(id: String?, result: MethodChannel.Result) {
        if (picker != null) throw SnpFailure("BUSY")
        val activity = binding?.activity ?: throw SnpFailure("CANCELLED")
        val volume = volumes().find { it.uuid.equals(id, true) } ?: throw SnpFailure("USB_REMOVED")
        picker = result; pickerVolume = volume.uuid
        try {
            val intent = if (Build.VERSION.SDK_INT >= 29) volume.createOpenDocumentTreeIntent() else Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
            intent.flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
            activity.startActivityForResult(intent, 61905)
        } catch(e: Exception) { picker = null; pickerVolume = null; throw e }
    }
    override fun onActivityResult(code: Int, resultCode: Int, data: Intent?): Boolean {
        if (code !in listOf(61905, 61906)) return false
        val result = picker ?: return true; val volume = pickerVolume; picker = null; pickerVolume = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { result.error("PERMISSION_DENIED", "Selection cancelled", null); return true }
        if (code == 61905) {
            try {
                if (!valid(uri, volume)) throw SnpFailure("PERMISSION_DENIED")
                context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                invalidate("CANCELLED"); discover(result)
            } catch(e: Exception) { result.error(failure(e), "USB permission rejected", null) }
        } else worker.execute {
            try {
                val text = context.contentResolver.openInputStream(uri)?.use {
                    val output = java.io.ByteArrayOutputStream(); val buffer = ByteArray(8192)
                    while (true) {
                        val count = it.read(buffer); if (count < 0) break
                        if (output.size() + count > 2 * 1024 * 1024) throw SnpFailure("RESOURCE_LIMIT")
                        output.write(buffer, 0, count)
                    }
                    output.toString("UTF-8")
                } ?: throw IOException()
                main.post { result.success(text) }
            } catch(e: Exception) { main.post { result.error(failure(e), "Unable to read panel", null) } }
        }
        return true
    }
    private fun run(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("sourceId") ?: throw SnpFailure("PERMISSION_DENIED")
        val source = sources[id] ?: throw SnpFailure("PERMISSION_DENIED")
        if (id != selected || !valid(Uri.parse(id)) || !authorized(Uri.parse(id))) throw SnpFailure("PERMISSION_DENIED")
        val raw = call.argument<List<*>>("queries") ?: throw SnpFailure("INVALID_QUERY")
        val queries = raw.map { item ->
            val m = item as? Map<*, *> ?: throw SnpFailure("INVALID_QUERY")
            SnpQuery(m["id"] as? String ?: "", m["sequence"] as? String ?: "", m["ref"] as? String ?: "", m["alt"] as? String ?: "")
        }
        if (!SnpContracts.validQueries(queries)) throw SnpFailure("INVALID_QUERY")
        val token = gate.start(); val jobId = token.toString()
        this.jobId = jobId; jobCompleted = 0; jobTotal = queries.size
        result.success(mapOf("jobId" to jobId))
        emit(mapOf("jobId" to jobId, "status" to "running", "completed" to 0, "total" to queries.size))
        worker.execute {
            val signal = CancellationSignal(); opening = signal
            try {
                val resolver = context.contentResolver
                if (isCancelled(token)) throw SnpFailure("CANCELLED")
                if (!valid(Uri.parse(id)) || !authorized(Uri.parse(id))) throw SnpFailure("USB_REMOVED")
                resolver.openFileDescriptor(Uri.parse(source.idx.uri), "r", signal)?.use { idx ->
                    resolver.openFileDescriptor(Uri.parse(source.ids.uri), "r", signal)?.use { ids ->
                        val idxSize = Os.fstat(idx.fileDescriptor).st_size; val idsSize = Os.fstat(ids.fileDescriptor).st_size
                        if (!SnpContracts.validSizes(idxSize, idsSize)) throw SnpFailure("INVALID_FORMAT")
                        try { Os.lseek(idx.fileDescriptor, 0, OsConstants.SEEK_CUR); Os.lseek(ids.fileDescriptor, 0, OsConstants.SEEK_CUR) }
                        catch (_: Exception) { throw SnpFailure("NOT_SEEKABLE") }
                        val rows = mutableListOf<Map<String, Any?>>()
                        queries.forEachIndexed { index, q ->
                            if (isCancelled(token)) throw SnpFailure("CANCELLED")
                            val data = JSONObject(nativeCompute(idx.fd, ids.fd, q.sequence, q.ref, q.alt, token))
                            if (data.has("errorCode")) throw SnpFailure(data.getString("errorCode"))
                            rows.add(jsonMap(data) + mapOf("id" to q.id, "refAllele" to q.ref, "altAllele" to q.alt,
                                "sourceId" to id, "sourceLabel" to source.folder.name))
                            main.post { if (gate.current(token)) { jobCompleted = index + 1; emit(mapOf("jobId" to jobId, "status" to "running")) } }
                        }
                        main.post { if (gate.current(token)) emit(mapOf("jobId" to jobId, "status" to "completed", "completed" to queries.size, "total" to queries.size, "results" to rows)) }
                    } ?: throw IOException()
                } ?: throw IOException()
            } catch(e: Throwable) {
                val code = when(e) { is OutOfMemoryError -> "RESOURCE_LIMIT"; is Exception -> failure(e); else -> "IO_ERROR" }
                main.post { if (gate.current(token)) emit(mapOf("jobId" to jobId, "status" to "error", "errorCode" to code)) }
            } finally {
                opening = null
                main.post { gate.finish(token) }
            }
        }
    }
    private fun jsonMap(obj: JSONObject): Map<String, Any?> = obj.keys().asSequence().associateWith { key -> jsonValue(obj.get(key)) }
    private fun jsonValue(v: Any?): Any? = when(v) {
        JSONObject.NULL -> null
        is JSONObject -> jsonMap(v)
        is org.json.JSONArray -> (0 until v.length()).map { jsonValue(v.get(it)) }
        else -> v
    }
    private class AndroidSnpTree(private val context: Context) : GeneTree {
        override fun open(file: GeneEntry) = throw UnsupportedOperationException("Discovery never copies data")
        override fun list(directory: GeneEntry): List<GeneEntry> {
            val uri = Uri.parse(directory.uri)
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(uri, DocumentsContract.getDocumentId(uri))
            val columns = arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE)
            return (context.contentResolver.query(children, columns, null, null, null) ?: throw IOException()).use { cursor ->
                val list = mutableListOf<GeneEntry>()
                while (cursor.moveToNext()) {
                    if (list.size >= 10000) throw SnpFailure("RESOURCE_LIMIT")
                    list.add(GeneEntry(DocumentsContract.buildDocumentUriUsingTree(uri, cursor.getString(0)).toString(), cursor.getString(1) ?: "", cursor.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR))
                }; list
            }
        }
    }
}
