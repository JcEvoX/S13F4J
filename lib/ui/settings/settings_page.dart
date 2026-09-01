import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/settings_service.dart';
import '../../theme/theme_controller.dart';
import '../../theme/wallpapers.dart';
import '../about/about_page.dart';
import '../backuprestore/backup_restore_page.dart';
import '../preview/markdown_preview_settings_page.dart';
import '../recent/recent_page.dart';
import '../statistics/statistics_page.dart';
import '../theme/editor_font_page.dart';
import '../theme/wallpaper_page.dart';
import '../webdav/webdav_page.dart';

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
                  title: const Text('编辑器字体'),
                  subtitle: Text('${s.editorFontSize.round()} 号'),
                  onTap: () => _push(const EditorFontPage()),
                ),
                ListTile(
                  leading: const Icon(Icons.wallpaper),
                  title: const Text('壁纸'),
                  subtitle: Text(
                    wallpaperByKey(s.wallpaper)?.title ?? '跟随系统',
                  ),
                  onTap: () => _push(const WallpaperPage()),
                ),
                const Divider(),
                _section('数据'),
                ListTile(
                  leading: const Icon(Icons.insert_chart_outlined),
                  title: const Text('统计'),
                  onTap: () => _push(const StatisticsPage()),
                ),
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('最近编辑的文章'),
                  onTap: () => _push(const RecentPage()),
                ),
                ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('备份和恢复'),
                  subtitle: Text(
                    s.autoBackupLocal || s.autoBackupToWebdav
                        ? '自动备份已开启'
                        : '未开启自动备份',
                  ),
                  onTap: () => _push(const BackupRestorePage()),
                ),
                ListTile(
                  leading: const Icon(Icons.cloud_outlined),
                  title: const Text('我的 WebDAV'),
                  onTap: () => _push(const WebDavPage()),
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
                ListTile(
                  leading: const Icon(Icons.preview_outlined),
                  title: const Text('Markdown 预览设置'),
                  onTap: () => _push(const MarkdownPreviewSettingsPage()),
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

  void _push(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

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
}