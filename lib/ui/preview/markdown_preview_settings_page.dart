import 'package:flutter/material.dart';

import '../../services/settings_service.dart';
import 'markdown_helper_page.dart';

/// Markdown 预览设置页。
///
/// 对应原 Android 端的「Markdown 预览设置」：
/// 是否解析内嵌 HTML，以及进入「Markdown 助手」语法速查。
class MarkdownPreviewSettingsPage extends StatefulWidget {
  const MarkdownPreviewSettingsPage({super.key});

  @override
  State<MarkdownPreviewSettingsPage> createState() =>
      _MarkdownPreviewSettingsPageState();
}

class _MarkdownPreviewSettingsPageState extends State<MarkdownPreviewSettingsPage> {
  SettingsService? _settings;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await SettingsService.instance;
    if (!mounted) return;
    setState(() => _settings = s);
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Markdown 预览设置')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.code),
                  title: const Text('解析内嵌 HTML'),
                  subtitle: const Text('预览时渲染正文中的 HTML 标签'),
                  value: s.markdownParseHtml,
                  onChanged: (v) {
                    s.setMarkdownParseHtml(v);
                    setState(() {});
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: const Text('Markdown 助手'),
                  subtitle: const Text('常用 Markdown 语法速查'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MarkdownHelperPage(),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
