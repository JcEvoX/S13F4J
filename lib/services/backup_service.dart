import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/note_dao.dart';
import '../models/note.dart';
import 'settings_service.dart';
import 'webdav_service.dart';

/// 备份文件格式版本。
const int kBackupFormatVersion = 1;

/// 备份与恢复服务。
///
/// 对应原 Android 端「备份和恢复」能力：
/// - 本地：通过 SAF 选择文件夹，将全部节点（含回收站）导出为 JSON；
/// - WebDAV：上传 / 下载到用户自建的 WebDAV 服务器。
///
/// 跨平台统一使用 `file_selector`（移动 / 桌面通用），桌面端同样可用
/// 文件夹选择器，从而在 Android / iOS / 桌面三端保持一致。
class BackupService {
  BackupService._();

  /// 生成备份文件名：NotePad-yyyyMMdd-HHmmss.json。
  static String backupFileName([DateTime? t]) {
    final now = t ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'NotePad-${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}.json';
  }

  /// 将节点树序列化为备份 JSON（含应用标识与版本号）。
  static String encodeBackup(List<NotePadNode> nodes) {
    return jsonEncode({
      'app': 'notepad',
      'format': kBackupFormatVersion,
      'exported_at': DateTime.now().millisecondsSinceEpoch,
      'nodes': nodes.map((n) => n.toMap()).toList(),
    });
  }

  /// 解析备份 JSON 为节点列表。
  ///
  /// 兼容两种格式：本应用导出的包装格式，以及直接节点数组。
  static List<NotePadNode> decodeBackup(String raw) {
    final decoded = jsonDecode(raw);
    List<dynamic> list;
    if (decoded is List) {
      list = decoded;
    } else if (decoded is Map && decoded['nodes'] is List) {
      list = decoded['nodes'] as List;
    } else {
      throw const FormatException('备份文件格式不正确');
    }
    return list
        .map((e) => NotePadNode.fromMap(Map<String, Object?>.from(e as Map)))
        .toList();
  }

  /// 备份到本地文件夹，返回生成的文件名。
  static Future<String?> backupToDirectory(
    String dirPath,
    List<NotePadNode> nodes,
  ) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) throw const FileSystemException('备份文件夹不存在');
    final name = backupFileName();
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsString(encodeBackup(nodes), flush: true);
    return name;
  }

  /// 读取备份文件并解析为节点列表。
  static Future<List<NotePadNode>> readBackupFile(String filePath) async {
    final file = File(filePath);
    final raw = await file.readAsString();
    return decodeBackup(raw);
  }

  /// 弹窗选择备份文件夹（返回 null 表示取消）。
  static Future<String?> pickBackupDirectory() {
    return getDirectoryPath(confirmButtonText: '选择此文件夹');
  }
}

/// 自动备份调度器。
///
/// 原 Android 端基于 WorkManager 在系统后台周期执行；Flutter 端为
/// 「桌面适配预留」实现：应用运行期间周期触发（默认 30 分钟），
/// 若后续接入 `workmanager` 插件即可无缝升级为系统级后台任务。
class AutoBackupService {
  AutoBackupService._();

  static final AutoBackupService instance = AutoBackupService._();

  Timer? _timer;
  bool _running = false;

  bool get running => _running;

  /// 启动周期自动备份。
  void start({Duration interval = const Duration(minutes: 30)}) {
    if (_running) return;
    _running = true;
    _timer = Timer.periodic(interval, (_) => run());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
  }

  /// 立即执行一次自动备份（本地 + WebDAV，按配置决定）。
  Future<void> run() async {
    final settings = await SettingsService.instance;
    final nodes = await NoteDao().allNodes();

    if (settings.autoBackupLocal) {
      final dir = settings.backupFolder;
      if (dir != null && await Directory(dir).exists()) {
        try {
          await BackupService.backupToDirectory(dir, nodes);
        } catch (_) {
          // 本地自动备份失败不打断流程
        }
      }
    }

    if (settings.autoBackupToWebdav) {
      try {
        final svc = await _webdavFromPrefs();
        if (svc != null) {
          final name = BackupService.backupFileName();
          await svc.uploadText(name, BackupService.encodeBackup(nodes));
          svc.close();
        }
      } catch (_) {
        // WebDAV 自动备份失败（离线 / 未配置）静默处理
      }
    }
  }

  /// 从已保存的偏好读取 WebDAV 配置；未配置返回 null。
  static Future<WebDavService?> _webdavFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('webdav_config');
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split('\u0001');
    if (parts.length < 3) return null;
    return WebDavService.connect(
      WebDavConfig(url: parts[0], username: parts[1], password: parts[2]),
    );
  }
}
