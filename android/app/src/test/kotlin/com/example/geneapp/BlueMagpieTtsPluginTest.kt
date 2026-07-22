package com.example.geneapp

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayDeque
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BlueMagpieTtsPluginTest {
    private val workers = mutableListOf<java.util.concurrent.ExecutorService>()

    @After
    fun tearDown() {
        workers.forEach { it.shutdownNow() }
    }

    @Test
    fun `model work runs on worker and callback is dispatched to main`() {
        val native = FakeNativeBridge()
        val main = QueuedMainDispatcher()
        val worker = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "bluemagpie-test-worker")
        }.also(workers::add)
        val plugin = BlueMagpieTtsPlugin(native, worker, main)
        val result = RecordingResult()

        plugin.onMethodCall(MethodCall("probe", null), result)

        assertTrue(native.probeCalled.await(2, TimeUnit.SECONDS))
        assertEquals("bluemagpie-test-worker", native.callThreadName)
        assertFalse(result.completed)
        main.awaitSize(1)
        main.drain()
        assertTrue(result.completed)
        assertEquals(true, (result.value as Map<*, *>)["available"])
    }

    @Test
    fun `duplicate initialize shares one native allocation and both callbacks`() {
        val native = FakeNativeBridge(blockInitialize = true)
        val main = QueuedMainDispatcher()
        val worker = Executors.newSingleThreadExecutor().also(workers::add)
        val plugin = BlueMagpieTtsPlugin(native, worker, main)
        val first = RecordingResult()
        val duplicate = RecordingResult()
        val call = MethodCall("initialize", mapOf("backend" to "cpu"))

        plugin.onMethodCall(call, first)
        assertTrue(native.initializeStarted.await(2, TimeUnit.SECONDS))
        plugin.onMethodCall(call, duplicate)
        native.allowInitialize.countDown()
        assertTrue(native.initializeFinished.await(2, TimeUnit.SECONDS))
        main.awaitSize(1)
        main.drain()

        assertEquals(1, native.initializeCalls.get())
        assertEquals(first.value, duplicate.value)
    }

    @Test
    fun `detach cancels active work releases native context and closes event sink`() {
        val native = FakeNativeBridge()
        val main = QueuedMainDispatcher()
        val worker = Executors.newSingleThreadExecutor().also(workers::add)
        val plugin = BlueMagpieTtsPlugin(native, worker, main)
        val events = RecordingEventSink()
        plugin.onListen(null, events)

        plugin.detachForTest()

        assertTrue(native.released.await(2, TimeUnit.SECONDS))
        main.awaitSize(1)
        main.drain()
        assertEquals(1, native.cancelAllCalls.get())
        assertEquals(1, native.releaseCalls.get())
        assertTrue(events.ended)
    }

    @Test
    fun `unknown method is rejected without touching native bridge`() {
        val native = FakeNativeBridge()
        val main = QueuedMainDispatcher()
        val worker = Executors.newSingleThreadExecutor().also(workers::add)
        val plugin = BlueMagpieTtsPlugin(native, worker, main)
        val result = RecordingResult()

        plugin.onMethodCall(MethodCall("dangerousUnknownCall", null), result)

        assertTrue(result.notImplemented)
        assertNull(native.callThreadName)
    }

    @Test
    fun `play accepts opaque cache token and never passes a filesystem path`() {
        val native = FakeNativeBridge()
        val audio = FakeAudioPlayer()
        val main = QueuedMainDispatcher()
        val worker = Executors.newSingleThreadExecutor().also(workers::add)
        val plugin = BlueMagpieTtsPlugin(native, worker, main, audio)
        val result = RecordingResult()

        plugin.onMethodCall(
            MethodCall("play", mapOf("wavToken" to "cache:smoke-1.wav")),
            result,
        )

        assertTrue(audio.played.await(2, TimeUnit.SECONDS))
        main.awaitSize(1)
        main.drain()
        assertEquals("cache:smoke-1.wav", audio.lastToken)
        assertTrue(result.completed)
    }

    @Test
    fun `play rejects raw and traversal paths before audio player`() {
        val native = FakeNativeBridge()
        val audio = FakeAudioPlayer()
        val main = QueuedMainDispatcher()
        val worker = Executors.newSingleThreadExecutor().also(workers::add)
        val plugin = BlueMagpieTtsPlugin(native, worker, main, audio)

        listOf("/private/cache/output.wav", "cache:../secret.wav", "file:///tmp/output.wav").forEach { token ->
            val result = RecordingResult()
            plugin.onMethodCall(MethodCall("play", mapOf("wavToken" to token)), result)
            assertEquals("io_failed", (result.value as Map<*, *>)["code"])
        }
        assertEquals(1L, audio.played.count)
    }

    @Test
    fun `synthesis emits structured progress events through main dispatcher`() {
        val native = FakeNativeBridge()
        val events = RecordingEventSink()
        val main = QueuedMainDispatcher()
        val worker = Executors.newSingleThreadExecutor().also(workers::add)
        val plugin = BlueMagpieTtsPlugin(native, worker, main)
        val result = RecordingResult()
        plugin.onListen(null, events)

        plugin.onMethodCall(
            MethodCall(
                "synthesize",
                mapOf("requestId" to "smoke-1", "text" to "今天天氣真好。"),
            ),
            result,
        )

        main.awaitSize(3)
        main.drain()
        assertEquals(listOf("synthesizing", "ready"), events.values.map { it["state"] })
        assertTrue(events.values.all { it.keys.containsAll(setOf("requestId", "progress", "timestampMs", "errorCode")) })
        assertTrue(result.completed)
    }
}

private class FakeNativeBridge(
    private val blockInitialize: Boolean = false,
) : BlueMagpieNativeBridge {
    val probeCalled = CountDownLatch(1)
    val initializeStarted = CountDownLatch(1)
    val initializeFinished = CountDownLatch(1)
    val allowInitialize = CountDownLatch(1)
    val released = CountDownLatch(1)
    val initializeCalls = AtomicInteger()
    val cancelAllCalls = AtomicInteger()
    val releaseCalls = AtomicInteger()
    @Volatile var callThreadName: String? = null

    override fun probe(): Map<String, Any?> {
        callThreadName = Thread.currentThread().name
        probeCalled.countDown()
        return mapOf("available" to true)
    }

    override fun validateModels(): Map<String, Any?> = emptyMap()

    override fun initialize(backend: BlueMagpieBackend): Map<String, Any?> {
        initializeCalls.incrementAndGet()
        initializeStarted.countDown()
        if (blockInitialize) allowInitialize.await(2, TimeUnit.SECONDS)
        return mapOf("state" to "ready", "backend" to backend.wireName).also {
            initializeFinished.countDown()
        }
    }

    override fun synthesize(requestId: String, text: String): Map<String, Any?> = emptyMap()

    override fun cancel(requestId: String) = Unit

    override fun cancelAll() {
        cancelAllCalls.incrementAndGet()
    }

    override fun release() {
        releaseCalls.incrementAndGet()
        released.countDown()
    }
}

private class QueuedMainDispatcher : MainThreadDispatcher {
    private val tasks = ArrayDeque<() -> Unit>()

    @Synchronized
    override fun dispatch(action: () -> Unit) {
        tasks.addLast(action)
        (this as java.lang.Object).notifyAll()
    }

    @Synchronized
    fun awaitSize(expected: Int) {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(2)
        while (tasks.size < expected && System.nanoTime() < deadline) {
            (this as java.lang.Object).wait(10)
        }
        assertTrue("Expected $expected main-thread tasks, got ${tasks.size}", tasks.size >= expected)
    }

    fun drain() {
        while (true) {
            val task = synchronized(this) {
                if (tasks.isEmpty()) null else tasks.removeFirst()
            } ?: return
            task()
        }
    }
}

private class FakeAudioPlayer : BlueMagpieAudioPlayer {
    val played = CountDownLatch(1)
    var lastToken: String? = null

    override fun play(wavToken: String) {
        lastToken = wavToken
        played.countDown()
    }

    override fun release() = Unit
}

private class RecordingResult : MethodChannel.Result {
    var completed = false
    var value: Any? = null
    var notImplemented = false

    override fun success(result: Any?) {
        completed = true
        value = result
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        completed = true
        value = mapOf("code" to errorCode, "message" to errorMessage, "details" to errorDetails)
    }

    override fun notImplemented() {
        completed = true
        notImplemented = true
    }
}

private class RecordingEventSink : io.flutter.plugin.common.EventChannel.EventSink {
    var ended = false
    val values = mutableListOf<Map<*, *>>()
    override fun success(event: Any?) {
        values += event as Map<*, *>
    }
    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit
    override fun endOfStream() {
        ended = true
    }
}
