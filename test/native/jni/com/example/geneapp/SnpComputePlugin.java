package com.example.geneapp;

import java.io.FileDescriptor;
import java.io.RandomAccessFile;
import java.lang.reflect.Field;
import java.nio.file.Files;
import java.nio.file.Path;

/** Host integration harness exercises the actual JNI bridge, C engine and C model.
 * No Android runtime, patient data, network or installed app is used. */
public final class SnpComputePlugin {
    private boolean cancelled;
    private boolean callbackThrows;
    private native String nativeComputeLocus(int idx,int ids,String[] sequences,String ref,long token,boolean debug);
    private native String nativeCompute(int idx, int ids, String sequence, String ref, String alt, long token, boolean debug);
    private String nativeCompute(int idx, int ids, String sequence, String ref, String alt, long token) {
        return nativeCompute(idx, ids, sequence, ref, alt, token, false);
    }
    private static double time(String json, String name) {
        java.util.regex.Matcher m = java.util.regex.Pattern.compile("\\\"" + name + "\\\":([0-9.eE+\\-]+)").matcher(json);
        require(m.find()); double value = Double.parseDouble(m.group(1));
        require(Double.isFinite(value) && value >= 0); return value;
    }
    public boolean isCancelled(long token) {
        if (callbackThrows) throw new IllegalStateException("test callback");
        return cancelled || token != 1;
    }
    private static int descriptor(RandomAccessFile file) throws Exception {
        Field fd = FileDescriptor.class.getDeclaredField("fd"); fd.setAccessible(true);
        return fd.getInt(file.getFD());
    }
    private static void require(boolean condition) { if (!condition) throw new AssertionError(); }
    private static void le(RandomAccessFile file, long value) throws Exception {
        for (int i = 0; i < 4; i++) file.write((int)(value >>> (8 * i)) & 255);
    }
    private static long bucket(RandomAccessFile idx, RandomAccessFile ids, String seq, int position, long offset, int[] reads) throws Exception {
        long hash = 0;
        for (int i = 0; i < 13; i++) hash = (hash << 2) | ((seq.charAt(position+i) >>> 1) & 3);
        idx.seek(hash * 8); le(idx, offset); le(idx, reads.length | ((offset >>> 32) << 24));
        ids.seek(offset * 4); for (int read : reads) le(ids, read);
        return offset + reads.length;
    }
    public static void main(String[] args) throws Exception {
        System.load(args[0]); SnpComputePlugin plugin = new SnpComputePlugin();
        Path index = Files.createTempFile("snp-jni-index", ".bin");
        Path postings = Files.createTempFile("snp-jni-postings", ".bin");
        try (RandomAccessFile idx = new RandomAccessFile(index.toFile(), "rw");
             RandomAccessFile ids = new RandomAccessFile(postings.toFile(), "rw")) {
            idx.setLength(536870912); ids.setLength(4);
            char[] sequence = new char[301]; int seed = 123456789;
            for (int i = 0; i < 301; i++) { seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5; sequence[i] = "ACTG".charAt(seed & 3); }
            sequence[150] = 'A'; String ref = new String(sequence); sequence[150] = 'C'; String alt = new String(sequence);
            int ifd = descriptor(idx), dfd = descriptor(ids);
            String empty = plugin.nativeCompute(ifd, dfd, ref, "A", "C", 1);
            require(empty.contains("\"gt\":\"./.\"") && empty.contains("\"noCallReason\":\"ZERO_DEPTH\""));
            require(empty.contains("\"modelVersion\":\"bb-research-v1\"") && empty.contains("\"calibrated\":false"));
            require(plugin.nativeCompute(ifd, dfd, "A", "A", "C", 1).contains("INVALID_QUERY"));
            require(plugin.nativeCompute(ifd, dfd, ref, "A", "A", 1).contains("INVALID_QUERY"));
            plugin.cancelled = true;
            for (int i = 0; i < 100; i++) require(plugin.nativeCompute(ifd, dfd, ref, "A", "C", 1).contains("CANCELLED"));
            plugin.cancelled = false; plugin.callbackThrows = true;
            try { plugin.nativeCompute(ifd, dfd, ref, "A", "C", 1); throw new AssertionError(); }
            catch (IllegalStateException expected) { require(expected.getMessage().equals("test callback")); }
            plugin.callbackThrows = false;
            long offset = (1L << 30) + 1; int[] all = new int[42], rs = new int[21], as = new int[21];
            for (int i = 0; i < 42; i++) all[i] = i;
            for (int i = 0; i < 20; i++) { rs[i] = i; as[i] = i + 20; } rs[20] = as[20] = 40;
            for (int i = 0; i <= 288; i += 2) {
                if (i >= 138 && i <= 150) { offset = bucket(idx, ids, ref, i, offset, rs); offset = bucket(idx, ids, alt, i, offset, as); }
                else offset = bucket(idx, ids, ref, i, offset, all);
            }
            String result = plugin.nativeCompute(ifd, dfd, ref, "A", "C", 1);
            require(result.contains("\"total\":42") && result.contains("\"ref\":20") && result.contains("\"alt\":20"));
            require(result.contains("\"ambiguous\":1") && result.contains("\"coverageOnly\":1"));
            require(result.contains("\"effectiveDepth\":40") && result.contains("\"gt\":\"0/1\""));
            require(result.contains("\"noCallReason\":null") && result.contains("\"parameters\":{") && !result.contains("NaN"));
            require(!result.contains("debugTiming"));
            String debug = plugin.nativeCompute(ifd, dfd, ref, "A", "C", 1, true);
            require(debug.contains("\"debugTiming\":{") && debug.startsWith(result.substring(0, result.length()-1)));
            require(Math.abs(time(debug,"nativeTotalMs") - time(debug,"ioMs") - time(debug,"countMs")
                - time(debug,"genotypeMs") - time(debug,"nativeOverheadMs")) < 0.01);
            // Caller descriptors remain valid after each native call.
            String locus=plugin.nativeComputeLocus(ifd,dfd,new String[]{ref,alt},"A",1,false);
            require(locus.contains("\"baseCounts\":[20,20,0,0]")&&locus.contains("\"actualGenotype\":\"AC\""));
            require(locus.contains("\"modelVersion\":\"dm-locus-research-v1\"")&&!locus.contains("debugTiming"));
            String measured=plugin.nativeComputeLocus(ifd,dfd,new String[]{ref,alt},"A",1,true);
            require(measured.startsWith(locus.substring(0,locus.length()-1)));
            require(Math.abs(time(measured,"nativeTotalMs")-time(measured,"ioMs")-time(measured,"countMs")
                -time(measured,"genotypeMs")-time(measured,"nativeOverheadMs"))<.01);
            require(plugin.nativeComputeLocus(ifd,dfd,new String[]{ref,"A"},"A",1,false).contains("INVALID_QUERY"));
            require(plugin.nativeComputeLocus(ifd,dfd,new String[]{ref,"T"+alt.substring(1)},"A",1,false).contains("INVALID_QUERY"));
            plugin.cancelled=true;
            require(plugin.nativeComputeLocus(ifd,dfd,new String[]{ref},"A",1,true).contains("CANCELLED"));
            plugin.cancelled=false;
            for(int i=0;i<77;i++)require(plugin.nativeComputeLocus(ifd,dfd,new String[]{ref,alt},"A",1,false).equals(locus));
            require(idx.length() == 536870912 && ids.length() > 4294967296L);
            System.out.println("JNI + C engine + C genotype integration passed");
        } finally { Files.deleteIfExists(index); Files.deleteIfExists(postings); }
    }
}
