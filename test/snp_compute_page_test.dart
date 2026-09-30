import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geneapp/snp_compute.dart';
import 'package:geneapp/snp_compute_page.dart';
import 'snp_compute_test.dart' as fixtures;

void main() {
  testWidgets('invalid query never starts C computation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final p = fixtures.FakeSnpPlatform();
    final c = SnpComputeController(platform: p, supported: true);
    await tester.pumpWidget(MaterialApp(home: SnpComputePage(controller: c)));
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
