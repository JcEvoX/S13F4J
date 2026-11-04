import 'package:flutter/material.dart';

import '../../core/capability.dart';
import '../../plugins/plugin_manager.dart';
import '../../plugins/plugin_model.dart';
import '../backuprestore/backup_restore_page.dart';
import '../plugins/plugin_center_page.dart';
import '../recyclebin/recyclebin_page.dart';
import '../settings/settings_page.dart';

/// 笔记能力停用后的首页：按已启用插件展示能力入口。
///
/// 数据不受影响：备份 / 回收站入口始终保留，重新启用笔记插件后
/// 首页自动回到文件列表（D9 / D12）。
class CapabilityHomePage extends StatelessWidget {
  const CapabilityHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = PluginManager.instance;
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final enabled = manager.enabledPlugins;
        return Scaffold(
          appBar: AppBar(
            title: const Text('NotePad'),
            actions: [
              IconButton(
                tooltip: '设置',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => _push(context, const SettingsPage()),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _DisabledBanner(),
              const SizedBox(height: 16),
              if (enabled.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('当前没有启用的能力')),
                )
              else
                for (final plugin in enabled) _PluginTile(plugin: plugin),
              const SizedBox(height: 8),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.widgets_outlined),
                title: const Text('插件中心'),
                subtitle: const Text('重新启用笔记，或安装其它能力'),
                onTap: () => _push(context, const PluginCenterPage()),
              ),
              ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: const Text('备份和恢复'),
                subtitle: const Text('已停用能力的数据仍可快照与恢复'),
                onTap: () => _push(context, const BackupRestorePage()),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('回收站'),
                subtitle: const Text('已停用能力的已删除内容仍可恢复'),
                onTap: () => _push(context, const RecycleBinPage()),
              ),
            ],
          ),
        );
      },
    );
  }

  static void _push(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }
}

class _DisabledBanner extends StatelessWidget {
  const _DisabledBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: scheme.onSecondaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '笔记能力已停用，数据不会被删除。在插件中心重新启用后，文件列表会自动恢复。',
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _PluginTile extends StatelessWidget {
  const _PluginTile({required this.plugin});

  final InstalledPlugin plugin;

  @override
  Widget build(BuildContext context) {
    final manifest = plugin.manifest;
    return Card(
      child: ListTile(
        leading: Icon(pluginIcon(manifest.icon)),
        title: Text(manifest.name),
        subtitle: Text(manifest.description),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final capability = capabilities[manifest.capability];
          if (capability == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('该插件所需能力未注册')),
            );
            return;
          }
          await capability.launch(context, manifest);
        },
      ),
    );
  }
}
