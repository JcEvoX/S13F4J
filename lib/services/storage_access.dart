import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// 访问应用沙箱之外的真实文件（导入文件夹、备份目录、本机文件夹）所需的系统授权。
///
/// 应用自己的数据目录（笔记库、项目副本）不需要任何授权；只有读写用户选择的
/// 外部路径时才需要：Android 11+ 为「所有文件访问权限」，Android 10 及以下为
/// 存储读写权限。其它平台没有这一层限制，视为已授权。
abstract class StorageAccess {
  static StorageAccess instance = PlatformStorageAccess();

  /// 当前是否已具备访问外部文件的权限。
  Future<bool> isGranted();

  /// 向系统申请权限（Android 11+ 会跳转到「所有文件访问」设置页）。
  Future<bool> request();

  /// 被永久拒绝时，让用户去系统设置里手动打开。
  Future<void> openSystemSettings();
}

class PlatformStorageAccess implements StorageAccess {
  bool get _needsPermission => !kIsWeb && Platform.isAndroid;

  @override
  Future<bool> isGranted() async {
    if (!_needsPermission) return true;
    if (await Permission.manageExternalStorage.isGranted) return true;
    return Permission.storage.isGranted;
  }

  @override
  Future<bool> request() async {
    if (!_needsPermission) return true;
    if (await isGranted()) return true;
    final all = await Permission.manageExternalStorage.request();
    if (all.isGranted) return true;
    final legacy = await Permission.storage.request();
    return legacy.isGranted;
  }

  @override
  Future<void> openSystemSettings() async {
    await openAppSettings();
  }
}

/// 在需要访问外部文件前调用：未授权时先向用户说明用途，再发起系统授权。
///
/// 返回 true 表示可以继续；用户拒绝或系统未授权返回 false，并已通过
/// [notify] 给出下一步提示。UI 差异（对话框 / 提示）由调用方注入。
Future<bool> ensureStorageAccess({
  required Future<bool> Function(String title, String message) confirm,
  required void Function(String message) notify,
  String purpose = '读取你选择的文件夹',
}) async {
  final access = StorageAccess.instance;
  if (await access.isGranted()) return true;
  final agreed = await confirm(
    '需要文件访问权限',
    '$purpose需要访问应用之外的文件。\n\n'
        '点击「去授权」后，系统会请求存储 / 所有文件访问权限；'
        '应用只会读写你主动选择的位置。',
  );
  if (!agreed) return false;
  if (await access.request()) return true;
  notify('未获得文件访问权限，无法$purpose。可在系统设置 > 应用 > 权限中手动开启。');
  await access.openSystemSettings();
  return false;
}
