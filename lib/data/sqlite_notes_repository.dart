import '../core/storage/trash_policy.dart';
import '../models/note.dart';
import 'app_database.dart';
import 'note_dao.dart';
import 'notes_repository.dart';

/// SQLite 过渡实现（行为基线）。
///
/// M0 阶段把 UI 与 [NoteDao] 解耦，后续可回退到该实现（backend=sqlite）。
class SqliteNotesRepository implements NotesRepository {
  SqliteNotesRepository({NoteDao? dao, this.namespaceId = 'notes'})
      : _dao = dao ?? NoteDao();

  final NoteDao _dao;
  final String namespaceId;
  int _idSeq = 0;

  @override
  Future<void> init() async {
    await AppDatabase.instance;
  }

  @override
  Future<List<NotePadNode>> childrenOf(String? folderId) =>
      _dao.childrenOf(parentId: folderId);

  @override
  Future<NotePadNode?> nodeById(String id) => _dao.nodeById(id);

  @override
  Future<String> readBody(String id) async {
    final node = await _dao.nodeById(id);
    if (node == null) {
      throw NotesException('E-NOT-FOUND', '文章不存在: $id');
    }
    return node.content;
  }

  @override
  Future<void> writeBody(String id, String body) async {
    final node = await _dao.nodeById(id);
    if (node == null) {
      throw NotesException('E-NOT-FOUND', '文章不存在: $id');
    }
    await _dao.saveNode(
      node.copyWith(
        content: body,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  @override
  Future<String> bodyFingerprint(String id) async {
    final node = await _dao.nodeById(id);
    if (node == null) {
      throw NotesException('E-NOT-FOUND', '文章不存在: $id');
    }
    return '${node.updatedAt}:${node.content.length}';
  }

  @override
  Future<NotePadNode> createNode({
    required bool isFolder,
    required String title,
    String? parentId,
    String content = '',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final siblings = await _dao.childrenOf(parentId: parentId);
    final node = NotePadNode(
      id: '$now-${_idSeq++}',
      isFolder: isFolder,
      title: title,
      content: content,
      parentId: parentId,
      sortOrder: siblings.length,
      isRecycled: false,
      createdAt: now,
      updatedAt: now,
    );
    await _dao.saveNode(node);
    return node;
  }

  @override
  Future<void> rename(String id, String newTitle) async {
    final node = await _dao.nodeById(id);
    if (node == null) {
      throw NotesException('E-NOT-FOUND', '节点不存在: $id');
    }
    await _dao.saveNode(
      node.copyWith(
        title: newTitle,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  @override
  Future<void> move(List<String> ids, String? targetFolderId) =>
      _dao.moveTo(ids, targetFolderId);

  @override
  Future<void> reorder(String? folderId, List<String> orderedIds) async {
    final children = await _dao.childrenOf(parentId: folderId);
    final byId = {for (final n in children) n.id: n};
    final updated = <NotePadNode>[];
    for (var i = 0; i < orderedIds.length; i++) {
      final node = byId[orderedIds[i]];
      if (node == null) {
        throw NotesException('E-VALIDATE', '排序包含非本层节点: ${orderedIds[i]}');
      }
      updated.add(node.copyWith(sortOrder: i));
    }
    for (final n in children) {
      if (!orderedIds.contains(n.id)) {
        updated.add(n.copyWith(sortOrder: orderedIds.length + n.sortOrder));
      }
    }
    await _dao.saveNodes(updated);
  }

  @override
  Future<List<NotePadNode>> allFolders() => _dao.allFolders();

  @override
  Future<void> moveToTrash(List<String> ids) async {
    final nodes = <NotePadNode>[];
    for (final id in ids) {
      final node = await _dao.nodeById(id);
      if (node != null) nodes.add(node);
    }
    if (nodes.isEmpty) return;
    await _dao.moveToRecycleBin(nodes);
  }

  @override
  Future<List<ScopedTrashEntry>> listTrash() async {
    final nodes = await _dao.recycleBin();
    return nodes.map((n) {
      return ScopedTrashEntry(
        namespaceId: namespaceId,
        displayName: '笔记',
        entry: TrashEntry(
          id: n.id,
          kind: n.isFolder ? 'folder' : 'note',
          originalPath: n.title,
          trashPath: '',
          deletedAt: n.deletedAt ?? n.updatedAt,
          metadata: {'title': n.title},
        ),
      );
    }).toList();
  }

  @override
  Future<void> restore(List<String> ids) async {
    final nodes = <NotePadNode>[];
    for (final id in ids) {
      final node = await _dao.nodeById(id);
      if (node != null) nodes.add(node);
    }
    if (nodes.isEmpty) return;
    await _dao.restoreNodes(nodes);
  }

  @override
  Future<void> purge(List<String> ids) async {
    final nodes = <NotePadNode>[];
    for (final id in ids) {
      final node = await _dao.nodeById(id);
      if (node != null) nodes.add(node);
    }
    if (nodes.isEmpty) return;
    await _dao.deletePermanently(nodes);
  }

  @override
  Future<List<NotePadNode>> search(String keyword) => _dao.search(keyword);

  @override
  Future<List<NotePadNode>> recent({int limit = 50}) =>
      _dao.recentArticles(limit: limit);

  @override
  Future<NoteStatistics> statistics() => _dao.statistics();

  @override
  Future<List<NotePadNode>> allNodes() => _dao.allNodes();

  @override
  Future<void> replaceAll(List<NotePadNode> nodes, {String? stagingDir}) =>
      _dao.replaceAll(nodes);

  @override
  Future<bool> hasUserContent() async => (await _dao.allNodes()).isNotEmpty;

  @override
  Future<void> reloadFromDisk() async {
    // SQLite 无外部文件变更，读取即为最新。
  }

  @override
  Future<void> close() async {}
}
