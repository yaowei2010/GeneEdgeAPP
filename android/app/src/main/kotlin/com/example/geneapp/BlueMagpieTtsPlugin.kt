package com.example.geneapp

import android.app.ActivityManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.media.MediaPlayer
import com.example.geneapp.bluemagpie.ModelManifestParser
import com.example.geneapp.bluemagpie.ModelValidationCode
import com.example.geneapp.bluemagpie.ModelValidator
import com.example.geneapp.bluemagpie.BlueMagpieNativeBindings
import com.example.geneapp.bluemagpie.androidBlueMagpieRuntimeProbe
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.io.File
import org.json.JSONObject

internal enum class BlueMagpieBackend(val wireName: String) {
    CPU("cpu"),
    VULKAN("vulkan");

    companion object {
        fun fromWire(value: Any?): BlueMagpieBackend? = entries.firstOrNull { it.wireName == value }
    }
}

/** Boundary implemented by the optional JNI runtime in later PoC stages. */
internal interface BlueMagpieNativeBridge {
    fun probe(): Map<String, Any?>
    fun validateModels(): Map<String, Any?>
    fun initialize(backend: BlueMagpieBackend): Map<String, Any?>
    fun synthesize(requestId: String, text: String): Map<String, Any?>
    fun cancel(requestId: String)
    fun cancelAll()
    fun release()
}

internal interface BlueMagpieAudioPlayer {
    fun play(wavToken: String)
    fun release()
}

internal fun interface MainThreadDispatcher {
    fun dispatch(action: () -> Unit)
}

internal class BlueMagpieBridgeException(
    val stableCode: String,
    cause: Throwable? = null,
) : RuntimeException(cause)

/**
 * Flutter bridge for the isolated BlueMagpie Android PoC.
 *
 * Potentially expensive work is serialized on one worker. JNI is injected so
 * unit tests never need model files and a build without the runtime fails closed.
 */
internal class BlueMagpieTtsPlugin(
    injectedNativeBridge: BlueMagpieNativeBridge? = null,
    private val worker: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "geneedge-bluemagpie-worker")
    },
    private val mainThread: MainThreadDispatcher = MainThreadDispatcher { action ->
        Handler(Looper.getMainLooper()).post(action)
    },
    injectedAudioPlayer: BlueMagpieAudioPlayer? = null,
) : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val lifecycleLock = Any()
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var detached = false
    private var initializeInFlight = false
    private var initializedResult: Map<String, Any?>? = null
    private val initializeResults = mutableListOf<MethodChannel.Result>()
    private var nativeBridge: BlueMagpieNativeBridge? = injectedNativeBridge
    private var audioPlayer: BlueMagpieAudioPlayer? = injectedAudioPlayer

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        synchronized(lifecycleLock) {
            check(methodChannel == null && !detached) { "BlueMagpie plugin is already attached or released." }
            methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL).also {
                it.setMethodCallHandler(this)
            }
            eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL).also {
                it.setStreamHandler(this)
            }
            if (audioPlayer == null) {
                audioPlayer = PrivateCacheAudioPlayer(binding.applicationContext.cacheDir)
            }
            if (nativeBridge == null) {
                nativeBridge = AndroidScaffoldBlueMagpieBridge(binding.applicationContext)
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        synchronized(lifecycleLock) {
            methodChannel?.setMethodCallHandler(null)
            eventChannel?.setStreamHandler(null)
            methodChannel = null
            eventChannel = null
        }
        detach()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        synchronized(lifecycleLock) {
            if (detached) {
                mainThread.dispatch(events::endOfStream)
            } else {
                eventSink = events
            }
        }
    }

    override fun onCancel(arguments: Any?) {
        synchronized(lifecycleLock) { eventSink = null }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "probe" -> runOnWorker(result) { bridge().probe() }
            "validateModels" -> runOnWorker(result) { bridge().validateModels() }
            "initialize" -> initialize(call, result)
            "synthesize" -> synthesize(call, result)
            "play" -> play(call, result)
            "cancel" -> cancel(call, result)
            "release" -> release(result)
            else -> result.notImplemented()
        }
    }

    private fun initialize(call: MethodCall, result: MethodChannel.Result) {
        val backend = BlueMagpieBackend.fromWire(call.argument<Any?>("backend"))
        if (backend == null) {
            result.safeError("backend_unavailable")
            return
        }

        synchronized(lifecycleLock) {
            if (detached) {
                result.safeError("runtime_missing")
                return
            }
            initializedResult?.let { ready ->
                mainThread.dispatch { result.success(ready) }
                return
            }
            initializeResults += result
            if (initializeInFlight) return
            initializeInFlight = true
        }

        val accepted = execute {
            try {
                val ready = bridge().initialize(backend)
                completeInitialize(ready, null)
            } catch (error: Throwable) {
                completeInitialize(null, stableCode(error))
            }
        }
        if (!accepted) completeInitialize(null, "cancelled")
    }

    private fun completeInitialize(value: Map<String, Any?>?, errorCode: String?) {
        val callbacks = synchronized(lifecycleLock) {
            if (value != null && !detached) initializedResult = value
            initializeInFlight = false
            initializeResults.toList().also { initializeResults.clear() }
        }
        mainThread.dispatch {
            callbacks.forEach { result ->
                if (value != null) result.success(value) else result.safeError(errorCode ?: "internal_error")
            }
        }
    }

    private fun synthesize(call: MethodCall, result: MethodChannel.Result) {
        val requestId = call.argument<String>("requestId")
        val text = call.argument<String>("text")
        if (requestId == null || !REQUEST_ID.matches(requestId) || text.isNullOrBlank() ||
            text.codePointCount(0, text.length) > MAX_TEXT_SCALARS
        ) {
            result.safeError("invalid_text")
            return
        }
        runOnWorker(result) {
            emitEvent(requestId, "synthesizing", 0.0, null)
            bridge().synthesize(requestId, text).also {
                emitEvent(requestId, "ready", 1.0, null)
            }
        }
    }

    private fun cancel(call: MethodCall, result: MethodChannel.Result) {
        val requestId = call.argument<String>("requestId")
        if (requestId == null || !REQUEST_ID.matches(requestId)) {
            result.safeError("invalid_text")
            return
        }
        // Cancellation is a thread-safe signal, not model work. Calling it
        // directly lets it interrupt a long synthesis queued on the sole worker.
        try {
            bridge().cancel(requestId)
            result.success(null)
        } catch (error: Throwable) {
            result.safeError(stableCode(error))
        }
    }

    private fun play(call: MethodCall, result: MethodChannel.Result) {
        val wavToken = call.argument<String>("wavToken")
        if (wavToken == null || !WAV_TOKEN.matches(wavToken)) {
            result.safeError("io_failed")
            return
        }
        val player = synchronized(lifecycleLock) { audioPlayer }
        if (player == null) {
            result.safeError("io_failed")
            return
        }
        runOnWorker(result) {
            player.play(wavToken)
            null
        }
    }

    private fun release(result: MethodChannel.Result) {
        try {
            bridge().cancelAll()
        } catch (_: Throwable) {
            // Release remains idempotent and continues to worker cleanup.
        }
        runOnWorker(result) {
            bridge().release()
            audioPlayer?.release()
            synchronized(lifecycleLock) { initializedResult = null }
            null
        }
    }

    private fun runOnWorker(result: MethodChannel.Result, operation: () -> Any?) {
        synchronized(lifecycleLock) {
            if (detached) {
                result.safeError("runtime_missing")
                return
            }
        }
        val accepted = execute {
            try {
                val value = operation()
                mainThread.dispatch { result.success(value) }
            } catch (error: Throwable) {
                val code = stableCode(error)
                mainThread.dispatch { result.safeError(code) }
            }
        }
        if (!accepted) mainThread.dispatch { result.safeError("cancelled") }
    }

    private fun execute(action: () -> Unit): Boolean =
        try {
            worker.execute(action)
            true
        } catch (_: RuntimeException) {
            false
        }

    private fun emitEvent(requestId: String, state: String, progress: Double, errorCode: String?) {
        val event = mapOf(
            "requestId" to requestId,
            "state" to state,
            "progress" to progress,
            "timestampMs" to System.currentTimeMillis(),
            "errorCode" to errorCode,
        )
        mainThread.dispatch {
            synchronized(lifecycleLock) { eventSink }?.success(event)
        }
    }

    private fun detach() {
        val pendingInitialize = synchronized(lifecycleLock) {
            if (detached) return
            detached = true
            initializeInFlight = false
            initializeResults.toList().also { initializeResults.clear() }
        }
        try {
            nativeBridge?.cancelAll()
        } catch (_: Throwable) {
            // A broken optional runtime must never prevent Flutter teardown.
        }
        if (pendingInitialize.isNotEmpty()) {
            mainThread.dispatch {
                pendingInitialize.forEach { it.safeError("cancelled") }
            }
        }
        execute {
            try {
                nativeBridge?.release()
                audioPlayer?.release()
            } finally {
                mainThread.dispatch {
                    synchronized(lifecycleLock) {
                        eventSink?.endOfStream()
                        eventSink = null
                    }
                }
            }
        }
        worker.shutdown()
    }

    internal fun detachForTest() = detach()

    private fun bridge(): BlueMagpieNativeBridge =
        synchronized(lifecycleLock) { nativeBridge }
            ?: throw BlueMagpieBridgeException("runtime_missing")

    private fun stableCode(error: Throwable): String {
        val requested = (error as? BlueMagpieBridgeException)?.stableCode
        return if (requested in STABLE_ERROR_CODES) requested!! else "internal_error"
    }

    private fun MethodChannel.Result.safeError(code: String) {
        val safeCode = if (code in STABLE_ERROR_CODES) code else "internal_error"
        error(safeCode, SAFE_MESSAGES.getValue(safeCode), null)
    }

    companion object {
        const val METHOD_CHANNEL = "geneedge/bluemagpie_tts"
        const val EVENT_CHANNEL = "geneedge/bluemagpie_tts/events"
        private const val MAX_TEXT_SCALARS = 200
        private val REQUEST_ID = Regex("[A-Za-z0-9._-]{1,128}")
        private val WAV_TOKEN = Regex("cache:[A-Za-z0-9._-]{1,128}\\.wav")
        private val STABLE_ERROR_CODES = setOf(
            "runtime_missing", "unsupported_abi", "model_missing", "model_path_rejected",
            "model_size_mismatch", "model_checksum_mismatch", "insufficient_space",
            "insufficient_memory", "backend_unavailable", "invalid_text", "decode_failed",
            "cancelled", "io_failed", "internal_error",
        )
        private val SAFE_MESSAGES = STABLE_ERROR_CODES.associateWith { code ->
            when (code) {
                "runtime_missing" -> "BlueMagpie runtime is not available in this build."
                "invalid_text" -> "Provide a valid request id and 1 to 200 text characters."
                "cancelled" -> "BlueMagpie operation was cancelled."
                else -> "BlueMagpie operation failed ($code)."
            }
        }
    }
}

private class PrivateCacheAudioPlayer(private val cacheDirectory: File) : BlueMagpieAudioPlayer {
    private var mediaPlayer: MediaPlayer? = null

    @Synchronized
    override fun play(wavToken: String) {
        val fileName = wavToken.removePrefix("cache:")
        val canonicalCache = cacheDirectory.canonicalFile
        val wav = File(canonicalCache, fileName).canonicalFile
        if (wav.parentFile != canonicalCache || !wav.isFile || !wav.canRead()) {
            throw BlueMagpieBridgeException("io_failed")
        }
        mediaPlayer?.release()
        mediaPlayer = null
        val next = MediaPlayer()
        try {
            next.setDataSource(wav.path)
            next.prepare()
            next.start()
            mediaPlayer = next
        } catch (error: Throwable) {
            next.release()
            throw BlueMagpieBridgeException("io_failed", error)
        }
    }

    @Synchronized
    override fun release() {
        mediaPlayer?.release()
        mediaPlayer = null
    }
}

private class AndroidScaffoldBlueMagpieBridge(private val context: Context) : BlueMagpieNativeBridge {
    private val modelDirectory: File
        get() = File(context.getExternalFilesDir(null), "models/bluemagpie")

    private fun manifest() = context.assets.open("bluemagpie-models.json").bufferedReader().use {
        ModelManifestParser.parse(it.readText())
    }

    private fun validation() = manifest().let { manifest ->
        manifest to ModelValidator(manifest, freeBytesProvider = { modelDirectory.usableSpace })
            .validate(modelDirectory)
    }

    override fun probe(): Map<String, Any?> = androidBlueMagpieRuntimeProbe.probe(
        deviceMemoryClassMb =
            (context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).memoryClass,
    )

    override fun validateModels(): Map<String, Any?> {
        val (manifest, validation) = validation()
        return mapOf(
            "state" to if (validation.isReady) "ready" else "unavailable",
            "freeSpaceBytes" to (validation.freeBytes ?: 0L),
            "requiredSpaceBytes" to (validation.minimumFreeBytes ?: manifest.minimumFreeBytes),
            "models" to manifest.models.map { descriptor ->
                val item = validation.models.firstOrNull { it.modelId == descriptor.id }
                val code = item?.code ?: ModelValidationCode.MODEL_MISSING
                mapOf(
                    "id" to descriptor.id,
                    "fileName" to descriptor.filename,
                    "state" to if (code == ModelValidationCode.READY) "ready" else "unavailable",
                    "sizeBytes" to descriptor.byteSize,
                    "errorCode" to code.wireValue.takeUnless { it == "ready" },
                )
            },
        )
    }

    override fun initialize(backend: BlueMagpieBackend): Map<String, Any?> {
        if (probe()["available"] != true) throw BlueMagpieBridgeException("runtime_missing")
        val (manifest, validation) = validation()
        if (!validation.isReady) throw BlueMagpieBridgeException(validation.code.wireValue)
        val models = manifest.models.associateBy { it.id }
        val backbone = File(modelDirectory, models.getValue("barbet_q4_k_m").filename)
        val codec = File(modelDirectory, models.getValue("audio_vae_f16").filename)
        val result = nativeResult(
            BlueMagpieNativeBindings.nativeInitializeJson(
                backbone.canonicalPath,
                codec.canonicalPath,
                backend.wireName,
            ),
        )
        return mapOf(
            "state" to result.getString("state"),
            "backend" to result.getString("backend"),
            "elapsedMs" to result.getLong("elapsedMs"),
            "rssBeforeBytes" to result.getLong("rssBeforeBytes"),
            "rssAfterBytes" to result.getLong("rssAfterBytes"),
        )
    }

    override fun synthesize(requestId: String, text: String): Map<String, Any?> {
        val partial = File(context.cacheDir, "bluemagpie-$requestId.partial.wav")
        val completed = File(context.cacheDir, "bluemagpie-$requestId.wav")
        partial.delete()
        completed.delete()
        try {
            val result = nativeResult(
                BlueMagpieNativeBindings.nativeSynthesizeJson(requestId, text, partial.canonicalPath),
            )
            if (!partial.renameTo(completed)) throw BlueMagpieBridgeException("io_failed")
            return mapOf(
                "wavToken" to "cache:${completed.name}",
                "sampleRate" to result.getInt("sampleRate"),
                "samples" to result.getLong("samples"),
                "durationMs" to result.getLong("durationMs"),
                "firstAudioMs" to result.getLong("firstAudioMs"),
                "elapsedMs" to result.getLong("elapsedMs"),
                "peakRssBytes" to result.getLong("peakRssBytes"),
            )
        } catch (error: Throwable) {
            partial.delete()
            throw error
        }
    }

    override fun cancel(requestId: String) {
        if (BlueMagpieNativeBindings.load()) {
            BlueMagpieNativeBindings.nativeCancel(requestId)
        }
        File(context.cacheDir, "bluemagpie-$requestId.partial.wav").delete()
    }

    override fun cancelAll() {
        if (BlueMagpieNativeBindings.load()) BlueMagpieNativeBindings.nativeCancel("")
        context.cacheDir.listFiles { file ->
            file.name.startsWith("bluemagpie-") && file.name.endsWith(".partial.wav")
        }?.forEach(File::delete)
    }

    override fun release() {
        if (BlueMagpieNativeBindings.load()) BlueMagpieNativeBindings.nativeRelease()
    }

    private fun nativeResult(encoded: String): JSONObject {
        val result = JSONObject(encoded)
        if (!result.optBoolean("ok", false)) {
            throw BlueMagpieBridgeException(result.optString("errorCode", "internal_error"))
        }
        return result
    }
}
