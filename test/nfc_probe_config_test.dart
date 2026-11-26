import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_nfc/universal_nfc.dart';

void main() {
  group('NfcProbeConfig', () {
    test('default is the original 200 ms behaviour', () {
      const c = NfcProbeConfig();
      expect(c.enabled, isTrue);
      expect(c.effectiveInterval, const Duration(milliseconds: 200));
    });

    test('milliseconds and seconds', () {
      expect(NfcProbeConfig.milliseconds(100).effectiveInterval,
          const Duration(milliseconds: 100));
      expect(NfcProbeConfig.seconds(2).effectiveInterval,
          const Duration(seconds: 2));
    });

    test('off', () {
      expect(const NfcProbeConfig.off().enabled, isFalse);
    });

    test('too fast is raised to the minimum', () {
      expect(NfcProbeConfig.milliseconds(5).effectiveInterval,
          NfcProbeConfig.minInterval);
      expect(NfcProbeConfig.milliseconds(0).effectiveInterval,
          const Duration(milliseconds: 50));
    });

    test('toString is readable', () {
      expect(NfcProbeConfig.seconds(1).toString(), contains('1000 ms'));
      expect(const NfcProbeConfig.off().toString(), contains('off'));
    });
  });

  group('ProbeStatus', () {
    test('has every status', () {
      expect(ProbeStatus.values.map((s) => s.name), [
        'unknown',
        'readerPresent',
        'noReader',
        'serviceUnavailable',
        'unsupported',
        'error',
      ]);
    });

    test('check is unsupported when not on Windows', () {
      expect(NfcReaderProbe.check(), ProbeStatus.unsupported);
      expect(NfcReaderProbe.hasReader(), isFalse);
    }, skip: Platform.isWindows ? 'needs a non-Windows machine' : false);

    test('check returns a real status on Windows', () {
      final s = NfcReaderProbe.check();
      expect(
        [
          ProbeStatus.readerPresent,
          ProbeStatus.noReader,
          ProbeStatus.serviceUnavailable
        ],
        contains(s),
      );
      expect(NfcReaderProbe.hasReader(), s == ProbeStatus.readerPresent);
    }, skip: Platform.isWindows ? false : 'needs Windows');
  });
}
