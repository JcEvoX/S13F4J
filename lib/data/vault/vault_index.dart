import 'filename_policy.dart';
import 'tree_store.dart';
import 'vault_store.dart';

/// 派生索引条目（path / title / mtime / size）。
class VaultIndexEntry {
  const VaultIndexEntry({
    required this.id,
    required this.path,
    required this.title,
    required this.isFolder,
    required this.mtime,
  });

  final String id;
  final String path;
  final String title;
  final bool isFolder;
  final int mtime;
}

/// 派生索引：可随时删除重建，不存用户意图。
///
/// v2 先使用内存索引；M4 再把快照落到
/// `<appDataRoot>/namespaces/notes/index/`，格式与本文档一致。
class VaultIndex {
  final VaultStore _store;

  List<VaultIndexEntry> _entries = const [];
  bool _dirty = true;

  VaultIndex(this._store);

  void invalidate() {
    _dirty = true;
  }

  Future<List<VaultIndexEntry>> ensure(VaultTree tree) async {
    if (!_dirty) return _entries;
    return rebuild(tree);
  }

  Future<List<VaultIndexEntry>> rebuild(VaultTree tree) async {
    final entries = <VaultIndexEntry>[];
    for (final record in tree.nodes) {
      if (!await _store.exists(record.path)) continue;
      final modified = await _store.modifiedAt(record.path);
      entries.add(
        VaultIndexEntry(
          id: record.id,
          path: record.path,
          title: FilenamePolicy.titleOfPath(record.path),
          isFolder: record.isFolder,
          mtime: modified.millisecondsSinceEpoch,
        ),
      );
    }
    _entries = entries;
    _dirty = false;
    return entries;
  }
}
