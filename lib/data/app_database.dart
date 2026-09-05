import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 数据库助手。
///
/// 移动端使用原生 `sqflite`（对应原 Android 的 Room / app_database）；
/// 桌面端（Windows/macOS/Linux）通过 `sqflite_common_ffi` 实现同样的
/// 本地存储能力，从而在 Android / iOS / 桌面三端复用同一套数据层逻辑。
class AppDatabase {
  AppDatabase._();

  static const String _dbName = 'app_database.db';
  static const int _version = 1;
  static const String tableNode = 'notepad_node';

  static Database? _db;

  /// 是否为桌面平台（用于决定使用 FFI 实现）。
  static bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// 获取单例数据库。首次调用会初始化工厂并建表。
  static Future<Database> get instance async {
    if (_db != null) return _db!;
    debugPrint('[AppDatabase] 初始化数据库（desktop=$isDesktop）');
    if (isDesktop) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _dbName);
    debugPrint('[AppDatabase] 打开数据库路径: $path');

    try {
      _db = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: _version,
          onCreate: _onCreate,
        ),
      );
    } catch (e) {
      debugPrint('[AppDatabase] 打开数据库失败: $e');
      rethrow;
    }
    debugPrint('[AppDatabase] 数据库已就绪');
    return _db!;
  }

  static Future<void> _onCreate(Database db, int version) async {
    // 统一节点表：文件夹与文章共用一张表，支持多层级与回收站。
    await db.execute('''
      CREATE TABLE $tableNode (
        id TEXT PRIMARY KEY,
        is_folder INTEGER NOT NULL DEFAULT 0,
        title TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL DEFAULT '',
        parent_id TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        is_recycled INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_node_parent ON $tableNode(parent_id)',
    );
    await db.execute(
      'CREATE INDEX idx_node_recycled ON $tableNode(is_recycled)',
    );
  }

  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}