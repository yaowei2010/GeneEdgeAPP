package com.example.geneapp.snp

import com.example.geneapp.usb.*

class SnpFailure(val code: String) : Exception(code)
data class SnpQuery(val id: String, val sequence: String, val ref: String, val alt: String)
data class SnpSource(val folder: GeneEntry, val idx: GeneEntry, val ids: GeneEntry)
object SnpContracts {
    fun validSizes(idx: Long, ids: Long) = idx == 536870912L && ids > 0 && ids % 4 == 0L
    fun validQueries(queries: List<SnpQuery>): Boolean = queries.size in 1..3000 &&
        queries.map { it.id }.toSet().size == queries.size && queries.all {
            it.id.isNotBlank() && it.id.length <= 512 && it.sequence.length == 301 &&
            it.sequence.all { base -> base in "ACGT" } && it.ref.length == 1 && it.alt.length == 1 &&
            it.ref[0] in "ACGT" && it.alt[0] in "ACGT" && it.ref != it.alt &&
            it.sequence[150] in (it.ref + it.alt)
        }
}
/** A cancelled worker remains busy until its native call actually releases resources. */
class SnpJobGate {
    private var generation = 0L
    private var active: Long? = null
    @Synchronized fun tryStart(): Long? = if (active != null) null else (++generation).also { active = it }
    fun start(): Long = tryStart() ?: throw SnpFailure("BUSY")
    @Synchronized fun current(token: Long) = active == token && generation == token
    @Synchronized fun invalidate() { generation++ }
    @Synchronized fun finish(token: Long) { if (active == token) active = null }
}
class SnpSourceScanner(private val tree: GeneTree) {
    fun scan(roots: List<GeneEntry>, cancelled: () -> Boolean = { false }): List<SnpSource> {
        val result = mutableListOf<SnpSource>(); val visited = mutableSetOf<String>(); var entries = 0
        fun visit(dir: GeneEntry, depth: Int) {
            if (cancelled()) throw SnpFailure("CANCELLED")
            if (depth > 16) throw SnpFailure("RESOURCE_LIMIT")
            if (!visited.add(dir.uri)) return
            val children = tree.list(dir)
            // A provider query can block while cancellation/source removal occurs.
            // Recheck after it returns, including for the final leaf directory.
            if (cancelled()) throw SnpFailure("CANCELLED")
            entries += children.size
            if (entries > 10000) throw SnpFailure("RESOURCE_LIMIT")
            val ids = children.filter { !it.directory && it.name == GeneDongleImporter.IDS }
            val idx = children.filter { !it.directory && it.name == GeneDongleImporter.IDX }
            if (ids.size > 1 || idx.size > 1) throw SnpFailure("SOURCE_AMBIGUOUS")
            if (ids.size == 1 && idx.size == 1) result.add(SnpSource(dir, idx.single(), ids.single()))
            children.filter { it.directory }.forEach { visit(it, depth + 1) }
        }
        roots.forEach { visit(it, 0) }; return result
    }
}
