import 'package:flutter_test/flutter_test.dart';
import 'package:geneapp/snp_compute.dart';
import 'package:geneapp/snp_api_payload.dart';
import 'snp_locus_compute_test.dart' show locusWire;

SnpLocusResult row(int n, {bool noCall = false}) {
  final q = SnpLocus.group([
    SnpQuery.validated(
        id: 'rs${n + 1}_4_${100 + n}_T_C',
        sequence: 'T' * 301,
        ref: 'T',
        alt: 'C')
  ]).single;
  final m = locusWire(q, noCall: noCall);
  if (!noCall) {
    m['bestGenotype'] = [0, 2];
    m['gt'] = '0/2';
    m['actualGenotype'] = 'TC';
    m['posterior'] = [
      .001,
      .001,
      .991,
      .001,
      .001,
      .001,
      .001,
      .001,
      .001,
      .001
    ];
  }
  return SnpLocusResult.fromMap(m);
}

void main() {
  test(
      'API exact contract exports one actual-base GT per locus and 77/70/7 counts',
      () {
    final export = SnpApiPayload.build(
        context: const SnpChatContext('person', '我能喝酒嗎', '酒精'),
        input: const SnpInputIdentity('alcohol', '酒精代謝', 'v1'),
        results: List.generate(77, (i) => row(i, noCall: i >= 70)));
    final request = export.request;
    expect(request.keys.toSet(), {
      'user_id',
      'query',
      'topic',
      'SNP_list',
      'snp_list',
      'variants',
      'variant_input_count',
      'variant_used_count',
      'no_call_count',
      'yuguard'
    });
    expect(request['variants'], (request['SNP_list']));
    expect(request['snp_list'], request['variants']);
    expect((request['variants'] as List).length, 70);
    expect((request['variants'] as List).first, 'rs1-TC');
    expect(request['variant_input_count'], 77);
    expect(request['variant_used_count'], 70);
    expect(request['no_call_count'], 7);
    expect(request['yuguard'], isNull);
    expect(request['query'], '我能喝酒嗎');
    expect(export.apiJson, isNot(contains('sourceId')));
    expect(export.diagnosticJson, contains('"schemaVersion": 2'));
    expect(export.diagnosticJson, contains('LOW_POSTERIOR'));
    expect(export.diagnosticJson, isNot(contains('usb1')));
    expect(export.diagnosticJson, isNot(contains('debugTiming')));
  });
  test('empty identity, empty batch and duplicate rsID are rejected', () {
    final r = row(0),
        q = SnpLocus.group([
          SnpQuery.validated(
              id: 'rs1_4_200_T_C', sequence: 'T' * 301, ref: 'T', alt: 'C')
        ]).single;
    for (final rows in [
      <SnpLocusResult>[],
      [r, r],
      [r, SnpLocusResult.fromMap(locusWire(q))]
    ]) {
      expect(
          () => SnpApiPayload.build(
              context: const SnpChatContext('p', 'q', '酒精'),
              input: const SnpInputIdentity('a', 'a', 'v1'),
              results: rows),
          throwsFormatException);
    }
    expect(
        () => SnpApiPayload.build(
            context: const SnpChatContext('', 'q', '酒精'),
            input: const SnpInputIdentity('a', 'a', 'v1'),
            results: [r]),
        throwsFormatException);
  });
}
