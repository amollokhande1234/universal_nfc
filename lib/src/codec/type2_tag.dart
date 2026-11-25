/// The tag's own description of itself (page 3, "capability container").
class Type2Capability {
  const Type2Capability({
    required this.version,
    required this.dataAreaBytes,
    required this.accessByte,
  });

  final int version;

  /// Usable data area in bytes: NTAG213 = 144, NTAG215 = 496, NTAG216 = 872.
  final int dataAreaBytes;
  final int accessByte;

  /// Write access is open (lower nibble of the access byte is 0).
  bool get writable => (accessByte & 0x0F) == 0x00;

  /// Parses the 4 bytes of page 3. Null if the tag is not NDEF formatted.
  static Type2Capability? parse(List<int> cc) {
    if (cc.length < 4 || cc[0] != 0xE1) return null;
    final size = cc[2] * 8;
    if (size == 0) return null;
    return Type2Capability(version: cc[1], dataAreaBytes: size, accessByte: cc[3]);
  }
}

class Type2WriteException implements Exception {
  const Type2WriteException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What to write, and where.
class Type2WritePlan {
  const Type2WritePlan({
    required this.startPage,
    required this.bytes,
    required this.usedBytes,
    required this.capacity,
  });

  /// First page to write, counted from the first user page (0 = page 4).
  final int startPage;

  /// Bytes to write from [startPage]; always a multiple of 4.
  final List<int> bytes;

  /// Data area bytes used after the write, including NDEF framing.
  final int usedBytes;
  final int capacity;

  List<List<int>> get pages => [
        for (var i = 0; i < bytes.length; i += 4) bytes.sublist(i, i + 4),
      ];
}

/// Pure functions for the memory layout of NFC Forum Type 2 tags: TLV framing,
/// finding where the NDEF message goes, and planning a safe write.
class Type2Layout {
  const Type2Layout._();

  /// Offset (from the first user byte) where the NDEF TLV starts or should be
  /// placed. Existing control TLVs (such as a Lock Control TLV) before it are
  /// skipped so they are never overwritten. Null if not found in [memory]
  /// (read more bytes, or there is no room).
  static int? findNdefStart(List<int> memory) {
    var i = 0;
    while (i < memory.length) {
      final t = memory[i];
      if (t == 0x03 || t == 0x00 || t == 0xFE) return i;
      if (i + 1 >= memory.length) return null;
      var len = memory[i + 1];
      var header = 2;
      if (len == 0xFF) {
        if (i + 3 >= memory.length) return null;
        len = (memory[i + 2] << 8) | memory[i + 3];
        header = 4;
      }
      i += header + len;
    }
    return null;
  }

  /// `03 <len> <message> FE`.
  static List<int> wrapTlv(List<int> message) {
    final n = message.length;
    final length = n < 0xFF ? [n] : [0xFF, (n >> 8) & 0xFF, n & 0xFF];
    return [0x03, ...length, ...message, 0xFE];
  }

  /// Plans a write of [message] into a tag whose data area is
  /// [dataAreaBytes] long and whose current content starts with [memory].
  /// Throws [Type2WriteException] if it does not fit or cannot be placed.
  static Type2WritePlan plan({
    required List<int> memory,
    required List<int> message,
    required int dataAreaBytes,
  }) {
    final start = findNdefStart(memory);
    if (start == null) {
      throw const Type2WriteException(
        'Could not find where to put the NDEF message on this tag.',
      );
    }
    final tlv = wrapTlv(message);
    final end = start + tlv.length;
    if (end > dataAreaBytes) {
      throw Type2WriteException(
        'Data needs ${tlv.length} bytes but only ${dataAreaBytes - start} are '
        'free (the tag holds $dataAreaBytes). Use less data or a bigger tag.',
      );
    }
    final alignedStart = (start ~/ 4) * 4;
    final bytes = <int>[...memory.sublist(alignedStart, start), ...tlv];
    while (bytes.length % 4 != 0) {
      bytes.add(0x00);
    }
    return Type2WritePlan(
      startPage: alignedStart ~/ 4,
      bytes: bytes,
      usedBytes: end,
      capacity: dataAreaBytes,
    );
  }
}
