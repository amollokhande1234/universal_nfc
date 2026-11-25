/// Thrown when NFC cannot be used (unsupported platform, PC/SC failure, ...).
class NfcReaderException implements Exception {
  const NfcReaderException(this.message, {this.code});

  final String message;

  /// Raw platform error code, when available.
  final int? code;

  @override
  String toString() =>
      'NfcReaderException: $message${code != null ? ' (rc=$code)' : ''}';
}
