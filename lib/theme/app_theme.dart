import 'package:flutter/material.dart';

import '../services/settings_service.dart';

/// 提供了 NotePad 风格的统一配色与亮/暗两套主题。
///
/// 颜色取材灵感来自简洁、温润、以纸色与墨色为主的观感。
class AppTheme {
  /// 品牌主色调（暖橙色）。
  static const Color primary = Color(0xFFE8853D);

  /// 亮色背景（纸色）。
  static const Color lightPaper = Color(0xFFFAF6F0);

  /// 暗色背景。
  static const Color darkPaper = Color(0xFF1C1C1C);

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.light,
        surface: lightPaper,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: lightPaper,
      appBarTheme: const AppBarTheme(
        backgroundColor: lightPaper,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        foregroundColor: Colors.black87,
        centerTitle: false,
      ),
    );
  }

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.dark,
        surface: darkPaper,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: darkPaper,
      appBarTheme: const AppBarTheme(
        backgroundColor: darkPaper,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
      ),
    );
  }

  /// 从设置解析主题模式选项。
  static ThemeMode toThemeMode(ThemeModeOption option) {
    switch (option) {
      case ThemeModeOption.system:
        return ThemeMode.system;
      case ThemeModeOption.light:
        return ThemeMode.light;
      case ThemeModeOption.dark:
        return ThemeMode.dark;
    }
  }
}