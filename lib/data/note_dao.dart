import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../data/app_database.dart';
import '../models/note.dart';

/// 节点数据访问对象。
class NoteDao {
  /// 查询某一层级下的全部节点（文件夹与文章），按排序权重与创建时间排序。
  /// [includeRecycled] 是否包含回收站节点（常规列表为 false）。
  Future<List<NotePadNode>> childrenOf({
    String? parentId,
    bool includeRecycled = false,
  }) async {
    final db = await AppDatabase.instance;
    final where = StringBuffer('parent_id IS ');
    final args = <Object?>[];
    if (parentId == null) {
      where.write('NULL');
    } else {
      where.write('?');
      args.add(parentId);
    }
    if (!includeRecycled) {
      where.write(' AND is_recycled = 0');
    }
    final rows = await db.query(
      AppDatabase.tableNode,
      where: where.toString(),
      whereArgs: args,
      orderBy: 'sort_order ASC, created_at ASC',
    );
    return rows.map(NotePadNode.fromMap).toList();
  }

  /// 根据 id 查询单个节点。
  Future<NotePadNode?> nodeById(String id) async {
    final db = await AppDatabase.instance;
    final rows = await db.query(
      AppDatabase.tableNode,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return NotePadNode.fromMap(rows.first);
  }

  /// 新增或更新节点（insert or replace）。
  Future<void> saveNode(NotePadNode node) async {
    final db = await AppDatabase.instance;
    await db.insert(
      AppDatabase.tableNode,
      node.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 批量保存（用于拖拽排序、多选移动后的批量落库）。
  Future<void> saveNodes(List<NotePadNode> nodes) async {
    final db = await AppDatabase.instance;
    debugPrint('[NoteDao] saveNodes: ${nodes.length} 个节点');
    await db.transaction((txn) async {
      for (final n in nodes) {
        await txn.insert(
          AppDatabase.tableNode,
          n.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    debugPrint('[NoteDao] saveNodes 完成');
  }

  /// 逻辑删除：移入回收站（写入 deleted_at）。
  Future<void> moveToRecycleBin(List<NotePadNode> nodes) async {
    final db = await AppDatabase.instance;
    final now = DateTime.now().millisecondsSinceEpoch;
    debugPrint('[NoteDao] moveToRecycleBin: ids=${nodes.map((n) => n.id).toList()}');
    await db.transaction((txn) async {
      for (final n in nodes) {
        await txn.update(
          AppDatabase.tableNode,
          {
            'is_recycled': 1,
            'deleted_at': now,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [n.id],
        );
      }
    });
    debugPrint('[NoteDao] moveToRecycleBin 完成');
  }

  /// 从回收站恢复（包括其下所有后代节点）。
  Future<void> restoreNodes(List<NotePadNode> roots) async {
    final db = await AppDatabase.instance;
    final ids = await _collectIds(roots);
    final now = DateTime.now().millisecondsSinceEpoch;
    debugPrint('[NoteDao] restoreNodes: ids=$ids');
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.update(
          AppDatabase.tableNode,
          {'is_recycled': 0, 'deleted_at': null, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    });
    debugPrint('[NoteDao] restoreNodes 完成: ${ids.length} 个');
  }

  /// 永久删除（含所有后代节点）。
  Future<void> deletePermanently(List<NotePadNode> roots) async {
    final db = await AppDatabase.instance;
    final ids = await _collectIds(roots);
    debugPrint('[NoteDao] deletePermanently: ids=$ids');
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.delete(
          AppDatabase.tableNode,
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    });
    debugPrint('[NoteDao] deletePermanently 完成: ${ids.length} 个');
  }

  /// 递归收集一个节点集合及其全部后代的 id。
  ///
  /// 一次性读出整库（或按 is_recycled 过滤）构建「父 → 子」映射，
  /// 避免递归多次查询。
  Future<List<String>> _collectIds(List<NotePadNode> roots) async {
    final db = await AppDatabase.instance;
    final rows = await db.query(AppDatabase.tableNode);
    final byParent = <String?, List<NotePadNode>>{};
    for (final r in rows) {
      final n = NotePadNode.fromMap(r);
      byParent.putIfAbsent(n.parentId, () => []).add(n);
    }

    final out = <String>{};
    void walk(List<NotePadNode> nodes) {
      for (final n in nodes) {
        if (out.add(n.id)) {
          final children = byParent[n.id];
          if (children != null) walk(children);
        }
      }
    }

    walk(roots);
    return out.toList();
  }

  /// 回收站列表（顶层回收站节点，去重后代）。
  Future<List<NotePadNode>> recycleBin() async {
    final db = await AppDatabase.instance;
    final rows = await db.query(
      AppDatabase.tableNode,
      where: 'is_recycled = 1',
      orderBy: 'deleted_at DESC',
    );
    final nodes = rows.map(NotePadNode.fromMap).toList();
    // 若某节点的父节点也在回收站，则它属于父节点的后代，不单独显示。
    final recycledIds = nodes.map((n) => n.id).toSet();
    return nodes
        .where((n) => n.parentId == null || !recycledIds.contains(n.parentId))
        .toList();
  }

  /// 关键词搜索（递归搜索所有未回收节点，返回直接命中的节点）。
  Future<List<NotePadNode>> search(String keyword) async {
    final db = await AppDatabase.instance;
    final rows = await db.query(
      AppDatabase.tableNode,
      where: 'is_recycled = 0 AND (title LIKE ? OR content LIKE ?)',
      whereArgs: ['%$keyword%', '%$keyword%'],
      orderBy: 'updated_at DESC',
    );
    return rows.map(NotePadNode.fromMap).toList();
  }

  /// 移动节点到目标层级（批量）。
  Future<void> moveTo(List<String> ids, String? targetParentId) async {
    final db = await AppDatabase.instance;
    final now = DateTime.now().millisecondsSinceEpoch;
    debugPrint('[NoteDao] moveTo: ids=$ids, 目标=$targetParentId');
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.update(
          AppDatabase.tableNode,
          {'parent_id': targetParentId, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    });
    debugPrint('[NoteDao] moveTo 完成: ${ids.length} 项');
  }

  /// 自动备份：读取全部未回收节点（导出用基础）。
  Future<List<NotePadNode>> allActive() async {
    final db = await AppDatabase.instance;
    final rows = await db.query(
      AppDatabase.tableNode,
      where: 'is_recycled = 0',
    );
    return rows.map(NotePadNode.fromMap).toList();
  }

  /// 获取全部未回收文件夹（用于移动定位）。
  Future<List<NotePadNode>> allFolders() async {
    final db = await AppDatabase.instance;
    final rows = await db.query(
      AppDatabase.tableNode,
      where: 'is_folder = 1 AND is_recycled = 0',
      orderBy: 'sort_order ASC, created_at ASC',
    );
    return rows.map(NotePadNode.fromMap).toList();
  }

  // ---- 最近 / 统计 / 备份 ----

  /// 最近编辑的文章（仅未回收的文章节点，按更新时间倒序）。
  Future<List<NotePadNode>> recentArticles({int limit = 50}) async {
    final db = await AppDatabase.instance;
    final rows = await db.query(
      AppDatabase.tableNode,
      where: 'is_folder = 0 AND is_recycled = 0',
      orderBy: 'updated_at DESC',
      limit: limit,
    );
    return rows.map(NotePadNode.fromMap).toList();
  }

  /// 读取全部节点（含回收站，导出备份用）。
  Future<List<NotePadNode>> allNodes() async {
    final db = await AppDatabase.instance;
    final rows = await db.query(AppDatabase.tableNode);
    return rows.map(NotePadNode.fromMap).toList();
  }

  /// 统计信息汇总。
  Future<NoteStatistics> statistics() async {
    final db = await AppDatabase.instance;
    final rows = await db.query(AppDatabase.tableNode);
    var folders = 0;
    var articles = 0;
    var words = 0;
    var recycled = 0;
    var lastEdited = 0;
    for (final r in rows) {
      final n = NotePadNode.fromMap(r);
      if (n.isRecycled) {
        recycled++;
        continue;
      }
      if (n.isFolder) {
        folders++;
      } else {
        articles++;
        words += _countWords(n.content);
      }
      if (n.updatedAt > lastEdited) lastEdited = n.updatedAt;
    }
    return NoteStatistics(
      folders: folders,
      articles: articles,
      words: words,
      recycled: recycled,
      lastEditedAt: lastEdited,
    );
  }

  /// 统计字数（与编辑器一致：中文字符 + 英文单词）。
  int _countWords(String text) {
    final cn = RegExp(r'[\u4e00-\u9fa5]').allMatches(text).length;
    final en = text
        .replaceAll(RegExp(r'[\u4e00-\u9fa5]'), ' ')
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;
    return cn + en;
  }

  /// 恢复备份：清空现有数据并整库写入（事务内完成）。
  Future<void> replaceAll(List<NotePadNode> nodes) async {
    final db = await AppDatabase.instance;
    debugPrint('[NoteDao] replaceAll: ${nodes.length} 个节点');
    await db.transaction((txn) async {
      await txn.delete(AppDatabase.tableNode);
      for (final n in nodes) {
        await txn.insert(
          AppDatabase.tableNode,
          n.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    debugPrint('[NoteDao] replaceAll 完成');
  }
}

/// 统计结果。
class NoteStatistics {
  const NoteStatistics({
    required this.folders,
    required this.articles,
    required this.words,
    required this.recycled,
    required this.lastEditedAt,
  });

  /// 文件夹数量。
  final int folders;

  /// 文章数量。
  final int articles;

  /// 总字数。
  final int words;

  /// 回收站节点数量。
  final int recycled;

  /// 最近编辑时间（毫秒，0 表示无数据）。
  final int lastEditedAt;
}