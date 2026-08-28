/// 椒盐笔记 —— 统一节点模型。
///
/// 参照原 Android 端「类文件管理器」的多层级结构设计：
/// 一个表同时承载「文件夹」和「文章」两种节点，通过 [isFolder] 区分。
/// [parentId] 为空表示位于根层级，支持无限嵌套。
class SaltNode {
  const SaltNode({
    required this.id,
    required this.isFolder,
    required this.title,
    required this.content,
    required this.parentId,
    required this.sortOrder,
    required this.isRecycled,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  /// 数据库主键（毫秒时间戳字符串，保证单调递增）。
  final String id;

  /// 是否为文件夹。文件夹无正文内容。
  final bool isFolder;

  /// 文件名 / 文件夹名。
  final String title;

  /// 正文（Markdown / 纯文本）。
  final String content;

  /// 父文件夹 id，null 表示根层级。
  final String? parentId;

  /// 排序权重（拖拽排序持久化依赖它）。
  final int sortOrder;

  /// 是否在回收站。
  final bool isRecycled;

  /// 创建时间（毫秒）。
  final int createdAt;

  /// 最近更新时间（毫秒）。
  final int updatedAt;

  /// 删除时间（进入回收站时间），null 表示未删除。
  final int? deletedAt;

  SaltNode copyWith({
    String? title,
    String? content,
    String? parentId,
    bool clearParentId = false,
    int? sortOrder,
    bool? isRecycled,
    int? updatedAt,
    int? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return SaltNode(
      id: id,
      isFolder: isFolder,
      title: title ?? this.title,
      content: content ?? this.content,
      parentId: clearParentId ? null : (parentId ?? this.parentId),
      sortOrder: sortOrder ?? this.sortOrder,
      isRecycled: isRecycled ?? this.isRecycled,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'is_folder': isFolder ? 1 : 0,
      'title': title,
      'content': content,
      'parent_id': parentId,
      'sort_order': sortOrder,
      'is_recycled': isRecycled ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'deleted_at': deletedAt,
    };
  }

  factory SaltNode.fromMap(Map<String, Object?> map) {
    return SaltNode(
      id: map['id'] as String,
      isFolder: (map['is_folder'] as int) == 1,
      title: (map['title'] as String?) ?? '',
      content: (map['content'] as String?) ?? '',
      parentId: map['parent_id'] as String?,
      sortOrder: (map['sort_order'] as int?) ?? 0,
      isRecycled: (map['is_recycled'] as int) == 1,
      createdAt: (map['created_at'] as int?) ?? 0,
      updatedAt: (map['updated_at'] as int?) ?? 0,
      deletedAt: map['deleted_at'] as int?,
    );
  }

  /// 文件夹是否为空（无任何子节点）——由调用方结合计数判断。
  bool get isRoot => parentId == null;

  SaltNode copy() => SaltNode(
        id: id,
        isFolder: isFolder,
        title: title,
        content: content,
        parentId: parentId,
        sortOrder: sortOrder,
        isRecycled: isRecycled,
        createdAt: createdAt,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
      );
}