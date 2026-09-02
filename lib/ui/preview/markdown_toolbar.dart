import 'package:flutter/material.dart';

/// Markdown 快捷工具栏。
///
/// 还原原 Android 端 KeyboardToolbar：底部横排图标按钮，点击插入对应
/// Markdown 符号到光标处。可横向滚动，支持加粗/斜体/删除线/标题/列表/
/// 引用/行内代码/代码块/链接/图片/公式/Mermaid。
class MarkdownToolbar extends StatelessWidget {
  const MarkdownToolbar({super.key, required this.onInsert});

  /// 插入回调，参数为要插入的符号。
  final void Function(String symbol) onInsert;

  static const List<_Tool> _tools = [
    _Tool(Icons.format_bold, '加粗', '**'),
    _Tool(Icons.format_italic, '斜体', '*'),
    _Tool(Icons.format_strikethrough, '删除线', '~~'),
    _Tool(Icons.title, '标题', '# '),
    _Tool(Icons.format_list_bulleted, '无序列表', '- '),
    _Tool(Icons.format_list_numbered, '有序列表', '1. '),
    _Tool(Icons.format_quote, '引用', '> '),
    _Tool(Icons.code, '行内代码', '`'),
    _Tool(Icons.integration_instructions, '代码块', '```\n'),
    _Tool(Icons.link, '链接', '['),
    _Tool(Icons.image, '图片', '!['),
    _Tool(Icons.functions, '公式', '\$\$'),
    _Tool(Icons.account_tree, 'Mermaid 图', '```mermaid\n'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark ? Colors.white70 : const Color(0xFF191B23);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: isDark
            ? Theme.of(context).colorScheme.surfaceContainerHighest
                .withOpacity(0.3)
            : const Color(0x80FFFFFF),
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white12 : Colors.black12,
            width: 0.5,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            for (final t in _tools)
              IconButton(
                icon: Icon(t.icon, size: 20, color: iconColor),
                tooltip: t.label,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: () => onInsert(t.open),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tool {
  const _Tool(this.icon, this.label, this.open);

  final IconData icon;

  /// 无障碍标签 / 长按提示。
  final String label;

  /// 插入的起始符号。
  final String open;
}
