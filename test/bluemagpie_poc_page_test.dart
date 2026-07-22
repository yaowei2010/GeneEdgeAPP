import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geneapp/bluemagpie_poc_page.dart';
import 'package:geneapp/bluemagpie_tts.dart';

void main() {
  testWidgets('Chinese text runs probe, validation, init, synthesis and play',
      (tester) async {
    final channel = _PageFakeChannel();
    await tester.pumpWidget(
      MaterialApp(
        home: BlueMagpiePocPage(tts: BlueMagpieTts(channel: channel)),
      ),
    );

    expect(find.text('台灣藍鵲 TTS 手機測試'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('bluemagpie-text-input')),
      '今天天氣真好，我們一起去散步吧。',
    );
    await tester.tap(find.text('合成並播放'));
    await tester.pumpAndSettle();

    expect(channel.methods, <String>[
      'probe',
      'validateModels',
      'initialize',
      'synthesize',
      'play',
    ]);
    expect(find.textContaining('2.0 秒'), findsOneWidget);
    expect(find.textContaining('CPU'), findsWidgets);
  });

  testWidgets('unavailable runtime is shown without attempting model work',
      (tester) async {
    final channel = _PageFakeChannel(runtimeAvailable: false);
    await tester.pumpWidget(
      MaterialApp(
        home: BlueMagpiePocPage(tts: BlueMagpieTts(channel: channel)),
      ),
    );

    await tester.tap(find.text('合成並播放'));
    await tester.pumpAndSettle();

    expect(channel.methods, <String>['probe']);
    expect(find.textContaining('runtime_missing'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _PageFakeChannel implements BlueMagpieTtsChannel {
  _PageFakeChannel({this.runtimeAvailable = true});

  final bool runtimeAvailable;
  final List<String> methods = <String>[];

  @override
  Stream<Object?> get events => const Stream<Object?>.empty();

  @override
  Future<Object?> invokeMethod(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    methods.add(method);
    switch (method) {
      case 'probe':
        return <String, Object?>{
          'available': runtimeAvailable,
          'runtimeRevision': '7d5cf82',
          'abi': 'arm64-v8a',
          'backend': 'cpu',
          'deviceMemoryClassMb': 8192,
          if (!runtimeAvailable) 'errorCode': 'runtime_missing',
        };
      case 'validateModels':
        return <String, Object?>{
          'state': 'ready',
          'freeSpaceBytes': 5000000000,
          'requiredSpaceBytes': 2500000000,
          'models': <Object?>[
            <String, Object?>{
              'id': 'barbet',
              'fileName': 'BlueMagpie-Barbet-1B-q4_k_m.gguf',
              'state': 'ready',
              'sizeBytes': 661000000,
            },
            <String, Object?>{
              'id': 'audiovae',
              'fileName': 'BlueMagpie-AudioVAE.gguf',
              'state': 'ready',
              'sizeBytes': 1760000000,
            },
          ],
        };
      case 'initialize':
        return <String, Object?>{
          'state': 'ready',
          'backend': 'cpu',
          'elapsedMs': 100,
          'rssBeforeBytes': 10,
          'rssAfterBytes': 20,
        };
      case 'synthesize':
        return <String, Object?>{
          'wavToken': 'cache:smoke.wav',
          'sampleRate': 48000,
          'samples': 96000,
          'durationMs': 2000,
          'firstAudioMs': 250,
          'elapsedMs': 1500,
          'peakRssBytes': 3200000000,
        };
      case 'play':
        return null;
      default:
        throw StateError('Unexpected method: $method');
    }
  }
}
