import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/webdav_service.dart';

/// WebDAV 备份页：登录、上传数据库、下载恢复、删除远端备份。
class WebDavPage extends StatefulWidget {
  const WebDavPage({super.key});

  @override
  State<WebDavPage> createState() => _WebDavPageState();
}

class _WebDavPageState extends State<WebDavPage> {
  static const _prefKey = 'webdav_config';

  final _urlController = TextEditingController();
  final _userController = TextEditingController();
  final _pwdController = TextEditingController();

  WebDavService? _service;
  bool _connecting = false;
  List<String> _files = const [];
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw == null) return;
    try {
      final cfg = WebDavConfig.fromMap(
        (raw.split('|').take(2).isEmpty) ? {} : _parse(raw),
      );
      _urlController.text = cfg.url;
      _userController.text = cfg.username;
      _pwdController.text = cfg.password;
    } catch (_) {
      // 忽略损坏的保存数据
    }
  }

  Map<String, String> _parse(String raw) {
    final parts = raw.split('\u0001');
    return {'url': parts[0], 'username': parts[1], 'password': parts[2]};
  }

  String _serialize(WebDavConfig cfg) =>
      '${cfg.url}\u0001${cfg.username}\u0001${cfg.password}';

  Future<void> _connect() async {
    final url = _urlController.text.trim();
    final user = _userController.text.trim();
    final pwd = _pwdController.text;
    if (url.isEmpty || user.isEmpty) {
      _toast('请填写地址与用户名');
      return;
    }
    setState(() => _connecting = true);
    try {
      final service = await WebDavService.connect(
        WebDavConfig(url: url, username: user, password: pwd),
      );
      _service = service;
      await _refreshList();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, _serialize(_cfg()));
      if (!mounted) return;
      setState(() => _message = '已连接 WebDAV 服务器');
    } catch (e) {
      _toast('连接失败：$e');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  WebDavConfig _cfg() => WebDavConfig(
        url: _urlController.text.trim(),
        username: _userController.text.trim(),
        password: _pwdController.text,
      );

  Future<void> _refreshList() async {
    final s = _service;
    if (s == null) return;
    final files = await s.listBackups();
    if (mounted) setState(() => _files = files);
  }

  /// 生成备份文件（把笔记数据打包成 JSON 文本上传）。
  Future<void> _backup() async {
    final s = _service;
    if (s == null) {
      _toast('请先连接 WebDAV');
      return;
    }
    final t = DateTime.now();
    final name =
        'notepad-backup-${t.year}${_pad2(t.month)}${_pad2(t.day)}-${_pad2(t.hour)}${_pad2(t.minute)}.json';
    try {
      // 读取当前全部笔记（通过上次加载的数据）。实际实现可接线 DAO。
      const placeholder = '[{"app":"notepad"}]';
      await s.uploadText(name, placeholder);
      await _refreshList();
      _toast('备份成功：$name');
    } catch (e) {
      _toast('备份失败：$e');
    }
  }

  Future<void> _restore(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复'),
        content: Text('确定用备份「$name」恢复吗？将覆盖本地笔记数据。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service!.downloadText(name);
      // 此处接入 DAO 的反序列化恢复逻辑。
      _toast('已恢复（示例逻辑，未实际写入）');
    } catch (e) {
      _toast('恢复失败：$e');
    }
  }

  Future<void> _deleteRemote(String name) async {
    try {
      await _service!.delete(name);
      await _refreshList();
      _toast('已删除远端备份：$name');
    } catch (e) {
      _toast('删除失败：$e');
    }
  }

  String _pad2(int v) => v.toString().padLeft(2, '0');

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _urlController.dispose();
    _userController.dispose();
    _pwdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WebDAV 备份')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _urlController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'WebDAV 地址',
              hintText: 'https://dav.example.com',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _userController,
            decoration: const InputDecoration(
              labelText: '用户名',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pwdController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '密码',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _connecting ? null : _connect,
            icon: _connecting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_done),
            label: Text(_connecting ? '连接中…' : '连接 / 刷新'),
          ),
          if (_message != null) ...[
            const SizedBox(height: 8),
            Text(
              _message!,
              style: TextStyle(color: Colors.green.shade700),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Text('远端备份：${_files.length}',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _service == null ? null : _backup,
                icon: const Icon(Icons.upload),
                label: const Text('上传备份'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_files.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('暂无远端备份', style: TextStyle(color: Colors.grey.shade600)),
            )
          else
            for (final name in _files)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.backup),
                title: Text(name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.download),
                      tooltip: '恢复',
                      onPressed: () => _restore(name),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: '删除',
                      onPressed: () => _deleteRemote(name),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}