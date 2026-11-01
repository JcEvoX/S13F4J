import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 应用存储路径解析。
///
/// - vaultRoot：用户数据根（文档库）
/// - projectsRoot：文件阅读项目根（与 vault 同级隔离）
/// - appDataRoot：索引 / 备份 / 日志 / staging
/// - legacyDbPath：旧 SQLite 库路径（迁移只用）
class StoragePaths {
  const StoragePaths({
    required this.documentsRoot,
    required this.vaultRoot,
    required this.projectsRoot,
    required this.appDataRoot,
    required this.cacheRoot,
  });

  final String documentsRoot;
  final String vaultRoot;
  final String projectsRoot;
  final String appDataRoot;
  final String cacheRoot;

  String get legacyDbPath =>
      p.join(documentsRoot, 'app_database.db');

  static Future<StoragePaths> resolve() async {
    final documents = await getApplicationDocumentsDirectory();
    final support = await getApplicationSupportDirectory();
    final cache = await getTemporaryDirectory();

    final paths = StoragePaths(
      documentsRoot: documents.path,
      vaultRoot: p.join(documents.path, 'Notepad'),
      projectsRoot: p.join(documents.path, 'NotePadProjects'),
      appDataRoot: p.join(support.path, 'Notepad'),
      cacheRoot: cache.path,
    );

    await Directory(paths.vaultRoot).create(recursive: true);
    await Directory(paths.projectsRoot).create(recursive: true);
    await Directory(paths.appDataRoot).create(recursive: true);
    return paths;
  }
}
