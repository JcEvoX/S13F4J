import 'package:flutter/material.dart';

import '../services/workbench.dart';

/// 状态栏：活动资源 + 只读标记 + 编辑器类型 + 插件贡献的状态项。
class WorkbenchStatusBar extends StatelessWidget {
  const WorkbenchStatusBar({super.key, required this.workbench});

  final Workbench workbench;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        workbench,
        workbench.contributions,
        workbench.contextKeys,
      ]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final style = TextStyle(
          fontSize: 12,
          color: theme.colorScheme.onSurfaceVariant,
        );
        final items = [
          for (final item in workbench.contributions.statusBarItems)
            if (workbench.contextKeys.evaluate(item.when)) item,
        ];
        Widget chip(String text, {String? tooltip, String? command}) {
          final label = Text(text, style: style, maxLines: 1);
          final child = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(child: label),
          );
          final wrapped = command == null
              ? child
              : InkWell(
                  onTap: () => workbench.executeCommand(command).catchError(
                    (Object e) {
                      workbench.reportError(e);
                      return null;
                    },
                  ),
                  child: child,
                );
          return tooltip == null
              ? wrapped
              : Tooltip(message: tooltip, child: wrapped);
        }

        final tab = workbench.activeTab;
        final resource = tab?.resource;
        final readOnly = workbench.contextKeys.get('resourceReadOnly') == true;
        return Material(
          color: theme.colorScheme.surfaceContainerHighest,
          child: SizedBox(
            height: 24,
            child: Row(
              children: [
                for (final item in items)
                  if (item.alignment == 'left')
                    chip(item.text,
                        tooltip: item.tooltip, command: item.command),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        resource?.toString() ?? '',
                        style: style,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                if (resource != null && readOnly) chip('只读'),
                if (tab != null)
                  chip(workbench.editors.displayNameOf(tab.viewType)),
                for (final item in items)
                  if (item.alignment == 'right')
                    chip(item.text,
                        tooltip: item.tooltip, command: item.command),
              ],
            ),
          ),
        );
      },
    );
  }
}
