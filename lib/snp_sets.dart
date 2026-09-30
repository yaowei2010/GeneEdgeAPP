import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'snp_compute.dart';

class SnpSet {
  const SnpSet(this.id, this.label,
      {this.assetPath,
      this.expectedCount = 0,
      this.version = 'unavailable',
      this.sha256Hex,
      this.source = '尚未提供 SNP set'});
  final String id, label, version, source;
  final String? assetPath, sha256Hex;
  final int expectedCount;
  bool get available => assetPath != null && expectedCount > 0;
  SnpInputIdentity get identity => SnpInputIdentity(id, label, version);
  List<SnpQuery> parse(List<int> bytes) {
    if (!available || sha256.convert(bytes).toString() != sha256Hex) {
      throw const FormatException('SNP set 資料缺失或完整性檢查失敗');
    }
    final queries =
        SnpQuery.parseFasta(utf8.decode(bytes), alleleQualifiedIds: true);
    if (queries.length != expectedCount) {
      throw const FormatException('SNP set 筆數不符');
    }
    if (id == SnpSets.alcohol.id &&
        queries
                .map((q) => q.id.replaceFirst(RegExp(r'_[ACGT]_[ACGT]$'), ''))
                .toSet()
                .length !=
            77) {
      throw const FormatException('酒精 SNP set 位點數不符');
    }
    return queries;
  }

  Future<List<SnpQuery>> load({AssetBundle? bundle}) async {
    if (!available) throw const FormatException('尚未提供 SNP set');
    final data = await (bundle ?? rootBundle).load(assetPath!);
    return parse(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  }
}

abstract final class SnpSets {
  static const alcohol = SnpSet('alcohol-set143-k150-v1', '酒精代謝',
      assetPath: 'assets/snp_sets/alcohol.set143.k150.fasta',
      expectedCount: 143,
      version: 'alcohol-set143-k150-v1',
      sha256Hex:
          '0bc77278d47ddcf41f1bbf4ef6f879d47f86c2d06791c0e29c5c0812a72b73f9',
      source: 'MXIC_NCKU_demo_v4/ref_dataset/alcohol.set143.k150.fasta');
  static const catalog = [
    alcohol,
    SnpSet('medication', '藥物反應'),
    SnpSet('memory', '記憶認知'),
    SnpSet('mental_state', '心理狀態'),
    SnpSet('hypertension', '高血壓'),
    SnpSet('lipids', '血脂管理'),
    SnpSet('nutrition', '營養建議')
  ];
}
