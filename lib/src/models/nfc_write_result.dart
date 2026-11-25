/// Outcome of writing a tag.
class NfcWriteResult {
  const NfcWriteResult.success(
      {required this.bytesUsed, required this.capacity})
      : ok = true,
        error = null;

  const NfcWriteResult.failure(String this.error,
      {this.bytesUsed = 0, this.capacity = 0})
      : ok = false;

  final bool ok;

  /// Why the write failed (null on success).
  final String? error;

  /// Bytes now used in the tag's data area (including NDEF framing).
  final int bytesUsed;

  /// Size of the tag's data area.
  final int capacity;

  int get bytesFree => capacity - bytesUsed;

  @override
  String toString() => ok
      ? 'NfcWriteResult(ok, $bytesUsed of $capacity bytes used)'
      : 'NfcWriteResult(failed: $error)';
}
