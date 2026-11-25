import 'package:test/test.dart';
import 'package:universal_nfc/universal_nfc.dart';

void main() {
  final data = <String, Object?>{
    'n': 5,
    's': '7',
    'f': 2.5,
    'whole': 3.0,
    'b': true,
    'bs': 'No',
    'text': 'hi',
    'obj': {'k': 1},
    'list': [1, 2],
  };

  test('integer accepts numbers and numeric text', () {
    expect(data.integer('n'), 5);
    expect(data.integer('s'), 7);
    expect(data.integer('whole'), 3);
    expect(data.integer('f'), isNull); // 2.5 is not a whole number
    expect(data.integer('missing'), isNull);
    expect(data.integer('text'), isNull);
  });

  test('str ignores objects and lists', () {
    expect(data.str('text'), 'hi');
    expect(data.str('n'), '5');
    expect(data.str('obj'), isNull);
    expect(data.str('list'), isNull);
  });

  test('boolean accepts bools and common words', () {
    expect(data.boolean('b'), isTrue);
    expect(data.boolean('bs'), isFalse);
    expect(data.boolean('text'), isNull);
  });

  test('object and list', () {
    expect(data.object('obj'), {'k': 1});
    expect(data.list('list'), [1, 2]);
    expect(data.object('list'), isNull);
  });

  test('require* throw FormatException when missing', () {
    expect(data.requireInt('n'), 5);
    expect(data.requireString('text'), 'hi');
    expect(() => data.requireInt('nope'), throwsFormatException);
    expect(() => data.requireString('obj'), throwsFormatException);
  });
}
