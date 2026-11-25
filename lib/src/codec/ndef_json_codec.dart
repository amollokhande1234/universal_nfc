import 'dart:convert';

import '../models/nfc_data.dart';
import 'ndef_text_parser.dart';
import 'nfc_tag_codec.dart';

/// Default layout: one NDEF Text record whose text is a JSON object, e.g.
/// `{"ind":"2","sub":"1","pass":{"zone":"A","days":[1,2,3]}}`.
///
/// Standard NDEF, so phones can read these tags too.
class NdefJsonCodec extends NfcTagCodec {
  const NdefJsonCodec({this.language = 'en'});

  /// Language code stored in the text record.
  final String language;

  @override
  int? requiredLength(List<int> bytes) => NdefTextParser.payloadEnd(bytes);

  @override
  NfcDecodeResult decode(List<int> bytes) {
    final parsed = NdefTextParser.parse(bytes);
    if (!parsed.isOk) return NfcDecodeResult.fail(parsed.error!);
    return decodeText(parsed.text!);
  }

  @override
  List<int> encode(NfcData data) {
    if (data.isEmpty) throw ArgumentError('Nothing to write: data is empty.');
    return NdefTextParser.encodeTextRecord(jsonEncode(data),
        language: language);
  }

  /// JSON text -> data. Public so platform backends that already receive the
  /// NDEF text (Android/iOS) can reuse it. Top-level null values are dropped.
  static NfcDecodeResult decodeText(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map || decoded.isEmpty) {
        return NfcDecodeResult.fail(
          'Tag text is not a non-empty JSON object.',
          rawText: text,
        );
      }
      final fields = <String, Object?>{};
      decoded.forEach((k, v) {
        if (v != null) fields[k.toString()] = v;
      });
      if (fields.isEmpty) {
        return NfcDecodeResult.fail('No valid fields in JSON.', rawText: text);
      }
      return NfcDecodeResult.ok(fields, rawText: text);
    } catch (e) {
      return NfcDecodeResult.fail('Invalid JSON: $e', rawText: text);
    }
  }
}
