package com.example.geneapp.usb

import java.io.*
import java.util.Properties
import java.util.UUID
import java.nio.file.Files
import java.nio.file.StandardCopyOption

data class GeneEntry(val uri: String, val name: String, val directory: Boolean)
interface GeneTree {
    fun list(directory: GeneEntry): List<GeneEntry>
    fun open(file: GeneEntry): InputStream
}
class GeneScanLimitException : IOException()
data class GeneDataset(val datasetId: String, val sourceUri: String, val folderName: String, val idsBytes: Long, val idxBytes: Long) {
    fun snapshot(): Map<String, Any> = mapOf("datasetId" to datasetId, "sourceUri" to sourceUri, "folderName" to folderName, "idsBytes" to idsBytes, "idxBytes" to idxBytes)
}
data class GeneImportResult(val state: String, val dataset: GeneDataset? = null, val errorCode: String? = null)
object GeneSourcePolicy {
    fun accepts(authority: String?, treeId: String, mounted: Set<String>, requested: String?): Boolean {
        val volume = treeId.substringBefore(':')
        return authority == "com.android.externalstorage.documents" && treeId.contains(':') &&
            !volume.equals("primary", true) && mounted.any { it.equals(volume, true) } && (requested == null || requested.equals(volume, true))
    }
}

/** Provider-independent raw import. Only UUIDs and fixed names form private paths. */
class GeneDongleImporter(
    private val tree: GeneTree,
    private val storage: File,
    private val maxBytes: Long = 256L * 1024 * 1024,
    private val maxEntries: Int = 10000,
    private val maxDepth: Int = 16,
    private val publicationLock: Any = Any()
) {
    init { require(maxBytes > 0 && maxEntries > 0 && maxDepth >= 0) }
    companion object { const val IDS = "combined_ids_all.txt"; const val IDX = "combined_idx_all.txt" }
    private class Failure(val code: String) : IOException()
    private fun check(cancelled: () -> Boolean) { if (cancelled() || Thread.currentThread().isInterrupted) throw Failure("cancelled") }
    fun restore(): GeneDataset? = try {
        val p = Properties().apply { File(storage, "current.properties").inputStream().use { load(it) } }
        val id = p.getProperty("datasetId")
        require(UUID.fromString(id).toString() == id)
        val d = GeneDataset(id, p.getProperty("sourceUri"), p.getProperty("folderName"), p.getProperty("idsBytes").toLong(), p.getProperty("idxBytes").toLong())
        require(d.idsBytes in 1..maxBytes && d.idxBytes in 1..maxBytes)
        require(File(storage, "$id/$IDS").length() == d.idsBytes && File(storage, "$id/$IDX").length() == d.idxBytes)
        d
    } catch (_: Exception) { null }

    fun import(roots: List<GeneEntry>, cancelled: () -> Boolean = { false }): GeneImportResult {
        var temporary: File? = null
        var published: File? = null
        try {
            check(cancelled)
            storage.mkdirs()
            // Single worker owns this directory; leftovers are never successful datasets.
            storage.listFiles()?.filter { it.name.startsWith("partial-") }?.forEach { it.deleteRecursively() }
            var entries = 0
            val visited = mutableSetOf<String>()
            val pairs = mutableListOf<Triple<GeneEntry, GeneEntry, GeneEntry>>()
            fun visit(directory: GeneEntry, depth: Int) {
                check(cancelled)
                if (depth > maxDepth) throw Failure("scan_limit")
                if (!visited.add(directory.uri)) return
                val children = tree.list(directory)
                entries += children.size
                if (entries > maxEntries) throw Failure("scan_limit")
                val ids = children.filter { !it.directory && it.name == IDS }
                val idx = children.filter { !it.directory && it.name == IDX }
                if (ids.isNotEmpty() && idx.isNotEmpty() && pairs.size < 2) {
                    pairs.add(Triple(directory, ids.first(), idx.first()))
                    if ((ids.size > 1 || idx.size > 1) && pairs.size < 2) pairs.add(Triple(directory, ids.last(), idx.last()))
                }
                children.filter { it.directory }.forEach { visit(it, depth + 1) }
            }
            roots.forEach { visit(it, 0) }
            if (pairs.isEmpty()) return GeneImportResult("missing_files")
            if (pairs.size != 1) return GeneImportResult("ambiguous")
            val pair = pairs.single()
            val id = UUID.randomUUID().toString()
            temporary = File(storage, "partial-$id").apply { if (!mkdir()) throw IOException() }
            fun copy(entry: GeneEntry, name: String): Long {
                var count = 0L
                tree.open(entry).use { input ->
                    FileOutputStream(File(temporary, name)).use { output ->
                        val buffer = ByteArray(65536)
                        while (true) {
                            check(cancelled)
                            val read = input.read(buffer)
                            check(cancelled)
                            if (read < 0) break
                            if (read == 0) continue
                            count += read
                            if (count > maxBytes) throw Failure("file_too_large")
                            output.write(buffer, 0, read)
                        }
                        output.fd.sync()
                    }
                }
                if (count == 0L) throw Failure("empty_file")
                return count
            }
            val idsBytes = copy(pair.second, IDS)
            val idxBytes = copy(pair.third, IDX)
            check(cancelled)
            val dataset = GeneDataset(id, pair.first.uri, pair.first.name, idsBytes, idxBytes)
            published = File(storage, id)
            if (!temporary.renameTo(published)) throw IOException()
            val previous = restore()
            val properties = Properties().apply { dataset.snapshot().forEach { (k, v) -> setProperty(k, v.toString()) } }
            val metadata = File(storage, "partial-$id-metadata")
            try {
                FileOutputStream(metadata).use { properties.store(it, null); it.fd.sync() }
                synchronized(publicationLock) {
                    check(cancelled)
                    Files.move(metadata.toPath(), File(storage, "current.properties").toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
                }
            } finally { metadata.delete() }
            published = null
            previous?.let { if (it.datasetId != id) File(storage, it.datasetId).deleteRecursively() }
            return GeneImportResult("ready", dataset)
        } catch (e: Failure) { return GeneImportResult("error", errorCode = e.code) }
        catch (_: GeneScanLimitException) { return GeneImportResult("error", errorCode = "scan_limit") }
        catch (_: SecurityException) { return GeneImportResult("error", errorCode = "permission_denied") }
        catch (_: Exception) { return GeneImportResult("error", errorCode = "io_failed") }
        finally { temporary?.deleteRecursively(); published?.deleteRecursively() }
    }
}
