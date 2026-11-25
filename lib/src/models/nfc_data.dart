/// The content of a tag: a JSON-like map. Values can be text, numbers,
/// booleans, nested maps or lists.
typedef NfcData = Map<String, Object?>;

/// Typed, forgiving accessors, so models do not repeat `int.tryParse` and
/// casts. Numbers stored as text (`"2"`) and as numbers (`2`) both work.
extension NfcDataAccess on Map<String, Object?> {
  /// Text value, or null when missing or when the value is an object / list.
  String? str(String key) {
    final v = this[key];
    if (v == null || v is Map || v is List) return null;
    return v.toString();
  }

  int? integer(String key) {
    final v = this[key];
    if (v is int) return v;
    if (v is num) return v == v.truncateToDouble() ? v.toInt() : null;
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  double? number(String key) {
    final v = this[key];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  bool? boolean(String key) {
    final v = this[key];
    if (v is bool) return v;
    if (v is String) {
      switch (v.trim().toLowerCase()) {
        case 'true' || '1' || 'yes':
          return true;
        case 'false' || '0' || 'no':
          return false;
      }
    }
    return null;
  }

  /// A nested object.
  NfcData? object(String key) {
    final v = this[key];
    if (v is Map) return v.map((k, x) => MapEntry(k.toString(), x));
    return null;
  }

  List<Object?>? list(String key) {
    final v = this[key];
    return v is List ? List<Object?>.from(v) : null;
  }

  /// Like [str] but throws [FormatException] when missing. Use inside a
  /// model's `parse`; the reader reports it as an unreadable tag.
  String requireString(String key) =>
      str(key) ?? (throw FormatException('Missing or invalid text "$key"'));

  int requireInt(String key) =>
      integer(key) ?? (throw FormatException('Missing or invalid number "$key"'));
}
