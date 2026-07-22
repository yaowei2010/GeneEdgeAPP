import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geneapp/bluemagpie_tts.dart';

void main() {
  group('BlueMagpieTts contract', () {
    test('uses stable channel names and parses events with unknown fields',
        () async {
      final channel = FakeBlueMagpieTtsChannel();
      final tts = BlueMagpieTts(channel: channel);

      expect(BlueMagpieTts.methodChannelName, 'geneedge/bluemagpie_tts');
      expect(
        BlueMagpieTts.eventChannelName,
        'geneedge/bluemagpie_tts/events',
      );

      final eventFuture = tts.events.first;
      channel.emit({
        'requestId': 'smoke-1',
        'state': 'synthesizing',
        'progress': 0.25,
        'timestampMs': 1234,
        'errorCode': null,
        'futureNativeField': true,
      });

      final event = await eventFuture;
      expect(event.requestId, 'smoke-1');
      expect(event.state, BlueMagpieState.synthesizing);
      expect(event.progress, 0.25);
      expect(event.timestampMs, 1234);
      expect(event.errorCode, isNull);
    });

    test('probe and model validation have stable typed serialization',
        () async {
      final channel = FakeBlueMagpieTtsChannel(responses: {
        'probe': {
          'available': true,
          'runtimeRevision': '7d5cf82',
          'abi': 'arm64-v8a',
          'backend': 'cpu',
          'deviceMemoryClassMb': 8192,
        },
        'validateModels': {
          'state': 'ready',
          'freeSpaceBytes': 5000000000,
          'requiredSpaceBytes': 2500000000,
          'models': [
            {
              'id': 'barbet',
              'fileName': 'BlueMagpie-Barbet-1B-q4_k_m.gguf',
              'state': 'ready',
              'sizeBytes': 661000000,
            },
          ],
        },
      });
      final tts = BlueMagpieTts(channel: channel);

      final probe = await tts.probe();
      final validation = await tts.validateModels();

      expect(probe.available, isTrue);
      expect(probe.backend, BlueMagpieBackend.cpu);
      expect(probe.toMap()['runtimeRevision'], '7d5cf82');
      expect(validation.state, BlueMagpieState.ready);
      expect(validation.models.single.id, 'barbet');
      expect(validation.toMap()['freeSpaceBytes'], 5000000000);
    });

    test('duplicate initialize shares one native operation and ready result',
        () async {
      final completer = Completer<Object?>();
      final channel = FakeBlueMagpieTtsChannel();
      channel.handlers['initialize'] = (_) => completer.future;
      final tts = BlueMagpieTts(channel: channel);

      final first = tts.initialize(backend: BlueMagpieBackend.vulkan);
      final duplicate = tts.initialize(backend: BlueMagpieBackend.vulkan);
      expect(channel.calls.where((call) => call.method == 'initialize'),
          hasLength(1));

      completer.complete({
        'state': 'ready',
        'backend': 'vulkan',
        'elapsedMs': 100,
        'rssBeforeBytes': 10,
        'rssAfterBytes': 20,
      });
      final firstResult = await first;
      expect(await duplicate, same(firstResult));

      expect(await tts.initialize(backend: BlueMagpieBackend.vulkan),
          same(firstResult));
      expect(channel.calls.where((call) => call.method == 'initialize'),
          hasLength(1));
    });

    test('synthesize validates Traditional Chinese input before native call',
        () async {
      final channel = FakeBlueMagpieTtsChannel();
      final tts = BlueMagpieTts(channel: channel);

      await expectLater(
        tts.synthesize(requestId: 'empty', text: '   '),
        throwsA(
          isA<BlueMagpieTtsException>().having(
            (error) => error.code,
            'code',
            BlueMagpieErrorCode.invalidText,
          ),
        ),
      );
      await expectLater(
        tts.synthesize(requestId: 'long', text: '今' * 201),
        throwsA(isA<BlueMagpieTtsException>()),
      );
      expect(channel.calls, isEmpty);
    });

    test('successful synthesis returns typed finite metrics', () async {
      final channel = FakeBlueMagpieTtsChannel(responses: {
        'synthesize': {
          'wavToken': 'cache:smoke-1.wav',
          'sampleRate': 48000,
          'samples': 96000,
          'durationMs': 2000,
          'firstAudioMs': 250,
          'elapsedMs': 1500,
          'peakRssBytes': 3200000000,
        },
      });
      final tts = BlueMagpieTts(channel: channel);

      final result = await tts.synthesize(
        requestId: 'smoke-1',
        text: '今天天氣真好，我們一起去散步吧。',
      );

      expect(result.wavToken, 'cache:smoke-1.wav');
      expect(result.sampleRate, 48000);
      expect(result.durationMs, 2000);
      expect(channel.calls.single.arguments, {
        'requestId': 'smoke-1',
        'text': '今天天氣真好，我們一起去散步吧。',
      });
    });

    test('cancel and release are idempotent', () async {
      final channel = FakeBlueMagpieTtsChannel();
      final tts = BlueMagpieTts(channel: channel);

      await tts.cancel('smoke-1');
      await tts.cancel('smoke-1');
      await tts.release();
      await tts.release();

      expect(
          channel.calls.where((call) => call.method == 'cancel'), hasLength(1));
      expect(
        channel.calls.where((call) => call.method == 'release'),
        hasLength(1),
      );
    });

    test('maps every stable native error and does not expose native details',
        () async {
      for (final code in BlueMagpieErrorCode.values) {
        if (code == BlueMagpieErrorCode.unknown) continue;
        final channel = FakeBlueMagpieTtsChannel();
        channel.handlers['probe'] = (_) => throw PlatformException(
              code: code.wireName,
              message: '/private/secret/model.gguf failed at 0x1234',
              details: {'stack': 'native memory'},
            );
        final tts = BlueMagpieTts(channel: channel);

        await expectLater(
          tts.probe(),
          throwsA(
            isA<BlueMagpieTtsException>()
                .having((error) => error.code, 'code', code)
                .having(
                  (error) => error.safeMessage,
                  'safeMessage',
                  isNot(contains('/private/')),
                ),
          ),
        );
      }
    });
  });
}

class FakeBlueMagpieTtsChannel implements BlueMagpieTtsChannel {
  FakeBlueMagpieTtsChannel({Map<String, Object?>? responses})
      : responses = responses ?? <String, Object?>{};

  final Map<String, Object?> responses;
  final Map<String, FutureOr<Object?> Function(Map<String, Object?>?)>
      handlers = {};
  final List<FakeChannelCall> calls = [];
  final StreamController<Object?> _events = StreamController.broadcast();

  void emit(Object? event) => _events.add(event);

  @override
  Stream<Object?> get events => _events.stream;

  @override
  Future<Object?> invokeMethod(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    calls.add(FakeChannelCall(method, arguments));
    final handler = handlers[method];
    if (handler != null) return handler(arguments);
    return responses[method];
  }
}

class FakeChannelCall {
  const FakeChannelCall(this.method, this.arguments);

  final String method;
  final Map<String, Object?>? arguments;
}
