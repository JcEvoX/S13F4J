import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/note.dart';
import '../../state/note_provider.dart';
import '../../widgets/node_icon.dart';
import '../../widgets/wallpaper_background.dart';
import '../editor/editor_page.dart';
import '../webdav/webdav_page.dart';
import '../recyclebin/recyclebin_page.dart';
import '../search/search_page.dart';
import '../settings/settings_page.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: Text(provider.currentParentId == null ? 'NotePad' : '.. 返回上层'),
        leading: provider.currentParentId != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () =>
                    context.read<NoteProvider>().navigateUp(),
              )
            : null,
        actions: [
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
            ],
          ),
        ],
        bottom: provider.selectionMode
            ? PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: _buildSelectionBar(context, provider),
              )
            : null,
      ),
      body: WallpaperBackground(
        child: _buildBody(provider),
      ),
      floatingActionButton: provider.selectionMode
          ? null
          : FloatingActionButton(
              heroTag: 'fab_add',
              onPressed: () => _showCreateSheet(provider),
              child: const Icon(Icons.add),
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