import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;

import '../../models/note.dart';

/// 旧 SQLite 库只读来源。
class LegacySqliteSource {
  LegacySqliteSource._();

  static const String tableName = 'notepad_node';

  static bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static Future<bool> exists(String dbPath) => File(dbPath).exists();

  /// 读取整张节点表（不修改旧库）。
  static Future<List<NotePadNode>> readNodes(String dbPath) async {
    if (!await exists(dbPath)) return const [];
    if (_isDesktop) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(readOnly: true),
    );
    try {
      final rows = await db.query(tableName);
      return rows.map(NotePadNode.fromMap).toList();
    } finally {
      await db.close();
    }
  }

  /// 旧库指纹（用于迁移幂等判断；v2 暂不引入 crypto 依赖）。
  static Future<String> fingerprint(String dbPath) async {
    final file = File(dbPath);
    if (!await file.exists()) return '';
    final stat = await file.stat();
    return 'size:${stat.size};mtime:${stat.modified.millisecondsSinceEpoch}';
  }
}
