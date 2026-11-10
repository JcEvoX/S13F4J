import 'package:flutter/material.dart';

import '../services/storage_access.dart';

/// 读写应用之外的文件前的授权流程（对话框版本，供传统页面使用）。
Future<bool> ensureStorageAccessWithDialog(
  BuildContext context, {
  String purpose = '读取你选择的文件夹',
}) {
  return ensureStorageAccess(
    purpose: purpose,
    confirm: (title, message) async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('去授权'),
            ),
          ],
        ),
      );
      return ok ?? false;
    },
    notify: (message) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(message)));
    },
  );
}
