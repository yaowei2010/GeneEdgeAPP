import 'dart:async';
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
  static List<SnpQuery> parseFasta(String input) {
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
          id: match[1]!,
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
    return SnpResult._(
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
  }
}

abstract interface class SnpComputePlatform {
  Stream<Object?> get events;
  Future<Object?> sources();
  Future<Object?> requestAccess(String volumeId);
  Future<Object?> selectSource(String sourceId);
  Future<Object?> run(String sourceId, List<SnpQuery> queries);
  Future<void> cancel();
  Future<String?> pickPanel();
}

class MethodChannelSnpComputePlatform implements SnpComputePlatform {
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
  Future<Object?> run(String sourceId, List<SnpQuery> queries) =>
      methods.invokeMethod('run', {
        'sourceId': sourceId,
        'queries': queries.map((q) => q.toMap()).toList()
      });
  @override
  Future<void> cancel() => methods.invokeMethod<void>('cancel');
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
  String? errorCode, selectedSourceId, _jobId;
  int completed = 0, total = 0, _revision = -1, _generation = 0;
  List<Map<Object?, Object?>> sources = const [], volumes = const [];
  List<SnpResult> results = const [];
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
    results = const [];
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
      results = const [];
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
    results = const [];
    try {
      final v = await _platform.selectSource(id);
      if (!_disposed) _applySources(v);
    } catch (e) {
      _fail(e);
    }
  }

  Future<String?> pickPanel() => _platform.pickPanel();
  Future<void> run(List<SnpQuery> queries) async {
    if (!supported || _disposed || busy) return;
    if (selectedSourceId == null ||
        queries.isEmpty ||
        queries.length > 3000 ||
        queries.map((q) => q.id).toSet().length != queries.length) {
      throw const FormatException('請選擇 USB 資料來源並提供有效查詢');
    }
    final generation = ++_generation;
    _pending = true;
    _jobId = null;
    _early.clear();
    results = const [];
    status = 'running';
    completed = 0;
    total = queries.length;
    errorCode = null;
    _notify();
    try {
      final response = _map(await _platform.run(selectedSourceId!, queries));
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
      if (state == 'invalidated') {
        _revision = revision;
        _generation++;
        _jobId = null;
        _pending = false;
        _early.clear();
        results = const [];
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
      if (_jobId == null || m['jobId'] != _jobId) return;
      if (!['running', 'completed', 'cancelled', 'error'].contains(state)) {
        throw const FormatException('Invalid status');
      }
      final done = _count(m, 'completed'), all = _count(m, 'total');
      if (done > all) throw const FormatException('Invalid progress');
      final parsed = state == 'completed'
          ? ((m['results'] as List).map(SnpResult.fromMap).toList())
          : <SnpResult>[];
      if (state == 'completed' && (done != all || parsed.length != all)) {
        throw const FormatException('Incomplete results');
      }
      _revision = revision;
      status = state;
      completed = done;
      total = all;
      results = List.unmodifiable(parsed);
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
    _jobId = null;
    _pending = false;
    _early.clear();
    results = const [];
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
    results = const [];
    _early.clear();
    unawaited(_sub?.cancel());
    if (busy) unawaited(_platform.cancel().catchError((Object _) {}));
    super.dispose();
  }
}
