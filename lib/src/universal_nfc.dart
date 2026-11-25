import 'dart:async';

import 'backends/nfc_backend.dart';
import 'backends/pcsc/reader_profile.dart';
import 'backends/platform_backend.dart';
import 'codec/ndef_json_codec.dart';
import 'codec/nfc_tag_codec.dart';
import 'codec/type2_tag.dart';
import 'models/nfc_data.dart';
import 'models/nfc_diagnostics.dart';
import 'models/nfc_event.dart';
import 'models/nfc_model_registry.dart';
import 'models/nfc_tag_model.dart';
import 'models/nfc_write_result.dart';
import 'nfc_logger.dart';

/// The one class an app talks to.
///
/// Three independent layers sit behind it, each replaceable:
///
/// ```
///  backend  (reader hardware)   PC/SC on Windows, Android, iOS, or your own
///  codec    (card layout)       NDEF-text JSON by default
///  models   (what data means)   your NfcTagModel classes
/// ```
///
/// ```dart
/// final nfc = UniversalNfc(models: [industryModel]);
/// nfc.events.listen((e) { switch (e) { case TagRead(): ... } });
/// await nfc.start();   // fine even if no reader is plugged in yet
/// ```
class UniversalNfc {
  UniversalNfc({
    NfcBackend? backend,
    Iterable<NfcTagModel<Object?>> models = const [],
    String? modelKey = 'm',
    NfcTagCodec codec = const NdefJsonCodec(),
    List<ReaderProfile> readerProfiles = ReaderProfile.defaults,
    bool allowAnyReader = true,
    NfcLogger? logger,
  })  : models = NfcModelRegistry(modelKey: modelKey),
        _codec = codec,
        _logger = logger {
    for (final m in models) {
      this.models.register(m);
    }
    _backend = backend ??
        createPlatformBackend(
          codec: codec,
          readerProfiles: readerProfiles,
          allowAnyReader: allowAnyReader,
          logger: logger,
        );
  }

  /// Tag models. Add or remove at any time: `nfc.models.register(...)`.
  final NfcModelRegistry models;

  final NfcTagCodec _codec;
  final NfcLogger? _logger;
  late final NfcBackend _backend;
  final _controller = StreamController<NfcEvent>.broadcast();
  StreamSubscription<BackendEvent>? _sub;

  NfcReaderState _state = NfcReaderState.idle;
  String? _readerName;

  /// Everything that happens: reader connected/disconnected, tag detected/read/
  /// removed/written, state changes, failures. Broadcast stream.
  Stream<NfcEvent> get events => _controller.stream;

  /// Only the state changes, handy for a status indicator.
  Stream<NfcReaderState> get states => events
      .where((e) => e is NfcStateChanged)
      .map((e) => (e as NfcStateChanged).state);

  NfcReaderState get state => _state;

  /// Name of the connected reader, null when none.
  String? get readerName => _readerName;

  bool get isReaderConnected => _readerName != null;
  bool get isTagPresent => _state == NfcReaderState.tagPresent;

  /// Can NFC work on this machine at all? (Windows: PC/SC service reachable.
  /// Other platforms: false until their backend exists.) A missing reader is
  /// NOT a reason for false: [start] waits for one to be plugged in.
  Future<bool> isAvailable() => _backend.isAvailable();

  /// A plain-language health report: platform, NFC service, readers found, the
  /// reader profile chosen, and what to do when something is wrong.
  Future<NfcDiagnostics> diagnose() => _backend.diagnose();

  /// Starts listening. Does not fail when no reader is plugged in; the state
  /// becomes [NfcReaderState.waitingForReader] and it connects as soon as one
  /// appears. Throws `NfcReaderException` on platforms without a backend.
  Future<void> start() async {
    if (_state == NfcReaderState.disposed) {
      throw StateError('UniversalNfc is disposed.');
    }
    if (_sub != null) return; // already started

    _setState(NfcReaderState.waitingForReader);
    _sub = _backend.events.listen(
      _onBackend,
      onError: (Object e, StackTrace st) => _emit(NfcFailure(e, st)),
    );
    try {
      await _backend.start();
    } catch (_) {
      await _sub?.cancel();
      _sub = null;
      _setState(NfcReaderState.idle);
      rethrow;
    }
  }

  /// Stops listening; [start] can be called again.
  Future<void> stop() async {
    if (_sub == null) return;
    await _sub?.cancel();
    _sub = null;
    await _backend.stop();
    _readerName = null;
    if (_state != NfcReaderState.disposed) _setState(NfcReaderState.idle);
  }

  /// Releases everything. Cannot be used afterwards.
  Future<void> dispose() async {
    if (_state == NfcReaderState.disposed) return;
    await stop();
    await _backend.dispose();
    _setState(NfcReaderState.disposed);
    await _controller.close();
  }

  // ------------------------------------------------------------------ writing

  /// Approximate bytes [data] needs on an NFC Forum Type 2 tag (NTAG / Ultralight),
  /// including NDEF framing. Compare with the tag's capacity: NTAG213 = 144,
  /// NTAG215 = 496, NTAG216 = 872. Throws if [data] cannot be encoded.
  int estimateSize(NfcData data) =>
      Type2Layout.wrapTlv(_codec.encode(data)).length;

  /// Writes [data] to the tag that is on the reader now. Pass [modelId] to
  /// store the model name on the tag so it is selected explicitly later.
  ///
  /// Never throws for expected problems; check [NfcWriteResult.ok]. Nothing is
  /// written if the data does not fit, and the result is read back and verified.
  Future<NfcWriteResult> write(NfcData data, {String? modelId}) async {
    if (_state != NfcReaderState.tagPresent) {
      return const NfcWriteResult.failure('Place a tag on the reader first.');
    }
    final key = models.modelKey;
    final payload = (modelId != null && key != null)
        ? <String, Object?>{key: modelId, ...data}
        : data;
    try {
      final result = await _backend.write(payload);
      if (result.ok) {
        _emit(TagWritten(
          data: payload,
          bytesUsed: result.bytesUsed,
          capacity: result.capacity,
        ));
      }
      return result;
    } catch (e) {
      return NfcWriteResult.failure('Write failed: $e');
    }
  }

  // ------------------------------------------------------------------ internals

  void _log(String m) => _logger?.call('[NFC] $m');

  void _emit(NfcEvent e) {
    if (!_controller.isClosed) _controller.add(e);
  }

  void _setState(NfcReaderState s) {
    if (_state == s) return;
    _state = s;
    _emit(NfcStateChanged(s));
  }

  NfcReaderState get _idleState => _readerName == null
      ? NfcReaderState.waitingForReader
      : NfcReaderState.listening;

  void _onBackend(BackendEvent e) {
    switch (e) {
      case ReaderAttached(:final readerName, :final profileId):
        _readerName = readerName;
        _emit(ReaderConnected(readerName, profileId: profileId));
        _setState(NfcReaderState.listening);
      case ReaderDetached(:final readerName):
        _readerName = null;
        _emit(ReaderDisconnected(readerName));
        _setState(NfcReaderState.waitingForReader);
      case TagArrived():
        _emit(const TagDetected());
        _setState(NfcReaderState.tagPresent);
      case TagFields(
          :final fields,
          :final rawText,
          :final uid,
          :final rawBytes
        ):
        _resolve(fields, rawText, uid, rawBytes);
      case TagReadFailed(
          :final error,
          :final rawText,
          :final uid,
          :final rawBytes
        ):
        _emit(TagUnreadable(
          error,
          rawText: rawText,
          uid: uid,
          rawBytes: rawBytes,
        ));
      case TagLeft():
        _emit(const TagRemoved());
        _setState(_idleState);
      case BackendFailure(:final error, :final stackTrace):
        _emit(NfcFailure(error, stackTrace));
    }
  }

  /// data -> model -> typed value. Any problem becomes an event, never a crash.
  void _resolve(
    NfcData fields,
    String? rawText,
    String? uid,
    List<int>? rawBytes,
  ) {
    final model = models.resolve(fields);
    if (model == null) {
      _log('No model for $fields');
      _emit(UnknownTag(fields, rawText: rawText, uid: uid, rawBytes: rawBytes));
      return;
    }

    final missing =
        model.requiredKeys.where((k) => !fields.containsKey(k)).toList();
    if (missing.isNotEmpty) {
      _emit(TagUnreadable(
        'Model "${model.id}" needs missing keys: ${missing.join(', ')}',
        rawText: rawText,
        fields: fields,
        uid: uid,
        rawBytes: rawBytes,
      ));
      return;
    }

    try {
      final value = model.parse(fields);
      _emit(TagRead(
        model: model,
        value: value,
        fields: fields,
        rawText: rawText,
        uid: uid,
        rawBytes: rawBytes,
      ));
    } catch (e) {
      _emit(TagUnreadable(
        'Model "${model.id}" could not parse the tag: $e',
        rawText: rawText,
        fields: fields,
        uid: uid,
        rawBytes: rawBytes,
      ));
    }
  }
}
