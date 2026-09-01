import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/note.dart';
import '../../state/note_provider.dart';
import '../../widgets/node_icon.dart';
import '../../widgets/wallpaper_background.dart';
import '../editor/editor_page.dart';
import '../webdav/webdav_page.dart';
import '../recyclebin/recyclebin_page.dart';
import '../recent/recent_page.dart';
import '../search/search_page.dart';
import '../settings/settings_page.dart';
import '../statistics/statistics_page.dart';
import '../backuprestore/backup_restore_page.dart';

/// 首页：类文件管理器的多层级文章管理。
///
/// - 无限嵌套的文件夹 / 文章
/// - 长按进入多选，支持多选移动 / 删除
/// - 拖拽排序（下拉到底触发，长按后拖拽）
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NoteProvider>().loadFolder(null);
    });
  }

  Future<void> _confirmDelete(List<NotePadNode> targets) async {
    final provider = context.read<NoteProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移入回收站'),
        content: Text('确定要将选中的 ${targets.length} 个项目移入回收站吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('移入'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await provider.deleteToRecycle(targets);
    }
  }

  Future<void> _showMoveDialog(List<NotePadNode> targets) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _MoveDialog(targets: targets),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NoteProvider>();
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 沉浸式标题栏：状态栏图标颜色随主题切换，壁纸铺满整屏。
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: WallpaperBackground(
          child: Column(
            children: [
              _buildTopBar(context, provider, colors),
              if (provider.selectionMode)
                _buildSelectionBar(context, provider),
              Expanded(child: _buildBody(provider)),
            ],
          ),
        ),
        floatingActionButton: provider.selectionMode
            ? null
            : _SpeedDial(
                color: colors.primary,
                onAddNote: () => _showCreateSheet(provider, isFolder: false),
                onAddFolder: () => _showCreateSheet(provider, isFolder: true),
              ),
      ),
    );
  }

  /// 自绘沉浸式标题栏（贴近原版 TitleBar 的简洁观感）。
  Widget _buildTopBar(
    BuildContext context,
    NoteProvider provider,
    ColorScheme colors,
  ) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            if (provider.currentParentId != null)
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: '返回上层',
                onPressed: () => context.read<NoteProvider>().navigateUp(),
              ),
            Expanded(
              child: Text(
                provider.currentParentId == null ? 'NotePad' : '文件夹',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: '搜索',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SearchPage()),
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (v) => _handleMenu(v, provider),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'new_folder', child: Text('新建文件夹')),
                const PopupMenuItem(value: 'new_note', child: Text('新建文章')),
                const PopupMenuItem(value: 'recycle', child: Text('回收站')),
                const PopupMenuItem(value: 'webdav', child: Text('WebDAV 备份')),
                const PopupMenuItem(value: 'settings', child: Text('设置')),
                const PopupMenuItem(value: 'statistics', child: Text('统计')),
                const PopupMenuItem(value: 'recent', child: Text('最近编辑')),
                const PopupMenuItem(value: 'backup', child: Text('备份和恢复')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _handleMenu(String value, NoteProvider provider) {
    switch (value) {
      case 'new_folder':
        _showCreateSheet(provider, isFolder: true);
        break;
      case 'new_note':
        _showCreateSheet(provider, isFolder: false);
        break;
      case 'recycle':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RecycleBinPage()),
        );
        break;
      case 'webdav':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const WebDavPage()),
        );
        break;
      case 'settings':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsPage()),
        );
        break;
      case 'statistics':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const StatisticsPage()),
        );
        break;
      case 'recent':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RecentPage()),
        );
        break;
      case 'backup':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BackupRestorePage()),
        );
        break;
    }
  }

  /// 底部选择操作栏（多选模式下）。
  Widget _buildSelectionBar(BuildContext context, NoteProvider provider) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.select_all),
            onPressed: provider.selectedIds.length != provider.nodes.length
                ? () => provider.enterFullSelection()
                : () => provider.exitSelection(),
          ),
          Text('已选 ${provider.selectedIds.length}'),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.drive_file_move),
            tooltip: '移动',
            onPressed: provider.selectedNodes.isEmpty
                ? null
                : () => _showMoveDialog(provider.selectedNodes),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除',
            onPressed: provider.selectedNodes.isEmpty
                ? null
                : () => _confirmDelete(provider.selectedNodes),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => provider.exitSelection(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(NoteProvider provider) {
    if (provider.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.error != null) {
      return _ErrorView(
        message: provider.error!,
        onRetry: () => provider.loadFolder(provider.currentParentId),
      );
    }
    if (provider.nodes.isEmpty) {
      return _EmptyHint(onCreate: () => _showCreateSheet(provider));
    }
    final onReorder = provider.reorder;
    return ReorderableListView(
      padding: const EdgeInsets.only(bottom: 96),
      onReorder: onReorder,
      buildDefaultDragHandles: false,
      children: [
        for (final node in provider.nodes)
          _buildTile(context, provider, node),
      ],
    );
  }

  Widget _buildTile(BuildContext context, NoteProvider provider, NotePadNode node) {
    final selected = provider.selectedIds.contains(node.id);
    return Card(
      key: ValueKey(node.id),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: Icon(
          nodeIcon(node),
          color: selected ? Theme.of(context).colorScheme.primary : null,
        ),
        title: Text(node.title.isEmpty ? '未命名' : node.title),
        subtitle: node.isFolder ? null : _subtitle(node),
        trailing: provider.selectionMode
            ? Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
              )
            : ReorderableDragStartListener(
                index: provider.nodes.indexOf(node),
                child: const Icon(Icons.drag_handle),
              ),
        onTap: () {
          if (provider.selectionMode) {
            provider.toggleSelection(node.id);
            return;
          }
          if (node.isFolder) {
            context.read<NoteProvider>().openFolder(node);
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => EditorPage(nodeId: node.id)),
            );
          }
        },
        onLongPress: () {
          if (!provider.selectionMode) {
            provider.enterSelection(node);
          }
        },
      ),
    );
  }

  Widget? _subtitle(NotePadNode node) {
    if (node.content.trim().isEmpty) return null;
    final firstLine = node.content.trim().split('\n').first;
    if (firstLine == node.title) return null;
    return Text(
      firstLine,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
    );
  }

  /// 新建文件夹 / 文章 表单。
  void _showCreateSheet(NoteProvider provider, {bool isFolder = false}) {
    final controller = TextEditingController();
    final isNote = !isFolder;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isNote ? '新建文章' : '新建文件夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: isNote ? '输入标题 / 正文（可为空开始写）' : '输入文件夹名称',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final title = controller.text.trim();
              Navigator.pop(ctx);
              if (title.isEmpty) return;
              final node =
                  await context.read<NoteProvider>().createNode(isFolder: isFolder, title: title);
              if (!ctx.mounted) return;
              if (isNote) {
                Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) => EditorPage(nodeId: node.id),
                  ),
                );
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }
}

/// 数据加载失败的错误提示（替代无限转圈）。
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text('数据加载失败'),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

/// 空状态提示。
class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open, size: 72, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text('空空如也', style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          Text('点击右下角 + 新建文章或文件夹',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: onCreate,
            child: const Text('新建'),
          ),
        ],
      ),
    );
  }
}

/// 移动节点到其它层级对话框（展示可选的目标文件夹）。
class _MoveDialog extends StatefulWidget {
  const _MoveDialog({required this.targets});

  final List<NotePadNode> targets;

  @override
  State<_MoveDialog> createState() => _MoveDialogState();
}

class _MoveDialogState extends State<_MoveDialog> {
  int? _selectedIndex;
  List<NotePadNode> _folders = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<NoteProvider>();
      final all = await provider.allFolders();
      if (!mounted) return;
      setState(() {
        _folders = all;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: Text('移动到文件夹（${widget.targets.length} 项）'),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            '移动后会从当前文件夹中移除',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ),
        Flexible(
          child: SizedBox(
            height: 320,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (var i = 0; i < _folders.length; i++)
                  RadioListTile<int>(
                    value: i,
                    groupValue: _selectedIndex,
                    dense: true,
                    title: Text(_folders[i].title.isEmpty ? '未命名' : _folders[i].title),
                    onChanged: (v) => setState(() => _selectedIndex = v),
                  ),
                if (_folders.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '暂无其它文件夹',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _selectedIndex == null
                    ? null
                    : () async {
                        await context.read<NoteProvider>().moveSelectedTo(
                              _folders[_selectedIndex!].id,
                            );
                        if (!context.mounted) return;
                        Navigator.pop(context);
                      },
                child: const Text('移动'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 右下角可展开的 Speed Dial（贴近原版 speed-dial 交互）。
///
/// 主按钮点击后在下方展开「新建文章」「新建文件夹」两个子项，
/// 点击空白或主按钮收起。
class _SpeedDial extends StatefulWidget {
  const _SpeedDial({
    required this.color,
    required this.onAddNote,
    required this.onAddFolder,
  });

  final Color color;
  final VoidCallback onAddNote;
  final VoidCallback onAddFolder;

  @override
  State<_SpeedDial> createState() => _SpeedDialState();
}

class _SpeedDialState extends State<_SpeedDial> {
  bool _open = false;

  void _toggle() {
    setState(() => _open = !_open);
  }

  void _run(VoidCallback action) {
    setState(() => _open = false);
    action();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    final onColor = color.computeLuminance() > 0.5
        ? Colors.black
        : Colors.white;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_open) ...[
          _dialItem(
            icon: Icons.create_outlined,
            label: '新建文章',
            color: color,
            onColor: onColor,
            onTap: () => _run(widget.onAddNote),
          ),
          const SizedBox(height: 12),
          _dialItem(
            icon: Icons.create_new_folder_outlined,
            label: '新建文件夹',
            color: color,
            onColor: onColor,
            onTap: () => _run(widget.onAddFolder),
          ),
          const SizedBox(height: 12),
        ],
        _mainButton(color: color, onColor: onColor),
      ],
    );
  }

  Widget _dialItem({
    required IconData icon,
    required String label,
    required Color color,
    required Color onColor,
    required VoidCallback onTap,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
        ),
        const SizedBox(width: 8),
        FloatingActionButton.small(
          heroTag: 'dial_$label',
          backgroundColor: color,
          foregroundColor: onColor,
          onPressed: onTap,
          child: Icon(icon),
        ),
      ],
    );
  }

  Widget _mainButton({required Color color, required Color onColor}) {
    return FloatingActionButton(
      heroTag: 'dial_main',
      onPressed: _toggle,
      child: Icon(_open ? Icons.close : Icons.add),
    );
  }
}