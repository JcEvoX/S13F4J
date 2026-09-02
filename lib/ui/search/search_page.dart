import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/note.dart';
import '../../state/note_provider.dart';
import '../../widgets/article_card.dart';
import '../editor/editor_page.dart';

/// 关键词搜索页。
///
/// 还原原版 SearchActivity（ui_search.xml）：
/// - 顶栏为圆角搜索框（左侧放大镜图标）+ 右侧「取消」按钮
/// - 搜索结果复用 recycler_article 卡片样式
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  bool _searched = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NoteProvider>();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
          child: _buildSearchField(context),
        ),
        actions: [
          // 原版 tvCancel：「取消」关闭搜索。
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _buildBody(provider.searchResults),
    );
  }

  /// 圆角搜索框（原版 etSearch：白/半透明白圆角底 + 左侧放大镜）。
  Widget _buildSearchField(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0x1FFFFFFF) : const Color(0x33FFFFFF),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search,
            size: 20,
            color: Theme.of(context).hintColor,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                hintText: '搜索文章标题 / 内容',
                isCollapsed: true,
                border: InputBorder.none,
              ),
              onChanged: (v) {
                _searched = true;
                context.read<NoteProvider>().search(v);
              },
            ),
          ),
          // 有输入时显示清除按钮。
          if (_controller.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _controller.clear();
                _searched = false;
                context.read<NoteProvider>().search('');
              },
              child: Icon(
                Icons.cancel,
                size: 18,
                color: Theme.of(context).hintColor,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(List<NotePadNode> results) {
    if (!_searched) {
      return Center(
        child: Text(
          '输入关键词开始搜索',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }
    if (results.isEmpty) {
      return Center(
        child: Text(
          '未找到相关内容',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final node = results[index];
        return ArticleCard(
          node: node,
          time: node.isFolder ? null : _timeText(node.updatedAt),
          trailing: Icon(
            Icons.chevron_right,
            size: 20,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white54
                : Colors.grey.shade600,
          ),
          onTap: () {
            if (node.isFolder) {
              context.read<NoteProvider>().openFolder(node);
              Navigator.pop(context);
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => EditorPage(nodeId: node.id)),
              );
            }
          },
        );
      },
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
