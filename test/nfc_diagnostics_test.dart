import 'package:test/test.dart';
import 'package:universal_nfc/universal_nfc.dart';

void main() {
  test('healthy only with service, support and a selected reader', () {
    const ok = NfcDiagnostics(
      platform: 'Windows',
      supported: true,
      serviceReachable: true,
      readers: ['ACS ACR1552'],
      selectedReader: 'ACS ACR1552',
      selectedProfile: 'acr1552',
    );
    expect(ok.healthy, isTrue);

    const noReader = NfcDiagnostics(
      platform: 'Windows',
      supported: true,
      serviceReachable: true,
      notes: ['No reader found.'],
    );
    expect(noReader.healthy, isFalse);
    expect(noReader.report(), contains('No reader found.'));
  });
}
