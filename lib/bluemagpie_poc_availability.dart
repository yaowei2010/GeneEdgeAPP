import 'package:flutter/foundation.dart';

/// Centralized fail-closed visibility rule for the developer-only PoC entry.
abstract final class BlueMagpiePocAvailability {
  static bool canShowEntry({
    required bool featureEnabled,
    required bool debugMode,
    required TargetPlatform platform,
    required bool isArm64,
  }) {
    return featureEnabled &&
        debugMode &&
        platform == TargetPlatform.android &&
        isArm64;
  }
}
