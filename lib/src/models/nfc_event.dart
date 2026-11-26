import '../codec/hex.dart';
import 'nfc_data.dart';
import 'nfc_probe_status.dart';
import 'nfc_tag_model.dart';

/// Overall state of the reader, for showing status in the UI.
enum NfcReaderState {
  /// Not started (or stopped).
  idle,

  /// Started, but no reader is plugged in / NFC unavailable. Plug one in and
  /// it connects by itself.
  waitingForReader,

  /// Reader connected, waiting for a tag.
  listening,

  /// A tag is on the reader.
  tagPresent,

  /// Disposed; cannot be used again.
  disposed,
}

/// Everything the reader reports. Use an exhaustive `switch`:
///
/// ```dart
/// switch (event) {
///   case TagRead(): ...
///   case TagRemoved(): ...
///   case ReaderDisconnected(): ...
///   default: ...
/// }
/// ```
sealed class NfcEvent {
  const NfcEvent();
}

/// [UniversalNfc.state] changed.
final class NfcStateChanged extends NfcEvent {
  const NfcStateChanged(this.state);
  final NfcReaderState state;
  @override
  String toString() => 'NfcStateChanged($state)';
}

/// A reader was plugged in / became usable.
final class ReaderConnected extends NfcEvent {
  const ReaderConnected(this.readerName, {this.profileId});
  final String readerName;

  /// Which reader profile was applied (Windows), e.g. "acr1552".
  final String? profileId;
  @override
  String toString() => 'ReaderConnected($readerName)';
}

/// The reader was unplugged / lost.
final class ReaderDisconnected extends NfcEvent {
  const ReaderDisconnected(this.readerName);
  final String readerName;
  @override
  String toString() => 'ReaderDisconnected($readerName)';
}

/// The reader probe's answer changed: reader present, no reader, service down...
final class ReaderProbeChanged extends NfcEvent {
  const ReaderProbeChanged(this.status);
  final ProbeStatus status;
  @override
  String toString() => 'ReaderProbeChanged($status)';
}

/// A tag touched the reader; reading has started.
final class TagDetected extends NfcEvent {
  const TagDetected();
  @override
  String toString() => 'TagDetected';
}

/// Tag read and understood by a registered model.
final class TagRead extends NfcEvent {
  const TagRead({
    required this.model,
    required this.value,
    required this.fields,
    this.rawText,
    this.uid,
    this.rawBytes,
  });

  /// The model that handled the tag.
  final NfcTagModel<Object?> model;

  /// What `model.parse` returned.
  final Object? value;

  /// All data from the tag (may contain nested objects and lists).
  final NfcData fields;
  final String? rawText;

  /// The card's unique id as hex, e.g. "04A1B2C3D4E580". Null if unavailable.
  final String? uid;

  /// Raw tag memory that was read.
  final List<int>? rawBytes;

  String? get rawHex => rawBytes == null ? null : NfcHex.encode(rawBytes!);

  /// [value] as [T], or null if it is another type.
  T? valueAs<T>() {
    final v = value;
    return v is T ? v : null;
  }

  Object? operator [](String key) => fields[key];

  @override
  String toString() => 'TagRead(${model.id}, $fields, uid: $uid)';
}

/// Tag read fine but no registered model understands it. The raw [fields] are
/// still delivered so the app can decide what to do.
final class UnknownTag extends NfcEvent {
  const UnknownTag(this.fields, {this.rawText, this.uid, this.rawBytes});
  final NfcData fields;
  final String? rawText;
  final String? uid;
  final List<int>? rawBytes;
  String? get rawHex => rawBytes == null ? null : NfcHex.encode(rawBytes!);
  Object? operator [](String key) => fields[key];
  @override
  String toString() => 'UnknownTag($fields, uid: $uid)';
}

/// A tag is present but could not be read or parsed.
final class TagUnreadable extends NfcEvent {
  const TagUnreadable(
    this.error, {
    this.rawText,
    this.fields,
    this.uid,
    this.rawBytes,
  });
  final String error;
  final String? rawText;
  final NfcData? fields;
  final String? uid;
  final List<int>? rawBytes;
  String? get rawHex => rawBytes == null ? null : NfcHex.encode(rawBytes!);
  @override
  String toString() => 'TagUnreadable($error, uid: $uid)';
}

/// The tag was taken away.
final class TagRemoved extends NfcEvent {
  const TagRemoved();
  @override
  String toString() => 'TagRemoved';
}

/// [UniversalNfc.write] succeeded.
final class TagWritten extends NfcEvent {
  const TagWritten({
    required this.data,
    required this.bytesUsed,
    required this.capacity,
  });
  final NfcData data;
  final int bytesUsed;
  final int capacity;
  @override
  String toString() => 'TagWritten($bytesUsed of $capacity bytes)';
}

/// Something went wrong in the backend. The reader keeps running.
final class NfcFailure extends NfcEvent {
  const NfcFailure(this.error, [this.stackTrace]);
  final Object error;
  final StackTrace? stackTrace;
  @override
  String toString() => 'NfcFailure($error)';
}
