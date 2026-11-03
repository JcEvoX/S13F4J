import '../core/storage/trash_policy.dart';
import '../models/note.dart';

/// 统一错误码（见架构文档第 9 节）。
class NotesException implements Exception {
  const NotesException(
    this.code,
    this.message, {
    this.detail,
    this.retryable = false,
  });

  final String code;
  final String message;
  final String? detail;
  final bool retryable;

  @override
  String toString() => '[$code] $message${detail == null ? '' : ' ($detail)'}';
}

/// 聚合回收站条目：携带来源命名空间，供按能力分组的 UI 使用。
class ScopedTrashEntry {
  const ScopedTrashEntry({
    required this.namespaceId,
    required this.displayName,
    required this.entry,
  });

  final String namespaceId;
  final String displayName;
  final TrashEntry entry;

  /// 转成列表卡片可用的节点。
  NotePadNode toNode() {
    final metadataTitle = entry.metadata['title'];
    final pathName = entry.originalPath.split('/').last;
    final title = (metadataTitle is String && metadataTitle.isNotEmpty)
        ? metadataTitle
        : pathName.replaceFirst(RegExp(r'\.md$'), '');
    return NotePadNode(
      id: entry.id,
      isFolder: entry.isFolder,
      title: title,
      content: '',
      parentId: null,
      sortOrder: 0,
      isRecycled: true,
      createdAt: entry.deletedAt,
      updatedAt: entry.deletedAt,
      deletedAt: entry.deletedAt,
    );
  }
}

/// 对外唯一数据接口。
///
/// 列表接口返回的节点默认不加载完整正文（[NotePadNode.content] 仅用于预览）；
/// 编辑器通过 [readBody] 取正文。
abstract class NotesRepository {
  Future<void> init();

  /// 单层列表；[folderId] 为 null 表示根层级。
  Future<List<NotePadNode>> childrenOf(String? folderId);

  Future<NotePadNode?> nodeById(String id);

  Future<String> readBody(String id);

  Future<void> writeBody(String id, String body);

  /// 正文外部指纹：文件实现返回 mtime，SQLite 返回 updatedAt。
  ///
  /// 编辑器在保存前 / 前台恢复时对比该指纹，用于发现「文件被外部程序改动」。
  Future<String> bodyFingerprint(String id);

  /// 新建节点，返回实际落盘后的节点。
  Future<NotePadNode> createNode({
    required bool isFolder,
    required String title,
    String? parentId,
    String content = '',
  });

  /// 标题即文件名；冲突自动加后缀。
  Future<void> rename(String id, String newTitle);

  Future<void> move(List<String> ids, String? targetFolderId);

  Future<void> reorder(String? folderId, List<String> orderedIds);

  Future<List<NotePadNode>> allFolders();

  Future<void> moveToTrash(List<String> ids);

  Future<List<ScopedTrashEntry>> listTrash();

  Future<void> restore(List<String> ids);

  Future<void> purge(List<String> ids);

  Future<List<NotePadNode>> search(String keyword);

  Future<List<NotePadNode>> recent({int limit = 50});

  Future<NoteStatistics> statistics();

  /// 全部节点（含回收站），用于旧 JSON 备份导出。
  Future<List<NotePadNode>> allNodes();

  /// 迁移 / 旧备份导入专用。
  Future<void> replaceAll(List<NotePadNode> nodes, {String? stagingDir});

  /// 是否已有用户内容（迁移前判断，避免覆盖）。
  Future<bool> hasUserContent();

  /// 从磁盘重建内部缓存（外部恢复快照后调用）。
  Future<void> reloadFromDisk();

  Future<void> close();
}
