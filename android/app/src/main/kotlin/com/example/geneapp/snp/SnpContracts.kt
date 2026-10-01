package com.example.geneapp.snp

import com.example.geneapp.usb.*

class SnpFailure(val code: String) : Exception(code)
data class SnpQuery(val id: String, val sequence: String, val ref: String, val alt: String)
data class SnpLocus(val id: String,val rsId: String,val chromosome: String,val position: Long,
                    val ref: String,val sequences: List<String>)
data class SnpSource(val folder: GeneEntry, val idx: GeneEntry, val ids: GeneEntry)
/** Candidates MUST already come from authorized mounted trees, never from preferences. */
object SnpUsbAccess {
    fun rootDocumentId(volume: String, mounted: Set<String>): String {
        val id = mounted.singleOrNull { it.equals(volume, true) }
            ?: throw SnpFailure("USB_REMOVED")
        if (id.isBlank() || id.contains(':') || id.equals("primary", true)) throw SnpFailure("USB_REMOVED")
        return "$id:"
    }
    fun scopeLabel(documentId: String): String = documentId.substringAfter(':', "").let {
        if (it.isEmpty()) "USB 根目錄" else "子資料夾：$it"
    }
    fun restore(current: String?, authorizedPairs: Map<String, String>, remembered: Map<String, String>): String? {
        if (current != null && authorizedPairs.containsKey(current)) return current
        val matches = authorizedPairs.filter { (source, volume) ->
            remembered.entries.any { it.key.equals(volume, true) && it.value == source }
        }.keys
        return matches.singleOrNull() ?: if (matches.isEmpty()) authorizedPairs.keys.singleOrNull() else null
    }
}
object SnpContracts {
    fun locusMode(value: Any?): Boolean = when(value) {
        null,"query" -> false
        "locus" -> true
        else -> throw SnpFailure("INVALID_QUERY")
    }
    fun loci(queries: List<SnpQuery>): List<SnpLocus> {
        if(!validQueries(queries)) throw SnpFailure("INVALID_QUERY")
        val pattern=Regex("^(rs[0-9]+)_([A-Za-z0-9]+)_([1-9][0-9]*)_([ACGT])_([ACGT])$")
        val grouped=linkedMapOf<String,MutableList<SnpQuery>>()
        queries.forEach { q ->
            val m=pattern.matchEntire(q.id) ?: throw SnpFailure("INVALID_QUERY")
            if(m.groupValues[4]!=q.ref||m.groupValues[5]!=q.alt||m.groupValues[3].toLongOrNull()==null)
                throw SnpFailure("INVALID_QUERY")
            val id=m.groupValues.subList(1,4).joinToString("_")
            grouped.getOrPut(id){mutableListOf()}.add(q)
        }
        return grouped.map { (id,qs) ->
            val first=qs.first();val flank=first.sequence.removeRange(150,151)
            if(qs.size>3||qs.any { it.ref!=first.ref||it.sequence.removeRange(150,151)!=flank })
                throw SnpFailure("INVALID_QUERY")
            val m=pattern.matchEntire(first.id)!!
            SnpLocus(id,m.groupValues[1],m.groupValues[2],m.groupValues[3].toLong(),first.ref,qs.map{it.sequence})
        }
    }
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
