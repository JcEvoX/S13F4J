import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/storage/storage_capability.dart';
import '../data/vault/vault_store.dart';
import 'backup_center.dart';
import 'namespace_registry.dart';
import 'storage_paths.dart';

/// 文件阅读项目摘要（对应 `project.json`）。
class FileProject {
  const FileProject({
    required this.id,
    required this.displayName,
    required this.rootPath,
    required this.fileCount,
    required this.totalBytes,
    required this.importedAt,
    required this.updatedAt,
    required this.sourcePath,
    required this.skipped,
    required this.missing,
  });

  final String id;
  final String displayName;
  final String rootPath;
  final int fileCount;
  final int totalBytes;
  final int importedAt;
  final int updatedAt;
  final String sourcePath;
  final Map<String, int> skipped;

  /// 项目根不可用（被手动删除 / 外置盘拔出）。
  final bool missing;

  String get timeLabel {
    final dt = DateTime.fromMillisecondsSinceEpoch(importedAt);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  String get sizeLabel {
    if (totalBytes < 1024) return '$totalBytes B';
    if (totalBytes < 1024 * 1024) {
      return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(totalBytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  Map<String, Object?> toJson() => {
        'schema': 1,
        'projectId': id,
        'displayName': displayName,
        'mode': 'copy',
        'source': {'kind': 'directory', 'displayPath': sourcePath},
        'importedAt': importedAt,
        'updatedAt': updatedAt,
        'fileCount': fileCount,
        'totalBytes': totalBytes,
        'skipped': skipped,
      };

  factory FileProject.fromJson(
    Map<String, Object?> json, {
    required String rootPath,
    required bool missing,
  }) {
    final source = (json['source'] as Map?)?.cast<String, Object?>() ?? const {};
    return FileProject(
      id: (json['projectId'] as String?) ?? p.basename(rootPath),
      displayName: (json['displayName'] as String?) ??
          (json['projectId'] as String?) ??
          '',
      rootPath: rootPath,
      fileCount: (json['fileCount'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      importedAt: (json['importedAt'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      sourcePath: (source['displayPath'] as String?) ?? '',
      skipped:
          ((json['skipped'] as Map?)?.cast<String, Object?>() ?? const {})
              .map((key, value) => MapEntry(key, (value as num?)?.toInt() ?? 0)),
      missing: missing,
    );
  }
}

/// 项目导入 / 浏览内核（能力 `file.browser`）。
///
/// - 每个项目复制到 `projectsRoot/<projectId>/`，与笔记库隔离；
/// - 项目根内写 `.notepad/namespace.json` 与 `.notepad/project.json`；
/// - 注册为 `files.<projectId>` 命名空间，可单独备份 / 恢复；
/// - 文件级只读：不提供删除，移除项目需先快照（见 [removeProject]）。
class ProjectStore {
  ProjectStore._();

  static final ProjectStore instance = ProjectStore._();

  /// 单文件预览上限（5 MB），超出不载入内存。
  static const int maxPreviewBytes = 5 * 1024 * 1024;

  /// 复制时跳过的超大单文件（50 MB）。
  static const int maxImportFileBytes = 50 * 1024 * 1024;

  static const String metaDir = '.notepad';

  StoragePaths? _paths;

  Future<StoragePaths> _ensurePaths() async {
    return _paths ??= await StoragePaths.resolve();
  }

  /// 项目列表（按导入时间倒序）。
  Future<List<FileProject>> list() async {
    final paths = await _ensurePaths();
    final dir = Directory(paths.projectsRoot);
    if (!await dir.exists()) return const [];
    final projects = <FileProject>[];
    await for (final entity in dir.list()) {
      if (entity is! Directory) continue;
      final result = await _readProject(entity.path);
      if (result != null) projects.add(result);
    }
    projects.sort((a, b) => b.importedAt.compareTo(a.importedAt));
    await _ensureRegistered(projects);
    return projects;
  }

  /// 启动 / 列表加载时补登命名空间注册记录。
  Future<void> _ensureRegistered(List<FileProject> projects) async {
    if (projects.isEmpty) return;
    final paths = await _ensurePaths();
    final registry = NamespaceRegistry(store: VaultStore(paths.vaultRoot));
    await registry.load();
    for (final project in projects) {
      final id = 'files.${project.id}';
      if (await registry.resolve(id) != null) continue;
      await registry.register(
        NamespaceDescriptor(
          id: id,
          pluginId: 'builtin.files',
          root: project.rootPath,
          displayName: project.displayName,
          trashDriver: false,
          createdAt: project.importedAt,
        ),
      );
    }
  }

  Future<FileProject?> byId(String id) async {
    final paths = await _ensurePaths();
    final root = p.join(paths.projectsRoot, id);
    if (!await Directory(root).exists()) return null;
    return _readProject(root);
  }

  /// 扫描源目录（供导入前预览）。
  Future<ImportPreview> scan(String sourcePath) async {
    final result = await _walk(Directory(sourcePath), countOnly: true);
    return ImportPreview(
      displayName: p.basename(sourcePath),
      fileCount: result.fileCount,
      totalBytes: result.totalBytes,
      skipped: result.skipped,
    );
  }

  /// 从源目录导入为新项目（拷贝模式）。
  Future<FileProject> importDirectory(
    String sourcePath, {
    String? displayName,
  }) async {
    final paths = await _ensurePaths();
    final source = Directory(sourcePath);
    if (!await source.exists()) {
      throw const FileSystemException('源目录不存在或不可访问');
    }
    final id = 'p-${DateTime.now().millisecondsSinceEpoch}';
    final staging = Directory(
      p.join(paths.appDataRoot, 'staging', 'import-$id'),
    );
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    try {
      final result = await _walk(source, destination: staging);
      final target = Directory(p.join(paths.projectsRoot, id));
      if (await target.exists()) await target.delete(recursive: true);
      await staging.rename(target.path);
      final now = DateTime.now().millisecondsSinceEpoch;
      final project = FileProject(
        id: id,
        displayName: (displayName == null || displayName.trim().isEmpty)
            ? p.basename(sourcePath)
            : displayName.trim(),
        rootPath: target.path,
        fileCount: result.fileCount,
        totalBytes: result.totalBytes,
        importedAt: now,
        updatedAt: now,
        sourcePath: sourcePath,
        skipped: result.skipped,
        missing: false,
      );
      await _writeMeta(project);
      await _register(project);
      debugPrint(
        '[ProjectStore] 导入完成 $id: ${result.fileCount} 个文件, '
        '${result.totalBytes} 字节, 跳过 ${result.skipped}',
      );
      return project;
    } catch (e) {
      if (await staging.exists()) {
        try {
          await staging.delete(recursive: true);
        } catch (_) {
          // 清理失败不覆盖原始错误。
        }
      }
      rethrow;
    }
  }

  /// 用同一来源重新导入并覆盖项目内容（保留项目 id 与显示名）。
  Future<FileProject> updateProject(String id, String sourcePath) async {
    final paths = await _ensurePaths();
    final existing = await byId(id);
    if (existing == null) {
      throw FileSystemException('项目不存在: $id');
    }
    final source = Directory(sourcePath);
    if (!await source.exists()) {
      throw const FileSystemException('源目录不存在或不可访问');
    }
    final staging = Directory(
      p.join(paths.appDataRoot, 'staging', 'update-$id'),
    );
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    try {
      final result = await _walk(source, destination: staging);
      final target = Directory(p.join(paths.projectsRoot, id));
      if (await target.exists()) await target.delete(recursive: true);
      await staging.rename(target.path);
      final now = DateTime.now().millisecondsSinceEpoch;
      final project = FileProject(
        id: id,
        displayName: existing.displayName,
        rootPath: target.path,
        fileCount: result.fileCount,
        totalBytes: result.totalBytes,
        importedAt: existing.importedAt,
        updatedAt: now,
        sourcePath: sourcePath,
        skipped: result.skipped,
        missing: false,
      );
      await _writeMeta(project);
      return project;
    } catch (e) {
      if (await staging.exists()) {
        try {
          await staging.delete(recursive: true);
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// 移除项目：先快照（若可用），再删除目录并移除注册记录。
  Future<void> removeProject(String id, {bool snapshotFirst = true}) async {
    final paths = await _ensurePaths();
    final project = await byId(id);
    if (project == null) return;
    if (snapshotFirst && !project.missing) {
      try {
        await BackupCenter.instance.snapshotNamespace(
          namespaceId: 'files.$id',
          displayName: project.displayName,
          rootPath: project.rootPath,
        );
      } catch (e) {
        debugPrint('[ProjectStore] 移除前快照失败（继续移除）: $e');
      }
    }
    if (!project.missing) {
      final dir = Directory(project.rootPath);
      if (await dir.exists()) await dir.delete(recursive: true);
    }
    final registry = NamespaceRegistry(
      store: VaultStore(paths.vaultRoot),
    );
    await registry.load();
    await registry.forget('files.$id');
    debugPrint('[ProjectStore] 已移除项目 $id');
  }

  /// 列出项目某一层目录（文件夹优先，自然排序）。
  Future<List<ProjectEntry>> childrenOf(FileProject project, String relDir) async {
    if (project.missing) return const [];
    final root = p.join(project.rootPath, relDir);
    final dir = Directory(root);
    if (!await dir.exists()) return const [];
    final entries = <ProjectEntry>[];
    await for (final entity in dir.list()) {
      final name = p.basename(entity.path);
      if (name == metaDir) continue;
      final rel = relDir.isEmpty ? name : '$relDir/$name';
      try {
        final stat = await entity.stat();
        entries.add(
          ProjectEntry(
            name: name,
            relPath: rel,
            isFolder: entity is Directory,
            size: entity is File ? stat.size : 0,
            modifiedAt: stat.modified.millisecondsSinceEpoch,
          ),
        );
      } catch (_) {
        // 无权限 / 已删除的条目直接跳过。
      }
    }
    entries.sort((a, b) {
      if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  /// 读取项目内文件为只读文本。
  ///
  /// 返回结果区分「过大」「二进制」「读取失败」，供 UI 给出明确文案。
  Future<ReadOnlyResult> readFile(FileProject project, String relPath) async {
    final file = File(p.join(project.rootPath, relPath));
    if (!await file.exists()) {
      return const ReadOnlyResult(error: '文件已不可用，可能已被外部删除或移动。');
    }
    final size = await file.length();
    if (size > maxPreviewBytes) {
      return ReadOnlyResult(
        error: '文件过大（${(size / 1024 / 1024).toStringAsFixed(1)} MB），'
            '暂不支持预览。',
      );
    }
    if (!_looksTextual(file.path)) {
      return const ReadOnlyResult(error: '暂不支持预览二进制文件。');
    }
    try {
      final text = await file.readAsString();
      return ReadOnlyResult(text: text, size: size);
    } catch (e) {
      return ReadOnlyResult(error: '读取失败：$e');
    }
  }

  /// 读取单个外部文件（不落盘、不注册命名空间）。
  Future<ReadOnlyResult> readExternalFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return const ReadOnlyResult(error: '文件已不可用。');
    }
    return readFile(
      FileProject(
        id: '',
        displayName: p.basename(path),
        rootPath: p.dirname(path),
        fileCount: 0,
        totalBytes: 0,
        importedAt: 0,
        updatedAt: 0,
        sourcePath: path,
        skipped: const {},
        missing: false,
      ),
      p.basename(path),
    );
  }

  static bool _looksTextual(String path) {
    final ext = p.extension(path).toLowerCase();
    const textual = {
      '.md', '.markdown', '.txt', '.json', '.yaml', '.yml', '.dart', '.js',
      '.ts', '.py', '.java', '.kt', '.html', '.css', '.sh', '.xml', '.csv',
      '.log', '.ini', '.toml', '.gradle', '.properties', '.sql', '.c', '.h',
      '.cpp', '.rs', '.go', '.swift', '.m', '.mm', '.rb', '.php', '.lua',
    };
    return textual.contains(ext) || ext.isEmpty;
  }

  Future<FileProject?> _readProject(String rootPath) async {
    final metaFile = File(p.join(rootPath, metaDir, 'project.json'));
    Map<String, Object?> json = const {};
    if (await metaFile.exists()) {
      try {
        final decoded = jsonDecode(await metaFile.readAsString());
        if (decoded is Map) json = decoded.cast<String, Object?>();
      } catch (e) {
        debugPrint('[ProjectStore] project.json 解析失败 $rootPath: $e');
      }
    }
    final missing = !await Directory(rootPath).exists();
    final id = (json['projectId'] as String?) ?? p.basename(rootPath);
    if (json.isEmpty && missing) return null;
    if (json.isEmpty) {
      // 兼容手工放置的目录：按目录名补一份最小 metadata。
      json = {
        'projectId': id,
        'displayName': id,
        'importedAt': 0,
      };
    }
    return FileProject.fromJson(
      json,
      rootPath: rootPath,
      missing: missing,
    );
  }

  Future<void> _writeMeta(FileProject project) async {
    final dir = Directory(p.join(project.rootPath, metaDir));
    await dir.create(recursive: true);
    await File(p.join(dir.path, 'namespace.json')).writeAsString(
      jsonEncode({
        'schema': 1,
        'namespaceId': 'files.${project.id}',
        'pluginId': 'builtin.files',
        'createdAt': project.importedAt,
      }),
      flush: true,
    );
    await File(p.join(dir.path, 'project.json')).writeAsString(
      jsonEncode(project.toJson()),
      flush: true,
    );
  }

  Future<void> _register(FileProject project) async {
    final paths = await _ensurePaths();
    final registry = NamespaceRegistry(
      store: VaultStore(paths.vaultRoot),
    );
    await registry.load();
    await registry.register(
      NamespaceDescriptor(
        id: 'files.${project.id}',
        pluginId: 'builtin.files',
        root: project.rootPath,
        displayName: project.displayName,
        trashDriver: false,
        createdAt: project.importedAt,
      ),
    );
  }

  Future<_WalkResult> _walk(
    Directory source, {
    Directory? destination,
    bool countOnly = false,
  }) async {
    var fileCount = 0;
    var totalBytes = 0;
    final skipped = <String, int>{'symlinks': 0, 'oversize': 0, 'unsupported': 0};

    Future<void> visit(Directory dir, String rel) async {
      await for (final entity in dir.list(followLinks: false)) {
        final name = p.basename(entity.path);
        if (name == metaDir) {
          skipped['unsupported'] = (skipped['unsupported'] ?? 0) + 1;
          continue;
        }
        if (entity is Link) {
          skipped['symlinks'] = (skipped['symlinks'] ?? 0) + 1;
          continue;
        }
        final childRel = rel.isEmpty ? name : '$rel/$name';
        if (entity is Directory) {
          if (!countOnly) {
            await Directory(p.join(destination!.path, childRel))
                .create(recursive: true);
          }
          await visit(entity, childRel);
          continue;
        }
        if (entity is! File) {
          skipped['unsupported'] = (skipped['unsupported'] ?? 0) + 1;
          continue;
        }
        try {
          final size = await entity.length();
          if (size > maxImportFileBytes) {
            skipped['oversize'] = (skipped['oversize'] ?? 0) + 1;
            continue;
          }
          fileCount++;
          totalBytes += size;
          if (!countOnly) {
            final out = File(p.join(destination!.path, childRel));
            await out.parent.create(recursive: true);
            await entity.copy(out.path);
          }
        } catch (_) {
          skipped['unsupported'] = (skipped['unsupported'] ?? 0) + 1;
        }
      }
    }

    await visit(source, '');
    return _WalkResult(fileCount: fileCount, totalBytes: totalBytes, skipped: skipped);
  }
}

class _WalkResult {
  const _WalkResult({
    required this.fileCount,
    required this.totalBytes,
    required this.skipped,
  });

  final int fileCount;
  final int totalBytes;
  final Map<String, int> skipped;
}

/// 项目内条目（只在浏览时使用，不建索引）。
class ProjectEntry {
  const ProjectEntry({
    required this.name,
    required this.relPath,
    required this.isFolder,
    required this.size,
    required this.modifiedAt,
  });

  final String name;
  final String relPath;
  final bool isFolder;
  final int size;
  final int modifiedAt;
}

/// 导入前扫描结果。
class ImportPreview {
  const ImportPreview({
    required this.displayName,
    required this.fileCount,
    required this.totalBytes,
    required this.skipped,
  });

  final String displayName;
  final int fileCount;
  final int totalBytes;
  final Map<String, int> skipped;

  String get sizeLabel {
    if (totalBytes < 1024) return '$totalBytes B';
    if (totalBytes < 1024 * 1024) {
      return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(totalBytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

/// 只读加载结果：文本或可读错误。
class ReadOnlyResult {
  const ReadOnlyResult({this.text, this.size = 0, this.error});

  final String? text;
  final int size;
  final String? error;

  bool get ok => error == null;
}
