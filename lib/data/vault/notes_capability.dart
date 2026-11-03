import '../../core/storage/backup_policy.dart';
import '../../core/storage/storage_capability.dart';
import '../../core/storage/trash_policy.dart';
import '../notes_repository.dart';
import 'filename_policy.dart';

/// notes 能力的回收站策略（宿主执行搬运，能力只声明元数据）。
class NotesTrashPolicy implements TrashPolicy {
  @override
  bool get enabled => true;

  @override
  Future<Map<String, Object?>> metadataFor(String relativePath) async {
    return {'title': FilenamePolicy.titleOfPath(relativePath)};
  }

  @override
  Future<void> afterRestore(List<TrashEntry> entries) async {
    // 派生索引按需重建；恢复后无需额外动作。
  }
}

/// notes 能力的备份策略。
class NotesBackupPolicy implements BackupPolicy {
  NotesBackupPolicy(this._repository);

  final NotesRepository _repository;

  @override
  List<String> get excludePatterns => const [
        '.notepad/index',
        '.notepad/backups',
        '.notepad/logs',
        '.notepad/staging',
      ];

  @override
  Future<void> quiesce() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> afterRestore() async {}

  @override
  Future<LegacyImportResult> importLegacy(LegacySource source) async {
    final nodes = source.nodes;
    if (nodes == null) {
      return const LegacyImportResult(
        nodeCount: 0,
        success: false,
        message: '缺少可导入节点',
      );
    }
    await _repository.replaceAll(nodes, stagingDir: source.path);
    return LegacyImportResult(nodeCount: nodes.length);
  }
}

/// notes 能力描述（注册表条目 + 策略）。
class NotesStorageCapability implements StorageCapability {
  NotesStorageCapability(this._repository);

  final NotesRepository _repository;

  @override
  String get namespaceId => 'notes';

  @override
  String get pluginId => 'builtin.notes';

  @override
  NamespaceDescriptor get descriptor => NamespaceDescriptor(
        id: namespaceId,
        pluginId: pluginId,
        root: '',
        displayName: '笔记',
        createdAt: 0,
      );

  @override
  BackupPolicy get backupPolicy => NotesBackupPolicy(_repository);

  @override
  TrashPolicy get trashPolicy => NotesTrashPolicy();
}
