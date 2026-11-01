import 'dart:convert';

import '../../core/storage/trash_policy.dart';
import 'vault_store.dart';

/// 回收站 manifest 读写（宿主定义格式，D12）。
class TrashManifestStore {
  TrashManifestStore(this._store);

  final VaultStore _store;

  static const String trashDir = '.notepad/trash';
  static const String itemsDir = '.notepad/trash/items';
  static const String manifestPath = '.notepad/trash/manifest.json';
  static const int schema = 1;

  Future<void> ensureLayout() async {
    await _store.ensureDir(itemsDir);
  }

  Future<List<TrashEntry>> load() async {
    if (!await _store.exists(manifestPath)) return <TrashEntry>[];
    try {
      final raw = await _store.readText(manifestPath);
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <TrashEntry>[];
      final list = (decoded['entries'] as List?) ?? const [];
      return [
        for (final item in list)
          TrashEntry.fromJson((item as Map).cast<String, Object?>()),
      ];
    } catch (_) {
      // manifest 损坏：保留现场，返回空列表；调用方可按 items 目录兜底重建。
      final backup = '$trashDir/manifest.corrupt-'
          '${DateTime.now().millisecondsSinceEpoch}.json';
      try {
        await _store.rename(manifestPath, backup);
      } catch (_) {
        // 忽略备份失败
      }
      return <TrashEntry>[];
    }
  }

  Future<void> save(List<TrashEntry> entries) async {
    await ensureLayout();
    final payload = jsonEncode({
      'schema': schema,
      'entries': [for (final entry in entries) entry.toJson()],
    });
    await _store.writeTextAtomic(manifestPath, payload);
  }
}
