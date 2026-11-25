import 'package:test/test.dart';
import 'package:universal_nfc/universal_nfc.dart';

void main() {
  test('matches reader names case-insensitively', () {
    expect(ReaderProfile.acr1552.matches('ACS ACR1552 3S CL Reader 0'), isTrue);
    expect(ReaderProfile.acr1552.matches('acs acr1552 reader'), isTrue);
    expect(
        ReaderProfile.acr1552.matches('ACS ACR122U PICC Interface 0'), isFalse);
    expect(
        ReaderProfile.acr122u.matches('ACS ACR122U PICC Interface 0'), isTrue);
  });

  test('generic matches anything', () {
    expect(ReaderProfile.generic.matches('Some Vendor NFC Reader'), isTrue);
  });

  test('standard read and write commands', () {
    expect(ReaderProfile.generic.readApdu(4), [0xFF, 0xB0, 0x00, 4, 16]);
    expect(
      ReaderProfile.generic.writeApdu(5, [1, 2, 3, 4]),
      [0xFF, 0xD6, 0x00, 5, 4, 1, 2, 3, 4],
    );
    expect(ReaderProfile.generic.uidApdu, [0xFF, 0xCA, 0x00, 0x00, 0x00]);
  });

  test('a custom profile can override commands', () {
    final p = ReaderProfile(
      id: 'custom',
      nameContains: ['MyVendor'],
      buildReadApdu: (page) => [0x30, page],
      uidApdu: null,
    );
    expect(p.readApdu(4), [0x30, 4]);
    expect(p.uidApdu, isNull);
  });

  test('default list covers the known ACS readers', () {
    expect(ReaderProfile.defaults.map((p) => p.id),
        ['acr1552', 'acr1252', 'acr122u']);
  });
}
