import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/notes_repository.dart';
import '../data/sqlite_notes_repository.dart';
import '../models/note.dart';

/// 全局数据状态管理。
///
/// 页面只依赖本 Provider；底层经 [NotesRepository] 屏蔽 sqlite / 文件实现。
class NoteProvider extends ChangeNotifier {
  NoteProvider({NotesRepository? repository})
      : _repo = repository ?? SqliteNotesRepository();

  final NotesRepository _repo;
  bool _ready = false;

  Future<void> _ensureReady() async {
    if (_ready) return;
    await _repo.init();
    _ready = true;
  }

  /// 当前展示层级下的节点列表。
  List<NotePadNode> _nodes = [];
  List<NotePadNode> get nodes => _nodes;

  /// 当前层级父节点 id（null 为根层级）。
  String? _currentParentId;
  String? get currentParentId => _currentParentId;

  /// 当前文件夹标题（用于顶部栏回显；根层级为 null）。
  String? _currentFolderTitle;
  String? get currentFolderTitle => _currentFolderTitle;

  /// 当前是否处于多选模式。
  bool _selectionMode = false;
  bool get selectionMode => _selectionMode;

  /// 被选中的节点 id 集合。
  final Set<String> _selectedIds = {};
  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);

  /// 回收站顶层节点列表。
  List<NotePadNode> _recycleNodes = [];
  List<NotePadNode> get recycleNodes => _recycleNodes;

  /// 回收站聚合条目（带命名空间来源，供按能力分组使用）。
  List<ScopedTrashEntry> _recycleEntries = [];
  List<ScopedTrashEntry> get recycleEntries => _recycleEntries;

  /// 搜索结果缓存。
  List<NotePadNode> _searchResults = [];
  List<NotePadNode> get searchResults => _searchResults;

  /// 当前正在编辑的文章 id（编辑器打开时写入，供首页「定位」使用）。
  String? _currentEditingNodeId;
  String? get currentEditingNodeId => _currentEditingNodeId;

  static const _kLastEditedNodeId = 'note.lastEditedNodeId';

  /// 最后一次编辑（打开 / 保存）的文章 id，持久化。
  ///
  /// 编辑器关闭后 [currentEditingNodeId] 会清空，「定位正在编辑的文章」靠它
  /// 找回最近编辑的那一篇，重启应用后依然有效。
  String? _lastEditedNodeId;
  bool _lastEditedLoaded = false;

  Future<String?> lastEditedNodeId() async {
    if (!_lastEditedLoaded) {
      _lastEditedLoaded = true;
      try {
        final prefs = await SharedPreferences.getInstance();
        _lastEditedNodeId ??= prefs.getString(_kLastEditedNodeId);
      } catch (e) {
        debugPrint('[NoteProvider] 读取最后编辑文章失败: $e');
      }
    }
    return _lastEditedNodeId;
  }

  /// 记录最后编辑的文章（不触发界面刷新）。
  Future<void> markEdited(String id) async {
    if (_lastEditedNodeId == id && _lastEditedLoaded) return;
    _lastEditedNodeId = id;
    _lastEditedLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastEditedNodeId, id);
    } catch (e) {
      debugPrint('[NoteProvider] 保存最后编辑文章失败: $e');
    }
  }

  /// 「定位」的目标：正在编辑的优先，其次是最后一次编辑的。
  Future<String?> locateTargetId() async =>
      _currentEditingNodeId ?? await lastEditedNodeId();

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// 记录当前正在编辑的文章（编辑器页打开/关闭时调用）。
  void setCurrentEditingNodeId(String? id) {
    if (_disposed || _currentEditingNodeId == id) return;
    _currentEditingNodeId = id;
    debugPrint('[NoteProvider] 当前编辑文章: $id');
    notifyListeners();
  }

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  /// 加载某个层级的内容。
  Future<void> loadFolder(String? parentId) async {
    debugPrint('[NoteProvider] loadFolder: 层级=$parentId');
    _currentParentId = parentId;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await _ensureReady();
      if (parentId == null) {
        _currentFolderTitle = null;
      } else {
        _currentFolderTitle = (await _repo.nodeById(parentId))?.title ?? '';
      }
      _nodes = await _repo.childrenOf(parentId);
      debugPrint('[NoteProvider] loadFolder 完成: 层级=$parentId, 节点=${_nodes.length}');
    } catch (e) {
      _error = '$e';
      debugPrint('[NoteProvider] loadFolder 失败: $e');
    } finally {
      exitSelection();
      _loading = false;
      notifyListeners();
    }
  }

  /// 记录返回栈，用于「返回上层」。
  final List<String?> _backStack = [];

  void pushCurrent() {
    _backStack.add(_currentParentId);
  }

  Future<void> refresh() async {
    await _ensureReady();
    _nodes = await _repo.childrenOf(_currentParentId);
    debugPrint('[NoteProvider] refresh: 层级=$_currentParentId, 节点=${_nodes.length}');
    notifyListeners();
  }

  /// 返回上一层。返回值为是否成功返回（无栈则无操作）。
  Future<bool> navigateUp() async {
    if (_backStack.isEmpty) return false;
    final target = _backStack.removeLast();
    await loadFolder(target);
    return true;
  }

  /// 进入某子文件夹（记录返回栈）。
  Future<void> openFolder(NotePadNode folder) async {
    pushCurrent();
    await loadFolder(folder.id);
  }

  /// 获取全部未回收文件夹（用于移动定位）。
  Future<List<NotePadNode>> allFolders() async {
    await _ensureReady();
    return _repo.allFolders();
  }

  /// 新建节点（文件或文件夹）。
  Future<NotePadNode> createNode({
    required bool isFolder,
    required String title,
    String content = '',
  }) async {
    debugPrint('[NoteProvider] createNode: isFolder=$isFolder, title=$title, parentId=$_currentParentId');
    await _ensureReady();
    final node = await _repo.createNode(
      isFolder: isFolder,
      title: title,
      parentId: _currentParentId,
      content: content,
    );
    await refresh();
    debugPrint('[NoteProvider] createNode 完成: id=${node.id}, title=${node.title}');
    return node;
  }

  /// 重命名节点（标题即文件名）。
  Future<void> renameNode(String id, String newTitle) async {
    debugPrint('[NoteProvider] renameNode: id=$id, title=$newTitle');
    await _ensureReady();
    await _repo.rename(id, newTitle);
    await refresh();
  }

  /// 保存文章正文。
  Future<void> saveBody(String id, String body) async {
    debugPrint('[NoteProvider] saveBody: id=$id, 长度=${body.length}');
    await _ensureReady();
    await _repo.writeBody(id, body);
    _syncSavedNode(id, body);
  }

  /// 读取正文（编辑器懒加载）。
  Future<String> readBody(String id) async {
    await _ensureReady();
    return _repo.readBody(id);
  }

  /// 正文指纹：用于检测文件被外部程序修改。
  Future<String> bodyFingerprint(String id) async {
    await _ensureReady();
    return _repo.bodyFingerprint(id);
  }

  /// 保存后同步内存快照，避免首页 / 搜索结果 / 回收站仍显示旧预览与旧时间。
  void _syncSavedNode(String id, String body) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final preview = _previewOf(body);
    var changed = false;

    void replaceIn(List<NotePadNode> list) {
      final index = list.indexWhere((n) => n.id == id);
      if (index >= 0) {
        list[index] = list[index].copyWith(content: preview, updatedAt: now);
        changed = true;
      }
    }

    replaceIn(_nodes);
    replaceIn(_searchResults);
    replaceIn(_recycleNodes);
    if (changed) notifyListeners();
  }

  /// 卡片副文本：取首个非空行，最多 160 字符。
  static String _previewOf(String text) {
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      return trimmed.length > 160 ? trimmed.substring(0, 160) : trimmed;
    }
    return '';
  }

  // ---- 选中 / 多选 ----

  void enterSelection(NotePadNode node) {
    _selectionMode = true;
    _selectedIds.clear();
    _selectedIds.add(node.id);
    notifyListeners();
  }

  void toggleSelection(String id) {
    if (_selectedIds.contains(id)) {
      _selectedIds.remove(id);
    } else {
      _selectedIds.add(id);
    }
    if (_selectedIds.isEmpty) {
      _selectionMode = false;
    }
    notifyListeners();
  }

  void enterFullSelection() {
    if (_nodes.isEmpty) return;
    _selectionMode = true;
    for (final n in _nodes) {
      _selectedIds.add(n.id);
    }
    notifyListeners();
  }

  void exitSelection() {
    _selectionMode = false;
    _selectedIds.clear();
    notifyListeners();
  }

  /// 当前被选中的节点对象列表。
  List<NotePadNode> get selectedNodes =>
      _nodes.where((n) => _selectedIds.contains(n.id)).toList();

  // ---- 删除 / 回收站 ----

  /// 将选中（或给定）节点移入回收站。
  Future<void> deleteToRecycle(List<NotePadNode> targets) async {
    debugPrint('[NoteProvider] deleteToRecycle: ids=${targets.map((n) => n.id).toList()}');
    await _ensureReady();
    await _repo.moveToTrash(targets.map((n) => n.id).toList());
    exitSelection();
    await refresh();
    await loadRecycleBin();
    debugPrint('[NoteProvider] deleteToRecycle 完成');
  }

  Future<void> loadRecycleBin() async {
    await _ensureReady();
    _recycleEntries = await _repo.listTrash();
    _recycleNodes = _recycleEntries.map((e) => e.toNode()).toList();
    debugPrint('[NoteProvider] loadRecycleBin: ${_recycleNodes.length} 项');
    notifyListeners();
  }

  Future<void> restoreFromRecycle(List<NotePadNode> targets) async {
    debugPrint('[NoteProvider] restoreFromRecycle: ids=${targets.map((n) => n.id).toList()}');
    await _ensureReady();
    await _repo.restore(targets.map((n) => n.id).toList());
    await loadRecycleBin();
    // 恢复的节点可能回到当前层级，刷新当前列表以免首页仍看不到。
    await refresh();
    debugPrint('[NoteProvider] restoreFromRecycle 完成');
  }

  Future<void> purgeFromRecycle(List<NotePadNode> targets) async {
    debugPrint('[NoteProvider] purgeFromRecycle: ids=${targets.map((n) => n.id).toList()}');
    await _ensureReady();
    await _repo.purge(targets.map((n) => n.id).toList());
    await loadRecycleBin();
    debugPrint('[NoteProvider] purgeFromRecycle 完成');
  }

  // ---- 排序 / 移动 ----

  /// 拖拽重排。
  Future<void> reorder(int oldIndex, int newIndex) async {
    debugPrint('[NoteProvider] reorder: $oldIndex -> $newIndex');
    final updated = List<NotePadNode>.from(_nodes);
    final moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);
    for (var i = 0; i < updated.length; i++) {
      updated[i] = updated[i].copyWith(sortOrder: i);
    }
    _nodes = updated;
    notifyListeners();
    await _ensureReady();
    await _repo.reorder(
      _currentParentId,
      updated.map((n) => n.id).toList(),
    );
    debugPrint('[NoteProvider] reorder 完成');
  }

  /// 将选中节点移动到目标层级。
  Future<void> moveSelectedTo(String? targetParentId) async {
    final ids = selectedNodes.map((n) => n.id).toList();
    debugPrint('[NoteProvider] moveSelectedTo: ids=$ids, 目标=$targetParentId');
    await _ensureReady();
    await _repo.move(ids, targetParentId);
    exitSelection();
    await refresh();
    debugPrint('[NoteProvider] moveSelectedTo 完成，当前父节点=$_currentParentId');
  }

  // ---- 搜索 / 最近 / 统计 ----

  Future<void> search(String keyword) async {
    debugPrint('[NoteProvider] search: "$keyword"');
    await _ensureReady();
    if (keyword.trim().isEmpty) {
      _searchResults = [];
    } else {
      _searchResults = await _repo.search(keyword.trim());
    }
    debugPrint('[NoteProvider] search 结果: ${_searchResults.length} 条');
    notifyListeners();
  }

  Future<NotePadNode?> nodeById(String id) async {
    await _ensureReady();
    return _repo.nodeById(id);
  }

  Future<List<NotePadNode>> recent({int limit = 50}) async {
    await _ensureReady();
    return _repo.recent(limit: limit);
  }

  Future<NoteStatistics> statistics() async {
    await _ensureReady();
    return _repo.statistics();
  }

  /// 全部节点（含回收站），用于旧 JSON 备份。
  Future<List<NotePadNode>> allNodes() async {
    await _ensureReady();
    return _repo.allNodes();
  }

  /// 旧 JSON 备份恢复（覆盖当前数据）。
  Future<void> replaceAll(List<NotePadNode> nodes) async {
    await _ensureReady();
    await _repo.replaceAll(nodes);
    await refresh();
    await loadRecycleBin();
  }

  /// 从磁盘重建缓存（外部恢复命名空间快照后调用）。
  Future<void> reloadFromDisk() async {
    await _ensureReady();
    await _repo.reloadFromDisk();
    await refresh();
    await loadRecycleBin();
    debugPrint('[NoteProvider] 已从磁盘重建数据');
  }

  /// 定位到指定节点：沿父链向上逐层进入，直到其所在层级成为当前列表。
  Future<int?> navigateToNode(String nodeId) async {
    debugPrint('[NoteProvider] navigateToNode: $nodeId');
    await _ensureReady();
    final node = await _repo.nodeById(nodeId);
    if (node == null || node.isRecycled) {
      debugPrint('[NoteProvider] navigateToNode 失败：节点不存在或已回收');
      return null;
    }
    final ancestors = <String?>[];
    String? parent = node.parentId;
    while (parent != null) {
      ancestors.add(parent);
      final p = await _repo.nodeById(parent);
      parent = p?.parentId;
    }
    for (final folderId in ancestors.reversed) {
      await loadFolder(folderId);
    }
    final index = _nodes.indexWhere((n) => n.id == nodeId);
    debugPrint('[NoteProvider] navigateToNode 完成，index=$index');
    return index >= 0 ? index : null;
  }
}
