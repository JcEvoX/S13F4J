import 'package:flutter/material.dart';

import '../services/contribution_registry.dart';
import '../services/editor_registry.dart';
import '../services/workbench.dart';
import 'editors/editor_message.dart';
import 'icons.dart';

/// 编辑区：标签条 + 当前编辑器。
///
/// 标签第一次被激活时才构建编辑器，之后切换保活（IndexedStack）。
class EditorArea extends StatefulWidget {
  const EditorArea({super.key, required this.workbench});

  final Workbench workbench;

  @override
  State<EditorArea> createState() => _EditorAreaState();
}

class _EditorAreaState extends State<EditorArea> {
  final Set<String> _built = {};

  Workbench get _wb => widget.workbench;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_wb, _wb.editors]),
      builder: (context, _) {
        final tabs = _wb.tabs;
        final live = {for (final t in tabs) t.id};
        _built.removeWhere((id) => !live.contains(id));
        final active = _wb.activeTab;
        if (active != null) _built.add(active.id);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (tabs.isNotEmpty) TabStrip(workbench: _wb),
            const Divider(height: 1),
            Expanded(
              child: tabs.isEmpty
                  ? _NoEditor(workbench: _wb)
                  : IndexedStack(
                      index: _wb.activeIndex,
                      children: [
                        for (final tab in tabs)
                          _built.contains(tab.id)
                              ? KeyedSubtree(
                                  key: ValueKey(tab.id),
                                  child: _EditorHost(workbench: _wb, tab: tab),
                                )
                              : SizedBox.shrink(
                                  key: ValueKey('empty-${tab.id}')),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _EditorHost extends StatefulWidget {
  const _EditorHost({required this.workbench, required this.tab});

  final Workbench workbench;
  final EditorTab tab;

  @override
  State<_EditorHost> createState() => _EditorHostState();
}

class _EditorHostState extends State<_EditorHost> {
  Workbench get workbench => widget.workbench;
  EditorTab get tab => widget.tab;

  @override
  void initState() {
    super.initState();
    // 会话恢复出来的标签没有经过 openResource，这里补一次懒激活。
    if (!workbench.editors.hasProvider(tab.viewType)) {
      workbench.extensionHost?.activateByEvent('onEditor:${tab.viewType}');
    }
    final scheme = tab.resource?.scheme;
    if (scheme != null) workbench.fileSystems.resolve(scheme);
  }

  @override
  Widget build(BuildContext context) {
    final builder = workbench.editors.builderFor(tab.viewType);
    if (builder != null) return builder(context, tab.input);
    final uri = tab.resource;
    return EditorMessage(
      message: '没有可用的编辑器「${workbench.editors.displayNameOf(tab.viewType)}」。\n'
          '提供它的能力可能已停用，或尚未激活。',
      icon: Icons.extension_off_outlined,
      actions: [
        if (uri != null)
          OutlinedButton(
            onPressed: () async {
              workbench.closeTab(workbench.tabs.indexOf(tab));
              await workbench.openResource(uri, viewType: kTextEditorViewType);
            },
            child: const Text('用文本方式打开'),
          ),
        TextButton(
          onPressed: () => workbench.closeTab(workbench.tabs.indexOf(tab)),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _NoEditor extends StatelessWidget {
  const _NoEditor({required this.workbench});

  final Workbench workbench;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget action(String command, String label, IconData icon) {
      final exists = workbench.commands.hasHandler(command) ||
          workbench.contributions.command(command) != null;
      if (!exists) return const SizedBox.shrink();
      return TextButton.icon(
        onPressed: () =>
            workbench.executeCommand(command).catchError((Object e) {
          workbench.reportError(e);
          return null;
        }),
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.dashboard_customize_outlined,
              size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text('没有打开的编辑器', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          action('workbench.action.quickOpen', '转到文件…', Icons.search),
          action('workbench.action.showCommands', '显示所有命令', Icons.terminal),
          action('workbench.action.openWelcome', '欢迎页',
              Icons.waving_hand_outlined),
        ],
      ),
    );
  }
}

/// 标签条：可横向滚动，右侧「⋯」打开 `editor/title` 菜单与关闭操作。
class TabStrip extends StatelessWidget {
  const TabStrip({super.key, required this.workbench});

  final Workbench workbench;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tabs = workbench.tabs;
    return SizedBox(
      height: 38,
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              itemBuilder: (context, index) => _TabChip(
                workbench: workbench,
                tab: tabs[index],
                index: index,
                active: index == workbench.activeIndex,
              ),
            ),
          ),
          IconButton(
            tooltip: '编辑器操作',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.more_horiz,
                color: theme.colorScheme.onSurfaceVariant),
            onPressed: () => showEditorMenu(context, workbench),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.workbench,
    required this.tab,
    required this.index,
    required this.active,
  });

  final Workbench workbench;
  final EditorTab tab;
  final int index;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: active
          ? scheme.surface
          : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: InkWell(
        onTap: () => workbench.activateTab(index),
        onLongPress: () => showEditorMenu(context, workbench, tabIndex: index),
        onSecondaryTap: () =>
            showEditorMenu(context, workbench, tabIndex: index),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 220, minWidth: 90),
          padding: const EdgeInsets.only(left: 10, right: 2),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: active ? scheme.primary : Colors.transparent,
                width: 2,
              ),
              right: BorderSide(color: theme.dividerColor, width: 0.5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                tab.resource == null
                    ? Icons.waving_hand_outlined
                    : iconForFile(tab.resource!.basename),
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: ValueListenableBuilder<String>(
                  valueListenable: tab.input.title,
                  builder: (_, title, __) => Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: tab.input.dirty,
                builder: (_, dirty, __) => SizedBox(
                  width: 28,
                  height: 28,
                  child: dirty
                      ? Center(
                          child: Container(
                            key: const ValueKey('dirty-dot'),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        )
                      : IconButton(
                          tooltip: '关闭',
                          padding: EdgeInsets.zero,
                          iconSize: 15,
                          icon: const Icon(Icons.close),
                          onPressed: () =>
                              workbench.closeTab(workbench.tabs.indexOf(tab)),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 编辑器菜单：贡献的 `editor/title` 命令 + 打开方式 + 关闭操作。
Future<void> showEditorMenu(
  BuildContext context,
  Workbench workbench, {
  int? tabIndex,
}) async {
  if (tabIndex != null) workbench.activateTab(tabIndex);
  final contributed = workbench.activeTab == null
      ? const <MenuContribution>[]
      : workbench.visibleMenu(MenuIds.editorTitle);
  final index = tabIndex ?? workbench.activeIndex;
  final entries = <(String, String, IconData)>[
    for (final item in contributed)
      (
        item.command,
        workbench.contributions.command(item.command)!.title,
        iconByName(workbench.contributions.command(item.command)!.icon),
      ),
    if (workbench.activeTab?.resource != null)
      ('workbench.action.openWith', '打开方式…', Icons.open_in_new),
    if (index >= 0) ('workbench.action.closeActiveEditor', '关闭', Icons.close),
    if (workbench.tabs.length > 1)
      ('workbench.action.closeOtherEditors', '关闭其他', Icons.tab_unselected),
    if (workbench.tabs.isNotEmpty)
      ('workbench.action.closeAllEditors', '全部关闭', Icons.clear_all),
    ('workbench.action.reopenClosedEditor', '重新打开已关闭的编辑器', Icons.restore),
  ];
  final chosen = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final (command, label, icon) in entries)
            if (workbench.commands.hasHandler(command) ||
                workbench.contributions.command(command) != null)
              ListTile(
                leading: Icon(icon),
                title: Text(label),
                onTap: () => Navigator.pop(ctx, command),
              ),
        ],
      ),
    ),
  );
  if (chosen == null) return;
  try {
    await workbench.executeCommand(chosen);
  } catch (e) {
    workbench.reportError(e);
  }
}
