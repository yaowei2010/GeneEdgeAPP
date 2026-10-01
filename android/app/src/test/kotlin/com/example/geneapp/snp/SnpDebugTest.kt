package com.example.geneapp.snp

import org.junit.Assert.*
import org.junit.Test

class SnpDebugTest {
    @Test fun jointLocusLoggingIncludesCountsAndGenotypeWithoutPrivateFields() {
        val log=SnpDebug.logRow(true,row()+mapOf("baseCounts" to listOf(10,20,0,0),
            "alleles" to listOf("T","A","C","G"),"actualGenotype" to "TA","bestPosterior" to .99))!!
        assertTrue(log.contains("baseCounts"));assertTrue(log.contains("actualGenotype"));assertTrue(log.contains("bestPosterior"))
        assertFalse(log.contains("PRIVATE"))
    }
    @Test fun elapsedOnlyBelongsToActiveStartedDebugJob() {
        assertNull(SnpDebug.elapsed(false, 100L, 500L, true))
        assertNull(SnpDebug.elapsed(true, 0L, 500L, true))
        assertNull(SnpDebug.elapsed(true, 100L, 500L, false))
        assertEquals(4.0, SnpDebug.elapsed(true, 1000000L, 5000000L, true)!!, 0.0)
        assertFalse(SnpDebug.enabled(null)); assertTrue(SnpDebug.enabled(true))
        try { SnpDebug.enabled("true"); fail("string must not enable genetic logging") } catch (_: SnpFailure) {}
    }
    private fun row() = mapOf<String, Any?>("id" to "rs1", "ref" to 20, "alt" to 20,
        "gt" to "0/1", "sequence" to "PRIVATE", "sourceId" to "content://PRIVATE",
        "debugTiming" to mapOf("ioMs" to 7.0, "countMs" to 5.0, "genotypeMs" to 2.0,
            "nativeOverheadMs" to 1.0, "nativeTotalMs" to 15.0))
    @Test fun nonOverlappingBatchBreakdown() {
        val t = SnpDebug.batch(listOf(row()), 3.0, 22.0)
        assertEquals(7.0, t.getValue("queryIoMs"), 0.0)
        assertEquals(5.0, t.getValue("countMs"), 0.0)
        assertEquals(2.0, t.getValue("genotypeMs"), 0.0)
        assertEquals(5.0, t.getValue("overheadMs"), 0.0)
        assertEquals(22.0, t.getValue("totalMs"), 0.0)
    }
    @Test fun loggingIsOptInAndPrivateFieldsAreRemoved() {
        assertNull(SnpDebug.logRow(false, row()))
        val log = SnpDebug.logRow(true, row())!!
        assertTrue(log.contains("\"ref\":20")); assertTrue(log.contains("ioMs"))
        assertFalse(log.contains("PRIVATE")); assertFalse(log.contains("sourceId")); assertFalse(log.contains("sequence"))
    }
    @Test fun unicodeAndControlCharactersAreBoundedAndEscaped() {
        val log = SnpDebug.logRow(true, row() + ("id" to ("\n\"😀".repeat(512))))!!
        assertTrue(log.toByteArray(Charsets.UTF_8).size <= 3000)
        assertFalse(log.contains('\n')); assertTrue(log.contains("\\n")); assertTrue(log.contains("\\\""))
    }
    @Test fun rejectsImpossibleAndNonfiniteTimings() {
        for (total in listOf(1.0, Double.NaN, Double.POSITIVE_INFINITY, -1.0)) {
            try { SnpDebug.batch(listOf(row()), 3.0, total); fail("accepted $total") }
            catch (_: SnpFailure) {}
        }
    }
    @Test fun interruptedSummaryHasNoCompleteTimingOrResults() {
        assertNull(SnpDebug.logTerminal(false, "cancelled", 4.0))
        val log = SnpDebug.logTerminal(true, "cancelled", 4.0)!!
        assertTrue(log.contains("cancelled")); assertTrue(log.contains("elapsedMs"))
        assertFalse(log.contains("debugTiming")); assertFalse(log.contains("gt"))
    }
}
