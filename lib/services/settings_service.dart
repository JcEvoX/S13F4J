import 'package:shared_preferences/shared_preferences.dart';

/// 主题模式：跟随系统 / 浅色 / 深色。
enum ThemeModeOption { system, light, dark }

/// 启动后页面：文档列表 / 编辑器。
enum StartPage { home, editor }

/// 应用设置服务。
///
/// 对应原 Android 端基于 MMKV 的键值存储（`key_default_language`、
/// `salt_note_folder_uri` 等），跨平台统一使用 shared_preferences 实现，
/// Android / iOS / 桌面端行为一致。
class SettingsService {
  SettingsService._(this._prefs);

  final SharedPreferences _prefs;

  static const _kThemeMode = 'pref_theme_mode';
  static const _kEditorFontSize = 'pref_editor_font_size';
  static const _kScaleEditorFont = 'pref_editor_scale_font';
  static const _kAutoFirstLineIndent = 'pref_auto_first_line_indent';
  static const _kStartPage = 'pref_start_page';
  static const _kWallpaper = 'pref_wallpaper_path';
  static const _kBackupFolder = 'pref_backup_folder_path';
  static const _kWordCount = 'pref_show_word_count';

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

  bool get showWordCount => _prefs.getBool(_kWordCount) ?? true;

  Future<void> setShowWordCount(bool v) => _prefs.setBool(_kWordCount, v);
}