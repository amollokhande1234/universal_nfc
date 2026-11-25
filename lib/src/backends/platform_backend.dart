import 'dart:io' show Platform;

import '../codec/nfc_tag_codec.dart';
import '../nfc_logger.dart';
import 'nfc_backend.dart';
import 'pcsc/pcsc_backend.dart';
import 'pcsc/reader_profile.dart';
import 'unimplemented_backend.dart';

/// Picks the backend for the current platform. Never throws: platforms
/// without a backend get an [UnimplementedBackend] so the app keeps running.
NfcBackend createPlatformBackend({
  required NfcTagCodec codec,
  required List<ReaderProfile> readerProfiles,
  required bool allowAnyReader,
  NfcLogger? logger,
}) {
  if (Platform.isWindows) {
    return PcscBackend(
      codec: codec,
      profiles: readerProfiles,
      allowAnyReader: allowAnyReader,
      logger: logger,
    );
  }
  if (Platform.isAndroid) {
    return UnimplementedBackend(
      platform: 'Android',
      hint: 'Planned: the phone NFC chip through an Android backend.',
    );
  }
  if (Platform.isIOS) {
    return UnimplementedBackend(
      platform: 'iOS',
      hint: 'Planned: Core NFC through an iOS backend.',
    );
  }
  if (Platform.isMacOS) {
    return UnimplementedBackend(
      platform: 'macOS',
      hint: 'Planned: macOS has PC/SC built in; a PC/SC backend for macOS is next.',
    );
  }
  if (Platform.isLinux) {
    return UnimplementedBackend(
      platform: 'Linux',
      hint: 'Planned: needs the pcscd service and libpcsclite; a PC/SC backend for Linux is next.',
    );
  }
  return UnimplementedBackend(
    platform: Platform.operatingSystem,
    hint: 'No backend for this platform.',
  );
}
