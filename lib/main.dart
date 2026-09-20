import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'plugins/builtin_plugins.dart';
import 'plugins/plugin_manager.dart';
import 'services/backup_service.dart';
import 'state/note_provider.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'ui/home/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 启动周期自动备份（应用运行期间）。
  AutoBackupService.instance.start();
  // 初始化插件系统：注册宿主能力 + 注册内置插件（笔记 / 文件系统）。
  registerBuiltinCapabilities();
  await PluginManager.instance.init();
  PluginManager.instance
    ..registerBuiltin(builtinNotesPlugin())
    ..registerBuiltin(builtinFileBrowserPlugin());
  // 启动时从持久化设置恢复主题模式，保证全局主题与用户选择一致。
  final themeController = await ThemeController.load();
  runApp(NotePadApp(themeController: themeController));
}

class NotePadApp extends StatelessWidget {
  const NotePadApp({super.key, required this.themeController});

  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeController),
        ChangeNotifierProvider(create: (_) => NoteProvider()),
      ],
      child: const _Root(),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController>();
    return MaterialApp(
      title: 'NotePad',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeController.themeMode,
      home: const HomePage(),
    );
  }
}