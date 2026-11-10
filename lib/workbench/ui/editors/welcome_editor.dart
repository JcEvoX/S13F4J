import 'package:flutter/material.dart';

import '../../services/workbench.dart';
import '../icons.dart';

/// 欢迎页：常用入口 + 最近文件。入口只在对应命令存在时显示，
/// 因此停用某个能力后，相关按钮自动消失。
class WelcomeEditorView extends StatelessWidget {
  const WelcomeEditorView({super.key, required this.workbench});

  final Workbench workbench;

  static const _entries = <(String, String, IconData)>[
    ('notes.newNote', '新建笔记', Icons.note_add_outlined),
    ('workbench.action.quickOpen', '转到文件…', Icons.search),
    ('workbench.action.showCommands', '命令面板', Icons.terminal),
    ('files.importProject', '导入项目', Icons.create_new_folder_outlined),
    ('workbench.action.openPluginCenter', '插件中心', Icons.extension_outlined),
    ('workbench.action.openBackup', '备份与恢复', Icons.backup_outlined),
  ];

  bool _exists(String command) =>
      workbench.commands.hasHandler(command) ||
      workbench.contributions.command(command) != null;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([workbench, workbench.contributions]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final recent = workbench.recentResources.take(8).toList();
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('NotePad 工作台', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              '笔记只是其中一种能力。资源管理器、命令面板与编辑器对所有能力一视同仁。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (command, label, icon) in _entries)
                  if (_exists(command))
                    ActionChip(
                      avatar: Icon(icon, size: 18),
                      label: Text(label),
                      onPressed: () =>
                          workbench.executeCommand(command).catchError(
                        (Object e) {
                          workbench.reportError(e);
                          return null;
                        },
                      ),
                    ),
              ],
            ),
            const SizedBox(height: 24),
            Text('最近', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            if (recent.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '还没有打开过文件',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            for (final uri in recent)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(iconForFile(uri.basename), size: 20),
                title: Text(workbench.titleFor(uri)),
                subtitle: Text(uri.toString(),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => workbench.openResource(uri),
              ),
          ],
        );
      },
    );
  }
}
