import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../base/context_keys.dart';
import '../base/resource_uri.dart';
import 'command_registry.dart';
import 'contribution_registry.dart';
import 'editor_registry.dart';
import 'extension_host.dart';
import 'file_system.dart';
import 'view_registry.dart';

/// scheme 的「家族」：`files.p-01` → `files`，`notes` → `notes`。
/// 同一能力的多个命名空间共用一个家族，便于 when 子句匹配。
String schemeFamily(String scheme) {
  final dot = scheme.indexOf('.');
  return dot < 0 ? scheme : scheme.substring(0, dot);
}

/// 工作区文件夹 = 一个命名空间（笔记库 / 导入项目 / 将来的 git 仓库）。
class WorkspaceFolder {
  const WorkspaceFolder({
    required this.scheme,
    required this.name,
    this.state = 'active',
  });

  final String scheme;
  final String name;

  /// active / disabled / missing，与注册表一致。
  final String state;

  bool get isActive => state == 'active';

  ResourceUri get root => ResourceUri(scheme);
}

typedef WorkspaceFolderSource = Future<List<WorkspaceFolder>> Function();

class QuickPickItem {
  const QuickPickItem({required this.id, required this.label, this.detail});

  final String id;
  final String label;
  final String? detail;
}

/// 工作台向命令暴露的交互能力。由 UI 外壳实现；测试里用 [HeadlessWorkbenchUi]。
abstract class WorkbenchUi {
  Future<String?> prompt({
    required String title,
    String initialValue = '',
    String? hint,
  });

  Future<bool> confirm({
    required String title,
    required String message,
    String confirmLabel = '确定',
    bool destructive = false,
  });

  Future<String?> pickOne({
    required String title,
    required List<QuickPickItem> items,
  });

  void showMessage(String message, {bool isError = false});

  /// 以整页方式打开（插件中心 / 设置 / 备份等宿主页面）。
  Future<void> showPage(WidgetBuilder builder);

  /// 打开命令面板，[initialText] 以 `>` 开头时直接进入命令模式。
  Future<void> showQuickOpen({String initialText = ''});
}

class HeadlessWorkbenchUi implements WorkbenchUi {
  final List<String> messages = [];
  String? promptResult;
  bool confirmResult = true;
  String? pickResult;

  @override
  Future<String?> prompt({
    required String title,
    String initialValue = '',
    String? hint,
  }) async =>
      promptResult;

  @override
  Future<bool> confirm({
    required String title,
    required String message,
    String confirmLabel = '确定',
    bool destructive = false,
  }) async =>
      confirmResult;

  @override
  Future<String?> pickOne({
    required String title,
    required List<QuickPickItem> items,
  }) async =>
      pickResult;

  @override
  void showMessage(String message, {bool isError = false}) =>
      messages.add(message);

  @override
  Future<void> showPage(WidgetBuilder builder) async {}

  @override
  Future<void> showQuickOpen({String initialText = ''}) async {}
}

/// 会话持久化（打开的标签 / 最近文件 / 侧栏状态）。
abstract class SessionStore {
  Future<Map<String, Object?>?> load();
  Future<void> save(Map<String, Object?> data);
}

class MemorySessionStore implements SessionStore {
  Map<String, Object?>? data;

  @override
  Future<Map<String, Object?>?> load() async => data;

  @override
  Future<void> save(Map<String, Object?> value) async {
    data = jsonDecode(jsonEncode(value)) as Map<String, Object?>;
  }
}

/// 编辑区中的一个标签。
class EditorTab {
  EditorTab(this.input);

  final EditorInput input;

  String get id => input.id;
  ResourceUri? get resource => input.resource;
  String get viewType => input.viewType;
}

/// 工作台：编辑器分组 + 工作区 + 命令执行入口 + 全部注册表。
class Workbench extends ChangeNotifier {
  Workbench({SessionStore? sessionStore})
      : _sessionStore = sessionStore,
        contributions = ContributionRegistry() {
    editors = EditorRegistry(contributions);
    fileSystems.activator =
        (scheme) async => extensionHost?.activateByEvent('onResource:$scheme');
    contextKeys.setAll({
      'sidebarVisible': true,
      'workspaceFolderCount': 0,
      'openEditorCount': 0,
    });
  }

  final SessionStore? _sessionStore;

  final CommandRegistry commands = CommandRegistry();
  final FileSystemRegistry fileSystems = FileSystemRegistry();
  final ViewRegistry views = ViewRegistry();
  final ContextKeyService contextKeys = ContextKeyService();
  final ContributionRegistry contributions;
  late final EditorRegistry editors;

  ExtensionHost? extensionHost;
  WorkbenchUi ui = HeadlessWorkbenchUi();
  WorkspaceFolderSource? workspaceFolderSource;

  static const int maxRecent = 30;
  static const int maxMacroDepth = 16;

  // ── 命令 ──────────────────────────────────────────────

  /// 把异常转成面向用户的一句话并通过 UI 提示。
  void reportError(Object error) {
    ui.showMessage(describeError(error), isError: true);
  }

  /// 执行命令：先找处理函数，找不到就触发 `onCommand:<id>` 激活，
  /// 仍没有则回退到 manifest 声明的 `run` 宏。
  Future<Object?> executeCommand(
    String id, [
    List<Object?> args = const [],
  ]) =>
      _execute(id, args, 0);

  Future<Object?> _execute(String id, List<Object?> args, int depth) async {
    if (depth > maxMacroDepth) {
      throw StateError('命令宏嵌套过深（可能存在循环）: $id');
    }
    var handler = commands.handlerOf(id);
    if (handler == null) {
      await extensionHost?.activateByEvent('onCommand:$id');
      handler = commands.handlerOf(id);
    }
    if (handler != null) {
      return await handler(CommandContext(workbench: this, args: args));
    }
    final declared = contributions.command(id);
    if (declared != null && declared.run.isNotEmpty) {
      Object? last;
      for (final step in declared.run) {
        last = await _execute(step.command, step.args, depth + 1);
      }
      return last;
    }
    throw CommandNotFoundError(id, declared: declared != null);
  }

  /// 面板 / 菜单里可见的命令：已声明、`when` 通过，且有实现或宏。
  List<CommandContribution> paletteCommands() {
    final hidden = <String>{};
    final palette = contributions.menu(MenuIds.commandPalette);
    for (final item in palette) {
      if (!contextKeys.evaluate(item.when)) hidden.add(item.command);
    }
    return [
      for (final c in contributions.commands)
        if (!hidden.contains(c.command) &&
            contextKeys.evaluate(c.when) &&
            (commands.hasHandler(c.command) ||
                c.run.isNotEmpty ||
                extensionHost?.canActivateFor('onCommand:${c.command}') ==
                    true))
          c,
    ];
  }

  /// 某菜单位置当前可见的条目（`when` 通过）。
  List<MenuContribution> visibleMenu(
    String menuId, {
    Map<String, Object?>? overrides,
  }) =>
      [
        for (final item in contributions.menu(menuId))
          if (contextKeys.evaluate(item.when, overrides: overrides) &&
              contextKeys.evaluate(
                contributions.command(item.command)?.when,
                overrides: overrides,
              ))
            item,
      ];

  // ── 工作区 ────────────────────────────────────────────

  List<WorkspaceFolder> _folders = const [];

  List<WorkspaceFolder> get workspaceFolders => _folders;

  List<WorkspaceFolder> get activeFolders => [
        for (final f in _folders)
          if (f.isActive) f
      ];

  Future<void> refreshWorkspace() async {
    final source = workspaceFolderSource;
    if (source == null) return;
    _folders = await source();
    contextKeys.set('workspaceFolderCount', activeFolders.length);
    notifyListeners();
  }

  // ── 编辑器 / 标签 ──────────────────────────────────────

  final List<EditorTab> _tabs = [];
  final List<ResourceUri> _recent = [];
  final List<({ResourceUri? uri, String viewType})> _closed = [];
  int _active = -1;
  int _tabSeq = 0;

  List<EditorTab> get tabs => List.unmodifiable(_tabs);
  int get activeIndex => _active;
  EditorTab? get activeTab =>
      _active >= 0 && _active < _tabs.length ? _tabs[_active] : null;
  List<ResourceUri> get recentResources => List.unmodifiable(_recent);

  String titleFor(ResourceUri uri) {
    final provider = fileSystems.providerOf(uri.scheme);
    if (provider != null) return provider.displayName(uri);
    return uri.isRoot ? uri.scheme : uri.basename;
  }

  /// 打开资源。已打开同一资源 + 编辑器则直接激活。
  Future<EditorTab> openResource(
    ResourceUri uri, {
    String? viewType,
    bool activate = true,
  }) async {
    await fileSystems.resolve(uri.scheme);
    final type = viewType ?? editors.resolve(uri);
    if (!editors.hasProvider(type)) {
      await extensionHost?.activateByEvent('onEditor:$type');
    }
    final existing = _tabs.indexWhere(
      (t) => t.resource == uri && t.viewType == type,
    );
    if (existing >= 0) {
      if (activate) activateTab(existing);
      _touchRecent(uri);
      return _tabs[existing];
    }
    final tab = EditorTab(
      EditorInput(
        id: 'tab-${_tabSeq++}',
        viewType: type,
        title: titleFor(uri),
        resource: uri,
      ),
    );
    _tabs.add(tab);
    _touchRecent(uri);
    if (activate || _active < 0) {
      _active = _tabs.length - 1;
    }
    _afterTabsChanged();
    return tab;
  }

  /// 打开没有资源的编辑器（欢迎页等）。
  EditorTab openEditor(String viewType, {required String title}) {
    final existing = _tabs.indexWhere(
      (t) => t.resource == null && t.viewType == viewType,
    );
    if (existing >= 0) {
      activateTab(existing);
      return _tabs[existing];
    }
    final tab = EditorTab(
      EditorInput(id: 'tab-${_tabSeq++}', viewType: viewType, title: title),
    );
    _tabs.add(tab);
    _active = _tabs.length - 1;
    _afterTabsChanged();
    return tab;
  }

  void activateTab(int index) {
    if (index < 0 || index >= _tabs.length || index == _active) return;
    _active = index;
    _afterTabsChanged();
  }

  void nextTab() {
    if (_tabs.length < 2) return;
    activateTab((_active + 1) % _tabs.length);
  }

  void previousTab() {
    if (_tabs.length < 2) return;
    activateTab((_active - 1 + _tabs.length) % _tabs.length);
  }

  void closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    final tab = _tabs.removeAt(index);
    _closed.add((uri: tab.resource, viewType: tab.viewType));
    if (_closed.length > 20) _closed.removeAt(0);
    if (_tabs.isEmpty) {
      _active = -1;
    } else if (index < _active) {
      _active -= 1;
    } else if (index == _active) {
      _active = index >= _tabs.length ? _tabs.length - 1 : index;
    }
    _afterTabsChanged();
  }

  void closeActiveTab() => closeTab(_active);

  void closeOtherTabs(int keepIndex) {
    for (var i = _tabs.length - 1; i >= 0; i--) {
      if (i != keepIndex) closeTab(i);
    }
  }

  void closeAllTabs() {
    for (var i = _tabs.length - 1; i >= 0; i--) {
      closeTab(i);
    }
  }

  /// 关闭属于 [scheme] 的全部标签（插件停用 / 项目移除时调用）。
  void closeTabsOfScheme(String scheme) {
    for (var i = _tabs.length - 1; i >= 0; i--) {
      if (_tabs[i].resource?.scheme == scheme) closeTab(i);
    }
  }

  /// 资源被删除 / 改名后清理标签。
  void closeTabsUnder(ResourceUri uri) {
    for (var i = _tabs.length - 1; i >= 0; i--) {
      final resource = _tabs[i].resource;
      if (resource != null && uri.contains(resource)) closeTab(i);
    }
  }

  Future<EditorTab?> reopenClosedTab() async {
    while (_closed.isNotEmpty) {
      final entry = _closed.removeLast();
      final uri = entry.uri;
      if (uri != null) return openResource(uri, viewType: entry.viewType);
      return openEditor(entry.viewType, title: entry.viewType);
    }
    return null;
  }

  void _touchRecent(ResourceUri uri) {
    _recent.remove(uri);
    _recent.insert(0, uri);
    if (_recent.length > maxRecent) _recent.removeLast();
  }

  void _afterTabsChanged() {
    _syncContext();
    notifyListeners();
    unawaited(_persist());
  }

  // ── 侧栏 ─────────────────────────────────────────────

  bool _sidebarVisible = true;
  String _activeContainer = 'explorer';

  bool get sidebarVisible => _sidebarVisible;
  String get activeContainer => _activeContainer;

  void setSidebarVisible(bool value) {
    if (_sidebarVisible == value) return;
    _sidebarVisible = value;
    contextKeys.set('sidebarVisible', value);
    notifyListeners();
    unawaited(_persist());
  }

  void toggleSidebar() => setSidebarVisible(!_sidebarVisible);

  /// 切换活动栏容器；点击当前容器则收起 / 展开侧栏（与 VS Code 一致）。
  void selectContainer(String id, {bool toggleIfActive = true}) {
    if (_activeContainer == id) {
      if (toggleIfActive) toggleSidebar();
      return;
    }
    _activeContainer = id;
    _sidebarVisible = true;
    contextKeys.set('sidebarVisible', true);
    notifyListeners();
    unawaited(_persist());
  }

  // ── 在资源管理器中定位 ──

  ResourceUri? _pendingReveal;

  /// 请求资源管理器展开并选中 [uri]：切到资源管理器、展开侧栏，由视图消费。
  void revealInExplorer(ResourceUri uri) {
    _pendingReveal = uri;
    _activeContainer = 'explorer';
    _sidebarVisible = true;
    contextKeys.set('sidebarVisible', true);
    notifyListeners();
    unawaited(_persist());
  }

  bool get hasPendingReveal => _pendingReveal != null;

  /// 取走待处理的定位请求（视图处理一次即清除）。
  ResourceUri? takePendingReveal() {
    final uri = _pendingReveal;
    _pendingReveal = null;
    return uri;
  }

  // ── 资源管理器选中项（供 explorer/context 菜单的 when 使用）──

  ResourceUri? _explorerSelection;
  ResourceUri? get explorerSelection => _explorerSelection;

  void setExplorerSelection(ResourceUri? uri, {bool isFolder = false}) {
    _explorerSelection = uri;
    contextKeys.setAll({
      'explorerResourceScheme': uri?.scheme,
      'explorerResourceFamily': uri == null ? null : schemeFamily(uri.scheme),
      'explorerResourceIsFolder': uri == null ? false : isFolder,
      'explorerResourceIsRoot': uri?.isRoot ?? false,
      'explorerResourceReadOnly': uri == null
          ? false
          : fileSystems.providerOf(uri.scheme)?.readOnly ?? true,
    });
  }

  void _syncContext() {
    final tab = activeTab;
    final resource = tab?.resource;
    contextKeys.setAll({
      'openEditorCount': _tabs.length,
      'activeEditor': tab != null,
      'editorViewType': tab?.viewType,
      'resourceScheme': resource?.scheme,
      'resourceFamily': resource == null ? null : schemeFamily(resource.scheme),
      'resourcePath': resource?.path,
      'resourceFilename': resource?.basename,
      'resourceExtname': resource?.extname,
      'resourceReadOnly': resource == null
          ? false
          : fileSystems.providerOf(resource.scheme)?.readOnly ?? true,
    });
  }

  // ── 会话 ─────────────────────────────────────────────

  Future<void> _persist() async {
    final store = _sessionStore;
    if (store == null) return;
    try {
      await store.save({
        'tabs': [
          for (final tab in _tabs)
            {
              if (tab.resource != null) 'uri': tab.resource.toString(),
              'viewType': tab.viewType,
              'title': tab.input.title.value,
            },
        ],
        'active': _active,
        'recent': [for (final uri in _recent) uri.toString()],
        'sidebar': _sidebarVisible,
        'container': _activeContainer,
      });
    } catch (e) {
      debugPrint('[Workbench] 保存会话失败: $e');
    }
  }

  /// 恢复上次会话。资源已不存在的标签保留（编辑器会显示明确提示）。
  Future<void> restoreSession() async {
    final store = _sessionStore;
    if (store == null) return;
    Map<String, Object?>? data;
    try {
      data = await store.load();
    } catch (e) {
      debugPrint('[Workbench] 读取会话失败: $e');
    }
    if (data == null) return;
    _recent.clear();
    for (final raw in (data['recent'] as List?) ?? const []) {
      final uri = raw is String ? ResourceUri.tryParse(raw) : null;
      if (uri != null) _recent.add(uri);
    }
    _sidebarVisible = data['sidebar'] as bool? ?? true;
    _activeContainer = data['container'] as String? ?? 'explorer';
    contextKeys.set('sidebarVisible', _sidebarVisible);
    for (final raw in (data['tabs'] as List?) ?? const []) {
      if (raw is! Map) continue;
      final viewType = raw['viewType'];
      if (viewType is! String) continue;
      final uriText = raw['uri'];
      final title = (raw['title'] as String?) ?? viewType;
      final uri = uriText is String ? ResourceUri.tryParse(uriText) : null;
      if (uriText is String && uri == null) continue;
      _tabs.add(
        EditorTab(
          EditorInput(
            id: 'tab-${_tabSeq++}',
            viewType: viewType,
            title: title,
            resource: uri,
          ),
        ),
      );
    }
    final active = data['active'];
    _active = _tabs.isEmpty
        ? -1
        : (active is int && active >= 0 && active < _tabs.length
            ? active
            : _tabs.length - 1);
    _syncContext();
    notifyListeners();
  }

  @override
  void dispose() {
    commands.dispose();
    fileSystems.dispose();
    contextKeys.dispose();
    contributions.dispose();
    editors.dispose();
    views.dispose();
    super.dispose();
  }
}

/// 面向用户的错误文案。
String describeError(Object error) {
  if (error is FileSystemError) return error.message;
  if (error is CommandNotFoundError) return error.toString();
  return '$error';
}
