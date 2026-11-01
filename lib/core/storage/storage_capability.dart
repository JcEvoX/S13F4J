import 'backup_policy.dart';
import 'trash_policy.dart';

/// 命名空间描述信息（注册表条目）。
class NamespaceDescriptor {
  const NamespaceDescriptor({
    required this.id,
    required this.pluginId,
    this.root = '',
    required this.displayName,
    this.schema = 1,
    this.state = 'active',
    this.backupDriver = true,
    this.trashDriver = true,
    required this.createdAt,
  });

  /// 命名空间 id（如 notes / files.p-01）。
  final String id;

  /// 所属插件 id。
  final String pluginId;

  /// 空 = 根即 vaultRoot；绝对路径 / URI = 外部根。
  final String root;

  final String displayName;
  final int schema;

  /// active / disabled / missing。
  final String state;

  /// 是否提供备份 / 回收站驱动。
  final bool backupDriver;
  final bool trashDriver;

  final int createdAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'pluginId': pluginId,
        'root': root,
        'displayName': displayName,
        'schema': schema,
        'state': state,
        'drivers': {'backup': backupDriver, 'trash': trashDriver},
        'createdAt': createdAt,
      };

  factory NamespaceDescriptor.fromJson(Map<String, Object?> json) {
    final drivers = (json['drivers'] as Map?)?.cast<String, Object?>() ?? const {};
    return NamespaceDescriptor(
      id: (json['id'] as String?) ?? '',
      pluginId: (json['pluginId'] as String?) ?? '',
      root: (json['root'] as String?) ?? '',
      displayName: (json['displayName'] as String?) ?? '',
      schema: (json['schema'] as num?)?.toInt() ?? 1,
      state: (json['state'] as String?) ?? 'active',
      backupDriver: (drivers['backup'] as bool?) ?? true,
      trashDriver: (drivers['trash'] as bool?) ?? true,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
    );
  }

  NamespaceDescriptor copyWith({
    String? root,
    String? displayName,
    String? state,
    bool? backupDriver,
    bool? trashDriver,
  }) {
    return NamespaceDescriptor(
      id: id,
      pluginId: pluginId,
      root: root ?? this.root,
      displayName: displayName ?? this.displayName,
      schema: schema,
      state: state ?? this.state,
      backupDriver: backupDriver ?? this.backupDriver,
      trashDriver: trashDriver ?? this.trashDriver,
      createdAt: createdAt,
    );
  }
}

/// 能力（命名空间）注册的存储策略。
///
/// 实现随宿主分发；插件停用后宿主仍可依据这里声明/实现的策略
/// 操作其 trash / backup（D12）。
abstract class StorageCapability {
  String get namespaceId;
  String get pluginId;
  NamespaceDescriptor get descriptor;

  /// null = 不参与备份。
  BackupPolicy? get backupPolicy;

  /// null = 删除不可恢复。
  TrashPolicy? get trashPolicy;
}
