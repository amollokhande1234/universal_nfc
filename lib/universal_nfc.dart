/// One API to read and write NFC tags. Windows PC/SC readers today; Android,
/// iOS, macOS and Linux plug into the same API.
library;

export 'src/backends/nfc_backend.dart';
export 'src/backends/pcsc/nfc_reader_probe.dart';
export 'src/backends/pcsc/pcsc_backend.dart' show PcscBackend;
export 'src/backends/pcsc/reader_profile.dart';
export 'src/backends/unimplemented_backend.dart';
export 'src/codec/hex.dart';
export 'src/codec/ndef_json_codec.dart';
export 'src/codec/ndef_text_parser.dart';
export 'src/codec/nfc_tag_codec.dart';
export 'src/codec/type2_tag.dart';
export 'src/models/nfc_data.dart';
export 'src/models/nfc_diagnostics.dart';
export 'src/models/nfc_event.dart';
export 'src/models/nfc_model_registry.dart';
export 'src/models/nfc_probe_config.dart';
export 'src/models/nfc_probe_status.dart';
export 'src/models/nfc_reader_exception.dart';
export 'src/models/nfc_tag_model.dart';
export 'src/models/nfc_write_result.dart';
export 'src/nfc_logger.dart';
export 'src/universal_nfc.dart' show UniversalNfc;
