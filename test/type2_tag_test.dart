import 'package:test/test.dart';
import 'package:universal_nfc/universal_nfc.dart';

const codec = NdefJsonCodec();

/// Applies a plan to a memory image, like the reader would.
List<int> apply(List<int> memory, Type2WritePlan plan) {
  final out = [...memory];
  final start = plan.startPage * 4;
  for (var i = 0; i < plan.bytes.length; i++) {
    out[start + i] = plan.bytes[i];
  }
  return out;
}

List<int> blank(int size) => List<int>.filled(size, 0);

void main() {
  group('capability container', () {
    test('NTAG213 / 215 / 216 sizes', () {
      expect(Type2Capability.parse([0xE1, 0x10, 0x12, 0x00])!.dataAreaBytes, 144);
      expect(Type2Capability.parse([0xE1, 0x10, 0x3E, 0x00])!.dataAreaBytes, 496);
      expect(Type2Capability.parse([0xE1, 0x10, 0x6D, 0x00])!.dataAreaBytes, 872);
    });

    test('not NDEF formatted', () {
      expect(Type2Capability.parse([0x00, 0x00, 0x00, 0x00]), isNull);
      expect(Type2Capability.parse([0xE1, 0x10]), isNull);
    });

    test('write access flag', () {
      expect(Type2Capability.parse([0xE1, 0x10, 0x12, 0x00])!.writable, isTrue);
      expect(Type2Capability.parse([0xE1, 0x10, 0x12, 0x0F])!.writable, isFalse);
    });
  });

  group('findNdefStart', () {
    test('blank tag: start at 0', () {
      expect(Type2Layout.findNdefStart(blank(16)), 0);
    });

    test('factory empty NDEF TLV', () {
      expect(Type2Layout.findNdefStart([0x03, 0x00, 0xFE, 0x00]), 0);
    });

    test('skips a Lock Control TLV', () {
      final mem = [0x01, 0x03, 0xA0, 0x0C, 0x34, 0x03, 0x00, 0xFE];
      expect(Type2Layout.findNdefStart(mem), 5);
    });

    test('null when it runs off the known bytes', () {
      expect(Type2Layout.findNdefStart([0x01]), isNull);
      expect(Type2Layout.findNdefStart([0x01, 0x10, 0xAA]), isNull);
    });
  });

  group('wrapTlv', () {
    test('short message', () {
      expect(Type2Layout.wrapTlv([1, 2, 3]), [0x03, 3, 1, 2, 3, 0xFE]);
    });

    test('long message uses a 3-byte length', () {
      final tlv = Type2Layout.wrapTlv(List<int>.filled(300, 7));
      expect(tlv.sublist(0, 4), [0x03, 0xFF, 0x01, 0x2C]);
      expect(tlv.last, 0xFE);
      expect(tlv.length, 300 + 5);
    });
  });

  group('plan', () {
    test('blank NTAG213: writes, page aligned, decodes back', () {
      final mem = blank(144);
      final msg = codec.encode({'ind': '2', 'sub': '1'});
      final plan = Type2Layout.plan(memory: mem, message: msg, dataAreaBytes: 144);

      expect(plan.bytes.length % 4, 0);
      expect(plan.startPage, 0);
      expect(plan.usedBytes, msg.length + 3);
      expect(codec.decode(apply(mem, plan)).fields, {'ind': '2', 'sub': '1'});
    });

    test('keeps the Lock Control TLV in front of the message', () {
      final mem = blank(144)..setRange(0, 5, [0x01, 0x03, 0xA0, 0x0C, 0x34]);
      final msg = codec.encode({'ind': '2', 'sub': '1'});
      final plan = Type2Layout.plan(memory: mem, message: msg, dataAreaBytes: 144);
      final after = apply(mem, plan);

      expect(plan.startPage, 1); // page 0 holds bytes before the NDEF TLV
      expect(after.sublist(0, 5), [0x01, 0x03, 0xA0, 0x0C, 0x34]);
      expect(codec.decode(after).fields, {'ind': '2', 'sub': '1'});
    });

    test('replaces an existing, longer message', () {
      final mem = blank(144);
      final long = codec.encode({'text': 'a' * 60});
      final first = Type2Layout.plan(memory: mem, message: long, dataAreaBytes: 144);
      final written = apply(mem, first);

      final short = codec.encode({'x': '1'});
      final second =
          Type2Layout.plan(memory: written, message: short, dataAreaBytes: 144);
      expect(codec.decode(apply(written, second)).fields, {'x': '1'});
    });

    test('refuses data that does not fit, with a clear message', () {
      final msg = codec.encode({'text': 'a' * 200});
      expect(
        () => Type2Layout.plan(memory: blank(144), message: msg, dataAreaBytes: 144),
        throwsA(isA<Type2WriteException>()
            .having((e) => e.message, 'message', contains('Use less data'))),
      );
    });

    test('same data fits a bigger tag', () {
      final msg = codec.encode({'text': 'a' * 200});
      final plan =
          Type2Layout.plan(memory: blank(496), message: msg, dataAreaBytes: 496);
      expect(plan.capacity, 496);
      expect(plan.usedBytes, lessThanOrEqualTo(496));
    });

    test('never plans a write outside the data area', () {
      final msg = codec.encode({'ind': '2'});
      final plan = Type2Layout.plan(memory: blank(144), message: msg, dataAreaBytes: 144);
      expect(plan.startPage * 4 + plan.bytes.length, lessThanOrEqualTo(144));
    });
  });
}
