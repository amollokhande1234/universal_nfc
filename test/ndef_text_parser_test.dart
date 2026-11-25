import 'dart:convert';

import 'package:test/test.dart';
import 'package:universal_nfc/universal_nfc.dart';

/// What a real NTAG looks like: Lock Control TLV, then the NDEF TLV.
List<int> tag(String json) {
  final record = NdefTextParser.encodeTextRecord(json);
  return [
    0x01, 0x03, 0xA0, 0x0C, 0x34, // Lock Control TLV
    ...Type2Layout.wrapTlv(record),
  ];
}

void main() {
  group('reading', () {
    test('extracts the text of a short record', () {
      final r = NdefTextParser.parse(tag('{"ind":"2"}'));
      expect(r.isOk, isTrue);
      expect(r.text, '{"ind":"2"}');
    });

    test('payloadEnd is null until the header is available', () {
      expect(NdefTextParser.payloadEnd([0x01, 0x03, 0xA0]), isNull);
      expect(NdefTextParser.payloadEnd(tag('{"a":"1"}')), isNotNull);
    });

    test('reports an incomplete payload', () {
      final bytes = tag('{"ind":"2","sub":"1"}');
      expect(NdefTextParser.parse(bytes.sublist(0, 14)).text, isNull);
    });

    test('fails when there is no text record', () {
      expect(NdefTextParser.parse([0, 0, 0, 0, 0, 0]).isOk, isFalse);
    });
  });

  group('writing', () {
    test('short record round trip', () {
      final bytes = NdefTextParser.encodeTextRecord('hello');
      expect(bytes.first, 0xD1);
      expect(NdefTextParser.parse(bytes).text, 'hello');
    });

    test('long record (over 255 bytes) round trip', () {
      final text = 'x' * 400;
      final bytes = NdefTextParser.encodeTextRecord(text);
      expect(bytes.first, 0xC1);
      expect(NdefTextParser.parse(bytes).text, text);
    });

    test('unicode text round trip (Marathi)', () {
      const text = 'आशा देशमुख';
      final bytes = NdefTextParser.encodeTextRecord(text);
      expect(NdefTextParser.parse(bytes).text, text);
      expect(utf8.encode(text).length, greaterThan(text.length));
    });
  });
}
