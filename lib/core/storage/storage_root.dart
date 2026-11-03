/// 存储根抽象与相对路径校验。
///
/// 所有能力（笔记 / 文件阅读项目 / 将来插件）都只通过 [StorageRoot]
/// 与 [NamespaceHandle] 访问磁盘，禁止直接拼绝对路径。相对路径统一使用
/// `/` 作为分隔符，由具体实现转换为平台路径。
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// 目录 / 文件条目。
class StorageEntry {
  const StorageEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.size,
    required this.modifiedAt,
  });

  /// 相对于根的路径，使用 `/` 分隔。
  final String path;

  /// 名称（不含路径）。
  final String name;
  final bool isDirectory;
  final int size;
  final DateTime modifiedAt;
}

/// 相对路径非法（越界 / 绝对路径 / 空段）。
class StoragePathException implements Exception {
  const StoragePathException(this.message);

  final String message;

  @override
  String toString() => 'StoragePathException: $message';
}

/// 相对路径校验工具。
///
/// 拒绝绝对路径、盘符、`..`、空段、空路径（可配置允许空路径表示根）。
class StoragePathGuard {
  StoragePathGuard._();

  static final RegExp _drivePrefix = RegExp(r'^[A-Za-z]:');

  static String validate(String rel, {bool allowEmpty = false}) {
    final value = rel.trim();
    if (value.isEmpty) {
      if (allowEmpty) return '';
      throw const StoragePathException('相对路径不能为空');
    }
    if (_drivePrefix.hasMatch(value) ||
        value.startsWith('/') ||
        value.startsWith('\\')) {
      throw StoragePathException('不允许绝对路径: $rel');
    }
    if (value.contains('\u0000')) {
      throw const StoragePathException('路径包含非法字符');
    }
    for (final segment in value.split('/')) {
      if (segment.isEmpty || segment == '.' || segment == '..') {
        throw StoragePathException('路径包含非法片段: $rel');
      }
    }
    return value;
  }
}

/// 存储根契约。
abstract class StorageRoot {
  /// 相对路径是否存在。
  Future<bool> exists(String rel);

  /// 列出目录（单层）。
  Future<List<StorageEntry>> list(String relDir);

  /// 读取文本。
  Future<String> readText(String rel);

  /// 原子写入文本（同目录 tmp + rename）。
  Future<void> writeTextAtomic(String rel, String text);

  /// 原子写入字节。
  Future<void> writeBytesAtomic(String rel, List<int> bytes);

  /// 同根内移动 / 改名。
  Future<void> rename(String fromRel, String toRel);

  /// 删除文件或目录（目录递归）。不存在时忽略。
  Future<void> delete(String rel);

  /// 修改时间。
  Future<DateTime> modifiedAt(String rel);

  /// 是否支持文件监听。
  bool get supportsWatch;
}

/// 本机沙盒实现（dart:io）。
class SandboxRoot implements StorageRoot {
  SandboxRoot(this.rootPath);

  /// 绝对根路径。
  final String rootPath;

  static final String _sep = Platform.pathSeparator;

  /// 把相对路径转换为绝对路径。
  String absolutePath(String rel, {bool allowEmpty = true}) {
    final validated = StoragePathGuard.validate(rel, allowEmpty: allowEmpty);
    if (validated.isEmpty) return rootPath;
    return '$rootPath$_sep${validated.split('/').join(_sep)}';
  }

  @override
  bool get supportsWatch => true;

  @override
  Future<bool> exists(String rel) async {
    final type = await FileSystemEntity.type(absolutePath(rel), followLinks: false);
    return type != FileSystemEntityType.notFound;
  }

  @override
  Future<List<StorageEntry>> list(String relDir) async {
    final dir = Directory(absolutePath(relDir));
    if (!await dir.exists()) return const [];
    final baseRel = relDir.isEmpty ? '' : '$relDir/';
    final entries = <StorageEntry>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is Link) continue; // 不跟随符号链接
      final name = _basename(entity.path);
      final stat = await entity.stat();
      entries.add(
        StorageEntry(
          path: '$baseRel$name',
          name: name,
          isDirectory: entity is Directory,
          size: entity is Directory ? 0 : stat.size,
          modifiedAt: stat.modified,
        ),
      );
    }
    return entries;
  }

  @override
  Future<String> readText(String rel) {
    final file = File(absolutePath(rel));
    return file.readAsString();
  }

  @override
  Future<void> writeTextAtomic(String rel, String text) async {
    await _writeAtomic(rel, (file) => file.writeAsString(text, flush: true));
  }

  @override
  Future<void> writeBytesAtomic(String rel, List<int> bytes) async {
    await _writeAtomic(rel, (file) => file.writeAsBytes(bytes, flush: true));
  }

  Future<void> _writeAtomic(
    String rel,
    Future<File> Function(File tmp) writer,
  ) async {
    final target = absolutePath(rel, allowEmpty: false);
    final targetDir = _dirname(target);
    await Directory(targetDir).create(recursive: true);
    final name = _basename(target);
    final tmp = File(
      '$targetDir$_sep.$name.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await writer(tmp);
      try {
        await tmp.rename(target);
      } catch (_) {
        // 目标已存在且平台不支持覆盖式 rename 时，先删除再重命名。
        final existing = File(target);
        if (await existing.exists()) {
          await existing.delete();
        }
        await tmp.rename(target);
      }
    } catch (e) {
      if (await tmp.exists()) {
        try {
          await tmp.delete();
        } catch (_) {
          // 忽略清理失败
        }
      }
      rethrow;
    }
  }

  @override
  Future<void> rename(String fromRel, String toRel) async {
    final from = absolutePath(fromRel, allowEmpty: false);
    final to = absolutePath(toRel, allowEmpty: false);
    final toDir = _dirname(to);
    await Directory(toDir).create(recursive: true);
    final type = await FileSystemEntity.type(from, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw FileSystemException('源路径不存在', from);
    }
    if (type == FileSystemEntityType.directory) {
      await Directory(from).rename(to);
    } else {
      await File(from).rename(to);
    }
  }

  @override
  Future<void> delete(String rel) async {
    final target = absolutePath(rel, allowEmpty: false);
    final type = await FileSystemEntity.type(target, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;
    if (type == FileSystemEntityType.directory) {
      await Directory(target).delete(recursive: true);
    } else if (type == FileSystemEntityType.link) {
      await Link(target).delete();
    } else {
      await File(target).delete();
    }
  }

  @override
  Future<DateTime> modifiedAt(String rel) async {
    final stat = await FileStat.stat(absolutePath(rel, allowEmpty: false));
    if (stat.type == FileSystemEntityType.notFound) {
      throw FileSystemException('路径不存在', absolutePath(rel, allowEmpty: false));
    }
    return stat.modified;
  }

  static String _basename(String path) => p.basename(path);

  static String _dirname(String path) => p.dirname(path);
}
