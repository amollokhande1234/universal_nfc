/// Hex helpers for logging and debugging raw tag bytes.
class NfcHex {
  const NfcHex._();

  /// `[1, 171]` -> `"01 ab"`.
  static String encode(List<int> bytes, {String separator = ' '}) => bytes
      .map((b) => (b & 0xFF).toRadixString(16).padLeft(2, '0'))
      .join(separator);
}
