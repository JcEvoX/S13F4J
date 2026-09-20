import 'package:flutter/material.dart';

import '../../core/capability.dart';
import '../../plugins/plugin_manager.dart';
import '../../plugins/plugin_model.dart';
import '../../plugins/plugin_store.dart';
import '../../services/settings_service.dart';

/// 插件中心：管理已安装插件（热插拔开关/卸载）与插件市场（从 GitHub 下载安装）。
class PluginCenterPage extends StatefulWidget {
  const PluginCenterPage({super.key});

  @override
  State<PluginCenterPage> createState() => _PluginCenterPageState();
}

class _PluginCenterPageState extends State<PluginCenterPage> {
  final PluginManager _manager = PluginManager.instance;

  bool _loadingMarket = false;
  String? _marketError;
  List<MarketPlugin>? _market;
  String _source = PluginStore.defaultSource;

  @override
  void initState() {
    super.initState();
    _manager.addListener(_onManagerChanged);
    _init();
  }

  Future<void> _init() async {
    final settings = await SettingsService.instance;
    if (!mounted) return;
    setState(() => _source = settings.pluginSource);
    await _loadMarket();
  }

  @override
  void dispose() {
    _manager.removeListener(_onManagerChanged);
    super.dispose();
  }

  void _onManagerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _editSource() async {
    final controller = TextEditingController(text: _source);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('插件源'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'GitHub 仓库（owner/repo）',
            hintText: '如 JcEvoX/S13F4J-plugins',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    final settings = await SettingsService.instance;
    await settings.setPluginSource(result);
    if (!mounted) return;
    setState(() => _source = result);
    await _loadMarket();
  }

  Future<void> _loadMarket() async {
    setState(() {
      _loadingMarket = true;
      _marketError = null;
    });
    try {
      final list = await PluginStore.fetchMarket(_source);
      if (!mounted) return;
      setState(() {
        _market = list;
        _loadingMarket = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _marketError = '$e';
        _loadingMarket = false;
      });
    }
  }

  Future<void> _install(MarketPlugin item) async {
    try {
      final bytes = await PluginStore.download(Uri.parse(item.downloadUrl));
      await _manager.installFromZip(bytes, downloadUrl: item.downloadUrl);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已安装插件 ${item.name}')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _marketError = '安装失败：$e');
    }
  }

  Future<void> _launch(InstalledPlugin plugin) async {
    final cap = capabilities[plugin.manifest.capability];
    if (cap == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该插件所需能力未注册')),
      );
      return;
    }
    await cap.launch(context, plugin.manifest);
  }

  Future<void> _confirmUninstall(InstalledPlugin plugin) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('卸载「${plugin.manifest.name}」？'),
        content: const Text('卸载后需重新从市场下载安装。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _manager.uninstall(plugin.manifest.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('插件中心'),
          actions: [
            IconButton(
              tooltip: '插件源',
              icon: const Icon(Icons.settings_ethernet),
              onPressed: _editSource,
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: '已安装'),
              Tab(text: '插件市场'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildInstalled(),
            _buildMarket(),
          ],
        ),
      ),
    );
  }

  Widget _buildInstalled() {
    final plugins = _manager.plugins;
    if (plugins.isEmpty) {
      return const Center(child: Text('暂无已安装插件'));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: plugins.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, i) {
        final p = plugins[i];
        return ListTile(
          leading: Icon(pluginIcon(p.manifest.icon), color: Colors.blueAccent),
          title: Row(
            children: [
              Flexible(child: Text(p.manifest.name)),
              if (p.manifest.builtin) ...[
                const SizedBox(width: 6),
                const Chip(
                  label: Text('内置', style: TextStyle(fontSize: 10)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ],
          ),
          subtitle: Text(
            '${p.manifest.description}\nv${p.manifest.version} · ${p.manifest.capability}',
          ),
          isThreeLine: true,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!p.manifest.builtin)
                IconButton(
                  tooltip: '卸载',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmUninstall(p),
                ),
              Switch(
                value: p.enabled,
                onChanged: (v) => _manager.setEnabled(p.manifest.id, v),
              ),
            ],
          ),
          onTap: p.enabled ? () => _launch(p) : null,
          enabled: p.enabled,
        );
      },
    );
  }

  Widget _buildMarket() {
    if (_loadingMarket) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_marketError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_marketError!, textAlign: TextAlign.center),
            ),
            OutlinedButton.icon(
              onPressed: _loadMarket,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    final market = _market;
    if (market == null || market.isEmpty) {
      return const Center(child: Text('插件市场暂无可用插件'));
    }
    return Column(
      children: [
        ListTile(
          dense: true,
          leading: const Icon(Icons.cloud_outlined, size: 20),
          title: const Text('插件源', style: TextStyle(fontSize: 13)),
          subtitle: Text(
            _source,
            style: const TextStyle(fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.edit_outlined, size: 18),
          onTap: _editSource,
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: market.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, i) {
              final item = market[i];
              // 按下载地址精确判断：同名/同能力但不同源的插件不算已安装。
              final installed = _manager.plugins
                  .any((p) => p.downloadUrl == item.downloadUrl);
              return ListTile(
                leading: const Icon(Icons.inventory_2_outlined,
                    color: Colors.green),
                title: Text(item.name),
                subtitle: Text('${item.releaseName} · ${_sizeLabel(item.size)}'),
                trailing: installed
                    ? const Text('已安装', style: TextStyle(color: Colors.green))
                    : FilledButton.tonal(
                        onPressed: () => _install(item),
                        child: const Text('安装'),
                      ),
              );
            },
          ),
        ),
      ],
    );
  }

  static String _sizeLabel(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
