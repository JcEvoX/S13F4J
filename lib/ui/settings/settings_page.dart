import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/settings_service.dart';
import '../../theme/theme_controller.dart';
import '../about/about_page.dart';

/// 设置主页面。
///
/// 含主题模式、编辑器字号、启动页、自动缩进、字数统计等偏好项。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
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
      appBar: AppBar(title: const Text('设置')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _section('显示与主题'),
                _buildThemeMode(s),
                ListTile(
                  leading: const Icon(Icons.font_download_outlined),
                  title: const Text('编辑器字体与大小'),
                  onTap: () => _toast('字体设置（可在编辑器内调整字号）'),
                ),
                ListTile(
                  leading: const Icon(Icons.wallpaper),
                  title: const Text('壁纸'),
                  trailing: Switch(
                    value: s.wallpaper != null,
                    onChanged: (v) {
                      s.setWallpaper(v ? 'builtin' : null);
                      setState(() {});
                    },
                  ),
                  onTap: () => _toast('壁纸设置（示例）'),
                ),
                const Divider(),
                _section('编辑'),
                SwitchListTile(
                  secondary: const Icon(Icons.format_size),
                  title: const Text('缩放编辑器字号'),
                  value: s.scaleEditorFont,
                  onChanged: (v) {
                    s.setScaleEditorFont(v);
                    setState(() {});
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.format_indent_increase),
                  title: const Text('自动首行缩进'),
                  value: s.autoFirstLineIndent,
                  onChanged: (v) {
                    s.setAutoFirstLineIndent(v);
                    setState(() {});
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.numbers),
                  title: const Text('实时字数统计'),
                  value: s.showWordCount,
                  onChanged: (v) {
                    s.setShowWordCount(v);
                    setState(() {});
                  },
                ),
                const Divider(),
                _section('启动'),
                ListTile(
                  leading: const Icon(Icons.launch),
                  title: const Text('启动后页面'),
                  subtitle: Text(s.startPage == StartPage.home ? '文档列表' : '编辑器'),
                  onTap: () => _pickStartPage(s),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('关于'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AboutPage()),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );

  Widget _buildThemeMode(SettingsService s) {
    final map = {
      ThemeModeOption.system: '跟随系统',
      ThemeModeOption.light: '浅色模式',
      ThemeModeOption.dark: '深色模式',
    };
    return ListTile(
      leading: const Icon(Icons.brightness_6),
      title: const Text('主题模式'),
      subtitle: Text(map[s.themeMode]!),
      onTap: () async {
        final selected = await showModalBottomSheet<ThemeModeOption>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final e in ThemeModeOption.values)
                  ListTile(
                    title: Text(map[e]!),
                    trailing: e == s.themeMode ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.pop(ctx, e),
                  ),
              ],
            ),
          ),
        );
        if (selected != null) {
          await s.setThemeMode(selected);
          // 通知全局 ThemeController 切换主题。
          if (!mounted) return;
          context.read<ThemeController>().setMode(selected);
        }
      },
    );
  }

  Future<void> _pickStartPage(SettingsService s) async {
    final selected = await showModalBottomSheet<StartPage>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('文档列表'),
              trailing: s.startPage == StartPage.home ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, StartPage.home),
            ),
            ListTile(
              title: const Text('编辑器'),
              trailing: s.startPage == StartPage.editor ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, StartPage.editor),
            ),
          ],
        ),
      ),
    );
    if (selected != null) {
      await s.setStartPage(selected);
      if (mounted) setState(() {});
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}