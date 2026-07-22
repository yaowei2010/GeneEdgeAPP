package com.example.geneapp.bluemagpie

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BlueMagpieRuntimeProbeTest {
    @Test
    fun `runtime library is loaded lazily only when probe is requested`() {
        var loads = 0
        val probe = BlueMagpieRuntimeProbe(
            loadLibrary = { loads += 1; true },
            nativeRevision = { PINNED_BLUEMAGPIE_RUNTIME_REVISION },
            abiProvider = { "arm64-v8a" },
        )

        assertEquals(0, loads)
        val result = probe.probe(deviceMemoryClassMb = 8192)

        assertEquals(1, loads)
        assertEquals(true, result["available"])
        assertEquals(PINNED_BLUEMAGPIE_RUNTIME_REVISION, result["runtimeRevision"])
        assertEquals("arm64-v8a", result["abi"])
        assertEquals(8192, result["deviceMemoryClassMb"])
    }

    @Test
    fun `missing library fails closed without calling native binding`() {
        var nativeCalls = 0
        val probe = BlueMagpieRuntimeProbe(
            loadLibrary = { false },
            nativeRevision = { nativeCalls += 1; "unexpected" },
            abiProvider = { "arm64-v8a" },
        )

        val result = probe.probe(deviceMemoryClassMb = 4096)

        assertFalse(result["available"] as Boolean)
        assertEquals("runtime_missing", result["errorCode"])
        assertEquals(0, nativeCalls)
    }

    @Test
    fun `wrong ABI or revision is rejected`() {
        val wrongAbi = BlueMagpieRuntimeProbe(
            loadLibrary = { true },
            nativeRevision = { PINNED_BLUEMAGPIE_RUNTIME_REVISION },
            abiProvider = { "x86_64" },
        ).probe(4096)
        assertEquals("unsupported_abi", wrongAbi["errorCode"])

        val wrongRevision = BlueMagpieRuntimeProbe(
            loadLibrary = { true },
            nativeRevision = { "0".repeat(40) },
            abiProvider = { "arm64-v8a" },
        ).probe(4096)
        assertEquals("runtime_missing", wrongRevision["errorCode"])
        assertTrue(wrongRevision["runtimeRevision"] == PINNED_BLUEMAGPIE_RUNTIME_REVISION)
    }
}
