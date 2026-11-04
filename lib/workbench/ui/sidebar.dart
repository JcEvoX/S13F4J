import 'package:flutter/material.dart';

import '../services/workbench.dart';
import 'icons.dart';

/// 活动栏：贡献的视图容器 + 底部的宿主入口（插件中心 / 设置）。
class ActivityBar extends StatelessWidget {
  const ActivityBar(
      {super.key, required this.workbench, this.drawerMode = false});

  final Workbench workbench;

  /// 抽屉里点击容器只切换内容，不收起侧栏。
  final bool drawerMode;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([workbench, workbench.contributions]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final containers = workbench.contributions.viewContainers;
        Widget bottom(String command, IconData icon, String tooltip) {
          final exists = workbench.commands.hasHandler(command) ||
              workbench.contributions.command(command) != null;
          if (!exists) return const SizedBox.shrink();
          return IconButton(
            tooltip: tooltip,
            icon: Icon(icon),
            color: theme.colorScheme.onSurfaceVariant,
            onPressed: () => workbench.executeCommand(command).catchError(
              (Object e) {
                workbench.reportError(e);
                return null;
              },
            ),
          );
        }

        return Container(
          width: 52,
          color: theme.colorScheme.surfaceContainerHighest,
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 4),
                for (final container in containers)
                  _ActivityButton(
                    key: ValueKey('activity-${container.id}'),
                    icon: iconByName(container.icon),
                    tooltip: container.title,
                    selected: workbench.activeContainer == container.id &&
                        (drawerMode || workbench.sidebarVisible),
                    onPressed: () => workbench.selectContainer(
                      container.id,
                      toggleIfActive: !drawerMode,
                    ),
                  ),
                const Spacer(),
                bottom('workbench.action.showCommands', Icons.terminal, '命令面板'),
                bottom('workbench.action.openPluginCenter',
                    Icons.extension_outlined, '插件中心'),
                bottom('workbench.action.openSettings', Icons.settings_outlined,
                    '设置'),
                const SizedBox(height: 4),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ActivityButton extends StatelessWidget {
  const _ActivityButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: selected ? scheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon),
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
        onPressed: onPressed,
      ),
    );
  }
}

/// 侧栏：显示当前容器里（`when` 通过的）全部视图。
class WorkbenchSidebar extends StatelessWidget {
  const WorkbenchSidebar({super.key, required this.workbench, this.onOpened});

  final Workbench workbench;
  final VoidCallback? onOpened;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        workbench,
        workbench.contributions,
        workbench.views,
        workbench.contextKeys,
      ]),
      builder: (context, _) {
        final views = [
          for (final view
              in workbench.contributions.viewsOf(workbench.activeContainer))
            if (workbench.contextKeys.evaluate(view.when)) view,
        ];
        if (views.isEmpty) {
          return const Center(child: Text('这个容器还没有视图'));
        }
        if (views.length == 1) {
          return _ViewHost(
            key: ValueKey(views.single.id),
            workbench: workbench,
            viewId: views.single.id,
            onOpened: onOpened,
          );
        }
        return ListView(
          children: [
            for (final view in views)
              ExpansionTile(
                key: ValueKey(view.id),
                initiallyExpanded: true,
                dense: true,
                title: Text(view.name),
                children: [
                  SizedBox(
                    height: 320,
                    child: _ViewHost(
                      workbench: workbench,
                      viewId: view.id,
                      onOpened: onOpened,
                    ),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _ViewHost extends StatefulWidget {
  const _ViewHost({
    super.key,
    required this.workbench,
    required this.viewId,
    this.onOpened,
  });

  final Workbench workbench;
  final String viewId;
  final VoidCallback? onOpened;

  @override
  State<_ViewHost> createState() => _ViewHostState();
}

class _ViewHostState extends State<_ViewHost> {
  @override
  void initState() {
    super.initState();
    if (widget.workbench.views.builderFor(widget.viewId) == null) {
      widget.workbench.extensionHost
          ?.activateByEvent('onView:${widget.viewId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final builder = widget.workbench.views.builderFor(widget.viewId);
    if (builder == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return OpenedScope(
      onOpened: widget.onOpened,
      child: Builder(builder: (ctx) => builder(ctx, widget.workbench)),
    );
  }
}

/// 视图内容（如资源管理器）通过它通知外壳「用户已打开文件」。
class OpenedScope extends InheritedWidget {
  const OpenedScope({super.key, this.onOpened, required super.child});

  final VoidCallback? onOpened;

  static VoidCallback? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OpenedScope>()?.onOpened;

  @override
  bool updateShouldNotify(OpenedScope oldWidget) =>
      onOpened != oldWidget.onOpened;
}
