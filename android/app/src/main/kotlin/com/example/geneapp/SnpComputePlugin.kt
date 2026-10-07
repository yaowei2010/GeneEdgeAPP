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
import android.util.Log
import com.example.geneapp.snp.*
import com.example.geneapp.usb.*
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.*
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.Executors

/**
 * 手機 SNP 運算的 Android 管理層。
 * 呼叫鏈：Flutter MethodChannel → Kotlin 開啟 USB 檔案 → JNI → C → EventChannel 回報。
 *
 * 職責界線：本類別只管理 USB 權限、來源、檔案描述符及背景工作的生命週期。
 * SNP 查詢／計數與 genotype 機率運算均在 C，不能在這裡用 Kotlin 重算。
 * 這個計算流程直接讀 USB，不複製 combined 檔案；舊 UsbGeneDonglePlugin 匯入功能是另一條流程。
 * 聊天 UI、API request JSON 轉換及 LLM 網路呼叫由 Flutter 層處理，不在本類別進行。
 */
class SnpComputePlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler, PluginRegistry.ActivityResultListener {
    private lateinit var context: Context
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    // worker 負責掃描／檔案 I/O／C 計算；main 負責發布 Flutter 狀態，避免阻塞 UI。
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    // gate 的 token 識別有效工作；sourceRevision 識別有效來源／授權掃描。
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
    private var jobDebug = false
    @Volatile private var jobStarted = 0L
    private var sources = emptyMap<String, SnpSource>()
    private var selected: String? = null
    private var picker: MethodChannel.Result? = null
    private var pickerVolume: String? = null
    private var pickerSourceRevision = 0L
    // 只記住每個 USB UUID 選過的來源 URI；這不是授權，也不保存基因資料或結果。
    private val sourcePreferences get() = context.getSharedPreferences("snp_usb_sources", Context.MODE_PRIVATE)
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context?, i: Intent?) {
            // 掛載／卸載等媒體狀態變化一律使舊工作與來源失效，通知 Flutter 重新搜尋。
            // 此處不自動運算，也不直接開系統授權畫面。
            invalidate("USB_REMOVED"); sources = emptyMap()
            emit(mapOf("status" to "sourcesChanged"))
        }
    }
    // JNI 入口：idx／ids 是已開啟的唯讀描述符，不是手機檔案路徑。
    // nativeCompute 是舊二等位單筆模式；nativeComputeLocus 是聊天室同位點聯合模式。
    // C／JNI 回傳結果 JSON，Kotlin 只轉換資料形狀，不判定 genotype。
    private external fun nativeCompute(idx: Int, ids: Int, sequence: String, ref: String, alt: String, token: Long, debug: Boolean): String
    private external fun nativeComputeLocus(idx:Int,ids:Int,sequences:Array<String>,ref:String,token:Long,debug:Boolean):String
    // C 透過 JNI 在背景執行緒詢問取消狀態，不存取 UI；取消是合作式停止，非強制終止 C。
    fun isCancelled(token: Long): Boolean = !gate.current(token) || Thread.currentThread().isInterrupted
    companion object { init { System.loadLibrary("geneedge_snp") } }

    override fun onAttachedToEngine(b: FlutterPlugin.FlutterPluginBinding) {
        // MethodChannel 接命令，EventChannel 持續回報進度／完成／錯誤。
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
        // Activity 分離或重建時停止舊工作，解除廣播／picker callback，避免回覆舊畫面。
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
        // 先記錄中斷耗時，再取消工作與開檔、清除選定來源並推進來源版本。
        // 過期結果會被 gate／sourceRevision 守衛丟棄，不能復活成成功結果。
        val diagnostic = interrupted("invalidated")
        gate.invalidate(); opening?.cancel(); sourceRevision++; selected = null
        emit(mapOf("status" to "invalidated", "errorCode" to code) + diagnostic)
    }
    private fun interrupted(status: String): Map<String, Any?> {
        // 只有 debug 且工作仍有效時提供 elapsedMs；中斷不偽造完整成功的分段計時。
        val active = jobId?.toLongOrNull()?.let { gate.current(it) } == true
        val elapsed = SnpDebug.elapsed(jobDebug,jobStarted,SystemClock.elapsedRealtimeNanos(),active) ?: return emptyMap()
        SnpDebug.logTerminal(true,status,elapsed)?.let { Log.d("GeneEdgeSnp",it) }
        return mapOf("elapsedMs" to elapsed)
    }
    // 每個事件附工作 ID、進度與遞增 revision，供 Flutter 排除過期通知。
    private fun emit(data: Map<String, Any?>) { if (attached) sink?.success(
        mapOf("jobId" to jobId, "completed" to jobCompleted, "total" to jobTotal) + data + ("revision" to ++revision)) }
    // 只接受已掛載（含唯讀掛載）的可移除卷，排除手機 primary 儲存空間。
    private fun volumes(): List<StorageVolume> = context.getSystemService(StorageManager::class.java).storageVolumes.filter {
        !it.isPrimary && it.isRemovable && it.uuid != null && it.state in listOf(Environment.MEDIA_MOUNTED, Environment.MEDIA_MOUNTED_READ_ONLY)
    }
    private fun valid(uri: Uri, requested: String? = null): Boolean = try {
        uri.scheme == "content" && DocumentsContract.isTreeUri(uri) && GeneSourcePolicy.accepts(uri.authority,
            DocumentsContract.getTreeDocumentId(uri), volumes().mapNotNull { it.uuid }.toSet(), requested)
    } catch (_: Exception) { false }
    // 記住來源不代表仍有權限：每次都核對目前掛載與 Android 保存的唯讀 tree grant。
    private fun authorized(uri: Uri): Boolean = context.contentResolver.persistedUriPermissions.any {
        it.isReadPermission && valid(it.uri) && DocumentsContract.getTreeDocumentId(it.uri) == DocumentsContract.getTreeDocumentId(uri)
    }
    private fun sourceVolume(id: String): String = DocumentsContract.getDocumentId(Uri.parse(id)).substringBefore(':')
    private fun snapshot(): Map<String, Any?> = mapOf("revision" to revision, "selectedSourceId" to selected,
        "sources" to sources.map { (id, s) -> mapOf("id" to id, "label" to s.folder.name, "volumeId" to sourceVolume(id)) },
        "volumes" to volumes().map { v ->
            val grants = context.contentResolver.persistedUriPermissions.filter { it.isReadPermission && valid(it.uri, v.uuid) }
            mapOf("id" to v.uuid, "label" to v.getDescription(context), "authorized" to grants.isNotEmpty(),
                "authorizationScopes" to grants.map { SnpUsbAccess.scopeLabel(DocumentsContract.getTreeDocumentId(it.uri)) }.distinct())
        })
    private fun failure(e: Exception): String = when(e) {
        is SnpFailure -> e.code; is SecurityException -> "PERMISSION_DENIED"; else -> "IO_ERROR"
    }
    private fun discover(result: MethodChannel.Result) {
        // 掃描只走已授權 USB tree，搜尋同資料夾的 combined_idx_all.txt／combined_ids_all.txt。
        // 掛載資訊先回報，讓 Flutter 不必等完整掃描才顯示插入確認；scanning 不是 ready。
        val token = sourceRevision
        // Publish mounted volumes before provider traversal, which can be slow.
        // A snapshot is not a completed scan or permission to start computation.
        emit(mapOf("status" to "sourcesSnapshot") + snapshot() + ("scanning" to true))
        worker.execute {
            try {
                val roots = context.contentResolver.persistedUriPermissions.filter { it.isReadPermission && valid(it.uri) }.map {
                    val doc = DocumentsContract.buildDocumentUriUsingTree(it.uri, DocumentsContract.getTreeDocumentId(it.uri))
                    GeneEntry(doc.toString(), SnpUsbAccess.scopeLabel(DocumentsContract.getTreeDocumentId(it.uri)), true)
                }
                val found = SnpSourceScanner(AndroidSnpTree(context)).scan(roots) { token != sourceRevision }
                main.post {
                    // 掃描途中 USB／授權狀態改變，丟棄舊掃描結果。
                    if (!attached || token != sourceRevision) result.error("CANCELLED", "Source changed", null)
                    else {
                        sources = found.associateBy { it.folder.uri }
                        if (selected != null && !sources.containsKey(selected)) invalidate("USB_REMOVED")
                        val pairs = sources.keys.filter { valid(Uri.parse(it)) && authorized(Uri.parse(it)) }.associateWith { sourceVolume(it) }
                        val remembered = volumes().mapNotNull { v ->
                            sourcePreferences.getString(v.uuid!!.lowercase(), null)?.let { v.uuid!! to it }
                        }.toMap()
                        // 恢復順序：有效目前選擇 → 同卷有效紀錄 → 唯一來源；多組無紀錄不猜。
                        selected = SnpUsbAccess.restore(selected, pairs, remembered)
                        emit(mapOf("status" to "sourcesSnapshot") + snapshot())
                        result.success(snapshot())
                    }
                }
            } catch(e: Exception) { main.post { result.error(failure(e), "Unable to discover USB source", null) } }
        }
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        // Flutter 命令入口：sources 搜尋、requestAccess 授權、selectSource 選來源、run／cancel。
        // pickPanel 是進階模式的參考 FASTA 選取，不是 combined 個人資料的匯入。
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
                    if (selected != id) invalidate("CANCELLED")
                    selected = id
                    sourcePreferences.edit().putString(sourceVolume(id).lowercase(), id).apply()
                    revision++; result.success(snapshot())
                }
                "run" -> run(call, result)
                "cancel" -> { val diagnostic = interrupted("cancelled"); gate.invalidate(); opening?.cancel(); emit(mapOf("status" to "cancelled") + diagnostic); result.success(null) }
                else -> result.notImplemented()
            }
        } catch(e: Exception) { result.error(failure(e), "SNP operation rejected", null) }
    }
    private fun requestAccess(id: String?, result: MethodChannel.Result) {
        // 定位指定 USB 根目錄，只要求可保存的讀取授權；仍需使用者在 Android picker 確認。
        // EXTRA_INITIAL_URI 只是預選位置，不代表已取得根目錄存取權。
        if (picker != null) throw SnpFailure("BUSY")
        val activity = binding?.activity ?: throw SnpFailure("CANCELLED")
        val volume = volumes().find { it.uuid.equals(id, true) } ?: throw SnpFailure("USB_REMOVED")
        picker = result; pickerVolume = volume.uuid; pickerSourceRevision = sourceRevision
        try {
            val intent = if (Build.VERSION.SDK_INT >= 29) volume.createOpenDocumentTreeIntent() else Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
            intent.flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
            val rootId = SnpUsbAccess.rootDocumentId(volume.uuid!!, volumes().mapNotNull { it.uuid }.toSet())
            intent.putExtra(DocumentsContract.EXTRA_INITIAL_URI,
                DocumentsContract.buildDocumentUri("com.android.externalstorage.documents", rootId))
            activity.startActivityForResult(intent, 61905)
        } catch(e: Exception) { picker = null; pickerVolume = null; throw e }
    }
    override fun onActivityResult(code: Int, resultCode: Int, data: Intent?): Boolean {
        // 61905：USB tree 授權；61906：進階參考 panel。取消選擇不啟動計算。
        if (code !in listOf(61905, 61906)) return false
        val result = picker ?: return true; val volume = pickerVolume; picker = null; pickerVolume = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { result.error("PERMISSION_DENIED", "Selection cancelled", null); return true }
        if (code == 61905) {
            try {
                if (pickerSourceRevision != sourceRevision) throw SnpFailure("USB_REMOVED")
                if (!valid(uri, volume)) throw SnpFailure("PERMISSION_DENIED")
                // 拒絕已失效的插入／授權回覆，保存唯讀 grant 後重新掃描實際可存取範圍。
                context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                invalidate("CANCELLED"); discover(result)
            } catch(e: Exception) { result.error(failure(e), "USB permission rejected", null) }
        } else worker.execute {
            // 只將使用者選取的參考 panel 讀成文字回傳，大小上限 2 MiB；不寫入手機檔案。
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
        // 開始前再次驗證來源／選擇／授權與整批查詢，不能以未授權來源或模擬資料替代。
        val id = call.argument<String>("sourceId") ?: throw SnpFailure("PERMISSION_DENIED")
        val source = sources[id] ?: throw SnpFailure("PERMISSION_DENIED")
        if (id != selected || !valid(Uri.parse(id)) || !authorized(Uri.parse(id))) throw SnpFailure("PERMISSION_DENIED")
        val raw = call.argument<List<*>>("queries") ?: throw SnpFailure("INVALID_QUERY")
        val queries = raw.map { item ->
            val m = item as? Map<*, *> ?: throw SnpFailure("INVALID_QUERY")
            SnpQuery(m["id"] as? String ?: "", m["sequence"] as? String ?: "", m["ref"] as? String ?: "", m["alt"] as? String ?: "")
        }
        if (!SnpContracts.validQueries(queries)) throw SnpFailure("INVALID_QUERY")
        // locus 模式按同位點分組：酒精 143 筆參考形成 77 個工作單位；舊 query 模式逐筆。
        val locusMode=SnpContracts.locusMode(call.argument<Any?>("mode"))
        val loci=if(locusMode) SnpContracts.loci(queries) else emptyList()
        val workCount=if(locusMode) loci.size else queries.size
        val debug = SnpDebug.enabled(call.argument<Any?>("debugEnabled"))
        // gate.start 拒絕同時執行第二個 job；debug 設定固定為本次工作的快照。
        val token = gate.start(); val jobId = token.toString()
        this.jobId = jobId; jobCompleted = 0; jobTotal = workCount; jobDebug = debug; jobStarted = 0L
        // 此回覆只代表「已啟動」，不是完成；Flutter 必須等 completed 事件才能匯出／送 LLM。
        result.success(mapOf("jobId" to jobId))
        emit(mapOf("jobId" to jobId, "status" to "running", "completed" to 0, "total" to workCount))
        worker.execute {
            // 計時邊界：從 worker 開始，不含排隊等待；涵蓋開檔、驗證、C／JNI 與結果處理。
            val began = if (debug) SystemClock.elapsedRealtimeNanos() else 0L
            jobStarted = began
            val signal = CancellationSignal(); opening = signal
            try {
                val resolver = context.contentResolver
                if (isCancelled(token)) throw SnpFailure("CANCELLED")
                if (!valid(Uri.parse(id)) || !authorized(Uri.parse(id))) throw SnpFailure("USB_REMOVED")
                val setupStart = if (debug) SystemClock.elapsedRealtimeNanos() else 0L
                // 直接開啟 USB 的唯讀描述符，沒有完整複製到手機或整檔載入記憶體。
                // Kotlin 的 use 在正常、取消及例外離開時關閉 FD；JNI 不應關閉呼叫端的 FD。
                resolver.openFileDescriptor(Uri.parse(source.idx.uri), "r", signal)?.use { idx ->
                    resolver.openFileDescriptor(Uri.parse(source.ids.uri), "r", signal)?.use { ids ->
                        // IDX 須為 512 MiB；IDs 須非空、4 bytes 對齊，且兩檔都支援隨機定位。
                        // 不可 seek 時報 NOT_SEEKABLE，不靠複製完整檔案繞過限制。
                        val idxSize = Os.fstat(idx.fileDescriptor).st_size; val idsSize = Os.fstat(ids.fileDescriptor).st_size
                        if (!SnpContracts.validSizes(idxSize, idsSize)) throw SnpFailure("INVALID_FORMAT")
                        try { Os.lseek(idx.fileDescriptor, 0, OsConstants.SEEK_CUR); Os.lseek(ids.fileDescriptor, 0, OsConstants.SEEK_CUR) }
                        catch (_: Exception) { throw SnpFailure("NOT_SEEKABLE") }
                        val setupMs = if (debug) (SystemClock.elapsedRealtimeNanos()-setupStart)/1e6 else 0.0
                        val rows = mutableListOf<Map<String, Any?>>()
                        for(index in 0 until workCount) {
                            // 逐工作單位呼叫 C；位點內更細的取消／I/O 檢查由 C 負責。
                            if (isCancelled(token)) throw SnpFailure("CANCELLED")
                            val metadata:Map<String,Any?>
                            val native:String
                            if(locusMode) {
                                val q=loci[index]
                                native=nativeComputeLocus(idx.fd,ids.fd,q.sequences.toTypedArray(),q.ref,token,debug)
                                metadata=mapOf("id" to q.id,"rsId" to q.rsId,"chromosome" to q.chromosome,
                                    "position" to q.position,"refAllele" to q.ref)
                            }else {
                                val q=queries[index]
                                native=nativeCompute(idx.fd,ids.fd,q.sequence,q.ref,q.alt,token,debug)
                                metadata=mapOf("id" to q.id,"refAllele" to q.ref,"altAllele" to q.alt)
                            }
                            // 原生錯誤使整批失敗；部分完成列只用於進度，不當成完整成功結果匯出。
                            val data=JSONObject(native)
                            if (data.has("errorCode")) throw SnpFailure(data.getString("errorCode"))
                            rows.add(jsonMap(data)+metadata+mapOf("sourceId" to id,"sourceLabel" to source.folder.name))
                            main.post { if (gate.current(token)) { jobCompleted = index + 1; emit(mapOf("jobId" to jobId, "status" to "running")) } }
                        }
                        // 全部工作完成才發布 results；gate 守衛防止取消後的晚到完成事件。
                        val event = mapOf("jobId" to jobId, "status" to "completed", "completed" to workCount, "total" to workCount,
                            "mode" to if(locusMode) "locus" else "query", "results" to rows)
                        val timing = if (debug) mapOf("debugTiming" to SnpDebug.batch(rows,setupMs,(SystemClock.elapsedRealtimeNanos()-began)/1e6)) else emptyMap()
                        // debug 才附分段時間與有界日誌；SnpDebug 排除序列、read ID、URI 等欄位。
                        // logcat 輸出不在上述結果建構的計時邊界內；關閉 debug 不輸出結果日誌。
                        if (debug && gate.current(token)) {
                            rows.forEach { SnpDebug.logRow(true,it)?.let { line -> Log.d("GeneEdgeSnp",line) } }
                            Log.d("GeneEdgeSnp",JSONObject(mapOf("jobId" to jobId,"status" to "completed") + timing).toString())
                        }
                        main.post { if (gate.current(token)) emit(event + timing) }
                    } ?: throw IOException()
                } ?: throw IOException()
            } catch(e: Throwable) {
                // 記憶體不足轉 RESOURCE_LIMIT，其他失敗轉固定錯誤碼；失效工作不再回報。
                val code = when(e) { is OutOfMemoryError -> "RESOURCE_LIMIT"; is Exception -> failure(e); else -> "IO_ERROR" }
                main.post { if (gate.current(token)) emit(mapOf("jobId" to jobId, "status" to "error", "errorCode" to code) + interrupted("error")) }
            } finally {
                // 不論成功或失敗都收尾；gate.finish(token) 不會結束較新的工作。
                opening = null
                main.post { gate.finish(token) }
            }
        }
    }
    // 將 native JSON 遞迴轉為 Flutter codec 支援的 Map／List／null，不改計算內容。
    private fun jsonMap(obj: JSONObject): Map<String, Any?> = obj.keys().asSequence().associateWith { key -> jsonValue(obj.get(key)) }
    private fun jsonValue(v: Any?): Any? = when(v) {
        JSONObject.NULL -> null
        is JSONObject -> jsonMap(v)
        is org.json.JSONArray -> (0 until v.length()).map { jsonValue(v.get(it)) }
        else -> v
    }
    private class AndroidSnpTree(private val context: Context) : GeneTree {
        // 搜尋只列出目錄 metadata；禁止從 scanner 開啟檔案內容，避免誤用為完整資料匯入。
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
