import "dart:convert";
import "dart:io";
import "package:flutter/foundation.dart";
import "package:flutter/services.dart";
import "package:path_provider/path_provider.dart";

class LocalPayloadLoader {
  static const String _assetPath = "assets/mock/local_payload.json";
  static const String _fileName = "local_payload.json";

  static Future<String?> getExternalPayloadPath() async {
    if (!Platform.isAndroid) return null;
    final dir = await getExternalStorageDirectory();
    if (dir == null) return null;
    return "${dir.path}/$_fileName";
  }

  static Future<Map<String, dynamic>> load() async {
    final externalPath = await getExternalPayloadPath();
    if (externalPath != null) {
      final f = File(externalPath);
      if (await f.exists()) {
        try {
          final raw = await f.readAsString();
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) return decoded;
          if (decoded is Map) {
            return decoded.map((k, v) => MapEntry(k.toString(), v));
          }
        } catch (e) {
          debugPrint("[LocalPayload] external json parse failed: $e");
        }
      }
    }

    final raw = await rootBundle.loadString(_assetPath);
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map((k, v) => MapEntry(k.toString(), v));
    }
    throw Exception("Invalid payload JSON: root is not an object.");
  }
}
