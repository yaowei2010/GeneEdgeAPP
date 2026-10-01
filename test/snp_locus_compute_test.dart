import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:geneapp/snp_compute.dart';
import 'package:geneapp/snp_sets.dart';
import 'package:geneapp/snp_api_payload.dart';
import 'snp_compute_test.dart' show FakeSnpPlatform;

class FakeLocusPlatform extends FakeSnpPlatform
    implements SnpLocusComputePlatform {
  int sourceCalls = 0;
  @override
  Future<Object?> sources() {
    sourceCalls++;
    return super.sources();
  }

  @override
  Future<Object?> runLoci(String sourceId, List<SnpQuery> queries,
          {bool debugEnabled = false}) =>
      run(sourceId, queries, debugEnabled: debugEnabled);
}

Map<String, Object?> locusWire(SnpLocus q,
        {bool debug = false, bool noCall = false}) =>
    {
      'id': q.id,
      'rsId': q.rsId,
      'chromosome': q.chromosome,
      'position': q.position,
      'refAllele': q.ref,
      'sourceId': 'usb1',
      'sourceLabel': 'USB / gene',
      'total': 200,
      'baseCounts': [100, 100, 0, 0],
      'alleles': q.alleles,
      'ambiguous': 0,
      'coverageOnly': 0,
      'skippedBuckets': 0,
      'effectiveDepth': 200,
      'posterior': noCall
          ? [.051, .541, .051, .051, .051, .051, .051, .051, .051, .051]
          : [.001, .991, .001, .001, .001, .001, .001, .001, .001, .001],
      'bestGenotype': [0, 1],
      'bestPosterior': noCall ? .541 : .991,
      'logScoreGap': 6.9,
      'gt': noCall ? './.' : '0/1',
      'actualGenotype': noCall ? null : '${q.alleles[0]}${q.alleles[1]}',
      'noCallReason': noCall ? 'LOW_POSTERIOR' : null,
      'modelVersion': 'dm-locus-research-v1',
      'calibrated': false,
      'parameters': {
        'epsilon': .01,
        'rho': .02,
        'priors': List.filled(10, .1),
        'minDepth': 10,
        'minPosterior': .99
      },
      if (debug)
        'debugTiming': {
          'ioMs': 7.0,
          'countMs': 5.0,
          'genotypeMs': 2.0,
          'nativeOverheadMs': 1.0,
          'nativeTotalMs': 15.0
        }
    };
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('143 references group to 77 common loci; mismatched flanks/ref reject',
      () async {
    final queries = SnpSets.alcohol
        .parse(await File(SnpSets.alcohol.assetPath!).readAsBytes());
    final loci = SnpLocus.group(queries);
    expect(loci.length, 77);
    final q = loci.singleWhere((q) => q.rsId == 'rs1229984');
    expect(q.queries.length, 3);
    expect(q.ref, 'T');
    expect(q.alleles, ['T', 'A', 'C', 'G']);
    final first = q.queries.first;
    final wrong = SnpQuery.validated(
        id: first.id,
        sequence:
            '${first.sequence[0] == 'A' ? 'C' : 'A'}${first.sequence.substring(1)}',
        ref: first.ref,
        alt: first.alt);
    expect(() => SnpLocus.group([wrong, ...q.queries.skip(1)]),
        throwsFormatException);
    final wrongRef = SnpQuery.validated(
        id: 'rs1_1_1_A_C', sequence: 'A' * 301, ref: 'C', alt: 'A');
    expect(() => SnpLocus.group([wrongRef]), throwsFormatException);
  });
  test(
      'locus controller captures context, accepts 77 rows, invalidates stale export',
      () async {
    final queries = SnpSets.alcohol
        .parse(await File(SnpSets.alcohol.assetPath!).readAsBytes());
    final loci = SnpLocus.group(queries);
    final p = FakeLocusPlatform();
    final c = SnpComputeController(platform: p, supported: true);
    await c.start();
    c.setDebugEnabled(true);
    await c.runLoci(queries,
        input: SnpSets.alcohol.identity,
        context: const SnpChatContext('person', '酒精問題', '酒精'));
    expect(c.total, 77);
    expect(p.lastQueries.length, 143);
    expect(p.lastDebug, true);
    p.stream.add({
      'jobId': 'job1',
      'revision': 2,
      'status': 'completed',
      'completed': 77,
      'total': 77,
      'mode': 'locus',
      'results': loci.map((q) => locusWire(q, debug: true)).toList(),
      'debugTiming': {
        'setupIoMs': 3.0,
        'queryIoMs': 539.0,
        'countMs': 385.0,
        'genotypeMs': 154.0,
        'overheadMs': 82.0,
        'totalMs': 1163.0
      }
    });
    expect(c.status, 'completed');
    expect(c.locusResults.length, 77);
    expect(c.resultContext!.query, '酒精問題');
    expect(jsonDecode(c.debugReport!)['schemaVersion'], 2);
    expect(c.debugReport, isNot(contains('usb1')));
    expect(SnpApiPayload.fromCompleted(c)!.diagnostic['jobId'], 'job1');
    c.clearResults();
    expect(c.locusResults, isEmpty);
    expect(c.resultContext, isNull);
    p.stream.add({
      'jobId': 'job1',
      'revision': 3,
      'status': 'completed',
      'completed': 77,
      'total': 77,
      'mode': 'locus',
      'results': loci.map(locusWire).toList()
    });
    expect(c.locusResults, isEmpty);
    c.dispose();
    await p.stream.close();
  });
  test(
      'locus payload rejects wrong genotype, duplicate allele, source and nonfinite time',
      () {
    final q = SnpLocus.group([
      SnpQuery.validated(
          id: 'rs1_1_1_T_C', sequence: 'T' * 301, ref: 'T', alt: 'C')
    ]).single;
    final valid = locusWire(q);
    expect(SnpLocusResult.fromMap(valid).actualGenotype, 'TA');
    for (final bad in [
      {...valid, 'actualGenotype': 'CC'},
      {
        ...valid,
        'alleles': ['T', 'A', 'C', 'T']
      },
      {...valid, 'sourceId': ''},
      {...valid, 'bestPosterior': .2},
      {
        ...valid,
        'gt': './.',
        'actualGenotype': null,
        'noCallReason': 'ZERO_DEPTH'
      },
      {
        ...valid,
        'baseCounts': [100, 101, 0, 0]
      },
      {
        ...locusWire(q, debug: true),
        'debugTiming': {'ioMs': double.nan}
      }
    ]) {
      expect(() => SnpLocusResult.fromMap(bad), throwsFormatException);
    }
  });
  test('method channel locus run is explicit and leaves query wire unchanged',
      () async {
    final calls = <Map>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannelSnpComputePlatform.methods,
            (call) async {
      calls.add(call.arguments as Map);
      return {'jobId': '1'};
    });
    final p = MethodChannelSnpComputePlatform();
    final q = SnpQuery.validated(
        id: 'rs1_1_1_A_C', sequence: 'A' * 301, ref: 'A', alt: 'C');
    await p.run('usb', [q]);
    await p.runLoci('usb', [q]);
    expect(calls[0].containsKey('mode'), false);
    expect(calls[1]['mode'], 'locus');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            MethodChannelSnpComputePlatform.methods, null);
  });
  test('mounted USB source-change event refreshes without starting a job',
      () async {
    final p = FakeLocusPlatform();
    final c = SnpComputeController(platform: p, supported: true);
    await c.start();
    p.stream.add({'status': 'sourcesChanged', 'revision': 2});
    await Future<void>.delayed(Duration.zero);
    expect(c.status, isNot('error'));
    expect(p.sourceCalls, 2);
    expect(p.runCalls, 0);
    c.dispose();
    await p.stream.close();
  });
  test('locus debug-off export and cancel/source invalidation reject late jobs',
      () async {
    final q = SnpQuery.validated(
        id: 'rs1_1_1_A_C', sequence: 'A' * 301, ref: 'A', alt: 'C');
    final locus = SnpLocus.group([q]).single;
    for (final action in ['cancel', 'source', 'dispose']) {
      final p = FakeLocusPlatform();
      final c = SnpComputeController(platform: p, supported: true);
      await c.start();
      await c.runLoci([q],
          input: SnpSets.alcohol.identity,
          context: const SnpChatContext('p', 'q', '酒精'));
      final event = {
        'jobId': 'job1',
        'revision': 2,
        'status': 'completed',
        'completed': 1,
        'total': 1,
        'mode': 'locus',
        'results': [locusWire(locus)]
      };
      if (action == 'cancel') {
        await c.cancel();
      } else {
        p.stream.add(event);
        final payload = SnpApiPayload.fromCompleted(c)!;
        expect(payload.request['variant_used_count'], 1);
        expect(payload.diagnostic['jobId'], 'job1');
        expect(payload.diagnostic.containsKey('debugTiming'), false);
        if (action == 'source') {
          p.stream.add({
            'revision': 3,
            'status': 'invalidated',
            'errorCode': 'USB_REMOVED'
          });
        } else {
          c.dispose();
        }
      }
      p.stream.add({...event, 'revision': 4});
      expect(c.locusResults, isEmpty);
      expect(c.resultContext, isNull);
      expect(c.resultJobId, isNull);
      expect(SnpApiPayload.fromCompleted(c), isNull);
      if (action != 'dispose') c.dispose();
      await p.stream.close();
    }
  });
  test('locus controller rejects mismatched source and query-mode completion',
      () async {
    final q = SnpQuery.validated(
        id: 'rs1_1_1_A_C', sequence: 'A' * 301, ref: 'A', alt: 'C');
    for (final bad in ['source', 'mode', 'duplicate']) {
      final p = FakeLocusPlatform();
      final c = SnpComputeController(platform: p, supported: true);
      await c.start();
      await c.runLoci([q],
          input: SnpSets.alcohol.identity,
          context: const SnpChatContext('p', 'q', '酒精'));
      final row = locusWire(SnpLocus.group([q]).single);
      if (bad == 'source') row['sourceId'] = 'other';
      p.stream.add({
        'jobId': 'job1',
        'revision': 2,
        'status': 'completed',
        'completed': 1,
        'total': 1,
        'mode': bad == 'mode' ? 'query' : 'locus',
        'results': bad == 'duplicate' ? [row, row] : [row]
      });
      expect(c.errorCode, 'INVALID_FORMAT');
      expect(c.locusResults, isEmpty);
      c.dispose();
      await p.stream.close();
    }
  });
}
