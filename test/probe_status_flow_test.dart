import 'dart:async';

import 'package:test/test.dart';
import 'package:universal_nfc/universal_nfc.dart';

/// A backend whose probe can be changed, like the Windows one.
class ConfigurableBackend implements NfcBackend, ProbeConfigurable {
  final _c = StreamController<BackendEvent>.broadcast();
  NfcProbeConfig? lastConfig;

  void emit(BackendEvent e) => _c.add(e);

  @override
  void updateProbe(NfcProbeConfig config) => lastConfig = config;
  @override
  Stream<BackendEvent> get events => _c.stream;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<NfcWriteResult> write(NfcData data) async =>
      const NfcWriteResult.failure('n/a');
  @override
  Future<NfcDiagnostics> diagnose() async => const NfcDiagnostics(
        platform: 'Fake',
        supported: true,
        probeStatus: ProbeStatus.readerPresent,
      );
  @override
  Future<void> dispose() => _c.close();
}

class NoProbeBackend implements NfcBackend {
  @override
  Stream<BackendEvent> get events => const Stream.empty();
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<NfcWriteResult> write(NfcData data) async =>
      const NfcWriteResult.failure('n/a');
  @override
  Future<NfcDiagnostics> diagnose() async =>
      const NfcDiagnostics(platform: 'Fake', supported: true);
  @override
  Future<void> dispose() async {}
}

void main() {
  test('probe status flows to the app as events and as state', () async {
    final backend = ConfigurableBackend();
    final nfc = UniversalNfc(backend: backend);
    final events = <NfcEvent>[];
    final statuses = <ProbeStatus>[];
    nfc.events.listen(events.add);
    nfc.probeStatuses.listen(statuses.add);
    await nfc.start();

    expect(nfc.probeStatus, ProbeStatus.unknown);

    backend
      ..emit(const ProbeUpdated(ProbeStatus.noReader))
      ..emit(const ProbeUpdated(ProbeStatus.readerPresent))
      ..emit(const ProbeUpdated(ProbeStatus.serviceUnavailable));
    await pumpEventQueue();

    expect(statuses, [
      ProbeStatus.noReader,
      ProbeStatus.readerPresent,
      ProbeStatus.serviceUnavailable,
    ]);
    expect(nfc.probeStatus, ProbeStatus.serviceUnavailable);
    expect(events.whereType<ReaderProbeChanged>(), hasLength(3));
    await nfc.dispose();
  });

  test('setProbe reaches a configurable backend', () async {
    final backend = ConfigurableBackend();
    final nfc = UniversalNfc(backend: backend);

    expect(nfc.setProbe(NfcProbeConfig.seconds(2)), isTrue);
    expect(backend.lastConfig!.effectiveInterval, const Duration(seconds: 2));

    expect(nfc.setProbe(const NfcProbeConfig.off()), isTrue);
    expect(backend.lastConfig!.enabled, isFalse);

    expect(nfc.setProbe(NfcProbeConfig.milliseconds(100)), isTrue);
    expect(backend.lastConfig!.effectiveInterval,
        const Duration(milliseconds: 100));
    await nfc.dispose();
  });

  test('setProbe returns false when the backend has no probe', () async {
    final nfc = UniversalNfc(backend: NoProbeBackend());
    expect(nfc.setProbe(NfcProbeConfig.seconds(1)), isFalse);
    await nfc.dispose();
  });

  test('diagnose report includes the probe status', () async {
    final nfc = UniversalNfc(backend: ConfigurableBackend());
    final report = (await nfc.diagnose()).report();
    expect(report, contains('Probe status'));
    expect(report, contains('readerPresent'));
    await nfc.dispose();
  });
}
