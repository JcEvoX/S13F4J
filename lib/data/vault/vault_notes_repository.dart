import 'dart:convert';

import 'package:path/path.dart' as p;

import '../../core/storage/trash_policy.dart';
import '../../models/note.dart';
import '../notes_repository.dart';
import 'filename_policy.dart';
import 'trash_store.dart';
import 'tree_store.dart';
import 'vault_index.dart';
import 'vault_store.dart';

/// 文件化笔记仓储（vault 权威实现）。
///
/// 布局：正文 = `<vaultRoot>/<相对路径>.md`；元数据 = `.notepad/tree.json`；
/// 回收站 = `.notepad/trash/`。所有变更经 [VaultStore.guard] 串行执行。
class VaultNotesRepository implements NotesRepository {
  VaultNotesRepository({required VaultStore store})
      : _store = store,
        _treeStore = TreeStore(store),
        _trash = TrashManifestStore(store),
        _index = VaultIndex(store);

  factory VaultNotesRepository.atRoot(String rootPath) =>
      VaultNotesRepository(store: VaultStore(rootPath));

  final VaultStore _store;
  final TreeStore _treeStore;
  final TrashManifestStore _trash;
  final VaultIndex _index;

  VaultTree _tree = VaultTree();
  Future<void>? _initFuture;
  bool _initialized = false;
  int _seq = 0;

  static const String namespaceId = 'notes';
  static const String _namespaceMarker = '.notepad/namespace.json';

  // ---- 初始化 ----

  @override
  Future<void> init() => _initFuture ??= _doInit();

  Future<void> _doInit() async {
    await _store.ensureDir('.notepad');
    await _trash.ensureLayout();
    await _store.ensureDir('assets');
    _tree = await _treeStore.load();
    await _reconcileAll();
    if (!await _store.exists(_namespaceMarker)) {
      await _store.writeTextAtomic(
        _namespaceMarker,
        jsonEncode({
          'schema': 1,
          'namespaceId': namespaceId,
          'pluginId': 'builtin.notes',
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        }),
      );
    }
    _index.invalidate();
    _initialized = true;
  }

  Future<void> _ensureInit() async {
    if (_initialized) return;
    await init();
  }

  Future<void> _reconcileAll() async {
    final disk = <String, bool>{}; // path -> isFolder
    await _scanDir('', disk);

    var changed = false;
    for (final entry in disk.entries) {
      final existing = _tree.byPath(entry.key);
      if (existing == null) {
        _tree.nodes.add(_newRecord(entry.key, entry.value));
        changed = true;
      } else if (existing.isFolder != entry.value) {
        final index = _tree.nodes.indexOf(existing);
        _tree.nodes[index] = VaultNodeRecord(
          id: existing.id,
          kind: entry.value ? 'folder' : 'note',
          path: entry.key,
          order: existing.order,
          createdAt: existing.createdAt,
          updatedAt: existing.updatedAt,
        );
        changed = true;
      } else if (!existing.isFolder) {
        // 正文文件比 tree 新（例如崩溃前已 rename 未写 tree）→ 以磁盘为准校正。
        final modified = await _store.modifiedAt(entry.key);
        final mtime = modified.millisecondsSinceEpoch;
        if (mtime > existing.updatedAt) {
          existing.updatedAt = mtime;
          changed = true;
        }
      }
    }

    // 去掉同路径重复记录。
    final seen = <String>{};
    final unique = <VaultNodeRecord>[];
    for (final record in _tree.nodes) {
      if (seen.add(record.path)) unique.add(record);
    }
    if (unique.length != _tree.nodes.length) {
      _tree.nodes
        ..clear()
        ..addAll(unique);
      changed = true;
    }

    if (changed) {
      await _treeStore.save(_tree);
    }
  }

  Future<void> _scanDir(String relDir, Map<String, bool> out) async {
    final entries = await _store.list(relDir);
    for (final entry in entries) {
      if (_isReservedName(entry.name)) continue;
      if (entry.isDirectory) {
        out[entry.path] = true;
        await _scanDir(entry.path, out);
      } else if (FilenamePolicy.isNotePath(entry.path)) {
        out[entry.path] = false;
      }
    }
  }

  static bool _isReservedName(String name) {
    final lower = name.toLowerCase();
    return name.startsWith('.') || lower == 'assets';
  }

  bool _isReservedPath(String path) {
    final first = path.split('/').first;
    return first.startsWith('.') || first.toLowerCase() == 'assets';
  }

  VaultNodeRecord _newRecord(String path, bool isFolder) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return VaultNodeRecord(
      id: _newId(isFolder),
      kind: isFolder ? 'folder' : 'note',
      path: path,
      order: _tree.nextOrder(VaultTree.parentOf(path)),
      createdAt: now,
      updatedAt: now,
    );
  }

  String _newId(bool isFolder) {
    final prefix = isFolder ? 'f' : 'n';
    while (true) {
      final candidate =
          '$prefix-${DateTime.now().millisecondsSinceEpoch}-${_seq++}';
      if (_tree.byId(candidate) == null) return candidate;
    }
  }

  // ---- 读取 ----

  @override
  Future<List<NotePadNode>> childrenOf(String? folderId) async {
    await _ensureInit();
    var parentPath = '';
    if (folderId != null) {
      final folder = _tree.byId(folderId);
      if (folder == null) {
        throw NotesException('E-NOT-FOUND', '文件夹不存在: $folderId');
      }
      parentPath = folder.path;
    }
    await _reconcileDir(parentPath);
    final records = _tree.sortedChildren(parentPath);
    final out = <NotePadNode>[];
    for (final record in records) {
      if (!await _store.exists(record.path)) continue;
      out.add(await _nodeOf(record, parentId: folderId, preview: true));
    }
    return out;
  }

  Future<void> _reconcileDir(String parentPath) async {
    final entries = await _store.list(parentPath);
    var changed = false;
    for (final entry in entries) {
      if (_isReservedName(entry.name)) continue;
      if (!entry.isDirectory && !FilenamePolicy.isNotePath(entry.path)) {
        continue;
      }
      if (_tree.byPath(entry.path) == null) {
        _tree.nodes.add(_newRecord(entry.path, entry.isDirectory));
        changed = true;
      }
    }
    if (changed) {
      await _treeStore.save(_tree);
      _index.invalidate();
    }
  }

  @override
  Future<NotePadNode?> nodeById(String id) async {
    await _ensureInit();
    final record = _tree.byId(id);
    if (record == null) return null;
    final parentId = _parentIdOf(record);
    if (record.isFolder) {
      return record.toNode(parentId: parentId);
    }
    var body = '';
    try {
      body = await _store.readText(record.path);
    } catch (_) {
      body = '';
    }
    return record.toNode(content: body, parentId: parentId);
  }

  @override
  Future<String> readBody(String id) async {
    await _ensureInit();
    final record = _tree.byId(id);
    if (record == null || record.isFolder) {
      throw NotesException('E-NOT-FOUND', '文章不存在: $id');
    }
    if (!await _store.exists(record.path)) {
      throw NotesException('E-NOT-FOUND', '文章文件已丢失: ${record.path}');
    }
    return _store.readText(record.path);
  }

  @override
  Future<List<NotePadNode>> allFolders() async {
    await _ensureInit();
    final out = <NotePadNode>[];
    for (final record in _tree.nodes) {
      if (!record.isFolder) continue;
      if (!await _store.exists(record.path)) continue;
      out.add(record.toNode(parentId: _parentIdOf(record)));
    }
    out.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      if (byOrder != 0) return byOrder;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return out;
  }

  // ---- 写入 ----

  @override
  Future<void> writeBody(String id, String body) async {
    await _ensureInit();
    await _store.guard(() async {
      final record = _tree.byId(id);
      if (record == null || record.isFolder) {
        throw NotesException('E-NOT-FOUND', '文章不存在: $id');
      }
      if (!await _store.exists(record.path)) {
        throw NotesException('E-NOT-FOUND', '文章文件已丢失: ${record.path}');
      }
      await _store.writeTextAtomic(record.path, body);
      record.updatedAt = DateTime.now().millisecondsSinceEpoch;
      await _treeStore.save(_tree);
      _index.invalidate();
    });
  }

  @override
  Future<NotePadNode> createNode({
    required bool isFolder,
    required String title,
    String? parentId,
    String content = '',
  }) async {
    await _ensureInit();
    return _store.guard(() async {
      var parentPath = '';
      if (parentId != null) {
        final parent = _tree.byId(parentId);
        if (parent == null || !parent.isFolder) {
          throw NotesException('E-NOT-FOUND', '目标文件夹不存在: $parentId');
        }
        parentPath = parent.path;
      }
      final desired = FilenamePolicy.sanitizeTitle(title, isFolder: isFolder);
      final unique = FilenamePolicy.uniqueTitle(
        desired,
        _tree.siblingTitles(parentPath),
      );
      final fileName = isFolder ? unique : '$unique.md';
      final path = parentPath.isEmpty ? fileName : '$parentPath/$fileName';

      if (isFolder) {
        await _store.ensureDir(path);
      } else {
        await _store.ensureDir(parentPath);
        await _store.writeTextAtomic(path, content);
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final record = VaultNodeRecord(
        id: _newId(isFolder),
        kind: isFolder ? 'folder' : 'note',
        path: path,
        order: _tree.nextOrder(parentPath),
        createdAt: now,
        updatedAt: now,
      );
      _tree.nodes.add(record);
      await _treeStore.save(_tree);
      _index.invalidate();

      final body = isFolder ? '' : content;
      return record.toNode(content: body, parentId: parentId);
    });
  }

  @override
  Future<void> rename(String id, String newTitle) async {
    await _ensureInit();
    await _store.guard(() async {
      final record = _tree.byId(id);
      if (record == null) {
        throw NotesException('E-NOT-FOUND', '节点不存在: $id');
      }
      final parentPath = VaultTree.parentOf(record.path);
      final desired =
          FilenamePolicy.sanitizeTitle(newTitle, isFolder: record.isFolder);
      if (desired == FilenamePolicy.titleOfPath(record.path)) return;
      final unique = FilenamePolicy.uniqueTitle(
        desired,
        _tree.siblingTitles(parentPath, excludeId: id),
      );
      final fileName = record.isFolder ? unique : '$unique.md';
      final newPath = parentPath.isEmpty ? fileName : '$parentPath/$fileName';
      if (newPath == record.path) return;

      final oldPath = record.path;
      if (await _store.exists(oldPath)) {
        await _store.rename(oldPath, newPath);
      }
      _replacePathPrefix(oldPath, newPath);
      record.path = newPath;
      record.updatedAt = DateTime.now().millisecondsSinceEpoch;
      await _treeStore.save(_tree);
      _index.invalidate();
    });
  }

  void _replacePathPrefix(String oldRoot, String newRoot) {
    for (final record in _tree.descendantsOfPath(oldRoot)) {
      record.path = '$newRoot${record.path.substring(oldRoot.length)}';
    }
  }

  @override
  Future<void> move(List<String> ids, String? targetFolderId) async {
    await _ensureInit();
    await _store.guard(() async {
      var targetPath = '';
      if (targetFolderId != null) {
        final target = _tree.byId(targetFolderId);
        if (target == null || !target.isFolder) {
          throw NotesException('E-NOT-FOUND', '目标文件夹不存在: $targetFolderId');
        }
        targetPath = target.path;
      }

      final moving = ids.toSet();
      final reserved = <String>{};
      for (final child in _tree.childrenOfPath(targetPath)) {
        if (!moving.contains(child.id)) {
          reserved.add(FilenamePolicy.titleOfPath(child.path));
        }
      }

      final plans = <_MovePlan>[];
      var order = _tree.nextOrder(targetPath);
      for (final id in ids) {
        final record = _tree.byId(id);
        if (record == null) {
          throw NotesException('E-NOT-FOUND', '节点不存在: $id');
        }
        if (record.isFolder &&
            (targetPath == record.path ||
                _tree.isDescendantPath(record.path, targetPath))) {
          throw NotesException('E-CYCLE', '不能把文件夹移动到自身或后代');
        }
        if (VaultTree.parentOf(record.path) == targetPath) {
          // 已在目标目录，保持原顺序，不参与移动。
          continue;
        }
        final unique = FilenamePolicy.uniqueTitle(
          FilenamePolicy.titleOfPath(record.path),
          reserved,
        );
        reserved.add(unique);
        final fileName = record.isFolder ? unique : '$unique.md';
        final newPath = targetPath.isEmpty ? fileName : '$targetPath/$fileName';
        plans.add(
          _MovePlan(record: record, oldPath: record.path, newPath: newPath,
              order: order++),
        );
      }

      final applied = <_MovePlan>[];
      try {
        for (final plan in plans) {
          if (await _store.exists(plan.oldPath)) {
            await _store.rename(plan.oldPath, plan.newPath);
          }
          applied.add(plan);
        }
      } catch (e) {
        for (final plan in applied.reversed) {
          try {
            await _store.rename(plan.newPath, plan.oldPath);
          } catch (_) {
            // 回滚尽力而为
          }
        }
        throw NotesException('E-IO', '移动失败：$e', retryable: true);
      }

      for (final plan in plans) {
        _replacePathPrefix(plan.oldPath, plan.newPath);
        plan.record.path = plan.newPath;
        plan.record.order = plan.order;
        plan.record.updatedAt = DateTime.now().millisecondsSinceEpoch;
      }
      await _treeStore.save(_tree);
      _index.invalidate();
    });
  }

  @override
  Future<void> reorder(String? folderId, List<String> orderedIds) async {
    await _ensureInit();
    await _store.guard(() async {
      var parentPath = '';
      if (folderId != null) {
        final folder = _tree.byId(folderId);
        if (folder == null || !folder.isFolder) {
          throw NotesException('E-NOT-FOUND', '文件夹不存在: $folderId');
        }
        parentPath = folder.path;
      }
      final children = _tree.childrenOfPath(parentPath);
      final childIds = {for (final child in children) child.id};
      for (final id in orderedIds) {
        if (!childIds.contains(id)) {
          throw NotesException('E-VALIDATE', '排序包含非本层节点: $id');
        }
      }
      var next = 0;
      for (final id in orderedIds) {
        _tree.byId(id)!.order = next++;
      }
      for (final child in children) {
        if (!orderedIds.contains(child.id)) {
          child.order = next++;
        }
      }
      await _treeStore.save(_tree);
      _index.invalidate();
    });
  }

  @override
  Future<void> moveToTrash(List<String> ids) async {
    await _ensureInit();
    await _store.guard(() async {
      final roots = <String>[];
      for (final id in ids) {
        final record = _tree.byId(id);
        if (record == null) continue;
        final hasAncestorSelected = ids.any((otherId) {
          if (otherId == id) return false;
          final other = _tree.byId(otherId);
          return other != null &&
              other.isFolder &&
              _tree.isDescendantPath(other.path, record.path);
        });
        if (!hasAncestorSelected) roots.add(id);
      }
      if (roots.isEmpty) return;

      final entries = await _trash.load();
      final applied = <_TrashPlan>[];
      try {
        for (final id in roots) {
          final record = _tree.byId(id);
          if (record == null) continue;
          final oldPath = record.path;
          final baseName = p.posix.basename(oldPath);
          final itemDir = 'items/$id';
          final trashPath = '$itemDir/$baseName';
          await _store.ensureDir('${TrashManifestStore.itemsDir}/$id');
          final target = '${TrashManifestStore.trashDir}/$trashPath';
          if (await _store.exists(oldPath)) {
            await _store.rename(oldPath, target);
          }
          applied.add(
            _TrashPlan(record: record, oldPath: oldPath, targetPath: target),
          );
          entries.removeWhere((entry) => entry.id == id);
          entries.add(
            TrashEntry(
              id: id,
              kind: record.kind,
              originalPath: oldPath,
              trashPath: trashPath,
              deletedAt: DateTime.now().millisecondsSinceEpoch,
              metadata: {'title': FilenamePolicy.titleOfPath(oldPath)},
            ),
          );
        }
        await _trash.save(entries);
        for (final plan in applied) {
          _tree.removeSubtree(plan.record.id);
        }
        await _treeStore.save(_tree);
        _index.invalidate();
      } catch (e) {
        for (final plan in applied.reversed) {
          try {
            await _store.rename(plan.targetPath, plan.oldPath);
          } catch (_) {
            // 回滚尽力而为
          }
        }
        throw NotesException('E-IO', '移入回收站失败：$e', retryable: true);
      }
    });
  }

  @override
  Future<List<ScopedTrashEntry>> listTrash() async {
    await _ensureInit();
    final entries = await _trash.load();
    entries.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return [
      for (final entry in entries)
        ScopedTrashEntry(
          namespaceId: namespaceId,
          displayName: '笔记',
          entry: entry,
        ),
    ];
  }

  @override
  Future<void> restore(List<String> ids) async {
    await _ensureInit();
    await _store.guard(() async {
      final entries = await _trash.load();
      final applied = <_RestorePlan>[];
      try {
        for (final id in ids) {
          final matches = entries.where((entry) => entry.id == id).toList();
          if (matches.isEmpty) continue;
          final entry = matches.first;
          final targetPath = await _uniqueTargetPath(
            entry.originalPath,
            isFolder: entry.isFolder,
          );
          final source = '${TrashManifestStore.trashDir}/${entry.trashPath}';
          if (await _store.exists(source)) {
            await _store.rename(source, targetPath);
          }
          final now = DateTime.now().millisecondsSinceEpoch;
          final parentPath = VaultTree.parentOf(targetPath);
          if (_tree.byPath(targetPath) == null) {
            _tree.nodes.add(
              VaultNodeRecord(
                id: entry.id,
                kind: entry.kind,
                path: targetPath,
                order: _tree.nextOrder(parentPath),
                createdAt: now,
                updatedAt: now,
              ),
            );
          }
          if (entry.isFolder) {
            await _addRecordsForSubtree(targetPath);
          }
          applied.add(
            _RestorePlan(source: source, targetPath: targetPath),
          );
          entries.remove(entry);
        }
        await _treeStore.save(_tree);
        await _trash.save(entries);
        _index.invalidate();
      } catch (e) {
        for (final plan in applied.reversed) {
          try {
            await _store.rename(plan.targetPath, plan.source);
          } catch (_) {
            // 回滚尽力而为
          }
        }
        throw NotesException('E-IO', '恢复失败：$e', retryable: true);
      }
    });
  }

  Future<String> _uniqueTargetPath(
    String desired, {
    required bool isFolder,
  }) async {
    if (!await _store.exists(desired)) return desired;
    final parentPath = VaultTree.parentOf(desired);
    final title = FilenamePolicy.titleOfPath(desired);
    final ext = isFolder ? '' : '.md';
    var index = 2;
    var candidate = desired;
    while (await _store.exists(candidate)) {
      candidate = parentPath.isEmpty
          ? '$title ($index)$ext'
          : '$parentPath/$title ($index)$ext';
      index++;
    }
    return candidate;
  }

  Future<void> _addRecordsForSubtree(String rootPath) async {
    final entries = await _store.list(rootPath);
    for (final entry in entries) {
      if (_isReservedName(entry.name)) continue;
      if (!entry.isDirectory && !FilenamePolicy.isNotePath(entry.path)) {
        continue;
      }
      if (_tree.byPath(entry.path) == null) {
        _tree.nodes.add(_newRecord(entry.path, entry.isDirectory));
      }
      if (entry.isDirectory) {
        await _addRecordsForSubtree(entry.path);
      }
    }
  }

  @override
  Future<void> purge(List<String> ids) async {
    await _ensureInit();
    await _store.guard(() async {
      final entries = await _trash.load();
      for (final id in ids) {
        entries.removeWhere((entry) => entry.id == id);
        await _store.delete('${TrashManifestStore.itemsDir}/$id');
      }
      await _trash.save(entries);
    });
  }

  // ---- 搜索 / 最近 / 统计 ----

  @override
  Future<List<NotePadNode>> search(String keyword) async {
    await _ensureInit();
    final query = keyword.trim().toLowerCase();
    if (query.isEmpty) return const [];
    final out = <NotePadNode>[];
    for (final record in _tree.nodes) {
      if (!await _store.exists(record.path)) continue;
      final title = FilenamePolicy.titleOfPath(record.path);
      if (record.isFolder) {
        if (title.toLowerCase().contains(query)) {
          out.add(record.toNode(parentId: _parentIdOf(record)));
        }
        continue;
      }
      var body = '';
      try {
        body = await _store.readText(record.path);
      } catch (_) {
        continue;
      }
      if (title.toLowerCase().contains(query) ||
          body.toLowerCase().contains(query)) {
        out.add(
          record.toNode(
            content: _previewOf(body),
            parentId: _parentIdOf(record),
          ),
        );
      }
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out.take(200).toList();
  }

  @override
  Future<List<NotePadNode>> recent({int limit = 50}) async {
    await _ensureInit();
    final notes = <VaultNodeRecord>[];
    for (final record in _tree.nodes) {
      if (!record.isFolder && await _store.exists(record.path)) {
        notes.add(record);
      }
    }
    notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final out = <NotePadNode>[];
    for (final record in notes.take(limit)) {
      var body = '';
      try {
        body = await _store.readText(record.path);
      } catch (_) {
        body = '';
      }
      out.add(
        record.toNode(
          content: _previewOf(body),
          parentId: _parentIdOf(record),
        ),
      );
    }
    return out;
  }

  @override
  Future<NoteStatistics> statistics() async {
    await _ensureInit();
    await _index.ensure(_tree);
    var folders = 0;
    var articles = 0;
    var words = 0;
    var lastEdited = 0;
    for (final record in _tree.nodes) {
      if (!await _store.exists(record.path)) continue;
      if (record.isFolder) {
        folders++;
        continue;
      }
      articles++;
      try {
        words += _countWords(await _store.readText(record.path));
      } catch (_) {
        // 读失败不计字数
      }
      if (record.updatedAt > lastEdited) lastEdited = record.updatedAt;
    }
    final recycled = (await _trash.load()).length;
    return NoteStatistics(
      folders: folders,
      articles: articles,
      words: words,
      recycled: recycled,
      lastEditedAt: lastEdited,
    );
  }

  @override
  Future<List<NotePadNode>> allNodes() async {
    await _ensureInit();
    final out = <NotePadNode>[];
    for (final record in _tree.nodes) {
      final parentId = _parentIdOf(record);
      if (record.isFolder) {
        out.add(record.toNode(parentId: parentId));
        continue;
      }
      var body = '';
      try {
        body = await _store.readText(record.path);
      } catch (_) {
        body = '';
      }
      out.add(record.toNode(content: body, parentId: parentId));
    }

    for (final entry in await _trash.load()) {
      final title = entry.metadata['title'];
      var body = '';
      if (!entry.isFolder) {
        try {
          body = await _store.readText(
            '${TrashManifestStore.trashDir}/${entry.trashPath}',
          );
        } catch (_) {
          body = '';
        }
      }
      out.add(
        NotePadNode(
          id: entry.id,
          isFolder: entry.isFolder,
          title: title is String && title.isNotEmpty
              ? title
              : FilenamePolicy.titleOfPath(entry.originalPath),
          content: body,
          parentId: null,
          sortOrder: 0,
          isRecycled: true,
          createdAt: entry.deletedAt,
          updatedAt: entry.deletedAt,
          deletedAt: entry.deletedAt,
        ),
      );
      // 回收站文件夹需要展开子树，保证备份导出不丢内容。
      if (entry.isFolder) {
        await _collectTrashChildren(
          '${TrashManifestStore.trashDir}/${entry.trashPath}',
          entry.id,
          entry.deletedAt,
          out,
        );
      }
    }
    return out;
  }

  Future<void> _collectTrashChildren(
    String dirPath,
    String parentId,
    int deletedAt,
    List<NotePadNode> out,
  ) async {
    final entries = await _store.list(dirPath);
    for (final entry in entries) {
      if (_isReservedName(entry.name)) continue;
      final rel = entry.path.substring(dirPath.length + 1);
      final childId = '$parentId/$rel';
      if (entry.isDirectory) {
        out.add(
          NotePadNode(
            id: childId,
            isFolder: true,
            title: entry.name,
            content: '',
            parentId: parentId,
            sortOrder: 0,
            isRecycled: true,
            createdAt: deletedAt,
            updatedAt: deletedAt,
            deletedAt: deletedAt,
          ),
        );
        await _collectTrashChildren(entry.path, childId, deletedAt, out);
        continue;
      }
      if (!FilenamePolicy.isNotePath(entry.path)) continue;
      var body = '';
      try {
        body = await _store.readText(entry.path);
      } catch (_) {
        body = '';
      }
      out.add(
        NotePadNode(
          id: childId,
          isFolder: false,
          title: FilenamePolicy.titleOfPath(entry.path),
          content: body,
          parentId: parentId,
          sortOrder: 0,
          isRecycled: true,
          createdAt: deletedAt,
          updatedAt: deletedAt,
          deletedAt: deletedAt,
        ),
      );
    }
  }

  // ---- 迁移 / 旧备份导入 ----

  @override
  Future<void> replaceAll(List<NotePadNode> nodes, {String? stagingDir}) async {
    await _ensureInit();
    await _store.guard(() async {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final prevDir = '.notepad/staging/prev-$stamp';
      final movedBackups = <String>[];
      String? trashItemsBackup;
      String? trashManifestBackup;
      try {
        final top = await _store.list('');
        for (final entry in top) {
          if (_isReservedPath(entry.path)) continue;
          await _store.ensureDir(prevDir);
          final target = '$prevDir/${entry.name}';
          await _store.rename(entry.path, target);
          movedBackups.add(target);
        }

        // 旧回收站一并转入 staging，成功后随 prevDir 删除，失败可回滚。
        if (await _store.exists(TrashManifestStore.itemsDir)) {
          trashItemsBackup = '$prevDir/.trash-items';
          await _store.rename(TrashManifestStore.itemsDir, trashItemsBackup);
        }
        if (await _store.exists(TrashManifestStore.manifestPath)) {
          trashManifestBackup = '$prevDir/.trash-manifest.json';
          await _store.rename(
            TrashManifestStore.manifestPath,
            trashManifestBackup,
          );
        }
        await _store.ensureDir(TrashManifestStore.itemsDir);

        _tree.nodes.clear();
        final active = nodes.where((n) => !n.isRecycled).toList();
        final recycled = nodes.where((n) => n.isRecycled).toList();
        final byId = {for (final node in active) node.id: node};
        final idPath = <String, String>{};
        final folderPaths = <String, String>{};

        final folders = active.where((n) => n.isFolder).toList()
          ..sort((a, b) => _depthOf(a, byId).compareTo(_depthOf(b, byId)));
        for (final folder in folders) {
          final parentPath = _parentPathOf(folder, byId, idPath);
          final unique = FilenamePolicy.uniqueTitle(
            FilenamePolicy.sanitizeTitle(folder.title, isFolder: true),
            _tree.siblingTitles(parentPath),
          );
          final path = parentPath.isEmpty ? unique : '$parentPath/$unique';
          await _store.ensureDir(path);
          idPath[folder.id] = path;
          folderPaths[folder.id] = path;
          _tree.nodes.add(
            VaultNodeRecord(
              id: folder.id,
              kind: 'folder',
              path: path,
              order: folder.sortOrder,
              createdAt: folder.createdAt,
              updatedAt: folder.updatedAt,
            ),
          );
        }

        for (final note in active.where((n) => !n.isFolder)) {
          final parentPath = _parentPathOf(note, byId, idPath);
          final unique = FilenamePolicy.uniqueTitle(
            FilenamePolicy.sanitizeTitle(note.title, isFolder: false),
            _tree.siblingTitles(parentPath),
          );
          final fileName = '$unique.md';
          final path = parentPath.isEmpty ? fileName : '$parentPath/$fileName';
          await _store.ensureDir(parentPath);
          await _store.writeTextAtomic(path, note.content);
          idPath[note.id] = path;
          _tree.nodes.add(
            VaultNodeRecord(
              id: note.id,
              kind: 'note',
              path: path,
              order: note.sortOrder,
              createdAt: note.createdAt,
              updatedAt: note.updatedAt,
            ),
          );
        }

        // 回收站节点写入 `.notepad/trash/` + manifest（见架构 6.6）。
        final recycledById = {for (final node in recycled) node.id: node};
        final roots = recycled.where((n) {
          final parentId = n.parentId;
          return parentId == null || !recycledById.containsKey(parentId);
        }).toList();
        final entries = <TrashEntry>[];
        for (final root in roots) {
          entries.add(
            await _writeRecycledRoot(root, recycledById, folderPaths),
          );
        }
        await _trash.save(entries);

        await _treeStore.save(_tree);
        _index.invalidate();
        try {
          await _store.delete(prevDir);
        } catch (_) {
          // 旧内容清理失败不影响恢复结果
        }
      } catch (e) {
        // 回滚：清掉本次写入，再把旧内容搬回。
        try {
          final top = await _store.list('');
          for (final entry in top) {
            if (_isReservedPath(entry.path)) continue;
            await _store.delete(entry.path);
          }
          await _store.delete(TrashManifestStore.itemsDir);
          await _store.delete(TrashManifestStore.manifestPath);
          for (final backup in movedBackups) {
            final name = p.posix.basename(backup);
            try {
              await _store.rename(backup, name);
            } catch (_) {
              // 回滚尽力而为
            }
          }
          if (trashItemsBackup != null) {
            try {
              await _store.rename(
                trashItemsBackup,
                TrashManifestStore.itemsDir,
              );
            } catch (_) {
              // 回滚尽力而为
            }
          }
          if (trashManifestBackup != null) {
            try {
              await _store.rename(
                trashManifestBackup,
                TrashManifestStore.manifestPath,
              );
            } catch (_) {
              // 回滚尽力而为
            }
          }
        } catch (_) {
          // 忽略回滚失败
        }
        throw NotesException('E-IO', '导入失败：$e', retryable: true);
      }
    });
  }

  /// 把一个回收站根节点写进 `trash/`，并生成 manifest 条目。
  Future<TrashEntry> _writeRecycledRoot(
    NotePadNode root,
    Map<String, NotePadNode> recycledById,
    Map<String, String> activeFolderPaths,
  ) async {
    final fileName =
        FilenamePolicy.fileNameFor(root.title, isFolder: root.isFolder);
    final parentPath =
        root.parentId == null ? '' : (activeFolderPaths[root.parentId] ?? '');
    final originalPath =
        parentPath.isEmpty ? fileName : '$parentPath/$fileName';
    final itemDir = '${TrashManifestStore.itemsDir}/${root.id}';
    final trashPath = '$itemDir/$fileName';
    final target = '${TrashManifestStore.trashDir}/$trashPath';
    await _store.ensureDir(itemDir);
    if (root.isFolder) {
      await _store.ensureDir(target);
    } else {
      await _store.writeTextAtomic(target, root.content);
    }
    await _writeRecycledChildren(root, target, recycledById);
    return TrashEntry(
      id: root.id,
      kind: root.isFolder ? 'folder' : 'note',
      originalPath: originalPath,
      trashPath: trashPath,
      deletedAt: root.deletedAt ?? root.updatedAt,
      metadata: {'title': FilenamePolicy.titleOfPath(originalPath)},
    );
  }

  /// 递归写入回收站根节点下的子文件 / 子目录。
  Future<void> _writeRecycledChildren(
    NotePadNode root,
    String rootTarget,
    Map<String, NotePadNode> recycledById,
  ) async {
    final childrenByParent = <String, List<NotePadNode>>{};
    for (final node in recycledById.values) {
      final parentId = node.parentId;
      if (parentId == null) continue;
      childrenByParent.putIfAbsent(parentId, () => []).add(node);
    }

    Future<void> walk(NotePadNode parent, String relDir) async {
      final children = (childrenByParent[parent.id] ?? const <NotePadNode>[])
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      final used = <String>{};
      for (final child in children) {
        final unique = FilenamePolicy.uniqueTitle(
          FilenamePolicy.sanitizeTitle(child.title, isFolder: child.isFolder),
          used,
        );
        used.add(unique);
        final name = child.isFolder ? unique : '$unique.md';
        final path =
            relDir.isEmpty ? '$rootTarget/$name' : '$rootTarget/$relDir/$name';
        if (child.isFolder) {
          await _store.ensureDir(path);
          await walk(child, relDir.isEmpty ? unique : '$relDir/$unique');
        } else {
          await _store.writeTextAtomic(path, child.content);
        }
      }
    }

    await walk(root, '');
  }

  String _parentPathOf(
    NotePadNode node,
    Map<String, NotePadNode> byId,
    Map<String, String> idPath,
  ) {
    final parentId = node.parentId;
    if (parentId == null) return '';
    final path = idPath[parentId];
    if (path != null) return path;
    final parent = byId[parentId];
    if (parent == null || !parent.isFolder) return '';
    return idPath[parentId] ?? '';
  }

  int _depthOf(NotePadNode node, Map<String, NotePadNode> byId) {
    var depth = 0;
    var parentId = node.parentId;
    while (parentId != null && depth < 64) {
      final parent = byId[parentId];
      if (parent == null || !parent.isFolder) break;
      depth++;
      parentId = parent.parentId;
    }
    return depth;
  }

  @override
  Future<bool> hasUserContent() async {
    await _ensureInit();
    final entries = await _store.list('');
    for (final entry in entries) {
      if (!_isReservedPath(entry.path)) return true;
    }
    return false;
  }

  @override
  Future<void> close() async {}

  // ---- 内部工具 ----

  Future<NotePadNode> _nodeOf(
    VaultNodeRecord record, {
    required String? parentId,
    required bool preview,
  }) async {
    if (record.isFolder) {
      return record.toNode(parentId: parentId);
    }
    var body = '';
    try {
      body = await _store.readText(record.path);
    } catch (_) {
      body = '';
    }
    return record.toNode(
      content: preview ? _previewOf(body) : body,
      parentId: parentId,
    );
  }

  String? _parentIdOf(VaultNodeRecord record) {
    final parentPath = VaultTree.parentOf(record.path);
    if (parentPath.isEmpty) return null;
    return _tree.byPath(parentPath)?.id;
  }

  static String _previewOf(String body) {
    for (final line in body.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        return trimmed.length > 160 ? trimmed.substring(0, 160) : trimmed;
      }
    }
    return '';
  }

  static int _countWords(String text) {
    final cn = RegExp(r'[\u4e00-\u9fa5]').allMatches(text).length;
    final en = text
        .replaceAll(RegExp(r'[\u4e00-\u9fa5]'), ' ')
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;
    return cn + en;
  }
}

class _MovePlan {
  _MovePlan({
    required this.record,
    required this.oldPath,
    required this.newPath,
    required this.order,
  });

  final VaultNodeRecord record;
  final String oldPath;
  final String newPath;
  final int order;
}

class _TrashPlan {
  _TrashPlan({
    required this.record,
    required this.oldPath,
    required this.targetPath,
  });

  final VaultNodeRecord record;
  final String oldPath;
  final String targetPath;
}

class _RestorePlan {
  _RestorePlan({
    required this.source,
    required this.targetPath,
  });

  final String source;
  final String targetPath;
}
