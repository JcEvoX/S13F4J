import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/note.dart';
import '../../state/note_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/article_card.dart';
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
  /// 每个列表项的 GlobalKey，用于「定位正在编辑的文章」滚动定位。
  final Map<String, GlobalKey> _tileKeys = {};

  GlobalKey _tileKey(String id) => _tileKeys.putIfAbsent(id, () => GlobalKey());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NoteProvider>().loadFolder(null);
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 新建文章：无需输入标题，直接创建空文章并进入编辑器。
  Future<void> _createNoteDirectly() async {
    final provider = context.read<NoteProvider>();
    final node = await provider.createNode(isFolder: false, title: '');
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditorPage(nodeId: node.id)),
    );
  }

  /// 新建文件夹：底部弹出输入名称的面板（贴近原版 DialogX BottomDialog）。
  Future<void> _showFolderCreateDialog() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _FolderCreateSheet(),
    );
  }

  /// 定位当前正在编辑的文章：逐层进入所在文件夹并滚动到该文章。
  Future<void> _locateEditingNote() async {
    final provider = context.read<NoteProvider>();
    final id = provider.currentEditingNodeId;
    if (id == null) {
      _showSnack('当前没有正在编辑的文章');
      return;
    }
    final index = await provider.navigateToNode(id);
    if (!mounted) return;
    if (index == null) {
      _showSnack('未找到正在编辑的文章（可能已删除或移入回收站）');
      return;
    }
    // 等待列表按新层级渲染完成后，再滚动到目标项。
    await Future<void>.delayed(Duration.zero);
    await WidgetsBinding.instance.endOfFrame;
    final ctx = _tileKeys[id]?.currentContext;
    if (ctx == null) {
      _showSnack('正在编辑的文章不在当前列表中');
      return;
    }
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: 0.25,
    );
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

  /// 先取好可选目标文件夹，再弹出选择弹窗。
  ///
  /// 关键点：文件夹列表在 showDialog 之前就 `await` 取完，
  /// 弹窗构建时同步拿到数据，不在 initState 里异步触发 setState，
  /// 避免出现「点击移动后无弹窗 / 锁屏」的问题。
  Future<void> _showMoveDialog(List<NotePadNode> targets) async {
    debugPrint('[MoveDialog] 打开移动弹窗，目标 ${targets.length} 项');
    final provider = context.read<NoteProvider>();
    List<NotePadNode> folders;
    try {
      folders = await provider.allFolders();
    } catch (e) {
      debugPrint('[MoveDialog] 加载目标文件夹失败: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('加载目标文件夹失败，请重试')),
      );
      return;
    }
    // 从可选目标里排除「选中的文件夹本身」，避免把文件夹移进自己。
    final excludeIds =
        targets.where((t) => t.isFolder).map((t) => t.id).toSet();
    final eligible = folders.where((f) => !excludeIds.contains(f.id)).toList();
    debugPrint('[MoveDialog] 可选目标文件夹 ${eligible.length} 个');
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _MoveDialog(targets: targets, folders: eligible),
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
                onAddNote: _createNoteDirectly,
                onAddFolder: _showFolderCreateDialog,
                onLocate: _locateEditingNote,
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
              child: Row(
                children: [
                  // 顶栏文件夹图标（贴近原版 TitleBar）。
                  const NodeIcon(isFolder: true, size: 22),
                  const SizedBox(width: 8),
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
                ],
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
        _showFolderCreateDialog();
        break;
      case 'new_note':
        _createNoteDirectly();
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
      return _EmptyHint(onCreate: _createNoteDirectly);
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
    final dim = Theme.of(context).brightness == Brightness.dark
        ? Colors.white54
        : Colors.grey.shade600;
    final isFolder = node.isFolder;

    final Widget trailing;
    if (provider.selectionMode) {
      trailing = Icon(
        selected ? Icons.check_circle : Icons.radio_button_unchecked,
        color: selected ? Theme.of(context).colorScheme.primary : dim,
        size: 22,
      );
    } else if (isFolder) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _moreButton(node),
          Icon(Icons.chevron_right, size: 20, color: dim),
        ],
      );
    } else {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _moreButton(node),
          ReorderableDragStartListener(
            index: provider.nodes.indexOf(node),
            child: Icon(Icons.drag_indicator, size: 20, color: dim),
          ),
        ],
      );
    }

    return ArticleCard(
      key: _tileKey(node.id),
      node: node,
      selected: selected,
      contentEndPadding: provider.selectionMode ? 40 : 80,
      subtitle: _cardSubtitle(node),
      time: isFolder ? null : _relativeTime(node.updatedAt),
      trailing: trailing,
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
    );
  }

  /// more_vert：打开原版风格的单条目操作菜单（重命名 / 移动 / 移入回收站）。
  Widget _moreButton(NotePadNode node) {
    final dim = Theme.of(context).brightness == Brightness.dark
        ? Colors.white54
        : Colors.grey.shade600;
    return IconButton(
      icon: Icon(Icons.more_vert, size: 20, color: dim.withOpacity(0.75)),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      visualDensity: VisualDensity.compact,
      onPressed: () => _showItemMenu(node),
    );
  }

  Future<void> _showItemMenu(NotePadNode node) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('重命名'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outlined),
              title: const Text('移动'),
              onTap: () => Navigator.pop(ctx, 'move'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(ctx).colorScheme.error),
              title: Text('移入回收站',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'rename':
        await _rename(node);
        break;
      case 'move':
        await _showMoveDialog([node]);
        break;
      case 'delete':
        await _confirmDelete([node]);
        break;
    }
  }

  /// 重命名：底部弹出输入框（贴近原版 DialogX 风格）。
  Future<void> _rename(NotePadNode node) async {
    final controller = TextEditingController(text: node.title);
    final title = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RenameSheet(controller: controller, isFolder: node.isFolder),
    );
    controller.dispose();
    if (!mounted || title == null || title.trim().isEmpty) return;
    final provider = context.read<NoteProvider>();
    await provider.updateNode(node.copyWith(title: title.trim()));
    await provider.refresh();
  }

  /// 卡片副文本：文章为内容预览，文件夹显示为空。
  String? _cardSubtitle(NotePadNode node) {
    if (node.isFolder) return '';
    return node.content.trim().split('\n').first;
  }

  /// 相对时间（纯 Dart 计算，避免依赖 intl 本地化初始化）。
  String _relativeTime(int ms) {
    if (ms <= 0) return '—';
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${t.month}月${t.day}日';
  }
}

/// 新建文件夹底部面板（贴近原版 DialogX BottomDialog）。
///
/// 从屏幕底部滑出、顶部圆角 + 拖拽把手，含标题、文件夹图标、
/// 名称输入框以及右下角「取消 / 确定」按钮。
class _FolderCreateSheet extends StatefulWidget {
  const _FolderCreateSheet();

  @override
  State<_FolderCreateSheet> createState() => _FolderCreateSheetState();
}

class _FolderCreateSheetState extends State<_FolderCreateSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    final provider = context.read<NoteProvider>();
    await provider.createNode(isFolder: true, title: title);
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = theme.colorScheme;
    // 输入框弹出时整体上移，避免被键盘遮挡。
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2E2E2E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 拖拽把手（原版 img_tab）。
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black26,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const NodeIcon(isFolder: true, size: 24),
                  const SizedBox(width: 10),
                  Text(
                    '新建文件夹',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _create(),
                decoration: const InputDecoration(
                  hintText: '请输入文件夹名称',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _create,
                    child: const Text('确定'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 重命名底部面板（贴近原版 DialogX BottomDialog 风格）。
class _RenameSheet extends StatefulWidget {
  const _RenameSheet({required this.controller, required this.isFolder});

  final TextEditingController controller;
  final bool isFolder;

  @override
  State<_RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends State<_RenameSheet> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = theme.colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2E2E2E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black26,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  NodeIcon(isFolder: widget.isFolder, size: 24),
                  const SizedBox(width: 10),
                  Text(
                    widget.isFolder ? '重命名文件夹' : '重命名文章',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: widget.controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  hintText: '请输入新名称',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _submit,
                    child: const Text('确定'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    final title = widget.controller.text.trim();
    if (title.isEmpty) return;
    Navigator.pop(context, title);
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
          const NodeIcon(isFolder: true, size: 72),
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
///
/// 文件夹列表由调用方在弹窗前已取好并传入，构建过程全同步，
/// 不再依赖 initState 异步 setState。
class _MoveDialog extends StatefulWidget {
  const _MoveDialog({required this.targets, required this.folders});

  final List<NotePadNode> targets;
  final List<NotePadNode> folders;

  @override
  State<_MoveDialog> createState() => _MoveDialogState();
}

class _MoveDialogState extends State<_MoveDialog> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final folders = widget.folders;
    // 注意：SimpleDialog 会把 children 包进自带的 SingleChildScrollView + Column，
    // 所以绝不能在 children 里再放 Flexible / 定高 SizedBox / ListView，
    // 否则会因高度不受限抛出 RenderFlex 布局异常导致弹窗卡死。直接铺平即可。
    return SimpleDialog(
      title: Text('移动 ${widget.targets.length} 项'),
      children: [
        if (folders.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Text('当前没有可移动的文件夹'),
          )
        else
          for (var i = 0; i < folders.length; i++)
            RadioListTile<int>(
              value: i,
              groupValue: _selectedIndex,
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              secondary: const NodeIcon(isFolder: true, size: 22),
              title: Text(
                folders[i].title.isEmpty ? '未命名' : folders[i].title,
              ),
              onChanged: (v) => setState(() => _selectedIndex = v),
            ),
        // 注意：SimpleDialog 只有 title / children，没有 actions 参数
        // （actions 是 AlertDialog 的），按钮需放在 children 末尾，
        // children 已由 SimpleDialog 自带的滚动承载，勿再嵌套 Flexible/ListView。
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
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
                        final target = folders[_selectedIndex!];
                        debugPrint('[MoveDialog] 确认移动 ${widget.targets.length} 项 -> ${target.title}(${target.id})');
                        final provider = context.read<NoteProvider>();
                        final moved = provider.selectedNodes;
                        debugPrint('[MoveDialog] 被移动节点 ids=${moved.map((n) => n.id).toList()}');
                        try {
                          await provider.moveSelectedTo(target.id);
                          debugPrint('[MoveDialog] 移动完成，目标=${target.id}');
                        } catch (e) {
                          debugPrint('[MoveDialog] 移动失败: $e');
                        }
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
/// 主按钮点击后在下方展开「新建文章」「新建文件夹」「定位正在编辑的文章」
/// 三个子项，点击空白或主按钮收起。主按钮 / 子项按钮统一使用原版
/// 深黑色（#ff191919）。
class _SpeedDial extends StatefulWidget {
  const _SpeedDial({
    required this.onAddNote,
    required this.onAddFolder,
    required this.onLocate,
  });

  final VoidCallback onAddNote;
  final VoidCallback onAddFolder;
  final VoidCallback onLocate;

  /// 原版 SpeedDial 主按钮背景色。
  static const Color _fabColor = Color(0xff191919);

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
    final color = _SpeedDial._fabColor;
    final onColor = Colors.white;
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
          _dialItem(
            icon: Icons.edit_location_outlined,
            label: '定位正在编辑的文章',
            color: color,
            onColor: onColor,
            onTap: () => _run(widget.onLocate),
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
      backgroundColor: color,
      foregroundColor: onColor,
      onPressed: _toggle,
      child: Icon(_open ? Icons.close : Icons.add),
    );
  }
}