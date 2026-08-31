import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notepad/services/settings_service.dart';
import 'package:notepad/theme/theme_controller.dart';

void main() {
  test('ThemeController 默认跟随系统', () {
    final controller = ThemeController();
    expect(controller.mode, ThemeModeOption.system);
  });

  test('ThemeController 切换浅色 / 深色', () {
    final controller = ThemeController();
    controller.setMode(ThemeModeOption.dark);
    expect(controller.mode, ThemeModeOption.dark);
    expect(controller.themeMode, ThemeMode.dark);
  });
}