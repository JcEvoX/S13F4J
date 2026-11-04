import 'package:flutter/material.dart';

/// manifest 里用名字引用图标（声明式插件不能携带 Flutter 对象）。
IconData iconByName(String? name) {
  switch (name) {
    case 'search':
      return Icons.search;
    case 'folder_open':
      return Icons.folder_open_outlined;
    case 'folder':
      return Icons.folder_outlined;
    case 'note_alt':
      return Icons.note_alt_outlined;
    case 'description':
      return Icons.description_outlined;
    case 'code':
      return Icons.code;
    case 'terminal':
      return Icons.terminal;
    case 'settings':
      return Icons.settings_outlined;
    case 'source':
      return Icons.source_outlined;
    case 'extension':
    default:
      return Icons.extension_outlined;
  }
}

IconData iconForFile(String name,
    {bool isDirectory = false, bool open = false}) {
  if (isDirectory) {
    return open ? Icons.folder_open_outlined : Icons.folder_outlined;
  }
  final dot = name.lastIndexOf('.');
  final ext = dot <= 0 ? '' : name.substring(dot).toLowerCase();
  switch (ext) {
    case '.md':
    case '.markdown':
      return Icons.article_outlined;
    case '.json':
    case '.yaml':
    case '.yml':
    case '.toml':
    case '.xml':
      return Icons.data_object;
    case '.png':
    case '.jpg':
    case '.jpeg':
    case '.gif':
    case '.webp':
    case '.svg':
      return Icons.image_outlined;
    case '.dart':
    case '.js':
    case '.ts':
    case '.py':
    case '.java':
    case '.kt':
    case '.c':
    case '.h':
    case '.cpp':
    case '.rs':
    case '.go':
    case '.swift':
    case '.sh':
    case '.html':
    case '.css':
      return Icons.code;
    default:
      return Icons.insert_drive_file_outlined;
  }
}
