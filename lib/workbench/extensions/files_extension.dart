import 'dart:async';

import 'package:file_picker/file_picker.dart';

import '../../services/project_store.dart';
import '../../services/storage_access.dart';
import '../../ui/plugins/file_browser_page.dart';
import '../../ui/plugins/read_only_file_page.dart';
import '../base/disposable.dart';
import '../base/resource_uri.dart';
import '../services/extension_host.dart';
import '../services/file_system.dart';

/// 导入项目面向工作台的只读资源视图（scheme = `files.<projectId>`）。
class ProjectFileSystemProvider extends FileSystemProvider {
  ProjectFileSystemProvider(this.project, this._store);

  final FileProject project;
  final ProjectStore _store;

  static const String schemePrefix = 'files.';

  static String schemeOf(String projectId) => '$schemePrefix$projectId';

  @override
  String get scheme => schemeOf(project.id);

  @override
  String get label => project.displayName;

  @override
  bool get readOnly => true;

  String _rel(ResourceUri uri) => uri.isRoot ? '' : uri.path.substring(1);

  @override
  Future<FileStat> stat(ResourceUri uri) async {
    if (uri.isRoot) return const FileStat(type: ResourceType.directory);
    final siblings = await readDirectory(uri.parent);
    for (final entry in siblings) {
      if (entry.name == uri.basename) {
        return FileStat(type: entry.type, size: entry.size, mtime: entry.mtime);
      }
    }
    throw FileSystemError('E-NOT-FOUND', '文件不存在：${uri.path}', uri);
  }

  @override
  Future<List<DirEntry>> readDirectory(ResourceUri uri) async {
    try {
      final entries = await _store.childrenOf(project, _rel(uri));
      return [
        for (final entry in entries)
          DirEntry(
            name: entry.name,
            type: entry.isFolder ? ResourceType.directory : ResourceType.file,
            size: entry.size,
            mtime: entry.modifiedAt,
          ),
      ];
    } catch (e) {
      throw FileSystemError('E-IO', '读取目录失败：$e', uri);
    }
  }

  @override
  Future<String> readText(ResourceUri uri) async {
    final result = await _store.readFile(project, _rel(uri));
    final text = result.text;
    if (text == null) {
      final message = result.error ?? '无法读取文件';
      throw FileSystemError(
        message.contains('不可用') ? 'E-NOT-FOUND' : 'E-UNSUPPORTED',
        message,
        uri,
      );
    }
    return text;
  }

  /// 项目内容被更新后通知资源管理器刷新。
  void notifyChanged() => emitChange(ResourceUri(scheme));
}

/// 文件系统能力的宿主实现（对应 manifest 的 `capability: file.browser`）。
///
/// 激活时为每个已导入项目注册一个只读 provider；导入 / 移除后同步增减。
class FilesExtension extends HostExtension {
  FilesExtension({ProjectStore? store})
      : _store = store ?? ProjectStore.instance;

  final ProjectStore _store;
  final Map<String,
          ({ProjectFileSystemProvider provider, Disposable registration})>
      _registered = {};
  late ExtensionContext _context;

  @override
  Future<void> activate(ExtensionContext context) async {
    _context = context;
    final workbench = context.workbench;

    context.registerCommand('files.importProject', (_) => _importProject());
    context.registerCommand('files.openFile', (_) => _openSingleFile());
    context.registerCommand('files.manageProjects', (_) async {
      await workbench.ui.showPage((_) => const FileBrowserPage());
      await _sync();
      return null;
    });
    context.registerCommand('files.updateProject', (ctx) async {
      final project = await _projectOf(ctx.arg<ResourceUri>(0));
      if (project == null) return null;
      return _updateProject(project);
    });
    context.registerCommand('files.removeProject', (ctx) async {
      final project = await _projectOf(ctx.arg<ResourceUri>(0));
      if (project == null) return null;
      return _removeProject(project);
    });

    await _sync();
  }

  @override
  void deactivate() {
    _registered.clear();
  }

  /// 让已注册 provider 与项目列表一致（新增 / 移除），并刷新工作区。
  Future<void> _sync() async {
    final projects = await _store.list();
    final ids = {for (final p in projects) p.id};
    for (final id in _registered.keys.toList()) {
      if (!ids.contains(id)) {
        final removed = _registered.remove(id)!;
        removed.registration.dispose();
        _context.workbench.closeTabsOfScheme(removed.provider.scheme);
      }
    }
    for (final project in projects) {
      if (_registered.containsKey(project.id)) continue;
      final provider = ProjectFileSystemProvider(project, _store);
      final registration = _context.registerFileSystemProvider(provider);
      _registered[project.id] =
          (provider: provider, registration: registration);
    }
    await _context.workbench.refreshWorkspace();
  }

  Future<FileProject?> _projectOf(ResourceUri? uri) async {
    final target = uri ?? _context.workbench.explorerSelection;
    if (target == null ||
        !target.scheme.startsWith(ProjectFileSystemProvider.schemePrefix)) {
      return null;
    }
    return _store.byId(
      target.scheme.substring(ProjectFileSystemProvider.schemePrefix.length),
    );
  }

  Future<Object?> _openSingleFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return null;
    final picked = result.files.single;
    final path = picked.path;
    final ui = _context.workbench.ui;
    if (path == null) {
      ui.showMessage('无法访问该文件（未返回路径）', isError: true);
      return null;
    }
    final loaded = await _store.readExternalFile(path);
    await ui.showPage(
      (_) => ReadOnlyFilePage(
        title: picked.name,
        sourceLabel: '外部文件',
        content: loaded.text,
        size: loaded.size,
        error: loaded.error,
      ),
    );
    return null;
  }

  Future<bool> _ensureStorageAccess(String purpose) {
    final ui = _context.workbench.ui;
    return ensureStorageAccess(
      purpose: purpose,
      confirm: (title, message) =>
          ui.confirm(title: title, message: message, confirmLabel: '去授权'),
      notify: ui.showMessage,
    );
  }

  Future<Object?> _importProject() async {
    final ui = _context.workbench.ui;
    if (!await _ensureStorageAccess('导入文件夹')) return null;
    final source = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择要导入的文件夹',
    );
    if (source == null || source.isEmpty) return null;
    final preview = await _store.scan(source);
    final ok = await ui.confirm(
      title: '导入项目',
      message: '来源：$source\n'
          '文件：${preview.fileCount} 个 · ${preview.sizeLabel}\n\n'
          '将复制到应用内独立项目，源目录不变；项目可单独备份 / 恢复。',
      confirmLabel: '导入',
    );
    if (!ok) return null;
    final project = await _store.importDirectory(source);
    await _sync();
    ui.showMessage('已导入项目「${project.displayName}」');
    return ResourceUri(ProjectFileSystemProvider.schemeOf(project.id));
  }

  Future<Object?> _updateProject(FileProject project) async {
    final ui = _context.workbench.ui;
    if (!await _ensureStorageAccess('更新项目')) return null;
    final source = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择项目的新来源目录',
    );
    if (source == null || source.isEmpty) return null;
    final ok = await ui.confirm(
      title: '更新项目',
      message: '将用 $source 的内容覆盖「${project.displayName}」。\n'
          '项目 id 与命名空间保持不变，旧内容会被替换。',
      confirmLabel: '更新',
    );
    if (!ok) return null;
    await _store.updateProject(project.id, source);
    _registered[project.id]?.provider.notifyChanged();
    ui.showMessage('已更新项目「${project.displayName}」');
    return null;
  }

  Future<Object?> _removeProject(FileProject project) async {
    final ui = _context.workbench.ui;
    final ok = await ui.confirm(
      title: '移除项目',
      message: '将移除「${project.displayName}」及其内部文件。\n'
          '移除前会自动生成一份快照（若备份可用），可在备份中心恢复；源目录不受影响。',
      confirmLabel: '移除',
      destructive: true,
    );
    if (!ok) return null;
    await _store.removeProject(project.id);
    await _sync();
    ui.showMessage('已移除项目「${project.displayName}」');
    return null;
  }
}
