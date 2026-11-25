import 'nfc_data.dart';

/// Describes ONE kind of tag: which fields it carries and how to turn them into
/// a typed Dart object. Register as many models as you like; the reader picks
/// the right one for every tag it reads.
///
/// ```dart
/// final industry = NfcTagModel<IndustryTag>.define(
///   id: 'industry',
///   requiredKeys: {'ind', 'sub'},
///   parse: (f) => IndustryTag(f.requireInt('ind'), f.requireInt('sub')),
/// );
/// ```
///
/// Or extend the class for more control.
abstract class NfcTagModel<T> {
  const NfcTagModel();

  /// Quick way to define a model without writing a class.
  factory NfcTagModel.define({
    required String id,
    Set<String> requiredKeys = const {},
    required T Function(NfcData fields) parse,
  }) =>
      _FunctionTagModel<T>(id: id, requiredKeys: requiredKeys, parseFn: parse);

  /// Unique name. A tag can select its model explicitly by storing this id
  /// under the registry's model key (default `"m"`): `{"m":"industry",...}`.
  String get id;

  /// Keys that must exist on the tag. Also used for automatic detection when
  /// the tag does not name its model: all keys present => this model matches.
  Set<String> get requiredKeys => const {};

  /// Automatic detection. Override for custom rules (e.g. check a value range).
  bool matches(NfcData fields) =>
      requiredKeys.isNotEmpty && requiredKeys.every(fields.containsKey);

  /// Converts raw fields to your type. Throw (e.g. [FormatException]) when the
  /// values are invalid; the reader reports an unreadable tag instead of
  /// crashing.
  T parse(NfcData fields);
}

class _FunctionTagModel<T> extends NfcTagModel<T> {
  const _FunctionTagModel({
    required this.id,
    required this.requiredKeys,
    required this.parseFn,
  });

  @override
  final String id;

  @override
  final Set<String> requiredKeys;

  final T Function(NfcData fields) parseFn;

  @override
  T parse(NfcData fields) => parseFn(fields);
}
