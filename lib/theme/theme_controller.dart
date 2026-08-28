import 'package:flutter/material.dart';

import '../services/settings_service.dart';

/// 全局主题控制器：负责持有当前主题模式并通知界面重建。
class ThemeController extends ChangeNotifier {
  ThemeController([ThemeModeOption initial = ThemeModeOption.system])
      : _mode = initial;

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