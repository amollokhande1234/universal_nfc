import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../../models/nfc_probe_status.dart';

typedef _EstablishN = Int32 Function(
    Uint32, Pointer<Void>, Pointer<Void>, Pointer<IntPtr>);
typedef _EstablishD = int Function(
    int, Pointer<Void>, Pointer<Void>, Pointer<IntPtr>);

typedef _ListN = Int32 Function(
    IntPtr, Pointer<Utf16>, Pointer<Utf16>, Pointer<Uint32>);
typedef _ListD = int Function(
    int, Pointer<Utf16>, Pointer<Utf16>, Pointer<Uint32>);

typedef _ReleaseN = Int32 Function(IntPtr);
typedef _ReleaseD = int Function(int);

/// Asks Windows whether at least one smart-card/NFC reader is plugged in.
///
/// Very cheap (one short PC/SC context, no reader names read), so it can run
/// several times per second. The PC/SC backend uses it to notice a reader
/// being plugged in or unplugged almost instantly.
class NfcReaderProbe {
  const NfcReaderProbe._();

  static DynamicLibrary? _lib;
  static _EstablishD? _establish;
  static _ListD? _list;
  static _ReleaseD? _release;

  static bool _load() {
    if (!Platform.isWindows) return false;
    if (_establish != null) return true;
    try {
      _lib = DynamicLibrary.open('winscard.dll');
      _establish = _lib!.lookupFunction<_EstablishN, _EstablishD>(
        'SCardEstablishContext',
      );
      _list = _lib!.lookupFunction<_ListN, _ListD>('SCardListReadersW');
      _release = _lib!.lookupFunction<_ReleaseN, _ReleaseD>(
        'SCardReleaseContext',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Full answer: reader present, no reader, service down, unsupported, error.
  static ProbeStatus check() {
    if (!_load()) return ProbeStatus.unsupported;

    final ctx = calloc<IntPtr>();
    final len = calloc<Uint32>();
    var opened = false;
    try {
      // 0 = SCARD_SCOPE_USER. Failing here means the service is not running.
      if (_establish!(0, nullptr, nullptr, ctx) != 0) {
        return ProbeStatus.serviceUnavailable;
      }
      opened = true;

      // Ask only for the size of the reader list. A value above 2 means at
      // least one reader name is present. Error 0x8010002E = no readers.
      final rc = _list!(ctx.value, nullptr, nullptr, len);
      return (rc == 0 && len.value > 2)
          ? ProbeStatus.readerPresent
          : ProbeStatus.noReader;
    } catch (_) {
      return ProbeStatus.error;
    } finally {
      if (opened) _release!(ctx.value);
      calloc.free(ctx);
      calloc.free(len);
    }
  }

  /// true = a reader is plugged in right now.
  static bool hasReader() => check() == ProbeStatus.readerPresent;
}
