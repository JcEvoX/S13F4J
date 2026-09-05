import 'package:flutter/material.dart';

import '../../data/note_dao.dart';
import '../../models/note.dart';
import '../../widgets/article_card.dart';
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
    debugPrint('[Recent] 加载最近编辑文章');
    final items = await NoteDao().recentArticles();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
    debugPrint('[Recent] 加载完成: ${items.length} 篇');
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
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _items.length,
                    itemBuilder: (ctx, i) => _buildCard(ctx, _items[i]),
                  ),
                ),
    );
  }

  Widget _buildCard(BuildContext context, NotePadNode node) {
    return ArticleCard(
      node: node,
      time: _timeText(node.updatedAt),
      trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => EditorPage(nodeId: node.id)),
      ),
    );
  }

  String _timeText(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    if (day == today) return '今天 $hh:$mm';
    if (day == today.subtract(const Duration(days: 1))) return '昨天 $hh:$mm';
    if (dt.year == now.year) return '${dt.month}月${dt.day}日 $hh:$mm';
    return '${dt.year}年${dt.month}月${dt.day}日';
  }
}
