import "package:flutter_blue_plus/flutter_blue_plus.dart";

class AppConfig {
  static const int scanSeconds = 5;
  static const String preferredNamePrefix = "";

  // Must match edge Python gateway UUIDs.
  static final Guid serviceUuid = Guid("12345678-1234-5678-1234-56789abcdef0");
  static final Guid cmdUuid = Guid("12345678-1234-5678-1234-56789abcdef1");
  static final Guid resUuid = Guid("12345678-1234-5678-1234-56789abcdef2");
  static final Guid offUuid = Guid("12345678-1234-5678-1234-56789abcdef3");
}
