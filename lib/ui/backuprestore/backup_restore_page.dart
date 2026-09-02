import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/note_dao.dart';
import '../../models/note.dart';
import '../../services/backup_service.dart';
import '../../services/settings_service.dart';
import '../../state/note_provider.dart';
import '../webdav/webdav_page.dart';

/// 备份和恢复页。
///
/// 对应原 Android 端的「备份和恢复」：
/// - 选择本地备份文件夹（用于自动备份）；
/// - 手动「备份到本地」与「恢复备份」；
/// - 自动备份到本地 / WebDAV 开关。
class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({super.key});

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  SettingsService? _settings;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await SettingsService.instance;
    if (!mounted) return;
    setState(() => _settings = s);
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    return Scaffold(
      appBar: AppBar(title: const Text('备份和恢复')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _folderStatusCard(s),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: const Text('本地备份文件夹'),
                  subtitle: Text(
                    s.backupFolderName ??
                        s.backupFolder ??
                        '未选择（这将影响自动备份功能）',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _pickFolder(s),
                ),
                const Divider(),
                SwitchListTile(
                  secondary: const Icon(Icons.schedule),
                  title: const Text('自动备份'),
                  subtitle: const Text('周期将数据备份到本地文件夹'),
                  value: s.autoBackupLocal,
                  onChanged: (v) {
                    s.setAutoBackupLocal(v);
                    setState(() {});
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.cloud_upload_outlined),
                  title: const Text('自动备份到 WebDAV'),
                  value: s.autoBackupToWebdav,
                  onChanged: (v) {
                    s.setAutoBackupToWebdav(v);
                    setState(() {});
                  },
                ),
                const Divider(),
                _actionTile(
                  icon: Icons.save_alt,
                  title: '备份到本地',
                  onTap: () => _backupToLocal(s),
                ),
                _actionTile(
                  icon: Icons.cloud_upload,
                  title: '备份到 WebDAV',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const WebDavPage()),
                  ),
                ),
                _actionTile(
                  icon: Icons.restore,
                  title: '恢复备份',
                  onTap: () => _restore(),
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
    );
  }

  Widget _folderStatusCard(SettingsService s) {
    final folderSet = s.backupFolder != null;
    final color = folderSet ? const Color(0xFF50D18D) : const Color(0xFFE74C3C);
    final text = folderSet
        ? '自动备份已生效，将自动备份数据到本地文件夹'
        : '还未选择本地备份文件夹，这将影响到自动备份功能';
    return Card(
      elevation: 0,
      color: color.withOpacity(0.1),
      child: ListTile(
        leading: Icon(
          folderSet ? Icons.check_circle : Icons.warning_amber,
          color: color,
        ),
        title: Text(text, style: TextStyle(color: color, fontSize: 14)),
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  /// 选择本地备份文件夹。
  Future<void> _pickFolder(SettingsService s) async {
    final dir = await BackupService.pickBackupDirectory();
    if (dir == null) return;
    await s.setBackupFolder(dir);
    await s.setBackupFolderName(dir.split(RegExp(r'[/\\]')).last);
    if (mounted) setState(() {});
  }

  /// 手动备份到本地（选择目录写入 JSON）。
  Future<void> _backupToLocal(SettingsService s) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final dir = await BackupService.pickBackupDirectory() ?? s.backupFolder;
      if (dir == null) {
        _toast('请先选择备份文件夹');
        return;
      }
      final nodes = await NoteDao().allNodes();
      final name = await BackupService.backupToDirectory(dir, nodes);
      _toast(name == null ? '备份已取消' : '备份成功：$name');
    } catch (e) {
      _toast('备份失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 从本地备份文件恢复（覆盖当前数据）。
  Future<void> _restore() async {
    if (_busy) return;
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: '备份文件', extensions: ['json']),
      ],
    );
    if (file == null) return;
    if (!mounted) return;

    List<NotePadNode> nodes;
    try {
      nodes = await BackupService.readBackupFile(file.path);
    } catch (e) {
      _toast('备份文件解析失败：$e');
      return;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复备份'),
        content: Text('确定用「${file.name}」恢复吗？将覆盖本地全部笔记数据。'),
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
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final dao = NoteDao();
      await dao.replaceAll(nodes);
      if (!mounted) return;
      await context.read<NoteProvider>().refresh();
      await context.read<NoteProvider>().loadRecycleBin();
      _toast('恢复成功');
    } catch (e) {
      _toast('恢复失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
