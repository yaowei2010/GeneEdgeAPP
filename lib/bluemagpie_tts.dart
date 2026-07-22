import 'dart:async';

import 'package:flutter/services.dart';

/// Injectable boundary used by [BlueMagpieTts].
///
/// Production uses Flutter platform channels. Tests can provide a fake without
/// loading an Android runtime or model weights.
abstract interface class BlueMagpieTtsChannel {
  Future<Object?> invokeMethod(
    String method, [
    Map<String, Object?>? arguments,
  ]);

  Stream<Object?> get events;
}

final class FlutterBlueMagpieTtsChannel implements BlueMagpieTtsChannel {
  FlutterBlueMagpieTtsChannel({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _methodChannel = methodChannel ??
            const MethodChannel(BlueMagpieTts.methodChannelName),
        _eventChannel =
            eventChannel ?? const EventChannel(BlueMagpieTts.eventChannelName);

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  @override
  Future<Object?> invokeMethod(
    String method, [
    Map<String, Object?>? arguments,
  ]) {
    return _methodChannel.invokeMethod<Object?>(method, arguments);
  }

  @override
  Stream<Object?> get events => _eventChannel.receiveBroadcastStream();
}

enum BlueMagpieBackend {
  cpu('cpu'),
  vulkan('vulkan');

  const BlueMagpieBackend(this.wireName);

  final String wireName;

  static BlueMagpieBackend? fromWire(Object? value) {
    for (final backend in values) {
      if (backend.wireName == value) return backend;
    }
    return null;
  }
}

enum BlueMagpieState {
  uninitialized('uninitialized'),
  initializing('initializing'),
  ready('ready'),
  synthesizing('synthesizing'),
  cancelling('cancelling'),
  cancelled('cancelled'),
  failed('failed'),
  released('released'),
  unavailable('unavailable'),
  unknown('unknown');

  const BlueMagpieState(this.wireName);

  final String wireName;

  static BlueMagpieState fromWire(Object? value) {
    for (final state in values) {
      if (state.wireName == value) return state;
    }
    return unknown;
  }
}

enum BlueMagpieErrorCode {
  runtimeMissing('runtime_missing'),
  unsupportedAbi('unsupported_abi'),
  modelMissing('model_missing'),
  modelPathRejected('model_path_rejected'),
  modelSizeMismatch('model_size_mismatch'),
  modelChecksumMismatch('model_checksum_mismatch'),
  insufficientSpace('insufficient_space'),
  insufficientMemory('insufficient_memory'),
  backendUnavailable('backend_unavailable'),
  invalidText('invalid_text'),
  decodeFailed('decode_failed'),
  cancelled('cancelled'),
  ioFailed('io_failed'),
  internalError('internal_error'),
  unknown('unknown');

  const BlueMagpieErrorCode(this.wireName);

  final String wireName;

  static BlueMagpieErrorCode fromWire(Object? value) {
    for (final code in values) {
      if (code.wireName == value) return code;
    }
    return unknown;
  }
}

final class BlueMagpieTtsException implements Exception {
  const BlueMagpieTtsException({
    required this.code,
    required this.safeMessage,
    this.metadata = const <String, Object?>{},
  });

  final BlueMagpieErrorCode code;
  final String safeMessage;
  final Map<String, Object?> metadata;

  @override
  String toString() => 'BlueMagpieTtsException(${code.wireName}): '
      '$safeMessage';
}

final class BlueMagpieProbeResult {
  const BlueMagpieProbeResult({
    required this.available,
    required this.runtimeRevision,
    required this.abi,
    required this.deviceMemoryClassMb,
    this.backend,
    this.errorCode,
  });

  factory BlueMagpieProbeResult.fromMap(Map<String, Object?> map) {
    return BlueMagpieProbeResult(
      available: map['available'] == true,
      runtimeRevision: _string(map, 'runtimeRevision'),
      abi: _string(map, 'abi'),
      backend: BlueMagpieBackend.fromWire(map['backend']),
      deviceMemoryClassMb: _nonNegativeInt(map, 'deviceMemoryClassMb'),
      errorCode: map['errorCode'] == null
          ? null
          : BlueMagpieErrorCode.fromWire(map['errorCode']),
    );
  }

  final bool available;
  final String runtimeRevision;
  final String abi;
  final BlueMagpieBackend? backend;
  final int deviceMemoryClassMb;
  final BlueMagpieErrorCode? errorCode;

  Map<String, Object?> toMap() => {
        'available': available,
        'runtimeRevision': runtimeRevision,
        'abi': abi,
        'backend': backend?.wireName,
        'deviceMemoryClassMb': deviceMemoryClassMb,
        'errorCode': errorCode?.wireName,
      };
}

final class BlueMagpieModelValidation {
  const BlueMagpieModelValidation({
    required this.id,
    required this.fileName,
    required this.state,
    required this.sizeBytes,
    this.errorCode,
  });

  factory BlueMagpieModelValidation.fromMap(Map<String, Object?> map) {
    return BlueMagpieModelValidation(
      id: _string(map, 'id'),
      fileName: _string(map, 'fileName'),
      state: BlueMagpieState.fromWire(map['state']),
      sizeBytes: _nonNegativeInt(map, 'sizeBytes'),
      errorCode: map['errorCode'] == null
          ? null
          : BlueMagpieErrorCode.fromWire(map['errorCode']),
    );
  }

  final String id;
  final String fileName;
  final BlueMagpieState state;
  final int sizeBytes;
  final BlueMagpieErrorCode? errorCode;

  Map<String, Object?> toMap() => {
        'id': id,
        'fileName': fileName,
        'state': state.wireName,
        'sizeBytes': sizeBytes,
        'errorCode': errorCode?.wireName,
      };
}

final class BlueMagpieModelValidationResult {
  const BlueMagpieModelValidationResult({
    required this.state,
    required this.freeSpaceBytes,
    required this.requiredSpaceBytes,
    required this.models,
  });

  factory BlueMagpieModelValidationResult.fromMap(Map<String, Object?> map) {
    final rawModels = map['models'];
    if (rawModels is! List<Object?>) {
      throw const FormatException('models must be a list');
    }
    return BlueMagpieModelValidationResult(
      state: BlueMagpieState.fromWire(map['state']),
      freeSpaceBytes: _nonNegativeInt(map, 'freeSpaceBytes'),
      requiredSpaceBytes: _nonNegativeInt(map, 'requiredSpaceBytes'),
      models: List.unmodifiable(
        rawModels.map(
            (model) => BlueMagpieModelValidation.fromMap(_objectMap(model))),
      ),
    );
  }

  final BlueMagpieState state;
  final int freeSpaceBytes;
  final int requiredSpaceBytes;
  final List<BlueMagpieModelValidation> models;

  Map<String, Object?> toMap() => {
        'state': state.wireName,
        'freeSpaceBytes': freeSpaceBytes,
        'requiredSpaceBytes': requiredSpaceBytes,
        'models': models.map((model) => model.toMap()).toList(growable: false),
      };
}

final class BlueMagpieInitializeResult {
  const BlueMagpieInitializeResult({
    required this.state,
    required this.backend,
    required this.elapsedMs,
    required this.rssBeforeBytes,
    required this.rssAfterBytes,
  });

  factory BlueMagpieInitializeResult.fromMap(Map<String, Object?> map) {
    final backend = BlueMagpieBackend.fromWire(map['backend']);
    if (backend == null) throw const FormatException('invalid backend');
    return BlueMagpieInitializeResult(
      state: BlueMagpieState.fromWire(map['state']),
      backend: backend,
      elapsedMs: _nonNegativeInt(map, 'elapsedMs'),
      rssBeforeBytes: _nonNegativeInt(map, 'rssBeforeBytes'),
      rssAfterBytes: _nonNegativeInt(map, 'rssAfterBytes'),
    );
  }

  final BlueMagpieState state;
  final BlueMagpieBackend backend;
  final int elapsedMs;
  final int rssBeforeBytes;
  final int rssAfterBytes;

  Map<String, Object?> toMap() => {
        'state': state.wireName,
        'backend': backend.wireName,
        'elapsedMs': elapsedMs,
        'rssBeforeBytes': rssBeforeBytes,
        'rssAfterBytes': rssAfterBytes,
      };
}

final class BlueMagpieSynthesisResult {
  const BlueMagpieSynthesisResult({
    required this.wavToken,
    required this.sampleRate,
    required this.samples,
    required this.durationMs,
    required this.firstAudioMs,
    required this.elapsedMs,
    required this.peakRssBytes,
  });

  factory BlueMagpieSynthesisResult.fromMap(Map<String, Object?> map) {
    return BlueMagpieSynthesisResult(
      wavToken: _string(map, 'wavToken'),
      sampleRate: _nonNegativeInt(map, 'sampleRate'),
      samples: _nonNegativeInt(map, 'samples'),
      durationMs: _nonNegativeInt(map, 'durationMs'),
      firstAudioMs: _nonNegativeInt(map, 'firstAudioMs'),
      elapsedMs: _nonNegativeInt(map, 'elapsedMs'),
      peakRssBytes: _nonNegativeInt(map, 'peakRssBytes'),
    );
  }

  final String wavToken;
  final int sampleRate;
  final int samples;
  final int durationMs;
  final int firstAudioMs;
  final int elapsedMs;
  final int peakRssBytes;

  Map<String, Object?> toMap() => {
        'wavToken': wavToken,
        'sampleRate': sampleRate,
        'samples': samples,
        'durationMs': durationMs,
        'firstAudioMs': firstAudioMs,
        'elapsedMs': elapsedMs,
        'peakRssBytes': peakRssBytes,
      };
}

final class BlueMagpieTtsEvent {
  const BlueMagpieTtsEvent({
    required this.requestId,
    required this.state,
    required this.progress,
    required this.timestampMs,
    this.errorCode,
  });

  factory BlueMagpieTtsEvent.fromMap(Map<String, Object?> map) {
    final progressValue = map['progress'];
    if (progressValue is! num ||
        !progressValue.isFinite ||
        progressValue < 0 ||
        progressValue > 1) {
      throw const FormatException('progress must be between zero and one');
    }
    return BlueMagpieTtsEvent(
      requestId: _string(map, 'requestId'),
      state: BlueMagpieState.fromWire(map['state']),
      progress: progressValue.toDouble(),
      timestampMs: _nonNegativeInt(map, 'timestampMs'),
      errorCode: map['errorCode'] == null
          ? null
          : BlueMagpieErrorCode.fromWire(map['errorCode']),
    );
  }

  final String requestId;
  final BlueMagpieState state;
  final double progress;
  final int timestampMs;
  final BlueMagpieErrorCode? errorCode;

  Map<String, Object?> toMap() => {
        'requestId': requestId,
        'state': state.wireName,
        'progress': progress,
        'timestampMs': timestampMs,
        'errorCode': errorCode?.wireName,
      };
}

final class BlueMagpieTts {
  BlueMagpieTts({BlueMagpieTtsChannel? channel})
      : _channel = channel ?? FlutterBlueMagpieTtsChannel();

  static const methodChannelName = 'geneedge/bluemagpie_tts';
  static const eventChannelName = 'geneedge/bluemagpie_tts/events';
  static const maxTextUnicodeScalars = 200;

  final BlueMagpieTtsChannel _channel;
  Future<BlueMagpieInitializeResult>? _initialization;
  BlueMagpieInitializeResult? _initializedResult;
  final Set<String> _cancelledRequestIds = <String>{};
  Future<void>? _releaseOperation;

  Stream<BlueMagpieTtsEvent> get events => _channel.events.map(
        (event) => BlueMagpieTtsEvent.fromMap(_objectMap(event)),
      );

  Future<BlueMagpieProbeResult> probe() => _invokeParsed(
        'probe',
        BlueMagpieProbeResult.fromMap,
      );

  Future<BlueMagpieModelValidationResult> validateModels() => _invokeParsed(
        'validateModels',
        BlueMagpieModelValidationResult.fromMap,
      );

  Future<BlueMagpieInitializeResult> initialize({
    required BlueMagpieBackend backend,
  }) {
    final initialized = _initializedResult;
    if (initialized != null) return Future.value(initialized);
    final existing = _initialization;
    if (existing != null) return existing;

    final operation = _invokeParsed(
      'initialize',
      BlueMagpieInitializeResult.fromMap,
      {'backend': backend.wireName},
    ).then((result) {
      if (result.state == BlueMagpieState.ready) {
        _initializedResult = result;
      }
      return result;
    });
    _initialization = operation;
    unawaited(operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {
        _initialization = null;
      },
    ));
    return operation;
  }

  Future<BlueMagpieSynthesisResult> synthesize({
    required String requestId,
    required String text,
  }) {
    if (requestId.trim().isEmpty ||
        text.trim().isEmpty ||
        text.runes.length > maxTextUnicodeScalars) {
      return Future.error(_localError(BlueMagpieErrorCode.invalidText));
    }
    return _invokeParsed(
      'synthesize',
      BlueMagpieSynthesisResult.fromMap,
      {'requestId': requestId, 'text': text},
    );
  }

  /// Plays a WAV previously returned by [synthesize].
  ///
  /// The native side receives only an opaque private-cache token, never an
  /// arbitrary filesystem path supplied by Flutter code.
  Future<void> play(String wavToken) {
    if (!wavToken.startsWith('cache:') || wavToken.length <= 'cache:'.length) {
      return Future.error(
        ArgumentError.value(wavToken, 'wavToken', 'must be a cache token'),
      );
    }
    return _invokeVoid('play', {'wavToken': wavToken});
  }

  Future<void> cancel(String requestId) {
    if (requestId.trim().isEmpty) {
      return Future.error(_localError(BlueMagpieErrorCode.invalidText));
    }
    if (!_cancelledRequestIds.add(requestId)) return Future.value();
    return _invokeVoid('cancel', {'requestId': requestId});
  }

  Future<void> release() {
    final existing = _releaseOperation;
    if (existing != null) return existing;
    final operation = _invokeVoid('release');
    _releaseOperation = operation;
    return operation;
  }

  Future<T> _invokeParsed<T>(
    String method,
    T Function(Map<String, Object?> map) parse, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      final result = await _channel.invokeMethod(method, arguments);
      return parse(_objectMap(result));
    } on BlueMagpieTtsException {
      rethrow;
    } on PlatformException catch (error) {
      throw _platformError(error);
    } on Object {
      throw _localError(BlueMagpieErrorCode.internalError);
    }
  }

  Future<void> _invokeVoid(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      await _channel.invokeMethod(method, arguments);
    } on PlatformException catch (error) {
      throw _platformError(error);
    } on Object {
      throw _localError(BlueMagpieErrorCode.internalError);
    }
  }
}

BlueMagpieTtsException _platformError(PlatformException error) {
  final code = BlueMagpieErrorCode.fromWire(error.code);
  return _localError(code);
}

BlueMagpieTtsException _localError(BlueMagpieErrorCode code) {
  return BlueMagpieTtsException(
    code: code,
    safeMessage:
        _safeMessages[code] ?? _safeMessages[BlueMagpieErrorCode.unknown]!,
  );
}

const _safeMessages = <BlueMagpieErrorCode, String>{
  BlueMagpieErrorCode.runtimeMissing: '此版本未包含 BlueMagpie 執行環境。',
  BlueMagpieErrorCode.unsupportedAbi: '這台裝置的處理器架構不受支援。',
  BlueMagpieErrorCode.modelMissing: '尚未安裝完整的語音模型。',
  BlueMagpieErrorCode.modelPathRejected: '語音模型不在允許的 App 私有位置。',
  BlueMagpieErrorCode.modelSizeMismatch: '語音模型檔案大小不符。',
  BlueMagpieErrorCode.modelChecksumMismatch: '語音模型完整性驗證失敗。',
  BlueMagpieErrorCode.insufficientSpace: '裝置儲存空間不足。',
  BlueMagpieErrorCode.insufficientMemory: '裝置可用記憶體不足。',
  BlueMagpieErrorCode.backendUnavailable: '指定的推論後端無法使用。',
  BlueMagpieErrorCode.invalidText: '請輸入 1 到 200 個字元的文字。',
  BlueMagpieErrorCode.decodeFailed: '語音產生失敗。',
  BlueMagpieErrorCode.cancelled: '語音產生已取消。',
  BlueMagpieErrorCode.ioFailed: '語音檔案處理失敗。',
  BlueMagpieErrorCode.internalError: 'BlueMagpie 發生內部錯誤。',
  BlueMagpieErrorCode.unknown: 'BlueMagpie 發生未知錯誤。',
};

Map<String, Object?> _objectMap(Object? value) {
  if (value is! Map) throw const FormatException('expected a map');
  return value.map((key, entryValue) {
    if (key is! String) throw const FormatException('map keys must be strings');
    return MapEntry(key, entryValue);
  });
}

String _string(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String) throw FormatException('$key must be a string');
  return value;
}

int _nonNegativeInt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! num || !value.isFinite || value < 0 || value != value.round()) {
    throw FormatException('$key must be a non-negative integer');
  }
  return value.toInt();
}
