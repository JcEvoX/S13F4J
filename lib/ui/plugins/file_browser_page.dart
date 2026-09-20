import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// 文件系统读取插件入口（能力 `file.browser`）。
///
/// 使用系统文件选择器（SAF）打开本地文件，读取文本内容并展示预览。
/// 不申请存储权限、不遍历目录，iOS / Android 均可过审。
class FileBrowserPage extends StatefulWidget {
  const FileBrowserPage({super.key});

  @override
  State<FileBrowserPage> createState() => _FileBrowserPageState();
}

class _FileBrowserPageState extends State<FileBrowserPage> {
  bool _loading = false;
  String? _fileName;
  String? _content;
  String? _error;

  Future<void> _pick() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.isEmpty) {
        if (!mounted) return;
        setState(() => _loading = false);
        return;
      }
      final file = result.files.single;
      final path = file.path;
      if (path == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = '无法访问该文件（未返回路径）。';
        });
        return;
      }
      final content = await File(path).readAsString();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _fileName = file.name;
        _content = content;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '读取失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('文件系统')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: _loading ? null : _pick,
              icon: const Icon(Icons.folder_open),
              label: const Text('选择文件'),
            ),
          ),
          if (_loading)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            )
          else if (_content == null)
            const Expanded(
              child: Center(
                child: Text('选择设备中的文本/文档文件，读取内容预览。'),
              ),
            )
          else
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      _fileName ?? '',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(
                        _content ?? '',
                        style: const TextStyle(fontSize: 15, height: 1.6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
