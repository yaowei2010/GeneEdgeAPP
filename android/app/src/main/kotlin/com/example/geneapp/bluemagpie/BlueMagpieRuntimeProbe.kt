package com.example.geneapp.bluemagpie

import android.os.Build

internal const val PINNED_BLUEMAGPIE_RUNTIME_REVISION =
    "7d5cf82cf33883bc80ec845905f5d85c5565d132"

internal class BlueMagpieRuntimeProbe(
    private val loadLibrary: () -> Boolean,
    private val nativeRevision: () -> String,
    private val abiProvider: () -> String,
) {
    fun probe(deviceMemoryClassMb: Int): Map<String, Any?> {
        val abi = abiProvider()
        if (abi != "arm64-v8a") {
            return unavailable("unsupported_abi", abi, deviceMemoryClassMb)
        }
        if (!loadLibrary()) {
            return unavailable("runtime_missing", abi, deviceMemoryClassMb)
        }
        val actualRevision = try {
            nativeRevision()
        } catch (_: LinkageError) {
            return unavailable("runtime_missing", abi, deviceMemoryClassMb)
        }
        if (actualRevision != PINNED_BLUEMAGPIE_RUNTIME_REVISION) {
            return unavailable("runtime_missing", abi, deviceMemoryClassMb)
        }
        return mapOf(
            "available" to true,
            "runtimeRevision" to actualRevision,
            "abi" to abi,
            "backend" to "cpu",
            "deviceMemoryClassMb" to deviceMemoryClassMb,
            "errorCode" to null,
        )
    }

    private fun unavailable(code: String, abi: String, memoryClassMb: Int) = mapOf(
        "available" to false,
        "runtimeRevision" to PINNED_BLUEMAGPIE_RUNTIME_REVISION,
        "abi" to abi,
        "backend" to null,
        "deviceMemoryClassMb" to memoryClassMb,
        "errorCode" to code,
    )
}

internal object BlueMagpieNativeBindings {
    private var loadAttempted = false
    private var loaded = false

    @Synchronized
    fun load(): Boolean {
        if (loadAttempted) return loaded
        loadAttempted = true
        loaded = try {
            System.loadLibrary("geneedge_bluemagpie")
            true
        } catch (_: LinkageError) {
            false
        }
        return loaded
    }

    external fun nativeRuntimeRevision(): String
    external fun nativeInitializeJson(backbonePath: String, codecPath: String, backend: String): String
    external fun nativeSynthesizeJson(requestId: String, text: String, outputPath: String): String
    external fun nativeCancel(requestId: String)
    external fun nativeRelease()
}

internal val androidBlueMagpieRuntimeProbe = BlueMagpieRuntimeProbe(
    loadLibrary = BlueMagpieNativeBindings::load,
    nativeRevision = BlueMagpieNativeBindings::nativeRuntimeRevision,
    abiProvider = { Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown" },
)
