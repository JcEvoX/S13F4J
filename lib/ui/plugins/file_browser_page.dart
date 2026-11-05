import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/project_store.dart';
import '../../state/note_provider.dart';
import '../storage_access_dialog.dart';
import 'project_browse_page.dart';
import 'read_only_file_page.dart';

/// 文件阅读页（能力 `file.browser` / `builtin.files`）。
///
/// - 项目列表：导入整个文件夹为独立项目（命名空间 `files.<projectId>`）；
/// - 打开单个外部文件：临时只读会话，不导入、不备份、不进回收站；
/// - 项目内文件默认只读，可显式「另存为笔记」。
class FileBrowserPage extends StatefulWidget {
  const FileBrowserPage({super.key});

  @override
  State<FileBrowserPage> createState() => _FileBrowserPageState();
}

class _FileBrowserPageState extends State<FileBrowserPage> {
  List<FileProject>? _projects;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final projects = await ProjectStore.instance.list();
      if (!mounted) return;
      setState(() {
        _projects = projects;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _projects = const [];
        _error = '读取项目列表失败：$e';
      });
    }
  }

  Future<void> _openSingleFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) {
      _toast('无法访问该文件（未返回路径）');
      return;
    }
    setState(() => _busy = true);
    final loaded = await ProjectStore.instance.readExternalFile(path);
    if (!mounted) return;
    setState(() => _busy = false);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReadOnlyFilePage(
          title: result.files.single.name,
          sourceLabel: '外部文件',
          content: loaded.text,
          size: loaded.size,
          error: loaded.error,
        ),
      ),
    );
  }

  Future<void> _importProject() async {
    if (!await ensureStorageAccessWithDialog(context, purpose: '导入文件夹')) {
      return;
    }
    final source = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择要导入的文件夹',
    );
    if (source == null || source.isEmpty) return;
    setState(() => _busy = true);
    try {
      final preview = await ProjectStore.instance.scan(source);
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导入项目'),
          content: Text(
            '来源：$source\n'
            '文件：${preview.fileCount} 个 · ${preview.sizeLabel}\n'
            '${_skippedLabel(preview.skipped)}\n\n'
            '将复制到应用内独立项目，源目录不变；'
            '项目可单独备份 / 恢复。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('导入'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      final project = await ProjectStore.instance.importDirectory(source);
      if (!mounted) return;
      _toast('已导入项目「${project.displayName}」');
      await _load();
    } catch (e) {
      _toast('导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updateProject(FileProject project, {bool relocate = false}) async {
    if (!await ensureStorageAccessWithDialog(context, purpose: '读取新的来源目录')) {
      return;
    }
    final source = await FilePicker.platform.getDirectoryPath(
      dialogTitle: relocate ? '选择项目的新位置' : '选择项目的新来源目录',
    );
    if (source == null || source.isEmpty || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(relocate ? '重新定位项目' : '更新项目'),
        content: Text(
          '将用 $source 的内容${relocate ? '重建' : '覆盖'}「${project.displayName}」。\n'
          '项目 id 与命名空间保持不变，旧内容会被替换。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(relocate ? '重新定位' : '更新'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ProjectStore.instance.updateProject(project.id, source);
      if (!mounted) return;
      _toast(relocate ? '已重新定位项目「${project.displayName}」' : '已更新项目「${project.displayName}」');
      await _load();
    } catch (e) {
      _toast('${relocate ? '重新定位' : '更新'}失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeProject(FileProject project) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除项目'),
        content: Text(
          '将移除「${project.displayName}」及其内部文件。\n'
          '移除前会自动生成一份快照（若备份可用），'
          '可在备份中心恢复；源目录不受影响。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ProjectStore.instance.removeProject(project.id);
      if (!mounted) return;
      _toast('已移除项目「${project.displayName}」');
      await _load();
    } catch (e) {
      _toast('移除失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _skippedLabel(Map<String, int> skipped) {
    final parts = <String>[];
    if ((skipped['symlinks'] ?? 0) > 0) {
      parts.add('跳过符号链接 ${skipped['symlinks']} 个');
    }
    if ((skipped['oversize'] ?? 0) > 0) {
      parts.add('跳过超大文件 ${skipped['oversize']} 个');
    }
    if ((skipped['unsupported'] ?? 0) > 0) {
      parts.add('跳过不支持项 ${skipped['unsupported']} 个');
    }
    return parts.isEmpty ? '未发现需要跳过的项目' : parts.join('，');
  }

  @override
  Widget build(BuildContext context) {
    final projects = _projects;
    return Scaffold(
      appBar: AppBar(
        title: const Text('文件阅读'),
        actions: [
          IconButton(
            tooltip: '打开文件',
            onPressed: _busy ? null : _openSingleFile,
            icon: const Icon(Icons.file_open_outlined),
          ),
          IconButton(
            tooltip: '导入项目',
            onPressed: _busy ? null : _importProject,
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: projects == null
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: projects.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: projects.length,
                            itemBuilder: (_, index) =>
                                _buildProjectCard(projects[index]),
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      children: [
        const SizedBox(height: 96),
        Icon(Icons.folder_open, size: 56, color: Colors.grey.shade400),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            '尚无项目',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            '导入一个文件夹作为独立项目，或直接打开单个文件查看。',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: FilledButton.icon(
            onPressed: _busy ? null : _importProject,
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('导入项目'),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: _busy ? null : _openSingleFile,
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('打开文件'),
          ),
        ),
      ],
    );
  }

  Widget _buildProjectCard(FileProject project) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: project.missing
            ? null
            : () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProjectBrowsePage(project: project),
                  ),
                );
                await _load();
              },
        onLongPress: () => _showProjectActions(project),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            children: [
              Icon(
                project.missing
                    ? Icons.folder_off_outlined
                    : Icons.folder_copy_outlined,
                size: 26,
                color: project.missing
                    ? Colors.grey.shade500
                    : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            project.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (project.missing) ...[
                          const SizedBox(width: 6),
                          _tag('缺失', Colors.grey),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${project.fileCount} 个文件 · ${project.sizeLabel} · '
                      '导入于 ${project.timeLabel}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'update') _updateProject(project);
                  if (value == 'relocate') {
                    _updateProject(project, relocate: true);
                  }
                  if (value == 'remove') _removeProject(project);
                },
                itemBuilder: (_) => [
                  if (project.missing)
                    const PopupMenuItem(
                      value: 'relocate',
                      child: Text('重新定位'),
                    )
                  else
                    const PopupMenuItem(
                      value: 'update',
                      child: Text('更新项目'),
                    ),
                  const PopupMenuItem(value: 'remove', child: Text('移除项目')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 10, color: color),
        ),
      );

  void _showProjectActions(FileProject project) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(project.missing ? Icons.folder_open : Icons.sync_outlined),
              title: Text(project.missing ? '重新定位' : '更新项目'),
              onTap: () {
                Navigator.pop(ctx);
                _updateProject(project, relocate: project.missing);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('移除项目'),
              onTap: () {
                Navigator.pop(ctx);
                _removeProject(project);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 「另存为笔记」：把只读文本复制进笔记库，生成一篇 `.md`。
Future<void> saveTextAsNote(
  BuildContext context, {
  required String title,
  required String content,
}) async {
  final provider = context.read<NoteProvider>();
  final base = title.replaceFirst(RegExp(r'\.\w+$'), '');
  final node = await provider.createNode(
    isFolder: false,
    title: base.isEmpty ? '未命名' : base,
    content: content,
  );
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('已保存为笔记「${node.title}」')),
  );
}
