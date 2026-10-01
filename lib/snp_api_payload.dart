import 'dart:convert';
import 'snp_compute.dart';

/// Converts completed C results only. Never runs statistics or performs I/O.
class SnpApiPayload {
  SnpApiPayload._(this.request, this.diagnostic);
  final Map<String, Object?> request, diagnostic;
  String get apiJson => const JsonEncoder.withIndent('  ').convert(request);
  String get diagnosticJson =>
      const JsonEncoder.withIndent('  ').convert(diagnostic);
  factory SnpApiPayload.build(
      {required SnpChatContext context,
      required SnpInputIdentity input,
      required List<SnpLocusResult> results,
      String? jobId,
      Map<String, double>? timing}) {
    if (context.userId.trim().isEmpty ||
        context.query.trim().isEmpty ||
        context.topic.trim().isEmpty ||
        results.isEmpty ||
        results.map((r) => r.rsId).toSet().length != results.length ||
        results.map((r) => r.sourceId).toSet().length != 1 ||
        (timing == null && results.any((r) => r.debugTiming != null)) ||
        (timing != null && results.any((r) => r.debugTiming == null))) {
      throw const FormatException(
          'Invalid or non-unique completed locus export');
    }
    final variants = List<String>.unmodifiable(results
        .where((r) => r.actualGenotype != null)
        .map((r) => '${r.rsId}-${r.actualGenotype}'));
    final request = Map<String, Object?>.unmodifiable({
      'user_id': context.userId,
      'query': context.query,
      'topic': context.topic,
      'SNP_list': variants,
      'snp_list': variants,
      'variants': variants,
      'variant_input_count': results.length,
      'variant_used_count': variants.length,
      'no_call_count': results.length - variants.length,
      'yuguard': null
    });
    return SnpApiPayload._(
        request,
        Map<String, Object?>.unmodifiable({
          'schemaVersion': 2,
          if (jobId != null) 'jobId': jobId,
          'inputSet': input.toMap(),
          'modelVersion': 'dm-locus-research-v1',
          'calibrated': false,
          'locusCount': results.length,
          'results': results.map((r) => r.toDiagnosticMap()).toList(),
          if (timing != null) 'debugTiming': timing
        }));
  }
  static SnpApiPayload? fromCompleted(SnpComputeController c) {
    if (c.busy ||
        c.status != 'completed' ||
        c.resultContext == null ||
        c.resultInput == null ||
        c.completed != c.total ||
        c.locusResults.length != c.total) {
      return null;
    }
    return SnpApiPayload.build(
        context: c.resultContext!,
        input: c.resultInput!,
        results: c.locusResults,
        jobId: c.resultJobId,
        timing: c.batchTiming);
  }
}
