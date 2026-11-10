import 'dart:io';

import 'package:path/path.dart' as p;

/// 搬迁结果。
class RelocationResult {
  const RelocationResult({
    required this.copiedFiles,
    required this.targetAlreadyHadData,
    required this.sourceMissing,
  });

  /// 复制的文件数。
  final int copiedFiles;

  /// 目标目录里已经有内容：沿用目标，不覆盖。
  final bool targetAlreadyHadData;

  /// 源目录不存在（全新安装）。
  final bool sourceMissing;
}

/// 把文档库从一个目录复制到另一个目录。
///
/// 只复制、不删除源目录：搬迁失败或用户后悔时，原数据始终完好。
/// 先复制到目标旁的临时目录，校验文件数后再改名，避免留下半份数据。
class VaultRelocator {
  static Future<RelocationResult> copyVault(String from, String to) async {
    final source = Directory(from);
    final target = Directory(to);
    if (p.equals(p.normalize(from), p.normalize(to))) {
      return const RelocationResult(
        copiedFiles: 0,
        targetAlreadyHadData: true,
        sourceMissing: false,
      );
    }
    if (!await source.exists()) {
      await target.create(recursive: true);
      return const RelocationResult(
        copiedFiles: 0,
        targetAlreadyHadData: false,
        sourceMissing: true,
      );
    }
    if (await target.exists() && !(await target.list().isEmpty)) {
      return const RelocationResult(
        copiedFiles: 0,
        targetAlreadyHadData: true,
        sourceMissing: false,
      );
    }

    final staging = Directory('${p.normalize(to)}.migrating');
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    var copied = 0;
    var expected = 0;
    try {
      await for (final entity in source.list(recursive: true, followLinks: false)) {
        final relative = p.relative(entity.path, from: from);
        if (entity is Directory) {
          await Directory(p.join(staging.path, relative)).create(recursive: true);
        } else if (entity is File) {
          expected++;
          final out = File(p.join(staging.path, relative));
          await out.parent.create(recursive: true);
          await entity.copy(out.path);
          copied++;
        }
      }
      if (copied != expected) {
        throw FileSystemException('复制文件数不一致', to);
      }
      if (await target.exists()) await target.delete(recursive: true);
      await staging.rename(target.path);
    } catch (_) {
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    }
    return RelocationResult(
      copiedFiles: copied,
      targetAlreadyHadData: false,
      sourceMissing: false,
    );
  }
}
