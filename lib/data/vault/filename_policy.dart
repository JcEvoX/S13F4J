import 'dart:convert';

import 'package:path/path.dart' as p;

/// 文件 / 文件夹命名策略（唯一跨端命名真相）。
class FilenamePolicy {
  FilenamePolicy._();

  /// 系统保留名（用户不可创建）。
  static const Set<String> reservedNames = {'.notepad', 'assets'};

  static final RegExp _invalidChars = RegExp(r'[\\/:*?"<>|]');
  static final RegExp _controlChars = RegExp(r'[\x00-\x1F\x7F]');

  /// 清洗标题。
  ///
  /// 说明：Dart 核心库没有 Unicode NFC 归一化，v2 暂以清洗 + 长度截断为准，
  /// NFC 归一化留待引入字符库后在策略内部补齐。
  static String sanitizeTitle(String raw, {bool isFolder = false}) {
    var value = raw.trim().replaceAll(_controlChars, '');
    value = value.replaceAll(_invalidChars, '_');
    value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    // 以点开头的名称属于系统保留区，去掉前导点。
    while (value.startsWith('.')) {
      value = value.substring(1).trimLeft();
    }
    if (value.isEmpty) value = '未命名';
    if (reservedNames.contains(value.toLowerCase())) {
      value = '${value}_';
    }
    final budget = 255 - (isFolder ? 0 : '.md'.length);
    return _truncateUtf8(value, budget);
  }

  /// 生成候选文件名（含扩展名）。
  static String fileNameFor(String title, {required bool isFolder}) {
    final safe = sanitizeTitle(title, isFolder: isFolder);
    return isFolder ? safe : '$safe.md';
  }

  /// 在已有标题集合内生成唯一标题（大小写不敏感，自动加 ` (2)`）。
  static String uniqueTitle(String desired, Set<String> existingTitles) {
    final lowered = {for (final t in existingTitles) t.toLowerCase()};
    if (!lowered.contains(desired.toLowerCase())) return desired;
    var index = 2;
    while (true) {
      final candidate = '$desired ($index)';
      if (!lowered.contains(candidate.toLowerCase())) return candidate;
      index++;
    }
  }

  /// 从相对路径提取标题（笔记去 `.md`，文件夹取末段）。
  static String titleOfPath(String path) {
    final name = p.posix.basename(path);
    if (name.endsWith('.md')) {
      return name.substring(0, name.length - 3);
    }
    return name;
  }

  static bool isNotePath(String path) =>
      p.posix.extension(path).toLowerCase() == '.md';

  static String _truncateUtf8(String value, int maxBytes) {
    if (maxBytes <= 0) return '未命名';
    final buffer = StringBuffer();
    var used = 0;
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      final size = utf8.encode(char).length;
      if (used + size > maxBytes) break;
      buffer.write(char);
      used += size;
    }
    final out = buffer.toString().trim();
    return out.isEmpty ? '未命名' : out;
  }
}
