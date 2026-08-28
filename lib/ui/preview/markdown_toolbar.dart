import 'package:flutter/material.dart';

/// Markdown 快捷工具栏。
///
/// 提供常用 Markdown 符号的快速插入，可横向滚动。对应原 Android
/// 端「双层工具栏快捷 Markdown 相关符号输入」能力。
class MarkdownToolbar extends StatelessWidget {
  const MarkdownToolbar({super.key, required this.onInsert});

  /// 插入回调，参数为要插入的符号。
  final void Function(String symbol) onInsert;

  static const List<_Tool> _tools = [
    _Tool('B', '**', '**'),
    _Tool('I', '*', '*'),
    _Tool('#', '# ', null),
    _Tool('H2', '## ', null),
    _Tool('H3', '### ', null),
    _Tool('•', '- ', null),
    _Tool('1.', '1. ', null),
    _Tool('>', '> ', null),
    _Tool('` 代码 `', '```\n', '\n```'),
    _Tool('链接', '[', '](https://)'),
    _Tool('图片', '![', '](https://)'),
    _Tool('~~', '~~', '~~'),
    _Tool('= 公式 =', '\$\$', '\$\$'),
    _Tool('{mermaid}', '```mermaid\n', '\n```'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.3),
        border: Border(top: BorderSide(color: Colors.grey.shade300, width: 0.4)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            for (final t in _tools)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: ActionChip(
                  label: Text(t.label, style: const TextStyle(fontSize: 12)),
                  onPressed: () => onInsert(t.open),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tool {
  const _Tool(this.label, this.open, this.close);

  final String label;
  final String open;
  final String? close;
}