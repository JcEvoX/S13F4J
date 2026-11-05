import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/editor_registry.dart';
import '../services/quick_open.dart';
import '../services/workbench.dart';
import 'editor_area.dart';
import 'quick_open_panel.dart';
import 'sidebar.dart';
import 'status_bar.dart';

/// 工作台外壳：活动栏 + 侧栏 + 编辑区 + 状态栏。
///
/// 宽屏（≥ 840dp）常驻三栏；窄屏侧栏收进抽屉，编辑区占满。
class WorkbenchPage extends StatefulWidget {
  const WorkbenchPage({super.key});

  static const double wideBreakpoint = 840;

  @override
  State<WorkbenchPage> createState() => _WorkbenchPageState();
}

class _WorkbenchPageState extends State<WorkbenchPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final Workbench _wb;
  late final QuickOpenService _quickOpen;
  late final _PageUi _ui;
  String? _lastActiveTabId;

  @override
  void initState() {
    super.initState();
    _wb = context.read<Workbench>();
    _quickOpen = context.read<QuickOpenService>();
    _ui = _PageUi(this);
    _wb.ui = _ui;
    _wb.addListener(_closeDrawerOnNewEditor);
    unawaited(_boot());
  }

  Future<void> _boot() async {
    await _wb.restoreSession();
    await _wb.refreshWorkspace();
    if (_wb.tabs.isEmpty && mounted) {
      _wb.openEditor(kWelcomeViewType, title: '欢迎');
    }
  }

  /// 窄屏下抽屉盖在编辑区上：新标签被激活（新建 / 打开 / 命令面板）后收起抽屉。
  void _closeDrawerOnNewEditor() {
    final id = _wb.activeTab?.id;
    if (id == _lastActiveTabId) return;
    _lastActiveTabId = id;
    if (id == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final scaffold = _scaffoldKey.currentState;
      if (mounted && scaffold != null && scaffold.isDrawerOpen) {
        scaffold.closeDrawer();
      }
    });
  }

  @override
  void dispose() {
    _wb.removeListener(_closeDrawerOnNewEditor);
    if (identical(_wb.ui, _ui)) _wb.ui = HeadlessWorkbenchUi();
    super.dispose();
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts {
    void run(String command) => unawaited(
          _wb.executeCommand(command).catchError((Object e) {
            _wb.reportError(e);
            return null;
          }),
        );
    return {
      const SingleActivator(LogicalKeyboardKey.keyP, control: true): () =>
          run('workbench.action.quickOpen'),
      const SingleActivator(LogicalKeyboardKey.keyP, meta: true): () =>
          run('workbench.action.quickOpen'),
      const SingleActivator(LogicalKeyboardKey.keyP,
          control: true,
          shift: true): () => run('workbench.action.showCommands'),
      const SingleActivator(LogicalKeyboardKey.keyP, meta: true, shift: true):
          () => run('workbench.action.showCommands'),
      const SingleActivator(LogicalKeyboardKey.keyW, control: true): () =>
          run('workbench.action.closeActiveEditor'),
      const SingleActivator(LogicalKeyboardKey.keyB, control: true): () =>
          run('workbench.action.toggleSidebar'),
      const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () =>
          run('workbench.action.toggleSidebar'),
    };
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: _shortcuts,
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) =>
              constraints.maxWidth >= WorkbenchPage.wideBreakpoint
                  ? _buildWide(context)
                  : _buildNarrow(context),
        ),
      ),
    );
  }

  Widget _buildWide(BuildContext context) {
    return ListenableBuilder(
      listenable: _wb,
      builder: (context, _) => Scaffold(
        body: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  ActivityBar(workbench: _wb),
                  if (_wb.sidebarVisible) ...[
                    SizedBox(
                      width: 300,
                      child: WorkbenchSidebar(workbench: _wb),
                    ),
                    const VerticalDivider(width: 1),
                  ],
                  Expanded(child: EditorArea(workbench: _wb)),
                ],
              ),
            ),
            const Divider(height: 1),
            WorkbenchStatusBar(workbench: _wb),
          ],
        ),
      ),
    );
  }

  Widget _buildNarrow(BuildContext context) {
    return ListenableBuilder(
      listenable: _wb,
      builder: (context, _) {
        final tab = _wb.activeTab;
        return Scaffold(
          key: _scaffoldKey,
          appBar: AppBar(
            leading: IconButton(
              tooltip: '资源管理器',
              icon: const Icon(Icons.menu),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
            title: tab == null
                ? const Text('NotePad')
                : ValueListenableBuilder<String>(
                    valueListenable: tab.input.title,
                    builder: (_, title, __) => Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
            actions: [
              IconButton(
                tooltip: '转到文件 / 命令',
                icon: const Icon(Icons.search),
                onPressed: () => unawaited(_ui.showQuickOpen()),
              ),
            ],
          ),
          drawer: Drawer(
            width: 340,
            child: Row(
              children: [
                ActivityBar(workbench: _wb, drawerMode: true),
                Expanded(
                  child: SafeArea(
                    child: WorkbenchSidebar(
                      workbench: _wb,
                      onOpened: () => _scaffoldKey.currentState?.closeDrawer(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          body: Column(
            children: [
              Expanded(child: EditorArea(workbench: _wb)),
              const Divider(height: 1),
              WorkbenchStatusBar(workbench: _wb),
            ],
          ),
        );
      },
    );
  }
}

/// 把命令需要的交互落到页面上：对话框 / 提示 / 整页导航 / 命令面板。
class _PageUi implements WorkbenchUi {
  _PageUi(this._state);

  final _WorkbenchPageState _state;

  BuildContext? get _context => _state.mounted ? _state.context : null;

  @override
  Future<String?> prompt({
    required String title,
    String initialValue = '',
    String? hint,
  }) async {
    final context = _context;
    if (context == null) return null;
    return showDialog<String>(
      context: context,
      builder: (ctx) => _PromptDialog(
        title: title,
        initialValue: initialValue,
        hint: hint,
      ),
    );
  }

  @override
  Future<bool> confirm({
    required String title,
    required String message,
    String confirmLabel = '确定',
    bool destructive = false,
  }) async {
    final context = _context;
    if (context == null) return false;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                  )
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Future<String?> pickOne({
    required String title,
    required List<QuickPickItem> items,
  }) async {
    final context = _context;
    if (context == null) return null;
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              dense: true,
              title: Text(title, style: Theme.of(ctx).textTheme.titleSmall),
            ),
            for (final item in items)
              ListTile(
                title: Text(item.label),
                subtitle: item.detail == null ? null : Text(item.detail!),
                onTap: () => Navigator.pop(ctx, item.id),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void showMessage(String message, {bool isError = false}) {
    final context = _context;
    if (context == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
        ),
      );
  }

  @override
  Future<void> showPage(WidgetBuilder builder) async {
    final context = _context;
    if (context == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));
  }

  @override
  Future<void> showQuickOpen({String initialText = ''}) async {
    final context = _context;
    if (context == null) return;
    await showQuickOpenPanel(
      context,
      workbench: _state._wb,
      quickOpen: _state._quickOpen,
      initialText: initialText,
    );
  }
}

/// 输入框对话框：控制器随对话框的 State 释放，避免关闭动画期间使用已释放的控制器。
class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.initialValue,
    this.hint,
  });

  final String title;
  final String initialValue;
  final String? hint;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  )..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initialValue.length,
    );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('prompt-input'),
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
