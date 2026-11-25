import 'dart:async';

import '../models/nfc_data.dart';
import '../models/nfc_diagnostics.dart';
import '../models/nfc_reader_exception.dart';
import '../models/nfc_write_result.dart';
import 'nfc_backend.dart';

/// Stands in for platforms that do not have a backend yet (Android, iOS, macOS,
/// Linux). The app keeps running: [isAvailable] is false and [diagnose]
/// explains the situation. Replace it with a real [NfcBackend] to add support.
class UnimplementedBackend implements NfcBackend {
  UnimplementedBackend({required this.platform, required this.hint});

  final String platform;
  final String hint;
  final _controller = StreamController<BackendEvent>.broadcast();

  @override
  Stream<BackendEvent> get events => _controller.stream;

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<void> start() async {
    throw NfcReaderException('NFC is not supported on $platform yet. $hint');
  }

  @override
  Future<void> stop() async {}

  @override
  Future<NfcWriteResult> write(NfcData data) async =>
      NfcWriteResult.failure('NFC is not supported on $platform yet.');

  @override
  Future<NfcDiagnostics> diagnose() async => NfcDiagnostics(
        platform: platform,
        supported: false,
        notes: ['NFC is not supported on $platform yet.', hint],
      );

  @override
  Future<void> dispose() => _controller.close();
}
