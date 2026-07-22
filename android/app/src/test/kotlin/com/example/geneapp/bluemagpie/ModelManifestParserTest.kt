package com.example.geneapp.bluemagpie

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ModelManifestParserTest {
    @Test
    fun `bundled manifest pins immutable revision and verified blobs`() {
        val manifestFile = File("src/main/assets/bluemagpie-models.json")

        val manifest = ModelManifestParser.parse(manifestFile.readText())

        assertEquals("37ab65a2836e6cf5780f2e5566ae77ca5967982f", manifest.revision)
        assertEquals("Apache-2.0", manifest.conversionLicense)
        assertEquals("other", manifest.upstreamLicense)
        assertEquals("aaf1a0878e37875382bb0e5c8a3a2ba43be67297", manifest.upstreamRevision)
        assertTrue(manifest.licenseReviewRequired)
        assertEquals(2, manifest.models.size)
        assertEquals(693_008_576, manifest.models[0].byteSize)
        assertEquals(
            "c8e66535e9ee3b114a9be05ac404cb9585910865718095a3914c2b51c4d5462f",
            manifest.models[0].sha256,
        )
        assertEquals(1_884_843_552, manifest.models[1].byteSize)
        assertEquals(
            "de3acf2f77842aa0cd7a958bf9ce5c549b94db0c7930776f320ad6152e1e86f6",
            manifest.models[1].sha256,
        )
        assertTrue(manifest.models.all { it.provenanceUrl.startsWith("https://") })
    }

    @Test(expected = IllegalArgumentException::class)
    fun `manifest rejects a mutable revision`() {
        ModelManifestParser.parse(
            """{"repository":"owner/repo","revision":"main"}"""
        )
    }

    @Test(expected = IllegalArgumentException::class)
    fun `manifest rejects a model filename with path traversal`() {
        ModelManifestParser.parse(
            """{"repository":"owner/repo","revision":"${"a".repeat(40)}","conversionLicense":"Apache-2.0","conversionLicenseUrl":"https://example.test/license","upstreamRepository":"owner/source","upstreamRevision":"${"c".repeat(40)}","upstreamLicense":"other","upstreamLicenseUrl":"https://example.test/upstream-license","licenseReviewRequired":true,"architectureProvenanceUrl":"https://example.test/architecture","minimumFreeBytes":1,"models":[{"id":"barbet","filename":"../model.gguf","byteSize":1,"sha256":"${"b".repeat(64)}","provenanceUrl":"https://example.test/source"}]}"""
        )
    }

    @Test(expected = IllegalArgumentException::class)
    fun `manifest cannot waive review when upstream and conversion licenses differ`() {
        val manifestJson =
            File("src/main/assets/bluemagpie-models.json").readText()
                .replace("\"licenseReviewRequired\": true", "\"licenseReviewRequired\": false")

        ModelManifestParser.parse(manifestJson)
    }
}
