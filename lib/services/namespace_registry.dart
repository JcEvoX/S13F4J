import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/storage/storage_capability.dart';
import '../data/notes_repository.dart';
import '../data/vault/trash_store.dart';
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

  /// 停用只改 `state`：驱动声明描述「能力是否提供备份 / 回收站」，
  /// 与入口是否可见无关；停用后宿主仍可操作其数据（D12）。
  Future<void> deactivate(String pluginId) async {
    await load();
    await _store.guard(() async {
      for (var i = 0; i < _namespaces.length; i++) {
        final item = _namespaces[i];
        if (item.pluginId == pluginId) {
          _namespaces[i] = item.copyWith(state: 'disabled');
        }
      }
      await _save();
    });
  }

  /// 重新启用：恢复 `active`，并按能力默认值校正驱动声明
  /// （兼容旧版本停用时把驱动置 false 的注册表）。
  Future<void> activate(String pluginId) async {
    await load();
    await _store.guard(() async {
      for (var i = 0; i < _namespaces.length; i++) {
        final item = _namespaces[i];
        if (item.pluginId == pluginId) {
          _namespaces[i] = item.copyWith(
            state: 'active',
            backupDriver: true,
            trashDriver: defaultTrashDriver(item),
          );
        }
      }
      await _save();
    });
  }

  /// 启动时把插件启停状态对齐到注册表（只改与期望不一致的记录）。
  Future<void> syncPluginStates(Map<String, bool> enabledByPlugin) async {
    await load();
    for (final entry in enabledByPlugin.entries) {
      final targets = _namespaces.where((n) => n.pluginId == entry.key);
      final mismatch = targets.any(
        (n) => entry.value ? n.state == 'disabled' : n.state == 'active',
      );
      if (!mismatch) continue;
      if (entry.value) {
        await activate(entry.key);
      } else {
        await deactivate(entry.key);
      }
    }
  }

  /// 能力默认是否提供回收站驱动：文件阅读项目只读浏览，不提供（`TrashPolicy = null`）。
  static bool defaultTrashDriver(NamespaceDescriptor descriptor) =>
      descriptor.pluginId != 'builtin.files' &&
      !descriptor.id.startsWith('files.');

  /// 命名空间回收站中的条目数（manifest 记录与 `items/` 子项取较大值）。
  Future<int> trashEntryCount(String namespaceId) async {
    final descriptor = await resolve(namespaceId);
    if (descriptor == null) return 0;
    var manifestCount = 0;
    var itemCount = 0;
    if (descriptor.root.isEmpty) {
      if (await _store.exists(TrashManifestStore.manifestPath)) {
        manifestCount = _countEntries(
          await _store.readText(TrashManifestStore.manifestPath),
        );
      }
      if (await _store.exists(TrashManifestStore.itemsDir)) {
        itemCount =
            (await _store.list(TrashManifestStore.itemsDir)).length;
      }
    } else {
      final root = p.isAbsolute(descriptor.root)
          ? descriptor.root
          : p.join(_store.rootPath, descriptor.root);
      final manifest = File(p.join(root, TrashManifestStore.manifestPath));
      if (await manifest.exists()) {
        manifestCount = _countEntries(await manifest.readAsString());
      }
      final items = Directory(p.join(root, TrashManifestStore.itemsDir));
      if (await items.exists()) {
        itemCount = await items.list().length;
      }
    }
    return manifestCount > itemCount ? manifestCount : itemCount;
  }

  int _countEntries(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return ((decoded['entries'] as List?) ?? const []).length;
      }
    } catch (_) {
      // manifest 损坏时交由 items 目录计数兜底。
    }
    return 0;
  }

  /// 移除注册记录。回收站非空时拒绝（`E-CONFLICT`），避免丢失可恢复数据。
  Future<void> forget(String namespaceId) async {
    await load();
    final pending = await trashEntryCount(namespaceId);
    if (pending > 0) {
      throw NotesException(
        'E-CONFLICT',
        '回收站内仍有 $pending 项，请先清空或恢复后再移除记录',
        detail: namespaceId,
      );
    }
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
