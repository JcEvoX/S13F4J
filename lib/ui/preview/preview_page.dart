import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:cached_network_image/cached_network_image.dart';

import '../editor/export/export_service.dart';

/// Markdown 预览页。
///
/// 覆盖常见 Markdown 元素渲染，并针对代码块、HTML、网络图片提供
/// 一定程度的支持。同时提供导出为图片 / 纯文本 / Markdown / PDF。
class PreviewPage extends StatefulWidget {
  const PreviewPage({super.key, required this.title, required this.content});

  final String title;
  final String content;

  @override
  State<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<PreviewPage> {
  final GlobalKey _renderKey = GlobalKey();
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title.isEmpty ? '预览' : widget.title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              icon: const Icon(Icons.more_vert),
              tooltip: '导出',
              onPressed: () => _showExportSheet(),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_exporting)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: RepaintBoundary(
              key: _renderKey,
              child: MarkdownBody(
                data: widget.content,
                selectable: true,
                builders: {
                  'img': _ImageBuilder(),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showExportSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('导出为图片'),
              onTap: () => _export(ExportKind.image),
            ),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: const Text('导出为纯文本 (.txt)'),
              onTap: () => _export(ExportKind.text),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('导出为 Markdown (.md)'),
              onTap: () => _export(ExportKind.markdown),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('导出为 PDF'),
              onTap: () => _export(ExportKind.pdf),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _export(ExportKind kind) async {
    Navigator.pop(context);
    setState(() => _exporting = true);
    final service = ExportService();
    try {
      await service.export(
        context,
        kind: kind,
        title: widget.title,
        content: widget.content,
        renderBoundary: kind == ExportKind.image ? _renderKey : null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导出完成')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

/// 网络图片 builder：使用缓存网络图片，节省流量（对应原「网络图片缓存」）。
class _ImageBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(
    md.Element element,
    TextStyle? preferredStyle,
  ) {
    final src = element.attributes['src'];
    if (src == null) return null;
    final isNetwork = src.startsWith('http://') || src.startsWith('https://');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: isNetwork
          ? CachedNetworkImage(
              imageUrl: src,
              fit: BoxFit.contain,
              placeholder: (_, __) => const SizedBox(
                height: 24,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              errorWidget: (_, __, ___) => const Text('图片加载失败'),
            )
          : Image.network(src, fit: BoxFit.contain, errorBuilder: (_, __, ___) {
              return Text(src);
            }),
    );
  }
}