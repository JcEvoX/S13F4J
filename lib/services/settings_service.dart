import 'package:shared_preferences/shared_preferences.dart';

/// 主题模式：跟随系统 / 浅色 / 深色。
enum ThemeModeOption { system, light, dark }

/// 启动后页面：文档列表 / 编辑器。
enum StartPage { home, editor }

/// 应用设置服务。
///
/// 对应原 Android 端基于 MMKV 的键值存储（如 `key_default_language`、
/// `pref_backup_folder_path` 等），跨平台统一使用 shared_preferences 实现，
/// Android / iOS / 桌面端行为一致。
class SettingsService {
  SettingsService._(this._prefs);

  final SharedPreferences _prefs;

  static const _kThemeMode = 'pref_theme_mode';
  static const _kEditorFontSize = 'pref_editor_font_size';
  static const _kEditorFontFamily = 'pref_editor_font_family';
  static const _kScaleEditorFont = 'pref_editor_scale_font';
  static const _kAutoFirstLineIndent = 'pref_auto_first_line_indent';
  static const _kStartPage = 'pref_start_page';
  static const _kWallpaper = 'pref_wallpaper_path';
  static const _kBackupFolder = 'pref_backup_folder_path';
  static const _kBackupFolderName = 'pref_backup_folder_name';
  static const _kAutoBackupLocal = 'pref_auto_backup_local';
  static const _kAutoBackupWebdav = 'pref_auto_backup_to_webdav';
  static const _kMarkdownParseHtml = 'pref_markdown_parse_html';
  static const _kMathJax = 'mathjax';
  static const _kMermaid = 'mermaid';
  static const _kWordCount = 'pref_show_word_count';
  static const _kEnablePluginSystem = 'pref_enable_plugin_system';
  static const _kPluginSource = 'pref_plugin_source';

  static SettingsService? _instance;

  static Future<SettingsService> get instance async {
    if (_instance != null) return _instance!;
    final prefs = await SharedPreferences.getInstance();
    _instance = SettingsService._(prefs);
    return _instance!;
  }

  ThemeModeOption get themeMode {
    final v = _prefs.getString(_kThemeMode) ?? 'system';
    return ThemeModeOption.values.firstWhere(
      (e) => e.name == v,
      orElse: () => ThemeModeOption.system,
    );
  }

  Future<void> setThemeMode(ThemeModeOption mode) =>
      _prefs.setString(_kThemeMode, mode.name);

  double get editorFontSize => _prefs.getDouble(_kEditorFontSize) ?? 17.0;

  Future<void> setEditorFontSize(double v) =>
      _prefs.setDouble(_kEditorFontSize, v);

  /// 编辑器字体族（'system' 表示跟随系统）。
  String get editorFontFamily => _prefs.getString(_kEditorFontFamily) ?? 'system';

  Future<void> setEditorFontFamily(String v) =>
      _prefs.setString(_kEditorFontFamily, v);

  Future<void> resetEditorFont() async {
    await setEditorFontFamily('system');
    await setEditorFontSize(17.0);
  }

  bool get scaleEditorFont => _prefs.getBool(_kScaleEditorFont) ?? true;

  Future<void> setScaleEditorFont(bool v) =>
      _prefs.setBool(_kScaleEditorFont, v);

  bool get autoFirstLineIndent => _prefs.getBool(_kAutoFirstLineIndent) ?? false;

  Future<void> setAutoFirstLineIndent(bool v) =>
      _prefs.setBool(_kAutoFirstLineIndent, v);

  StartPage get startPage {
    final v = _prefs.getString(_kStartPage) ?? 'home';
    return StartPage.values.firstWhere(
      (e) => e.name == v,
      orElse: () => StartPage.home,
    );
  }

  Future<void> setStartPage(StartPage v) => _prefs.setString(_kStartPage, v.name);

  String? get wallpaper => _prefs.getString(_kWallpaper);

  Future<void> setWallpaper(String? path) {
    if (path == null) return _prefs.remove(_kWallpaper);
    return _prefs.setString(_kWallpaper, path);
  }

  String? get backupFolder => _prefs.getString(_kBackupFolder);

  Future<void> setBackupFolder(String? path) {
    if (path == null) return _prefs.remove(_kBackupFolder);
    return _prefs.setString(_kBackupFolder, path);
  }

  /// 备份文件夹显示名（用户选择的目录名，便于界面展示）。
  String? get backupFolderName => _prefs.getString(_kBackupFolderName);

  Future<void> setBackupFolderName(String? name) {
    if (name == null) return _prefs.remove(_kBackupFolderName);
    return _prefs.setString(_kBackupFolderName, name);
  }

  /// 自动备份到本地文件夹。
  bool get autoBackupLocal => _prefs.getBool(_kAutoBackupLocal) ?? false;

  Future<void> setAutoBackupLocal(bool v) =>
      _prefs.setBool(_kAutoBackupLocal, v);

  /// 自动备份到 WebDAV。
  bool get autoBackupToWebdav => _prefs.getBool(_kAutoBackupWebdav) ?? true;

  Future<void> setAutoBackupToWebdav(bool v) =>
      _prefs.setBool(_kAutoBackupWebdav, v);

  /// Markdown 预览是否解析内嵌 HTML。
  bool get markdownParseHtml => _prefs.getBool(_kMarkdownParseHtml) ?? true;

  Future<void> setMarkdownParseHtml(bool v) =>
      _prefs.setBool(_kMarkdownParseHtml, v);

  /// 预览是否渲染 MathJax 数学公式（对应原 Pro 功能 `mathjax`）。
  bool get mathJax => _prefs.getBool(_kMathJax) ?? false;

  Future<void> setMathJax(bool v) => _prefs.setBool(_kMathJax, v);

  /// 预览是否渲染 Mermaid 流程图（对应原 Pro 功能 `mermaid`）。
  bool get mermaid => _prefs.getBool(_kMermaid) ?? false;

  Future<void> setMermaid(bool v) => _prefs.setBool(_kMermaid, v);

  bool get showWordCount => _prefs.getBool(_kWordCount) ?? true;

  Future<void> setShowWordCount(bool v) => _prefs.setBool(_kWordCount, v);

  /// 插件系统总开关。默认关闭：界面不显示插件入口；
  /// 开启后在设置中显示「插件中心」，可热插拔插件。
  bool get enablePluginSystem => _prefs.getBool(_kEnablePluginSystem) ?? false;

  Future<void> setEnablePluginSystem(bool v) =>
      _prefs.setBool(_kEnablePluginSystem, v);

  /// 插件市场源（GitHub 插件仓库 owner/repo）。
  String get pluginSource =>
      _prefs.getString(_kPluginSource) ?? 'JcEvoX/S13F4J-plugins';

  Future<void> setPluginSource(String v) => _prefs.setString(_kPluginSource, v);
}