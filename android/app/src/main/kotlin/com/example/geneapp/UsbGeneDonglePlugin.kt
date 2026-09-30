package com.example.geneapp

import android.app.Activity
import android.content.*
import android.net.Uri
import android.os.*
import android.os.storage.StorageManager
import android.os.storage.StorageVolume
import android.provider.DocumentsContract
import com.example.geneapp.usb.*
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.*
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors
import java.util.concurrent.ExecutorService
import java.util.concurrent.atomic.AtomicLong

/** Storage access stays separate from chat/API and never requests write permission. */
class UsbGeneDonglePlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler, PluginRegistry.ActivityResultListener {
    private lateinit var context: Context
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private lateinit var worker: ExecutorService
    private val main = Handler(Looper.getMainLooper())
    private val generation = AtomicLong(0)
    private val publicationLock = Any()
    private fun invalidate(): Long = synchronized(publicationLock) { generation.incrementAndGet() }
    private var attached = false
    private var binding: ActivityPluginBinding? = null
    private var sink: EventChannel.EventSink? = null
    private var picker: MethodChannel.Result? = null
    private var requestedVolume: String? = null
    private var revision = 0L
    private var imported: GeneDataset? = null
    private var snapshot: Map<String, Any?> = emptyMap()
    private var currentVolumes: List<Map<String, Any>> = emptyList()
    private var receiverRegistered = false
    private val pending = mutableSetOf<MethodChannel.Result>()
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) { refresh(null) }
    }
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        worker = Executors.newSingleThreadExecutor { runnable -> Thread(runnable, "gene-dongle-import") }
        attached = true
        methods = MethodChannel(binding.binaryMessenger, "geneedge/usb_gene_dongle")
        events = EventChannel(binding.binaryMessenger, "geneedge/usb_gene_dongle/events")
        methods.setMethodCallHandler(this); events.setStreamHandler(this)
        publish("no_device", emptyList())
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopActivity()
        attached = false; invalidate(); sink = null
        pending.forEach { it.success(snapshot) }; pending.clear()
        methods.setMethodCallHandler(null); events.setStreamHandler(null)
        worker.shutdownNow()
    }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        this.binding = binding; binding.addActivityResultListener(this)
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_MEDIA_MOUNTED); addAction(Intent.ACTION_MEDIA_UNMOUNTED)
            addAction(Intent.ACTION_MEDIA_EJECT); addAction(Intent.ACTION_MEDIA_REMOVED)
            addAction(Intent.ACTION_MEDIA_BAD_REMOVAL); addDataScheme("file")
        }
        if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        else context.registerReceiver(receiver, filter)
        receiverRegistered = true
        if (sink != null) refresh(null)
    }
    private fun stopActivity() {
        invalidate()
        binding?.removeActivityResultListener(this); binding = null
        if (receiverRegistered) { context.unregisterReceiver(receiver); receiverRegistered = false }
        picker?.let { finishError("cancelled", it) }; picker = null; requestedVolume = null
        pending.toList().forEach { finishError("cancelled", it) }; pending.clear()
    }
    override fun onDetachedFromActivityForConfigChanges() = stopActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivity() = stopActivity()
    override fun onListen(arguments: Any?, events: EventChannel.EventSink) { sink = events; refresh(null) }
    override fun onCancel(arguments: Any?) {
        sink = null; invalidate()
        pending.toList().forEach { it.success(snapshot) }; pending.clear()
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "refresh" -> refresh(result)
            "requestAccess" -> requestAccess(call.argument<String>("volumeId"), result)
            else -> result.notImplemented()
        }
    }
    private fun volumes(): List<StorageVolume> = context.getSystemService(StorageManager::class.java).storageVolumes.filter {
        !it.isPrimary && it.isRemovable && it.uuid != null && (it.state == Environment.MEDIA_MOUNTED || it.state == Environment.MEDIA_MOUNTED_READ_ONLY)
    }
    private fun valid(uri: Uri, mounted: Set<String>, requested: String? = null): Boolean = try {
        uri.scheme == "content" && DocumentsContract.isTreeUri(uri) && GeneSourcePolicy.accepts(uri.authority, DocumentsContract.getTreeDocumentId(uri), mounted, requested)
    } catch (_: Exception) { false }
    private fun grants(mounted: Set<String>): List<Uri> = context.contentResolver.persistedUriPermissions.filter {
        it.isReadPermission && valid(it.uri, mounted)
    }.map { it.uri }
    private fun volumeMaps(volumes: List<StorageVolume>, roots: List<Uri>): List<Map<String, Any>> = volumes.map { volume ->
        mapOf("id" to volume.uuid!!, "label" to volume.getDescription(context), "authorized" to roots.any {
            DocumentsContract.getTreeDocumentId(it).substringBefore(':').equals(volume.uuid, true)
        })
    }
    private fun publish(state: String, volumes: List<Map<String, Any>>, error: String? = null): Map<String, Any?> {
        currentVolumes = volumes
        snapshot = mapOf("revision" to ++revision, "state" to state, "volumes" to volumes, "imported" to imported?.snapshot(), "errorCode" to error)
        if (attached) sink?.success(snapshot)
        return snapshot
    }
    private fun finishError(code: String, result: MethodChannel.Result) {
        result.success(publish("error", currentVolumes, code)); pending.remove(result)
    }
    private fun refresh(result: MethodChannel.Result?) {
        val token = invalidate()
        if (result != null) pending.add(result)
        // Complete superseded method calls with the newer scanning snapshot, never leave a Future hanging.
        val scanning = publish("scanning", currentVolumes)
        pending.filter { it !== result }.toList().forEach { it.success(scanning); pending.remove(it) }
        worker.execute {
            try {
                val importer = GeneDongleImporter(AndroidTree(context), File(context.noBackupFilesDir, "gene-dongle"), publicationLock = publicationLock)
                val last = importer.restore()
                val mounted = volumes()
                val roots = grants(mounted.mapNotNull { it.uuid }.toSet())
                val maps = volumeMaps(mounted, roots)
                val outcome = when {
                    mounted.isEmpty() -> GeneImportResult("no_device")
                    roots.isEmpty() -> GeneImportResult("permission_required")
                    else -> importer.import(roots.map { AndroidTree.root(context, it) }) { generation.get() != token }
                }
                val state = if (outcome.state == "missing_files" && maps.any { it["authorized"] == false }) "permission_required" else outcome.state
                main.post {
                    if (attached && generation.get() == token) {
                        imported = outcome.dataset ?: last
                        val next = publish(state, maps, outcome.errorCode)
                        if (result != null && pending.remove(result)) result.success(next)
                    }
                }
            } catch (_: Exception) {
                main.post { if (attached && generation.get() == token) {
                    val next = publish("error", currentVolumes, "io_failed")
                    if (result != null && pending.remove(result)) result.success(next)
                } }
            }
        }
    }
    private fun requestAccess(volumeId: String?, result: MethodChannel.Result) {
        if (picker != null) { finishError("cancelled", result); return }
        val activity = binding?.activity
        val volume = try { volumes().find { it.uuid.equals(volumeId, true) } } catch (_: Exception) { null }
        if (activity == null || volume == null) { finishError("invalid_source", result); return }
        invalidate()
        pending.toList().forEach { it.success(snapshot) }; pending.clear()
        picker = result; requestedVolume = volumeId
        try {
            val intent = if (Build.VERSION.SDK_INT >= 29) volume.createOpenDocumentTreeIntent() else Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
            intent.flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
            activity.startActivityForResult(intent, 61904)
        } catch (_: Exception) { picker = null; requestedVolume = null; finishError("io_failed", result) }
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != 61904) return false
        val result = picker ?: return true
        val requested = requestedVolume
        picker = null; requestedVolume = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) { finishError("permission_denied", result); return true }
        val uri = data.data!!
        try {
            if (!valid(uri, volumes().mapNotNull { it.uuid }.toSet(), requested)) { finishError("invalid_source", result); return true }
            context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            // Replace an older subtree grant on this volume; other volume grants survive.
            val old = context.contentResolver.persistedUriPermissions.filter { it.uri != uri && it.isReadPermission && valid(it.uri, setOf(requested!!)) }
            old.forEach { context.contentResolver.releasePersistableUriPermission(it.uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
            refresh(result)
        } catch (_: Exception) { finishError("permission_denied", result) }
        return true
    }

    private class AndroidTree(private val context: Context) : GeneTree {
        override fun list(directory: GeneEntry): List<GeneEntry> {
            val uri = Uri.parse(directory.uri)
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(uri, DocumentsContract.getDocumentId(uri))
            val columns = arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE)
            val cursor = context.contentResolver.query(children, columns, null, null, null) ?: throw IOException()
            return cursor.use {
                val found = mutableListOf<GeneEntry>()
                while (it.moveToNext()) {
                    if (found.size >= 10000) throw GeneScanLimitException()
                    found.add(GeneEntry(DocumentsContract.buildDocumentUriUsingTree(uri, it.getString(0)).toString(), it.getString(1) ?: "", it.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR))
                }
                found
            }
        }
        override fun open(file: GeneEntry) = context.contentResolver.openInputStream(Uri.parse(file.uri)) ?: throw IOException()
        companion object {
            fun root(context: Context, tree: Uri): GeneEntry {
                val doc = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
                val cursor = context.contentResolver.query(doc, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null) ?: throw IOException()
                return cursor.use { if (!it.moveToFirst()) throw IOException(); GeneEntry(doc.toString(), it.getString(0)?.takeIf { name -> name.isNotBlank() } ?: "Gene dongle", true) }
            }
        }
    }
}
