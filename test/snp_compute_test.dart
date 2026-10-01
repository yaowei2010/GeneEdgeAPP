import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geneapp/snp_compute.dart';

String get sequence => '${'A' * 150}C${'A' * 150}';
SnpQuery get query =>
    SnpQuery.validated(id: 'rs1', sequence: sequence, ref: 'C', alt: 'T');
Map<String, Object?> sourceWire(int revision) => {
      'revision': revision,
      'sources': [
        {'id': 'usb1', 'label': 'USB / gene'}
      ],
      'volumes': [],
      'selectedSourceId': 'usb1'
    };
Map<String, Object?> result() => {
      'id': 'rs1',
      'refAllele': 'C',
      'altAllele': 'T',
      'sourceId': 'usb1',
      'sourceLabel': 'USB / gene',
      'total': 108,
      'ref': 4,
      'alt': 4,
      'ambiguous': 50,
      'coverageOnly': 50,
      'skippedBuckets': 0,
      'posterior': [.1, .8, .1],
      'gt': './.',
      'effectiveDepth': 8,
      'noCallReason': 'LOW_DEPTH',
      'modelVersion': 'bb-research-v1',
      'calibrated': false,
      'parameters': {
        'epsilon': .01,
        'rho': .02,
        'priors': [1 / 3, 1 / 3, 1 / 3],
        'minDepth': 10,
        'minPosterior': .99
      }
    };

class FakeSnpPlatform implements SnpComputePlatform {
  int runCalls = 0;
  bool lastDebug = false;
  List<SnpQuery> lastQueries = [];
  final stream = StreamController<Object?>.broadcast(sync: true);
  Future<Object?> Function()? onRun;
  @override
  Stream<Object?> get events => stream.stream;
  @override
  Future<Object?> sources() async => sourcesMap();
  Map<String, Object?> sourcesMap() => sourceWire(1);
  @override
  Future<Object?> requestAccess(String id) async => sourcesMap();
  @override
  Future<Object?> selectSource(String id) async => sourcesMap();
  @override
  Future<Object?> run(String id, List<SnpQuery> queries,
      {bool debugEnabled = false}) async {
    runCalls++;
    lastDebug = debugEnabled;
    lastQueries = List.of(queries);
    return onRun == null ? {'jobId': 'job1'} : await onRun!();
  }

  @override
  Future<void> cancel() async {}
  @override
  Future<String?> pickPanel() async => null;
}

class MutableSourcePlatform extends FakeSnpPlatform {
  Future<Object?> Function()? onSources;
  @override
  Future<Object?> sources() => onSources?.call() ?? super.sources();
  Map<String, Object?> snapshot = sourceWire(1);
  Future<Object?> Function()? onSelect;
  @override
  Map<String, Object?> sourcesMap() => snapshot;
  @override
  Future<Object?> selectSource(String id) async =>
      onSelect == null ? snapshot : await onSelect!();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('scanning snapshot is not permission to confirm or compute', () async {
    final p = MutableSourcePlatform();
    final c = SnpComputeController(platform: p, supported: true);
    await c.start();
    p.stream
        .add({...sourceWire(2), 'status': 'sourcesSnapshot', 'scanning': true});
    expect(c.sourceScanning, true);
    expect(await c.confirmUsbSource(), false);
    await c.run([query]);
    expect(p.runCalls, 0);
    c.dispose();
    await p.stream.close();
  });
  test('late scan reply and error after removal do not restore attachment',
      () async {
    for (final error in [false, true]) {
      final p = MutableSourcePlatform();
      final c = SnpComputeController(platform: p, supported: true);
      await c.start();
      final reply = Completer<Object?>();
      p.onSources = () => reply.future;
      final scanning = c.refresh();
      p.stream.add(
          {'revision': 2, 'status': 'invalidated', 'errorCode': 'USB_REMOVED'});
      if (error) {
        reply.completeError(PlatformException(code: 'CANCELLED'));
      } else {
        reply.complete(sourceWire(3));
      }
      await scanning;
      expect(c.sources, isEmpty);
      expect(c.errorCode, 'USB_REMOVED');
      c.dispose();
      await p.stream.close();
    }
  });
  test('invalid permission metadata clears an already confirmed source',
      () async {
    final p = MutableSourcePlatform();
    final c = SnpComputeController(platform: p, supported: true);
    await c.start();
    await c.confirmUsbSource();
    expect(c.sourceConfirmed, true);
    p.snapshot = {
      ...sourceWire(2),
      'volumes': [
        {
          'id': 'usb-volume',
          'label': 'USB',
          'authorized': true,
          'authorizationScopes': [42]
        }
      ]
    };
    await c.refresh();
    expect(c.errorCode, 'INVALID_FORMAT');
    expect(c.sourceConfirmed, false);
    c.dispose();
    await p.stream.close();
  });
  test(
      'source selection callback after removal cannot restore stale attachment',
      () async {
    final p = MutableSourcePlatform();
    final reply = Completer<Object?>();
    final c = SnpComputeController(platform: p, supported: true);
    await c.start();
    p.onSelect = () => reply.future;
    final selecting = c.selectSource('usb1');
    p.stream.add(
        {'revision': 2, 'status': 'invalidated', 'errorCode': 'USB_REMOVED'});
    reply.complete(sourceWire(3));
    await selecting;
    expect(c.sources, isEmpty);
    expect(c.selectedSourceId, isNull);
    expect(c.sourceConfirmed, false);
    c.dispose();
    await p.stream.close();
  });
  test('USB confirmation is explicit, attachment scoped and does not run C',
      () async {
    final p = FakeSnpPlatform();
    final c = SnpComputeController(platform: p, supported: true);
    await c.start();
    expect(c.sourceConfirmed, false);
    expect(await c.confirmUsbSource(), true);
    expect(c.sourceConfirmed, true);
    expect(p.runCalls, 0);
    p.stream.add(
        {'revision': 2, 'status': 'invalidated', 'errorCode': 'USB_REMOVED'});
    expect(c.sourceConfirmed, false);
    expect(c.sources, isEmpty);
    c.dispose();
    await p.stream.close();
  });
  test(
      'cancel reports measured elapsed but never accepts late debug completion',
      () async {
    final p = FakeSnpPlatform();
    final c = SnpComputeController(platform: p, supported: true);
    await c.start();
    c.setDebugEnabled(true);
    await c.run([query]);
    await c.cancel();
    p.stream.add({
      'jobId': 'job1',
      'revision': 2,
      'status': 'cancelled',
      'completed': 0,
      'total': 1,
      'elapsedMs': 4.0
    });
    expect(c.elapsedMs, 4.0);
    expect(c.debugReport, isNull);
    expect(c.batchTiming, isNull);
    p.stream.add({
      'jobId': 'job1',
      'revision': 3,
      'status': 'completed',
      'completed': 1,
      'total': 1,
      'results': [result()]
    });
    expect(c.status, 'cancelled');
    expect(c.results, isEmpty);
    expect(c.debugReport, isNull);
    p.stream.add({
      'jobId': 'job1',
      'revision': 4,
      'status': 'invalidated',
      'errorCode': 'USB_REMOVED',
      'elapsedMs': 5.0
    });
    expect(c.status, 'invalidated');
    expect(c.selectedSourceId, isNull);
    expect(c.elapsedMs, 5.0);
    c.dispose();
    await p.stream.close();
  });
  test('debug snapshot prints safe results and non-overlapping stage times',
      () async {
    final p = FakeSnpPlatform();
    final c = SnpComputeController(platform: p, supported: true);
    expect(c.debugEnabled, false);
    await c.start();
    c.setDebugEnabled(true);
    await c.run([query]);
    c.setDebugEnabled(false);
    expect(p.lastDebug, true);
    expect(c.debugEnabled, true);
    p.stream.add({
      'jobId': 'job1',
      'revision': 2,
      'status': 'completed',
      'completed': 1,
      'total': 1,
      'results': [
        {
          ...result(),
          'debugTiming': {
            'ioMs': 7.0,
            'countMs': 5.0,
            'genotypeMs': 2.0,
            'nativeOverheadMs': 1.0,
            'nativeTotalMs': 15.0
          }
        }
      ],
      'debugTiming': {
        'setupIoMs': 3.0,
        'queryIoMs': 7.0,
        'countMs': 5.0,
        'genotypeMs': 2.0,
        'overheadMs': 5.0,
        'totalMs': 22.0
      }
    });
    expect(c.batchTiming!['totalMs'], 22.0);
    expect(c.results.single.debugTiming!['countMs'], 5.0);
    expect(c.debugReport, contains('"schemaVersion": 1'));
    expect(c.debugReport, contains('"gt": "./."'));
    expect(c.debugReport, isNot(contains('sourceId')));
    expect(c.debugReport, isNot(contains(sequence)));
    c.clearResults();
    expect(c.debugReport, isNull);
    expect(c.results, isEmpty);
    c.dispose();
    await p.stream.close();
  });
  test(
      'debug rejects invalid timing, mismatched batch sum and missing instrumentation',
      () async {
    for (final bad in [-1.0, double.nan, double.infinity, 23.0, null]) {
      final p = FakeSnpPlatform();
      final c = SnpComputeController(platform: p, supported: true);
      await c.start();
      c.setDebugEnabled(true);
      await c.run([query]);
      p.stream.add({
        'jobId': 'job1',
        'revision': 2,
        'status': 'completed',
        'completed': 1,
        'total': 1,
        'results': [
          {
            ...result(),
            'debugTiming': {
              'ioMs': 7.0,
              'countMs': 5.0,
              'genotypeMs': 2.0,
              'nativeOverheadMs': 1.0,
              'nativeTotalMs': 15.0
            }
          }
        ],
        if (bad != null)
          'debugTiming': {
            'setupIoMs': 3.0,
            'queryIoMs': 7.0,
            'countMs': 5.0,
            'genotypeMs': 2.0,
            'overheadMs': 5.0,
            'totalMs': bad
          }
      });
      expect(c.errorCode, 'INVALID_FORMAT');
      expect(c.debugReport, isNull);
      c.dispose();
      await p.stream.close();
    }
  });
  test('rejects missing provenance and invalid allele definitions', () {
    for (final key in ['refAllele', 'altAllele', 'sourceId', 'sourceLabel']) {
      final missing = Map<String, Object?>.of(result())..remove(key);
      expect(() => SnpResult.fromMap(missing), throwsFormatException);
    }
    expect(() => SnpResult.fromMap({...result(), 'altAllele': 'C'}),
        throwsFormatException);
    expect(() => SnpResult.fromMap({...result(), 'refAllele': 'N'}),
        throwsFormatException);
  });
  test('adapter sends queries to native channel, never computes genotypes',
      () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannelSnpComputePlatform.methods,
            (call) async {
      calls.add(call);
      return call.method == 'run' ? {'jobId': 'job1'} : null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            MethodChannelSnpComputePlatform.methods, null));
    final p = MethodChannelSnpComputePlatform();
    await p.sources();
    await p.requestAccess('volume');
    await p.selectSource('usb1');
    await p.run('usb1', [query]);
    await p.cancel();
    await p.pickPanel();
    expect(calls.map((c) => c.method), [
      'sources',
      'requestAccess',
      'selectSource',
      'run',
      'cancel',
      'pickPanel'
    ]);
    expect(calls[3].arguments, {
      'sourceId': 'usb1',
      'queries': [query.toMap()]
    });
  });
  test('progress is job scoped and native error clears evidence', () async {
    final p = FakeSnpPlatform();
    final c = SnpComputeController(platform: p, supported: true);
    await c.start();
    await c.run([query]);
    p.stream.add({
      'jobId': 'old',
      'revision': 999,
      'status': 'completed',
      'completed': 1,
      'total': 1,
      'results': [result()]
    });
    expect(c.status, 'running');
    p.stream.add({
      'jobId': 'job1',
      'revision': 2,
      'status': 'running',
      'completed': 0,
      'total': 1
    });
    expect(c.completed, 0);
    expect(c.total, 1);
    p.stream.add({
      'jobId': 'job1',
      'revision': 3,
      'status': 'error',
      'completed': 0,
      'total': 1,
      'errorCode': 'IO_ERROR'
    });
    expect(c.status, 'error');
    expect(c.errorCode, 'IO_ERROR');
    expect(c.results, isEmpty);
    c.dispose();
    await p.stream.close();
  });
  test('malformed event fails closed and cannot later become success',
      () async {
    final p = FakeSnpPlatform();
    final c = SnpComputeController(platform: p, supported: true);
    await c.start();
    await c.run([query]);
    p.stream.add({
      'jobId': 'job1',
      'revision': 2,
      'status': 'completed',
      'completed': 1,
      'total': 1,
      'results': [
        {...result(), 'total': 109}
      ]
    });
    expect(c.status, 'error');
    p.stream.add({
      'jobId': 'job1',
      'revision': 3,
      'status': 'completed',
      'completed': 1,
      'total': 1,
      'results': [result()]
    });
    expect(c.status, 'error');
    expect(c.results, isEmpty);
    c.dispose();
    await p.stream.close();
  });
  test('validates entire panel before any native work', () {
    expect(() => SnpQuery.parseFasta('>rs1_C_T\n$sequence\n>rs2_A_G\nAAA'),
        throwsFormatException);
    expect(() => SnpQuery.parseFasta('>rs1_C_T\n${'N' * 301}'),
        throwsFormatException);
    expect(() => SnpQuery.parseFasta('>rs1_C_C\n$sequence'),
        throwsFormatException);
    expect(
        () => SnpQuery.parseFasta(
            List.generate(3001, (i) => '>rs${i}_C_T\n$sequence').join('\n')),
        throwsFormatException);
  });
  test('query validates centers and rejects malformed or duplicate FASTA', () {
    expect(query.toMap()['sequence'], sequence);
    expect(
        () => SnpQuery.validated(
            id: 'x', sequence: 'A' * 301, ref: 'C', alt: 'T'),
        throwsFormatException);
    expect(
        () => SnpQuery.parseFasta('>rs1_C_T\n$sequence\n>rs1_C_T\n$sequence'),
        throwsFormatException);
    expect(
        SnpQuery.parseFasta(
                '>rs1_C_T\n${sequence.substring(0, 100)}\n${sequence.substring(100)}')
            .single
            .id,
        'rs1');
  });
  test(
      'result validates partition and effective depth, preserves native no call',
      () {
    final parsed = SnpResult.fromMap(result());
    expect(parsed.effectiveDepth, 8);
    expect(parsed.gt, './.');
    expect(() => SnpResult.fromMap({...result(), 'total': 109}),
        throwsFormatException);
    expect(() => SnpResult.fromMap({...result(), 'effectiveDepth': 108}),
        throwsFormatException);
  });
  test('early completion buffered; cancel suppresses late successful events',
      () async {
    final p = FakeSnpPlatform();
    final c = SnpComputeController(platform: p, supported: true);
    await c.start();
    p.onRun = () async {
      p.stream.add({
        'jobId': 'job1',
        'revision': 2,
        'status': 'completed',
        'completed': 1,
        'total': 1,
        'results': [result()]
      });
      return {'jobId': 'job1'};
    };
    await c.run([query]);
    expect(c.status, 'completed');
    expect(c.results.single.effectiveDepth, 8);
    await c.cancel();
    p.stream.add({
      'jobId': 'job1',
      'revision': 3,
      'status': 'completed',
      'completed': 1,
      'total': 1,
      'results': [result()]
    });
    expect(c.results, isEmpty);
    expect(c.status, 'cancelled');
    c.dispose();
    await p.stream.close();
  });
  test('rejects older revision and invalidates results on source refresh',
      () async {
    final p = FakeSnpPlatform();
    final c = SnpComputeController(platform: p, supported: true);
    await c.start();
    await c.run([query]);
    p.stream.add({
      'jobId': 'job1',
      'revision': 3,
      'status': 'running',
      'completed': 0,
      'total': 1
    });
    p.stream.add({
      'jobId': 'job1',
      'revision': 2,
      'status': 'completed',
      'completed': 1,
      'total': 1,
      'results': [result()]
    });
    expect(c.status, 'running');
    p.stream.add(
        {'revision': 4, 'status': 'invalidated', 'errorCode': 'USB_REMOVED'});
    expect(c.results, isEmpty);
    expect(c.status, 'invalidated');
    c.dispose();
    await p.stream.close();
  });
  test('non Android never starts native platform', () async {
    final c = SnpComputeController(supported: false);
    await c.start();
    expect(c.status, 'unsupported');
    c.dispose();
  });
}
