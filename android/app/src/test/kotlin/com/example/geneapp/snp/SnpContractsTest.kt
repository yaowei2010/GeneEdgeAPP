package com.example.geneapp.snp

import com.example.geneapp.usb.*
import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream

class SnpContractsTest {
    private fun entry(name: String, dir: Boolean = false) = GeneEntry(name, name, dir)
    @Test fun discoversAllPairsWithoutReadingContents() {
        val root = entry("root", true); val sub = entry("sub", true)
        val tree = object : GeneTree {
            override fun list(directory: GeneEntry) = if (directory == root) listOf(entry("combined_idx_all.txt"), entry("combined_ids_all.txt"), sub) else listOf(entry("combined_idx_all.txt"), entry("combined_ids_all.txt"))
            override fun open(file: GeneEntry): ByteArrayInputStream = error("must not copy")
        }
        assertEquals(2, SnpSourceScanner(tree).scan(listOf(root)).size)
    }
    @Test fun malformedSizesFailRatherThanImport() {
        assertTrue(SnpContracts.validSizes(536870912L, 4294967300L))
        assertFalse(SnpContracts.validSizes(8, 4))
        assertFalse(SnpContracts.validSizes(536870912L, 5))
    }
    @Test fun validatesWholePanelAndCenter() {
        val seq = "A".repeat(301)
        assertTrue(SnpContracts.validQueries(listOf(SnpQuery("a", seq, "A", "C"))))
        assertFalse(SnpContracts.validQueries(listOf(SnpQuery("a", seq, "G", "T"))))
        assertFalse(SnpContracts.validQueries(listOf(SnpQuery("a", seq, "A", "C"), SnpQuery("a", seq, "A", "C"))))
    }
    @Test fun cancellationAndSourceChangeInvalidateGeneration() {
        val jobs = SnpJobGate(); val first = jobs.start()
        assertTrue(jobs.current(first)); assertNull(jobs.tryStart())
        jobs.invalidate(); assertFalse(jobs.current(first)); assertNull(jobs.tryStart())
        jobs.finish(first); val second = jobs.start()
        assertTrue(jobs.current(second)); assertFalse(jobs.current(first))
    }
    @Test fun scannerHonorsCancellation() {
        val tree = object : GeneTree {
            override fun list(directory: GeneEntry): List<GeneEntry> = error("cancel first")
            override fun open(file: GeneEntry) = ByteArrayInputStream(byteArrayOf())
        }
        try { SnpSourceScanner(tree).scan(listOf(entry("root", true))) { true }; fail() }
        catch (e: SnpFailure) { assertEquals("CANCELLED", e.code) }
    }
    @Test fun scannerRejectsCancellationDuringLastProviderListing() {
        var cancelled = false
        val tree = object : GeneTree {
            override fun list(directory: GeneEntry): List<GeneEntry> {
                cancelled = true
                return listOf(entry(GeneDongleImporter.IDX), entry(GeneDongleImporter.IDS))
            }
            override fun open(file: GeneEntry) = error("Discovery must not read contents")
        }
        try {
            SnpSourceScanner(tree).scan(listOf(entry("root", true))) { cancelled }
            fail("Cancellation during listing must not become a successful discovery")
        } catch (e: SnpFailure) { assertEquals("CANCELLED", e.code) }
    }
    @Test fun duplicateEntriesAndResourceLimitsFailExplicitly() {
        fun scanner(children: List<GeneEntry>) = SnpSourceScanner(object : GeneTree {
            override fun list(directory: GeneEntry) = children
            override fun open(file: GeneEntry) = error("Discovery must not read contents")
        })
        try {
            scanner(listOf(entry(GeneDongleImporter.IDX), entry(GeneDongleImporter.IDX), entry(GeneDongleImporter.IDS)))
                .scan(listOf(entry("root", true)))
            fail("Duplicate filename entries must not be guessed")
        } catch(e: SnpFailure) { assertEquals("SOURCE_AMBIGUOUS", e.code) }
        try {
            scanner((0..10000).map { entry("file$it") }).scan(listOf(entry("root", true)))
            fail("Discovery must enforce the aggregate entry limit")
        } catch(e: SnpFailure) { assertEquals("RESOURCE_LIMIT", e.code) }
    }
    @Test fun gateFinishOfStaleJobCannotReleaseNewJobAndCancelIsRepeatable() {
        val gate = SnpJobGate()
        val first = gate.start()
        gate.invalidate(); gate.invalidate()
        assertFalse(gate.current(first)); assertNull(gate.tryStart())
        gate.finish(first)
        val second = gate.start()
        gate.finish(first)
        assertTrue(gate.current(second)); assertNull(gate.tryStart())
        gate.finish(second)
        assertNotNull(gate.tryStart())
    }
    @Test fun completeQueryAndSizeBoundaryValidation() {
        val valid = SnpQuery("id", "A".repeat(301), "A", "C")
        assertFalse(SnpContracts.validQueries(emptyList()))
        assertTrue(SnpContracts.validQueries((0 until 3000).map { valid.copy(id="id$it") }))
        assertFalse(SnpContracts.validQueries((0..3000).map { valid.copy(id="id$it") }))
        listOf(valid.copy(id=" "), valid.copy(id="x".repeat(513)), valid.copy(sequence="A".repeat(300)),
            valid.copy(sequence="N"+"A".repeat(300)), valid.copy(ref=""), valid.copy(alt="CC"),
            valid.copy(alt="A"), valid.copy(ref="a")).forEach {
            assertFalse("Invalid query must reject the entire batch", SnpContracts.validQueries(listOf(valid,it)))
        }
        assertFalse(SnpContracts.validSizes(536870912L, 0))
        assertFalse(SnpContracts.validSizes(536870912L, -4))
        assertFalse(SnpContracts.validSizes(536870912L, Long.MAX_VALUE))
        assertTrue(SnpContracts.validSizes(536870912L, Long.MAX_VALUE-3))
    }
}
