import 'package:test/test.dart';
import 'package:universal_nfc/universal_nfc.dart';

void main() {
  const codec = NdefJsonCodec();

  test('decodes flat key-values, dropping null values', () {
    final r = NdefJsonCodec.decodeText('{"ind":2,"sub":"1","cha":null}');
    expect(r.fields, {'ind': 2, 'sub': '1'});
  });

  test('keeps nested objects, lists, numbers and booleans', () {
    final r = NdefJsonCodec.decodeText(
      '{"pass":{"zone":"A","days":[1,2,3]},"vip":true,"price":9.5}',
    );
    final f = r.fields!;
    expect(f.object('pass')!.str('zone'), 'A');
    expect(f.object('pass')!.list('days'), [1, 2, 3]);
    expect(f.boolean('vip'), isTrue);
    expect(f.number('price'), 9.5);
  });

  test('rejects non-JSON, arrays and empty objects', () {
    expect(NdefJsonCodec.decodeText('hello').fields, isNull);
    expect(NdefJsonCodec.decodeText('[1,2]').fields, isNull);
    expect(NdefJsonCodec.decodeText('{}').fields, isNull);
  });

  test('encode then decode gives the same data', () {
    final data = <String, Object?>{
      'ind': '2',
      'name': 'आशा',
      'pass': {
        'zone': 'A',
        'days': [1, 2, 3]
      },
    };
    final message = codec.encode(data);
    expect(codec.decode(message).fields, data);
  });

  test('encode refuses empty data', () {
    expect(() => codec.encode({}), throwsArgumentError);
  });

  test('requiredLength tells the reader when to stop', () {
    final message = codec.encode({'a': '1'});
    expect(codec.requiredLength(message), message.length);
    expect(codec.requiredLength([0x01, 0x02]), isNull);
  });
}
