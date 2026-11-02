import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/backup_center.dart';
import '../../state/note_provider.dart';

/// 备份中心：按命名空间列出快照，支持立即快照 / 恢复 / 删除，以及整机备份。
class NamespaceBackupPage extends StatefulWidget {
  const NamespaceBackupPage({super.key});

  @override
  State<NamespaceBackupPage> createState() => _NamespaceBackupPageState();
}

class _NamespaceBackupPageState extends State<NamespaceBackupPage> {
  List<NamespaceSource>? _sources;
  final Map<String, List<BackupSnapshot>> _snapshots = {};
  final Map<String, int> _usage = {};
  List<BackupSnapshot> _appSnapshots = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final center = BackupCenter.instance;
    final sources = await center.namespaceSources();
    for (final source in sources) {
      _snapshots[source.id] =
          await center.listSnapshots(namespaceId: source.id);
      _usage[source.id] = await center.usageBytes(source.rootPath);
    }
    final appSnapshots = await center.listSnapshots(
      namespaceId: 'all',
      appWide: true,
    );
    if (!mounted) return;
    setState(() {
      _sources = sources;
      _appSnapshots = appSnapshots;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sources = _sources;
    return Scaffold(
      appBar: AppBar(title: const Text('备份中心')),
      body: sources == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _sectionTitle('命名空间'),
                  for (final source in sources) _buildNamespaceCard(source),
                  const SizedBox(height: 20),
                  _sectionTitle('整机备份'),
                  _buildAppCard(sources),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );

  Widget _buildNamespaceCard(NamespaceSource source) {
    final snapshots = _snapshots[source.id] ?? const [];
    final latest = snapshots.isEmpty ? null : snapshots.first;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.layers_outlined, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    source.displayName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : () => _snapshotNamespace(source),
                  icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                  label: const Text('立即快照'),
                ),
              ],
            ),
            Text(
              '${_sizeLabel(_usage[source.id] ?? 0)} · '
              '${snapshots.length} 个快照'
              '${latest == null ? '' : ' · 最近 ${latest.timeLabel}'}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            if (snapshots.isNotEmpty) ...[
              const Divider(height: 20),
              for (final snapshot in snapshots)
                _snapshotTile(
                  snapshot,
                  onRestore: () => _restore(snapshot, source),
                  onDelete: () => _delete(snapshot),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAppCard(List<NamespaceSource> sources) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.devices_other, size: 22),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    '整机备份',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : () => _snapshotApp(sources),
                  icon: const Icon(Icons.backup_outlined, size: 18),
                  label: const Text('立即备份'),
                ),
              ],
            ),
            Text(
              '包含全部命名空间，恢复时按命名空间逐个执行。',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            if (_appSnapshots.isNotEmpty) ...[
              const Divider(height: 20),
              for (final snapshot in _appSnapshots)
                _snapshotTile(
                  snapshot,
                  onRestore: null,
                  onDelete: () => _delete(snapshot),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _snapshotTile(
    BackupSnapshot snapshot, {
    VoidCallback? onRestore,
    required VoidCallback onDelete,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.archive_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(snapshot.timeLabel, style: const TextStyle(fontSize: 13)),
                Text(
                  '${_sizeLabel(snapshot.totalBytes)} · ${snapshot.fileCount} 个文件',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '恢复',
            onPressed: _busy ? null : onRestore,
            icon: const Icon(Icons.restore, size: 20),
          ),
          IconButton(
            tooltip: '删除',
            onPressed: _busy ? null : onDelete,
            icon: Icon(
              Icons.delete_outline,
              size: 20,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _snapshotNamespace(NamespaceSource source) async {
    setState(() => _busy = true);
    try {
      final snapshot = await BackupCenter.instance.snapshotNamespace(
        namespaceId: source.id,
        displayName: source.displayName,
        rootPath: source.rootPath,
      );
      _toast('快照完成：${snapshot.fileName}');
      await _load();
    } catch (e) {
      _toast('快照失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _snapshotApp(List<NamespaceSource> sources) async {
    setState(() => _busy = true);
    try {
      final snapshot = await BackupCenter.instance.snapshotApp(sources);
      _toast('整机备份完成：${snapshot.fileName}');
      await _load();
    } catch (e) {
      _toast('整机备份失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(
    BackupSnapshot snapshot,
    NamespaceSource source,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复快照'),
        content: Text(
          '将用 ${snapshot.timeLabel} 的快照覆盖「${source.displayName}」全部内容。\n'
          '旧数据会先备份到 staging，失败时自动回滚。确定继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await BackupCenter.instance.restoreNamespace(
        snapshot,
        targetRoot: source.rootPath,
        namespaceId: source.id,
      );
      if (!mounted) return;
      await context.read<NoteProvider>().reloadFromDisk();
      if (!mounted) return;
      _toast('恢复完成');
    } catch (e) {
      _toast('恢复失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(BackupSnapshot snapshot) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除快照'),
        content: Text('确定删除 ${snapshot.fileName} 吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await BackupCenter.instance.deleteSnapshot(snapshot);
    await _load();
  }

  static String _sizeLabel(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
