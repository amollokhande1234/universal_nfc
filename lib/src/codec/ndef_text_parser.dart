import 'dart:convert';

/// Result of [NdefTextParser.parse].
class NdefTextResult {
  const NdefTextResult.ok(String this.text) : error = null;
  const NdefTextResult.fail(String this.error) : text = null;

  final String? text;
  final String? error;
  bool get isOk => text != null;
}

/// Pure-Dart helper that finds an NDEF Text record (TNF=Well Known, type "T")
/// inside raw tag memory bytes and extracts its text, and builds such records
/// for writing. No hardware access, so it can be unit tested.
class NdefTextParser {
  const NdefTextParser._();

  static const int _textType = 0x54; // 'T'

  /// Index just past the end of the text record payload, or null if the
  /// record header has not been seen yet. Used to know when to stop reading pages.
  static int? payloadEnd(List<int> bytes) {
    final rec = _find(bytes);
    return rec == null ? null : rec.start + rec.length;
  }

  static NdefTextResult parse(List<int> bytes) {
    final rec = _find(bytes);
    if (rec == null) {
      return const NdefTextResult.fail('NDEF Text record not found');
    }
    final end = rec.start + rec.length;
    if (end > bytes.length) {
      return NdefTextResult.fail(
        'Incomplete NDEF payload (expected $end bytes, have ${bytes.length})',
      );
    }
    final payload = bytes.sublist(rec.start, end);
    if (payload.isEmpty) return const NdefTextResult.fail('Empty NDEF payload');

    final status = payload[0];
    if ((status & 0x80) != 0) {
      return const NdefTextResult.fail('UTF-16 NDEF text is not supported');
    }
    final textStart = 1 + (status & 0x3F); // skip status byte + language code
    if (textStart >= payload.length) {
      return const NdefTextResult.fail('No text data found');
    }
    try {
      return NdefTextResult.ok(
        utf8.decode(payload.sublist(textStart)).trim(),
      );
    } catch (e) {
      return NdefTextResult.fail('UTF-8 decode failed: $e');
    }
  }

  /// Builds one complete NDEF Text record (the NDEF *message* of a tag that
  /// holds a single record).
  static List<int> encodeTextRecord(String text, {String language = 'en'}) {
    final lang = utf8.encode(language);
    if (lang.length > 63) {
      throw ArgumentError('Language code is too long: "$language"');
    }
    final payload = <int>[lang.length, ...lang, ...utf8.encode(text)];
    if (payload.length <= 0xFF) {
      // MB | ME | SR | TNF=well-known
      return [0xD1, 0x01, payload.length, _textType, ...payload];
    }
    final n = payload.length;
    // MB | ME | TNF=well-known, 4-byte payload length
    return [
      0xC1, 0x01,
      (n >> 24) & 0xFF, (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF,
      _textType,
      ...payload,
    ];
  }

  /// Looks for a record header: [flags][typeLen=1][payloadLen...]['T'].
  /// Supports short records (SR=1, 1-byte length) and normal records (4-byte length).
  static _Rec? _find(List<int> b) {
    for (var i = 0; i + 3 < b.length; i++) {
      final flags = b[i];
      final tnf = flags & 0x07;
      final isShort = (flags & 0x10) != 0;
      final hasId = (flags & 0x08) != 0;
      if (tnf != 0x01 || hasId || b[i + 1] != 0x01) continue;

      if (isShort) {
        if (b[i + 3] != _textType) continue;
        return _Rec(start: i + 4, length: b[i + 2]);
      }
      if (i + 6 >= b.length || b[i + 6] != _textType) continue;
      final len =
          (b[i + 2] << 24) | (b[i + 3] << 16) | (b[i + 4] << 8) | b[i + 5];
      return _Rec(start: i + 7, length: len);
    }
    return null;
  }
}

class _Rec {
  const _Rec({required this.start, required this.length});
  final int start;
  final int length;
}
