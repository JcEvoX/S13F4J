import 'package:flutter/material.dart';

import '../models/note.dart';

/// 根据节点类型返回图标（文件夹 / 文章）。
IconData nodeIcon(SaltNode node) {
  return node.isFolder ? Icons.folder : Icons.description_outlined;
}