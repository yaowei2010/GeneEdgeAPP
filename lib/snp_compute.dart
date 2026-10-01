import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

Map<Object?, Object?> _map(Object? value) {
  if (value is! Map) throw const FormatException('Invalid native payload');
  return Map<Object?, Object?>.from(value);
}

int _count(Map<Object?, Object?> map, String key) {
  final v = map[key];
  if (v is! int || v < 0) throw FormatException('Invalid $key');
  return v;
}

String _text(Map<Object?, Object?> map, String key) {
  final v = map[key];
  if (v is! String || v.isEmpty) throw FormatException('Invalid $key');
  return v;
}

double _milliseconds(Object? value) {
  if (value is! num || !value.isFinite || value < 0) {
    throw const FormatException('Invalid elapsed time');
  }
  return value.toDouble();
}

Map<String, double> _timing(Object? value, List<String> parts, String total) {
  final raw = _map(value);
  final parsed = {
    for (final key in [...parts, total]) key: _milliseconds(raw[key])
  };
  if ((parts.fold<double>(0, (sum, key) => sum + parsed[key]!) - parsed[total]!)
          .abs() >
      .01) {
    throw const FormatException('Inconsistent timing breakdown');
  }
  return Map.unmodifiable(parsed);
}

class SnpInputIdentity {
  const SnpInputIdentity(this.id, this.label, this.version);
  final String id, label, version;
  Map<String, String> toMap() => {'id': id, 'label': label, 'version': version};
}

class SnpQuery {
  const SnpQuery._(this.id, this.sequence, this.ref, this.alt);
  final String id, sequence, ref, alt;
  factory SnpQuery.validated(
      {required String id,
      required String sequence,
      required String ref,
      required String alt}) {
    sequence = sequence.replaceAll(RegExp(r'\s'), '').toUpperCase();
    ref = ref.trim().toUpperCase();
    alt = alt.trim().toUpperCase();
    id = id.trim();
    if (id.isEmpty ||
        id.length > 256 ||
        sequence.length != 301 ||
        !RegExp(r'^[ACGT]+$').hasMatch(sequence) ||
        !RegExp(r'^[ACGT]$').hasMatch(ref) ||
        !RegExp(r'^[ACGT]$').hasMatch(alt) ||
        ref == alt ||
        (sequence[150] != ref && sequence[150] != alt)) {
      throw const FormatException(
          '查詢須為 301 bp A/C/G/T，中心須為 REF 或 ALT，且 REF/ALT 不同。');
    }
    return SnpQuery._(id, sequence, ref, alt);
  }
  Map<String, Object?> toMap() =>
      {'id': id, 'sequence': sequence, 'ref': ref, 'alt': alt};
  static List<SnpQuery> parseFasta(String input,
      {bool alleleQualifiedIds = false}) {
    if (input.length > 2 * 1024 * 1024) {
      throw const FormatException('FASTA 超過大小上限');
    }
    final queries = <SnpQuery>[];
    final ids = <String>{};
    String? header;
    final seq = StringBuffer();
    void finish() {
      if (header == null) return;
      final match =
          RegExp(r'^(.+)_([ACGTacgt])_([ACGTacgt])$').firstMatch(header);
      if (match == null) throw const FormatException('FASTA 標頭須為 >標識_REF_ALT');
      final q = SnpQuery.validated(
          id: alleleQualifiedIds
              ? '${match[1]}_${match[2]!.toUpperCase()}_${match[3]!.toUpperCase()}'
              : match[1]!,
          sequence: seq.toString(),
          ref: match[2]!,
          alt: match[3]!);
      if (!ids.add(q.id) || queries.length >= 3000) {
        throw const FormatException('FASTA 標識重複或超過 3000 筆');
      }
      queries.add(q);
      seq.clear();
    }

    for (final raw in input.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('>')) {
        finish();
        header = line.substring(1).trim();
      } else {
        if (header == null) throw const FormatException('FASTA 缺少標頭');
        seq.write(line);
        if (seq.length > 301) throw const FormatException('FASTA 序列超過 301 bp');
      }
    }
    finish();
    if (queries.isEmpty) throw const FormatException('FASTA 無查詢');
    return List.unmodifiable(queries);
  }
}

class SnpResult {
  SnpResult._(
      this.id,
      this.total,
      this.ref,
      this.alt,
      this.ambiguous,
      this.coverageOnly,
      this.skippedBuckets,
      this.posterior,
      this.gt,
      this.effectiveDepth,
      this.noCallReason,
      this.modelVersion,
      this.parameters,
      this.refAllele,
      this.altAllele,
      this.sourceId,
      this.sourceLabel);
  Map<String, double>? debugTiming;
  final String id,
      gt,
      modelVersion,
      refAllele,
      altAllele,
      sourceId,
      sourceLabel;
  final String? noCallReason;
  final int total,
      ref,
      alt,
      ambiguous,
      coverageOnly,
      skippedBuckets,
      effectiveDepth;
  final List<double> posterior;
  final Map<Object?, Object?> parameters;
  factory SnpResult.fromMap(Object? value) {
    final m = _map(value);
    final refAllele = _text(m, 'refAllele'), altAllele = _text(m, 'altAllele');
    if (!RegExp(r'^[ACGT]$').hasMatch(refAllele) ||
        !RegExp(r'^[ACGT]$').hasMatch(altAllele) ||
        refAllele == altAllele) {
      throw const FormatException('Invalid result allele definitions');
    }
    final total = _count(m, 'total'),
        ref = _count(m, 'ref'),
        alt = _count(m, 'alt'),
        ambiguous = _count(m, 'ambiguous'),
        coverage = _count(m, 'coverageOnly'),
        depth = _count(m, 'effectiveDepth');
    final p = m['posterior'];
    final gt = _text(m, 'gt');
    final reason = m['noCallReason'];
    final params = _map(m['parameters']);
    if (total != ref + alt + ambiguous + coverage ||
        depth != ref + alt ||
        p is! List ||
        p.length != 3 ||
        p.any((v) => v is! num || !v.isFinite || v < 0 || v > 1) ||
        (p.cast<num>().fold<double>(0, (a, b) => a + b) - 1).abs() > 1e-6 ||
        !['./.', '0/0', '0/1', '1/1'].contains(gt) ||
        m['calibrated'] != false ||
        (reason != null && reason is! String) ||
        (gt == './.' && (reason == null || reason == ''))) {
      throw const FormatException('Invalid native result');
    }
    for (final key in ['epsilon', 'rho', 'minPosterior']) {
      final n = params[key];
      if (n is! num || !n.isFinite || n <= 0 || n >= 1) {
        throw const FormatException('Invalid model parameters');
      }
    }
    _count(params, 'minDepth');
    final priors = params['priors'];
    if (priors is! List ||
        priors.length != 3 ||
        priors.any((v) => v is! num || !v.isFinite || v <= 0) ||
        (priors.cast<num>().fold<double>(0, (a, b) => a + b) - 1).abs() >
            1e-6) {
      throw const FormatException('Invalid priors');
    }
    final result = SnpResult._(
        _text(m, 'id'),
        total,
        ref,
        alt,
        ambiguous,
        coverage,
        _count(m, 'skippedBuckets'),
        List.unmodifiable(p.cast<num>().map((v) => v.toDouble())),
        gt,
        depth,
        reason as String?,
        _text(m, 'modelVersion'),
        Map.unmodifiable(params),
        refAllele,
        altAllele,
        _text(m, 'sourceId'),
        _text(m, 'sourceLabel'));
    if (m.containsKey('debugTiming')) {
      result.debugTiming = _timing(
          m['debugTiming'],
          ['ioMs', 'countMs', 'genotypeMs', 'nativeOverheadMs'],
          'nativeTotalMs');
    }
    return result;
  }
  Map<String, Object?> toDebugMap() => {
        'id': id,
        'refAllele': refAllele,
        'altAllele': altAllele,
        'total': total,
        'ref': ref,
        'alt': alt,
        'ambiguous': ambiguous,
        'coverageOnly': coverageOnly,
        'skippedBuckets': skippedBuckets,
        'effectiveDepth': effectiveDepth,
        'gt': gt,
        'posterior': posterior,
        'noCallReason': noCallReason,
        'modelVersion': modelVersion,
        'calibrated': false,
        'parameters': {
          for (final key in [
            'epsilon',
            'rho',
            'priors',
            'minDepth',
            'minPosterior'
          ])
            key: parameters[key]
        },
        if (debugTiming != null) 'debugTiming': debugTiming,
      };
}

class SnpChatContext {
  const SnpChatContext(this.userId, this.query, this.topic);
  final String userId, query, topic;
}

class SnpLocus {
  SnpLocus._(this.id, this.rsId, this.chromosome, this.position, this.ref,
      this.queries);
  final String id, rsId, chromosome, ref;
  final int position;
  final List<SnpQuery> queries;
  List<String> get alleles => [ref, ...'ACGT'.split('').where((b) => b != ref)];
  static List<SnpLocus> group(List<SnpQuery> queries) {
    if (queries.isEmpty ||
        queries.length > 3000 ||
        queries.map((q) => q.id).toSet().length != queries.length) {
      throw const FormatException('Invalid locus panel');
    }
    final pattern =
        RegExp(r'^(rs[0-9]+)_([A-Za-z0-9]+)_([1-9][0-9]*)_([ACGT])_([ACGT])$');
    final grouped = <String, List<SnpQuery>>{};
    for (final q in queries) {
      final m = pattern.firstMatch(q.id);
      if (m == null ||
          m[4] != q.ref ||
          m[5] != q.alt ||
          int.tryParse(m[3]!) == null) {
        throw const FormatException('Invalid locus identity');
      }
      (grouped['${m[1]}_${m[2]}_${m[3]}'] ??= []).add(q);
    }
    return List.unmodifiable(grouped.entries.map((entry) {
      final first = entry.value.first, m = pattern.firstMatch(first.id)!;
      final flank = first.sequence.replaceRange(150, 151, '');
      if (entry.value.length > 3 ||
          entry.value.any((q) =>
              q.ref != first.ref ||
              q.sequence.replaceRange(150, 151, '') != flank)) {
        throw const FormatException('同位點 REF 或側翼不一致');
      }
      return SnpLocus._(entry.key, m[1]!, m[2]!, int.parse(m[3]!), first.ref,
          List.unmodifiable(entry.value));
    }));
  }
}

class SnpLocusResult {
  SnpLocusResult._(this.data, this.debugTiming);
  final Map<String, Object?> data;
  final Map<String, double>? debugTiming;
  String get id => data['id'] as String;
  String get rsId => data['rsId'] as String;
  String get refAllele => data['refAllele'] as String;
  String get sourceId => data['sourceId'] as String;
  String? get actualGenotype => data['actualGenotype'] as String?;
  String get gt => data['gt'] as String;
  factory SnpLocusResult.fromMap(Object? value) {
    final m = _map(value);
    final ref = _text(m, 'refAllele'),
        id = _text(m, 'id'),
        rs = _text(m, 'rsId'),
        chrom = _text(m, 'chromosome');
    final position = _count(m, 'position');
    if (!RegExp(r'^rs[0-9]+$').hasMatch(rs) ||
        !RegExp(r'^[A-Za-z0-9]+$').hasMatch(chrom) ||
        position == 0 ||
        id != '${rs}_${chrom}_$position' ||
        !RegExp(r'^[ACGT]$').hasMatch(ref)) {
      throw const FormatException('Invalid locus metadata');
    }
    final alleles = m['alleles'],
        counts = m['baseCounts'],
        p = m['posterior'],
        best = m['bestGenotype'];
    final order = [ref, ...'ACGT'.split('').where((b) => b != ref)];
    if (alleles is! List ||
        !listEquals(alleles, order) ||
        counts is! List ||
        counts.length != 4 ||
        counts.any((n) => n is! int || n < 0) ||
        p is! List ||
        p.length != 10 ||
        p.any((n) => n is! num || !n.isFinite || n < 0 || n > 1) ||
        (p.cast<num>().fold<double>(0, (a, b) => a + b) - 1).abs() > 1e-6 ||
        best is! List ||
        best.length != 2 ||
        best.any((n) => n is! int || n < 0 || n > 3) ||
        best[0] > best[1]) {
      throw const FormatException('Invalid joint model output');
    }
    final depth = counts.cast<int>().fold<int>(0, (a, b) => a + b);
    final ambiguous = _count(m, 'ambiguous'),
        coverage = _count(m, 'coverageOnly'),
        total = _count(m, 'total');
    if (depth > 1000000 ||
        depth != _count(m, 'effectiveDepth') ||
        total != depth + ambiguous + coverage) {
      throw const FormatException('Invalid evidence partition');
    }
    final b0 = best[0] as int, b1 = best[1] as int;
    final index = b0 * 4 - b0 * (b0 - 1) ~/ 2 + b1 - b0;
    final bp = _milliseconds(m['bestPosterior']),
        gap = _milliseconds(m['logScoreGap']);
    if ((bp - (p[index] as num)).abs() > 1e-8 ||
        p.cast<num>().any((n) => n > bp + 1e-8)) {
      throw const FormatException('Invalid best posterior');
    }
    final gt = _text(m, 'gt'),
        actual = m['actualGenotype'],
        reason = m['noCallReason'];
    if (gt == './.') {
      final expectedReason = depth == 0
          ? 'ZERO_DEPTH'
          : depth < 10
              ? 'LOW_DEPTH'
              : gap <= 1e-12
                  ? 'TIED'
                  : bp < .99
                      ? 'LOW_POSTERIOR'
                      : null;
      if (actual != null ||
          !['ZERO_DEPTH', 'LOW_DEPTH', 'LOW_POSTERIOR', 'TIED']
              .contains(reason) ||
          reason != expectedReason) {
        throw const FormatException('Invalid no-call');
      }
    } else if (gt != '$b0/$b1' ||
        actual != '${order[b0]}${order[b1]}' ||
        reason != null ||
        depth < 10 ||
        bp < .99 ||
        gap <= 1e-12) {
      throw const FormatException('Invalid called genotype');
    }
    final config = _map(m['parameters']);
    if (m['modelVersion'] != 'dm-locus-research-v1' ||
        m['calibrated'] != false ||
        config['epsilon'] != .01 ||
        config['rho'] != .02 ||
        config['minDepth'] != 10 ||
        config['minPosterior'] != .99 ||
        config['priors'] is! List ||
        !listEquals(config['priors'] as List, List.filled(10, .1))) {
      throw const FormatException('Invalid research model');
    }
    final data = <String, Object?>{
      'id': id,
      'rsId': rs,
      'chromosome': chrom,
      'position': position,
      'refAllele': ref,
      'sourceId': _text(m, 'sourceId'),
      'sourceLabel': _text(m, 'sourceLabel'),
      'total': total,
      'baseCounts': List<int>.unmodifiable(counts.cast<int>()),
      'alleles': List<String>.unmodifiable(order),
      'ambiguous': ambiguous,
      'coverageOnly': coverage,
      'skippedBuckets': _count(m, 'skippedBuckets'),
      'effectiveDepth': depth,
      'posterior':
          List<double>.unmodifiable(p.cast<num>().map((n) => n.toDouble())),
      'bestGenotype': List<int>.unmodifiable([b0, b1]),
      'bestPosterior': bp,
      'logScoreGap': gap,
      'gt': gt,
      'actualGenotype': actual,
      'noCallReason': reason,
      'modelVersion': 'dm-locus-research-v1',
      'calibrated': false,
      'parameters': Map<String, Object?>.unmodifiable({
        'epsilon': .01,
        'rho': .02,
        'priors': List<double>.unmodifiable(List.filled(10, .1)),
        'minDepth': 10,
        'minPosterior': .99
      })
    };
    final timing = m.containsKey('debugTiming')
        ? _timing(
            m['debugTiming'],
            ['ioMs', 'countMs', 'genotypeMs', 'nativeOverheadMs'],
            'nativeTotalMs')
        : null;
    return SnpLocusResult._(Map.unmodifiable(data), timing);
  }
  Map<String, Object?> toDiagnosticMap() => {
        for (final entry in data.entries)
          if (!['sourceId', 'sourceLabel'].contains(entry.key))
            entry.key: entry.value,
        if (debugTiming != null) 'debugTiming': debugTiming
      };
}

abstract interface class SnpLocusComputePlatform {
  Future<Object?> runLoci(String sourceId, List<SnpQuery> queries,
      {bool debugEnabled = false});
}

abstract interface class SnpComputePlatform {
  Stream<Object?> get events;
  Future<Object?> sources();
  Future<Object?> requestAccess(String volumeId);
  Future<Object?> selectSource(String sourceId);
  Future<Object?> run(String sourceId, List<SnpQuery> queries,
      {bool debugEnabled = false});
  Future<void> cancel();
  Future<String?> pickPanel();
}

class MethodChannelSnpComputePlatform
    implements SnpComputePlatform, SnpLocusComputePlatform {
  static const methods = MethodChannel('geneedge/snp_compute');
  static const eventChannel = EventChannel('geneedge/snp_compute/events');
  @override
  Stream<Object?> get events => eventChannel.receiveBroadcastStream();
  @override
  Future<Object?> sources() => methods.invokeMethod('sources');
  @override
  Future<Object?> requestAccess(String volumeId) =>
      methods.invokeMethod('requestAccess', {'volumeId': volumeId});
  @override
  Future<Object?> selectSource(String sourceId) =>
      methods.invokeMethod('selectSource', {'sourceId': sourceId});
  @override
  Future<Object?> run(String sourceId, List<SnpQuery> queries,
          {bool debugEnabled = false}) =>
      methods.invokeMethod('run', {
        'sourceId': sourceId,
        if (debugEnabled) 'debugEnabled': true,
        'queries': queries.map((q) => q.toMap()).toList()
      });
  @override
  Future<void> cancel() => methods.invokeMethod<void>('cancel');
  @override
  Future<Object?> runLoci(String sourceId, List<SnpQuery> queries,
          {bool debugEnabled = false}) =>
      methods.invokeMethod('run', {
        'sourceId': sourceId,
        'mode': 'locus',
        if (debugEnabled) 'debugEnabled': true,
        'queries': queries.map((q) => q.toMap()).toList()
      });
  @override
  Future<String?> pickPanel() => methods.invokeMethod<String>('pickPanel');
}

/// State and validation only. Counting and posterior calculations live in C.
class SnpComputeController extends ChangeNotifier {
  SnpComputeController({SnpComputePlatform? platform, bool? supported})
      : _platform = platform ?? MethodChannelSnpComputePlatform(),
        supported = supported ??
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    if (!this.supported) status = 'unsupported';
  }
  final SnpComputePlatform _platform;
  final bool supported;
  String status = 'idle';
  String? errorCode, selectedSourceId, _jobId, resultJobId;
  int completed = 0, total = 0, _revision = -1, _generation = 0;
  List<Map<Object?, Object?>> sources = const [], volumes = const [];
  List<SnpResult> results = const [];
  List<SnpLocusResult> locusResults = const [];
  List<SnpLocus> _loci = const [];
  SnpChatContext? _jobContext, resultContext;
  bool _locusMode = false;
  bool _debugEnabled = false, _jobDebug = false;
  bool get debugEnabled => _debugEnabled;
  Map<String, double>? batchTiming;
  String? debugReport, _cancelledJobId;
  double? elapsedMs;
  SnpInputIdentity? resultInput;
  SnpInputIdentity _jobInput =
      const SnpInputIdentity('single', '單 SNP', 'custom');
  List<SnpQuery> _queries = const [];
  void setDebugEnabled(bool value) {
    if (busy || _disposed) return;
    _debugEnabled = value;
    _notify();
  }

  void _clearOutput() {
    results = const [];
    locusResults = const [];
    resultContext = null;
    resultJobId = null;
    batchTiming = null;
    debugReport = null;
    elapsedMs = null;
    resultInput = null;
  }

  void clearResults() {
    if (busy || _disposed) return;
    _generation++;
    _jobId = null;
    _cancelledJobId = null;
    _early.clear();
    _clearOutput();
    completed = 0;
    total = 0;
    errorCode = null;
    status = 'idle';
    _notify();
  }

  StreamSubscription<Object?>? _sub;
  bool _disposed = false, _pending = false, _started = false;
  final List<Object?> _early = [];
  bool get busy => _pending || status == 'running';
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    if (_started || !supported || _disposed) return;
    _started = true;
    _sub = _platform.events.listen(_event, onError: (Object e) {
      _fail(e);
    });
    await refresh();
  }

  void _fail(Object e) {
    if (_disposed) return;
    if (busy) unawaited(_platform.cancel().catchError((Object _) {}));
    _generation++;
    _jobId = null;
    _early.clear();
    _clearOutput();
    status = 'error';
    errorCode = e is PlatformException ? e.code : 'INVALID_FORMAT';
    _pending = false;
    _notify();
  }

  void _applySources(Object? value) {
    final m = _map(value);
    final revision = _count(m, 'revision');
    if (revision < _revision) return;
    final s = m['sources'], v = m['volumes'];
    if (s is! List || v is! List) {
      throw const FormatException('Invalid sources');
    }
    final parsed = s.map(_map).toList();
    final pv = v.map(_map).toList();
    for (final x in [...parsed, ...pv]) {
      _text(x, 'id');
      _text(x, 'label');
    }
    if (parsed.map((s) => s['id']).toSet().length != parsed.length ||
        pv.any((v) => v['authorized'] is! bool)) {
      throw const FormatException(
          'Invalid source identifiers or authorization');
    }
    final selected = m['selectedSourceId'];
    if (selected != null &&
        (selected is! String || !parsed.any((s) => s['id'] == selected))) {
      throw const FormatException('Invalid source selection');
    }
    if (selected != selectedSourceId) {
      _generation++;
      _jobId = null;
      _clearOutput();
      if (busy) {
        unawaited(_platform.cancel().catchError((Object _) {}));
        status = 'invalidated';
      }
      _pending = false;
    }
    _revision = revision;
    sources = List.unmodifiable(parsed);
    volumes = List.unmodifiable(pv);
    selectedSourceId = selected as String?;
    _notify();
  }

  Future<void> refresh() async {
    if (!supported || _disposed) return;
    try {
      final v = await _platform.sources();
      if (!_disposed) _applySources(v);
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> requestAccess(String id) async {
    try {
      final v = await _platform.requestAccess(id);
      if (!_disposed) _applySources(v);
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> selectSource(String id) async {
    if (busy) await cancel();
    _clearOutput();
    try {
      final v = await _platform.selectSource(id);
      if (!_disposed) _applySources(v);
    } catch (e) {
      _fail(e);
    }
  }

  Future<String?> pickPanel() => _platform.pickPanel();
  Future<void> runLoci(List<SnpQuery> queries,
          {required SnpInputIdentity input, required SnpChatContext context}) =>
      run(queries, input: input, chat: context);
  Future<void> run(List<SnpQuery> queries,
      {SnpChatContext? chat,
      SnpInputIdentity input =
          const SnpInputIdentity('single', '單 SNP', 'custom')}) async {
    if (!supported || _disposed || busy) return;
    if (selectedSourceId == null ||
        queries.isEmpty ||
        queries.length > 3000 ||
        queries.map((q) => q.id).toSet().length != queries.length) {
      throw const FormatException('請選擇 USB 資料來源並提供有效查詢');
    }
    final generation = ++_generation;
    _locusMode = chat != null;
    _loci = _locusMode ? SnpLocus.group(queries) : const [];
    _jobContext = chat;
    _jobDebug = _debugEnabled;
    _jobInput = input;
    _queries = List.unmodifiable(queries);
    _cancelledJobId = null;
    _pending = true;
    _jobId = null;
    _early.clear();
    _clearOutput();
    status = 'running';
    completed = 0;
    total = _locusMode ? _loci.length : queries.length;
    errorCode = null;
    _notify();
    try {
      final Object? wire;
      if (_locusMode) {
        final platform = _platform;
        if (platform is! SnpLocusComputePlatform) {
          throw PlatformException(code: 'UNSUPPORTED_PLATFORM');
        }
        wire = await (platform as SnpLocusComputePlatform)
            .runLoci(selectedSourceId!, _queries, debugEnabled: _jobDebug);
      } else {
        wire = await _platform.run(selectedSourceId!, _queries,
            debugEnabled: _jobDebug);
      }
      final response = _map(wire);
      if (_disposed || generation != _generation) return;
      _jobId = _text(response, 'jobId');
      _pending = false;
      final buffered = List<Object?>.of(_early);
      _early.clear();
      for (final e in buffered) {
        _event(e);
      }
      _notify();
    } catch (e) {
      if (generation == _generation) _fail(e);
    }
  }

  void _event(Object? value) {
    if (_disposed) return;
    try {
      final m = _map(value);
      final revision = _count(m, 'revision');
      if (revision <= _revision) return;
      final state = _text(m, 'status');
      if (state == 'sourcesChanged') {
        _revision = revision;
        unawaited(refresh());
        return;
      }
      if (state == 'invalidated') {
        _revision = revision;
        _generation++;
        _jobId = null;
        _pending = false;
        _early.clear();
        _clearOutput();
        if (_jobDebug && m.containsKey('elapsedMs')) {
          elapsedMs = _milliseconds(m['elapsedMs']);
        }
        status = state;
        errorCode = m['errorCode'] as String?;
        selectedSourceId = null;
        _notify();
        return;
      }
      if (_pending) {
        if (_early.length == 64) _early.removeAt(0);
        _early.add(value);
        return;
      }
      if (state == 'cancelled' &&
          status == 'cancelled' &&
          _cancelledJobId != null &&
          m['jobId'] == _cancelledJobId) {
        if (_jobDebug && m.containsKey('elapsedMs')) {
          elapsedMs = _milliseconds(m['elapsedMs']);
        }
        _revision = revision;
        _cancelledJobId = null;
        _notify();
        return;
      }
      if (_jobId == null || m['jobId'] != _jobId) return;
      if (!['running', 'completed', 'cancelled', 'error'].contains(state)) {
        throw const FormatException('Invalid status');
      }
      final done = _count(m, 'completed'), all = _count(m, 'total');
      if (done > all) throw const FormatException('Invalid progress');
      final parsed = state == 'completed' && !_locusMode
          ? ((m['results'] as List).map(SnpResult.fromMap).toList())
          : <SnpResult>[];
      final parsedLoci = state == 'completed' && _locusMode
          ? ((m['results'] as List).map(SnpLocusResult.fromMap).toList())
          : <SnpLocusResult>[];
      if (all != total ||
          (state == 'completed' &&
              (done != all ||
                  (_locusMode ? parsedLoci.length : parsed.length) != all))) {
        throw const FormatException('Incomplete results');
      }
      Map<String, double>? timing;
      if (state == 'completed') {
        if (_locusMode) {
          if (m['mode'] != 'locus') {
            throw const FormatException('Unexpected run mode');
          }
          for (var i = 0; i < parsedLoci.length; i++) {
            final r = parsedLoci[i], q = _loci[i];
            if (r.id != q.id ||
                r.refAllele != q.ref ||
                r.sourceId != selectedSourceId) {
              throw const FormatException('Invalid locus/source identity');
            }
          }
        }
        for (var i = 0; i < parsed.length; i++) {
          final r = parsed[i], q = _queries[i];
          if (r.id != q.id ||
              r.refAllele != q.ref ||
              r.altAllele != q.alt ||
              r.sourceId != selectedSourceId) {
            throw const FormatException('Result does not match query/source');
          }
        }
        if (_jobDebug) {
          timing = _timing(
              m['debugTiming'],
              ['setupIoMs', 'queryIoMs', 'countMs', 'genotypeMs', 'overheadMs'],
              'totalMs');
          for (final pair in [
            ('queryIoMs', 'ioMs'),
            ('countMs', 'countMs'),
            ('genotypeMs', 'genotypeMs')
          ]) {
            double sum = 0;
            final rows = _locusMode
                ? parsedLoci.map((r) => r.debugTiming)
                : parsed.map((r) => r.debugTiming);
            for (final row in rows) {
              if (row == null) {
                throw const FormatException('Missing native timing');
              }
              sum += row[pair.$2]!;
            }
            if ((sum - timing[pair.$1]!).abs() > .01) {
              throw const FormatException('Invalid batch timing sum');
            }
          }
        } else if (m.containsKey('debugTiming') ||
            parsed.any((r) => r.debugTiming != null) ||
            parsedLoci.any((r) => r.debugTiming != null)) {
          throw const FormatException('Unexpected debug payload');
        }
      }
      _revision = revision;
      status = state;
      completed = done;
      total = all;
      results = List.unmodifiable(parsed);
      locusResults = List.unmodifiable(parsedLoci);
      resultContext = state == 'completed' ? _jobContext : null;
      resultJobId = state == 'completed' ? _jobId : null;
      batchTiming = timing;
      debugReport = null;
      resultInput = state == 'completed' ? _jobInput : null;
      elapsedMs = _jobDebug && m.containsKey('elapsedMs')
          ? _milliseconds(m['elapsedMs'])
          : null;
      if (_jobDebug && state == 'completed') {
        debugReport = const JsonEncoder.withIndent('  ').convert({
          'schemaVersion': _locusMode ? 2 : 1,
          'jobId': _jobId,
          'status': state,
          'completed': done,
          'total': all,
          'inputSet': _jobInput.toMap(),
          'debugTiming': timing,
          'results': _locusMode
              ? parsedLoci.map((r) => r.toDiagnosticMap()).toList()
              : parsed.map((r) => r.toDebugMap()).toList(),
        });
      }
      errorCode = m['errorCode'] as String?;
      if (state != 'running') _jobId = null;
      _notify();
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> cancel() async {
    if (_disposed || !supported) return;
    _generation++;
    _cancelledJobId = _jobId;
    _jobId = null;
    _pending = false;
    _early.clear();
    _clearOutput();
    status = 'cancelled';
    _notify();
    try {
      await _platform.cancel();
    } catch (e) {
      _fail(e);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _jobId = null;
    _clearOutput();
    _jobContext = null;
    _queries = const [];
    _loci = const [];
    _early.clear();
    unawaited(_sub?.cancel());
    if (busy) unawaited(_platform.cancel().catchError((Object _) {}));
    super.dispose();
  }
}
