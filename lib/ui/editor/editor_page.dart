import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/note.dart';
import '../../services/settings_service.dart';
import '../../state/note_provider.dart';
import '../preview/preview_page.dart';
import '../preview/markdown_toolbar.dart';

/// 编辑器页。
///
/// 支持 Markdown 语法编辑、二次工具栏插入符号、实时字数统计、
/// 撤销/重做，以及与「预览」页的切换。
class EditorPage extends StatefulWidget {
  const EditorPage({super.key, required this.nodeId});

  /// 编辑的文章节点 id。
  final String nodeId;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  SaltNode? _node;
  bool _loading = true;
  bool _dirty = false;
  int _wordCount = 0;
  SettingsService? _settings;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final provider = context.read<NoteProvider>();
    final settings = await SettingsService.instance;
    final node = await provider.nodeById(widget.nodeId);
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _node = node;
      _loading = false;
      if (node != null) {
        _controller.text = node.content;
        _updateWordCount();
      }
    });
  }

  void _updateWordCount() {
    final text = _controller.text;
    setState(() {
      _wordCount = text.trim().isEmpty ? 0 : _countWords(text);
    });
  }

  /// 统计字数（中文字符 + 英文单词）。
  int _countWords(String text) {
    final cn = RegExp(r'[\u4e00-\u9fa5]').allMatches(text).length;
    final en = text
        .replaceAll(RegExp(r'[\u4e00-\u9fa5]'), ' ')
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;
    return cn + en;
  }

  /// 插入符号到当前光标处。
  void _insert(String symbol, [String? close]) {
    final text = _controller.text;
    final sel = _controller.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final selected = text.substring(start, end);
    final replacement =
        close == null || selected.isEmpty ? symbol : '$symbol$selected$close';
    final newText = text.replaceRange(start, end, replacement);
    _controller.text = newText;
    _controller.selection = TextSelection.collapsed(
      offset: start + symbol.length + (close == null ? 0 : selected.length),
    );
    _focus.requestFocus();
    _onEditingChanged();
  }

  void _onEditingChanged() {
    _updateWordCount();
    _dirty = true;
  }

  /// 实时保存。
  Future<void> _save() async {
    final node = _node;
    if (node == null || !_dirty || !mounted) return;
    await context.read<NoteProvider>().updateNode(
          node.copyWith(content: _controller.text),
        );
    _dirty = false;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final node = _node;
    if (node == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('文章不存在或已被删除')),
      );
    }
    final settings = _settings!;
    final fontSize = settings.scaleEditorFont ? settings.editorFontSize : 17.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(node.title.isEmpty ? '未命名' : node.title),
        actions: [
          if (settings.showWordCount)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text('$_wordCount 字',
                    style: TextStyle(
                        color: Colors.grey.shade600, fontSize: 12)),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.visibility_outlined),
            tooltip: '预览',
            onPressed: () {
              _save();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      PreviewPage(title: node.title, content: _controller.text),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                style: TextStyle(fontSize: fontSize, height: 1.7),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: '开始书写，半角 # 表示标题…',
                ),
                onChanged: (_) => _onEditingChanged(),
              ),
            ),
          ),
          // 双层工具栏：Core 常用符号。
          MarkdownToolbar(onInsert: _insert),
        ],
      ),
    );
  }
}