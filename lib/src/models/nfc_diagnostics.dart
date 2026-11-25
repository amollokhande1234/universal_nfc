/// A health report for NFC on this machine. Show it in a settings screen or
/// print it when something does not work.
class NfcDiagnostics {
  const NfcDiagnostics({
    required this.platform,
    required this.supported,
    this.serviceReachable = false,
    this.readers = const [],
    this.selectedReader,
    this.selectedProfile,
    this.notes = const [],
  });

  /// "Windows", "Android", ...
  final String platform;

  /// Does this package have a working backend for this platform?
  final bool supported;

  /// Is the system's smart card / NFC service reachable?
  final bool serviceReachable;

  /// Every reader the system reports.
  final List<String> readers;

  /// The reader that would be used.
  final String? selectedReader;

  /// The reader profile that would be applied.
  final String? selectedProfile;

  /// What is wrong and how to fix it, in plain words.
  final List<String> notes;

  bool get healthy => supported && serviceReachable && selectedReader != null;

  String report() {
    final b = StringBuffer()
      ..writeln('Platform           : $platform')
      ..writeln('Supported          : ${supported ? 'yes' : 'not yet'}')
      ..writeln(
          'NFC service        : ${serviceReachable ? 'reachable' : 'not reachable'}')
      ..writeln(
          'Readers found      : ${readers.isEmpty ? 'none' : readers.join(' | ')}')
      ..writeln('Selected reader    : ${selectedReader ?? '-'}')
      ..writeln('Reader profile     : ${selectedProfile ?? '-'}')
      ..writeln('Healthy            : ${healthy ? 'yes' : 'no'}');
    for (final n in notes) {
      b.writeln('  - $n');
    }
    return b.toString().trimRight();
  }

  @override
  String toString() => report();
}
