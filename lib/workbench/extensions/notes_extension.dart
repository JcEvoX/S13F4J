import 'package:flutter/material.dart';

import '../../data/notes_repository.dart';
import '../../models/note.dart';
import '../../ui/editor/editor_page.dart';
import '../../ui/preview/preview_page.dart';
import '../base/resource_uri.dart';
import '../services/editor_registry.dart';
import '../services/extension_host.dart';
import '../services/file_system.dart';
import '../ui/editors/editor_message.dart';

/// 笔记库面向工作台的资源视图（scheme = `notes`）。
///
/// 资源路径由节点标题推出：文件夹 = 标题，笔记 = `标题.md`。
/// 顺序沿用仓库里的用户排序；删除进入回收站（可恢复）。
class NotesFileSystemProvider extends FileSystemProvider {
  NotesFileSystemProvider(this._repository);

  final NotesRepository _repository;

  static const String schemeName = 'notes';

  @override
  String get scheme => schemeName;

  @override
  String get label => '笔记';

  @override
  bool get deleteGoesToTrash => true;

  static String nameOf(NotePadNode node) =>
      node.isFolder ? node.title : '${node.title}.md';

  static String _titleOf(String name, {required bool isFolder}) {
    if (isFolder) return name;
    final lower = name.toLowerCase();
    return lower.endsWith('.md') ? name.substring(0, name.length - 3) : name;
  }

  @override
  String displayName(ResourceUri uri) {
    if (uri.isRoot) return label;
    final name = uri.basename;
    return name.toLowerCase().endsWith('.md')
        ? name.substring(0, name.length - 3)
        : name;
  }

  /// 逐段下钻：返回 (节点, 是否根)。找不到返回 null。
  Future<({NotePadNode? node, bool isRoot})?> _resolve(ResourceUri uri) async {
    if (uri.isRoot) return (node: null, isRoot: true);
    String? parentId;
    NotePadNode? current;
    for (final segment in uri.segments) {
      final siblings = await _repository.childrenOf(parentId);
      current = null;
      for (final node in siblings) {
        if (nameOf(node) == segment) {
          current = node;
          break;
        }
      }
      if (current == null) return null;
      parentId = current.id;
    }
    return (node: current, isRoot: false);
  }

  Future<({NotePadNode? node, bool isRoot})> _require(ResourceUri uri) async {
    final resolved = await _resolve(uri);
    if (resolved == null) {
      throw FileSystemError('E-NOT-FOUND', '笔记不存在：${uri.path}', uri);
    }
    return resolved;
  }

  /// 资源对应的笔记节点 id（根 / 不存在返回 null）。
  Future<String?> nodeIdOf(ResourceUri uri) async =>
      (await _resolve(uri))?.node?.id;

  Future<T> _guard<T>(ResourceUri uri, Future<T> Function() action) async {
    try {
      return await action();
    } on NotesException catch (e) {
      throw FileSystemError(e.code, e.message, uri);
    }
  }

  @override
  Future<FileStat> stat(ResourceUri uri) async {
    final resolved = await _require(uri);
    final node = resolved.node;
    if (node == null) return const FileStat(type: ResourceType.directory);
    return FileStat(
      type: node.isFolder ? ResourceType.directory : ResourceType.file,
      mtime: node.updatedAt,
    );
  }

  @override
  Future<List<DirEntry>> readDirectory(ResourceUri uri) async {
    final resolved = await _require(uri);
    final node = resolved.node;
    if (node != null && !node.isFolder) {
      throw FileSystemError('E-UNSUPPORTED', '不是文件夹：${uri.path}', uri);
    }
    final children = await _repository.childrenOf(node?.id);
    return [
      for (final child in children)
        DirEntry(
          name: nameOf(child),
          type: child.isFolder ? ResourceType.directory : ResourceType.file,
          mtime: child.updatedAt,
        ),
    ];
  }

  @override
  Future<String> readText(ResourceUri uri) async {
    final node = (await _require(uri)).node;
    if (node == null || node.isFolder) {
      throw FileSystemError('E-UNSUPPORTED', '不是笔记文件：${uri.path}', uri);
    }
    return _guard(uri, () => _repository.readBody(node.id));
  }

  @override
  Future<void> writeText(ResourceUri uri, String text) async {
    final node = (await _require(uri)).node;
    if (node == null || node.isFolder) {
      throw FileSystemError('E-UNSUPPORTED', '不是笔记文件：${uri.path}', uri);
    }
    await _guard(uri, () => _repository.writeBody(node.id, text));
  }

  Future<ResourceUri> _create(
    ResourceUri parent,
    String name, {
    required bool isFolder,
    String content = '',
  }) async {
    final folder = (await _require(parent)).node;
    if (folder != null && !folder.isFolder) {
      throw FileSystemError('E-UNSUPPORTED', '父级不是文件夹：${parent.path}', parent);
    }
    final title = _titleOf(name.trim(), isFolder: isFolder);
    if (title.isEmpty) {
      throw FileSystemError('E-UNSUPPORTED', '名称不能为空', parent);
    }
    final node = await _guard(
      parent,
      () => _repository.createNode(
        isFolder: isFolder,
        title: title,
        parentId: folder?.id,
        content: content,
      ),
    );
    emitChange(parent);
    return parent.join(nameOf(node));
  }

  @override
  Future<ResourceUri> createFile(
    ResourceUri parent,
    String name, {
    String content = '',
  }) =>
      _create(parent, name, isFolder: false, content: content);

  @override
  Future<ResourceUri> createDirectory(ResourceUri parent, String name) =>
      _create(parent, name, isFolder: true);

  @override
  Future<ResourceUri> rename(ResourceUri uri, String newName) async {
    final node = (await _require(uri)).node;
    if (node == null) {
      throw FileSystemError('E-UNSUPPORTED', '不能重命名工作区根', uri);
    }
    final title = _titleOf(newName.trim(), isFolder: node.isFolder);
    if (title.isEmpty) {
      throw FileSystemError('E-UNSUPPORTED', '名称不能为空', uri);
    }
    await _guard(uri, () => _repository.rename(node.id, title));
    final updated = await _repository.nodeById(node.id);
    emitChange(uri.parent);
    return uri.parent.join(updated == null ? title : nameOf(updated));
  }

  @override
  Future<void> delete(ResourceUri uri) async {
    final node = (await _require(uri)).node;
    if (node == null) {
      throw FileSystemError('E-UNSUPPORTED', '不能删除工作区根', uri);
    }
    await _guard(uri, () => _repository.moveToTrash([node.id]));
    emitChange(uri.parent);
  }
}

/// 笔记能力的宿主实现（对应 manifest 的 `capability: note.editor`）。
class NotesExtension extends HostExtension {
  NotesExtension(this.repository);

  final NotesRepository repository;

  @override
  void activate(ExtensionContext context) {
    final provider = NotesFileSystemProvider(repository);
    final workbench = context.workbench;
    context.registerFileSystemProvider(provider);
    context.registerEditorProvider(
      'notes.markdown',
      (_, input) => NoteMarkdownEditor(provider: provider, input: input),
    );

    context.registerCommand('notes.newNote', (ctx) async {
      var folder = ctx.arg<ResourceUri>(0);
      final selection = workbench.explorerSelection;
      if (folder == null && selection != null && selection.scheme == 'notes') {
        final stat = await provider.stat(selection);
        folder = stat.isDirectory ? selection : selection.parent;
      }
      folder ??= ResourceUri(NotesFileSystemProvider.schemeName);
      final created = await provider.createFile(
        folder,
        ctx.arg<String>(1) ?? '未命名.md',
      );
      await workbench.openResource(created);
      return created;
    });

    context.registerCommand('notes.preview', (ctx) async {
      final uri = workbench.activeTab?.resource;
      if (uri == null || uri.scheme != NotesFileSystemProvider.schemeName) {
        return null;
      }
      final text = await provider.readText(uri);
      await workbench.ui.showPage(
        (_) => PreviewPage(title: provider.displayName(uri), content: text),
      );
      return null;
    });
  }
}

/// 把既有的 Markdown 编辑页嵌进标签：同一份编辑逻辑（自动保存 / 外部修改检测 / 预览）。
class NoteMarkdownEditor extends StatefulWidget {
  const NoteMarkdownEditor(
      {super.key, required this.provider, required this.input});

  final NotesFileSystemProvider provider;
  final EditorInput input;

  @override
  State<NoteMarkdownEditor> createState() => _NoteMarkdownEditorState();
}

class _NoteMarkdownEditorState extends State<NoteMarkdownEditor> {
  String? _nodeId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final uri = widget.input.resource;
    final id = uri == null ? null : await widget.provider.nodeIdOf(uri);
    if (!mounted) return;
    setState(() {
      _nodeId = id;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final id = _nodeId;
    if (id == null) {
      return const EditorMessage(
        message: '笔记不存在，可能已被删除或移动。',
        icon: Icons.note_alt_outlined,
      );
    }
    return EditorPage(nodeId: id, embedded: true);
  }
}
