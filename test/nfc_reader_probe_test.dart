import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_nfc/universal_nfc.dart';

void main() {
  test('probe never throws and returns a bool', () {
    expect(NfcReaderProbe.hasReader(), isA<bool>());
  });

  test('probe is false when not on Windows', () {
    expect(NfcReaderProbe.hasReader(), isFalse);
  }, skip: Platform.isWindows ? 'needs a non-Windows machine' : false);
}
