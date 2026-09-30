import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geneapp/snp_compute.dart';
import 'package:geneapp/snp_compute_page.dart';
import 'package:geneapp/snp_sets.dart';
import 'snp_compute_test.dart' as fixtures;

class NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('Offline workflow must not call HTTP/LLM');
}

void main() {
  testWidgets('default alcohol selector loads and submits exact 143 queries',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final p = fixtures.FakeSnpPlatform();
    final c = SnpComputeController(platform: p, supported: true);
    await tester.pumpWidget(MaterialApp(home: SnpComputePage(controller: c)));
    await tester.pumpAndSettle();
    expect(find.text('已載入 143 筆等位查詢（77 位點）'), findsOneWidget);
    expect(find.text('酒精代謝（77 位點／143 查詢）'), findsOneWidget);
    expect(find.text('貼入 FASTA'), findsNothing);
    await tester.tap(find.text('開始 C 離線運算'));
    await tester.pump();
    final expected = await SnpSets.alcohol.load();
    expect(p.lastQueries.map((q) => q.toMap()).toList(),
        expected.map((q) => q.toMap()).toList());
    expect(c.total, 143);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await p.stream.close();
  });
  testWidgets(
      'offline alcohol flow completes 143 queries with captured set and debug timings',
      (tester) async {
    final before = HttpOverrides.current;
    HttpOverrides.global = NoNetwork();
    addTearDown(() => HttpOverrides.global = before);
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final p = fixtures.FakeSnpPlatform();
    final c = SnpComputeController(platform: p, supported: true);
    await tester.pumpWidget(MaterialApp(home: SnpComputePage(controller: c)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Debug：結果與分段計時'));
    await tester.pump();
    await tester.tap(find.text('開始 C 離線運算'));
    await tester.pump();
    expect(p.lastQueries.length, 143);
    expect(p.lastDebug, true);
    final rows = p.lastQueries
        .map((q) => {
              ...fixtures.result(),
              'id': q.id,
              'refAllele': q.ref,
              'altAllele': q.alt,
              'debugTiming': {
                'ioMs': 1.0,
                'countMs': 2.0,
                'genotypeMs': .5,
                'nativeOverheadMs': .5,
                'nativeTotalMs': 4.0
              },
            })
        .toList();
    p.stream.add({
      'jobId': 'job1',
      'revision': 2,
      'status': 'completed',
      'completed': 143,
      'total': 143,
      'results': rows,
      'debugTiming': {
        'setupIoMs': 3.0,
        'queryIoMs': 143.0,
        'countMs': 286.0,
        'genotypeMs': 71.5,
        'overheadMs': 80.5,
        'totalMs': 584.0
      }
    });
    await tester.pump();
    expect(c.results.length, 143);
    expect(c.completed, 143);
    expect(c.status, 'completed');
    expect(c.resultInput!.version, SnpSets.alcohol.version);
    expect(c.debugReport, contains(SnpSets.alcohol.version));
    expect(c.debugReport, isNot(contains('sourceId')));
    await tester.scrollUntilVisible(find.text('完成 143 / 143 筆查詢'), 300);
    expect(find.textContaining('總耗時：584.000 ms'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('進階：自訂查詢'), -300);
    await tester.tap(find.text('進階：自訂查詢'));
    await tester.pump();
    expect(c.results, isEmpty);
    expect(c.debugReport, isNull);
    expect(c.resultInput, isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await p.stream.close();
  });
  testWidgets(
      'stale panel load cannot change advanced mode and unavailable sets are disabled',
      (tester) async {
    final load = Completer<List<SnpQuery>>();
    final p = fixtures.FakeSnpPlatform();
    final c = SnpComputeController(platform: p, supported: true);
    await tester.pumpWidget(MaterialApp(
        home: SnpComputePage(controller: c, setLoader: (_) => load.future)));
    await tester.pump();
    final selector = tester.widget<DropdownButtonFormField<String>>(
        find.byKey(const ValueKey('snp-set-selector')));
    // The dropdown's actual items carry the availability contract.
    final dropdown = tester.widget<DropdownButton<String>>(find.descendant(
        of: find.byKey(const ValueKey('snp-set-selector')),
        matching: find.byType(DropdownButton<String>)));
    expect(selector.enabled, true);
    expect(dropdown.items!.where((item) => item.enabled).length, 1);
    await tester.ensureVisible(find.text('進階：自訂查詢'));
    await tester.tap(find.text('進階：自訂查詢'));
    await tester.pump();
    load.complete([fixtures.query]);
    await tester.pump();
    expect(find.text('已載入 1 筆等位查詢（77 位點）'), findsNothing);
    expect(find.text('SNP 標識'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await p.stream.close();
  });
  testWidgets('failed set loading disables run without manual fallback',
      (tester) async {
    final p = fixtures.FakeSnpPlatform();
    final c = SnpComputeController(platform: p, supported: true);
    await tester.pumpWidget(MaterialApp(
        home: SnpComputePage(
            controller: c,
            setLoader: (_) =>
                Future.error(const FormatException('invalid asset')))));
    await tester.pumpAndSettle();
    expect(find.textContaining('SNP set 載入失敗'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('開始 C 離線運算'), 300);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, '開始 C 離線運算'))
            .onPressed,
        isNull);
    expect(p.runCalls, 0);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await p.stream.close();
  });
  testWidgets('debug is opt-in and displays/copies validated report',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final p = fixtures.FakeSnpPlatform();
    final c = SnpComputeController(platform: p, supported: true);
    await tester.pumpWidget(MaterialApp(home: SnpComputePage(controller: c)));
    await tester.pump();
    final toggle = find.widgetWithText(SwitchListTile, 'Debug：結果與分段計時');
    expect(tester.widget<SwitchListTile>(toggle).value, false);
    await tester.tap(toggle);
    await tester.pump();
    await c.run([fixtures.query]);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
    p.stream.add({
      'jobId': 'job1',
      'revision': 2,
      'status': 'completed',
      'completed': 1,
      'total': 1,
      'results': [
        {
          ...fixtures.result(),
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
    await tester.pump();
    expect(find.textContaining('總耗時：22.000 ms'), findsOneWidget);
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.tap(find.text('複製 debug 結果'));
    await tester.pump();
    expect(copied, c.debugReport);
    expect(copied, isNot(contains('sourceId')));
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await p.stream.close();
  });
  testWidgets('invalid query never starts C computation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final p = fixtures.FakeSnpPlatform();
    final c = SnpComputeController(platform: p, supported: true);
    await tester.pumpWidget(MaterialApp(home: SnpComputePage(controller: c)));
    await tester.pump();
    await tester.tap(find.text('進階：自訂查詢'));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('開始 C 離線運算'), 300,
        scrollable: find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
    await tester.tap(find.text('開始 C 離線運算'));
    await tester.pump();
    expect(p.runCalls, 0);
    expect(find.textContaining('查詢須為'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await p.stream.close();
  });
  testWidgets('shows research warning and native depth8 no-call',
      (tester) async {
    final p = fixtures.FakeSnpPlatform();
    final c = SnpComputeController(platform: p, supported: true);
    await c.start();
    await c.run([fixtures.query]);
    p.stream.add({
      'jobId': 'job1',
      'revision': 2,
      'status': 'completed',
      'completed': 1,
      'total': 1,
      'results': [fixtures.result()]
    });
    await tester.pumpWidget(MaterialApp(home: SnpComputePage(controller: c)));
    await tester.pump();
    expect(find.textContaining('未校準'), findsWidgets);
    expect(find.textContaining('非 GATK'), findsWidgets);
    await tester.scrollUntilVisible(find.textContaining('有效深度 8'), 400,
        scrollable: find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
    expect(find.textContaining('有效深度 8'), findsOneWidget);
    expect(find.textContaining('REF C: 4 / ALT T: 4'), findsOneWidget);
    expect(find.text('來源：USB / gene'), findsOneWidget);
    expect(find.textContaining('GT ./. '), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await p.stream.close();
  });
  testWidgets('unsupported page is explicit', (tester) async {
    final c = SnpComputeController(supported: false);
    await tester.pumpWidget(MaterialApp(home: SnpComputePage(controller: c)));
    await tester.pump();
    expect(find.textContaining('僅支援 Android'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
