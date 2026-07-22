import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geneapp/bluemagpie_tts.dart';

void main() {
  test('play accepts only opaque private-cache WAV tokens', () async {
    final channel = _PlaybackFakeChannel();
    final tts = BlueMagpieTts(channel: channel);

    await tts.play('cache:smoke.wav');
    expect(channel.calls.single, <String, Object?>{
      'method': 'play',
      'wavToken': 'cache:smoke.wav',
    });

    await expectLater(
      tts.play('/sdcard/Download/untrusted.wav'),
      throwsA(isA<ArgumentError>()),
    );
    expect(channel.calls, hasLength(1));
  });
}

class _PlaybackFakeChannel implements BlueMagpieTtsChannel {
  final List<Map<String, Object?>> calls = <Map<String, Object?>>[];

  @override
  Stream<Object?> get events => const Stream<Object?>.empty();

  @override
  Future<Object?> invokeMethod(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    calls.add(<String, Object?>{
      'method': method,
      ...?arguments,
    });
    return null;
  }
}
