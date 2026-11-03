/// 回收站条目（宿主 `TrashCenter` 定义的 manifest 结构）。
class TrashEntry {
  const TrashEntry({
    required this.id,
    required this.kind,
    required this.originalPath,
    required this.trashPath,
    required this.deletedAt,
    this.metadata = const {},
  });

  /// 复用原节点 id。
  final String id;

  /// note / folder。
  final String kind;

  /// 删除前的相对路径（相对 nsRoot）。
  final String originalPath;

  /// 在 trash/ 内的相对路径（`items/<id>/...`）。
  final String trashPath;

  /// 删除时间（毫秒）。
  final int deletedAt;

  /// 能力补充的元数据（标题等），宿主原样存取。
  final Map<String, Object?> metadata;

  bool get isFolder => kind == 'folder';

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind,
        'originalPath': originalPath,
        'trashPath': trashPath,
        'deletedAt': deletedAt,
        'metadata': metadata,
      };

  factory TrashEntry.fromJson(Map<String, Object?> json) {
    return TrashEntry(
      id: (json['id'] as String?) ?? '',
      kind: (json['kind'] as String?) ?? 'note',
      originalPath: (json['originalPath'] as String?) ?? '',
      trashPath: (json['trashPath'] as String?) ?? '',
      deletedAt: (json['deletedAt'] as num?)?.toInt() ?? 0,
      metadata: (json['metadata'] as Map?)?.cast<String, Object?>() ?? const {},
    );
  }
}

/// 回收站策略钩子。
abstract class TrashPolicy {
  /// false 表示删除不可恢复（UI 需明确提示）。
  bool get enabled;

  /// 搬运前收集额外元数据。
  Future<Map<String, Object?>> metadataFor(String relativePath);

  /// 恢复成功后重建能力自己的派生数据。
  Future<void> afterRestore(List<TrashEntry> entries);
}
