/// Compile-time switches for the Android-only BlueMagpie diagnostic PoC.
abstract final class BlueMagpiePocConfig {
  /// Opt in with `--dart-define=BLUEMAGPIE_POC=true`.
  ///
  /// Platform and debug-build checks belong to the diagnostic entry point; this
  /// value intentionally only represents the compile-time request.
  static const bool enabled = bool.fromEnvironment(
    'BLUEMAGPIE_POC',
    defaultValue: false,
  );
}
