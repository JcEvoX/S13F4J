import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/note.dart';
import '../notes_repository.dart';
import 'legacy_sqlite_source.dart';

/// 迁移执行结果。
class LegacyMigrationResult {
  const LegacyMigrationResult({
    required this.status,
    this.nodeCount = 0,
    this.trashCount = 0,
    this.message,
  });

  /// success / skipped / failed。
  final String status;
  final int nodeCount;
  final int trashCount;
  final String? message;
}

/// 旧 SQLite → vault 一次性迁移器。
///
/// 幂等：`.notepad/migration.json` 记录成功结果后不再执行；
/// 保留旧库（改名为 `.migrated-<ts>`），失败整体回滚并可重入。
class LegacyMigrator {
  LegacyMigrator({
    required NotesRepository repository,
    required String vaultPath,
    required String dbPath,
  })  : _repository = repository,
        _vaultPath = vaultPath,
        _dbPath = dbPath;

  final NotesRepository _repository;
  final String _vaultPath;
  final String _dbPath;

  static const String markerRelativePath = '.notepad/migration.json';

  Future<LegacyMigrationResult> migrateIfNeeded() async {
    final marker = File(p.join(_vaultPath, markerRelativePath));
    if (await _hasSuccessfulMarker(marker)) {
      return const LegacyMigrationResult(status: 'skipped', message: '已迁移');
    }
    if (!await LegacySqliteSource.exists(_dbPath)) {
      return const LegacyMigrationResult(status: 'skipped', message: '无旧库');
    }
    if (await _repository.hasUserContent()) {
      // 已有 vault 内容时不覆盖，交由用户手动处理。
      return const LegacyMigrationResult(
        status: 'skipped',
        message: 'vault 已有内容，跳过自动迁移',
      );
    }

    final startedAt = DateTime.now().millisecondsSinceEpoch;
    final sourceHash = await LegacySqliteSource.fingerprint(_dbPath);
    List<NotePadNode> rawNodes;
    try {
      rawNodes = await LegacySqliteSource.readNodes(_dbPath);
    } catch (e) {
      return LegacyMigrationResult(
        status: 'failed',
        message: '读取旧库失败：$e',
      );
    }

    final active = rawNodes.where((n) => !n.isRecycled).length;
    final recycled = rawNodes.length - active;
    try {
      await _repository.replaceAll(
        rawNodes,
        stagingDir: p.join(_vaultPath, '.notepad', 'staging'),
      );
      final restored = await _repository.allNodes();
      if (restored.length < rawNodes.length) {
        throw StateError(
          '抽样校验失败：迁移后节点 ${restored.length} < 原库 ${rawNodes.length}',
        );
      }
    } catch (e) {
      return LegacyMigrationResult(
        status: 'failed',
        nodeCount: rawNodes.length,
        trashCount: recycled,
        message: '迁移失败（旧库保留）：$e',
      );
    }

    final finishedAt = DateTime.now().millisecondsSinceEpoch;
    await _writeMarker(
      marker,
      sourceHash: sourceHash,
      startedAt: startedAt,
      finishedAt: finishedAt,
      nodeCount: rawNodes.length,
      trashCount: recycled,
      result: 'success',
    );

    try {
      await File(_dbPath).rename(
        '$_dbPath.migrated-$finishedAt',
      );
    } catch (_) {
      // 改名失败不影响迁移结果，下次启动会因 marker 跳过。
    }

    return LegacyMigrationResult(
      status: 'success',
      nodeCount: active,
      trashCount: recycled,
    );
  }

  Future<bool> _hasSuccessfulMarker(File marker) async {
    if (!await marker.exists()) return false;
    try {
      final decoded = jsonDecode(await marker.readAsString());
      if (decoded is Map) {
        return decoded['result'] == 'success';
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  Future<void> _writeMarker(
    File marker, {
    required String sourceHash,
    required int startedAt,
    required int finishedAt,
    required int nodeCount,
    required int trashCount,
    required String result,
  }) async {
    await marker.parent.create(recursive: true);
    final payload = jsonEncode({
      'schema': 1,
      'source': p.basename(_dbPath),
      'sourceHash': sourceHash,
      'startedAt': startedAt,
      'finishedAt': finishedAt,
      'nodeCount': nodeCount,
      'trashCount': trashCount,
      'rebuilt': false,
      'result': result,
    });
    await marker.writeAsString(payload, flush: true);
  }
}
