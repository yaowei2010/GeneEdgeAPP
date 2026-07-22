import "package:flutter/services.dart";

class OfflineTaigiAsr {
  static const MethodChannel _channel = MethodChannel("geneedge/taigi_asr");

  Future<String> recordWav({int durationSeconds = 5}) async {
    final path = await _channel.invokeMethod<String>("recordWav", {
      "durationSeconds": durationSeconds,
    });
    if (path == null || path.isEmpty) {
      throw Exception("No WAV path returned from native recorder.");
    }
    return path;
  }

  Future<OfflineTaigiAsrResult> transcribeWav(String path) async {
    final raw =
        await _channel.invokeMapMethod<String, dynamic>("transcribeWav", {
      "path": path,
    });
    if (raw == null) {
      throw Exception("No ASR result returned from native engine.");
    }
    return OfflineTaigiAsrResult.fromMap(raw);
  }
}

class OfflineTaigiAsrResult {
  final String text;
  final bool engineInstalled;
  final String message;

  const OfflineTaigiAsrResult({
    required this.text,
    required this.engineInstalled,
    required this.message,
  });

  factory OfflineTaigiAsrResult.fromMap(Map<String, dynamic> map) {
    return OfflineTaigiAsrResult(
      text: map["text"]?.toString() ?? "",
      engineInstalled: (map["engineInstalled"] as bool?) ?? false,
      message: map["message"]?.toString() ?? "",
    );
  }
}
