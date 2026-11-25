/// Per-model settings for PC/SC readers. Different reader models can need
/// different names, memory ranges or commands; a profile captures that so
/// adding a reader never means editing the reading code.
///
/// ```dart
/// UniversalNfc(readerProfiles: [
///   ReaderProfile(id: 'my-reader', nameContains: ['MyVendor NFC'], maxPage: 40),
///   ...ReaderProfile.defaults,
/// ]);
/// ```
class ReaderProfile {
  const ReaderProfile({
    required this.id,
    this.nameContains = const [],
    this.firstPage = 4,
    this.maxPage = 225,
    this.pagesPerRead = 4,
    this.uidApdu = const [0xFF, 0xCA, 0x00, 0x00, 0x00],
    this.buildReadApdu,
    this.buildWriteApdu,
  });

  final String id;

  /// Case-insensitive fragments of the PC/SC reader name. Empty = matches any
  /// reader (use as a last resort).
  final List<String> nameContains;

  /// First user page (4 on NTAG21x / Ultralight).
  final int firstPage;

  /// Highest page to read. The tag's own size limits this further.
  final int maxPage;

  /// Pages returned by one read command (4 pages = 16 bytes).
  final int pagesPerRead;

  /// "Get UID" command (standard PC/SC: `FF CA 00 00 00`). Null skips reading it.
  final List<int>? uidApdu;

  /// Override the read command if the reader does not use the standard
  /// PC/SC "READ BINARY" (`FF B0 00 <page> <len>`).
  final List<int> Function(int page)? buildReadApdu;

  /// Override the write command if the reader does not use the standard
  /// "UPDATE BINARY" (`FF D6 00 <page> 04 <4 bytes>`).
  final List<int> Function(int page, List<int> data)? buildWriteApdu;

  bool matches(String readerName) {
    if (nameContains.isEmpty) return true;
    final n = readerName.toLowerCase();
    return nameContains.any((s) => n.contains(s.toLowerCase()));
  }

  List<int> readApdu(int page) =>
      buildReadApdu?.call(page) ?? [0xFF, 0xB0, 0x00, page, pagesPerRead * 4];

  List<int> writeApdu(int page, List<int> data) =>
      buildWriteApdu?.call(page, data) ??
      [0xFF, 0xD6, 0x00, page, data.length, ...data];

  static const acr1552 = ReaderProfile(id: 'acr1552', nameContains: ['ACR1552']);
  static const acr1252 = ReaderProfile(id: 'acr1252', nameContains: ['ACR1252']);
  static const acr122u = ReaderProfile(id: 'acr122u', nameContains: ['ACR122']);

  /// Matches any reader with the standard PC/SC commands. Works with most
  /// readers that follow the PC/SC part 3 specification.
  static const generic = ReaderProfile(id: 'generic');

  /// Built-in profiles, tried in this order.
  static const defaults = [acr1552, acr1252, acr122u];
}
