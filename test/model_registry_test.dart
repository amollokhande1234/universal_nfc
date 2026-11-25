import 'package:test/test.dart';
import 'package:universal_nfc/universal_nfc.dart';

NfcTagModel<String> m(String id, Set<String> keys) =>
    NfcTagModel<String>.define(id: id, requiredKeys: keys, parse: (_) => id);

void main() {
  test('auto-detects by required keys, most specific wins', () {
    final r = NfcModelRegistry()
      ..register(m('basic', {'ind'}))
      ..register(m('full', {'ind', 'sub'}));
    expect(r.resolve({'ind': '1'})!.id, 'basic');
    expect(r.resolve({'ind': '1', 'sub': '2'})!.id, 'full');
    expect(r.resolve({'x': '1'}), isNull);
  });

  test('explicit model key wins and an unknown id gives null', () {
    final r = NfcModelRegistry()
      ..register(m('basic', {'ind'}))
      ..register(m('other', {'zzz'}));
    expect(r.resolve({'m': 'other', 'ind': '1'})!.id, 'other');
    expect(r.resolve({'m': 'nope', 'ind': '1'}), isNull);
  });

  test('model key can be disabled', () {
    final r = NfcModelRegistry(modelKey: null)..register(m('basic', {'ind'}));
    expect(r.resolve({'m': 'x', 'ind': '1'})!.id, 'basic');
  });

  test('duplicate id throws unless replaced; unregister works', () {
    final r = NfcModelRegistry()..register(m('a', {'x'}));
    expect(() => r.register(m('a', {'y'})), throwsArgumentError);
    r.register(m('a', {'y'}), replace: true);
    expect(r.resolve({'y': '1'})!.id, 'a');
    expect(r.unregister('a'), isTrue);
    expect(r.unregister('a'), isFalse);
    expect(r.models, isEmpty);
  });

  test('a model with no required keys never auto-matches', () {
    final r = NfcModelRegistry()..register(m('open', {}));
    expect(r.resolve({'a': '1'}), isNull);
    expect(r.resolve({'m': 'open'})!.id, 'open');
  });
}
