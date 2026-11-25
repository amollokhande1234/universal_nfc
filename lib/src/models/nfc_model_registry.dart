import 'nfc_data.dart';
import 'nfc_tag_model.dart';

/// Holds the tag models the reader knows about. Models can be added or removed
/// at any time, also while the reader is running.
class NfcModelRegistry {
  NfcModelRegistry({this.modelKey = 'm'});

  /// Tag field that names the model explicitly. Null disables explicit
  /// selection (only automatic detection is used).
  final String? modelKey;

  final List<NfcTagModel<Object?>> _models = [];

  List<NfcTagModel<Object?>> get models => List.unmodifiable(_models);

  /// Adds a model. Throws if the id is taken, unless [replace] is true.
  void register(NfcTagModel<Object?> model, {bool replace = false}) {
    final i = _models.indexWhere((m) => m.id == model.id);
    if (i < 0) {
      _models.add(model);
    } else if (replace) {
      _models[i] = model;
    } else {
      throw ArgumentError('A model with id "${model.id}" is already registered.');
    }
  }

  bool unregister(String id) {
    final before = _models.length;
    _models.removeWhere((m) => m.id == id);
    return _models.length != before;
  }

  /// Finds the model for a tag:
  /// 1. the tag names a model (`modelKey`) -> that model, or null if unknown;
  /// 2. otherwise the matching model with the MOST required keys (most
  ///    specific wins; ties go to the one registered first);
  /// 3. null when nothing matches.
  NfcTagModel<Object?>? resolve(NfcData fields) {
    final key = modelKey;
    final explicit = key == null ? null : fields[key]?.toString();
    if (explicit != null) {
      for (final m in _models) {
        if (m.id == explicit) return m;
      }
      return null;
    }

    NfcTagModel<Object?>? best;
    for (final m in _models) {
      if (!m.matches(fields)) continue;
      if (best == null || m.requiredKeys.length > best.requiredKeys.length) {
        best = m;
      }
    }
    return best;
  }
}
