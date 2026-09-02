import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/note.dart';
import '../../state/note_provider.dart';
import '../../widgets/article_card.dart';

/// 回收站页：恢复 / 永久删除。
class RecycleBinPage extends StatefulWidget {
  const RecycleBinPage({super.key});

  @override
  State<RecycleBinPage> createState() => _RecycleBinPageState();
}

class _RecycleBinPageState extends State<RecycleBinPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NoteProvider>().loadRecycleBin();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NoteProvider>();
    final hasItems = provider.recycleNodes.isNotEmpty;
    return Scaffold(
      // 顶栏右侧「清空」按钮（对应原版 ui_recycle_bin.xml 的 tvEmpty）。
      appBar: AppBar(
        title: const Text('回收站'),
        actions: [
          if (hasItems)
            TextButton(
              onPressed: () => _clearAll(context, provider),
              child: const Text('清空'),
            ),
        ],
      ),
      body: hasItems
          ? ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: provider.recycleNodes.length,
              itemBuilder: (context, index) {
                final node = provider.recycleNodes[index];
                return ArticleCard(
                  node: node,
                  subtitle: node.isFolder ? '文件夹（含子项）' : null,
                  time: node.isFolder ? null : _timeText(node.deletedAt),
                  trailing: _moreButton(context, provider, node),
                  onTap: () => _showItemMenu(context, provider, node),
                  onLongPress: () => _showItemMenu(context, provider, node),
                );
              },
            )
          : Center(
              child: Text(
                '回收站为空',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
    );
  }

  /// more_vert：原版风格的单条目操作菜单（恢复 / 永久删除）。
  Widget _moreButton(
      BuildContext context, NoteProvider provider, NotePadNode node) {
    final dim = Theme.of(context).brightness == Brightness.dark
        ? Colors.white54
        : Colors.grey.shade600;
    return IconButton(
      icon: Icon(Icons.more_vert, size: 20, color: dim.withOpacity(0.75)),
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

  /// 清空回收站（全部永久删除）。
  Future<void> _clearAll(
      BuildContext context, NoteProvider provider) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空回收站'),
        content: const Text('将永久删除回收站中的全部项目，无法恢复。确定继续吗？'),
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
      debugPrint('[RecycleBin] 清空回收站，共 ${provider.recycleNodes.length} 项');
      await provider.purgeFromRecycle(provider.recycleNodes);
    }
  }

  String _timeText(int? ms) {
    if (ms == null) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} 删除';
  }

  Future<void> _restore(BuildContext context, NoteProvider provider, NotePadNode node) async {
    debugPrint('[RecycleBin] 恢复 nodeId=${node.id}, title=${node.title}');
    await provider.restoreFromRecycle([node]);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已恢复')),
      );
    }
  }

  Future<void> _purge(BuildContext context, NoteProvider provider, NotePadNode node) async {
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
