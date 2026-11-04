import 'package:flutter/foundation.dart';

/// 工作台统一的资源标识：`<namespaceId>:/<相对路径>`。
///
/// scheme 就是命名空间 id（与注册表一致，如 `notes`、`files.p-01`）。
/// 路径恒以 `/` 开头、无尾部 `/`（根为 `/`），且不含 `..` 与空片段。
@immutable
class ResourceUri {
  const ResourceUri._(this.scheme, this.path);

  factory ResourceUri(String scheme, [String path = '/']) {
    if (scheme.isEmpty || scheme.contains(':') || scheme.contains('/')) {
      throw FormatException('非法的资源 scheme: "$scheme"');
    }
    return ResourceUri._(scheme, _normalize(path));
  }

  factory ResourceUri.parse(String value) {
    final index = value.indexOf(':');
    if (index <= 0) {
      throw FormatException('资源标识缺少 scheme: "$value"');
    }
    return ResourceUri(value.substring(0, index), value.substring(index + 1));
  }

  static ResourceUri? tryParse(String value) {
    try {
      return ResourceUri.parse(value);
    } on FormatException {
      return null;
    }
  }

  final String scheme;
  final String path;

  static String _normalize(String raw) {
    final segments = <String>[];
    for (final segment in raw.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        throw FormatException('资源路径不能包含 "..": "$raw"');
      }
      segments.add(segment);
    }
    return '/${segments.join('/')}';
  }

  bool get isRoot => path == '/';

  List<String> get segments => isRoot ? const [] : path.substring(1).split('/');

  /// 最后一段（根返回空串）。
  String get basename => isRoot ? '' : segments.last;

  /// 扩展名（含点、小写）；无扩展名返回空串。
  String get extname {
    final name = basename;
    final dot = name.lastIndexOf('.');
    if (dot <= 0) return '';
    return name.substring(dot).toLowerCase();
  }

  ResourceUri get parent {
    if (isRoot) return this;
    final segs = segments;
    return ResourceUri._(
      scheme,
      segs.length == 1 ? '/' : '/${segs.sublist(0, segs.length - 1).join('/')}',
    );
  }

  ResourceUri join(String name) =>
      ResourceUri._(scheme, _normalize('$path/$name'));

  ResourceUri withPath(String newPath) =>
      ResourceUri._(scheme, _normalize(newPath));

  /// [other] 是否位于本资源之下（或相同）。
  bool contains(ResourceUri other) {
    if (other.scheme != scheme) return false;
    if (isRoot) return true;
    return other.path == path || other.path.startsWith('$path/');
  }

  @override
  bool operator ==(Object other) =>
      other is ResourceUri && other.scheme == scheme && other.path == path;

  @override
  int get hashCode => Object.hash(scheme, path);

  @override
  String toString() => '$scheme:$path';
}
