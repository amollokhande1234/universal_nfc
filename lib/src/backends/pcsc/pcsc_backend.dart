import 'dart:async';
import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../../codec/hex.dart';
import '../../codec/nfc_tag_codec.dart';
import '../../codec/type2_tag.dart';
import '../../models/nfc_data.dart';
import '../../models/nfc_diagnostics.dart';
import '../../models/nfc_reader_exception.dart';
import '../../models/nfc_write_result.dart';
import '../../nfc_logger.dart';
import '../nfc_backend.dart';
import 'reader_profile.dart';

/// Windows backend: any PC/SC reader (ACR1552, ACR1252, ACR122U, ...) through
/// winscard.dll.
///
/// * Plugging a reader in / out while running is detected (hot-plug).
/// * The reader model decides which [ReaderProfile] is used.
/// * Reads and writes NFC Forum Type 2 tags (NTAG21x, MIFARE Ultralight).
class PcscBackend implements NfcBackend {
  PcscBackend({
    required this.codec,
    this.profiles = ReaderProfile.defaults,
    this.allowAnyReader = true,
    this.pollInterval = const Duration(milliseconds: 250),
    this.readerScanInterval = const Duration(seconds: 1),
    this.removalDebounce = const Duration(milliseconds: 400),
    this.logger,
  }) {
    if (!Platform.isWindows) {
      throw UnsupportedError('PcscBackend only works on Windows.');
    }
  }

  final NfcTagCodec codec;

  /// Tried in order against each connected reader's name.
  final List<ReaderProfile> profiles;

  /// If no profile matches, still use the first reader found with
  /// [ReaderProfile.generic].
  final bool allowAnyReader;

  /// How often the tag state is polled.
  final Duration pollInterval;

  /// How often the list of connected readers is re-checked (hot-plug).
  final Duration readerScanInterval;

  /// A tag must be gone this long before [TagLeft] is emitted.
  final Duration removalDebounce;

  final NfcLogger? logger;

  final _controller = StreamController<BackendEvent>.broadcast();
  int _context = 0;
  String? _readerName;
  ReaderProfile? _profile;
  bool _wasPresent = false;
  bool _polling = false;
  bool _disposed = false;
  int _ticks = 0;
  int _listFailures = 0;
  int? _lastContextError;
  Timer? _timer;
  Timer? _removalTimer;

  @override
  Stream<BackendEvent> get events => _controller.stream;

  void _log(String m) => logger?.call('[NFC] $m');

  void _emit(BackendEvent e) {
    if (!_controller.isClosed) _controller.add(e);
  }

  int get _scanEvery => math.max(
        1,
        (readerScanInterval.inMilliseconds / pollInterval.inMilliseconds).ceil(),
      );

  // ---------------------------------------------------------------- public

  /// Names of all PC/SC readers Windows currently reports (diagnostics).
  static List<String> listReaders() {
    final ctxPtr = calloc<IntPtr>();
    try {
      final rc = SCardEstablishContext(
        SCARD_SCOPE_USER,
        nullptr,
        nullptr,
        ctxPtr,
      );
      if (rc != SCARD_S_SUCCESS) return const [];
      final ctx = ctxPtr.value;
      try {
        return _listReaders(ctx).names;
      } finally {
        SCardReleaseContext(ctx);
      }
    } finally {
      calloc.free(ctxPtr);
    }
  }

  @override
  Future<bool> isAvailable() async {
    final ctxPtr = calloc<IntPtr>();
    try {
      final rc = SCardEstablishContext(
        SCARD_SCOPE_USER,
        nullptr,
        nullptr,
        ctxPtr,
      );
      if (rc == SCARD_S_SUCCESS) SCardReleaseContext(ctxPtr.value);
      return rc == SCARD_S_SUCCESS;
    } catch (_) {
      return false;
    } finally {
      calloc.free(ctxPtr);
    }
  }

  @override
  Future<NfcDiagnostics> diagnose() async {
    final notes = <String>[];
    var reachable = false;
    var readers = <String>[];
    final ctxPtr = calloc<IntPtr>();
    try {
      final rc = SCardEstablishContext(
        SCARD_SCOPE_USER,
        nullptr,
        nullptr,
        ctxPtr,
      );
      if (rc == SCARD_S_SUCCESS) {
        reachable = true;
        final ctx = ctxPtr.value;
        try {
          readers = _listReaders(ctx).names;
        } finally {
          SCardReleaseContext(ctx);
        }
      }
    } catch (e) {
      notes.add('A PC/SC call failed: $e');
    } finally {
      calloc.free(ctxPtr);
    }

    final match = _match(readers);
    if (!reachable) {
      notes.add(
        'The Windows "Smart Card" service is not reachable. Open services.msc, '
        'start "Smart Card" and set it to Automatic.',
      );
    } else if (readers.isEmpty) {
      notes.add(
        'No reader found. Check the USB cable, try another USB port, and look '
        'for the reader under "Smart card readers" in Device Manager. If it has '
        'a warning icon, install the driver from the reader vendor.',
      );
    } else if (match == null) {
      notes.add(
        'Readers exist but none matches the configured profiles. Enable '
        'allowAnyReader or add a ReaderProfile whose nameContains matches one of them.',
      );
    } else if (match.profile.id == ReaderProfile.generic.id) {
      notes.add(
        'This reader is not in the built-in profiles, so the generic PC/SC '
        'profile is used. That works for most readers; if reading fails, add a '
        'ReaderProfile for it.',
      );
    }

    return NfcDiagnostics(
      platform: 'Windows',
      supported: true,
      serviceReachable: reachable,
      readers: readers,
      selectedReader: match?.name,
      selectedProfile: match?.profile.id,
      notes: notes,
    );
  }

  @override
  Future<void> start() async {
    if (_disposed) throw StateError('PcscBackend is disposed.');
    if (_timer != null) return;
    _scan(); // find an already-plugged reader right away
    _timer = Timer.periodic(pollInterval, (_) => _tick());
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _removalTimer?.cancel();
    _removalTimer = null;
    _readerName = null;
    _profile = null;
    _wasPresent = false;
    _releaseContext();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    await _controller.close();
  }

  // ---------------------------------------------------------------- reader watching

  void _tick() {
    if (_disposed) return;
    _ticks++;
    final scanNow = _ticks % _scanEvery == 0;
    if (_readerName != null) _poll();
    if (scanNow) _scan();
  }

  bool _openContext() {
    final ptr = calloc<IntPtr>();
    try {
      final rc = SCardEstablishContext(
        SCARD_SCOPE_USER,
        nullptr,
        nullptr,
        ptr,
      );
      if (rc != SCARD_S_SUCCESS) {
        if (_lastContextError != rc) {
          _lastContextError = rc; // report once, not every second
          _emit(BackendFailure(
            NfcReaderException('SCardEstablishContext failed', code: rc),
          ));
        }
        return false;
      }
      _lastContextError = null;
      _context = ptr.value;
      return true;
    } finally {
      calloc.free(ptr);
    }
  }

  void _releaseContext() {
    if (_context != 0) {
      SCardReleaseContext(_context);
      _context = 0;
    }
  }

  /// Compares the readers Windows reports with the one we use; attaches /
  /// detaches accordingly.
  void _scan() {
    if (_disposed) return;
    if (_context == 0 && !_openContext()) return;

    final listed = _listReaders(_context);
    if (listed.rc != SCARD_S_SUCCESS) {
      // "No readers" or a PC/SC hiccup. After a few misses start from scratch.
      if (++_listFailures >= 3) {
        _listFailures = 0;
        _detach();
        _releaseContext();
        return;
      }
    } else {
      _listFailures = 0;
    }
    final names = listed.names;

    final current = _readerName;
    if (current != null && !names.contains(current)) _detach();

    if (_readerName == null) {
      final match = _match(names);
      if (match != null) _attach(match.name, match.profile);
    }
  }

  ({String name, ReaderProfile profile})? _match(List<String> names) {
    for (final p in profiles) {
      for (final n in names) {
        if (p.matches(n)) return (name: n, profile: p);
      }
    }
    if (allowAnyReader && names.isNotEmpty) {
      return (name: names.first, profile: ReaderProfile.generic);
    }
    return null;
  }

  void _attach(String name, ReaderProfile profile) {
    _readerName = name;
    _profile = profile;
    _wasPresent = false;
    _log('Reader connected: $name (profile ${profile.id})');
    _emit(ReaderAttached(name, profileId: profile.id));
    _poll(); // a tag may already be on the reader
  }

  void _detach() {
    final name = _readerName;
    if (name == null) return;
    _removalTimer?.cancel();
    _removalTimer = null;
    if (_wasPresent) {
      _wasPresent = false;
      _emit(const TagLeft());
    }
    _readerName = null;
    _profile = null;
    _log('Reader disconnected: $name');
    _emit(ReaderDetached(name));
  }

  // ---------------------------------------------------------------- tag watching

  void _poll() {
    final name = _readerName;
    if (name == null || _disposed || _polling) return;
    _polling = true;
    var rescan = false;

    final statePtr = calloc<SCARD_READERSTATE>();
    final namePtr = name.toNativeUtf16();
    try {
      statePtr.ref.szReader = namePtr.cast();
      statePtr.ref.dwCurrentState = SCARD_STATE_UNAWARE;

      final rc = SCardGetStatusChange(_context, 200, statePtr, 1);
      if (rc == SCARD_S_SUCCESS) {
        final present = (statePtr.ref.dwEventState & SCARD_STATE_PRESENT) != 0;
        _handlePresence(present);
      } else {
        rescan = true; // reader probably unplugged: check right away
      }
    } catch (e, st) {
      _emit(BackendFailure(e, st));
    } finally {
      calloc.free(namePtr);
      calloc.free(statePtr);
      _polling = false;
    }
    if (rescan) _scan();
  }

  void _handlePresence(bool isPresent) {
    if (isPresent) {
      _removalTimer?.cancel();
      _removalTimer = null;
      if (!_wasPresent) {
        _wasPresent = true;
        _emit(const TagArrived());
        _readTag();
      }
    } else if (_wasPresent && _removalTimer == null) {
      _removalTimer = Timer(removalDebounce, () {
        _removalTimer = null;
        _wasPresent = false;
        _emit(const TagLeft());
      });
    }
  }

  // ---------------------------------------------------------------- reading

  static bool _isOk(List<int>? resp) =>
      resp != null &&
      resp.length >= 2 &&
      resp[resp.length - 2] == 0x90 &&
      resp[resp.length - 1] == 0x00;

  /// One read command; returns the data without the status bytes, or null.
  List<int>? _readChunk(_CardConnection conn, ReaderProfile p, int page) {
    final resp = conn.transmit(p.readApdu(page));
    if (!_isOk(resp)) return null;
    return resp!.sublist(0, resp.length - 2);
  }

  String? _readUid(_CardConnection conn, ReaderProfile profile) {
    final apdu = profile.uidApdu;
    if (apdu == null) return null;
    final resp = conn.transmit(apdu);
    if (!_isOk(resp) || resp!.length <= 2) return null;
    return NfcHex.encode(resp.sublist(0, resp.length - 2), separator: '')
        .toUpperCase();
  }

  void _readTag() {
    final profile = _profile!;
    final conn = _CardConnection.open(_context, _readerName!);
    if (conn == null) {
      _emit(const TagReadFailed('Could not connect to the tag.'));
      return;
    }

    final bytes = <int>[];
    String? uid;
    try {
      uid = _readUid(conn, profile);

      // The tag describes its own size in page 3; use it to bound the read.
      final cc = _readChunk(conn, profile, 3);
      final cap = cc == null ? null : Type2Capability.parse(cc);
      final lastPage = cap == null
          ? profile.maxPage
          : math.min(
              profile.maxPage,
              profile.firstPage + cap.dataAreaBytes ~/ 4 - 1,
            );

      for (var page = profile.firstPage;
          page <= lastPage;
          page += profile.pagesPerRead) {
        final chunk = _readChunk(conn, profile, page);
        if (chunk == null) {
          _log('Failed to read page $page');
          break; // end of tag memory or read error
        }
        bytes.addAll(chunk);

        final need = codec.requiredLength(bytes);
        if (need != null && bytes.length >= need) break; // got everything
      }
    } finally {
      conn.close();
    }

    _log('UID ${uid ?? '-'}; read ${bytes.length} bytes: ${NfcHex.encode(bytes)}');

    final raw = List<int>.unmodifiable(bytes);
    final result = codec.decode(bytes);
    final fields = result.fields;
    if (fields != null) {
      _emit(TagFields(fields, rawText: result.rawText, uid: uid, rawBytes: raw));
    } else {
      _emit(TagReadFailed(
        result.error ?? 'Unreadable tag.',
        rawText: result.rawText,
        uid: uid,
        rawBytes: raw,
      ));
    }
  }

  // ---------------------------------------------------------------- writing

  @override
  Future<NfcWriteResult> write(NfcData data) async => _writeNow(data);

  /// Synchronous on purpose: no timer callback can run in the middle of a write.
  ///
  /// Safety rules:
  /// * only NDEF-formatted Type 2 tags (capability container present);
  /// * never touches pages before the first user page, nor beyond the data area;
  /// * keeps control TLVs (e.g. Lock Control) that sit before the NDEF message;
  /// * writes the first page (with the message header) LAST;
  /// * reads everything back and compares;
  /// * never sets any lock bit.
  NfcWriteResult _writeNow(NfcData data) {
    final profile = _profile;
    final name = _readerName;
    if (profile == null || name == null || !_wasPresent) {
      return const NfcWriteResult.failure('No tag on the reader. Place a tag first.');
    }

    final List<int> message;
    try {
      message = codec.encode(data);
    } catch (e) {
      return NfcWriteResult.failure('Could not encode the data: $e');
    }

    final conn = _CardConnection.open(_context, name);
    if (conn == null) {
      return const NfcWriteResult.failure('Could not connect to the tag.');
    }

    try {
      final cc = _readChunk(conn, profile, 3);
      final cap = cc == null ? null : Type2Capability.parse(cc);
      if (cap == null) {
        return const NfcWriteResult.failure(
          'This tag is not NDEF formatted (no capability container). '
          'Nothing was written.',
        );
      }
      if (!cap.writable) {
        return NfcWriteResult.failure(
          'This tag is marked read-only. Nothing was written.',
          capacity: cap.dataAreaBytes,
        );
      }

      final endPage = profile.firstPage + cap.dataAreaBytes ~/ 4; // exclusive

      // Read just far enough to find where the NDEF message starts.
      final memory = <int>[];
      for (var page = profile.firstPage;
          page < endPage;
          page += profile.pagesPerRead) {
        final chunk = _readChunk(conn, profile, page);
        if (chunk == null) {
          return NfcWriteResult.failure(
            'Could not read the tag memory. Nothing was written.',
            capacity: cap.dataAreaBytes,
          );
        }
        memory.addAll(chunk);
        if (Type2Layout.findNdefStart(memory) != null) break;
      }
      if (memory.length > cap.dataAreaBytes) {
        memory.removeRange(cap.dataAreaBytes, memory.length);
      }

      final Type2WritePlan plan;
      try {
        plan = Type2Layout.plan(
          memory: memory,
          message: message,
          dataAreaBytes: cap.dataAreaBytes,
        );
      } on Type2WriteException catch (e) {
        return NfcWriteResult.failure(
          '${e.message} Nothing was written.',
          capacity: cap.dataAreaBytes,
        );
      }

      final pages = plan.pages;
      final order = [for (var i = 1; i < pages.length; i++) i, 0];
      for (final i in order) {
        final page = profile.firstPage + plan.startPage + i;
        if (page < profile.firstPage || page >= endPage) {
          return NfcWriteResult.failure(
            'Refusing to write outside the tag data area.',
            capacity: cap.dataAreaBytes,
          );
        }
        final resp = conn.transmit(profile.writeApdu(page, pages[i]));
        if (!_isOk(resp)) {
          return NfcWriteResult.failure(
            'The tag refused the write at page $page (locked or protected?). '
            'The tag may now hold incomplete data; write it again.',
            capacity: cap.dataAreaBytes,
          );
        }
      }

      // Read back and compare.
      final got = <int>[];
      var page = profile.firstPage + plan.startPage;
      while (got.length < plan.bytes.length) {
        final chunk = _readChunk(conn, profile, page);
        if (chunk == null) {
          return NfcWriteResult.failure(
            'Written, but the read-back check could not read the tag.',
            capacity: cap.dataAreaBytes,
          );
        }
        got.addAll(chunk);
        page += profile.pagesPerRead;
      }
      for (var i = 0; i < plan.bytes.length; i++) {
        if (got[i] != plan.bytes[i]) {
          return NfcWriteResult.failure(
            'Read-back check failed: the tag does not hold what was written.',
            capacity: cap.dataAreaBytes,
          );
        }
      }

      return NfcWriteResult.success(
        bytesUsed: plan.usedBytes,
        capacity: cap.dataAreaBytes,
      );
    } finally {
      conn.close();
    }
  }

  // ---------------------------------------------------------------- native helpers

  static ({int rc, List<String> names}) _listReaders(int context) {
    final sizePtr = calloc<Uint32>();
    try {
      var rc = SCardListReaders(context, nullptr, nullptr, sizePtr);
      if (rc != SCARD_S_SUCCESS || sizePtr.value == 0) {
        return (rc: rc, names: const <String>[]);
      }
      final buffer = calloc<Uint16>(sizePtr.value);
      try {
        rc = SCardListReaders(context, nullptr, buffer.cast(), sizePtr);
        if (rc != SCARD_S_SUCCESS) return (rc: rc, names: const <String>[]);
        // Multi-string "name1\0name2\0\0": pass the length or toDartString()
        // stops at the first \0 and only the first reader is seen.
        final raw = buffer.cast<Utf16>().toDartString(length: sizePtr.value);
        return (
          rc: rc,
          names: raw.split('\x00').where((s) => s.isNotEmpty).toList(),
        );
      } finally {
        calloc.free(buffer);
      }
    } finally {
      calloc.free(sizePtr);
    }
  }
}

/// One open connection to a tag; many APDUs over one SCardConnect.
class _CardConnection {
  _CardConnection._(this._handle, this._protocol);

  final int _handle;
  final int _protocol;

  static _CardConnection? open(int context, String readerName) {
    final handlePtr = calloc<IntPtr>();
    final protocolPtr = calloc<Uint32>();
    final namePtr = readerName.toNativeUtf16();
    try {
      final rc = SCardConnect(
        context,
        namePtr.cast(),
        SCARD_SHARE_SHARED,
        SCARD_PROTOCOL_T0 | SCARD_PROTOCOL_T1,
        handlePtr,
        protocolPtr,
      );
      if (rc != SCARD_S_SUCCESS) return null;
      return _CardConnection._(handlePtr.value, protocolPtr.value);
    } finally {
      calloc.free(namePtr);
      calloc.free(handlePtr);
      calloc.free(protocolPtr);
    }
  }

  /// Sends one APDU; returns the response including SW1 SW2, or null on failure.
  List<int>? transmit(List<int> apdu) {
    final sendBuf = calloc<Uint8>(apdu.length);
    final recvBuf = calloc<Uint8>(256);
    final recvLenPtr = calloc<Uint32>()..value = 256;
    final ioRequest = calloc<SCARD_IO_REQUEST>();
    try {
      for (var i = 0; i < apdu.length; i++) {
        sendBuf[i] = apdu[i];
      }
      ioRequest.ref.dwProtocol = _protocol;
      ioRequest.ref.cbPciLength = sizeOf<SCARD_IO_REQUEST>();

      final rc = SCardTransmit(
        _handle,
        ioRequest,
        sendBuf,
        apdu.length,
        nullptr,
        recvBuf,
        recvLenPtr,
      );
      if (rc != SCARD_S_SUCCESS || recvLenPtr.value < 2) return null;
      return List<int>.generate(recvLenPtr.value, (i) => recvBuf[i]);
    } finally {
      calloc.free(sendBuf);
      calloc.free(recvBuf);
      calloc.free(recvLenPtr);
      calloc.free(ioRequest);
    }
  }

  void close() => SCardDisconnect(_handle, SCARD_LEAVE_CARD);
}
