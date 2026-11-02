import 'dart:async';

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

class _EditorPageState extends State<EditorPage> with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  /// 停止输入后延迟落库的定时器（防抖），避免每个字符都写一次文件。
  Timer? _saveTimer;

  /// 自动保存防抖间隔。
  static const Duration _saveDebounce = Duration(milliseconds: 600);

  /// 最新文本：与输入同步更新，页面销毁后仍可用于完成最后一次落库
  /// （避免保存过程中释放 TextEditingController 导致读取异常）。
  String _latestContent = '';

  /// 串行化保存队列，避免并发写入互相覆盖（旧内容盖掉新内容）。
  Future<void> _saveQueue = Future<void>.value();

  /// 返回流程进行中标记：防止连续按返回时重复触发 pop。
  bool _popping = false;

  NotePadNode? _node;
  bool _loading = true;
  bool _dirty = false;

  /// 是否正在写盘。用于返回判定：写入期间不允许直接 pop，避免上一页读到旧数据。
  bool _saving = false;

  /// 保存状态轻提示：保存中… / 已保存 / 保存失败。
  String _saveStatus = '已保存';

  /// 打开 / 上次保存完成时的正文指纹，用于检测外部修改。
  String? _baseFingerprint;

  /// 外部修改提示框进行中标记，避免重复弹窗。
  bool _conflictPrompting = false;

  int _wordCount = 0;
  SettingsService? _settings;
  NoteProvider? _provider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    debugPrint('[Editor] 打开 nodeId=${widget.nodeId}');
    final provider = context.read<NoteProvider>();
    _provider = provider;
    // 记录当前正在编辑的文章，供首页「定位正在编辑的文章」使用。
    provider.setCurrentEditingNodeId(widget.nodeId);
    final settings = await SettingsService.instance;
    final node = await provider.nodeById(widget.nodeId);
    var body = node?.content ?? '';
    String? fingerprint;
    if (node != null && !node.isFolder) {
      try {
        body = await provider.readBody(node.id);
        fingerprint = await provider.bodyFingerprint(node.id);
      } catch (e) {
        debugPrint('[Editor] 读取正文失败，回退到节点快照: $e');
      }
    }
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _node = node;
      _loading = false;
      _baseFingerprint = fingerprint;
      if (node != null) {
        _latestContent = body;
        _controller.text = body;
        _updateWordCount();
      }
    });
    debugPrint(node == null
        ? '[Editor] 节点不存在或已删除 nodeId=${widget.nodeId}'
        : '[Editor] 加载完成 title=${node.title}, 内容 ${body.length} 字符');
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
    _saveStatus = '保存中…';
    _updateWordCount();
    _latestContent = _controller.text;
    _dirty = true;
    // 输入停顿后再落库，兼顾实时性与写入频率。
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, _save);
  }

  /// 排队保存：多次调用按顺序串行落库，保证最后一次输入不会被旧内容覆盖。
  Future<void> _save() {
    _saveTimer?.cancel();
    _saveTimer = null;
    _saveQueue = _saveQueue.then((_) => _doSave());
    return _saveQueue;
  }

  /// 实际落库逻辑。
  ///
  /// 读取 [_latestContent] 而不是 TextEditingController，页面销毁后仍可安全
  /// 完成最后一次保存；落库失败则保留脏标记，等待下次输入或离开时重试。
  Future<void> _doSave() async {
    final node = _node;
    final provider = _provider;
    if (node == null || provider == null || !_dirty) return;
    final content = _latestContent;
    _saving = true;
    _saveStatus = '保存中…';
    if (mounted) setState(() {});

    // 写盘前先对比指纹：磁盘文件被外部程序改过时，交由用户选择。
    if (_baseFingerprint != null) {
      try {
        final current = await provider.bodyFingerprint(node.id);
        if (current != _baseFingerprint) {
          final choice = await _askExternalConflict();
          if (choice == _ExternalConflictChoice.reload) {
            await _reloadFromDisk();
            _saving = false;
            return;
          }
          // 保留当前：以编辑器内容覆盖外部修改。
          _baseFingerprint = current;
        }
      } catch (e) {
        debugPrint('[Editor] 外部修改检测失败: $e');
      }
    }

    _dirty = false;
    debugPrint('[Editor] 保存 nodeId=${node.id}, 内容 ${content.length} 字符');
    try {
      await provider.saveBody(node.id, content);
      _saveStatus = '已保存';
      try {
        _baseFingerprint = await provider.bodyFingerprint(node.id);
      } catch (_) {
        // 指纹读取失败不影响保存结果。
      }
      debugPrint('[Editor] 保存完成');
    } catch (e) {
      _dirty = true;
      _saveStatus = '保存失败';
      debugPrint('[Editor] 保存失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存失败，内容仍在编辑器中')),
        );
      }
    } finally {
      _saving = false;
      // 刷新 PopScope.canPop：无待保存内容时恢复返回手势。
      if (mounted) setState(() {});
    }
  }

  /// 前台恢复时对账：未编辑则静默同步磁盘内容；有未保存内容则询问用户。
  Future<void> _checkExternalChange() async {
    final node = _node;
    final provider = _provider;
    if (node == null || provider == null || node.isFolder) return;
    if (_baseFingerprint == null || _conflictPrompting) return;
    String current;
    try {
      current = await provider.bodyFingerprint(node.id);
    } catch (_) {
      return;
    }
    if (current == _baseFingerprint) return;

    if (!_dirty) {
      await _reloadFromDisk();
      return;
    }
    final choice = await _askExternalConflict();
    if (choice == _ExternalConflictChoice.reload) {
      await _reloadFromDisk();
      return;
    }
    _baseFingerprint = current;
    await _save();
  }

  /// 重新从磁盘加载正文（放弃编辑器内未保存内容）。
  Future<void> _reloadFromDisk() async {
    final node = _node;
    final provider = _provider;
    if (node == null || provider == null) return;
    try {
      final body = await provider.readBody(node.id);
      final fingerprint = await provider.bodyFingerprint(node.id);
      _saveTimer?.cancel();
      _saveTimer = null;
      _controller.text = body;
      _controller.selection = TextSelection.collapsed(offset: body.length);
      _latestContent = body;
      _dirty = false;
      _baseFingerprint = fingerprint;
      _saveStatus = '已同步';
      if (!mounted) return;
      setState(() {
        _wordCount = body.trim().isEmpty ? 0 : _countWords(body);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已重新加载磁盘内容')),
      );
      debugPrint('[Editor] 已重新加载磁盘内容: ${body.length} 字符');
    } catch (e) {
      debugPrint('[Editor] 重新加载失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('重新加载失败，请稍后重试')),
        );
      }
    }
  }

  /// 外部修改确认框：返回重载 / 保留当前。
  Future<_ExternalConflictChoice> _askExternalConflict() async {
    if (!mounted || _conflictPrompting) {
      return _ExternalConflictChoice.keep;
    }
    _conflictPrompting = true;
    _saveStatus = '外部已修改';
    setState(() {});
    try {
      final choice = await showDialog<_ExternalConflictChoice>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('文件已在外部被修改'),
          content: const Text(
            '磁盘内容与当前编辑器不一致。'
            '「重新加载」会放弃本地未保存的修改；'
            '「保留当前」会用编辑器内容覆盖磁盘文件。',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, _ExternalConflictChoice.reload),
              child: const Text('重新加载'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, _ExternalConflictChoice.keep),
              child: const Text('保留当前'),
            ),
          ],
        ),
      );
      return choice ?? _ExternalConflictChoice.keep;
    } finally {
      _conflictPrompting = false;
    }
  }

  /// 立即冲刷未落库的内容（离开页面 / 切后台 / 预览前调用）。
  Future<void> _flushSave() async {
    await _save();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 应用切后台时立即保存，避免进程被系统回收导致内容丢失。
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_flushSave());
      return;
    }
    // 回到前台时对账：磁盘文件可能被外部程序修改。
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkExternalChange());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 兜底保存：返回键已在 PopScope 里等待落库，这里覆盖页面被其它方式移除的场景。
    // 保存使用 _latestContent，不依赖即将释放的 TextEditingController。
    _saveTimer?.cancel();
    _saveTimer = null;
    if (_dirty) unawaited(_save());
    // 离开编辑器后清除「当前编辑文章」，避免首页定位到已关闭的文章。
    _provider?.setCurrentEditingNodeId(null);
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
    final fontFamily = settings.editorFontFamily == 'system'
        ? null
        : settings.editorFontFamily;

    return PopScope(
      // 返回前先把待保存内容落库，保证上一页（首页 / 最近编辑 / 搜索）
      // 拿到的是最新数据。无未保存内容时放行，保留系统返回手势。
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _popping) return;
        _popping = true;
        try {
          await _flushSave();
        } finally {
          if (mounted) {
            if (_dirty) {
              // 落库失败时保留在当前编辑器，避免直接返回丢失内容。
              _popping = false;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('保存失败，已取消返回，请重试')),
              );
            } else {
              Navigator.of(context).pop(result);
            }
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          // 编辑器标题居中显示。
          centerTitle: true,
          title: Text(node.title.isEmpty ? '未命名' : node.title),
          actions: [
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  _saveStatus,
                  style: TextStyle(
                    fontSize: 11,
                    color: _saveStatus == '保存失败'
                        ? Theme.of(context).colorScheme.error
                        : Colors.grey.shade600,
                  ),
                ),
              ),
            ),
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
              onPressed: () async {
                await _flushSave();
                if (!mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PreviewPage(
                      title: node.title,
                      content: _controller.text,
                    ),
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
                  style: TextStyle(
                    fontSize: fontSize,
                    height: 1.7,
                    fontFamily: fontFamily,
                  ),
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
      ),
    );
  }
}

/// 外部修改冲突的处理方式。
enum _ExternalConflictChoice { reload, keep }
