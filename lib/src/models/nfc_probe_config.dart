/// How often the reader probe runs. The default (200 ms) is what the package
/// always did, so existing apps behave exactly as before.
///
/// ```dart
/// UniversalNfc(probe: const NfcProbeConfig());                // default, 200 ms
/// UniversalNfc(probe: const NfcProbeConfig.milliseconds(100)); // faster
/// UniversalNfc(probe: const NfcProbeConfig.seconds(2));        // gentler
/// UniversalNfc(probe: const NfcProbeConfig.off());             // regular 1 s scan only
/// ```
class NfcProbeConfig {
  const NfcProbeConfig({
    this.enabled = true,
    this.interval = const Duration(milliseconds: 200),
  });

  /// Check every [milliseconds].
  NfcProbeConfig.milliseconds(int milliseconds)
      : enabled = true,
        interval = Duration(milliseconds: milliseconds);

  /// Check every [seconds].
  NfcProbeConfig.seconds(int seconds)
      : enabled = true,
        interval = Duration(seconds: seconds);

  /// No fast probe.
  const NfcProbeConfig.off()
      : enabled = false,
        interval = const Duration(milliseconds: 200);

  final bool enabled;
  final Duration interval;

  static const Duration minInterval = Duration(milliseconds: 50);

  Duration get effectiveInterval =>
      interval < minInterval ? minInterval : interval;

  @override
  String toString() => enabled
      ? 'NfcProbeConfig(every ${effectiveInterval.inMilliseconds} ms)'
      : 'NfcProbeConfig(off)';
}

/// Implemented by backends whose probe can be changed while running
/// (the Windows PC/SC backend).
abstract interface class ProbeConfigurable {
  void updateProbe(NfcProbeConfig config);
}
