import '../../ui/backuprestore/backup_restore_page.dart';
import '../../ui/plugins/plugin_center_page.dart';
import '../../ui/recyclebin/recyclebin_page.dart';
import '../../ui/settings/settings_page.dart';
import '../base/resource_uri.dart';
import '../services/command_registry.dart';
import '../services/editor_registry.dart';
import '../services/extension_host.dart';
import '../services/workbench.dart';
import '../ui/editors/text_editor.dart';
import '../ui/editors/welcome_editor.dart';
import '../ui/explorer_view.dart';
import '../ui/sidebar.dart';

const String kCorePluginId = 'workbench.core';

/// 宿主自带的贡献：与插件走同一套贡献点，只是不可停用。
PluginInfo coreExtensionInfo() => const PluginInfo(
      id: kCorePluginId,
      capability: kCorePluginId,
      enabled: true,
      activationEvents: ['onStartup'],
      contributes: {
        'commands': [
          {
            'command': 'workbench.action.showCommands',
            'title': '显示所有命令',
            'category': '视图',
            'icon': 'code'
          },
          {
            'command': 'workbench.action.quickOpen',
            'title': '转到文件…',
            'category': '文件',
            'icon': 'search'
          },
          {
            'command': 'workbench.action.openWelcome',
            'title': '欢迎',
            'category': '视图'
          },
          {
            'command': 'workbench.action.toggleSidebar',
            'title': '切换侧栏',
            'category': '视图'
          },
          {
            'command': 'workbench.action.closeActiveEditor',
            'title': '关闭当前编辑器',
            'category': '编辑器',
            'when': 'activeEditor'
          },
          {
            'command': 'workbench.action.closeOtherEditors',
            'title': '关闭其他编辑器',
            'category': '编辑器',
            'when': 'openEditorCount > 1'
          },
          {
            'command': 'workbench.action.closeAllEditors',
            'title': '关闭全部编辑器',
            'category': '编辑器',
            'when': 'activeEditor'
          },
          {
            'command': 'workbench.action.reopenClosedEditor',
            'title': '重新打开已关闭的编辑器',
            'category': '编辑器'
          },
          {
            'command': 'workbench.action.nextEditor',
            'title': '下一个编辑器',
            'category': '编辑器',
            'when': 'openEditorCount > 1'
          },
          {
            'command': 'workbench.action.previousEditor',
            'title': '上一个编辑器',
            'category': '编辑器',
            'when': 'openEditorCount > 1'
          },
          {
            'command': 'workbench.action.openWith',
            'title': '打开方式…',
            'category': '编辑器',
            'when': 'resourceScheme'
          },
          {
            'command': 'workbench.action.openPluginCenter',
            'title': '打开插件中心',
            'category': '管理',
            'icon': 'extension'
          },
          {
            'command': 'workbench.action.openSettings',
            'title': '打开设置',
            'category': '管理',
            'icon': 'settings'
          },
          {
            'command': 'workbench.action.openBackup',
            'title': '备份与恢复',
            'category': '管理'
          },
          {
            'command': 'workbench.action.openRecycleBin',
            'title': '打开回收站',
            'category': '管理'
          },
          {
            'command': 'explorer.newFile',
            'title': '新建文件',
            'category': '文件',
            'when': 'workspaceFolderCount > 0',
            'icon': 'description'
          },
          {
            'command': 'explorer.newFolder',
            'title': '新建文件夹',
            'category': '文件',
            'when': 'workspaceFolderCount > 0',
            'icon': 'folder'
          },
          {'command': 'explorer.rename', 'title': '重命名', 'category': '文件'},
          {'command': 'explorer.delete', 'title': '删除', 'category': '文件'},
          {'command': 'explorer.refresh', 'title': '刷新资源管理器', 'category': '文件'},
        ],
        'menus': {
          'commandPalette': [
            {
              'command': 'explorer.rename',
              'when':
                  'explorerResourceScheme && !explorerResourceIsRoot && !explorerResourceReadOnly'
            },
            {
              'command': 'explorer.delete',
              'when':
                  'explorerResourceScheme && !explorerResourceIsRoot && !explorerResourceReadOnly'
            },
          ],
          'explorer/context': [
            {
              'command': 'explorer.newFile',
              'when': 'explorerResourceIsFolder && !explorerResourceReadOnly',
              'group': '1_create',
              'order': 1
            },
            {
              'command': 'explorer.newFolder',
              'when': 'explorerResourceIsFolder && !explorerResourceReadOnly',
              'group': '1_create',
              'order': 2
            },
            {
              'command': 'explorer.rename',
              'when': '!explorerResourceIsRoot && !explorerResourceReadOnly',
              'group': '2_modify',
              'order': 1
            },
            {
              'command': 'explorer.delete',
              'when': '!explorerResourceIsRoot && !explorerResourceReadOnly',
              'group': '2_modify',
              'order': 2
            },
          ],
        },
        'viewsContainers': {
          'activitybar': [
            {'id': 'explorer', 'title': '资源管理器', 'icon': 'folder_open'},
          ],
        },
        'views': {
          'explorer': [
            {'id': 'explorer.workspace', 'name': '工作区'},
          ],
        },
        'editors': [
          {
            'viewType': kTextEditorViewType,
            'displayName': '文本',
            'priority': 'builtin',
            'selector': [<String, Object?>{}],
          },
        ],
      },
    );

/// `workbench.core`：通用命令、文本编辑器、欢迎页、资源管理器视图。
class CoreExtension extends HostExtension {
  @override
  void activate(ExtensionContext context) {
    final workbench = context.workbench;

    context.registerEditorProvider(
      kTextEditorViewType,
      (_, input) => TextEditorView(workbench: workbench, input: input),
    );
    context.registerEditorProvider(
      kWelcomeViewType,
      (_, input) => WelcomeEditorView(workbench: workbench),
    );
    context.registerViewProvider(
      'explorer.workspace',
      (ctx, wb) => ExplorerView(workbench: wb, onOpened: OpenedScope.of(ctx)),
    );

    void command(String id, CommandHandler handler) =>
        context.registerCommand(id, handler);

    command('workbench.action.showCommands', (ctx) async {
      await ctx.workbench.ui.showQuickOpen(initialText: '>');
      return null;
    });
    command('workbench.action.quickOpen', (ctx) async {
      await ctx.workbench.ui.showQuickOpen();
      return null;
    });
    command('workbench.action.openWelcome', (ctx) {
      ctx.workbench.openEditor(kWelcomeViewType, title: '欢迎');
      return null;
    });
    command('workbench.action.toggleSidebar', (ctx) {
      ctx.workbench.toggleSidebar();
      return null;
    });
    command('workbench.action.closeActiveEditor', (ctx) {
      ctx.workbench.closeActiveTab();
      return null;
    });
    command('workbench.action.closeOtherEditors', (ctx) {
      ctx.workbench.closeOtherTabs(ctx.workbench.activeIndex);
      return null;
    });
    command('workbench.action.closeAllEditors', (ctx) {
      ctx.workbench.closeAllTabs();
      return null;
    });
    command('workbench.action.reopenClosedEditor', (ctx) async {
      await ctx.workbench.reopenClosedTab();
      return null;
    });
    command('workbench.action.nextEditor', (ctx) {
      ctx.workbench.nextTab();
      return null;
    });
    command('workbench.action.previousEditor', (ctx) {
      ctx.workbench.previousTab();
      return null;
    });
    command('workbench.action.openWith', _openWith);

    command('workbench.action.openPluginCenter', (ctx) async {
      await ctx.workbench.ui.showPage((_) => const PluginCenterPage());
      return null;
    });
    command('workbench.action.openSettings', (ctx) async {
      await ctx.workbench.ui.showPage((_) => const SettingsPage());
      return null;
    });
    command('workbench.action.openBackup', (ctx) async {
      await ctx.workbench.ui.showPage((_) => const BackupRestorePage());
      return null;
    });
    command('workbench.action.openRecycleBin', (ctx) async {
      await ctx.workbench.ui.showPage((_) => const RecycleBinPage());
      return null;
    });

    command('explorer.refresh', (ctx) async {
      await ctx.workbench.refreshWorkspace();
      return null;
    });
    command('explorer.newFile', (ctx) => _create(ctx, isFolder: false));
    command('explorer.newFolder', (ctx) => _create(ctx, isFolder: true));
    command('explorer.rename', _rename);
    command('explorer.delete', _delete);
  }

  /// 目录参数：显式参数 > 资源管理器选中项（文件取其父目录）。
  static Future<ResourceUri?> _folderOf(CommandContext ctx) async {
    final workbench = ctx.workbench;
    final explicit = ctx.arg<ResourceUri>(0) ?? workbench.explorerSelection;
    if (explicit == null) {
      final writable = [
        for (final f in workbench.activeFolders)
          if (workbench.fileSystems.providerOf(f.scheme)?.readOnly == false) f,
      ];
      return writable.length == 1 ? writable.first.root : null;
    }
    final stat = await workbench.fileSystems.stat(explicit);
    return stat.isDirectory ? explicit : explicit.parent;
  }

  static Future<Object?> _create(CommandContext ctx,
      {required bool isFolder}) async {
    final workbench = ctx.workbench;
    final folder = await _folderOf(ctx);
    if (folder == null) {
      workbench.ui.showMessage('请先在资源管理器中选择一个文件夹');
      return null;
    }
    if (await workbench.fileSystems.isReadOnly(folder)) {
      workbench.ui.showMessage('该位置是只读的，不能新建');
      return null;
    }
    final name = await workbench.ui.prompt(
      title: isFolder ? '新建文件夹' : '新建文件',
      hint: isFolder ? '文件夹名称' : '文件名称',
    );
    if (name == null || name.trim().isEmpty) return null;
    final created = isFolder
        ? await workbench.fileSystems.createDirectory(folder, name.trim())
        : await workbench.fileSystems.createFile(folder, name.trim());
    if (!isFolder) await workbench.openResource(created);
    return created;
  }

  static Future<Object?> _rename(CommandContext ctx) async {
    final workbench = ctx.workbench;
    final uri = ctx.arg<ResourceUri>(0) ?? workbench.explorerSelection;
    if (uri == null || uri.isRoot) return null;
    final provider = await workbench.fileSystems.resolve(uri.scheme);
    final name = await workbench.ui.prompt(
      title: '重命名',
      initialValue: provider?.displayName(uri) ?? uri.basename,
    );
    if (name == null || name.trim().isEmpty) return null;
    final renamed = await workbench.fileSystems.rename(uri, name.trim());
    workbench.closeTabsUnder(uri);
    return renamed;
  }

  static Future<Object?> _delete(CommandContext ctx) async {
    final workbench = ctx.workbench;
    final uri = ctx.arg<ResourceUri>(0) ?? workbench.explorerSelection;
    if (uri == null || uri.isRoot) return null;
    final provider = await workbench.fileSystems.resolve(uri.scheme);
    final toTrash = provider?.deleteGoesToTrash ?? false;
    final ok = await workbench.ui.confirm(
      title: '删除「${provider?.displayName(uri) ?? uri.basename}」？',
      message: toTrash ? '将移入回收站，可随时恢复。' : '此操作不可恢复。',
      confirmLabel: '删除',
      destructive: !toTrash,
    );
    if (!ok) return null;
    await workbench.fileSystems.delete(uri);
    workbench.closeTabsUnder(uri);
    workbench.setExplorerSelection(null);
    return null;
  }

  static Future<Object?> _openWith(CommandContext ctx) async {
    final workbench = ctx.workbench;
    final uri = ctx.arg<ResourceUri>(0) ?? workbench.activeTab?.resource;
    if (uri == null) return null;
    final candidates = <String>{
      for (final editor in workbench.editors.candidates(uri)) editor.viewType,
      kTextEditorViewType,
    }.toList();
    final chosen = await workbench.ui.pickOne(
      title: '选择打开方式',
      items: [
        for (final viewType in candidates)
          QuickPickItem(
            id: viewType,
            label: workbench.editors.displayNameOf(viewType),
            detail: viewType,
          ),
      ],
    );
    if (chosen == null) return null;
    await workbench.openResource(uri, viewType: chosen);
    return null;
  }
}
