import 'package:flutter/material.dart';

import '../../services/project_store.dart';
import 'read_only_file_page.dart';

/// 项目浏览：按原目录结构逐层进入，文件只读预览。
class ProjectBrowsePage extends StatefulWidget {
  const ProjectBrowsePage({super.key, required this.project});

  final FileProject project;

  @override
  State<ProjectBrowsePage> createState() => _ProjectBrowsePageState();
}

class _ProjectBrowsePageState extends State<ProjectBrowsePage> {
  String _relDir = '';
  List<ProjectEntry>? _entries;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final entries = await ProjectStore.instance.childrenOf(
        widget.project,
        _relDir,
      );
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _entries = const [];
        _error = '读取目录失败：$e';
      });
    }
  }

  void _enter(ProjectEntry entry) {
    setState(() {
      _relDir = entry.relPath;
      _entries = null;
    });
    _load();
  }

  void _back() {
    if (_relDir.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final parts = _relDir.split('/')..removeLast();
    setState(() {
      _relDir = parts.join('/');
      _entries = null;
    });
    _load();
  }

  Future<void> _open(ProjectEntry entry) async {
    final loaded = await ProjectStore.instance.readFile(
      widget.project,
      entry.relPath,
    );
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReadOnlyFilePage(
          title: entry.name,
          sourceLabel: '项目：${widget.project.displayName}',
          content: loaded.text,
          size: loaded.size,
          error: loaded.error,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final segments = _relDir.isEmpty ? <String>[] : _relDir.split('/');
    final title = segments.isEmpty
        ? widget.project.displayName
        : segments.last;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回',
          onPressed: _back,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 17)),
            if (segments.isNotEmpty)
              Text(
                widget.project.displayName,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
          ],
        ),
      ),
      body: widget.project.missing
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('项目根不可用，文件可能已被外部删除或移动。'),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: _buildBody(),
            ),
    );
  }

  Widget _buildBody() {
    final entries = _entries;
    if (entries == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      );
    }
    if (entries.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 96),
          Center(child: Text('此文件夹为空')),
        ],
      );
    }
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
      itemBuilder: (_, index) {
        final entry = entries[index];
        return ListTile(
          leading: Icon(
            entry.isFolder ? Icons.folder_outlined : _fileIcon(entry.name),
            color: entry.isFolder
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade600,
          ),
          title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            entry.isFolder
                ? '文件夹'
                : '${_sizeLabel(entry.size)} · ${_timeLabel(entry.modifiedAt)}',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: entry.isFolder
              ? const Icon(Icons.chevron_right, size: 20)
              : null,
          onTap: () => entry.isFolder ? _enter(entry) : _open(entry),
        );
      },
    );
  }

  static IconData _fileIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
      return Icons.description_outlined;
    }
    if (lower.endsWith('.json') ||
        lower.endsWith('.yaml') ||
        lower.endsWith('.yml')) {
      return Icons.data_object;
    }
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif')) {
      return Icons.image_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  static String _sizeLabel(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  static String _timeLabel(int millis) {
    if (millis <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }
}
