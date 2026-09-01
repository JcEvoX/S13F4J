import 'package:flutter/foundation.dart';

import '../data/note_dao.dart';
import '../models/note.dart';

/// 全局数据状态管理。
///
/// 持有当前层级列表、选中集合、回收站列表等状态，并对用户操作
/// （新建、删除、恢复、排序、移动、搜索）进行分发的单一入口。
class NoteProvider extends ChangeNotifier {
  NoteProvider({NoteDao? dao}) : _dao = dao ?? NoteDao();

  final NoteDao _dao;

  /// 当前展示层级下的节点列表。
  List<NotePadNode> _nodes = [];
  List<NotePadNode> get nodes => _nodes;

  /// 当前层级父节点 id（null 为根层级）。
  String? _currentParentId;
  String? get currentParentId => _currentParentId;

  /// 当前是否处于多选模式。
  bool _selectionMode = false;
  bool get selectionMode => _selectionMode;

  /// 被选中的节点 id 集合。
  final Set<String> _selectedIds = {};
  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);

  /// 回收站顶层节点列表。
  List<NotePadNode> _recycleNodes = [];
  List<NotePadNode> get recycleNodes => _recycleNodes;

  /// 搜索结果缓存。
  List<NotePadNode> _searchResults = [];
  List<NotePadNode> get searchResults => _searchResults;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  /// 加载某个层级的内容。
  ///
  /// 使用 [try]/[finally] 确保加载完成后必定复位 loading 状态，
  /// 避免首次开库/建表失败时界面永久停留在「加载中」。
  Future<void> loadFolder(String? parentId) async {
    _currentParentId = parentId;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _nodes = await _dao.childrenOf(parentId: parentId);
    } catch (e) {
      _error = '$e';
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
    _nodes = await _dao.childrenOf(parentId: _currentParentId);
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
    return _dao.allFolders();
  }

  /// 新建节点（文件或文件夹）。
  Future<NotePadNode> createNode({
    required bool isFolder,
    required String title,
    String content = '',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final node = NotePadNode(
      id: now.toString(),
      isFolder: isFolder,
      title: title,
      content: content,
      parentId: _currentParentId,
      sortOrder: _nodes.length,
      isRecycled: false,
      createdAt: now,
      updatedAt: now,
    );
    await _dao.saveNode(node);
    await refresh();
    return node;
  }

  /// 更新节点内容（编辑时实时保存）。
  Future<void> updateNode(NotePadNode updated) async {
    final merged = updated.copyWith(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _dao.saveNode(merged);
    await refresh();
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
    await _dao.moveToRecycleBin(targets);
    exitSelection();
    await refresh();
    await loadRecycleBin();
  }

  Future<void> loadRecycleBin() async {
    _recycleNodes = await _dao.recycleBin();
    notifyListeners();
  }

  Future<void> restoreFromRecycle(List<NotePadNode> targets) async {
    await _dao.restoreNodes(targets);
    await loadRecycleBin();
  }

  Future<void> purgeFromRecycle(List<NotePadNode> targets) async {
    await _dao.deletePermanently(targets);
    await loadRecycleBin();
  }

  // ---- 排序 / 移动 ----

  /// 拖拽重排：更新子节点的 sort_order 并批量落库。
  Future<void> reorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final updated = List<NotePadNode>.from(_nodes);
    final moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);
    for (var i = 0; i < updated.length; i++) {
      updated[i] = updated[i].copyWith(sortOrder: i);
    }
    _nodes = updated;
    notifyListeners();
    await _dao.saveNodes(updated);
  }

  /// 将选中节点移动到目标层级。
  Future<void> moveSelectedTo(String? targetParentId) async {
    final ids = selectedNodes.map((n) => n.id).toList();
    await _dao.moveTo(ids, targetParentId);
    exitSelection();
    await refresh();
  }

  // ---- 搜索 ----

  Future<void> search(String keyword) async {
    if (keyword.trim().isEmpty) {
      _searchResults = [];
    } else {
      _searchResults = await _dao.search(keyword.trim());
    }
    notifyListeners();
  }

  Future<NotePadNode?> nodeById(String id) => _dao.nodeById(id);
}