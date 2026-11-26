/// Answer of the fast "is a reader plugged in?" check.
enum ProbeStatus {
  /// Not checked yet, or the probe is switched off.
  unknown,

  /// At least one reader is plugged in.
  readerPresent,

  /// The NFC / smart card service works, but no reader is plugged in.
  noReader,

  /// The NFC / smart card service cannot be reached (on Windows: the "Smart
  /// Card" service is stopped). Plugging a reader in will not help until it runs.
  serviceUnavailable,

  /// This platform has no probe (anything but Windows today).
  unsupported,

  /// The check itself failed unexpectedly.
  error,
}
