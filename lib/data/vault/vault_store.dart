import 'dart:async';
import 'dart:io';

import '../../core/storage/storage_root.dart';

/// 文件存储内核：原子落盘 + 串行写队列。
///
/// 读写原语直接委托 [SandboxRoot]；所有多步变更由调用方通过 [guard]
/// 串行执行，保证同一时刻只有一个 writer 操作 tree / 文件结构。
class VaultStore implements StorageRoot {
  VaultStore(String rootPath) : _root = SandboxRoot(rootPath);

  final SandboxRoot _root;
  Future<void> _tail = Future<void>.value();

  String get rootPath => _root.rootPath;

  String absolutePath(String rel) => _root.absolutePath(rel);

  /// 串行执行变更操作。
  Future<T> guard<T>(Future<T> Function() action) {
    final previous = _tail;
    final completer = Completer<void>();
    _tail = completer.future;
    return previous.then((_) async {
      try {
        return await action();
      } finally {
        completer.complete();
      }
    });
  }

  /// 创建目录（写路径内部使用，不进入队列以避免自锁）。
  Future<void> ensureDir(String rel) async {
    final target = _root.absolutePath(rel, allowEmpty: true);
    await Directory(target).create(recursive: true);
  }

  @override
  bool get supportsWatch => _root.supportsWatch;

  @override
  Future<bool> exists(String rel) => _root.exists(rel);

  @override
  Future<List<StorageEntry>> list(String relDir) => _root.list(relDir);

  @override
  Future<String> readText(String rel) => _root.readText(rel);

  @override
  Future<void> writeTextAtomic(String rel, String text) =>
      _root.writeTextAtomic(rel, text);

  @override
  Future<void> writeBytesAtomic(String rel, List<int> bytes) =>
      _root.writeBytesAtomic(rel, bytes);

  @override
  Future<void> rename(String fromRel, String toRel) =>
      _root.rename(fromRel, toRel);

  @override
  Future<void> delete(String rel) => _root.delete(rel);

  @override
  Future<DateTime> modifiedAt(String rel) => _root.modifiedAt(rel);
}
