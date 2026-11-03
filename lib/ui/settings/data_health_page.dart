import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/storage/storage_capability.dart';
import '../../data/vault/vault_store.dart';
import '../../services/backup_center.dart';
import '../../services/namespace_registry.dart';
import '../../services/storage_paths.dart';
import '../../state/note_provider.dart';
import '../backuprestore/backup_restore_page.dart';

/// 单个命名空间的健康快照。
class _NamespaceHealth {
  const _NamespaceHealth({
    required this.id,
    required this.displayName,
    required this.pluginId,
    required this.state,
    required this.rootPath,
    required this.rootExists,
    required this.usageBytes,
    required this.backupCount,
    required this.backupBytes,
    required this.lastBackupAt,
    required this.backupDriver,
    required this.trashDriver,
  });

  final String id;
  final String displayName;
  final String pluginId;
  final String state;
  final String rootPath;
  final bool rootExists;
  final int usageBytes;
  final int backupCount;
  final int backupBytes;
  final int? lastBackupAt;
  final bool backupDriver;
  final bool trashDriver;

  String get stateLabel => switch (state) {
        'disabled' => '已停用',
        'missing' => '缺失',
        _ => '正常',
      };
}

/// 数据占用与健康：各命名空间占用、快照数量、注册表状态、恢复残留。
class DataHealthPage extends StatefulWidget {
  const DataHealthPage({super.key});

  @override
  State<DataHealthPage> createState() => _DataHealthPageState();
}

class _DataHealthPageState extends State<DataHealthPage> {
  List<_NamespaceHealth>? _items;
  List<String> _pendingStaging = const [];
  int _stagingBytes = 0;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final paths = await StoragePaths.resolve();
      final registry = NamespaceRegistry(store: VaultStore(paths.vaultRoot));
      await registry.load();
      await registry.ensureNotes();
      final descriptors = await registry.all();
      final items = <_NamespaceHealth>[];
      for (final item in descriptors) {
        items.add(await _inspect(paths, item));
      }
      final staging = await BackupCenter.instance.pendingStaging();
      var stagingBytes = 0;
      for (final name in staging) {
        stagingBytes += await BackupCenter.instance.usageBytes(
          p.join(paths.appDataRoot, 'staging', name),
        );
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _pendingStaging = staging;
        _stagingBytes = stagingBytes;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _error = '读取数据健康信息失败：$e';
      });
    }
  }

  Future<_NamespaceHealth> _inspect(
    StoragePaths paths,
    NamespaceDescriptor descriptor,
  ) async {
    final rootPath = _resolveRoot(paths, descriptor.root);
    final rootExists = await Directory(rootPath).exists();
    final usage = rootExists
        ? await BackupCenter.instance.usageBytes(rootPath)
        : 0;
    final snapshots = await BackupCenter.instance.listSnapshots(
      namespaceId: descriptor.id,
    );
    final backupBytes = await BackupCenter.instance.usageBytes(
      await BackupCenter.instance.backupDir(descriptor.id),
    );
    return _NamespaceHealth(
      id: descriptor.id,
      displayName:
          descriptor.displayName.isEmpty ? descriptor.id : descriptor.displayName,
      pluginId: descriptor.pluginId,
      state: descriptor.state,
      rootPath: rootPath,
      rootExists: rootExists,
      usageBytes: usage,
      backupCount: snapshots.length,
      backupBytes: backupBytes,
      lastBackupAt: snapshots.isEmpty ? null : snapshots.first.createdAt,
      backupDriver: descriptor.backupDriver,
      trashDriver: descriptor.trashDriver,
    );
  }

  static String _resolveRoot(StoragePaths paths, String root) {
    if (root.isEmpty) return paths.vaultRoot;
    if (p.isAbsolute(root)) return root;
    return p.join(paths.vaultRoot, root);
  }

  Future<void> _clearStaging() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理恢复残留'),
        content: Text(
          '将删除上次恢复中断留下的 ${_pendingStaging.length} 个临时目录'
          '（${_sizeLabel(_stagingBytes)}）。\n'
          '这不会影响现有数据与已完成的快照。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await BackupCenter.instance.clearPendingStaging();
      await _load();
      _toast('已清理恢复残留');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rebuildNotes() async {
    setState(() => _busy = true);
    try {
      await context.read<NoteProvider>().reloadFromDisk();
      await _load();
      _toast('已从磁盘重建笔记索引');
    } catch (e) {
      _toast('重建失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(
        title: const Text('数据占用与健康'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: items == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      _buildSummary(items),
                      const SizedBox(height: 16),
                      _sectionTitle('命名空间'),
                      for (final item in items) _buildNamespaceCard(item),
                      if (_pendingStaging.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _sectionTitle('恢复残留'),
                        _buildStagingCard(),
                      ],
                      const SizedBox(height: 16),
                      _sectionTitle('维护'),
                      _buildMaintenanceCard(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(List<_NamespaceHealth> items) {
    final usage = items.fold<int>(0, (sum, item) => sum + item.usageBytes);
    final backups = items.fold<int>(0, (sum, item) => sum + item.backupBytes);
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            _metric('数据占用', _sizeLabel(usage)),
            _metric('备份占用', _sizeLabel(backups)),
            _metric('命名空间', '${items.length} 个'),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value) {
    final dim = Colors.grey.shade600;
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 12, color: dim)),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );

  Widget _buildNamespaceCard(_NamespaceHealth item) {
    final scheme = Theme.of(context).colorScheme;
    final healthy = item.rootExists && item.state == 'active';
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  healthy ? Icons.check_circle_outline : Icons.error_outline,
                  size: 20,
                  color: healthy ? scheme.primary : Colors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _tag(item.stateLabel),
              ],
            ),
            const SizedBox(height: 8),
            _row('命名空间', item.id),
            _row('插件', item.pluginId),
            _row('数据占用', _sizeLabel(item.usageBytes)),
            _row(
              '备份',
              item.backupDriver
                  ? '${item.backupCount} 份 · ${_sizeLabel(item.backupBytes)}'
                      '${item.lastBackupAt == null ? '' : ' · 最近 ${_timeLabel(item.lastBackupAt!)}'}'
                  : '不参与备份',
            ),
            _row('回收站', item.trashDriver ? '可用' : '不提供'),
            _row(
              '根目录',
              item.rootExists ? item.rootPath : '不可用（${item.rootPath}）',
              dim: item.rootExists,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStagingCard() {
    final dim = Colors.grey.shade600;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const Icon(Icons.warning_amber_outlined, color: Colors.orange),
        title: Text('检测到 ${_pendingStaging.length} 个恢复中断残留'),
        subtitle: Text(
          '${_sizeLabel(_stagingBytes)} · 清理不会影响现有数据',
          style: TextStyle(fontSize: 12, color: dim),
        ),
        trailing: TextButton(
          onPressed: _busy ? null : _clearStaging,
          child: const Text('清理'),
        ),
      ),
    );
  }

  Widget _buildMaintenanceCard() {
    final dim = Colors.grey.shade600;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.manage_search_outlined),
            title: const Text('重建笔记索引'),
            subtitle: Text(
              '从磁盘重新扫描 tree.json 与正文，不影响内容',
              style: TextStyle(fontSize: 12, color: dim),
            ),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: _busy ? null : _rebuildNotes,
          ),
          const Divider(height: 1, indent: 56, endIndent: 12),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('备份和恢复'),
            subtitle: Text(
              '查看各命名空间快照与恢复入口',
              style: TextStyle(fontSize: 12, color: dim),
            ),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: _busy
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const BackupRestorePage(),
                      ),
                    ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool dim = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: dim ? Colors.grey.shade600 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(String label) {
    final color = switch (label) {
      '正常' => Colors.green,
      '已停用' => Colors.grey,
      _ => Colors.orange,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: color)),
    );
  }

  static String _sizeLabel(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  static String _timeLabel(int millis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
