package com.example.geneapp.snp

import org.json.JSONObject
import kotlin.math.abs

/** Diagnostic transport only, never counts evidence or calls the genotype model. */
object SnpDebug {
    fun elapsed(enabled: Boolean, started: Long, now: Long, active: Boolean): Double? {
        if (!enabled || !active || started == 0L) return null
        if (now < started) throw SnpFailure("INVALID_FORMAT")
        return (now-started)/1e6
    }
    fun enabled(value: Any?): Boolean = when (value) {
        null -> false
        is Boolean -> value
        else -> throw SnpFailure("INVALID_FORMAT")
    }
    private fun value(map: Map<*, *>, key: String): Double {
        val n = (map[key] as? Number)?.toDouble() ?: throw SnpFailure("INVALID_FORMAT")
        if (!n.isFinite() || n < 0) throw SnpFailure("INVALID_FORMAT")
        return n
    }
    fun batch(rows: List<Map<String, Any?>>, setup: Double, total: Double): Map<String, Double> {
        if (!setup.isFinite() || !total.isFinite() || setup < 0 || total < 0) throw SnpFailure("INVALID_FORMAT")
        var io = 0.0; var count = 0.0; var model = 0.0
        rows.forEach { row ->
            val t = row["debugTiming"] as? Map<*, *> ?: throw SnpFailure("INVALID_FORMAT")
            val i = value(t,"ioMs"); val c = value(t,"countMs"); val g = value(t,"genotypeMs")
            if (abs(value(t,"nativeTotalMs")-i-c-g-value(t,"nativeOverheadMs")) > 0.01) throw SnpFailure("INVALID_FORMAT")
            io += i; count += c; model += g
        }
        val overhead = total-setup-io-count-model
        if (!overhead.isFinite() || overhead < 0) throw SnpFailure("INVALID_FORMAT")
        return mapOf("setupIoMs" to setup, "queryIoMs" to io, "countMs" to count,
            "genotypeMs" to model, "overheadMs" to overhead, "totalMs" to total)
    }
    fun logRow(enabled: Boolean, row: Map<String, Any?>): String? {
        if (!enabled) return null
        val keys = listOf("id", "total", "ref", "alt", "ambiguous", "coverageOnly", "skippedBuckets",
            "effectiveDepth", "refAllele", "altAllele", "gt", "posterior", "noCallReason", "modelVersion", "calibrated",
            "baseCounts","alleles","actualGenotype","bestGenotype","bestPosterior","logScoreGap")
        val safe = keys.filter { row.containsKey(it) }.associateWith { row[it] }.toMutableMap()
        val id = (safe["id"] as? String).orEmpty()
        safe["id"] = id.substring(0,id.offsetByCodePoints(0,minOf(96,id.codePointCount(0,id.length))))
        (row["parameters"] as? Map<*, *>)?.let { p -> safe["parameters"] =
            listOf("epsilon","rho","priors","minDepth","minPosterior").filter { p.containsKey(it) }.associateWith { p[it] } }
        (row["debugTiming"] as? Map<*, *>)?.let { t -> safe["debugTiming"] =
            listOf("ioMs","countMs","genotypeMs","nativeOverheadMs","nativeTotalMs").associateWith { value(t,it) } }
        val line = JSONObject(safe).toString()
        if (line.toByteArray(Charsets.UTF_8).size > 3000) throw SnpFailure("INVALID_FORMAT")
        return line
    }
    fun logTerminal(enabled: Boolean, status: String, elapsed: Double): String? {
        if (!enabled) return null
        if (!elapsed.isFinite() || elapsed < 0) throw SnpFailure("INVALID_FORMAT")
        return JSONObject(mapOf("status" to status, "elapsedMs" to elapsed)).toString()
    }
}
