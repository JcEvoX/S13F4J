/// 可释放资源。所有注册（命令 / 文件系统 / 编辑器 / 视图）都返回它，
/// 由宿主在插件停用时统一释放。
abstract class Disposable {
  void dispose();
}

class _CallbackDisposable implements Disposable {
  _CallbackDisposable(this._callback);

  void Function()? _callback;

  @override
  void dispose() {
    final callback = _callback;
    _callback = null;
    callback?.call();
  }
}

/// 把回调包装成幂等的 [Disposable]。
Disposable toDisposable(void Function() callback) =>
    _CallbackDisposable(callback);

/// 一组 [Disposable]，按注册的逆序释放；释放后再加入的资源会被立即释放。
class DisposableStore implements Disposable {
  final List<Disposable> _items = [];
  bool _disposed = false;

  bool get isDisposed => _disposed;

  int get length => _items.length;

  T add<T extends Disposable>(T item) {
    if (_disposed) {
      item.dispose();
    } else {
      _items.add(item);
    }
    return item;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final items = _items.reversed.toList();
    _items.clear();
    for (final item in items) {
      try {
        item.dispose();
      } catch (_) {
        // 单个资源释放失败不影响其余资源。
      }
    }
  }

  /// 释放现有资源但保持可继续使用（插件停用后再启用）。
  void clear() {
    final items = _items.reversed.toList();
    _items.clear();
    for (final item in items) {
      try {
        item.dispose();
      } catch (_) {}
    }
  }
}
