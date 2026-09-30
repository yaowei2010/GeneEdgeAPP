package com.example.geneapp.usb

import org.junit.Assert.*
import org.junit.Test
import java.io.*
import java.nio.file.Files

class GeneDongleImporterTest {
    private class Tree : GeneTree {
        val children = mutableMapOf<String, List<GeneEntry>>()
        val data = mutableMapOf<String, ByteArray>()
        var fail: String? = null
        var closed = 0
        var onRead: (() -> Unit)? = null
        override fun list(directory: GeneEntry) = children[directory.uri] ?: emptyList()
        override fun open(file: GeneEntry): InputStream {
            if (file.uri == fail) throw IOException("provider failed")
            return object : ByteArrayInputStream(data[file.uri] ?: byteArrayOf(1)) {
                override fun read(buffer: ByteArray, offset: Int, length: Int): Int { onRead?.invoke(); return super.read(buffer, offset, length) }
                override fun close() { closed++; super.close() }
            }
        }
        fun pair(dir: String) {
            children[dir] = listOf(GeneEntry("$dir/i", GeneDongleImporter.IDS, false), GeneEntry("$dir/x", GeneDongleImporter.IDX, false))
        }
    }
    private val root = GeneEntry("root", "root", true)
    private fun temporary() = Files.createTempDirectory("gene-test").toFile().apply { deleteOnExit() }
    @Test fun nestedPreservesRawBytesAndClosesStreams() {
        val tree = Tree(); tree.children["root"] = listOf(GeneEntry("nested", "nested", true)); tree.pair("nested")
        tree.data["nested/i"] = byteArrayOf(0, -1, 10)
        val store = temporary()
        val result = GeneDongleImporter(tree, store).import(listOf(root))
        assertEquals("ready", result.state); assertEquals("nested", result.dataset!!.folderName)
        assertArrayEquals(byteArrayOf(0, -1, 10), File(store, "${result.dataset!!.datasetId}/${GeneDongleImporter.IDS}").readBytes())
        assertEquals(2, tree.closed)
    }
    @Test fun missingSplitAndAmbiguousPairs() {
        val tree = Tree(); val importer = GeneDongleImporter(tree, temporary())
        assertEquals("missing_files", importer.import(listOf(root)).state)
        tree.children["root"] = listOf(GeneEntry("a", "a", true), GeneEntry("b", "b", true))
        tree.children["a"] = listOf(GeneEntry("i", GeneDongleImporter.IDS, false))
        tree.children["b"] = listOf(GeneEntry("x", GeneDongleImporter.IDX, false))
        assertEquals("missing_files", importer.import(listOf(root)).state)
        tree.pair("a"); tree.pair("b")
        assertEquals("ambiguous", importer.import(listOf(root)).state)
    }
    @Test fun failuresPreservePreviousAndCleanPartial() {
        val tree = Tree(); tree.pair("root"); val store = temporary()
        val importer = GeneDongleImporter(tree, store, maxBytes = 3)
        val first = importer.import(listOf(root)).dataset!!
        tree.data["root/x"] = byteArrayOf()
        assertEquals("empty_file", importer.import(listOf(root)).errorCode)
        tree.data["root/x"] = byteArrayOf(1, 2, 3, 4)
        assertEquals("file_too_large", importer.import(listOf(root)).errorCode)
        tree.fail = "root/x"
        assertEquals("io_failed", importer.import(listOf(root)).errorCode)
        assertEquals("cancelled", importer.import(listOf(root)) { true }.errorCode)
        assertEquals(first, importer.restore())
        assertFalse(store.listFiles()!!.any { it.name.startsWith("partial-") })
        assertEquals(first, GeneDongleImporter(tree, store).restore())
    }
    @Test fun traversalLimitsAreErrors() {
        val tree = Tree(); tree.children["root"] = listOf(GeneEntry("a", "a", true)); tree.pair("a")
        assertEquals("scan_limit", GeneDongleImporter(tree, temporary(), maxDepth = 0).import(listOf(root)).errorCode)
        assertEquals("scan_limit", GeneDongleImporter(tree, temporary(), maxEntries = 1).import(listOf(root)).errorCode)
    }
    @Test fun validatesOnlyMountedRemovableExternalTrees() {
        val mounted = setOf("ABCD-1234")
        assertTrue(GeneSourcePolicy.accepts("com.android.externalstorage.documents", "ABCD-1234:folder", mounted, "ABCD-1234"))
        assertFalse(GeneSourcePolicy.accepts("cloud", "ABCD-1234:", mounted, null))
        assertFalse(GeneSourcePolicy.accepts("com.android.externalstorage.documents", "primary:folder", mounted, null))
        assertFalse(GeneSourcePolicy.accepts("com.android.externalstorage.documents", "ABCD-1234:", emptySet(), null))
        assertFalse(GeneSourcePolicy.accepts("com.android.externalstorage.documents", "ABCD-1234:", mounted, "OTHER"))
        assertTrue(GeneSourcePolicy.accepts("com.android.externalstorage.documents", "abcd-1234:folder", mounted, "ABCD-1234"))
    }
    @Test fun cancelledDuringCopyClosesAndPreservesDataset() {
        val tree = Tree(); tree.pair("root"); val store = temporary()
        val importer = GeneDongleImporter(tree, store)
        val first = importer.import(listOf(root)).dataset!!
        var cancel = false
        tree.onRead = { cancel = true }
        assertEquals("cancelled", importer.import(listOf(root)) { cancel }.errorCode)
        assertEquals(3, tree.closed)
        assertEquals(first, importer.restore())
        assertFalse(store.listFiles()!!.any { it.name.startsWith("partial-") })
    }
    @Test fun duplicateNamesAreAmbiguousWithoutCartesianAllocation() {
        val tree = Tree()
        tree.children["root"] = (1..5000).map { GeneEntry("i$it", GeneDongleImporter.IDS, false) } + (1..5000).map { GeneEntry("x$it", GeneDongleImporter.IDX, false) }
        assertEquals("ambiguous", GeneDongleImporter(tree, temporary()).import(listOf(root)).state)
        assertEquals(0, tree.closed)
    }
    @Test fun invalidLimitsFailFast() {
        for (limit in listOf(0L, -1L)) {
            try { GeneDongleImporter(Tree(), temporary(), maxBytes = limit); fail("must reject") } catch (_: IllegalArgumentException) {}
        }
        try { GeneDongleImporter(Tree(), temporary(), maxEntries = 0); fail("must reject") } catch (_: IllegalArgumentException) {}
        try { GeneDongleImporter(Tree(), temporary(), maxDepth = -1); fail("must reject") } catch (_: IllegalArgumentException) {}
    }
    @Test fun exactByteBoundarySucceedsAndRestoredOversizeIsRejected() {
        val tree = Tree(); tree.pair("root"); tree.data["root/i"] = byteArrayOf(1, 2, 3)
        val store = temporary()
        assertEquals("ready", GeneDongleImporter(tree, store, maxBytes = 3).import(listOf(root)).state)
        assertNull(GeneDongleImporter(tree, store, maxBytes = 2).restore())
    }
    @Test fun providerLimitPropagatesAndMalformedMetadataIsNotRestored() {
        val tree = object : GeneTree {
            override fun list(directory: GeneEntry): List<GeneEntry> = throw GeneScanLimitException()
            override fun open(file: GeneEntry): InputStream = throw AssertionError("no stream should open")
        }
        val store = temporary()
        assertEquals("scan_limit", GeneDongleImporter(tree, store).import(listOf(root)).errorCode)
        File(store, "current.properties").writeText("datasetId=../../outside\nidsBytes=1\nidxBytes=1\n")
        assertNull(GeneDongleImporter(tree, store).restore())
    }
}
