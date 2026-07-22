package com.example.geneapp.bluemagpie

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class ModelValidatorTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private val manifest =
        ModelManifest(
            repository = "hans00/BlueMagpie-TTS-GGUF",
            revision = "37ab65a2836e6cf5780f2e5566ae77ca5967982f",
            conversionLicense = "Apache-2.0",
            conversionLicenseUrl = "https://example.test/conversion-license",
            upstreamRepository = "OpenFormosa/BlueMagpie-TTS",
            upstreamRevision = "aaf1a0878e37875382bb0e5c8a3a2ba43be67297",
            upstreamLicense = "other",
            upstreamLicenseUrl = "https://example.test/upstream-license",
            licenseReviewRequired = true,
            architectureProvenanceUrl = "https://github.com/OpenBMB/VoxCPM",
            minimumFreeBytes = 536_870_912,
            models =
                listOf(
                    ModelDescriptor(
                        id = "barbet_q4_k_m",
                        filename = "BlueMagpie-Barbet-1B-q4_k_m.gguf",
                        byteSize = 693_008_576,
                        sha256 = "c8e66535e9ee3b114a9be05ac404cb9585910865718095a3914c2b51c4d5462f",
                        provenanceUrl = "https://huggingface.co/OpenFormosa/BlueMagpie-TTS",
                    ),
                    ModelDescriptor(
                        id = "audio_vae_f16",
                        filename = "BlueMagpie-AudioVAE.gguf",
                        byteSize = 1_884_843_552,
                        sha256 = "de3acf2f77842aa0cd7a958bf9ce5c549b94db0c7930776f320ad6152e1e86f6",
                        provenanceUrl = "https://huggingface.co/OpenFormosa/BlueMagpie-TTS",
                    ),
                ),
        )

    @Test
    fun `valid model pair is ready`() {
        val privateDirectory = temporaryFolder.newFolder("models", "bluemagpie")
        val inspector = FakeInspector.validFor(manifest)

        val result = validator(inspector).validate(privateDirectory, expectedPaths(privateDirectory))

        assertEquals(ModelValidationCode.READY, result.code)
        assertTrue(result.isReady)
        assertTrue(result.models.all { it.code == ModelValidationCode.READY })
    }

    @Test
    fun `missing Barbet model fails closed`() {
        val privateDirectory = temporaryFolder.newFolder("models", "bluemagpie")
        val inspector = FakeInspector.validFor(manifest).withMissing("barbet_q4_k_m")

        val result = validator(inspector).validate(privateDirectory, expectedPaths(privateDirectory))

        assertEquals(ModelValidationCode.MODEL_MISSING, result.code)
        assertFalse(result.isReady)
        assertEquals("barbet_q4_k_m", result.failedModelId)
    }

    @Test
    fun `AudioVAE checksum mismatch fails closed`() {
        val privateDirectory = temporaryFolder.newFolder("models", "bluemagpie")
        val inspector = FakeInspector.validFor(manifest).withSha("audio_vae_f16", "0".repeat(64))

        val result = validator(inspector).validate(privateDirectory, expectedPaths(privateDirectory))

        assertEquals(ModelValidationCode.MODEL_CHECKSUM_MISMATCH, result.code)
        assertFalse(result.isReady)
        assertEquals("audio_vae_f16", result.failedModelId)
    }

    @Test
    fun `public external path is rejected before file inspection`() {
        val privateDirectory = temporaryFolder.newFolder("models", "bluemagpie")
        val paths = expectedPaths(privateDirectory).toMutableMap()
        paths["barbet_q4_k_m"] = File("/sdcard/Download/BlueMagpie-Barbet-1B-q4_k_m.gguf")
        val inspector = FakeInspector.validFor(manifest)

        val result = validator(inspector).validate(privateDirectory, paths)

        assertEquals(ModelValidationCode.MODEL_PATH_REJECTED, result.code)
        assertFalse(result.isReady)
        assertEquals(0, inspector.probeCount)
        assertFalse(result.safeMessage.contains("/sdcard"))
    }

    @Test
    fun `wrong byte size is reported without exposing path`() {
        val privateDirectory = temporaryFolder.newFolder("models", "bluemagpie")
        val inspector = FakeInspector.validFor(manifest).withSize("barbet_q4_k_m", 1)

        val result = validator(inspector).validate(privateDirectory, expectedPaths(privateDirectory))

        assertEquals(ModelValidationCode.MODEL_SIZE_MISMATCH, result.code)
        assertFalse(result.safeMessage.contains(privateDirectory.absolutePath))
    }

    @Test
    fun `insufficient free space prevents readiness`() {
        val privateDirectory = temporaryFolder.newFolder("models", "bluemagpie")

        val result =
            ModelValidator(manifest, FakeInspector.validFor(manifest)) { manifest.minimumFreeBytes - 1 }
                .validate(privateDirectory, expectedPaths(privateDirectory))

        assertEquals(ModelValidationCode.INSUFFICIENT_SPACE, result.code)
        assertFalse(result.isReady)
    }

    @Test
    fun `free space inspection failure is isolated`() {
        val privateDirectory = temporaryFolder.newFolder("models", "bluemagpie")

        val result =
            ModelValidator(manifest, FakeInspector.validFor(manifest)) {
                throw SecurityException("private path must not cross the channel")
            }.validate(privateDirectory, expectedPaths(privateDirectory))

        assertEquals(ModelValidationCode.IO_FAILED, result.code)
        assertFalse(result.safeMessage.contains(privateDirectory.absolutePath))
    }

    private fun validator(inspector: FakeInspector) =
        ModelValidator(manifest, inspector) { manifest.minimumFreeBytes }

    private fun expectedPaths(privateDirectory: File): Map<String, File> =
        manifest.models.associate { it.id to File(privateDirectory, it.filename) }
}

private class FakeInspector(
    private val manifest: ModelManifest,
    private val overrides: MutableMap<String, FileProbe>,
) : ModelFileInspector {
    var probeCount: Int = 0
        private set

    override fun probe(file: File, descriptor: ModelDescriptor): FileProbe {
        probeCount += 1
        return overrides.getValue(descriptor.id)
    }

    fun withMissing(id: String) = apply {
        overrides[id] = overrides.getValue(id).copy(exists = false, readable = false)
    }

    fun withSha(id: String, sha256: String) = apply {
        overrides[id] = overrides.getValue(id).copy(sha256 = sha256)
    }

    fun withSize(id: String, byteSize: Long) = apply {
        overrides[id] = overrides.getValue(id).copy(byteSize = byteSize)
    }

    companion object {
        fun validFor(manifest: ModelManifest): FakeInspector =
            FakeInspector(
                manifest,
                manifest.models.associate { descriptor ->
                    descriptor.id to
                        FileProbe(
                            exists = true,
                            readable = true,
                            byteSize = descriptor.byteSize,
                            sha256 = descriptor.sha256,
                        )
                }.toMutableMap(),
            )
    }
}
