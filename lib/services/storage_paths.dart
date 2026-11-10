import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'settings_service.dart';

/// 应用存储路径解析。
///
/// - vaultRoot：用户数据根（文档库）。Android 上可放在公共「文档/NotePad」，
///   其它平台沿用应用文档目录
/// - projectsRoot：文件阅读项目根（与 vault 同级隔离，始终在应用内部）
/// - appDataRoot：索引 / 备份 / 日志 / staging
/// - legacyDbPath：旧 SQLite 库路径（迁移只用）
class StoragePaths {
  const StoragePaths({
    required this.documentsRoot,
    required this.vaultRoot,
    required this.projectsRoot,
    required this.appDataRoot,
    required this.cacheRoot,
    this.location = StorageLocation.internal,
  });

  final String documentsRoot;
  final String vaultRoot;
  final String projectsRoot;
  final String appDataRoot;
  final String cacheRoot;
  final StorageLocation location;

  String get legacyDbPath => p.join(documentsRoot, 'app_database.db');

  /// 公共文档库目录名（Android：`/storage/emulated/0/Documents/NotePad`）。
  static const String publicFolderName = 'NotePad';

  /// 由 `getExternalStorageDirectory()` 的结果（形如
  /// `/storage/emulated/0/Android/data/<包名>/files`）推出公共存储根下的文档库目录。
  /// 不是应用专属外部目录时返回 null。
  static String? publicVaultRootFrom(String externalAppDir) {
    final normalized = externalAppDir.replaceAll('\\', '/');
    final index = normalized.indexOf('/Android/');
    if (index <= 0) return null;
    return '${normalized.substring(0, index)}/Documents/$publicFolderName';
  }

  /// 当前平台是否提供「公共文档」这一位置。
  static bool get documentsLocationAvailable =>
      !kIsWeb && Platform.isAndroid;

  /// 应用内部的文档库目录（旧版本与默认位置）。
  static Future<String> internalVaultRoot() async {
    final documents = await getApplicationDocumentsDirectory();
    return p.join(documents.path, 'Notepad');
  }

  /// 公共「文档/NotePad」目录；非 Android 或取不到外部存储时返回 null。
  static Future<String?> publicVaultRoot() async {
    if (!documentsLocationAvailable) return null;
    final external = await getExternalStorageDirectory();
    if (external == null) return null;
    return publicVaultRootFrom(external.path);
  }

  /// 解析路径。[location] 缺省取持久化设置（未设置视为应用内部）。
  ///
  /// 选了公共文档却取不到目录时回退到应用内部，并在日志里留痕；
  /// 授权是否仍有效由启动流程在这之前检查。
  static Future<StoragePaths> resolve({StorageLocation? location}) async {
    final settings = await SettingsService.instance;
    var chosen = location ?? settings.storageLocation ?? StorageLocation.internal;
    final documents = await getApplicationDocumentsDirectory();
    final support = await getApplicationSupportDirectory();
    final cache = await getTemporaryDirectory();

    String vaultRoot = p.join(documents.path, 'Notepad');
    if (chosen == StorageLocation.documents) {
      final publicRoot = await publicVaultRoot();
      if (publicRoot == null) {
        debugPrint('[StoragePaths] 公共文档目录不可用，回退应用内部');
        chosen = StorageLocation.internal;
      } else {
        vaultRoot = publicRoot;
      }
    }

    final paths = StoragePaths(
      documentsRoot: documents.path,
      vaultRoot: vaultRoot,
      projectsRoot: p.join(documents.path, 'NotePadProjects'),
      appDataRoot: p.join(support.path, 'Notepad'),
      cacheRoot: cache.path,
      location: chosen,
    );

    await Directory(paths.vaultRoot).create(recursive: true);
    await Directory(paths.projectsRoot).create(recursive: true);
    await Directory(paths.appDataRoot).create(recursive: true);
    return paths;
  }
}
