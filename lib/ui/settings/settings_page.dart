import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/settings_service.dart';
import '../../theme/theme_controller.dart';
import '../../theme/wallpapers.dart';
import '../about/about_page.dart';
import '../backuprestore/backup_restore_page.dart';
import '../preview/markdown_preview_settings_page.dart';
import '../plugins/plugin_center_page.dart';
import '../recent/recent_page.dart';
import '../statistics/statistics_page.dart';
import '../theme/editor_font_page.dart';
import '../theme/wallpaper_page.dart';
import '../webdav/webdav_page.dart';

/// 设置主页面。
///
/// 还原原版 SettingsActivity 的分组圆角卡片风格：
/// - 每组分标题（13sp 加粗主题色）+ 一个圆角白色卡片（RoundedView）
/// - 卡片内为若干条目（ItemView）：图标 + 标题/副标题 + 分隔线
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
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _section('显示与主题'),
                _group([
                  _buildThemeMode(s),
                  _item(
                    icon: Icons.font_download_outlined,
                    title: '编辑器字体',
                    subtitle: '${s.editorFontSize.round()} 号',
                    onTap: () => _push(const EditorFontPage()),
                  ),
                  _item(
                    icon: Icons.wallpaper,
                    title: '壁纸',
                    subtitle: wallpaperByKey(s.wallpaper)?.title ?? '跟随系统',
                    onTap: () => _push(const WallpaperPage()),
                  ),
                ]),
                _section('数据'),
                _group([
                  _item(
                    icon: Icons.insert_chart_outlined,
                    title: '统计',
                    onTap: () => _push(const StatisticsPage()),
                  ),
                  _item(
                    icon: Icons.history,
                    title: '最近编辑的文章',
                    onTap: () => _push(const RecentPage()),
                  ),
                  _item(
                    icon: Icons.backup_outlined,
                    title: '备份和恢复',
                    subtitle: s.autoBackupLocal || s.autoBackupToWebdav
                        ? '自动备份已开启'
                        : '未开启自动备份',
                    onTap: () => _push(const BackupRestorePage()),
                  ),
                  _item(
                    icon: Icons.cloud_outlined,
                    title: '我的 WebDAV',
                    onTap: () => _push(const WebDavPage()),
                  ),
                ]),
                _section('编辑'),
                _group([
                  _switchItem(
                    icon: Icons.format_size,
                    title: '缩放编辑器字号',
                    value: s.scaleEditorFont,
                    onChanged: (v) {
                      s.setScaleEditorFont(v);
                      setState(() {});
                    },
                  ),
                  _switchItem(
                    icon: Icons.format_indent_increase,
                    title: '自动首行缩进',
                    value: s.autoFirstLineIndent,
                    onChanged: (v) {
                      s.setAutoFirstLineIndent(v);
                      setState(() {});
                    },
                  ),
                  _switchItem(
                    icon: Icons.numbers,
                    title: '实时字数统计',
                    value: s.showWordCount,
                    onChanged: (v) {
                      s.setShowWordCount(v);
                      setState(() {});
                    },
                  ),
                  _item(
                    icon: Icons.preview_outlined,
                    title: 'Markdown 预览设置',
                    onTap: () => _push(const MarkdownPreviewSettingsPage()),
                  ),
                ]),
                _section('启动'),
                _group([
                  _item(
                    icon: Icons.launch,
                    title: '启动后页面',
                    subtitle: s.startPage == StartPage.home ? '文档列表' : '编辑器',
                    onTap: () => _pickStartPage(s),
                  ),
                ]),
                _section('插件'),
                _group([
                  _switchItem(
                    icon: Icons.extension,
                    title: '启用插件系统',
                    value: s.enablePluginSystem,
                    onChanged: (v) {
                      s.setEnablePluginSystem(v);
                      setState(() {});
                    },
                  ),
                  if (s.enablePluginSystem)
                    _item(
                      icon: Icons.widgets_outlined,
                      title: '插件中心',
                      subtitle: '管理插件与插件市场',
                      onTap: () => _push(const PluginCenterPage()),
                    ),
                ]),
                _group([
                  _item(
                    icon: Icons.info_outline,
                    title: '关于',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AboutPage()),
                    ),
                  ),
                ]),
              ],
            ),
    );
  }

  /// 分标题（原版「显示与主题」等分组标题）。
  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );

  /// 圆角分组卡片（原版 RoundedView）。
  Widget _group(List<Widget> items) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0x14FFFFFF) : const Color(0x80FFFFFF),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) _divider(),
            items[i],
          ],
        ],
      ),
    );
  }

  /// 条目间分隔线（原版 ItemView 之间的 1dip 灰线）。
  Widget _divider() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Divider(
      height: 1,
      thickness: 1,
      indent: 56,
      endIndent: 12,
      color: isDark ? Colors.white12 : Colors.black12,
    );
  }

  /// 可点击条目（原版 ItemView：图标 + 标题/副标题 + 右侧箭头）。
  Widget _item({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : const Color(0xFF191B23);
    final dim = isDark ? Colors.white54 : const Color(0xFF8B8C90);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 22, color: scheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      color: titleColor,
                    ),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 11, color: dim),
                    ),
                  ],
                ],
              ),
            ),
            trailing ??
                Icon(Icons.chevron_right, size: 20, color: dim),
          ],
        ),
      ),
    );
  }

  /// 开关条目（原版 ItemView + Switch）。
  Widget _switchItem({
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 22, color: scheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white : const Color(0xFF191B23),
                ),
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }

  void _push(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  Widget _buildThemeMode(SettingsService s) {
    final map = {
      ThemeModeOption.system: '跟随系统',
      ThemeModeOption.light: '浅色模式',
      ThemeModeOption.dark: '深色模式',
    };
    return _item(
      icon: Icons.brightness_6,
      title: '主题模式',
      subtitle: map[s.themeMode],
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
          setState(() {});
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
