import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum UsbGeneDongleState {
  unsupported,
  noDevice,
  permissionRequired,
  scanning,
  ready,
  missingFiles,
  ambiguous,
  error,
}

const _wireStates = <String, UsbGeneDongleState>{
  'unsupported': UsbGeneDongleState.unsupported,
  'no_device': UsbGeneDongleState.noDevice,
  'permission_required': UsbGeneDongleState.permissionRequired,
  'scanning': UsbGeneDongleState.scanning,
  'ready': UsbGeneDongleState.ready,
  'missing_files': UsbGeneDongleState.missingFiles,
  'ambiguous': UsbGeneDongleState.ambiguous,
  'error': UsbGeneDongleState.error,
};

Map<Object?, Object?> _map(Object? value) {
  if (value is! Map) throw const FormatException('Expected map');
  return Map<Object?, Object?>.from(value);
}

String _string(Map<Object?, Object?> value, String key) {
  final field = value[key];
  if (field is! String || field.isEmpty) {
    throw FormatException('Invalid $key');
  }
  return field;
}

int _integer(Map<Object?, Object?> value, String key, {int minimum = 0}) {
  final field = value[key];
  if (field is! int || field < minimum) {
    throw FormatException('Invalid $key');
  }
  return field;
}

@immutable
class UsbGeneDongleVolume {
  const UsbGeneDongleVolume({
    required this.id,
    required this.label,
    required this.authorized,
  });

  final String id;
  final String label;
  final bool authorized;

  factory UsbGeneDongleVolume.fromMap(Object? value) {
    final map = _map(value);
    final authorized = map['authorized'];
    if (authorized is! bool) {
      throw const FormatException('Invalid authorized');
    }
    return UsbGeneDongleVolume(
      id: _string(map, 'id'),
      label: _string(map, 'label'),
      authorized: authorized,
    );
  }
}

@immutable
class UsbGeneDongleImport {
  const UsbGeneDongleImport({
    required this.datasetId,
    required this.sourceUri,
    required this.folderName,
    required this.idsBytes,
    required this.idxBytes,
  });

  static const idsFileName = 'combined_ids_all.txt';
  static const idxFileName = 'combined_idx_all.txt';
  final String datasetId;
  final String sourceUri;
  final String folderName;
  final int idsBytes;
  final int idxBytes;

  factory UsbGeneDongleImport.fromMap(Object? value) {
    final map = _map(value);
    final idsBytes = _integer(map, 'idsBytes', minimum: 1);
    final idxBytes = _integer(map, 'idxBytes', minimum: 1);
    if (idsBytes > 256 * 1024 * 1024 || idxBytes > 256 * 1024 * 1024) {
      throw const FormatException('Imported size exceeds limit');
    }
    final sourceUri = _string(map, 'sourceUri');
    if (Uri.tryParse(sourceUri)?.scheme != 'content') {
      throw const FormatException('Invalid sourceUri');
    }
    return UsbGeneDongleImport(
      datasetId: _string(map, 'datasetId'),
      sourceUri: sourceUri,
      folderName: _string(map, 'folderName'),
      idsBytes: idsBytes,
      idxBytes: idxBytes,
    );
  }
}

@immutable
class UsbGeneDongleSnapshot {
  const UsbGeneDongleSnapshot({
    required this.revision,
    required this.state,
    this.volumes = const [],
    this.imported,
    this.errorCode,
  });

  final int revision;
  final UsbGeneDongleState state;
  final List<UsbGeneDongleVolume> volumes;
  final UsbGeneDongleImport? imported;
  final String? errorCode;

  factory UsbGeneDongleSnapshot.fromMap(Object? value) {
    final map = _map(value);
    final revision = _integer(map, 'revision');
    final state = _wireStates[_string(map, 'state')];
    final volumes = map['volumes'];
    final errorCode = map['errorCode'];
    if (state == null ||
        volumes is! List ||
        (errorCode != null && (errorCode is! String || errorCode.isEmpty))) {
      throw const FormatException('Invalid snapshot fields');
    }
    final imported = map['imported'] == null
        ? null
        : UsbGeneDongleImport.fromMap(map['imported']);
    if (state == UsbGeneDongleState.ready && imported == null) {
      throw const FormatException('Ready requires imported dataset');
    }
    return UsbGeneDongleSnapshot(
      revision: revision,
      state: state,
      volumes: List.unmodifiable(volumes.map(UsbGeneDongleVolume.fromMap)),
      imported: imported,
      errorCode: errorCode as String?,
    );
  }
}

abstract interface class UsbGeneDonglePlatform {
  Stream<Object?> get events;
  Future<Object?> refresh();
  Future<Object?> requestAccess({required String volumeId});
}

class MethodChannelUsbGeneDonglePlatform implements UsbGeneDonglePlatform {
  static const methodChannelName = 'geneedge/usb_gene_dongle';
  static const eventChannelName = 'geneedge/usb_gene_dongle/events';
  static const _methods = MethodChannel(methodChannelName);
  static const _events = EventChannel(eventChannelName);

  @override
  Stream<Object?> get events => _events.receiveBroadcastStream();

  @override
  Future<Object?> refresh() => _methods.invokeMethod<Object?>('refresh');

  @override
  Future<Object?> requestAccess({required String volumeId}) =>
      _methods.invokeMethod<Object?>('requestAccess', {'volumeId': volumeId});
}

/// Observes native USB import state independently from chat or computation.
class UsbGeneDongleController extends ChangeNotifier {
  UsbGeneDongleController({UsbGeneDonglePlatform? platform, bool? supported})
      : _supported = supported ??
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.android),
        _platform = platform ?? MethodChannelUsbGeneDonglePlatform() {
    _snapshot = UsbGeneDongleSnapshot(
      revision: 0,
      state: _supported
          ? UsbGeneDongleState.noDevice
          : UsbGeneDongleState.unsupported,
    );
  }

  final bool _supported;
  final UsbGeneDonglePlatform _platform;
  late UsbGeneDongleSnapshot _snapshot;
  StreamSubscription<Object?>? _subscription;
  Future<void>? _startFuture;
  Future<void>? _accessFuture;
  bool _disposed = false;
  int _operations = 0;

  UsbGeneDongleSnapshot get snapshot => _snapshot;
  bool get busy =>
      _operations > 0 || _snapshot.state == UsbGeneDongleState.scanning;

  Future<void> start() {
    if (_disposed || !_supported) return Future<void>.value();
    return _startFuture ??= _start();
  }

  Future<void> _start() async {
    try {
      _subscription = _platform.events.listen(
        _receive,
        onError: (Object error, StackTrace stack) => _fail(error),
      );
    } catch (error) {
      _fail(error);
    }
    await refresh();
  }

  Future<void> refresh() {
    if (_disposed || !_supported) return Future<void>.value();
    return _run(_platform.refresh);
  }

  Future<void> requestAccess(String volumeId) {
    if (_disposed || !_supported) return Future<void>.value();
    if (volumeId.isEmpty) {
      _fail(PlatformException(code: 'invalid_source'));
      return Future<void>.value();
    }
    return _accessFuture ??= _run(
      () => _platform.requestAccess(volumeId: volumeId),
    ).whenComplete(() => _accessFuture = null);
  }

  Future<void> _run(Future<Object?> Function() action) async {
    final startingRevision = _snapshot.revision;
    _operations++;
    notifyListeners();
    try {
      final result = await action();
      if (!_disposed) _receive(result);
    } catch (error) {
      if (!_disposed && _snapshot.revision <= startingRevision) _fail(error);
    } finally {
      _operations--;
      if (!_disposed) notifyListeners();
    }
  }

  void _receive(Object? value) {
    if (_disposed) return;
    // Read revision before decoding the rest so even malformed stale replies
    // cannot overwrite a newer valid event with a local error state.
    if (value is Map &&
        value['revision'] is int &&
        (value['revision'] as int) < _snapshot.revision) {
      return;
    }
    try {
      final next = UsbGeneDongleSnapshot.fromMap(value);
      if (next.revision < _snapshot.revision) return;
      _snapshot = next;
      notifyListeners();
    } catch (error) {
      _fail(error);
    }
  }

  void _fail(Object error) {
    if (_disposed) return;
    const safeCodes = {
      'permission_denied',
      'invalid_source',
      'io_failed',
      'empty_file',
      'file_too_large',
      'scan_limit',
      'cancelled',
    };
    final code = error is FormatException
        ? 'invalid_snapshot'
        : error is PlatformException && safeCodes.contains(error.code)
            ? error.code
            : 'io_failed';
    _snapshot = UsbGeneDongleSnapshot(
      revision: _snapshot.revision,
      state: UsbGeneDongleState.error,
      volumes: _snapshot.volumes,
      imported: _snapshot.imported,
      errorCode: code,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }
}
