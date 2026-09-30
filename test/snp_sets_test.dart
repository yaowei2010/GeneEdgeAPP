import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:geneapp/snp_sets.dart';

void main() {
  test(
      'bundled alcohol hash and 143 queries preserve original locus and alleles',
      () async {
    final set = SnpSets.alcohol;
    final bytes = await File(set.assetPath!).readAsBytes();
    final queries = set.parse(bytes);
    expect(queries.length, 143);
    expect(queries.map((q) => q.id).toSet().length, 143);
    expect(
        queries
            .map((q) => q.id.replaceFirst(RegExp(r'_[ACGT]_[ACGT]$'), ''))
            .toSet()
            .length,
        77);
    final q = queries.singleWhere((q) => q.id == 'rs1229984_4_100239319_T_C');
    expect(
        queries.where((q) => q.id.startsWith('rs1229984_4_100239319_')).length,
        3);
    expect(q.ref, 'T');
    expect(q.alt, 'C');
    expect(q.sequence.length, 301);
    expect(queries.every((q) => q.sequence.length == 301), true);
    expect(SnpSets.catalog.where((s) => s.available).length, 1);
    expect(set.assetPath, isNot(contains('combined')));
  });
  test('mutated or empty alcohol panel fails rather than substituting data',
      () async {
    final set = SnpSets.alcohol;
    final bytes = await File(set.assetPath!).readAsBytes();
    expect(() => set.parse([]), throwsFormatException);
    bytes[0] = 65;
    expect(() => set.parse(bytes), throwsFormatException);
    expect(() => SnpSets.catalog[1].parse([]), throwsFormatException);
  });
}
