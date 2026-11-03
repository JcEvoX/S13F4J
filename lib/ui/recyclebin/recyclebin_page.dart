import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/notes_repository.dart';
import '../../data/vault/vault_store.dart';
import '../../models/note.dart';
import '../../services/namespace_registry.dart';
import '../../services/storage_paths.dart';
import '../../state/note_provider.dart';
import '../../widgets/article_card.dart';

/// 回收站页：按来源聚合，支持恢复 / 永久删除 / 清空。
class RecycleBinPage extends StatefulWidget {
  const RecycleBinPage({super.key});

  @override
  State<RecycleBinPage> createState() => _RecycleBinPageState();
}

class _RecycleBinPageState extends State<RecycleBinPage> {
  /// 当前来源过滤（null 表示全部）。
  String? _namespaceFilter;

  /// 已停用能力的命名空间 id（停用后数据仍展示，标签加「已停用」）。
  Set<String> _disabledNamespaces = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NoteProvider>().loadRecycleBin();
      _loadNamespaceStates();
    });
  }

  Future<void> _loadNamespaceStates() async {
    try {
      final paths = await StoragePaths.resolve();
      final registry = NamespaceRegistry(store: VaultStore(paths.vaultRoot));
      await registry.load();
      final list = await registry.all();
      final disabled = {
        for (final item in list)
          if (item.state != 'active') item.id,
      };
      if (!mounted) return;
      setState(() => _disabledNamespaces = disabled);
    } catch (_) {
      // 注册表不可读不影响回收站展示。
    }
  }

  String _sourceLabel(String namespaceId, String displayName) {
    return _disabledNamespaces.contains(namespaceId)
        ? '$displayName（已停用）'
        : displayName;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NoteProvider>();
    final entries = provider.recycleEntries;
    final namespaces = <String, String>{
      for (final e in entries) e.namespaceId: e.displayName,
    };
    final filter =
        namespaces.containsKey(_namespaceFilter) ? _namespaceFilter : null;
    final filtered = filter == null
        ? entries
        : entries.where((e) => e.namespaceId == filter).toList();
    final hasItems = filtered.isNotEmpty;

    return Scaffold(
      // 顶栏右侧「清空」按钮。
      appBar: AppBar(
        title: const Text('回收站'),
        actions: [
          if (hasItems)
            TextButton(
              onPressed: () => _clearAll(context, provider, filtered),
              child: const Text('清空'),
            ),
        ],
      ),
      body: entries.isEmpty
          ? Center(
              child: Text(
                '回收站为空',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            )
          : Column(
              children: [
                // 多来源时按能力分组；单来源时仅显示条目来源标签。
                if (namespaces.length > 1) _buildSourceFilter(namespaces),
                Expanded(
                  child: hasItems
                      ? ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final entry = filtered[index];
                            final node = entry.toNode();
                            return ArticleCard(
                              node: node,
                              subtitle:
                                  '${_sourceLabel(entry.namespaceId, entry.displayName)} · '
                                  '${node.isFolder ? '文件夹（含子项）' : '文章'}',
                              time: node.isFolder
                                  ? null
                                  : _timeText(node.deletedAt),
                              trailing:
                                  _moreButton(context, provider, node),
                              onTap: () =>
                                  _showItemMenu(context, provider, node),
                              onLongPress: () =>
                                  _showItemMenu(context, provider, node),
                            );
                          },
                        )
                      : Center(
                          child: Text(
                            '当前来源下暂无项目',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  /// 来源过滤条：全部 / 各命名空间。
  Widget _buildSourceFilter(Map<String, String> namespaces) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('全部'),
            selected: _namespaceFilter == null,
            onSelected: (_) => setState(() => _namespaceFilter = null),
          ),
          const SizedBox(width: 8),
          for (final entry in namespaces.entries) ...[
            ChoiceChip(
              label: Text(_sourceLabel(entry.key, entry.value)),
              selected: _namespaceFilter == entry.key,
              onSelected: (_) => setState(() => _namespaceFilter = entry.key),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  /// more_vert：单条目操作菜单（恢复 / 永久删除）。
  Widget _moreButton(
      BuildContext context, NoteProvider provider, NotePadNode node) {
    final dim = Theme.of(context).brightness == Brightness.dark
        ? Colors.white54
        : Colors.grey.shade600;
    return IconButton(
      icon: Icon(Icons.more_vert, size: 20, color: dim.withValues(alpha: 0.75)),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      visualDensity: VisualDensity.compact,
      onPressed: () => _showItemMenu(context, provider, node),
    );
  }

  Future<void> _showItemMenu(
      BuildContext context, NoteProvider provider, NotePadNode node) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('恢复'),
              onTap: () => Navigator.pop(ctx, 'restore'),
            ),
            ListTile(
              leading: Icon(Icons.delete_forever,
                  color: Theme.of(ctx).colorScheme.error),
              title: Text('永久删除',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () => Navigator.pop(ctx, 'purge'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'restore') {
      await _restore(context, provider, node);
    } else {
      await _purge(context, provider, node);
    }
  }

  /// 清空当前过滤范围内的项目（全部或单来源）。
  Future<void> _clearAll(BuildContext context, NoteProvider provider,
      List<ScopedTrashEntry> targets) async {
    final scope = _namespaceFilter == null ? '回收站' : '当前来源';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空回收站'),
        content: Text('将永久删除$scope下的 ${targets.length} 个项目，无法恢复。确定继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true) {
      debugPrint('[RecycleBin] 清空回收站，共 ${targets.length} 项');
      await provider.purgeFromRecycle(targets.map((e) => e.toNode()).toList());
    }
  }

  String _timeText(int? ms) {
    if (ms == null) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} 删除';
  }

  Future<void> _restore(
      BuildContext context, NoteProvider provider, NotePadNode node) async {
    debugPrint('[RecycleBin] 恢复 nodeId=${node.id}, title=${node.title}');
    await provider.restoreFromRecycle([node]);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已恢复')),
      );
    }
  }

  Future<void> _purge(
      BuildContext context, NoteProvider provider, NotePadNode node) async {
    debugPrint('[RecycleBin] 永久删除确认 nodeId=${node.id}, title=${node.title}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('永久删除'),
        content: const Text('删除后无法恢复，确定继续吗？'),
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
    if (ok == true) {
      debugPrint('[RecycleBin] 确认永久删除 nodeId=${node.id}');
      await provider.purgeFromRecycle([node]);
    }
  }
}
