import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/note.dart';
import '../../state/note_provider.dart';
import '../../widgets/node_icon.dart';
import '../editor/editor_page.dart';

/// 关键词搜索页。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();

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
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '搜索文章标题 / 内容',
            border: InputBorder.none,
          ),
          onChanged: (v) => context.read<NoteProvider>().search(v),
        ),
      ),
      body: _buildResults(provider.searchResults),
    );
  }

  Widget _buildResults(List<SaltNode> results) {
    if (results.isEmpty) {
      return Center(
        child: Text(
          '输入关键词开始搜索',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final node = results[index];
        return ListTile(
          leading: Icon(nodeIcon(node)),
          title: Text(node.title.isEmpty ? '未命名' : node.title),
          subtitle: Text(
            node.isFolder ? '文件夹' : node.content,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
}