import 'package:path/path.dart' as p;

import 'storage_root.dart';

/// 单一命名空间内的受限读写视图。
///
/// 能力代码只拿得到 handle，拿不到裸路径；所有相对路径都拼到
/// [baseRel]（命名空间根相对 StorageRoot 的位置）之下，越界直接抛错。
class NamespaceHandle {
  NamespaceHandle({
    required this.namespaceId,
    required StorageRoot root,
    String baseRel = '',
  })  : _root = root,
        _baseRel = baseRel.isEmpty
            ? ''
            : StoragePathGuard.validate(baseRel, allowEmpty: false);

  final String namespaceId;
  final StorageRoot _root;
  final String _baseRel;

  String _resolve(String rel, {bool allowEmpty = false}) {
    final value = StoragePathGuard.validate(rel, allowEmpty: allowEmpty);
    if (_baseRel.isEmpty) return value;
    if (value.isEmpty) return _baseRel;
    return p.posix.join(_baseRel, value);
  }

  /// handle 内置的命名空间私有目录：`.notepad/`。
  String get metaDir => _resolve('.notepad');

  Future<bool> exists(String rel) => _root.exists(_resolve(rel));

  Future<List<StorageEntry>> list(String relDir) =>
      _root.list(_resolve(relDir, allowEmpty: true));

  Future<String> readText(String rel) => _root.readText(_resolve(rel));

  Future<void> writeTextAtomic(String rel, String text) =>
      _root.writeTextAtomic(_resolve(rel), text);

  Future<void> writeBytesAtomic(String rel, List<int> bytes) =>
      _root.writeBytesAtomic(_resolve(rel), bytes);

  Future<void> rename(String fromRel, String toRel) =>
      _root.rename(_resolve(fromRel), _resolve(toRel));

  Future<void> delete(String rel) => _root.delete(_resolve(rel));

  Future<DateTime> modifiedAt(String rel) => _root.modifiedAt(_resolve(rel));
}
