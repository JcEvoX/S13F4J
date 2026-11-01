import '../../models/note.dart';

/// 备份策略钩子（能力提供，宿主执行打包 / 校验 / 落盘）。
abstract class BackupPolicy {
  /// 相对 nsRoot 的排除项；与宿主固定排除项取并集。
  List<String> get excludePatterns;

  /// 快照前静默写入、暂停后台任务。
  Future<void> quiesce();

  /// 快照结束（无论成功失败）后恢复。
  Future<void> resume();

  /// 恢复后重建索引 / 缓存 / 迁移标记。
  Future<void> afterRestore();

  /// 旧格式导入。
  Future<LegacyImportResult> importLegacy(LegacySource source);
}

/// 旧数据来源（SQLite 旧库 / 旧 JSON 备份）。
class LegacySource {
  const LegacySource({required this.kind, this.path, this.nodes});

  /// sqlite / json / directory。
  final String kind;
  final String? path;
  final List<NotePadNode>? nodes;
}

/// 旧数据导入结果。
class LegacyImportResult {
  const LegacyImportResult({
    required this.nodeCount,
    this.trashCount = 0,
    this.success = true,
    this.message,
  });

  final int nodeCount;
  final int trashCount;
  final bool success;
  final String? message;
}
