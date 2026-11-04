import 'dart:async';

import 'package:flutter/foundation.dart';

import '../base/disposable.dart';
import '../base/resource_uri.dart';

enum FileType { file, directory }

class FileStat {
  const FileStat({
    required this.type,
    this.size = 0,
    this.mtime = 0,
  });

  final FileType type;
  final int size;

  /// 最近修改时间（毫秒）；未知为 0。
  final int mtime;

  bool get isDirectory => type == FileType.directory;
}

class DirEntry {
  const DirEntry({
    required this.name,
    required this.type,
    this.size = 0,
    this.mtime = 0,
  });

  final String name;
  final FileType type;
  final int size;
  final int mtime;

  bool get isDirectory => type == FileType.directory;
}

/// 文件系统错误，沿用架构文档第 9 节的错误码。
class FileSystemError implements Exception {
  const FileSystemError(this.code, this.message, [this.uri]);

  /// `E-NOT-FOUND` / `E-READONLY` / `E-UNSUPPORTED` / `E-CONFLICT` / `E-IO` / `E-NO-PROVIDER`。
  final String code;
  final String message;
  final ResourceUri? uri;

  @override
  String toString() => '[$code] $message${uri == null ? '' : ' ($uri)'}';
}

/// 命名空间面向工作台的资源视图。
///
/// 只读能力无需实现写操作：默认实现抛 `E-READONLY`。
abstract class FileSystemProvider {
  /// 对应的命名空间 id。
  String get scheme;

  /// 工作区根节点的显示名。
  String get label;

  bool get readOnly => false;

  /// 标签 / 面包屑里显示的名称，默认是最后一段。
  String displayName(ResourceUri uri) => uri.isRoot ? label : uri.basename;

  Future<FileStat> stat(ResourceUri uri);

  Future<List<DirEntry>> readDirectory(ResourceUri uri);

  Future<String> readText(ResourceUri uri);

  Future<void> writeText(ResourceUri uri, String text) =>
      Future.error(FileSystemError('E-READONLY', '只读资源不能写入', uri));

  /// 返回实际创建的资源（名称冲突时 provider 可自动改名）。
  Future<ResourceUri> createFile(
    ResourceUri parent,
    String name, {
    String content = '',
  }) =>
      Future.error(FileSystemError('E-READONLY', '只读资源不能新建', parent));

  Future<ResourceUri> createDirectory(ResourceUri parent, String name) =>
      Future.error(FileSystemError('E-READONLY', '只读资源不能新建', parent));

  Future<ResourceUri> rename(ResourceUri uri, String newName) =>
      Future.error(FileSystemError('E-READONLY', '只读资源不能重命名', uri));

  /// 删除。支持回收站的能力应移入回收站（可恢复）。
  Future<void> delete(ResourceUri uri) =>
      Future.error(FileSystemError('E-READONLY', '只读资源不能删除', uri));

  final StreamController<ResourceUri> _changes =
      StreamController<ResourceUri>.broadcast();

  /// 目录内容发生变化（广播的是变化的目录）。
  Stream<ResourceUri> get onDidChange => _changes.stream;

  @protected
  void emitChange(ResourceUri directory) {
    if (!_changes.isClosed) _changes.add(directory);
  }

  @mustCallSuper
  void dispose() {
    _changes.close();
  }
}

/// 文件系统注册表：按 scheme 找 provider；找不到时先触发 `onResource:<scheme>` 激活。
class FileSystemRegistry extends ChangeNotifier {
  final Map<String, FileSystemProvider> _providers = {};
  final Map<String, StreamSubscription<ResourceUri>> _subscriptions = {};
  final StreamController<ResourceUri> _changes =
      StreamController<ResourceUri>.broadcast();

  /// 由宿主注入：触发 `onResource:<scheme>` 激活事件。
  Future<void> Function(String scheme)? activator;

  List<FileSystemProvider> get providers =>
      List.unmodifiable(_providers.values);

  Stream<ResourceUri> get onDidChange => _changes.stream;

  Disposable register(FileSystemProvider provider) {
    if (_providers.containsKey(provider.scheme)) {
      throw StateError('文件系统已注册: ${provider.scheme}');
    }
    _providers[provider.scheme] = provider;
    _subscriptions[provider.scheme] =
        provider.onDidChange.listen(_changes.add);
    notifyListeners();
    return toDisposable(() {
      if (_providers[provider.scheme] != provider) return;
      _providers.remove(provider.scheme);
      _subscriptions.remove(provider.scheme)?.cancel();
      notifyListeners();
    });
  }

  FileSystemProvider? providerOf(String scheme) => _providers[scheme];

  /// 取 provider；未注册时尝试激活提供它的能力。
  Future<FileSystemProvider?> resolve(String scheme) async {
    var provider = _providers[scheme];
    if (provider != null) return provider;
    final activate = activator;
    if (activate == null) return null;
    await activate(scheme);
    provider = _providers[scheme];
    return provider;
  }

  Future<FileSystemProvider> _require(ResourceUri uri) async {
    final provider = await resolve(uri.scheme);
    if (provider == null) {
      throw FileSystemError('E-NO-PROVIDER', '没有可用的文件系统: ${uri.scheme}', uri);
    }
    return provider;
  }

  Future<bool> isReadOnly(ResourceUri uri) async =>
      (await resolve(uri.scheme))?.readOnly ?? true;

  Future<FileStat> stat(ResourceUri uri) async =>
      (await _require(uri)).stat(uri);

  Future<List<DirEntry>> readDirectory(ResourceUri uri) async =>
      (await _require(uri)).readDirectory(uri);

  Future<String> readText(ResourceUri uri) async =>
      (await _require(uri)).readText(uri);

  Future<void> writeText(ResourceUri uri, String text) async =>
      (await _require(uri)).writeText(uri, text);

  Future<ResourceUri> createFile(
    ResourceUri parent,
    String name, {
    String content = '',
  }) async =>
      (await _require(parent)).createFile(parent, name, content: content);

  Future<ResourceUri> createDirectory(ResourceUri parent, String name) async =>
      (await _require(parent)).createDirectory(parent, name);

  Future<ResourceUri> rename(ResourceUri uri, String newName) async =>
      (await _require(uri)).rename(uri, newName);

  Future<void> delete(ResourceUri uri) async =>
      (await _require(uri)).delete(uri);

  @override
  void dispose() {
    for (final sub in _subscriptions.values) {
      sub.cancel();
    }
    _subscriptions.clear();
    _changes.close();
    super.dispose();
  }
}
