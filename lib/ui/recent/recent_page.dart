import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/note_dao.dart';
import '../../models/note.dart';
import '../editor/editor_page.dart';

/// 最近编辑的文章页。
///
/// 对应原 Android 端的「最近编辑的文章」，按更新时间倒序展示
/// 未回收的文章，点击进入编辑器。
class RecentPage extends StatefulWidget {
  const RecentPage({super.key});

  @override
  State<RecentPage> createState() => _RecentPageState();
}

class _RecentPageState extends State<RecentPage> {
  List<NotePadNode> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await NoteDao().recentArticles();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('最近编辑的文章')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('暂无最近编辑的文章'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) => _buildTile(ctx, _items[i]),
                  ),
                ),
    );
  }

  Widget _buildTile(BuildContext context, NotePadNode node) {
    final time = DateFormat('MM-dd HH:mm')
        .format(DateTime.fromMillisecondsSinceEpoch(node.updatedAt));
    final preview = node.content.trim().split('\n').first;
    return ListTile(
      leading: const Icon(Icons.description_outlined),
      title: Text(
        node.title.isEmpty ? '未命名文章' : node.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: preview.isEmpty
          ? Text('更新于 $time',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600))
          : Text(
              preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
      trailing: Text(time,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => EditorPage(nodeId: node.id)),
      ),
    );
  }
}
