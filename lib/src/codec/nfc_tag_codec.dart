import '../models/nfc_data.dart';

/// Result of decoding raw tag memory.
class NfcDecodeResult {
  const NfcDecodeResult.ok(NfcData this.fields, {this.rawText}) : error = null;
  const NfcDecodeResult.fail(String this.error, {this.rawText}) : fields = null;

  final NfcData? fields;
  final String? rawText;
  final String? error;
}

/// Knows how data is physically laid out on a card and turns it into
/// key/value data (and back, for writing). Swap it to support other layouts
/// (plain `key=value` text, vendor formats, ...). Models then work on the
/// data, whatever the layout was.
abstract class NfcTagCodec {
  const NfcTagCodec();

  /// How many bytes (from the first user page) are needed to decode, once that
  /// can be known from the bytes read so far. Null = keep reading.
  int? requiredLength(List<int> bytes);

  NfcDecodeResult decode(List<int> bytes);

  /// Builds the NDEF message bytes for [data]. Override to support writing.
  List<int> encode(NfcData data) =>
      throw UnsupportedError('This codec cannot write tags.');
}
