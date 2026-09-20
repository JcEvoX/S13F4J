import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:webdav_client/webdav_client.dart';

/// WebDAV 连接配置。
class WebDavConfig {
  const WebDavConfig({
    required this.url,
    required this.username,
    required this.password,
  });

  final String url;
  final String username;
  final String password;

  Map<String, String> toMap() => {
        'url': url,
        'username': username,
        'password': password,
      };

  factory WebDavConfig.fromMap(Map<String, String> m) => WebDavConfig(
        url: m['url'] ?? '',
        username: m['username'] ?? '',
        password: m['password'] ?? '',
      );
}

/// WebDAV 备份服务。
///
/// 对应原 Android 端的「WebDAV 备份」能力：通过标准 WebDAV 协议将
/// 数据文件上传 / 下载到用户自建的 WebDAV 服务器（如坚果云），
/// 在 Android / iOS / 桌面端保持一致。
class WebDavService {
  WebDavService._(this._client);

  final Client _client;

  static const String backupDir = '/NotePadBackup';

  /// 登录并创建客户端。
  static Future<WebDavService> connect(WebDavConfig config) async {
    final base = _normalizeUrl(config.url);
    debugPrint('[WebDav] connect: $base, user=${config.username}');
    final client = newClient(
      base,
      user: config.username,
      password: config.password,
    );
    client.setConnectTimeout(10000);
    client.setReceiveTimeout(30000);

    // 通过 ping 验证连通性与鉴权。
    try {
      await client.ping();
      debugPrint('[WebDav] connect 成功');
    } catch (e) {
      debugPrint('[WebDav] connect 失败: $e');
      throw ArgumentError('WebDAV 连接失败：$e\n请检查地址、用户名与密码');
    }
    return WebDavService._(client);
  }

  static String _normalizeUrl(String url) {
    var u = url.trim();
    if (u.isEmpty) throw ArgumentError('WebDAV 地址不能为空');
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  /// 生成备份目录（不存在则递归创建）。
  Future<void> ensureBackupDir() async {
    await _client.mkdirAll(backupDir);
  }

  /// 上传文本文件到备份目录。
  Future<void> uploadText(String name, String content) async {
    debugPrint('[WebDav] uploadText: $backupDir/$name, ${content.length} 字符');
    await ensureBackupDir();
    await _client.write('$backupDir/$name', utf8.encode(content));
  }

  /// 上传数据库字节到备份目录。
  Future<void> uploadBytes(String name, Uint8List data) async {
    debugPrint('[WebDav] uploadBytes: $backupDir/$name, ${data.length} 字节');
    await ensureBackupDir();
    await _client.write('$backupDir/$name', data);
  }

  /// 下载文件并解析为文本。
  Future<String> downloadText(String name) async {
    debugPrint('[WebDav] downloadText: $backupDir/$name');
    final bytes = await _client.read('$backupDir/$name');
    return utf8.decode(bytes);
  }

  /// 下载文件字节。
  Future<List<int>> downloadBytes(String name) {
    debugPrint('[WebDav] downloadBytes: $backupDir/$name');
    return _client.read('$backupDir/$name');
  }

  /// 备份目录中的文件列表。
  Future<List<String>> listBackups() async {
    try {
      final files = await _client.readDir(backupDir);
      final names = files
          .map((f) => f.name)
          .whereType<String>()
          .where((n) => n != backupDir)
          .toList();
      debugPrint('[WebDav] listBackups: ${names.length} 个');
      return names;
    } catch (e) {
      debugPrint('[WebDav] listBackups 失败: $e');
      return <String>[];
    }
  }

  /// 下载指定备份文件到本地路径。
  Future<void> downloadToFile(String name, String savePath) {
    debugPrint('[WebDav] downloadToFile: $backupDir/$name -> $savePath');
    return _client.read2File('$backupDir/$name', savePath);
  }

  /// 删除指定备份文件。
  Future<void> delete(String name) {
    debugPrint('[WebDav] delete: $backupDir/$name');
    return _client.remove('$backupDir/$name');
  }

  void close() {
    _client.c.close(force: true);
  }
}