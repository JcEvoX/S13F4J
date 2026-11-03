import 'package:flutter/material.dart';

import 'file_browser_page.dart';

/// 只读文件查看页（外部单文件 / 项目内文件共用）。
///
/// 默认只读；「另存为笔记」是唯一写入笔记库的动作。
class ReadOnlyFilePage extends StatelessWidget {
  const ReadOnlyFilePage({
    super.key,
    required this.title,
    required this.sourceLabel,
    this.content,
    this.error,
    this.size = 0,
  });

  final String title;
  final String sourceLabel;
  final String? content;
  final String? error;
  final int size;

  @override
  Widget build(BuildContext context) {
    final text = content;
    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (text != null)
            IconButton(
              tooltip: '另存为笔记',
              onPressed: () => saveTextAsNote(
                context,
                title: title,
                content: text,
              ),
              icon: const Icon(Icons.note_add_outlined),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Text(
                  sourceLabel,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const Spacer(),
                if (text != null)
                  Text(
                    '${_sizeLabel(size)} · 只读',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 40,
                            color: Colors.grey.shade500,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('返回'),
                          ),
                        ],
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      text ?? '',
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.7,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  static String _sizeLabel(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
