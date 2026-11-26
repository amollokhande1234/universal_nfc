import '../models/nfc_data.dart';
import '../models/nfc_diagnostics.dart';
import '../models/nfc_probe_status.dart';
import '../models/nfc_write_result.dart';

/// Low-level events a backend reports. [UniversalNfc] turns them into the
/// public `NfcEvent`s (and resolves tag models), so a backend only deals with
/// hardware.
sealed class BackendEvent {
  const BackendEvent();
}

final class ReaderAttached extends BackendEvent {
  const ReaderAttached(this.readerName, {this.profileId});
  final String readerName;
  final String? profileId;
}

final class ReaderDetached extends BackendEvent {
  const ReaderDetached(this.readerName);
  final String readerName;
}

/// A tag touched the reader.
final class TagArrived extends BackendEvent {
  const TagArrived();
}

/// The tag was read and decoded into data.
final class TagFields extends BackendEvent {
  const TagFields(this.fields, {this.rawText, this.uid, this.rawBytes});
  final NfcData fields;
  final String? rawText;
  final String? uid;
  final List<int>? rawBytes;
}

/// The tag is there but could not be read / decoded.
final class TagReadFailed extends BackendEvent {
  const TagReadFailed(this.error, {this.rawText, this.uid, this.rawBytes});
  final String error;
  final String? rawText;
  final String? uid;
  final List<int>? rawBytes;
}

final class TagLeft extends BackendEvent {
  const TagLeft();
}

/// The reader probe's answer changed (or was checked for the first time).
final class ProbeUpdated extends BackendEvent {
  const ProbeUpdated(this.status);
  final ProbeStatus status;
}

final class BackendFailure extends BackendEvent {
  const BackendFailure(this.error, [this.stackTrace]);
  final Object error;
  final StackTrace? stackTrace;
}

/// One way of talking to NFC hardware (Windows PC/SC, Android, iOS, or your own
/// reader type). Implement this to support a reader the package does not know,
/// then pass it to `UniversalNfc(backend: ...)`.
///
/// Rules for implementers:
/// * [start] must NOT fail just because no reader is plugged in; keep watching
///   and emit [ReaderAttached] when one appears.
/// * Emit [TagArrived] first, then either [TagFields] or [TagReadFailed].
/// * Emit [TagLeft] before [ReaderDetached] if a tag was present.
abstract class NfcBackend {
  Stream<BackendEvent> get events;

  /// Can this backend work on this machine at all (PC/SC service reachable, NFC
  /// chip present and on, ...)? Says nothing about a reader being plugged in.
  Future<bool> isAvailable();

  Future<void> start();

  /// Stops watching. [start] may be called again.
  Future<void> stop();

  /// Writes [data] to the tag that is currently on the reader. Must never
  /// throw for expected problems (no tag, too big, locked): return a failure.
  Future<NfcWriteResult> write(NfcData data);

  /// Explains the state of NFC on this machine and how to fix problems.
  Future<NfcDiagnostics> diagnose();

  /// Releases everything. Final.
  Future<void> dispose();
}
