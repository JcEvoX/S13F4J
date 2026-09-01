import 'package:flutter/material.dart';

import '../services/settings_service.dart';

/// 全局主题控制器：负责持有当前主题模式并通知界面重建。
class ThemeController extends ChangeNotifier {
  ThemeController([ThemeModeOption initial = ThemeModeOption.system])
      : _mode = initial;

  /// 从持久化设置恢复主题模式，保证启动后全局主题与用户选择一致。
  static Future<ThemeController> load() async {
    final settings = await SettingsService.instance;
    return ThemeController(settings.themeMode);
  }

  ThemeModeOption _mode;
  ThemeModeOption get mode => _mode;

  void setMode(ThemeModeOption option) {
    _mode = option;
    notifyListeners();
  }

  ThemeMode get themeMode => switch (_mode) {
        ThemeModeOption.system => ThemeMode.system,
        ThemeModeOption.light => ThemeMode.light,
        ThemeModeOption.dark => ThemeMode.dark,
      };
}