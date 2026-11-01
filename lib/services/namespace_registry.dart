import 'dart:convert';

import '../core/storage/storage_capability.dart';
import '../data/vault/vault_store.dart';

/// 命名空间注册表（权威文件在 `<vaultRoot>/.notepad/registry.json`）。
class NamespaceRegistry {
  NamespaceRegistry({required VaultStore store}) : _store = store;

  final VaultStore _store;

  static const String registryPath = '.notepad/registry.json';
  static const int schema = 1;

  final List<NamespaceDescriptor> _namespaces = [];
  bool _loaded = false;

  List<NamespaceDescriptor> get _list => List.unmodifiable(_namespaces);

  Future<void> load() async {
    if (_loaded) return;
    if (await _store.exists(registryPath)) {
      try {
        final raw = await _store.readText(registryPath);
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final map = decoded.cast<String, Object?>();
          final list = (map['namespaces'] as List?) ?? const [];
          _namespaces
            ..clear()
            ..addAll([
              for (final item in list)
                NamespaceDescriptor.fromJson(
                  (item as Map).cast<String, Object?>(),
                ),
            ]);
        }
      } catch (_) {
        // 注册表损坏：不阻塞启动，等待重新注册。
        _namespaces.clear();
      }
    }
    _loaded = true;
  }

  Future<void> ensureNotes() async {
    await load();
    if (_namespaces.any((n) => n.id == 'notes')) return;
    await register(
      NamespaceDescriptor(
        id: 'notes',
        pluginId: 'builtin.notes',
        root: '',
        displayName: '笔记',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> register(NamespaceDescriptor descriptor) async {
    await load();
    await _store.guard(() async {
      _namespaces.removeWhere((n) => n.id == descriptor.id);
      _namespaces.add(descriptor);
      await _save();
    });
  }

  Future<NamespaceDescriptor?> resolve(String namespaceId) async {
    await load();
    for (final descriptor in _namespaces) {
      if (descriptor.id == namespaceId) return descriptor;
    }
    return null;
  }

  Future<List<NamespaceDescriptor>> all() async {
    await load();
    return _list;
  }

  Future<void> deactivate(String pluginId) async {
    await load();
    await _store.guard(() async {
      for (var i = 0; i < _namespaces.length; i++) {
        final item = _namespaces[i];
        if (item.pluginId == pluginId) {
          _namespaces[i] = item.copyWith(
            state: 'disabled',
            backupDriver: false,
            trashDriver: false,
          );
        }
      }
      await _save();
    });
  }

  Future<void> activate(String pluginId) async {
    await load();
    await _store.guard(() async {
      for (var i = 0; i < _namespaces.length; i++) {
        final item = _namespaces[i];
        if (item.pluginId == pluginId) {
          _namespaces[i] = item.copyWith(
            state: 'active',
            backupDriver: true,
            trashDriver: true,
          );
        }
      }
      await _save();
    });
  }

  Future<void> forget(String namespaceId) async {
    await load();
    await _store.guard(() async {
      _namespaces.removeWhere((n) => n.id == namespaceId);
      await _save();
    });
  }

  Future<void> _save() async {
    final payload = jsonEncode({
      'schema': schema,
      'namespaces': [for (final n in _namespaces) n.toJson()],
    });
    await _store.writeTextAtomic(registryPath, payload);
  }
}
