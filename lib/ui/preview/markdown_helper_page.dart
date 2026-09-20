import 'package:flutter/material.dart';

/// Markdown 助手页。
///
/// 对应原 Android 端的「Markdown 助手」，提供常用语法速查。
class MarkdownHelperPage extends StatelessWidget {
  const MarkdownHelperPage({super.key});

  static const _entries = <(String, String)>[
    ('# 一级标题', '行首 1~6 个 # 加空格表示标题'),
    ('**加粗**', '两侧各两个星号为粗体'),
    ('*斜体* 或 _斜体_', '两侧各一个星号或下划线为斜体'),
    ('~~删除线~~', '两侧各两个波浪号为删除线'),
    ('> 引用', '行首 > 加空格为引用块'),
    ('`代码`', '反引号包裹行内代码'),
    ('```代码块```', '三个反引号包裹多行代码块'),
    ('- 列表项', '行首 -、* 或 + 为无序列表'),
    ('1. 有序项', '数字加点加空格为有序列表'),
    ('[文字](网址)', '方括号包文字，圆括号包链接地址'),
    ('---', '三个及以上连字符为分割线'),
    ('![描述](图片地址)', '感叹号加图片语法'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Markdown 助手')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _entries.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final (code, desc) = _entries[i];
          return ListTile(
            title: Text(
              code,
              style: TextStyle(
                fontFamily: 'monospace',
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            subtitle: Text(desc,
                style:
                    TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          );
        },
      ),
    );
  }
}
