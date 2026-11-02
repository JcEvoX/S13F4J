import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/storage/storage_capability.dart';
import '../data/vault/vault_store.dart';
import 'namespace_registry.dart';
import 'storage_paths.dart';

/// 命名空间快照来源。
class NamespaceSource {
  const NamespaceSource({
    required this.id,
    required this.displayName,
    required this.rootPath,
  });

  final String id;
  final String displayName;
  final String rootPath;
}

/// 一个备份快照（zip：manifest.json + data/...）。
class BackupSnapshot {
  const BackupSnapshot({
    required this.namespaceId,
    required this.displayName,
    required this.path,
    required this.createdAt,
    required this.fileCount,
    required this.totalBytes,
    required this.appWide,
  });

  final String namespaceId;
  final String displayName;
  final String path;
  final int createdAt;
  final int fileCount;
  final int totalBytes;
  final bool appWide;

  String get fileName => p.basename(path);

  String get timeLabel {
    final dt = DateTime.fromMillisecondsSinceEpoch(createdAt);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }
}

/// 备份中心：按命名空间生成 / 列出 / 恢复 / 删除快照。
///
/// 容器格式由宿主定义（manifest + sha256 校验），即使插件停用，
/// 仍可通过本服务解读与恢复命名空间数据。
class BackupCenter {
  BackupCenter._();

  static final BackupCenter instance = BackupCenter._();

  static const int schema = 1;
  static const String manifestName = 'manifest.json';
  static const String _stagingDir = 'staging';

  StoragePaths? _paths;
  Future<void> _guard = Future<void>.value();

  Future<StoragePaths> _ensurePaths() async {
    return _paths ??= await StoragePaths.resolve();
  }

  /// 串行化快照 / 恢复，避免并发写入同一命名空间。
  Future<T> _locked<T>(Future<T> Function() action) {
    final completer = _guard.then((_) => action());
    _guard = completer.then((_) {}, onError: (_) {});
    return completer;
  }

  /// 快照存放目录：`<appDataRoot>/namespaces/<nsId>/backups`。
  Future<String> backupDir(String namespaceId) async {
    final paths = await _ensurePaths();
    return p.join(paths.appDataRoot, 'namespaces', namespaceId, 'backups');
  }

  /// 已注册的命名空间来源（即使插件停用也保留，可继续备份 / 恢复）。
  Future<List<NamespaceSource>> namespaceSources() async {
    final paths = await _ensurePaths();
    final registry = NamespaceRegistry(store: VaultStore(paths.vaultRoot));
    await registry.load();
    var list = await registry.all();
    if (list.isEmpty) {
      list = [
        NamespaceDescriptor(
          id: 'notes',
          pluginId: 'builtin.notes',
          displayName: '笔记',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ];
    }
    return [
      for (final item in list)
        NamespaceSource(
          id: item.id,
          displayName: item.displayName.isEmpty ? item.id : item.displayName,
          rootPath: item.root.isEmpty
              ? paths.vaultRoot
              : p.join(paths.vaultRoot, item.root),
        ),
    ];
  }

  /// 命名空间目录占用字节数。
  Future<int> usageBytes(String rootPath) async {
    final dir = Directory(rootPath);
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += (await entity.stat()).size;
        } catch (_) {
          // 统计失败不计入
        }
      }
    }
    return total;
  }

  /// 列出某个命名空间（或整机）的快照，按时间倒序。
  Future<List<BackupSnapshot>> listSnapshots({
    required String namespaceId,
    bool appWide = false,
  }) async {
    final dir = Directory(
      appWide
          ? p.join((await _ensurePaths()).appDataRoot, 'backups')
          : await backupDir(namespaceId),
    );
    if (!await dir.exists()) return const [];
    final snapshots = <BackupSnapshot>[];
    for (final entity in await dir.list().toList()) {
      if (entity is! File || !entity.path.endsWith('.zip')) continue;
      final meta = _readMeta(entity.path);
      if (meta != null) {
        snapshots.add(meta);
        continue;
      }
      // 兼容没有 sidecar 的手工拷贝：从 zip 内 manifest 还原。
      final raw = await _readManifestFromZip(entity.path);
      if (raw == null) continue;
      snapshots.add(_snapshotFromManifest(entity.path, raw));
    }
    snapshots.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return snapshots;
  }

  /// 为单个命名空间生成快照。
  Future<BackupSnapshot> snapshotNamespace({
    required String namespaceId,
    required String displayName,
    required String rootPath,
  }) {
    return _locked(() async {
      final stamp = DateTime.now();
      final dir = Directory(await backupDir(namespaceId));
      await dir.create(recursive: true);
      final archive = Archive();
      final files = <Map<String, Object?>>[];

      await _collectTree(
        Directory(rootPath),
        'data',
        archive,
        files,
      );

      final manifest = _manifest(
        kind: 'namespace',
        namespaceId: namespaceId,
        displayName: displayName,
        createdAt: stamp.millisecondsSinceEpoch,
        files: files,
      );
      archive.addFile(
        ArchiveFile(
          manifestName,
          utf8.encode(jsonEncode(manifest)).length,
          utf8.encode(jsonEncode(manifest)),
        ),
      );

      final name = '${_slug(namespaceId)}-${_stamp(stamp)}.zip';
      final path = p.join(dir.path, name);
      final bytes = ZipEncoder().encode(archive);
      if (bytes == null) {
        throw const FileSystemException('快照打包失败');
      }
      await File(path).writeAsBytes(bytes, flush: true);
      final snapshot = _snapshotFromManifest(path, manifest);
      await _writeMeta(snapshot);
      debugPrint(
        '[BackupCenter] 快照完成 $name, 文件=${files.length}, ${bytes.length} 字节',
      );
      return snapshot;
    });
  }

  /// 整机快照：每个命名空间一个子目录，共享一份顶层 manifest。
  Future<BackupSnapshot> snapshotApp(List<NamespaceSource> sources) {
    return _locked(() async {
      final stamp = DateTime.now();
      final paths = await _ensurePaths();
      final dir = Directory(p.join(paths.appDataRoot, 'backups'));
      await dir.create(recursive: true);
      final archive = Archive();
      final files = <Map<String, Object?>>[];
      final namespaces = <Map<String, Object?>>[];
      for (final source in sources) {
        namespaces.add({
          'id': source.id,
          'displayName': source.displayName,
        });
        await _collectTree(
          Directory(source.rootPath),
          'namespaces/${source.id}/data',
          archive,
          files,
        );
      }
      final manifest = _manifest(
        kind: 'app',
        namespaceId: 'all',
        displayName: '整机备份',
        createdAt: stamp.millisecondsSinceEpoch,
        files: files,
        namespaces: namespaces,
      );
      archive.addFile(
        ArchiveFile(
          manifestName,
          utf8.encode(jsonEncode(manifest)).length,
          utf8.encode(jsonEncode(manifest)),
        ),
      );
      final name = 'app-${_stamp(stamp)}.zip';
      final path = p.join(dir.path, name);
      final bytes = ZipEncoder().encode(archive);
      if (bytes == null) {
        throw const FileSystemException('整机快照打包失败');
      }
      await File(path).writeAsBytes(bytes, flush: true);
      final snapshot = _snapshotFromManifest(path, manifest);
      await _writeMeta(snapshot);
      debugPrint('[BackupCenter] 整机快照完成 $name, 文件=${files.length}');
      return snapshot;
    });
  }

  Future<void> deleteSnapshot(BackupSnapshot snapshot) async {
    final file = File(snapshot.path);
    if (await file.exists()) await file.delete();
    final meta = File('${snapshot.path}.json');
    if (await meta.exists()) await meta.delete();
    debugPrint('[BackupCenter] 已删除快照 ${snapshot.fileName}');
  }

  /// 从快照恢复单个命名空间：staging → 校验 → 旧目录留存 → 落位，失败回滚。
  ///
  /// [namespaceId] 在整机快照中指定要恢复的命名空间；单命名空间快照可省略。
  Future<void> restoreNamespace(
    BackupSnapshot snapshot, {
    required String targetRoot,
    String? namespaceId,
  }) {
    return _locked(() async {
      final paths = await _ensurePaths();
      final zipBytes = await File(snapshot.path).readAsBytes();
      final archive = ZipDecoder().decodeBytes(zipBytes);
      final manifestFile =
          archive.files.where((f) => f.name == manifestName).firstOrNull;
      if (manifestFile == null) {
        throw const FormatException('快照缺少 manifest.json');
      }
      final manifest = jsonDecode(
        utf8.decode(manifestFile.content as List<int>),
      );
      if (manifest is! Map || manifest['schema'] != schema) {
        throw const FormatException('快照 manifest 版本不兼容');
      }
      final entries = (manifest['files'] as List?) ?? const [];
      final expected = <String, String>{
        for (final item in entries)
          (item as Map)['path'] as String: item['sha256'] as String,
      };
      if (snapshot.appWide && namespaceId == null) {
        throw const FormatException('整机快照需指定要恢复的命名空间');
      }
      final prefix = snapshot.appWide
          ? 'namespaces/$namespaceId/data/'
          : 'data/';
      final restoreId = snapshot.appWide ? namespaceId! : snapshot.namespaceId;

      final stamp = DateTime.now().millisecondsSinceEpoch;
      final staging = Directory(
        p.join(paths.appDataRoot, _stagingDir, 'restore-$restoreId-$stamp'),
      );
      final prev = Directory(
        p.join(paths.appDataRoot, _stagingDir, 'prev-$restoreId-$stamp'),
      );
      await staging.create(recursive: true);

      // 1) 解包并逐文件校验 sha256。
      for (final file in archive.files) {
        if (!file.isFile) continue;
        if (file.name == manifestName) continue;
        if (!file.name.startsWith(prefix)) continue;
        final rel = file.name.substring(prefix.length);
        final content = file.content as List<int>;
        final digest = sha256.convert(content).toString();
        if (expected[file.name] != null && expected[file.name] != digest) {
          throw FormatException('快照文件校验失败: ${file.name}');
        }
        final out = File(p.join(staging.path, rel));
        await out.parent.create(recursive: true);
        await out.writeAsBytes(content, flush: true);
      }

      // 2) 旧目录搬到 staging/prev，失败可整体搬回。
      final target = Directory(targetRoot);
      if (!await target.exists()) await target.create(recursive: true);
      await prev.create(recursive: true);
      final moved = <String>[];
      try {
        for (final entity in await target.list().toList()) {
          if (entity is! File && entity is! Directory) continue;
          final name = p.basename(entity.path);
          await entity.rename(p.join(prev.path, name));
          moved.add(name);
        }
        for (final entity in await staging.list().toList()) {
          final name = p.basename(entity.path);
          await entity.rename(p.join(target.path, name));
        }
        await prev.delete(recursive: true);
        await staging.delete(recursive: true);
      } catch (e) {
        // 回滚：清掉本次落位内容，再把旧目录搬回。
        try {
          for (final entity in await target.list().toList()) {
            if (entity is File || entity is Directory) {
              await entity.delete(recursive: true);
            }
          }
          for (final name in moved) {
            final from = p.join(prev.path, name);
            final stat = await FileStat.stat(from);
            if (stat.type == FileSystemEntityType.directory) {
              await Directory(from).rename(p.join(target.path, name));
            } else if (stat.type != FileSystemEntityType.notFound) {
              await File(from).rename(p.join(target.path, name));
            }
          }
        } catch (_) {
          // 回滚尽力而为
        }
        throw FileSystemException('恢复失败：$e');
      }
      debugPrint(
        '[BackupCenter] 恢复完成 ${snapshot.fileName} → $targetRoot',
      );
    });
  }

  /// 递归把目录内容写入 zip，并记录 sha256。
  Future<void> _collectTree(
    Directory dir,
    String prefix,
    Archive archive,
    List<Map<String, Object?>> files,
  ) async {
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      final name = p.basename(entity.path);
      if (name.startsWith('.tmp') || name.endsWith('.tmp')) continue;
      if (entity is Directory) {
        final rel = '$prefix/$name';
        if (rel.endsWith('.notepad/staging')) continue;
        await _collectTree(entity, rel, archive, files);
        continue;
      }
      if (entity is! File) continue;
      final rel = '$prefix/$name';
      final bytes = await entity.readAsBytes();
      files.add({
        'path': rel,
        'size': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
      });
      archive.addFile(
        ArchiveFile(rel, bytes.length, bytes),
      );
    }
  }

  Map<String, Object?> _manifest({
    required String kind,
    required String namespaceId,
    required String displayName,
    required int createdAt,
    required List<Map<String, Object?>> files,
    List<Map<String, Object?>>? namespaces,
  }) {
    final totalBytes = files.fold<int>(
      0,
      (sum, item) => sum + (item['size'] as int),
    );
    return {
      'schema': schema,
      'kind': kind,
      'namespaceId': namespaceId,
      'displayName': displayName,
      'createdAt': createdAt,
      'fileCount': files.length,
      'totalBytes': totalBytes,
      'files': files,
      if (namespaces != null) 'namespaces': namespaces,
    };
  }

  BackupSnapshot _snapshotFromManifest(String path, Map<Object?, Object?> json) {
    final map = json.cast<String, Object?>();
    return BackupSnapshot(
      namespaceId: (map['namespaceId'] as String?) ?? 'all',
      displayName: (map['displayName'] as String?) ?? '快照',
      path: path,
      createdAt: (map['createdAt'] as num?)?.toInt() ?? 0,
      fileCount: (map['fileCount'] as num?)?.toInt() ?? 0,
      totalBytes: (map['totalBytes'] as num?)?.toInt() ?? 0,
      appWide: map['kind'] == 'app',
    );
  }

  Future<void> _writeMeta(BackupSnapshot snapshot) async {
    await File('${snapshot.path}.json').writeAsString(
      jsonEncode({
        'namespaceId': snapshot.namespaceId,
        'displayName': snapshot.displayName,
        'createdAt': snapshot.createdAt,
        'fileCount': snapshot.fileCount,
        'totalBytes': snapshot.totalBytes,
        'appWide': snapshot.appWide,
      }),
      flush: true,
    );
  }

  BackupSnapshot? _readMeta(String zipPath) {
    final file = File('$zipPath.json');
    if (!file.existsSync()) return null;
    try {
      final map = jsonDecode(file.readAsStringSync()) as Map;
      return BackupSnapshot(
        namespaceId: map['namespaceId'] as String? ?? 'all',
        displayName: map['displayName'] as String? ?? '快照',
        path: zipPath,
        createdAt: (map['createdAt'] as num?)?.toInt() ?? 0,
        fileCount: (map['fileCount'] as num?)?.toInt() ?? 0,
        totalBytes: (map['totalBytes'] as num?)?.toInt() ?? 0,
        appWide: map['appWide'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<Object?, Object?>?> _readManifestFromZip(String path) async {
    try {
      final archive = ZipDecoder().decodeBytes(await File(path).readAsBytes());
      final entry =
          archive.files.where((f) => f.name == manifestName).firstOrNull;
      if (entry == null) return null;
      final decoded = jsonDecode(utf8.decode(entry.content as List<int>));
      return decoded is Map ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  static String _slug(String value) =>
      value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
}

extension on Iterable<ArchiveFile> {
  ArchiveFile? get firstOrNull {
    for (final item in this) {
      return item;
    }
    return null;
  }
}
