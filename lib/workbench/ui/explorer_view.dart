import 'dart:async';

import 'package:flutter/material.dart';

import '../base/resource_uri.dart';
import '../services/contribution_registry.dart';
import '../services/file_system.dart';
import '../services/workbench.dart';
import 'icons.dart';

/// 资源管理器视图：把全部活动命名空间作为工作区文件夹展示为一棵树。
///
/// 树只依赖 [FileSystemProvider]，不认识「笔记」或「项目」；
/// 右键 / 长按菜单来自 `explorer/context` 贡献点。
class ExplorerView extends StatefulWidget {
  const ExplorerView({super.key, required this.workbench, this.onOpened});

  final Workbench workbench;

  /// 打开文件后回调（窄屏用来收起抽屉）。
  final VoidCallback? onOpened;

  @override
  State<ExplorerView> createState() => _ExplorerViewState();
}

class _Row {
  const _Row({
    required this.uri,
    required this.name,
    required this.isDirectory,
    required this.depth,
    this.folder,
  });

  final ResourceUri uri;
  final String name;
  final bool isDirectory;
  final int depth;

  /// 仅根节点有值。
  final WorkspaceFolder? folder;
}

class _ExplorerViewState extends State<ExplorerView> {
  final Map<ResourceUri, List<DirEntry>> _children = {};
  final Set<ResourceUri> _expanded = {};
  final Set<ResourceUri> _loading = {};
  final Map<ResourceUri, String> _errors = {};
  StreamSubscription<ResourceUri>? _changes;
  ResourceUri? _selected;

  Workbench get _wb => widget.workbench;

  @override
  void initState() {
    super.initState();
    _wb.addListener(_onWorkbenchChanged);
    _changes = _wb.fileSystems.onDidChange.listen(_onFsChanged);
    _wb.refreshWorkspace();
  }

  @override
  void dispose() {
    _wb.removeListener(_onWorkbenchChanged);
    _changes?.cancel();
    super.dispose();
  }

  void _onWorkbenchChanged() {
    if (!mounted) return;
    // 能力被停用后，清掉它的缓存，避免再次启用时看到陈旧目录。
    final live = {for (final f in _wb.activeFolders) f.scheme};
    _children.removeWhere((uri, _) => !live.contains(uri.scheme));
    _expanded.removeWhere((uri) => !live.contains(uri.scheme));
    setState(() {});
  }

  void _onFsChanged(ResourceUri dir) {
    if (!mounted) return;
    if (_children.containsKey(dir) || _expanded.contains(dir)) _load(dir);
  }

  Future<void> _load(ResourceUri dir) async {
    setState(() {
      _loading.add(dir);
      _errors.remove(dir);
    });
    try {
      final entries = await _wb.fileSystems.readDirectory(dir);
      if (!mounted) return;
      setState(() {
        _children[dir] = entries;
        _loading.remove(dir);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading.remove(dir);
        _errors[dir] = e is FileSystemError ? e.message : '$e';
      });
    }
  }

  void _toggle(ResourceUri uri) {
    setState(() {
      if (!_expanded.remove(uri)) {
        _expanded.add(uri);
        if (!_children.containsKey(uri)) _load(uri);
      }
    });
  }

  void _collapseAll() => setState(_expanded.clear);

  Future<void> _refresh() async {
    _children.clear();
    await _wb.refreshWorkspace();
    for (final dir in _expanded.toList()) {
      unawaited(_load(dir));
    }
  }

  List<_Row> _rows() {
    final rows = <_Row>[];
    void walk(ResourceUri dir, int depth) {
      for (final entry in _children[dir] ?? const <DirEntry>[]) {
        final uri = dir.join(entry.name);
        rows.add(_Row(
          uri: uri,
          name: entry.name,
          isDirectory: entry.isDirectory,
          depth: depth,
        ));
        if (entry.isDirectory && _expanded.contains(uri)) walk(uri, depth + 1);
      }
    }

    for (final folder in _wb.workspaceFolders) {
      rows.add(_Row(
        uri: folder.root,
        name: folder.name,
        isDirectory: true,
        depth: 0,
        folder: folder,
      ));
      if (folder.isActive && _expanded.contains(folder.root)) {
        walk(folder.root, 1);
      }
    }
    return rows;
  }

  /// 新建文件 / 文件夹的目标目录：选中目录 > 选中文件的父目录 > 唯一可写的根。
  ResourceUri? _targetFolder() {
    final selected = _selected;
    if (selected != null) {
      final isDir = selected.isRoot ||
          (_children[selected.parent]
                  ?.any((e) => e.name == selected.basename && e.isDirectory) ??
              false);
      return isDir ? selected : selected.parent;
    }
    final writable = [
      for (final f in _wb.activeFolders)
        if (_wb.fileSystems.providerOf(f.scheme)?.readOnly == false) f,
    ];
    return writable.length == 1 ? writable.first.root : null;
  }

  Future<void> _run(String command, [List<Object?> args = const []]) async {
    try {
      await _wb.executeCommand(command, args);
    } catch (e) {
      _wb.reportError(e);
    }
  }

  void _select(_Row row) {
    _selected = row.uri;
    _wb.setExplorerSelection(row.uri, isFolder: row.isDirectory);
  }

  Future<void> _onTap(_Row row) async {
    _select(row);
    final folder = row.folder;
    if (folder != null && !folder.isActive) {
      _wb.ui.showMessage(
        folder.state == 'missing'
            ? '「${folder.name}」的数据缺失，请在插件中心检查'
            : '「${folder.name}」所属能力已停用，可在插件中心重新启用',
      );
      setState(() {});
      return;
    }
    if (row.isDirectory) {
      _toggle(row.uri);
      return;
    }
    setState(() {});
    try {
      await _wb.openResource(row.uri);
      widget.onOpened?.call();
    } catch (e) {
      _wb.reportError(e);
    }
  }

  Future<void> _showMenu(_Row row) async {
    _select(row);
    if (row.folder != null && !row.folder!.isActive) return;
    final items = _wb.visibleMenu(MenuIds.explorerContext);
    if (items.isEmpty || !mounted) return;
    final chosen = await showModalBottomSheet<MenuContribution>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        String? lastGroup;
        final tiles = <Widget>[
          ListTile(
            dense: true,
            title: Text(row.name, style: Theme.of(ctx).textTheme.titleSmall),
            subtitle: Text(row.uri.toString()),
          ),
        ];
        for (final item in items) {
          final group = item.group.split('_').first;
          if (lastGroup != null && lastGroup != group) {
            tiles.add(const Divider(height: 1));
          }
          lastGroup = group;
          final command = _wb.contributions.command(item.command)!;
          tiles.add(ListTile(
            leading: Icon(iconByName(command.icon)),
            title: Text(command.title),
            onTap: () => Navigator.pop(ctx, item),
          ));
        }
        return SafeArea(child: ListView(shrinkWrap: true, children: tiles));
      },
    );
    if (chosen != null) await _run(chosen.command, [row.uri]);
  }

  bool _can(String command) =>
      _wb.commands.hasHandler(command) ||
      _wb.contributions.command(command) != null;

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    final theme = Theme.of(context);
    final target = _targetFolder();
    final canWrite = target != null &&
        _wb.fileSystems.providerOf(target.scheme)?.readOnly == false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: Text('资源管理器', style: theme.textTheme.titleSmall),
              ),
              if (_can('explorer.newFile'))
                IconButton(
                  tooltip: '新建文件',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.note_add_outlined, size: 20),
                  onPressed: canWrite
                      ? () => _run('explorer.newFile', [target])
                      : null,
                ),
              if (_can('explorer.newFolder'))
                IconButton(
                  tooltip: '新建文件夹',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.create_new_folder_outlined, size: 20),
                  onPressed: canWrite
                      ? () => _run('explorer.newFolder', [target])
                      : null,
                ),
              IconButton(
                tooltip: '刷新',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _refresh,
              ),
              IconButton(
                tooltip: '全部折叠',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.unfold_less, size: 20),
                onPressed: _collapseAll,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: rows.isEmpty
              ? _EmptyExplorer(workbench: _wb, onRun: _run, can: _can)
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) =>
                      _buildRow(context, rows[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildRow(BuildContext context, _Row row) {
    final theme = Theme.of(context);
    final folder = row.folder;
    final inactive = folder != null && !folder.isActive;
    final expanded = _expanded.contains(row.uri);
    final selected = _selected == row.uri;
    final active = _wb.activeTab?.resource == row.uri;
    final loading = _loading.contains(row.uri);
    final error = _errors[row.uri];
    final color = inactive ? theme.disabledColor : theme.colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : active
                  ? theme.colorScheme.primary.withValues(alpha: 0.06)
                  : Colors.transparent,
          child: InkWell(
            onTap: () => _onTap(row),
            onLongPress: () => _showMenu(row),
            onSecondaryTap: () => _showMenu(row),
            child: Padding(
              padding: EdgeInsets.only(
                left: 8.0 + row.depth * 14,
                right: 4,
              ),
              child: SizedBox(
                height: 36,
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      child: row.isDirectory && !inactive
                          ? Icon(
                              expanded
                                  ? Icons.expand_more
                                  : Icons.chevron_right,
                              size: 18,
                              color: color,
                            )
                          : null,
                    ),
                    Icon(
                      folder != null
                          ? (folder.scheme == 'notes'
                              ? Icons.note_alt_outlined
                              : Icons.folder_special_outlined)
                          : iconForFile(
                              row.name,
                              isDirectory: row.isDirectory,
                              open: expanded,
                            ),
                      size: 18,
                      color: color,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        row.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color,
                          fontWeight: folder != null
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (inactive)
                      Text(
                        folder.state == 'missing' ? '缺失' : '已停用',
                        style: TextStyle(fontSize: 11, color: color),
                      ),
                    if (loading)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    if (!inactive)
                      IconButton(
                        tooltip: '更多操作',
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        icon: const Icon(Icons.more_horiz),
                        onPressed: () => _showMenu(row),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: EdgeInsets.only(left: 36.0 + row.depth * 14, bottom: 4),
            child: Text(
              error,
              style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
            ),
          ),
        if (expanded &&
            !loading &&
            error == null &&
            (_children[row.uri]?.isEmpty ?? false))
          Padding(
            padding: EdgeInsets.only(left: 36.0 + row.depth * 14, bottom: 4),
            child: Text(
              '（空）',
              style: TextStyle(fontSize: 12, color: theme.hintColor),
            ),
          ),
      ],
    );
  }
}

class _EmptyExplorer extends StatelessWidget {
  const _EmptyExplorer({
    required this.workbench,
    required this.onRun,
    required this.can,
  });

  final Workbench workbench;
  final Future<void> Function(String command, [List<Object?> args]) onRun;
  final bool Function(String command) can;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_off_outlined,
              size: 36,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            const Text('工作区里还没有文件夹', textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              '启用笔记能力，或导入一个项目文件夹。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (can('files.importProject'))
                  OutlinedButton(
                    onPressed: () => onRun('files.importProject'),
                    child: const Text('导入项目'),
                  ),
                if (can('workbench.action.openPluginCenter'))
                  OutlinedButton(
                    onPressed: () => onRun('workbench.action.openPluginCenter'),
                    child: const Text('插件中心'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
