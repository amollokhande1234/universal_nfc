import 'dart:async';

import 'package:test/test.dart';
import 'package:universal_nfc/universal_nfc.dart';

/// A fake reader: drives the whole lifecycle without hardware. It is also the
/// template for supporting a brand-new reader type.
class FakeBackend implements NfcBackend {
  final _c = StreamController<BackendEvent>.broadcast();
  NfcWriteResult nextWrite =
      const NfcWriteResult.success(bytesUsed: 30, capacity: 144);
  NfcData? lastWritten;

  void emit(BackendEvent e) => _c.add(e);

  @override
  Stream<BackendEvent> get events => _c.stream;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<NfcWriteResult> write(NfcData data) async {
    lastWritten = data;
    return nextWrite;
  }

  @override
  Future<NfcDiagnostics> diagnose() async => const NfcDiagnostics(
      platform: 'Fake', supported: true, serviceReachable: true);
  @override
  Future<void> dispose() => _c.close();
}

class IndustryTag {
  IndustryTag(this.industry, this.sector, {this.process});
  final int industry, sector;
  final int? process;
}

void main() {
  final industry = NfcTagModel<IndustryTag>.define(
    id: 'industry',
    requiredKeys: {'ind', 'sub'},
    parse: (f) => IndustryTag(
      f.requireInt('ind'),
      f.requireInt('sub'),
      process: f.integer('cat'),
    ),
  );

  late FakeBackend backend;
  late UniversalNfc nfc;
  late List<NfcEvent> events;

  setUp(() async {
    backend = FakeBackend();
    nfc = UniversalNfc(backend: backend, models: [industry]);
    events = [];
    nfc.events.listen(events.add);
    await nfc.start();
  });

  tearDown(() => nfc.dispose());

  test('full lifecycle: connect, tag read, tag removed, disconnect', () async {
    backend
      ..emit(const ReaderAttached('ACS ACR1552', profileId: 'acr1552'))
      ..emit(const TagArrived())
      ..emit(const TagFields({'ind': '2', 'sub': 1, 'cat': '3'}, uid: '04A1B2'))
      ..emit(const TagLeft())
      ..emit(const ReaderDetached('ACS ACR1552'));
    await pumpEventQueue();

    expect(events.map((e) => e.runtimeType).toList(), [
      NfcStateChanged, // waitingForReader
      ReaderConnected,
      NfcStateChanged, // listening
      TagDetected,
      NfcStateChanged, // tagPresent
      TagRead,
      TagRemoved,
      NfcStateChanged, // listening
      ReaderDisconnected,
      NfcStateChanged, // waitingForReader
    ]);

    final read = events.whereType<TagRead>().single;
    final tag = read.valueAs<IndustryTag>()!;
    expect(tag.industry, 2);
    expect(tag.sector, 1);
    expect(tag.process, 3);
    expect(read.uid, '04A1B2');
    expect(nfc.state, NfcReaderState.waitingForReader);
  });

  test('start does not need a reader', () {
    expect(nfc.state, NfcReaderState.waitingForReader);
    expect(nfc.isReaderConnected, isFalse);
  });

  test('unknown tag is reported with its raw data', () async {
    backend.emit(const TagFields({'zzz': '1'}, rawBytes: [1, 2, 255]));
    await pumpEventQueue();
    final e = events.whereType<UnknownTag>().single;
    expect(e['zzz'], '1');
    expect(e.rawHex, '01 02 ff');
  });

  test('a model that throws becomes TagUnreadable, not a crash', () async {
    backend.emit(const TagFields({'ind': 'abc', 'sub': '1'}));
    await pumpEventQueue();
    expect(events.whereType<TagUnreadable>(), hasLength(1));
    expect(events.whereType<TagRead>(), isEmpty);
  });

  test('an explicit model id with missing keys is unreadable', () async {
    backend.emit(const TagFields({'m': 'industry', 'ind': '2'}));
    await pumpEventQueue();
    expect(events.whereType<TagUnreadable>().single.error, contains('sub'));
  });

  test('read failures from the backend become TagUnreadable', () async {
    backend.emit(const TagReadFailed('blank tag', uid: 'AA'));
    await pumpEventQueue();
    final e = events.whereType<TagUnreadable>().single;
    expect(e.error, 'blank tag');
    expect(e.uid, 'AA');
  });

  test('models can be added while running', () async {
    nfc.models.register(NfcTagModel<String>.define(
      id: 'name',
      requiredKeys: {'name'},
      parse: (f) => f.requireString('name'),
    ));
    backend.emit(const TagFields({'name': 'rose'}));
    await pumpEventQueue();
    expect(events.whereType<TagRead>().single.valueAs<String>(), 'rose');
  });

  test('nested data reaches the model', () async {
    nfc.models.register(NfcTagModel<List<Object?>>.define(
      id: 'pass',
      requiredKeys: {'pass'},
      parse: (f) => f.object('pass')!.list('days')!,
    ));
    backend.emit(const TagFields({
      'pass': {
        'zone': 'A',
        'days': [1, 2, 3]
      },
    }));
    await pumpEventQueue();
    expect(events.whereType<TagRead>().single.value, [1, 2, 3]);
  });

  group('write', () {
    test('refuses when no tag is on the reader', () async {
      final r = await nfc.write({'a': '1'});
      expect(r.ok, isFalse);
      expect(r.error, contains('Place a tag'));
      expect(backend.lastWritten, isNull);
    });

    test('writes and reports TagWritten; modelId is stored on the tag',
        () async {
      backend
        ..emit(const ReaderAttached('R'))
        ..emit(const TagArrived());
      await pumpEventQueue();

      final r = await nfc.write({'ind': '2', 'sub': '1'}, modelId: 'industry');
      await pumpEventQueue();

      expect(r.ok, isTrue);
      expect(backend.lastWritten, {'m': 'industry', 'ind': '2', 'sub': '1'});
      expect(events.whereType<TagWritten>().single.capacity, 144);
    });

    test('a failed write emits no TagWritten', () async {
      backend
        ..emit(const ReaderAttached('R'))
        ..emit(const TagArrived());
      await pumpEventQueue();

      backend.nextWrite = const NfcWriteResult.failure('too big');
      final r = await nfc.write({'a': '1'});
      await pumpEventQueue();

      expect(r.ok, isFalse);
      expect(events.whereType<TagWritten>(), isEmpty);
    });

    test('estimateSize counts the NDEF framing', () {
      final small = nfc.estimateSize({'ind': '2', 'sub': '1'});
      final big = nfc.estimateSize({'ind': '2', 'sub': '1', 'text': 'x' * 100});
      expect(small, greaterThan(20));
      expect(big, greaterThan(small + 100));
    });
  });

  test('diagnose comes from the backend', () async {
    final d = await nfc.diagnose();
    expect(d.platform, 'Fake');
    expect(d.report(), contains('Platform'));
  });

  test('stop returns to idle and start works again', () async {
    await nfc.stop();
    expect(nfc.state, NfcReaderState.idle);
    await nfc.start();
    expect(nfc.state, NfcReaderState.waitingForReader);
  });

  test('platforms without a backend fail soft', () async {
    final stub =
        UnimplementedBackend(platform: 'Test OS', hint: 'Coming soon.');
    final other = UniversalNfc(backend: stub);
    expect(await other.isAvailable(), isFalse);
    expect(await other.diagnose().then((d) => d.supported), isFalse);
    await expectLater(other.start(), throwsA(isA<NfcReaderException>()));
    expect(other.state, NfcReaderState.idle);
    await other.dispose();
  });
}
