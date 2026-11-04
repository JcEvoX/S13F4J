import 'package:notepad/workbench/base/resource_uri.dart';
import 'package:notepad/workbench/services/file_system.dart';

/// 内存文件系统：路径 → 文本；目录由路径隐式推导。
class MemoryFileSystemProvider extends FileSystemProvider {
  MemoryFileSystemProvider(
    this.scheme, {
    Map<String, String> files = const {},
    this.readOnly = false,
    this.label = 'mem',
  }) : files = Map.of(files);

  @override
  final String scheme;
  @override
  final String label;
  @override
  final bool readOnly;

  final Map<String, String> files;
  final Set<String> dirs = {};

  bool _isDir(String path) =>
      path == '/' ||
      dirs.contains(path) ||
      files.keys.any((f) => f.startsWith('$path/'));

  @override
  Future<FileStat> stat(ResourceUri uri) async {
    if (files.containsKey(uri.path)) {
      return FileStat(type: FileType.file, size: files[uri.path]!.length);
    }
    if (_isDir(uri.path)) return const FileStat(type: FileType.directory);
    throw FileSystemError('E-NOT-FOUND', '不存在', uri);
  }

  @override
  Future<List<DirEntry>> readDirectory(ResourceUri uri) async {
    if (!_isDir(uri.path)) {
      throw FileSystemError('E-NOT-FOUND', '不存在', uri);
    }
    final prefix = uri.isRoot ? '/' : '${uri.path}/';
    final names = <String, FileType>{};
    for (final f in files.keys) {
      if (!f.startsWith(prefix)) continue;
      final rest = f.substring(prefix.length);
      final slash = rest.indexOf('/');
      if (slash < 0) {
        names[rest] = FileType.file;
      } else {
        names[rest.substring(0, slash)] = FileType.directory;
      }
    }
    for (final d in dirs) {
      if (!d.startsWith(prefix)) continue;
      final rest = d.substring(prefix.length);
      if (rest.isEmpty) continue;
      names.putIfAbsent(rest.split('/').first, () => FileType.directory);
    }
    return [
      for (final e in names.entries) DirEntry(name: e.key, type: e.value),
    ];
  }

  @override
  Future<String> readText(ResourceUri uri) async {
    final text = files[uri.path];
    if (text == null) throw FileSystemError('E-NOT-FOUND', '不存在', uri);
    return text;
  }

  @override
  Future<void> writeText(ResourceUri uri, String text) async {
    if (readOnly) throw FileSystemError('E-READONLY', '只读', uri);
    files[uri.path] = text;
  }

  @override
  Future<ResourceUri> createFile(
    ResourceUri parent,
    String name, {
    String content = '',
  }) async {
    if (readOnly) throw FileSystemError('E-READONLY', '只读', parent);
    final uri = parent.join(name);
    files[uri.path] = content;
    emitChange(parent);
    return uri;
  }

  @override
  Future<ResourceUri> createDirectory(ResourceUri parent, String name) async {
    if (readOnly) throw FileSystemError('E-READONLY', '只读', parent);
    final uri = parent.join(name);
    dirs.add(uri.path);
    emitChange(parent);
    return uri;
  }

  @override
  Future<ResourceUri> rename(ResourceUri uri, String newName) async {
    if (readOnly) throw FileSystemError('E-READONLY', '只读', uri);
    final target = uri.parent.join(newName);
    final text = files.remove(uri.path);
    if (text != null) files[target.path] = text;
    emitChange(uri.parent);
    return target;
  }

  @override
  Future<void> delete(ResourceUri uri) async {
    if (readOnly) throw FileSystemError('E-READONLY', '只读', uri);
    files.remove(uri.path);
    files.removeWhere((k, _) => k.startsWith('${uri.path}/'));
    dirs.remove(uri.path);
    emitChange(uri.parent);
  }
}
