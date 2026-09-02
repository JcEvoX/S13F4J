import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/note.dart';
import '../../state/note_provider.dart';
import '../../widgets/node_icon.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('回收站')),
      body: provider.recycleNodes.isEmpty
          ? Center(
              child: Text(
                '回收站为空',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            )
          : ListView.builder(
              itemCount: provider.recycleNodes.length,
              itemBuilder: (context, index) {
                final node = provider.recycleNodes[index];
                return ListTile(
                  leading: Icon(nodeIcon(node)),
                  title: Text(node.title.isEmpty ? '未命名' : node.title),
                  subtitle: Text(
                    node.isFolder ? '文件夹（含子项）' : _timeText(node.deletedAt),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.restore),
                        tooltip: '恢复',
                        onPressed: () =>
                            _restore(context, provider, node),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_forever),
                        tooltip: '永久删除',
                        onPressed: () =>
                            _purge(context, provider, node),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
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