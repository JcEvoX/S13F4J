import 'package:flutter/foundation.dart';

import 'when_clause.dart';

/// 上下文键服务：工作台各处把当前状态写进来，`when` 子句据此求值。
class ContextKeyService extends ChangeNotifier {
  final Map<String, Object?> _values = {};
  final Map<String, WhenClause> _cache = {};

  Object? get(String key) => _values[key];

  /// 值未变化时不通知，避免无谓重建。
  void set(String key, Object? value) {
    if (_values.containsKey(key) && _values[key] == value) return;
    if (value == null && !_values.containsKey(key)) return;
    _values[key] = value;
    notifyListeners();
  }

  void setAll(Map<String, Object?> values) {
    var changed = false;
    values.forEach((key, value) {
      if (_values.containsKey(key) && _values[key] == value) return;
      _values[key] = value;
      changed = true;
    });
    if (changed) notifyListeners();
  }

  void remove(String key) {
    if (!_values.containsKey(key)) return;
    _values.remove(key);
    notifyListeners();
  }

  Map<String, Object?> snapshot() => Map.unmodifiable(_values);

  /// 求值；null / 空串恒为真。解析结果带缓存。
  bool evaluate(String? when, {Map<String, Object?>? overrides}) {
    if (when == null || when.trim().isEmpty) return true;
    final clause = _cache.putIfAbsent(when, () => WhenClause.tryParse(when));
    if (overrides == null || overrides.isEmpty) {
      return clause.evaluate(_values);
    }
    return clause.evaluate({..._values, ...overrides});
  }
}
