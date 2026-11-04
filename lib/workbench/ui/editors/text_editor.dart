import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/editor_registry.dart';
import '../../services/file_system.dart';
import '../../services/workbench.dart';
import '../../../ui/plugins/file_browser_page.dart' show saveTextAsNote;
import 'editor_message.dart';

/// 通用文本编辑器（`workbench.text`）。
///
/// 只读资源以可选中的等宽文本呈现；可写资源防抖自动保存。
/// 任何命名空间的任意文本文件都能用它打开，是编辑器解析的最终回退。
class TextEditorView extends StatefulWidget {
  const TextEditorView(
      {super.key, required this.workbench, required this.input});

  final Workbench workbench;
  final EditorInput input;

  @override
  State<TextEditorView> createState() => _TextEditorViewState();
}

class _TextEditorViewState extends State<TextEditorView> {
  static const Duration _saveDebounce = Duration(milliseconds: 800);

  final TextEditingController _controller = TextEditingController();
  Timer? _timer;
  Future<void> _saveQueue = Future<void>.value();
  String _latest = '';
  bool _loading = true;
  bool _readOnly = true;
  String? _error;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uri = widget.input.resource;
    if (uri == null) {
      setState(() {
        _loading = false;
        _error = '该编辑器没有关联资源';
      });
      return;
    }
    try {
      final fs = widget.workbench.fileSystems;
      final readOnly = await fs.isReadOnly(uri);
      final text = await fs.readText(uri);
      if (!mounted) return;
      setState(() {
        _readOnly = readOnly;
        _latest = text;
        _controller.text = text;
        _loading = false;
      });
    } on FileSystemError catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.code == 'E-NOT-FOUND' ? '文件已不存在，可能已被删除或移动。' : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '读取失败：$e';
      });
    }
  }

  void _onChanged(String value) {
    _latest = value;
    widget.input.dirty.value = true;
    setState(() => _status = '保存中…');
    _timer?.cancel();
    _timer = Timer(_saveDebounce, _save);
  }

  Future<void> _save() {
    _timer?.cancel();
    _timer = null;
    _saveQueue = _saveQueue.then((_) => _doSave());
    return _saveQueue;
  }

  Future<void> _doSave() async {
    final uri = widget.input.resource;
    if (uri == null || !widget.input.dirty.value) return;
    final content = _latest;
    try {
      await widget.workbench.fileSystems.writeText(uri, content);
      if (_latest == content) widget.input.dirty.value = false;
      if (mounted) setState(() => _status = '已保存');
    } catch (e) {
      if (mounted) {
        setState(() => _status = '保存失败');
        widget.workbench.ui.showMessage('保存失败：$e', isError: true);
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (widget.input.dirty.value) unawaited(_save());
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final error = _error;
    if (error != null) {
      return EditorMessage(
          message: error, icon: Icons.insert_drive_file_outlined);
    }
    final uri = widget.input.resource!;
    final grey = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  uri.toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: grey),
                ),
              ),
              if (_readOnly) ...[
                Text('只读', style: TextStyle(fontSize: 12, color: grey)),
                if (uri.scheme != 'notes')
                  IconButton(
                    tooltip: '另存为笔记',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.note_add_outlined, size: 20),
                    onPressed: () => saveTextAsNote(
                      context,
                      title: uri.basename,
                      content: _latest,
                    ),
                  ),
              ] else
                Text(_status, style: TextStyle(fontSize: 12, color: grey)),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _readOnly
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    _latest,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      fontFamily: 'monospace',
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _controller,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      fontFamily: 'monospace',
                    ),
                    decoration: const InputDecoration(border: InputBorder.none),
                    onChanged: _onChanged,
                  ),
                ),
        ),
      ],
    );
  }
}
