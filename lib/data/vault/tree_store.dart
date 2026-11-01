import 'dart:convert';

import '../../models/note.dart';
import 'filename_policy.dart';
import 'vault_store.dart';

/// tree.json 中的单条节点记录。
class VaultNodeRecord {
  VaultNodeRecord({
    required this.id,
    required this.kind,
    required this.path,
    required this.order,
    required this.createdAt,
    required this.updatedAt,
    this.tags = const [],
    this.favorite = false,
  });

  /// 稳定 id；文件重命名不换 id。
  final String id;

  /// note / folder。
  final String kind;

  /// 相对 nsRoot，NFC 归一化、`/` 分隔。
  String path;

  /// 仅同一父目录内比较。
  int order;

  final int createdAt;
  int updatedAt;
  List<String> tags;
  bool favorite;

  bool get isFolder => kind == 'folder';

  VaultNodeRecord copyWith({
    String? path,
    int? order,
    int? updatedAt,
  }) {
    return VaultNodeRecord(
      id: id,
      kind: kind,
      path: path ?? this.path,
      order: order ?? this.order,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      tags: tags,
      favorite: favorite,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind,
        'path': path,
        'order': order,
        'createdAt': createdAt,
        if (!isFolder) 'updatedAt': updatedAt,
        'tags': tags,
        'favorite': favorite,
      };

  factory VaultNodeRecord.fromJson(Map<String, Object?> json) {
    return VaultNodeRecord(
      id: (json['id'] as String?) ?? '',
      kind: (json['kind'] as String?) ?? 'note',
      path: (json['path'] as String?) ?? '',
      order: (json['order'] as num?)?.toInt() ?? 0,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      tags: ((json['tags'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      favorite: (json['favorite'] as bool?) ?? false,
    );
  }

  /// 转成列表节点（正文 / 预览由调用方填充）。
  NotePadNode toNode({
    String content = '',
    String? parentId,
  }) {
    return NotePadNode(
      id: id,
      isFolder: isFolder,
      title: FilenamePolicy.titleOfPath(path),
      content: content,
      parentId: parentId,
      sortOrder: order,
      isRecycled: false,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

/// tree.json 的内存模型。
class VaultTree {
  VaultTree({List<VaultNodeRecord>? nodes})
      : nodes = nodes ?? <VaultNodeRecord>[];

  final List<VaultNodeRecord> nodes;
  int updatedAt = 0;

  VaultNodeRecord? byId(String id) {
    for (final record in nodes) {
      if (record.id == id) return record;
    }
    return null;
  }

  VaultNodeRecord? byPath(String path) {
    for (final record in nodes) {
      if (record.path == path) return record;
    }
    return null;
  }

  static String parentOf(String path) {
    final index = path.lastIndexOf('/');
    return index < 0 ? '' : path.substring(0, index);
  }

  static String rootOf(String path) => path.split('/').first;

  List<VaultNodeRecord> childrenOfPath(String parentPath) {
    return nodes.where((r) => parentOf(r.path) == parentPath).toList();
  }

  List<VaultNodeRecord> descendantsOfPath(String path) {
    final prefix = '$path/';
    return nodes.where((r) => r.path.startsWith(prefix)).toList();
  }

  bool isDescendantPath(String ancestorPath, String candidatePath) =>
      candidatePath.startsWith('$ancestorPath/');

  void removeSubtree(String id) {
    final record = byId(id);
    if (record == null) return;
    nodes.removeWhere(
      (r) => r.id == id || isDescendantPath(record.path, r.path),
    );
  }

  int nextOrder(String parentPath) {
    var max = -1;
    for (final record in nodes) {
      if (parentOf(record.path) == parentPath && record.order > max) {
        max = record.order;
      }
    }
    return max + 1;
  }

  Set<String> siblingTitles(String parentPath, {String? excludeId}) {
    return {
      for (final record in nodes)
        if (parentOf(record.path) == parentPath && record.id != excludeId)
          FilenamePolicy.titleOfPath(record.path),
    };
  }

  List<VaultNodeRecord> sortedChildren(String parentPath) {
    final children = childrenOfPath(parentPath);
    children.sort((a, b) {
      final byOrder = a.order.compareTo(b.order);
      if (byOrder != 0) return byOrder;
      return FilenamePolicy.titleOfPath(a.path)
          .toLowerCase()
          .compareTo(FilenamePolicy.titleOfPath(b.path).toLowerCase());
    });
    return children;
  }
}

/// tree.json 读写。
class TreeStore {
  TreeStore(this._store);

  final VaultStore _store;
  static const String treePath = '.notepad/tree.json';
  static const int schema = 1;

  Future<VaultTree> load() async {
    if (!await _store.exists(treePath)) {
      return VaultTree();
    }
    try {
      final raw = await _store.readText(treePath);
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return VaultTree();
      final map = decoded.cast<String, Object?>();
      final nodes = (map['nodes'] as List?) ?? const [];
      return VaultTree(
        nodes: [
          for (final item in nodes)
            VaultNodeRecord.fromJson(
              (item as Map).cast<String, Object?>(),
            ),
        ],
      )..updatedAt = (map['updatedAt'] as num?)?.toInt() ?? 0;
    } catch (_) {
      // 损坏的 tree 保留一份现场副本，然后重建。
      final backup = '.notepad/tree.corrupt-'
          '${DateTime.now().millisecondsSinceEpoch}.json';
      try {
        await _store.rename(treePath, backup);
      } catch (_) {
        // 备份失败不阻塞启动。
      }
      return VaultTree();
    }
  }

  Future<void> save(VaultTree tree) async {
    tree.updatedAt = DateTime.now().millisecondsSinceEpoch;
    final payload = jsonEncode({
      'schema': schema,
      'updatedAt': tree.updatedAt,
      'nodes': [for (final record in tree.nodes) record.toJson()],
    });
    await _store.writeTextAtomic(treePath, payload);
  }
}
